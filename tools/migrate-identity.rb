#!/usr/bin/env ruby
# frozen_string_literal: true

# Migrate a fork that ran the old rename onto the config-based identity scheme —
# and REFUSE, by name, on any tree whose state it cannot read (IDENT-14, D-70).
#
# WHAT THIS COMMAND DOES
#
# It reads a fork's tree, decides which of three states it is in, and says so:
#
#   never-migrated        none of the four signals present — the population this
#                         command exists for: a pre-#281 fork that ran the rename
#                         and carries its own token in project, schemes, targets,
#                         the @main struct and the entitlements filenames
#   already fully migrated  all four signals present — nothing to do, reported
#                         LOUDLY and never as a bare exit 0
#   partially migrated    any mixture — refused, naming every mixed signal
#
# WHAT THIS FILE DOES NOT DO, YET
#
# Nothing here writes a byte. The mutation half — the xcconfig writer, the
# git mv set, the manifest surgery and the reset-hard rollback — lands in plans
# 05-03 and 05-04. Until then the non-dry-run path refuses with exit 4 rather
# than pretending, because a migration that reports success without having
# changed anything is the same defect as one that reports success without having
# looked.
#
# WHY THE DETECTOR IS NEW RATHER THAN BORROWED
#
# bin/rename.sh's check_idempotency counts file paths and returns a bare 0/1/2
# with no message — a partial tree reported as a number. Upstream's post-#281
# rewrite of it keys on ONE signal, app/Identity.xcconfig, with the comment "the
# project structure is a constant, so file paths say nothing about whether a
# rename happened". That is true after #281 and false before it, which is
# precisely the tree this command is pointed at: on a pre-#281 renamed fork the
# single-signal detector answers "not migrated" for the right reason and
# "migrated" for the wrong one. The four signals below were measured across seven
# refs (05-RESEARCH.md:515-521).
#
# WHY THIS FILE IS IN tools/ AND NOT IN bin/
#
# bin/refork-smoketest.sh DELETES this repository and recreates it from the
# template, so a fork-authored file at a template-owned path is removed wholesale
# on the next refork — the UL-003 / IDENT-11 / D-69 failure class, and the reason
# tools/check-contamination.rb is not at bin/check-identity.sh. AGENTS.md:271
# states the rule; bin/lib/xcconfig.rb is its one recorded exception and this is
# not a second one. The file RELOCATES to bin/migrate-identity.rb inside the
# D-77(b) upstream pull request (plan 05-14), which is the convention
# docs/CONTRIBUTING-UPSTREAM.md:138-140 already documents for
# tools/gen-review-notes.rb.
#
# WHY RUBY AND NOT BASH
#
# bin/lib/xcconfig.rb — the one xcconfig reader this command is required to use
# (AGENTS.md:277-292) — is Ruby with zero require lines, and
# bin/preflight-identity.rb, whose refusal shape D-70 copies, is Ruby. A bash
# implementation would need a fifth reader or a shell-out per key. The accepted
# cost is porting bin/rename.sh's trap-based rollback, ~30 lines, in plan 05-03.
# /usr/bin/ruby is 2.6.10 and is never used; both pinned interpreters
# (/opt/homebrew/opt/ruby@3.3/bin/ruby 3.3.12 and
# /opt/homebrew/opt/ruby@4.0/bin/ruby 4.0.6) must pass test/migrate_identity_test.rb.
#
# WHY A ONE-TIME MIGRATION COMMAND IS IN SCOPE UPSTREAM
#
# SCOPE.md's test is "does this addition require modifying Swift source files to
# use it?" (SCOPE.md:11) and SCOPE.md:32 lists "fork-rename scripts" among the
# in-scope developer-experience helpers. This command edits a Swift file — the
# @main struct's name — which looks at first glance like the shape SCOPE.md bars.
# It is not: that edit is the command's one-time OUTPUT, not a precondition of
# using it. Nobody has to open a Swift file to run this, and nothing it installs
# has to be wired into app code afterwards. A rename script that renames source
# has always been in scope by the same reading; this is that script's successor,
# pointed the other way. The argument is made explicitly here so the upstream
# pull request can be reviewed on it rather than on an implicit claim.
#
# Exit-code contract:
#
#   Exit | Meaning                                              | Message must name
#   -----+------------------------------------------------------+---------------------------------------------
#   0    | migrated successfully, OR already fully migrated,     | every satisfied signal; the detected
#        | reported LOUDLY and never silently                    | structural token on a --dry-run
#   1    | unknown or malformed argv                            | the offending argument and the usage line
#   2    | the tree at --root is not one this command            | the resolved absolute path and the CWD;
#        | understands: missing, not a directory, no             | for a token disagreement, every value found;
#        | app/project.yml, no readable `name:`, a structural    | for a broken include, the include
#        | token that cannot be read the same way twice, an      |
#        | app/Identity.xcconfig that cannot be resolved, or —   |
#        | on a mutating run only — not a git repository         |
#   3    | partially migrated: a mixture of migrated and         | every mixed signal, comma-separated, and
#        | un-migrated state, including a present-but-           | every missing identity variable
#        | incomplete app/Identity.xcconfig                       |
#   4    | a mutation-phase refusal (plan 05-03)                 | what would have been migrated, and why it
#        |                                                       | was not
#
# Exit 2 versus exit 3 is the tools/asc-probe.rb idiom, restated at
# bin/preflight-identity.rb:32-48: "not found" is a distinct outcome from
# "checked and wrong", and it gets a distinct code, so "this tree was never
# understood" can never be read as "this tree checked out".
#
# Exit 4 exists for a measured reason rather than a stylistic one. The mutation
# half currently raises NotImplementedError; an UNCAUGHT NotImplementedError
# exits 1 with a backtrace under both pinned interpreters (measured 2026-09-03,
# 3.3.12 and 4.0.6). Exit 1 is spoken for by malformed argv, so a caller
# branching on the code would read "not implemented yet" as "you called me
# wrong" — the shape 03-REVIEW IN-01 found when a directory at --config produced
# an EISDIR backtrace instead of the contract's exit 2.
#
# Usage:
#   ruby tools/migrate-identity.rb --dry-run              # detect this repository, write nothing
#   ruby tools/migrate-identity.rb --root PATH --dry-run  # detect the tree at PATH (fixtures)
#   ruby tools/migrate-identity.rb --root PATH            # migrate it (plan 05-03)
#
# Ruby core only, exactly ONE require-family line — require_relative of a sibling
# in this repository that itself has zero requires, not even stdlib
# (test/xcconfig_test.rb asserts that, so it cannot rot). Nothing outside core is
# loaded on any path, which is what lets .github/workflows/review-notes.yml keep
# bundler-cache: false. Do NOT add a YAML gem to read app/project.yml: the
# manifest's `name:` is read line-orientedly below for exactly that reason.
#
# There is NO broad rescue in this file. The two rescues both name a class —
# Xcconfig::MissingInclude and NotImplementedError — and each is commented with
# what it is for. A silently tolerated error here means a tree reported as
# migrated that was never inspected.

