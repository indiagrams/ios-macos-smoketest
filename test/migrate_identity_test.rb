#!/usr/bin/env ruby
# frozen_string_literal: true

# Unit test for tools/migrate-identity.rb — three-state detection, the exit-code
# contract, and the argv parser (IDENT-14, D-70).
#
# WHY THIS EXISTS
#
# A migration that reports success without having looked at the tree is this
# project's signature failure mode, observed rather than imagined. Upstream's
# post-#281 `check_idempotency` keys on ONE signal (app/Identity.xcconfig
# exists), which is true post-#281 and false pre-#281 — so on exactly the tree
# this migration exists to serve it answers "not migrated" for the right reason
# and "migrated" for the wrong one. And bin/rename.sh's own three-state detector
# returns a bare 0/1/2 with no message at all, so a partial tree is reported by a
# number. D-70 rejected a silent idempotent exit 0 BY NAME: it is
# indistinguishable from a migration that did nothing because it could not see
# the fork's state.
#
# So every assertion below checks the exit code AND the message together. A
# command that exits 3 on a partially-migrated tree while naming nothing has
# satisfied the number and defeated the point; `assert_exit` fails it.
#
# THE STATES, AND WHY EACH SIGNAL IS SPELLED OUT HERE
#
#   never-migrated       none of the four signals present  -> exit 0 (--dry-run)
#   already fully mig.   all four present                  -> exit 0, LOUD
#   partially migrated   any mixture                       -> exit 3, naming each
#
# Every constant below is duplicated deliberately rather than derived from the
# file under test — the rule test/identity_test.rb:56-60 states: a test that
# reads its expectations out of its subject accepts whatever that subject
# happens to say, which is not a test. The four signal labels, the five exit
# codes and the three state names are written out here by hand, and a rewording
# on either side is meant to break this file.
#
# FAILURE-LINE CONTRACT
#
# This file adopts test/identity_test.rb's one-line contract —
#
#     FAIL <group> <path>: <message>
#
# — and NOT the `✗` shape from test/parser_test.rb. The choice is stated once,
# here, and kept: the red controls that drive this suite against a deliberately
# broken command grep for `^FAIL`, and a two-line failure would make every one of
# them vacuous. Detail lines (expected/actual) follow the FAIL line, indented,
# and never begin with FAIL.
#
# HOW IT INVOKES THE COMMAND
#
# Through the interpreter running THIS file (RbConfig.ruby), never through the
# command's `#!/usr/bin/env ruby` shebang. Running the suite under 4.0.6 while
# the subprocess silently resolved PATH's ruby — which on a bare shell here is
# /usr/bin/ruby 2.6.10 — would make "green under both pinned interpreters" a
# claim about one interpreter. Executability is asserted separately, by mode.
#
# Runnable locally, from the repository root, under BOTH pinned interpreters —
# and it must pass under both, spelled out because on this machine ambient
# `ruby` IS 3.3 and the second path is the one that gets skipped:
#   /opt/homebrew/opt/ruby@3.3/bin/ruby test/migrate_identity_test.rb
#   /opt/homebrew/opt/ruby@4.0/bin/ruby test/migrate_identity_test.rb
# Never /usr/bin/ruby (2.6.10).
#
# CI caller: .github/workflows/migrate.yml, added by plan 05-05. Until then this
# suite has no CI caller and is run by hand — stated out loud rather than left
# to be discovered, because a suite nobody runs is not a gate.
#
# Ruby core only, three `require`s, no gem — which is what lets a caller in the
# `review notes` job keep `bundler-cache: false`. Every shell-out is an explicit
# argv array, never a shell string. No broad rescue: the only rescue in this file
# names Errno::ENOENT, and it exists to tell "the command is not there" apart
# from "the command failed".

require "tmpdir"
require "fileutils"
require "rbconfig"

ROOT = File.expand_path("..", __dir__)

# The subject. Its path is a decision recorded in the file's own header:
# fork-owned tooling lives in tools/, because bin/refork-smoketest.sh deletes
# this repository and recreates it from the template (AGENTS.md:271).
COMMAND_RELATIVE = "tools/migrate-identity.rb"
COMMAND = File.join(ROOT, COMMAND_RELATIVE)

# The interpreter this file is running under, so the subprocess is the same
# Ruby. See "HOW IT INVOKES THE COMMAND" above.
RUBY = RbConfig.ruby

