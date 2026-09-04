#!/usr/bin/env ruby
# frozen_string_literal: true

# Trigger a release. Behavior depends on .bootstrap.env's RELEASE_MODE:
#
#   ci    — triggers .github/workflows/release.yml on the configured app repo,
#           then polls until completion. Idempotent:
#             - if a release run is already in progress on origin/main, tail it
#             - if origin/main HEAD already has a release tag, exit 0
#             - --force overrides both checks
#
#   local — runs `bundle exec fastlane release tag:vMARKETING+BUILD` on this
#           machine. Marketing version is read from app/project.yml or
#           app/Project.swift (whichever exists); build number is resolved
#           from ASC as `max(existing builds at this marketing version) + 1`,
#           so each ship lands as a new build under the current "Version
#           X" bucket in TestFlight (instead of inventing a new bucket per
#           ship). Signing comes from the login keychain (Apple Distribution
#           + Apple Development + 3rd Party Mac Developer Installer must be
#           present — `make doctor` verifies). No idempotency check: the
#           fastlane release lane is itself idempotent (refuses to re-tag
#           an existing tag).
#
# Usage:
#   bundle exec ruby bin/ship.rb               # ship — builds and uploads to App Store Connect
#   bundle exec ruby bin/ship.rb --dry-run     # ship through the same path with uploads skipped
#   bundle exec ruby bin/ship.rb --force       # ignore the in-progress / already-tagged checks
#   bundle exec ruby bin/ship.rb --help        # print usage; -h is an alias
#
# Exit-code contract, in bin/preflight-identity.rb's shape:
#
#   Exit | Meaning                                        | Message must name
#   -----+------------------------------------------------+---------------------------------
#   0    | -h / --help printed usage; or the release      | — (usage; or the tag and the run
#        | succeeded, was already shipped, or an          |     url)
#        | in-progress run completed successfully         |
#   1    | an invocation or I/O refusal: identity         | the missing value, the failing
#        | unresolvable, gh failed, tag not computable    | command, or the reason
#   2    | the workflow run / fastlane lane completed     | the conclusion and the run url
#        | with conclusion != success                     |
#   3    | unknown or malformed argv                      | the offending argument, verbatim
#
# WHY 3 AND NOT 2 for bad argv, which is what bin/adopt.rb uses: exit 2 already
# meant "the run concluded badly" here long before this front door existed, and
# redefining a live exit code to match a sibling would be a behaviour change
# wearing a consistency costume.
#
# WHY ARGUMENTS ARE PARSED AND NOT SNIFFED. Until 2026-09-04 this file did
# `ARGV.include?("--dry-run")` and `ARGV.include?("--force")` and nothing else.
# That is not parsing: it matches exactly or not at all, so `--help`, `--dryrun`,
# `--dry_run`, `--DRY-RUN` and every other near miss fell through as dry_run =
# "false" and shipped for real — from an operator who had just typed the flag
# whose entire purpose is to make the run harmless. The script had a dry-run mode
# and no way to discover it, which is worse than having none: the reader who
# types --help to find the flag triggers the thing the flag exists to prevent.
# Guessing which flag was meant is how a typo becomes a release, so an
# unrecognised argument is refused by name instead.
#
# --dry-run and --force keep their exact spellings and their exact meanings. The
# defect was never that these two were wrong; it was that everything else was
# ignored.
#
# test/driver_argv_test.rb is the durable guard, and it observes this file by
# RUNNING a copy of it in a temp directory with capturing `bundle`, `fastlane`
# and `gh` shims first on PATH. It never runs this script in place, and neither
# should you.

require "json"
require_relative "lib/bootstrap"

# ─── Front door: parsed BEFORE the config read and before any `gh` call. ─────
# Flag-shaped or not, an unrecognised argument is refused BY NAME: a parser that
# inspected only tokens beginning with a dash would ignore a bare positional and
# fall straight through to the dispatch.
SHIP_USAGE = <<~TEXT
  bin/ship.rb — ship a release.

  THIS COMMAND SHIPS. Depending on .bootstrap.env's RELEASE_MODE it either
  dispatches .github/workflows/release.yml on the configured app repository and
  tails it, or runs `fastlane release` on this machine. Either way it tags, it
  builds, and it uploads binaries to App Store Connect.

  Usage:
    bundle exec ruby bin/ship.rb              ship for real
    bundle exec ruby bin/ship.rb --dry-run    ship through the same path with the
                                              upload skipped (ci: dry_run=true is
                                              passed to release.yml; local:
                                              skip_upload:true is passed to the lane).
                                              It is a REAL run of the pipeline, not a
                                              report — it just does not upload.
    bundle exec ruby bin/ship.rb --force      ignore the "a release run is already in
                                              progress" and "HEAD is already tagged"
                                              checks and ship anyway
    bundle exec ruby bin/ship.rb --help       print this usage (-h is an alias)

  Flags may be combined. Anything else is refused: near misses of --dry-run
  (--dryrun, --dry_run, --DRY-RUN) used to be ignored, which turned a typo into
  a real ship.

  Exit codes: 0 usage or a successful release; 1 an invocation or I/O refusal;
  2 the run or lane concluded unsuccessfully; 3 an argument this script does not
  understand.