require_relative "../bin/lib/xcconfig"

# Resolved from __dir__, never from the CWD, so the default is the same whether
# the command is run from the repository root, from app/, or from anywhere else.
DEFAULT_ROOT = File.expand_path("..", __dir__)

# The constant the structural freeze landed on (D-47). A migrated tree's
# project, its @main struct, its entitlements and its manifest `name:` all say
# this, and nothing about the fork's own identity appears in a file path.
MIGRATED_TOKEN = "App"

# Duplicated deliberately from bin/preflight-identity.rb rather than imported:
# a list read out of the gate it is supposed to agree with is not a second
# opinion. If these two ever disagree, that is a finding, not a merge conflict.
REQUIRED_VARS = %w[BUNDLE_ID APP_PRODUCT_NAME DISPLAY_NAME COPYRIGHT].freeze

REL_IDENTITY     = "app/Identity.xcconfig"
REL_APP_SWIFT    = "app/Shared/App.swift"
REL_PROJECT_YML  = "app/project.yml"
REL_ENTITLEMENTS = "app/iOS/App.entitlements"

# The four D-70 signals, as printed. test/migrate_identity_test.rb spells the
# same four strings out by hand; a rewording on either side is meant to break it.
SIGNAL_IDENTITY     = "app/Identity.xcconfig exists"
SIGNAL_APP_SWIFT    = "app/Shared/App.swift exists"
SIGNAL_PROJECT_NAME = "app/project.yml name: is App"
SIGNAL_ENTITLEMENTS = "app/iOS/App.entitlements exists"