# ─── the exit-code contract, duplicated deliberately ─────────────────────────
EXIT_OK       = 0  # migrated, or already fully migrated (reported LOUDLY)
EXIT_ARGV     = 1  # unknown or malformed argv
EXIT_UNKNOWN  = 2  # not a tree this command understands
EXIT_PARTIAL  = 3  # partially migrated — names every mixed signal
EXIT_MUTATION = 4  # a mutation-phase refusal (plan 05-03)

# ─── the three state names, duplicated deliberately ──────────────────────────
STATE_NEVER   = "never-migrated"
STATE_FULL    = "already fully migrated"
STATE_PARTIAL = "partially migrated"

# ─── the four D-70 signals, measured across seven refs (05-RESEARCH.md:515) ──
# These strings are the CONTRACT, not a description of it: the command prints
# them and this file asserts them, and neither derives them from the other.
SIGNAL_IDENTITY     = "app/Identity.xcconfig exists"
SIGNAL_APP_SWIFT    = "app/Shared/App.swift exists"
SIGNAL_PROJECT_NAME = "app/project.yml name: is App"
SIGNAL_ENTITLEMENTS = "app/iOS/App.entitlements exists"
ALL_SIGNALS = [SIGNAL_IDENTITY, SIGNAL_APP_SWIFT, SIGNAL_PROJECT_NAME, SIGNAL_ENTITLEMENTS].freeze

# The four identity variables a migrated app/Identity.xcconfig must define with
# a non-empty value. Same list as bin/preflight-identity.rb's REQUIRED_VARS,
# written out again here for the same reason.
REQUIRED_VARS = %w[BUNDLE_ID APP_PRODUCT_NAME DISPLAY_NAME COPYRIGHT].freeze

# The fixture's structural token. Never a real fork name: a run against a
# fixture must be unmistakable in a log.
TOKEN = "MigrateFixture"

# ─── harness ─────────────────────────────────────────────────────────────────

@failures = 0
@checks   = 0

def fail_line(group, message)
  # One line, always. A message that put the group on one line and the detail on
  # another would make every `^FAIL <group>` control vacuous.
  puts "FAIL #{group} #{COMMAND_RELATIVE}: #{message.to_s.gsub(/\s*\n\s*/, ' ')}"
  @failures += 1
end

def assert(condition, group, label)
  @checks += 1
  if condition
    puts "  ✓ #{group} #{label}"
  else
    fail_line(group, label)
  end
end

# Runs an argv array from the repository root, returning [combined stdout+stderr,
# exit status]. Argv array only — a shell string would let a path with a space or
# a metacharacter change what is executed. Returns [nil, nil] when the command
# itself is not there, which is a THIRD outcome and must not read as a failed
# assertion about a command that ran.
def run(argv)
  out = IO.popen(argv, "r", err: [:child, :out], chdir: ROOT, &:read)
  [out.to_s, $?.exitstatus]
rescue Errno::ENOENT
  [nil, nil]
end

# The whole point of D-70, in one helper.
#
# Three distinguishable failure modes, because each is a different defect:
#
#   1. command not found        — the subject is absent; every other assertion
#                                 in this file is meaningless
#   2. wrong exit code          — the command decided something else
#   3. right code, wrong message— the command exited correctly while naming
#                                 nothing, which is exactly the silent-success
#                                 shape D-70 rejects and the reason this helper
#                                 exists instead of a bare exit-code check
#
# `needles` is a String or an Array of Strings; every one must appear in the
# combined stdout+stderr.
def assert_exit(argv, expected_code, needles, group, label)
  @checks += 1
  needles = Array(needles)
  out, code = run([RUBY, COMMAND, *argv])

  if code.nil?
    fail_line(group, "#{label} — command not found at #{COMMAND}")
    return
  end

  unless code == expected_code
    fail_line(group, "#{label} — expected exit #{expected_code}, got #{code}")
    puts "    argv:   #{argv.inspect}"
    puts "    output: #{out.to_s.strip.inspect}"
    return
  end

  absent = needles.reject { |n| out.include?(n) }
  unless absent.empty?
    fail_line(group, "#{label} — exit #{code} was right but the message named nothing")
    puts "    expected message to contain: #{absent.map(&:inspect).join(', ')}"
    puts "    actual message:              #{out.to_s.strip.inspect}"
    return
  end

  puts "  ✓ #{group} #{label}"