TEXT

dry_run_requested = false
force = false
ARGV.each do |arg|
  case arg
  when "-h", "--help"
    puts SHIP_USAGE
    exit 0
  when "--dry-run"
    dry_run_requested = true
  when "--force"
    force = true
  else
    warn "[ship] Unrecognised argument: #{arg}"
    warn "[ship] Nothing was tagged, built, dispatched or uploaded."
    warn ""
    warn SHIP_USAGE
    exit 3
  end
end

config  = Bootstrap::Config.load!
config.validate!

# Identity comes from app/Identity.xcconfig, the source of truth (A-01), and
# no longer from .bootstrap.env, which does not carry it. Resolved ONCE, here,
# so the preflight banner and the release tag cannot disagree about what is
# being shipped, and refused BY NAME rather than defaulted — there is no
# placeholder tier on the release path.
begin
  app_name  = Bootstrap.identity!("APP_PRODUCT_NAME")
  bundle_id = Bootstrap.identity!("BUNDLE_ID")
rescue StandardError => e
  Bootstrap::UI.fail!(e.message)
end

# The string form the rest of this file and release.yml's `dry_run` input expect.
# `force` was resolved by the parser above and is used unchanged below.
dry_run = dry_run_requested ? "true" : "false"

# Pre-flight summary so the human can sanity-check what's about to ship
# (right ref, right app, right mode) before any side effects. Surfaces
# config drift early — e.g. APP_NAME=SmokeApp on repo named my-cool-app
# stands out at a glance.
def fetch_main_head(repo)
  out, ok = Bootstrap::Sh.run("gh", "api", "repos/#{repo}/commits/main",
                              "--jq", '"\(.sha) \(.commit.message | split("\n")[0])"')
  return ["?", "(unknown)"] unless ok && !out.strip.empty?
  parts = out.strip.split(" ", 2)
  [parts[0], parts[1] || "(no message)"]
end

# `app_name` / `bundle_id` are passed in rather than read here: they are
# resolved once at the top of this script, from app/Identity.xcconfig.
def print_preflight(config, dry_run, app_name:, bundle_id:, repo: nil, tag: nil)
  puts
  puts Bootstrap::UI.bold("About to ship #{app_name} (#{bundle_id}):")
  if config.ci_mode?
    sha, subject = fetch_main_head(repo)
    puts "  ref:       #{repo} main @ #{sha[0, 7]} — #{subject}"
    puts "  mode:      ci → release.yml dispatches on GitHub (mints fresh certs, ships, revokes)"
  else
    head_sha, _ = Bootstrap::Sh.run("git", "rev-parse", "--short", "HEAD")
    head_msg, _ = Bootstrap::Sh.run("git", "log", "-1", "--pretty=%s")
    puts "  ref:       local HEAD @ #{head_sha.strip} — #{head_msg.strip}"
    puts "  mode:      local → fastlane release runs on this machine"
    puts "  signing:   login keychain (Apple Distribution + Apple Development + 3rd Party Mac Developer Installer)"
    puts "  tag:       #{tag}"
  end
  puts "  platforms: #{config.platforms.join(', ')}"
  puts "  dry-run:   #{dry_run}" if dry_run == "true"
  if config.ci_mode?
    puts
    puts Bootstrap::UI.dim('Note: GitHub Actions also runs a workflow named "PR" (.github/workflows/pr.yml)')
    puts Bootstrap::UI.dim("on every push. It is a CI sanity check, NOT a Pull Request, and does not")
    puts Bootstrap::UI.dim("gate this release. Both run independently.")
  end
  puts
end

# ─── Local mode: run fastlane release on this machine ─────────────────────────
if config.local_mode?
  require_relative "lib/version_resolver"
  require "spaceship"
  Bootstrap.ensure_asc_token!(config)
  begin
    tag = Bootstrap::Version.compute_release_tag(bundle_id)
  rescue StandardError => e
    Bootstrap::UI.fail!("Could not compute release tag: #{e.message}")
  end
  print_preflight(config, dry_run, app_name: app_name, bundle_id: bundle_id, tag: tag)
  puts Bootstrap::UI.bold("Running fastlane release locally — tag #{tag}")
  env = Bootstrap.asc_env(config).merge("PLATFORMS" => config.platforms.join(","))
  args = ["bundle", "exec", "fastlane", "release", "tag:#{tag}"]
  args << "skip_upload:true" if dry_run == "true"

  # Sh.stream, not Sh.run: this is the longest-running command in the whole
  # tool and its output is the only record of what happened. Sh.run would
  # buffer it through capture3, drop stderr, and hand back a string this
  # branch then throws away on success — so `make ship > ship.log` captured
  # 13 lines of this script's own puts and nothing from fastlane, on a failed
  # release as readily as on a good one.
  _out, ok = Bootstrap::Sh.stream(*args, env: env)
  if ok
    puts
    puts Bootstrap::UI.bold("✅ Local release succeeded.")
    puts "Tag #{tag} pushed; binaries uploaded to App Store Connect."
    puts "Run #{Bootstrap::UI.bold 'make verify'} to confirm TestFlight ingestion (~5-15 min)."
    exit 0
  else
    # No `puts out` here — it has already been printed, in order and with
    # stderr interleaved, as it happened.
    Bootstrap::UI.fail!("fastlane release failed. The fastlane output above is the diagnosis.")
  end
