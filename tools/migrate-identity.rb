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
# WHAT THIS FILE DOES, AND WHAT IT STILL DOES NOT
#
# The VALUE half is implemented (plan 05-03): it reads the fork's identity from
# what the build actually resolves, writes app/Identity.xcconfig and proves the
# write by reading it back through the one parser, and relocates the Apple Team
# ID into gitignored app/Local.xcconfig behind a git-confirmed ignore gate. All
# of it sits behind bin/rename.sh's gate order and on top of a port of its
# atomic rollback.
#
# The STRUCTURAL half — the file moves, the @main struct, the manifest rewiring
# onto $(VAR) references and the regeneration — lands in plan 05-04. Until it
# does, a completed value half exits 4 with a LOUD report saying the tree is
# partially migrated, never exit 0: a migration that reports success while the
# manifests still carry literals is the same defect as one that reports success
# without having looked.
#
# WHY THE IDENTITY IS READ FROM THE BUILD AND NOT FROM THE MANIFESTS
#
# xcodebuild -showBuildSettings is the only source that reports what the build
# actually RESOLVES. A literal baked into a generated .pbxproj shadows the
# manifest that was supposed to produce it, and CHANGELOG.md:55 records that
# exact defect in this repository — XcodeGen wrote a host target name into
# TEST_HOST at generation time while PRODUCT_NAME resolved at build time, and
# every file-level check was green about it. 05-RESEARCH.md:238 assigns "reading
# the fork's current identity" to the build tier for the same reason. The
# manifests are used only as the cross-check: the collapsed PRODUCT_NAME must
# equal the structural token the three derivations above already agreed on, and
# a disagreement is a refusal rather than a guess.
#
# TWO FIXTURE KNOBS, BOTH ANNOUNCING, NEITHER SET BY CI
#
#   MIGRATE_IDENTITY_TOOL_DIR=<dir>
#     Resolves xcodebuild and xcodegen from <dir> instead of PATH, so
#     test/migrate_identity_test.rb can exercise the whole mutation phase on a
#     runner with no Xcode. git is deliberately NOT resolved through it: the
#     rollback is a git operation and a knob that could substitute git would be
#     a knob that could substitute the rollback.
#
#   MIGRATE_IDENTITY_FAIL_AFTER=xcconfig-write|team-id-move
#     Raises after the named mutation stage, which is the only way to reach the
#     rollback path from a test without breaking this command on purpose. An
#     unknown stage is exit 1, not a silent no-op.
#
# Both print a two-line banner on stderr before any work, the shape
# bin/lib/bootstrap.rb:604-611 established for IDENTITY_XCCONFIG. A silent knob
# is a way to disable a gate without anything going red, so the suite asserts
# both the banner and its ABSENCE on a default run.
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
#   1    | unknown or malformed argv, or an unknown value for   | the offending argument or knob value, and
#        | one of the two fixture knobs                         | the usage line or the valid stages
#   2    | the tree at --root is not one this command            | the resolved absolute path and the CWD;
#        | understands: missing, not a directory, no             | for a token disagreement, every value found;
#        | app/project.yml, no readable `name:`, a structural    | for a broken include, the include; for a
#        | token that cannot be read the same way twice, an      | build-settings problem, the scheme and the
#        | app/Identity.xcconfig that cannot be resolved, a      | configuration; for a written-then-unreadable
#        | build-settings dump that cannot be read              | value, the key, the intended and the resolved
#        | unambiguously, two platforms that disagree about a   |
#        | value there is only one of, or — on a mutating run   |
#        | only — not a git repository                          |
#   3    | partially migrated: a mixture of migrated and         | every mixed signal, comma-separated, and
#        | un-migrated state, including a present-but-           | every missing identity variable
#        | incomplete app/Identity.xcconfig                       |
#   4    | a mutation-phase refusal: a gate in front of the      | what would have been migrated, and why it
#        | mutation (toolchain, clean tree, on main, no          | was not; for the plan boundary, exactly what
#        | generated project, a Team ID that must not be         | WAS written and how to restore the tree
#        | written), an injected fixture failure, or the plan    |
#        | boundary — the value half done, the structural half   |
#        | still ahead in plan 05-04                            |
#
# Exit 2 versus exit 3 is the tools/asc-probe.rb idiom, restated at
# bin/preflight-identity.rb:32-48: "not found" is a distinct outcome from
# "checked and wrong", and it gets a distinct code, so "this tree was never
# understood" can never be read as "this tree checked out".
#
# Exit 4 exists for a measured reason rather than a stylistic one. Ruby exits 1
# with a backtrace on ANY uncaught exception (measured 2026-09-03 under both
# pinned interpreters), and exit 1 is spoken for by malformed argv — so a caller
# branching on the code would read "the migration blew up" as "you called me
# wrong", the shape 03-REVIEW IN-01 found when a directory at --config produced
# an EISDIR backtrace instead of the contract's exit 2. Every mutation-phase
# failure is therefore rolled back and re-reported as exit 4, with the exception
# class, its message and its backtrace all printed rather than swallowed.
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
# RESCUE POLICY. Every rescue in this file names a class and is commented with
# what it is for. Two name Xcconfig::MissingInclude ("your include is broken"
# must never arrive as "that key is empty") and one names
# FixtureInjectedFailure. The one remaining `rescue StandardError` wraps the
# MUTATION PHASE ONLY and is not a silent tolerance: it prints the exception's
# class, message and full backtrace, rolls the tree back, and re-reports as the
# contract's exit 4 — because the alternative is Ruby's uncaught-exception exit
# 1, which the contract reserves for "you called me wrong", on a tree that has
# already been half rewritten. Nothing outside the mutation phase is rescued.
#
# The NotImplementedError raise-and-rescue pair that plan 05-02 left here, with
# an instruction to delete itself, is GONE: this plan implements the body it
# stood in for, and leaving it would have swallowed a genuine NotImplementedError
# raised from deeper inside the migration.

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

