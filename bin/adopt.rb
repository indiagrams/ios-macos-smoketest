#!/usr/bin/env ruby
# frozen_string_literal: true

# bin/adopt.rb — `make adopt` driver
#
# Pulls metadata + screenshots from a live ASC App record into the local
# fastlane/ tree. Use on forks adopting an app that's already in the App Store
# BEFORE running `make submit`, which would otherwise upload local placeholder
# metadata and clobber the live App Store listing.
#
# This driver does the preflight checks that don't belong inside fastlane:
#   1. .bootstrap.env exists and is loadable
#   2. BUNDLE_ID is not the template placeholder
#   3. No uncommitted changes in fastlane/metadata or fastlane/screenshots
#      (since the download will overwrite — protect work in flight)
#
# Then exec()s fastlane's adopt_existing_app lane.
#
# Idempotent — re-running re-syncs from ASC. Existing local files overwritten.
#
# Exit-code contract, in bin/preflight-identity.rb's shape. It is documented
# because this driver's failure mode is a network call against production state,
# and a caller has to be able to tell "I do not understand you" apart from "this
# fork is not ready to adopt":
#
#   Exit | Meaning                                        | Message must name
#   -----+------------------------------------------------+---------------------------------
#   0    | -h / --help printed usage; or --dry-run        | — (usage; or the resolved app
#        | reported the target and stopped; or the lane   |     name, bundle id and team)
#        | ran and fastlane itself exited 0               |
#   1    | a preflight refused: .bootstrap.env missing;   | the missing file; every missing
#        | a required variable missing or empty; the      | variable by name; or the
#        | bundle id still the template placeholder; or   | uncommitted paths, first 15
#        | the two fastlane trees below carry uncommitted |
#        | changes (FORCE=true overrides that last one)   |
#   2    | unknown or malformed argv                      | the offending argument, verbatim
#
# Exit 2 is deliberately distinct from exit 1, and an unrecognised argument is
# REFUSED rather than ignored. Until 2026-09-04 this file parsed no arguments at
# all, so `bin/adopt.rb --help` — the thing a reader reaches for first — was
# silently a live App Store Connect call. On 2026-09-03 it was one: a usage probe
# overwrote 13 tracked files under fastlane/metadata/ and created 10 more. An
# ignored flag is how that happened, so nothing here falls through to the lane.
#
# Usage:
#   bundle exec ruby bin/adopt.rb              # adopt — contacts ASC, overwrites local metadata
#   bundle exec ruby bin/adopt.rb --dry-run    # report what WOULD be adopted; contacts nothing
#   bundle exec ruby bin/adopt.rb --help       # print usage; -h is an alias
#   FORCE=true make adopt                      # re-sync over uncommitted local edits
#
# test/adopt_argv_test.rb is the durable guard for the three refusals above, and
# it observes this file by RUNNING a copy of it in a temp directory with a
# capturing `bundle` shim first on PATH — reaching that shim is its failure
# condition. It never runs this script in place, and neither should you.

require "pathname"

REPO_ROOT = Pathname.new(File.expand_path("..", __dir__))

def fail!(msg)
  warn "[adopt] #{msg}"
  exit 1
end

# The usage text, printed by -h / --help and quoted back on a refusal. It names
# what the command DOES before it lists flags, because the reader most likely to
# type --help is the one who does not yet know this contacts Apple and
# overwrites files.
USAGE = <<~TEXT
  bin/adopt.rb — adopt an app that is already in the App Store.

  Contacts App Store Connect and downloads that app's live metadata and
  screenshots into this repository, OVERWRITING:

      fastlane/metadata/
      fastlane/screenshots/

  Run it on a fork adopting an existing App Store app BEFORE `make submit`,
  which would otherwise upload local placeholder metadata over the live listing.
  Identity comes from .bootstrap.env — APP_NAME, BUNDLE_ID, FASTLANE_TEAM_ID,
  ASC_API_KEY_ID and ASC_API_KEY_ISSUER_ID — and an environment variable wins
  over the file.

  Usage:
    bundle exec ruby bin/adopt.rb             adopt — contacts App Store Connect
    bundle exec ruby bin/adopt.rb --dry-run   report what would be adopted, contact nothing
    bundle exec ruby bin/adopt.rb --help      print this usage (-h is an alias)

  Environment:
    FORCE=true                         re-sync over uncommitted changes in the two paths above
    SKIP_METADATA / SKIP_SCREENSHOTS   passed through to the fastlane lane

  Exit codes: 0 usage, a dry run, or a completed adoption; 1 a preflight refused;
  2 an argument this script does not understand.
TEXT

# Parsed BEFORE the .bootstrap.env read and before anything that could open a
# connection. An unrecognised argument — flag-shaped or not — is refused by name
# and never ignored, because ignoring one is exactly how a usage probe became a
# live production call.
dry_run = false
ARGV.each do |arg|
  case arg
  when "-h", "--help"
    puts USAGE
    exit 0
  when "--dry-run"
    dry_run = true
  else
    warn "[adopt] Unrecognised argument: #{arg}"
    warn "[adopt] Nothing was contacted and nothing was written."
    warn ""
    warn USAGE
    exit 2
  end