end

# ─── CI mode: trigger release.yml + tail ──────────────────────────────────────
repo = config.repo_slug

def find_in_progress_run(repo)
  out, _ = Bootstrap::Sh.run("gh", "run", "list", "--workflow", "release.yml",
                              "--repo", repo, "--branch", "main", "--limit", "5",
                              "--json", "databaseId,status",
                              "--jq", '.[] | select(.status == "in_progress" or .status == "queued" or .status == "pending") | .databaseId')
  id = out.lines.first&.strip
  id && !id.empty? ? id : nil
end

def head_already_tagged?(repo)
  head_sha, ok = Bootstrap::Sh.run("gh", "api", "repos/#{repo}/commits/main", "--jq", ".sha")
  return nil unless ok
  head_sha = head_sha.strip
  return nil if head_sha.empty?
  tags_json, ok2 = Bootstrap::Sh.run("gh", "api", "repos/#{repo}/tags?per_page=20",
                                      "--jq", '[.[] | {name, sha: .commit.sha}]')
  return nil unless ok2 && !tags_json.strip.empty?
  match = JSON.parse(tags_json).find { |t| t["sha"] == head_sha }
  match ? [match["name"], head_sha] : nil
end

def trigger_new_run(repo, dry_run, platforms, generator)
  banner = "Triggering release.yml on #{repo} (dry_run=#{dry_run}, platforms=#{platforms}"
  banner += ", generator=#{generator}" unless generator.to_s.empty?
  banner += ")…"
  puts Bootstrap::UI.bold(banner)
  args = ["gh", "workflow", "run", "release.yml", "--ref", "main",
          "-f", "dry_run=#{dry_run}",
          "-f", "platforms=#{platforms}",
          "--repo", repo]
  args += ["-f", "generator=#{generator}"] unless generator.to_s.empty?
  out, ok = Bootstrap::Sh.run(*args)
  Bootstrap::UI.fail!("gh workflow run failed:\n#{out}") unless ok

  sleep 5
  20.times do
    out, _ = Bootstrap::Sh.run("gh", "run", "list", "--workflow", "release.yml",
                                "--repo", repo, "--limit", "1",
                                "--json", "databaseId,status,createdAt",
                                "--jq", ".[0].databaseId")
    id = out.strip
    return id unless id.empty?
    sleep 2
  end
  Bootstrap::UI.fail!("could not find newly-triggered run id")
end

run_id = nil

unless force
  if (existing = find_in_progress_run(repo))
    puts Bootstrap::UI.warn("Existing release run already in progress on #{repo}/main: ##{existing}")
    puts "  → https://github.com/#{repo}/actions/runs/#{existing}"
    puts "  Tailing this run instead of starting a new one. Pass --force to override."
    puts
    run_id = existing
  elsif (already = head_already_tagged?(repo))
    tag, sha = already
    puts Bootstrap::UI.ok("HEAD on #{repo}/main is already shipped as tag #{tag}")
    puts Bootstrap::UI.dim("(SHA #{sha[0, 8]}; pass --force to ship again)")
    exit 0
  end
end

print_preflight(config, dry_run, app_name: app_name, bundle_id: bundle_id, repo: repo)

run_id ||= trigger_new_run(repo, dry_run, config.platforms.join(","), config["GENERATOR"])
run_url = "https://github.com/#{repo}/actions/runs/#{run_id}"
puts "  → #{run_url}"
puts

last_status = nil
loop do
  out, _ = Bootstrap::Sh.run("gh", "run", "view", run_id, "--repo", repo,
                              "--json", "status,conclusion",
                              "--jq", '"\(.status) \(.conclusion // "-")"')
  parts = out.strip.split(" ", 2)
  status, conclusion = parts[0], parts[1]
  if status != last_status
    ts = Time.now.strftime("%H:%M:%S")
    puts "[#{ts}] #{status} #{conclusion}"
    last_status = status
  end
  if status == "completed"
    if conclusion == "success"
      puts
      puts Bootstrap::UI.bold("✅ Release succeeded.")
      puts "Tag pushed; both binaries uploaded to App Store Connect."
      puts "Run #{Bootstrap::UI.bold 'make verify'} to confirm TestFlight ingestion (~5-15 min ASC processing time)."
      exit 0
    else
      puts
      Bootstrap::UI.fail!("Release run #{run_id} concluded with: #{conclusion}\nSee #{run_url}")
    end
  end
  sleep 30
end