REL_IDENTITY      = "app/Identity.xcconfig"
REL_APP_SWIFT     = "app/Shared/App.swift"
REL_PROJECT_YML   = "app/project.yml"
REL_ENTITLEMENTS  = "app/iOS/App.entitlements"
REL_PROJECT_SWIFT = "app/Project.swift"
REL_LOCAL         = "app/Local.xcconfig"

# The two platforms, and the one configuration the identity is read from. Debug
# rather than Release because a pre-#281 fork's Release configuration may not
# exist under that name in every generator, and the four identity settings are
# not configuration-scoped in either manifest — measured on e773cfc:app/project.yml,
# where all four sit under `settings: base:` and per-target `settings: base:`.
PLATFORMS     = %w[iOS macOS].freeze
CONFIGURATION = "Debug"

# The literal bin/rename.sh Step H substitutes away, and refuses to write when it
# is still present. A fork that never passed --team-id still carries it.
TEAM_ID_PLACEHOLDER = "TEAM_ID_PLACEHOLDER"

# --- fixture knobs ------------------------------------------------------------
# Read once, here, so the banners below and every later use see the same value
# and a knob cannot be re-read into a different answer mid-run.
FAIL_AFTER_ENV    = "MIGRATE_IDENTITY_FAIL_AFTER"
TOOL_DIR_ENV      = "MIGRATE_IDENTITY_TOOL_DIR"
FAIL_AFTER_STAGES = %w[xcconfig-write team-id-move].freeze
FAIL_AFTER        = ENV[FAIL_AFTER_ENV].to_s.strip
TOOL_DIR          = ENV[TOOL_DIR_ENV].to_s.strip.empty? ? "" : File.expand_path(ENV[TOOL_DIR_ENV].to_s.strip)

# Raised by the MIGRATE_IDENTITY_FAIL_AFTER knob and by nothing else, so an
# injected fixture failure can never be reported as a real one.
FixtureInjectedFailure = Class.new(StandardError)

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

# Same pin for text that came from a subprocess rather than a file. Ported from
# tools/identity-parity.rb:456-460: a settings dump carrying © raises out of a
# regex match under a US-ASCII default external encoding, and `scrub` keeps an
# invalid byte from becoming an exception three frames away from where it was read.
def utf8(text)
  text = text.dup.force_encoding(Encoding::UTF_8)
  text.valid_encoding? ? text : text.scrub("?")
end

# Subprocess capture, ported from tools/identity-parity.rb:431-454. Two things
# in it are load-bearing and neither is decoration:
#
#   * [argv[0], argv[0]] rather than a splat. Process.spawn with ONE string
#     argument is the STRING form, which Ruby hands to /bin/sh whenever the
#     string carries a metacharacter — so `Process.spawn(*argv)` on a
#     one-element argv would have been a shell string after all (03-REVIEW
#     IN-04, demonstrated). The two-element form is never shell-interpreted,
#     whatever argv holds. Nothing this command runs is ever built by
#     interpolating a value into a command line.
#   * $?.exitstatus is NIL for a signal-killed child, and every caller's
#     `status.zero?` would then raise NoMethodError — Ruby's exit 1, which this
#     contract reserves for malformed argv. Report 128+N instead.
#
# stderr is drained on its own thread so a chatty tool cannot deadlock the pipe.
def capture(argv, chdir:)
  out_r, out_w = IO.pipe
  err_r, err_w = IO.pipe
  pid = Process.spawn([argv[0], argv[0]], *argv[1..], chdir: chdir, in: File::NULL, out: out_w, err: err_w)
  out_w.close
  err_w.close
  err_thread = Thread.new { err_r.read }
  out = out_r.read
  err = err_thread.value
  out_r.close
  err_r.close
  Process.wait(pid)
  status = $?.exitstatus || (128 + $?.termsig.to_i)
  [utf8(out), utf8(err), status]
end

# PATH lookup in Ruby, so a missing binary is named before any subprocess is
# attempted rather than arriving as an ENOENT out of Process.spawn.
def on_path?(name)
  ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
    next false if dir.empty?

    candidate = File.join(dir, name)
    File.file?(candidate) && File.executable?(candidate)
  end
end

# The two Xcode-toolchain binaries, and ONLY those two, resolve through the
# fixture knob. `git` is always the PATH one: the rollback is a git operation,
# and a knob that could substitute git could substitute the rollback.
def tool_path(name)
  TOOL_DIR.empty? ? name : File.join(TOOL_DIR, name)
end

def tool_available?(name)
  return on_path?(name) if TOOL_DIR.empty?

  candidate = File.join(TOOL_DIR, name)
  File.file?(candidate) && File.executable?(candidate)
end

def tool_source
  TOOL_DIR.empty? ? "PATH" : TOOL_DIR
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

# The two fixture knobs announce themselves BEFORE any work, on stderr, in the
# shape bin/lib/bootstrap.rb:604-611 established for IDENTITY_XCCONFIG. An
# unrecognised stage is exit 1 and not a silent no-op: a knob that quietly
# ignored what it was handed would let a caller believe a gate had been driven
# when nothing had happened at all.
unless FAIL_AFTER.empty?
  unless FAIL_AFTER_STAGES.include?(FAIL_AFTER)
    warn "#{FAIL_PREFIX} #{FAIL_AFTER_ENV}=#{FAIL_AFTER.inspect} names no stage this command " \
         "knows. Valid stages: #{FAIL_AFTER_STAGES.join(', ')}. This knob exists only to drive " \
         "the rollback from test/migrate_identity_test.rb; unset it to run a real migration."
    exit 1
  end
  warn "!! #{FAIL_AFTER_ENV} override in effect: will raise after #{FAIL_AFTER}"
  warn "!! This run is a FIXTURE. It says nothing about a real migration."
end

unless TOOL_DIR.empty?
  warn "!! #{TOOL_DIR_ENV} override in effect: xcodebuild and xcodegen resolve from #{TOOL_DIR}"
  warn "!! This run is a FIXTURE. It says nothing about a real migration or a real build."
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