end

# ─── fixture builders ────────────────────────────────────────────────────────
#
# Every tree is built inside Dir.mktmpdir and every invocation that reads a tree
# passes an explicit --root at it. Nothing in this file points the command at the
# repository root: a detection bug that mistook this repository for a migration
# target would, once plan 05-03 lands the mutation half, rewrite the developer's
# own checkout.
#
# binwrite, not write: with LANG unset Ruby sets Encoding.default_external to
# US-ASCII, and writing the © (U+00A9) in the COPYRIGHT fixture below through a
# transcoding write raises instead of producing the byte. Commit 3b1efb9 is this
# repository's own instance of inheriting the locale (UL-012).

def write_file(dir, relative, text)
  path = File.join(dir, relative)
  FileUtils.mkdir_p(File.dirname(path))
  File.binwrite(path, text)
  path
end

def project_yml(name)
  <<~YML
    # Fixture manifest. Only the `name:` line is read by the detector.
    name: #{name}

    targets:
      #{name}-iOS:
        type: application
  YML
end

def main_swift(token)
  <<~SWIFT
    import SwiftUI

    @main
    struct #{token}Main: App {
        var body: some Scene { WindowGroup { Text("fixture") } }
    }
  SWIFT
end

ENTITLEMENTS = <<~XML
  <?xml version="1.0" encoding="UTF-8"?>
  <plist version="1.0"><dict/></plist>
XML

def identity_xcconfig(omit: [])
  rows = {
    "BUNDLE_ID"        => "com.indiagram.migratefixture.ios",
    "APP_PRODUCT_NAME" => "MigrateFixture",
    "DISPLAY_NAME"     => "Migrate Fixture",
    "COPYRIGHT"        => "Copyright © 2026 Fixture. All rights reserved."
  }
  body = rows.reject { |k, _| omit.include?(k) }
             .map { |k, v| "#{k.ljust(16)} = #{v}" }
             .join("\n")
  "// fixture identity — not a release configuration\n#{body}\n"
end

# All four signals absent: a pre-#281 fork that ran the rename and has never
# been migrated. This is the population IDENT-14 serves.
def build_never_migrated(dir)
  write_file(dir, "app/project.yml", project_yml(TOKEN))
  write_file(dir, "app/Shared/#{TOKEN}.swift", main_swift(TOKEN))
  write_file(dir, "app/iOS/#{TOKEN}.entitlements", ENTITLEMENTS)
  dir
end

# All four signals present: the shape this repository's HEAD is in.
def build_fully_migrated(dir, omit_vars: [])
  write_file(dir, "app/project.yml", project_yml("App"))
  write_file(dir, "app/Shared/App.swift", main_swift("App"))
  write_file(dir, "app/iOS/App.entitlements", ENTITLEMENTS)
  write_file(dir, "app/Identity.xcconfig", identity_xcconfig(omit: omit_vars))
  dir
end

# A mixture: the xcconfig landed, the structure did not. The state D-70 exists
# to refuse — and the one a single-signal detector calls "already migrated".
def build_partially_migrated(dir)
  write_file(dir, "app/project.yml", project_yml(TOKEN))
  write_file(dir, "app/Shared/#{TOKEN}.swift", main_swift(TOKEN))
  write_file(dir, "app/iOS/#{TOKEN}.entitlements", ENTITLEMENTS)
  write_file(dir, "app/Identity.xcconfig", identity_xcconfig)
  dir
end

# `git init` only — no commit, no config, no network. Used by the one case that
# has to reach the mutation-phase refusal, which is gated on the tree being a git
# repository because the rollback D-70 requires is a git operation.
def git_init(dir)
  IO.popen(["git", "init", "-q", dir], "r", err: [:child, :out], &:read)
  $?.exitstatus.zero? && File.exist?(File.join(dir, ".git"))
end

# ─── Preconditions: fail loudly and specifically if the subject is absent ─────
#
# This is the RED assertion. Before tools/migrate-identity.rb lands, this file
# must say WHICH path is missing, on one FAIL line, and exit 1 — never an
# Errno::ENOENT backtrace out of IO.popen, which would be a stack trace where a
# named refusal belongs.

missing = []
if !File.exist?(COMMAND)
  missing << "not found at #{COMMAND} — plan 05-02 Task 2 has not landed yet"