end

# Read .bootstrap.env (per-fork). Kept inline (not requiring a shared lib) so
# this driver doesn't need arbitrary load-path setup; the Makefile invokes it
# via `bundle exec ruby`.
#
# This comment used to say "same parser as Fastfile's _fork_config". Measured
# 2026-09-04: fastlane/Fastfile contains zero occurrences of that name -- 04-04
# removed it. Citing a function that no longer exists is the "inferring a fact
# from a doc" class, so the citation is deleted rather than softened. The parser
# that IS authoritative is Bootstrap::Config.parse in bin/lib/bootstrap.rb; this
# one is deliberately a second, simpler copy and the two are not kept in step.
env_path = REPO_ROOT.join(".bootstrap.env")
unless env_path.file?
  fail!(
    "Missing .bootstrap.env. Run `make init` first to scaffold it, then fill " \
    "in APP_NAME, BUNDLE_ID, FASTLANE_TEAM_ID, and ASC_API_KEY_* fields."
  )
end

config = {}
File.read(env_path, encoding: "UTF-8").each_line do |line|
  line = line.strip
  next if line.empty? || line.start_with?("#")
  k, v = line.split("=", 2)
  next unless k && v
  v = v.sub(/\s+#.*\z/, "").gsub(/\A['"]|['"]\z/, "")
  config[k.strip] = v.strip
end

# ENV wins over file when set (lets shell exports / .envrc / CI env block
# override the per-fork file for one-off invocations).
get = ->(key) { ENV[key].to_s.empty? ? config[key] : ENV[key] }

required = %w[APP_NAME BUNDLE_ID FASTLANE_TEAM_ID ASC_API_KEY_ID ASC_API_KEY_ISSUER_ID]
missing = required.reject { |k| !get.call(k).to_s.empty? }
if missing.any?
  fail!(
    "Missing required env vars: #{missing.join(', ')}.\n" \
    "Set them in .bootstrap.env, or export from your shell / .envrc.\n" \
    "See docs/BOOTSTRAP.md for the field reference."
  )
end

bundle_id = get.call("BUNDLE_ID")
if bundle_id == "com.indiagram.smokeapp"
  fail!(
    "BUNDLE_ID is the template placeholder 'com.indiagram.smokeapp'.\n" \
    "Set it to your real bundle id in .bootstrap.env first.\n" \
    "If your fork is greenfield (new app, no existing App Store app), don't " \
    "run adopt — `make doctor` + `make all` is the greenfield path."
  )
end

# Git-clean check on fastlane/metadata + fastlane/screenshots — overwriting
# would lose uncommitted work. FORCE=true skips the check (for users who
# explicitly want to re-sync over local edits).
status = `git -C "#{REPO_ROOT}" status --porcelain -- fastlane/metadata fastlane/screenshots 2>/dev/null`.strip

# --dry-run stops HERE: after identity has been resolved and validated, so the
# report names real values, and before the clean-tree gate, so it reports the
# uncommitted work rather than refusing over it. A dry run overwrites nothing, so
# there is nothing for that gate to protect. The gate below is untouched and
# still fires for every real invocation.
if dry_run
  puts "[adopt] DRY RUN — App Store Connect was NOT contacted and nothing was written."
  puts "[adopt] Would adopt: #{get.call('APP_NAME')} (#{bundle_id}) on team #{get.call('FASTLANE_TEAM_ID')}"
  puts "[adopt] Would run:   bundle exec fastlane adopt_existing_app"
  puts "[adopt] Would overwrite, from that app's live App Store record:"
  puts "  fastlane/metadata/"
  puts "  fastlane/screenshots/"
  if status.empty?
    puts "[adopt] Uncommitted changes in those paths: none."
  else
    puts "[adopt] Uncommitted changes a real run would refuse to overwrite (FORCE=true overrides):"
    status.lines.first(15).each { |l| puts "  #{l.chomp}" }
  end
  exit 0
end

if !status.empty? && ENV["FORCE"] != "true"
  warn "[adopt] Uncommitted changes detected in fastlane/metadata or fastlane/screenshots:"
  status.lines.first(15).each { |l| warn "  #{l.chomp}" }
  warn ""
  warn "[adopt] Adoption would overwrite these. Choose one:"
  warn "  • Commit:        git add fastlane/ && git commit"
  warn "  • Stash:         git stash push -- fastlane/metadata fastlane/screenshots"
  warn "  • Force-overwrite: FORCE=true make adopt"
  exit 1
end

puts "[adopt] Pulling ASC state for bundle id '#{bundle_id}' on team #{get.call('FASTLANE_TEAM_ID')}…"
puts ""

# exec replaces the current process — fastlane's exit code becomes ours.
# Pass through SKIP_METADATA / SKIP_SCREENSHOTS env vars (already in ENV;
# the lane reads them via ENV.fetch).
exec("bundle", "exec", "fastlane", "adopt_existing_app")