# --- the rollback spine -------------------------------------------------------
#
# A Ruby port of bin/rename.sh:325-371, whose behaviour is copied rather than
# improved on. Bash's `trap ... ERR EXIT INT TERM` has no direct equivalent, so
# the three arms are: begin/ensure around the mutation phase, Signal.trap for INT
# and TERM, and an at_exit guard. The MUTATION_STARTED latch is the load-bearing
# part and the reason bin/rename.sh documents it in place: without it, a
# clean-tree gate failure would fire the EXIT trap and `git reset --hard` would
# DESTROY the forker's uncommitted work — the gate would become the disaster it
# exists to prevent (T-05-13).
#
# Ruby cannot un-register an at_exit block, so the success path disarms by
# setting the latches rather than by removing a trap.

@mutation_started     = false
@rollback_done        = false
@rollback_root        = nil
@rollback_outcome     = "not-needed"
# Set by plan 05-04 when it regenerates app/App.xcodeproj. Deliberately stronger
# than bin/rename.sh's `[ -n "$APP_NAME" ] && [ -d ... ]`: that guard removes a
# directory by NAME, and this one removes only a directory this command created.
# On this path a pre-existing app/App.xcodeproj is unreachable anyway — it would
# make the token derivations disagree (exit 2) or the tree partially migrated
# (exit 3) long before the mutation phase — but "we made it" is the property the
# removal actually depends on, so that is what is recorded.
@regenerated_project  = nil
# path => bytes, or path => nil meaning "did not exist". THE PART bin/rename.sh
# does not need and this command does: `git reset --hard` cannot restore a
# GITIGNORED file and `git clean -fd` deliberately will not remove one, so a
# rollback after the Team-ID move would otherwise leave app/Local.xcconfig
# rewritten while reporting that the tree was restored.
@gitignored_snapshots = {}

def snapshot_gitignored(path)
  return if @gitignored_snapshots.key?(path)

  @gitignored_snapshots[path] = File.file?(path) ? File.binread(path) : nil
end

def restore_gitignored_snapshots
  @gitignored_snapshots.each do |path, bytes|
    if bytes.nil?
      File.delete(path) if File.file?(path)
    else
      File.binwrite(path, bytes)
    end
  end
end

def rollback
  return @rollback_outcome if @rollback_done

  @rollback_done = true
  # The pre-mutation early-out. A failure before the latch lands here as a no-op.
  return @rollback_outcome unless @mutation_started

  warn "#{LOG_PREFIX} rolling back to the pre-migration state..."

  # Step 0: the gitignored files this command wrote, which git cannot restore.
  restore_gitignored_snapshots

  # Step 1: the regenerated project, if this command made one. It is gitignored,
  # so step 3 would not touch it.
  if !@regenerated_project.nil? && File.directory?(@regenerated_project)
    capture(["rm", "-rf", @regenerated_project], chdir: @rollback_root)
  end

  # Step 2: tracked-file modifications and any staged moves, back to HEAD.
  _, err, status = capture(["git", "reset", "--hard", "HEAD", "--quiet"], chdir: @rollback_root)
  unless status.zero?
    warn "#{LOG_PREFIX} git reset --hard HEAD failed (exit #{status}): #{err.strip}"
    warn "#{LOG_PREFIX} manual recovery required — inspect: git status; git log --oneline -5"
    @rollback_outcome = "manual-recovery-required"
    return @rollback_outcome
  end

  # Step 3: new untracked files. -fd, and never the -x variant: -x would delete
  # the forker's gitignored .bootstrap.env and app/Local.xcconfig, which is the
  # denial-of-service T-05-12 names and which no failure of this command
  # justifies.
  capture(["git", "clean", "-fd", "--quiet"], chdir: @rollback_root)
  warn "#{LOG_PREFIX} rolled back to the pre-migration state."
  @rollback_outcome = "restored"
  @rollback_outcome
end

# Armed BEFORE the gates, not after them, which is where bin/rename.sh arms its
# traps (file scope, line 314-316) and is the only arrangement in which the
# MUTATION_STARTED latch is load-bearing rather than decoration.
#
# MEASURED 2026-09-03. With the arming done just before the first mutation
# instead, a control that set the latch unconditionally changed NOTHING and the
# suite stayed green — because a gate failure before the arming registers no
# at_exit handler at all, so the latch never gets consulted. A safety property no
# test can drive red is not a safety property. Armed here, the control goes red
# on the clean-tree case exactly as T-05-13 describes: the rollback fires, and a
# reset --hard lands on the forker's dirty tree.
def arm_rollback(root)
  @rollback_root = root
  Signal.trap("INT")  { rollback; exit 130 }
  Signal.trap("TERM") { rollback; exit 143 }
  at_exit { rollback }
end

def disarm_rollback
  @mutation_started = false
  @rollback_done    = true
end

def fail_after_stage(stage)
  return unless FAIL_AFTER == stage

  raise FixtureInjectedFailure,
        "#{FAIL_AFTER_ENV}=#{stage} raised immediately after the #{stage} stage, on purpose."
end

# --- gates, in bin/rename.sh:904-1000's order ---------------------------------

def gate_xcodegen_present
  return if tool_available?("xcodegen")

  fail_with 4, "xcodegen not found (looked in #{tool_source}). The migration regenerates the " \
               "project from #{REL_PROJECT_YML} once the structure has moved, and a migration " \
               "that stopped half way for a missing tool would leave the tree in exactly the " \
               "state D-70's rollback exists to prevent. Install it (brew install xcodegen) and " \
               "re-run."
end

def gate_clean_tree(root)
  out, err, status = capture(["git", "status", "--short"], chdir: root)
  unless status.zero?
    fail_with 4, "git status --short exited #{status} in #{root}: #{err.strip}. The clean-tree " \
                 "gate could not be evaluated, and an unevaluated gate is a refusal."
  end

  # Counted in Ruby. bin/rename.sh needs `| tr -d ' '` here because BSD `wc -l`
  # right-pads its output to width 8 and a bare string comparison fails on it;
  # there is no such padding to strip when the lines are counted in-process.
  dirty = out.lines.map(&:chomp).reject { |line| line.strip.empty? }
  return if dirty.empty?

  fail_with 4, "working tree not clean in #{root} — commit, stash or remove " \
               "#{dirty.length} entr#{dirty.length == 1 ? 'y' : 'ies'} before migrating. This " \
               "command rewrites tracked files in place and rolls the whole tree back with " \
               "git reset --hard on any failure, which would DESTROY uncommitted work. Untracked " \
               "files are counted deliberately (no --untracked-files=no), because the rollback's " \
               "git clean removes them. First: #{dirty.first(5).join(' | ')}"