elsif !File.executable?(COMMAND)
  missing << "present at #{COMMAND} but not executable (expected mode 100755)"
end

if missing.empty?
  help_out, help_code = run([RUBY, COMMAND, "--help"])
  if help_code.nil?
    missing << "could not be executed at #{COMMAND}"
  elsif help_code != EXIT_OK
    missing << "--help exited #{help_code}, expected #{EXIT_OK} (output: #{help_out.to_s.strip.inspect})"
  elsif !help_out.include?("migrate-identity")
    missing << "--help printed no usage line naming migrate-identity (output: #{help_out.to_s.strip.inspect})"
  end
end

unless missing.empty?
  missing.each { |m| puts "FAIL M0 #{COMMAND_RELATIVE}: #{m}" }
  puts
  puts "FAILED (#{missing.length} precondition(s) unmet) — this is the RED half of plan 05-02"
  exit 1
end

# ─── M1: argv is parsed, and unknown argv is REJECTED, never ignored ─────────

puts "M1 — argv: a typo must not look like a successful run:"

assert_exit ["--help"], EXIT_OK, ["usage:", "migrate-identity", "--root", "--dry-run"],
            "M1", "--help exits 0 and prints the usage line"

assert_exit ["--bogus", "--dry-run"], EXIT_ARGV, ["--bogus", "usage:"],
            "M1", "an unknown argument exits 1 naming the argument and the usage"

assert_exit ["--root"], EXIT_ARGV, ["--root requires a PATH argument", "usage:"],
            "M1", "--root with no value exits 1 naming the requirement"

assert_exit ["--root", "--dry-run"], EXIT_ARGV, ["--root requires a PATH argument"],
            "M1", "--root swallowing the next flag as its value exits 1"

assert_exit ["--root", "/a", "--root", "/b", "--dry-run"], EXIT_ARGV,
            ["--root given more than once", "usage:"],
            "M1", "--root given twice exits 1 rather than picking one"

# ─── M2: a tree this command does not understand is a DISTINCT outcome ───────
#
# Exit 2 is the tools/asc-probe.rb idiom restated at bin/preflight-identity.rb:32-48:
# "not found" is a different answer from "checked and wrong", and it gets its own
# code so a caller can never read one as the other.

puts "M2 — exit 2: not a tree this command understands:"

Dir.mktmpdir("migrate-shape") do |tmp|
  absent = File.join(tmp, "no-such-tree")
  assert_exit ["--root", absent, "--dry-run"], EXIT_UNKNOWN, [absent, "not found", "cwd"],
              "M2", "a --root that does not exist exits 2 naming the absolute path and the cwd"

  regular = write_file(tmp, "a-file", "not a tree\n")
  assert_exit ["--root", regular, "--dry-run"], EXIT_UNKNOWN, [regular, "is not a directory", "cwd"],
              "M2", "a --root that is a regular file exits 2 naming what it is"

  bare = File.join(tmp, "bare")
  FileUtils.mkdir_p(bare)
  assert_exit ["--root", bare, "--dry-run"], EXIT_UNKNOWN, [bare, "app/project.yml", "cwd"],
              "M2", "a directory with no app/project.yml exits 2 naming the manifest"
end

# ─── M3: the three D-70 states, each exiting distinguishably ─────────────────

puts "M3 — three states, three exits, every one of them named:"

Dir.mktmpdir("migrate-never") do |tmp|
  build_never_migrated(tmp)
  assert_exit ["--root", tmp, "--dry-run"], EXIT_OK, [STATE_NEVER, TOKEN],
              "M3", "a never-migrated tree exits 0 in --dry-run naming the state and the token"
end

Dir.mktmpdir("migrate-full") do |tmp|
  build_fully_migrated(tmp)
  assert_exit ["--root", tmp, "--dry-run"], EXIT_OK, [STATE_FULL, *ALL_SIGNALS],
              "M3", "a fully-migrated tree exits 0 LOUDLY naming all four satisfied signals"
end

Dir.mktmpdir("migrate-partial") do |tmp|
  build_partially_migrated(tmp)
  # The comma-separated list is asserted as ONE needle, in order: a message that
  # named only the first mixed signal would pass three separate `include?`
  # checks against a list it never printed.
  mixed = [SIGNAL_APP_SWIFT, SIGNAL_PROJECT_NAME, SIGNAL_ENTITLEMENTS].join(", ")
  assert_exit ["--root", tmp, "--dry-run"], EXIT_PARTIAL,
              [STATE_PARTIAL, "satisfied signal(s): #{SIGNAL_IDENTITY}", "unsatisfied signal(s): #{mixed}"],
              "M3", "a partially-migrated tree exits 3 naming EVERY mixed signal, comma-separated"