STATE_NEVER   = "never-migrated"
STATE_FULL    = "already fully migrated"
STATE_PARTIAL = "partially migrated"

# Every failure line carries this prefix so it is greppable out of a caller's
# interleaved output; every informational line carries the other.
FAIL_PREFIX = "MIGRATE-IDENTITY FAILED:"
LOG_PREFIX  = "MIGRATE-IDENTITY:"

# `struct <Token>Main: App {` — the @main entry point. The capture is lazy so it
# stops at the LAST "Main" that is followed by `: App {`, which is what makes
# `struct MigrateFixtureMain: App {` yield `MigrateFixture` and not `MigrateFi`.
MAIN_STRUCT = /^\s*struct\s+([A-Za-z_][A-Za-z0-9_]*?)Main\s*:\s*App\s*\{/.freeze

USAGE = <<~USAGE
  usage: ruby tools/migrate-identity.rb [--root PATH] [--dry-run]
    --root PATH   inspect the tree at PATH instead of #{DEFAULT_ROOT};
                  prints a banner to stderr on every use (fixtures only)
    --dry-run     detect and report only; never write a byte
    -h, --help    print this usage and exit 0
USAGE

# Every failure path is explicit and loud, on stderr, prefixed and coded.
def fail_with(code, message)
  warn "#{FAIL_PREFIX} #{message}"
  exit code
end

def say(message)
  puts "#{LOG_PREFIX} #{message}"
end

# Unbuffered stdout, so the report and the refusal interleave in the order they
# were actually emitted. Ruby line-buffers stdout to a tty but BLOCK-buffers it
# to a pipe or a file, while stderr is never buffered — so in a redirected run
# (which is every CI log and every transcript) a `fail_with` on stderr overtakes
# the `say` lines that explain it, and the log reads as a refusal with no
# preceding report. Observed 2026-09-03 in the ground-truth fixture transcript.
$stdout.sync = true

# UTF-8 pinned, never inherited. app/Identity.xcconfig carries © (U+00A9) in
# COPYRIGHT, and with LANG unset Ruby defaults Encoding.default_external to
# US-ASCII, where a non-ASCII byte raises ArgumentError out of a regex match
# instead of producing an exit code. Commit 3b1efb9 is this repository's own
# instance of inheriting the locale (UL-012).
def read_utf8(path)
  File.read(path, encoding: "UTF-8")
end

# --- argv --------------------------------------------------------------------
# Three flags are accepted. Unknown argv is REJECTED, never ignored: a typo'd
# flag on a command that is about to rewrite a tree must not look like a
# successful run. Shape copied from bin/preflight-identity.rb:112-150.

root_override = nil
dry_run = false
argv = ARGV.dup
until argv.empty?
  arg = argv.shift
  case arg
  when "--root"
    path = argv.shift
    if path.nil? || path.empty? || path.start_with?("--")
      warn "#{FAIL_PREFIX} --root requires a PATH argument\n#{USAGE}"
      exit 1
    end
    unless root_override.nil?
      warn "#{FAIL_PREFIX} --root given more than once\n#{USAGE}"
      exit 1
    end
    root_override = File.expand_path(path)
  when "--dry-run"
    dry_run = true
  when "-h", "--help"
    puts USAGE
    exit 0
  else
    warn "#{FAIL_PREFIX} unknown argument #{arg.inspect}\n#{USAGE}"
    exit 1
  end
end

root = root_override || DEFAULT_ROOT

# Loud on every use, on stderr, BEFORE any work, so a run pointed at a fixture
# can never be mistaken for a run against the real tree in a log (T-05-06). The
# shape is bin/preflight-identity.rb:154-163; both the root that was skipped and
# the one that was taken are named, because a banner that only says "override"
# tells a log reader nothing about what was actually inspected.
unless root_override.nil?
  warn "#{LOG_PREFIX} ==== ROOT OVERRIDE IN EFFECT (--root) ===="
  warn "#{LOG_PREFIX} default root #{DEFAULT_ROOT} was NOT inspected"
  warn "#{LOG_PREFIX} inspecting override #{root} instead"
end

# --- exit 2: is this a tree this command understands? -------------------------

unless File.exist?(root)
  fail_with 2, "#{root} not found (cwd: #{Dir.pwd}). --root must name the root " \
               "directory of the fork to inspect — the directory that contains app/."
end

unless File.directory?(root)
  fail_with 2, "#{root} is not a directory (cwd: #{Dir.pwd}). --root must name the root " \
               "directory of the fork to inspect — the directory that contains app/."
end

manifest = File.join(root, REL_PROJECT_YML)
unless File.file?(manifest)
  fail_with 2, "#{root} is not a tree this command understands: #{manifest} not found " \
               "(cwd: #{Dir.pwd}). Every ref of this template and of every fork of it " \
               "carries app/project.yml; without it there is no manifest to read a " \
               "structural token out of."
end

# --- exit 2: the structural token, read three independent ways ----------------
#
# A tree whose identity cannot be read the same way twice is not one this command
# understands, and guessing would mean renaming the wrong things (05-RESEARCH.md:309-313).
# Sources, in the order they are reported:
#
#   1. app/project.yml `name:`                    — always present
#   2. app/Shared/*.swift `struct <N>Main: App`   — present unless the @main file was moved
#   3. app/<N>.xcodeproj                          — only when a generated project is on disk
#                                                   (it is gitignored, so CI usually has none)

name_line = read_utf8(manifest).lines.find { |line| line.start_with?("name:") }
if name_line.nil?
  fail_with 2, "#{manifest} has no top-level `name:` line (cwd: #{Dir.pwd}). That line is " \
               "the project's name in XcodeGen's spec and the first of three independent " \
               "reads of this tree's structural token."
end

manifest_name = name_line.sub(/\Aname:/, "").strip
manifest_name = manifest_name[1..-2].to_s if manifest_name.length >= 2 &&
                                             (manifest_name.start_with?('"') && manifest_name.end_with?('"') ||
                                              manifest_name.start_with?("'") && manifest_name.end_with?("'"))
if manifest_name.empty?
  fail_with 2, "#{manifest}'s `name:` line assigns nothing (cwd: #{Dir.pwd}). An empty " \
               "project name is not a token this command can migrate away from."
end

derivations = { "app/project.yml name:" => manifest_name }

main_structs = Dir.glob(File.join(root, "app/Shared/*.swift")).sort.each_with_object({}) do |path, found|
  match = read_utf8(path).match(MAIN_STRUCT)
  found[path] = match[1] unless match.nil?
end
if main_structs.length > 1
  fail_with 2, "#{root} declares more than one `struct <Token>Main: App` " \
               "(#{main_structs.map { |p, t| "#{p} => #{t}" }.join('; ')}). A tree with two " \
               "@main entry points is not one this command understands."
end
main_structs.each { |path, token| derivations["#{path.sub("#{root}/", '')} struct #{token}Main"] = token }

xcodeprojs = Dir.glob(File.join(root, "app/*.xcodeproj")).select { |p| File.directory?(p) }.sort
if xcodeprojs.length > 1
  fail_with 2, "#{root} contains more than one generated project " \
               "(#{xcodeprojs.join(', ')}). Delete the stale one — it is gitignored and " \
               "regenerable — and re-run."
end
xcodeprojs.each { |path| derivations[path.sub("#{root}/", "")] = File.basename(path, ".xcodeproj") }

tokens = derivations.values.uniq
if tokens.length > 1
  fail_with 2, "#{root} is not a tree this command understands: its structural token could " \
               "not be read the same way twice — the derivations disagree: " \
               "#{derivations.map { |source, token| "#{source} => #{token}" }.join('; ')}. " \
               "Reconcile the tree by hand before migrating; a migration that picked one of " \
               "these would rename the others to something they never were."
end
token = tokens.first

# --- the four signals ---------------------------------------------------------

identity_path = File.join(root, REL_IDENTITY)
identity_present = File.file?(identity_path)

# "The file exists" is not a check. A key missing from a PRESENT
# app/Identity.xcconfig resolves to the empty string, both generators exit 0, and
# the built app carries an empty CFBundleIdentifier (RESEARCH Pitfall 1, observed
# on Xcode 26.1.1). So a present xcconfig is also asked for its four values,
# through the one reader (D-57) — `nil` (never assigned) and `""` (assigned but
# empty, comment-only, or resolving through undefined references to nothing) are
# both failures here, exactly as bin/preflight-identity.rb treats them.
missing_vars = []
if identity_present
  begin
    missing_vars = REQUIRED_VARS.reject do |key|
      value = Xcconfig.value(identity_path, key)
      !value.nil? && !value.empty?
    end
  rescue Xcconfig::MissingInclude => e
    # NAMED class, not a broad rescue. A hard `#include` that is not there, or an
    # include cycle: the config could not be READ, which is exit 2 and never exit
    # 3, so "your include is broken" cannot arrive as "that key is empty".
    fail_with 2, "#{identity_path} could not be resolved: #{e.message}. Fix the #include, " \
                 "or make it optional (`#include?`, which is silent when the file is absent), " \
                 "before migrating."
  end
end

signals = {
  SIGNAL_IDENTITY     => identity_present,
  SIGNAL_APP_SWIFT    => File.file?(File.join(root, REL_APP_SWIFT)),
  SIGNAL_PROJECT_NAME => manifest_name == MIGRATED_TOKEN,
  SIGNAL_ENTITLEMENTS => File.file?(File.join(root, REL_ENTITLEMENTS))
}
satisfied   = signals.select { |_, present| present }.keys
unsatisfied = signals.reject { |_, present| present }.keys

# --- exit 0: already fully migrated, said out loud ----------------------------

if unsatisfied.empty? && missing_vars.empty?
  say "==== #{STATE_FULL.upcase} ===="
  say "#{root} is #{STATE_FULL}. All four signals are satisfied:"
  satisfied.each { |signal| say "  satisfied: #{signal}" }
  say "  and #{REL_IDENTITY} defines #{REQUIRED_VARS.join(', ')}, every one of them non-empty"
  say "Nothing to do. This is exit 0 WITH A REPORT: D-70 rejected a silent idempotent exit 0"
  say "by name, because it is indistinguishable from a migration that did nothing because it"
  say "could not see the tree's state."
  exit 0
end

# --- exit 3: partially migrated, naming every mixed signal --------------------
#
# Collect every finding before reporting, per bin/preflight-identity.rb:200-224,
# so one run tells the operator all of what is mixed rather than the first thing.

unless satisfied.empty?
  detail = +"#{root} is #{STATE_PARTIAL} — a mixture of migrated and un-migrated state that " \
            "this command will not act on. "
  detail << "satisfied signal(s): #{satisfied.empty? ? 'none' : satisfied.join(', ')}; "
  detail << "unsatisfied signal(s): #{unsatisfied.empty? ? 'none' : unsatisfied.join(', ')}"
  unless missing_vars.empty?
    detail << "; #{identity_path} is present but missing required variable(s): " \
              "#{missing_vars.join(', ')}"
  end
  detail << ". Migrating a half-migrated tree would rename things that were already renamed " \
            "and leave the rest, so reconcile it by hand — or restore it from git and re-run " \
            "on the un-migrated tree."
  fail_with 3, detail
end

# --- never migrated -----------------------------------------------------------

say "state: #{STATE_NEVER} — none of the four migration signals is present in #{root}"
say "detected structural token: #{token}, read #{derivations.length} independent way(s):"
derivations.each { |source, value| say "  #{source} => #{value}" }
say "planned transformation (implemented in plans 05-03 and 05-04):"
say "  1. write #{REL_IDENTITY} with #{REQUIRED_VARS.join(', ')}, read from this tree's"
say "     currently resolved build settings"
say "  2. app/Shared/#{token}.swift -> #{REL_APP_SWIFT}, and struct #{token}Main -> struct #{MIGRATED_TOKEN}Main"
say "  3. app/iOS/#{token}.entitlements -> #{REL_ENTITLEMENTS}, and the macOS pair alongside it"
say "  4. #{REL_PROJECT_YML} and app/Project.swift onto the constant #{MIGRATED_TOKEN} — name,"
say "     targets, schemes and entitlement paths — with every identity setting a $(VAR)"
say "     reference into #{REL_IDENTITY} rather than a literal"
say "  5. regenerate app/#{MIGRATED_TOKEN}.xcodeproj and drop app/#{token}.xcodeproj (both gitignored)"
say "KNOWN BREAKING CHANGE (A-05): the built executable's filename changes, because a"
say "  pre-#281 renamed fork resolves PRODUCT_NAME to the target name including its platform"
say "  suffix while a migrated tree resolves one value. If you have a LIVE App Store listing,"
say "  verify with Apple that this is acceptable for your app BEFORE migrating. This command"
say "  does not make that judgement for you."

if dry_run
  say "--dry-run: nothing was written."
  exit 0
end

# --- exit 2: a mutating run needs a git repository ----------------------------
#
# Checked here and not during detection on purpose: detection is read-only and
# must work against an exported tree, a tarball or a fixture. The MUTATION needs
# git, because D-70's all-or-nothing rollback is `git reset --hard` plus a
# `git clean -fd` (never -fdx — the gitignored app/Local.xcconfig holds the
# forker's Team ID and .bootstrap.env holds their answers).
git_dir = File.join(root, ".git")
unless File.exist?(git_dir)
  fail_with 2, "#{root} is not a git repository (no .git at #{git_dir}; cwd: #{Dir.pwd}). " \
               "The migration rewrites tracked files in place and rolls the whole tree back " \
               "on any failure, which is a git operation. Re-run with --dry-run to inspect " \
               "this tree without mutating it."
end

# Plans 05-03 and 05-04 replace this body. Until they do it raises, and the raise
# is caught immediately below so the refusal carries a code from the contract.
def perform_migration(root:, token:)
  raise NotImplementedError, "mutation phase lands in plan 05-03"
end

begin
  perform_migration(root: root, token: token)
rescue NotImplementedError => e
  # NAMED class, not a broad rescue, and it exists for a measured reason: an
  # uncaught NotImplementedError exits 1 with a backtrace under both pinned
  # interpreters (measured 2026-09-03), and exit 1 is the contract's code for
  # malformed argv. DELETE THIS rescue in plan 05-03 together with the raise
  # above; leaving it once a real body exists would swallow a genuine
  # NotImplementedError raised from deeper in the migration.
  fail_with 4, "#{root} is #{STATE_NEVER} and would be migrated from the structural token " \
               "#{token} to the constant #{MIGRATED_TOKEN}, but nothing was written: " \
               "#{e.message}. Re-run with --dry-run to see the planned transformation."
end