end

def gate_on_main(root)
  _, _, has_main = capture(["git", "show-ref", "--verify", "--quiet", "refs/heads/main"], chdir: root)
  branch_out, _, branch_status = capture(["git", "rev-parse", "--abbrev-ref", "HEAD"], chdir: root)
  branch = branch_status.zero? ? branch_out.strip : "(unreadable)"

  unless has_main.zero?
    # A WARNING, not a refusal. bin/rename.sh refuses here because it runs on a
    # forker's own checkout, but this command is also pointed at fixture clones
    # that legitimately have no main — 05-01's harness force-sets one for exactly
    # this reason. Refusing would make every fixture unusable, and a gate that
    # blocks its own tests gets deleted rather than fixed.
    say "no main branch in #{root}; proceeding on #{branch}."
    return
  end

  return if branch == "main"

  fail_with 4, "not on main in #{root} (currently: #{branch}, and a main branch exists). Migrate " \
               "on main so the rollback's git reset --hard HEAD restores the branch you expect, " \
               "then merge. Check out main and re-run."
end

# --- reading the fork's identity from the BUILD -------------------------------

# One `<key>K</key>` / `<string>V</string>` pair out of a generated Info.plist.
# A line-oriented read rather than a plist library: no gem may be added here
# (that would cost .github/workflows/review-notes.yml its bundler-cache: false),
# /usr/libexec/PlistBuddy is macOS-only and this suite must run on a Linux
# runner, and the file being read is XcodeGen's own output with a known shape.
def plist_string(text, key)
  lines = text.lines.map(&:strip)
  index = lines.index("<key>#{key}</key>")
  return nil if index.nil?

  match = lines[index + 1].to_s.match(%r{\A<string>(.*)</string>\z})
  return nil if match.nil?

  # `&amp;` last, or an already-decoded `&` would be decoded twice.
  match[1].gsub("&lt;", "<").gsub("&gt;", ">").gsub("&quot;", '"')
          .gsub("&apos;", "'").gsub("&amp;", "&")
end

# CFBundleDisplayName and (on macOS) NSHumanReadableCopyright are NOT build
# settings in a pre-#281 fork — they are plist properties, measured on
# e773cfc:app/project.yml:41 and :86. So when the INFOPLIST_KEY_ form is absent,
# the value is read out of the plist the build itself named, at the path the
# build itself resolved: INFOPLIST_FILE relative to SRCROOT, never a path this
# command guessed.
def plist_lookup(settings, key, root)
  infoplist = settings["INFOPLIST_FILE"].to_s.strip
  srcroot   = settings["SRCROOT"].to_s.strip
  return nil if infoplist.empty? || srcroot.empty?

  path = File.expand_path(infoplist, srcroot)
  return nil unless File.file?(path)

  raw = plist_string(read_utf8(path), key)
  return nil if raw.nil?

  # A generated plist may hold a build-setting REFERENCE rather than a literal —
  # this repository's own app/iOS/Generated-Info.plist carries
  # <string>$(DISPLAY_NAME)</string>. Resolve it from the same dump; an
  # unresolvable reference becomes empty and is refused by name upstream, rather
  # than written into the xcconfig as the four characters "$(X)".
  match = raw.match(/\A\$\(([A-Za-z_][A-Za-z0-9_]*)\)\z/)
  return raw if match.nil?

  settings[match[1]].to_s.strip
end

def build_value(settings, setting_key, plist_key, scheme, root)
  value = settings[setting_key].to_s.strip
  value = plist_lookup(settings, plist_key, root).to_s.strip if value.empty? && !plist_key.nil?
  return value unless value.empty?

  sources = ["the build setting #{setting_key}"]
  sources << "#{plist_key} in the Info.plist the build named" unless plist_key.nil?
  fail_with 2, "scheme #{scheme} configuration #{CONFIGURATION} resolves no value for " \
               "#{sources.join(' or ')}. An identity value that resolves to nothing is what " \
               "ships an app with an empty CFBundleIdentifier (RESEARCH Pitfall 1), so this is a " \
               "refusal rather than a blank line in #{REL_IDENTITY}."
end

def resolve_identity(root, token)
  project_rel = "app/#{token}.xcodeproj"
  project_abs = File.join(root, project_rel)
  unless File.directory?(project_abs) && File.file?(File.join(project_abs, "project.pbxproj"))
    fail_with 4, "#{project_abs} is not a generated project (no project.pbxproj inside it). This " \
                 "command reads the fork's identity from what the BUILD resolves, not from the " \
                 "manifests, because a literal baked into a generated project shadows the " \
                 "manifest that was supposed to produce it. Generate it first — " \
                 "cd app && xcodegen generate — then re-run."
  end

  unless tool_available?("xcodebuild")
    fail_with 4, "xcodebuild not found (looked in #{tool_source}). The fork's current identity is " \
                 "read from xcodebuild -showBuildSettings and there is no second source for it."
  end

  PLATFORMS.each_with_object({}) do |platform, resolved|
    scheme = "#{token}-#{platform}"
    out, err, status = capture(
      [tool_path("xcodebuild"), "-project", project_rel, "-scheme", scheme,
       "-configuration", CONFIGURATION, "-showBuildSettings"], chdir: root
    )
    unless status.zero?
      fail_with 2, "xcodebuild -showBuildSettings exited #{status} for scheme #{scheme} " \
                   "configuration #{CONFIGURATION} in #{project_rel}: #{err.strip}"
    end

    # The ambiguity guard from tools/identity-parity.rb:530-535. If a scheme's
    # build action grew a second target, "the app's identity" is not a question
    # this dump answers and picking the first block would answer a different one.
    blocks = out.lines.count { |line| line.include?("Build settings for action") }
    unless blocks == 1
      fail_with 2, "expected exactly one target block for scheme #{scheme} configuration " \
                   "#{CONFIGURATION} in #{project_rel}, found #{blocks}. The read would be " \
                   "ambiguous, and this command will not guess which target's identity is the " \
                   "app's."
    end

    settings = {}
    out.lines.each do |line|
      key, separator, value = line.sub(/\A\s+/, "").chomp.partition(" = ")
      next if separator.empty?
      next unless key.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)

      settings[key] = value
    end

    # A build tool that silently substituted a default configuration would
    # otherwise be read as if it had answered the question that was asked.
    reported = settings["CONFIGURATION"]
    unless reported == CONFIGURATION
      fail_with 2, "configuration #{CONFIGURATION} was requested for scheme #{scheme} but the " \
                   "dump reports CONFIGURATION = #{reported.inspect}. Refusing to read a fork's " \
                   "identity out of a substituted configuration."
    end

    resolved[platform] = {
      "bundle_id"    => build_value(settings, "PRODUCT_BUNDLE_IDENTIFIER", nil, scheme, root),
      "product_name" => build_value(settings, "PRODUCT_NAME", nil, scheme, root),
      "display_name" => build_value(settings, "INFOPLIST_KEY_CFBundleDisplayName",
                                    "CFBundleDisplayName", scheme, root),
      "copyright"    => build_value(settings, "INFOPLIST_KEY_NSHumanReadableCopyright",
                                    "NSHumanReadableCopyright", scheme, root)
    }
  end