end

# ─── M4: refusals that name what was found, not that something was wrong ─────

puts "M4 — a tree whose identity cannot be read one way is refused, not guessed:"

Dir.mktmpdir("migrate-token") do |tmp|
  # Two independent derivations disagree: the manifest says one token, the
  # @main struct says another. A tree whose identity cannot be read the same way
  # twice is not one this command understands.
  write_file(tmp, "app/project.yml", project_yml(TOKEN))
  write_file(tmp, "app/Shared/OtherToken.swift", main_swift("OtherToken"))
  assert_exit ["--root", tmp, "--dry-run"], EXIT_UNKNOWN, [TOKEN, "OtherToken", "disagree"],
              "M4", "disagreeing token derivations exit 2 naming every value found"
end

Dir.mktmpdir("migrate-holes") do |tmp|
  # Structure fully migrated, values not: an app/Identity.xcconfig with a hole in
  # it. `BUNDLE_ID =` with nothing after the equals sign is what Xcode reads as
  # the empty string, both generators exit 0, and the built app carries an empty
  # CFBundleIdentifier (RESEARCH Pitfall 1). "The file exists" is not a check.
  build_fully_migrated(tmp, omit_vars: ["BUNDLE_ID"])
  assert_exit ["--root", tmp, "--dry-run"], EXIT_PARTIAL,
              [STATE_PARTIAL, "missing required variable(s): BUNDLE_ID"],
              "M4", "a present-but-incomplete app/Identity.xcconfig exits 3 naming the variable"
end

Dir.mktmpdir("migrate-include") do |tmp|
  build_fully_migrated(tmp)
  write_file(tmp, "app/Identity.xcconfig",
             "#include \"absent-include.xcconfig\"\n#{identity_xcconfig}")
  assert_exit ["--root", tmp, "--dry-run"], EXIT_UNKNOWN,
              ["absent-include.xcconfig", "could not be resolved"],
              "M4", "an unresolvable #include exits 2 naming the include, never 'that key is empty'"
end

# ─── M5: a fixture run can never be mistaken for a real one in a log ─────────

puts "M5 — the --root knob announces itself (T-05-06):"

Dir.mktmpdir("migrate-banner") do |tmp|
  build_fully_migrated(tmp)
  assert_exit ["--root", tmp, "--dry-run"], EXIT_OK,
              ["ROOT OVERRIDE IN EFFECT", ROOT, "was NOT inspected", tmp],
              "M5", "--root banners both the default root it skipped and the override it took"
end

# ─── M6: the mutation phase refuses distinguishably, and does not backtrace ──
#
# Without --dry-run the never-migrated path reaches the mutation half, which
# plan 05-03 implements. Until then it must refuse with a CODE, not with an
# uncaught NotImplementedError: Ruby exits 1 on an uncaught exception, and exit 1
# is spoken for by malformed argv, so a caller branching on the code would read
# "not implemented yet" as "you called me wrong" (the 03-REVIEW IN-01 shape).

puts "M6 — the mutation phase is refused by code, not by backtrace:"

Dir.mktmpdir("migrate-nogit") do |tmp|
  build_never_migrated(tmp)
  assert_exit ["--root", tmp], EXIT_UNKNOWN, [tmp, "not a git repository"],
              "M6", "mutating a tree with no git repository exits 2 — rollback needs one"
end

Dir.mktmpdir("migrate-git") do |tmp|
  build_never_migrated(tmp)
  if git_init(tmp)
    assert_exit ["--root", tmp], EXIT_MUTATION,
                ["mutation phase lands in plan 05-03", TOKEN],
                "M6", "a real migration exits 4 naming the plan that implements it"
  else
    fail_line("M6", "could not `git init` the fixture tree at #{tmp} — git is required by this case")
    @checks += 1
  end
end

# ─── verdict ─────────────────────────────────────────────────────────────────

puts
if @failures.zero?
  puts "All #{@checks} migrate-identity assertions passed."
  exit 0
else
  puts "#{@failures} of #{@checks} migrate-identity assertion(s) failed."
  exit 1
end