end

# A-05, measured rather than predicted. A pre-#281 renamed fork resolves TWO
# PRODUCT_NAME values because nothing sets it and Xcode defaults it to each
# target's own name, platform suffix included; a migrated tree resolves one.
def collapse_product_name(resolved, token)
  ios_raw   = resolved.fetch("iOS").fetch("product_name")
  macos_raw = resolved.fetch("macOS").fetch("product_name")
  ios       = ios_raw.sub(/-iOS\z/, "")
  macos     = macos_raw.sub(/-macOS\z/, "")

  unless ios == macos
    fail_with 2, "the two platforms resolve PRODUCT_NAME values that differ by more than the " \
                 "platform suffix: iOS #{ios_raw.inspect} (#{ios.inspect} without its suffix), " \
                 "macOS #{macos_raw.inspect} (#{macos.inspect} without its suffix). " \
                 "#{REL_IDENTITY} holds ONE APP_PRODUCT_NAME for both platforms, so a migration " \
                 "that picked one of these would rename the other platform's product to " \
                 "something it never was. Reconcile the two and re-run."
  end

  unless ios == token
    fail_with 2, "the build resolves PRODUCT_NAME #{ios.inspect} on both platforms while this " \
                 "tree's structure says #{token.inspect} (that token was read from " \
                 "#{REL_PROJECT_YML}, the @main struct and the generated project, and they " \
                 "agreed). A third opinion about this fork's identity is not one this command " \
                 "reconciles: fix the disagreement by hand and re-run."
  end

  ios
end

def announce_product_name_collapse(resolved, collapsed)
  ios_raw   = resolved.fetch("iOS").fetch("product_name")
  macos_raw = resolved.fetch("macOS").fetch("product_name")
  say "==== PRODUCT_NAME COLLAPSES TO ONE VALUE (A-05) ===="
  say "  before, iOS:   PRODUCT_NAME = #{ios_raw}"
  say "  before, macOS: PRODUCT_NAME = #{macos_raw}"
  say "  after, both:   APP_PRODUCT_NAME = #{collapsed}"
  say "Nothing in this tree sets PRODUCT_NAME, so Xcode defaulted it to each target's own name,"
  say "platform suffix included. A migrated tree resolves one value on both platforms, so"
  say "the built bundle's filename and executable name change on at least one platform; " \
      "see docs/MIGRATING-FROM-RENAME.md before migrating a fork with a live App Store listing"
  say "This command reports the change and stops there. It does not judge the consequences for"
  say "your listing on your behalf, and it does not speak for Apple."
end

# The four values, with the three that are not PRODUCT_NAME required to AGREE
# across the two platforms — app/Identity.xcconfig holds one of each, which is
# D-44's Universal Purchase shape, and a fork whose platforms disagree is a fork
# this command must not silently pick a winner for.
def identity_values(resolved, collapsed)
  ios = resolved.fetch("iOS")
  mac = resolved.fetch("macOS")
  {
    "BUNDLE_ID"        => agreed(ios, mac, "bundle_id", "PRODUCT_BUNDLE_IDENTIFIER"),
    "APP_PRODUCT_NAME" => collapsed,
    "DISPLAY_NAME"     => agreed(ios, mac, "display_name", "CFBundleDisplayName"),
    "COPYRIGHT"        => agreed(ios, mac, "copyright", "NSHumanReadableCopyright")
  }
end

def agreed(ios, mac, key, label)
  left  = ios.fetch(key)
  right = mac.fetch(key)
  return left if left == right

  fail_with 2, "the two platforms resolve different values for #{label}: iOS #{left.inspect}, " \
               "macOS #{right.inspect}. #{REL_IDENTITY} defines ONE value for both platforms, so " \
               "this command will not pick a winner. Reconcile the manifests and re-run."
end

# --- writing app/Identity.xcconfig, and proving the write ---------------------

def identity_xcconfig_body(values, resolved)
  ios_raw   = resolved.fetch("iOS").fetch("product_name")
  macos_raw = resolved.fetch("macOS").fetch("product_name")
  <<~XCCONFIG
    // app/Identity.xcconfig — the single tracked identity source of truth.
    //
    // Written by tools/migrate-identity.rb from this fork's own RESOLVED build
    // settings (xcodebuild -showBuildSettings), not from its manifests: a literal
    // baked into a generated project shadows the manifest that was supposed to
    // produce it, and the build is what ships.
    //
    // Editing the four values below rebrands the app on both platforms. XcodeGen
    // (configFiles:), Tuist (.settings(configurations:)) and xcodebuild all read
    // this file natively — there is no parser in between, which is what lets
    // xcodebuild -showBuildSettings report these resolved values directly.
    //
    // Format rules: values are UNQUOTED (quotes would land in the plist as
    // literal characters); comments are a double slash; the directive at the
    // bottom is a directive, not a comment.

    // Feeds PRODUCT_BUNDLE_IDENTIFIER on both app targets (one shared bundle id).
    BUNDLE_ID        = #{values.fetch('BUNDLE_ID')}

    // Feeds PRODUCT_NAME on the two APP targets only, through a per-target
    // PRODUCT_NAME = $(APP_PRODUCT_NAME) in each manifest. Deliberately NOT a
    // bare project-level PRODUCT_NAME: that leaks into every target, including
    // the test bundles, and the two generators then disagree.
    //
    // BEFORE THIS MIGRATION this tree resolved #{ios_raw} on iOS and
    // #{macos_raw} on macOS, because nothing set PRODUCT_NAME and Xcode
    // defaulted it to each target's own name. It now resolves one value on both
    // platforms, so the built bundle's filename and executable name change on at
    // least one platform. See docs/MIGRATING-FROM-RENAME.md.
    APP_PRODUCT_NAME = #{values.fetch('APP_PRODUCT_NAME')}

    // Feeds CFBundleDisplayName — the name under the icon — on both platforms.
    DISPLAY_NAME     = #{values.fetch('DISPLAY_NAME')}

    // Feeds NSHumanReadableCopyright. Set in both manifests' plist blocks rather
    // than through an INFOPLIST_KEY_ build setting: that form reaches the bundle
    // only under GENERATE_INFOPLIST_FILE = YES, which app targets carrying their
    // own Info.plist do not set (observed: the setting resolved, the built iOS
    // plist had no key).
    COPYRIGHT        = #{values.fetch('COPYRIGHT')}

    // The Apple Team ID (DEVELOPMENT_TEAM) lives in #{REL_LOCAL}, which is
    // gitignored and is never tracked. On a fresh clone the include below is
    // silent and DEVELOPMENT_TEAM is undefined — not empty, undefined: no line
    // for it appears in -showBuildSettings at all.
    #include? "Local.xcconfig"
  XCCONFIG
end

def write_identity_xcconfig(root, values, resolved)
  path = File.join(root, REL_IDENTITY)

  # Three shapes that would survive a "is it non-empty" check and still ship the
  # wrong string. The double slash opens a comment at ANY position in an xcconfig
  # value, so a value carrying one reads back TRUNCATED (that is UL-032 and
  # T-03-06, both observed in this repository); a $( reference expands against
  # the resolved set; a newline stops being one line.
  values.each do |key, value|
    if value.include?("//")
      fail_with 2, "#{key} resolves to #{value.inspect}, which contains a double slash. An " \
                   "xcconfig treats that as a comment at any position, so the value would read " \
                   "back truncated — non-empty, and wrong. Change it in the manifests and re-run."
    end
    if value.include?("$(")
      fail_with 2, "#{key} resolves to #{value.inspect}, which still carries an unresolved " \
                   "build-setting reference. Writing it would put a reference where a value " \
                   "belongs and resolve to something different on the next build."
    end
    if value.match?(/[\r\n]/)
      fail_with 2, "#{key} resolves to a value containing a line break (#{value.inspect}). An " \
                   "xcconfig assignment is one line, so this cannot be written faithfully."
    end
  end

  # binwrite, never write: COPYRIGHT carries © (U+00A9), and with LANG unset
  # Ruby's default external encoding is US-ASCII, where a transcoding write
  # raises instead of producing the byte. Commit 3b1efb9 is this repository's own
  # instance of inheriting the locale.
  File.binwrite(path, identity_xcconfig_body(values, resolved))

  # THE READ-BACK. Through Xcconfig.value — what Xcode would resolve — and
  # compared to the value that was intended, not merely checked for emptiness: a
  # writer whose output only the writer can read is the shape UL-044 was made of,
  # and equality is what catches a value that came back truncated or expanded
  # rather than absent. `nil` (never assigned) and "" (assigned but empty) are
  # both failures here, exactly as bin/preflight-identity.rb treats them.
  values.each_key do |key|
    resolved_back = begin
      Xcconfig.value(path, key)
    rescue Xcconfig::MissingInclude => e
      # NAMED class. The file was just written and its only include is optional,
      # so this can only fire for an include cycle reached through a Local.xcconfig
      # the forker wrote — which is a broken tree, not an empty key.
      fail_with 2, "#{path} was written but cannot be resolved: #{e.message}. Fix the include " \
                   "chain and re-run; the tree has been rolled back."
    end

    intended = values.fetch(key)
    next if resolved_back == intended

    fail_with 2, "#{path} was written but #{key} reads back through bin/lib/xcconfig.rb as " \
                 "#{resolved_back.inspect}, not #{intended.inspect}. The write was not faithful " \
                 "and this command will not report a migration it cannot verify."
  end

  path
end

# --- moving the Apple Team ID behind a git-confirmed ignore gate ---------------

YAML_TEAM_LINE  = /\A(\s*)DEVELOPMENT_TEAM:\s*(.*)\z/
SWIFT_TEAM_LINE = /\A(\s*)"DEVELOPMENT_TEAM"\s*:\s*"([^"]*)"\s*,?\s*\z/

# A YAML scalar, quoted or bare, with a trailing comment removed. Not a YAML
# parser and not trying to be one: the manifest line being read is
# `DEVELOPMENT_TEAM: "TEAM_ID_PLACEHOLDER"   # …`, measured on
# e773cfc:app/project.yml:25, and a gem would cost review-notes.yml its
# bundler-cache: false for one line of one file.
def yaml_scalar(raw)
  raw = raw.strip
  return Regexp.last_match(1) if raw.match(/\A"([^"]*)"/)
  return Regexp.last_match(1) if raw.match(/\A'([^']*)'/)

  raw.sub(/\s+#.*\z/, "").strip
end

def find_development_team(path, kind)
  return nil unless File.file?(path)

  read_utf8(path).lines.each_with_index do |line, index|
    match = (kind == :yaml ? YAML_TEAM_LINE : SWIFT_TEAM_LINE).match(line.chomp)
    next if match.nil?

    return [index, (kind == :yaml ? yaml_scalar(match[2]).to_s : match[2])]
  end
  nil
end

# Removes the assignment, and with it any contiguous comment block immediately
# above that mentions DEVELOPMENT_TEAM — otherwise the forker's tree keeps a
# comment saying the value is substituted by a script that no longer substitutes
# anything, which is a false instruction left behind by a correctness fix. One
# truthful comment goes back in its place, at the same indentation.
def strip_development_team(path, index, relative)
  lines  = read_utf8(path).lines
  indent = lines[index][/\A\s*/]
  marker = relative.end_with?(".yml") ? "#" : "//"

  block = []
  probe = index - 1
  while probe >= 0 && lines[probe].strip.start_with?(marker)
    block.unshift(lines[probe])
    probe -= 1
  end
  first = block.join.include?("DEVELOPMENT_TEAM") ? index - block.length : index

  lines[first..index] = ["#{indent}#{marker} DEVELOPMENT_TEAM is deliberately absent here: the " \
                         "Apple Team ID resolves from gitignored #{REL_LOCAL}.\n"]
  File.binwrite(path, lines.join)
end

# bin/rename.sh Step H's second refusal, and the one place this command departs
# from the plan's literal instruction — on a measurement, recorded here.
#
# The rule is unchanged: the Apple Team ID is written only to a path GIT confirms
# is ignored, and `git check-ignore -q` is the arbiter. 0 = ignored, 1 = not
# ignored, 128 = fatal; a 128 is evidence for NEITHER side and is a refusal
# (test/identity_test.rb:338-339 states that rule, and this is the write it
# exists to protect — T-05-11).
#
# What changed is what happens on a 1. MEASURED 2026-09-03:
#
#   git show e773cfc:.gitignore  ->  no app/Local.xcconfig row, at all
#
# app/Local.xcconfig is a POST-#281 concept, so no pre-#281 fork has a row for
# it — and a command that refuses on a missing row would refuse every single tree
# in the population it exists to serve. So it CREATES the condition and then asks
# git again rather than asking once and giving up. git is still the arbiter; this
# command just stops requiring the forker to do its setup by hand.
#
# The refusal is still reachable, and on the case that actually matters. Also
# measured, on a scratch repository:
#
#   file TRACKED   + matching .gitignore row  ->  check-ignore exits 1
#   file untracked + matching row             ->  check-ignore exits 0
#   file untracked + no row                   ->  check-ignore exits 1
#
# git reports a TRACKED path as not-ignored whatever .gitignore says. A fork that
# has already committed app/Local.xcconfig therefore still gets a refusal, which
# is exactly right: writing a Team ID into a tracked file puts it in the next
# commit, and adding a row would not change that.
def check_ignore(root)
  _, err, status = capture(["git", "check-ignore", "-q", "--", REL_LOCAL], chdir: root)
  [status, err]
end

def ensure_local_is_ignored(root)
  status, err = check_ignore(root)
  return if status.zero?

  unless status == 1
    fail_with 4, "git check-ignore -q -- #{REL_LOCAL} exited #{status} in #{root} (#{err.strip}). " \
                 "Exit 0 means ignored and exit 1 means not ignored; anything else is a fatal git " \
                 "error and is evidence for NEITHER, so it is a refusal. Nothing was written."
  end

  # .gitignore is TRACKED, so this edit is covered by the rollback's
  # git reset --hard and needs no snapshot of its own.
  gitignore = File.join(root, ".gitignore")
  existing  = File.file?(gitignore) ? read_utf8(gitignore) : ""
  body      = existing
  body      = "#{body}\n" unless body.empty? || body.end_with?("\n")
  body     += "\n# The Apple Team ID lives here and must never be committed.\n#{REL_LOCAL}\n"
  File.binwrite(gitignore, body)
  say "added #{REL_LOCAL} to .gitignore — git did not consider that path ignored, and a"
  say "  pre-#281 fork has no row for it because the file is a post-#281 concept."

  status, err = check_ignore(root)
  return if status.zero?

  fail_with 4, "git check-ignore -q -- #{REL_LOCAL} still exits #{status} in #{root} after a " \
               "matching .gitignore row was added (#{err.strip}). The usual cause is that the " \
               "path is already TRACKED: git reports a tracked path as not-ignored whatever " \
               ".gitignore says, and writing the Apple Team ID into a tracked file would put it " \
               "in the next commit. Remove it from the index first " \
               "(git rm --cached #{REL_LOCAL}), then re-run. Nothing was written."
end

def move_team_id(root)
  found = {
    REL_PROJECT_YML   => find_development_team(File.join(root, REL_PROJECT_YML), :yaml),
    REL_PROJECT_SWIFT => find_development_team(File.join(root, REL_PROJECT_SWIFT), :swift)
  }
  present = found.reject { |_, hit| hit.nil? }

  if present.empty?
    say "no DEVELOPMENT_TEAM assignment in #{REL_PROJECT_YML} or #{REL_PROJECT_SWIFT}; there is"
    say "  no Apple Team ID here for this command to move. Nothing was written to #{REL_LOCAL}."
    return nil
  end

  team_ids = present.values.map(&:last).uniq
  if team_ids.length > 1
    fail_with 2, "the two manifests disagree about DEVELOPMENT_TEAM (" +
                 present.map { |rel, (_, value)| "#{rel} => #{value.inspect}" }.join("; ") +
                 "). One of them signs a build you did not mean to sign, and this command will " \
                 "not choose between them. Reconcile the two and re-run."
  end

  team_id = team_ids.first
  # bin/rename.sh Step H's first refusal, copied in intent: a fork that never
  # supplied a Team ID still carries the literal, and moving THAT into
  # Local.xcconfig would relocate a placeholder while reporting a Team ID move.
  if team_id == TEAM_ID_PLACEHOLDER
    fail_with 4, "#{present.keys.join(' and ')} still carr#{present.length == 1 ? 'ies' : 'y'} " \
                 "the unsubstituted literal #{TEAM_ID_PLACEHOLDER}. There is no Apple Team ID in " \
                 "this tree to move. Put your Team ID in #{REL_LOCAL} yourself " \
                 "(DEVELOPMENT_TEAM = <ten characters>), or set it in the manifests first, then " \
                 "re-run."
  end
  if team_id.empty?
    fail_with 4, "#{present.keys.join(' and ')} assign#{present.length == 1 ? 's' : ''} " \
                 "DEVELOPMENT_TEAM with no value. An empty Team ID is not a Team ID and moving " \
                 "it would report a move that did nothing."
  end

  ensure_local_is_ignored(root)

  local_path = File.join(root, REL_LOCAL)
  existing   = File.file?(local_path) ? read_utf8(local_path) : nil
  current    = existing.nil? ? nil : Xcconfig.own(local_path)["DEVELOPMENT_TEAM"]
  if !current.nil? && !current.empty? && current != team_id
    fail_with 4, "#{local_path} already assigns DEVELOPMENT_TEAM = #{current.inspect} while the " \
                 "manifests say #{team_id.inspect}. This command will not overwrite a Team ID a " \
                 "forker put there by hand. Reconcile the two and re-run."
  end

  # Snapshot BEFORE the write. git cannot restore a gitignored file, so this is
  # the only thing standing between a mid-flight failure and a rewritten
  # Local.xcconfig that the rollback would report as restored.
  snapshot_gitignored(local_path)

  if current == team_id
    say "#{REL_LOCAL} already assigns the same DEVELOPMENT_TEAM; leaving it as it is."
  else
    body = existing.to_s
    body = "#{body}\n" unless body.empty? || body.end_with?("\n")
    body = "#{body}\n" unless body.empty?
    body += "// The Apple Team ID, moved out of the tracked manifests by\n" \
            "// tools/migrate-identity.rb. This file is gitignored and must stay that way.\n" \
            "DEVELOPMENT_TEAM = #{team_id}\n"
    File.binwrite(local_path, body)
  end

  present.each { |relative, (index, _)| strip_development_team(File.join(root, relative), index, relative) }
  local_path
end

# --- the mutation phase -------------------------------------------------------

def perform_migration(root:, token:)
  # Read-only, and deliberately BEFORE the latch: a tree whose identity cannot be
  # read has not been touched, and a rollback here would run git reset --hard
  # against a tree this command never wrote to.
  resolved  = resolve_identity(root, token)
  collapsed = collapse_product_name(resolved, token)
  announce_product_name_collapse(resolved, collapsed)
  values = identity_values(resolved, collapsed)

  # Everything from this line on can be undone, and must be. The traps have been
  # armed since before the gates ran; THIS is the line that lets them do
  # anything, and a failure above it lands in rollback as a no-op.
  @mutation_started = true

  begin
    identity_path = write_identity_xcconfig(root, values, resolved)
    say "wrote #{identity_path} and verified all four values by reading them back through " \
        "bin/lib/xcconfig.rb"
    fail_after_stage("xcconfig-write")

    local_path = move_team_id(root)
    say "moved the Apple Team ID into #{local_path} and removed it from both manifests" unless local_path.nil?
    fail_after_stage("team-id-move")

    disarm_rollback
  rescue FixtureInjectedFailure => e
    outcome = rollback
    fail_with 4, "#{e.message} This is the injected-failure fixture knob and not a real failure. " \
                 "Rollback outcome: #{outcome}."
  rescue StandardError => e
    # NOT a silent tolerance: the class, the message and the full backtrace are
    # printed, the tree is rolled back, and the refusal carries a code from the
    # contract. Ruby would otherwise exit 1 on an uncaught exception, and exit 1
    # is "you called me wrong" — reported from a tree that is half rewritten.
    warn "#{FAIL_PREFIX} #{e.class}: #{e.message}"
    warn e.backtrace.join("\n") unless e.backtrace.nil?
    outcome = rollback
    fail_with 4, "the migration raised #{e.class} (#{e.message}) and was rolled back " \
                 "(#{outcome}); the backtrace is above. Nothing about this tree's migration " \
                 "state should be inferred from a run that ended this way."
  ensure
    # Idempotent, and a no-op after disarm_rollback. This is the arm bash gets
    # from `trap ... EXIT`.
    rollback
  end

  # --- the plan boundary ------------------------------------------------------
  #
  # The value half is written and verified. The structural half is plan 05-04's,
  # so this is NOT a success and does not exit 0. The rollback is disarmed above
  # deliberately rather than by omission: discarding a verified, correct value
  # half in order to report a tidier outcome would throw away the work and tell
  # the operator less. What is left behind is named, and so is the way back.
  say "==== PARTIAL MIGRATION LEFT IN PLACE ===="
  say "what was migrated:"
  say "  #{REL_IDENTITY} now defines #{REQUIRED_VARS.join(', ')}, every one of them read back"
  say "    through bin/lib/xcconfig.rb and compared to the value the build reported"
  say "  the Apple Team ID now lives only in #{REL_LOCAL}, which git confirmed is ignored"
  say "what was NOT migrated:"
  say "  the structural un-rename (#{token} -> #{MIGRATED_TOKEN}) and the manifest rewiring onto"
  say "    $(VAR) references land in plan 05-04. Until they do, the manifests still name"
  say "    #{token} and still carry identity literals, so this tree is partially migrated."
  say "to undo everything this run did:  git reset --hard HEAD && git clean -fd"
  fail_with 4, "#{root} is partially migrated: the value half of the migration is written and " \
               "verified, and the structural half lands in plan 05-04. This is deliberately not " \
               "an exit 0 — a tree in this state must not be shipped. Undo it with " \
               "git reset --hard HEAD && git clean -fd."
end

# Traps armed BEFORE the gates, the way bin/rename.sh arms its at file scope.
# Every failure from here on reaches rollback; the MUTATION_STARTED latch, still
# unset, is what makes all of them no-ops until the mutation actually begins.
arm_rollback(root)

# GATES, in bin/rename.sh:904-1000's order. The three-state dispatch already ran,
# far above, so a second invocation on a dirty post-migration tree still resolves
# correctly rather than being stopped by the clean-tree gate first.
gate_xcodegen_present
gate_clean_tree(root)
gate_on_main(root)

perform_migration(root: root, token: token)
