#!/usr/bin/env ruby
# frozen_string_literal: true

# The front-door gate for bin/adopt.rb (gap GAP-05-02, ledger row UL-051).
#
# WHY THIS EXISTS
#
# bin/adopt.rb ends in exec("bundle", "exec", "fastlane", "adopt_existing_app").
# Before this suite it parsed no arguments at all: measured at the commit that
# introduced this file, a case-sensitive count over the script for the argument
# vector, the stdlib option parser and its require name returned zero for all
# three. Anything typed after the script name was therefore ignored, and the
# lane ran against the LIVE App Store Connect record.
#
# That is not hypothetical. On 2026-09-03 a `--help`, typed as a usage probe
# during planning, drove the real adopt_existing_app lane: it overwrote 13
# tracked files under fastlane/metadata/, created 10 untracked ones, and put a
# keychain unlock prompt on the operator's desktop. It was a download, so no
# Apple-side state changed and the tree was restored and verified byte-identical
# -- but the argument most likely to be typed by somebody who does not yet know
# what a command does was the argument that ran it.
#
# It got MORE dangerous as the codebase got healthier. Until plan 05-18, an
# unset locale made the script crash at its dotenv parse before the exec, so the
# obvious probe was safe -- and safe ONLY because of that defect. UL-048's fix
# removed the crash. A probe whose safety depends on the defect it probes for
# arms itself on success.
#
# WHAT IS ASSERTED, AND WHY IT IS AN OBSERVATION RATHER THAN A READING
#
# Grepping the source for a help flag would prove nothing about what the process
# does. So every case below RUNS the script -- never the tracked copy in this
# working tree, always a copy inside Dir.mktmpdir beside a synthetic fixture
# dotenv -- with a directory first on PATH holding a `bundle` that records its
# argv to a log and exits 0. REACHING THAT SHIM IS THE FAILURE CONDITION. This
# is test/setup_github_test.rb:161-170's established shape, for the same reason:
# the script under test is one whose only unguarded path is a live production
# call, so it is never run anywhere it could reach production.
#
# THE EXIT CODE DISCRIMINATES NOTHING HERE, deliberately. The shim exits 0, so on
# the unfixed script `--help` exits 0 by running the lane, and on the fixed one
# it exits 0 by printing usage -- identical codes, opposite behaviour. Every case
# therefore asserts shim_invocations NUMERICALLY. The subject of this suite is an
# unwanted EXECUTION, which is precisely the shape where a bare exit-code check,
# or a crash with zero FAIL lines, reads as a pass.
#
# THE POSITIVE CONTROL IS NOT OPTIONAL, AND IT RUNS FIRST. "The shim log is
# empty" is trivially satisfied by a harness that can never reach the shim at all
# -- a broken PATH, a copy that dies on its first line, a fixture missing a
# required key. A1 proves the harness can observe an exec BEFORE any emptiness
# assertion below is believed.
#
# THE REAL .bootstrap.env IS NEVER VISIBLE TO ANY RUN. The fixture is synthetic
# and lives in the sandbox; the child's REPO_ROOT resolves to the sandbox tree,
# not to this repository. A4 asserts the dry-run report names the FIXTURE app
# name -- a string that cannot come from a real dotenv -- so the isolation is
# measured rather than asserted.
#
# FAILURE-LINE CONTRACT -- one line per failure, no leading whitespace, so that
# negative controls can grep it:
#
#     FAIL <group> <path>: <message>
#
#   A0  harness integrity: the copy, the fixture, the shim, and the isolation
#   A1  positive control: a bare, fully-configured invocation DOES reach the shim
#   A2  --help and -h print usage, exit 0, and reach nothing
#   A3  an unrecognised argument is refused BY NAME, non-zero, and reaches nothing
#   A4  --dry-run reports the resolved target, exits 0, and reaches nothing
#   A5  restoration: the sandbox is gone and this repository was never the subject
#
# WHAT A GREEN RUN DOES NOT PROVE. It says the front door refuses. It says
# nothing about the adopt_existing_app lane itself, which this suite never
# reaches by construction, and nothing about whether an adoption that IS
# consented to does the right thing.
#
# DEPENDENCIES: Ruby core and stdlib only (open3, tmpdir, fileutils, rbconfig).
# No gem, no framework, no network, no .bootstrap.env and no generated project,
# so it is eligible for the required `review notes` context on a bare clone.
#
# Run under BOTH pinned interpreters:
#   /opt/homebrew/opt/ruby@3.3/bin/ruby test/adopt_argv_test.rb
#   /opt/homebrew/opt/ruby@4.0/bin/ruby test/adopt_argv_test.rb

require "open3"
require "tmpdir"
require "fileutils"
require "rbconfig"

ROOT   = File.expand_path("..", __dir__)
REL    = "bin/adopt.rb"
SCRIPT = File.join(ROOT, REL)

# Synthetic, and deliberately in the reserved-for-documentation namespace so it
# cannot collide with any real fork's identity. If one of these strings ever
# appears in output that came from a real dotenv -- or a real value appears in
# output that should have come from here -- the isolation has broken and A4 says
# so by name.
FIXTURE = {
  "APP_NAME"              => "Adopt Argv Fixture",
  "BUNDLE_ID"             => "com.example.adoptargv.fixture",
  "FASTLANE_TEAM_ID"      => "FIXTURETEAM",
  "ASC_API_KEY_ID"        => "FIXTUREKEYID",
  "ASC_API_KEY_ISSUER_ID" => "00000000-0000-0000-0000-000000000000"
}.freeze

# What an unhandled Ruby exception leaves on stderr. An empty shim log is only
# evidence when the process exited deliberately: a crash also reaches nothing.
BACKTRACE = /\.rb:\d+:in /

@checks   = 0
@failures = 0

def assert(condition, group, path, label)
  @checks += 1
  if condition
    puts "  ok #{group} #{path}: #{label}"
  else
    puts "FAIL #{group} #{path}: #{label.to_s.gsub(/\s*\n\s*/, ' ')}"
    @failures += 1
  end
end

# Refusing to run is not the same as passing. Exit 2, never 0, and always with a
# FAIL line so a control grepping the contract still sees one.
def cannot_run(message)
  puts "FAIL A0 #{REL}: cannot run -- #{message}"
  puts
  puts "adopt argv gate CANNOT RUN: #{message}"
  exit 2
end

Result = Struct.new(:argv, :status, :stdout, :stderr, :shim_argv)

# Runs the sandbox copy with the shim directory first on PATH. Returns the exit
# status, both streams, and every argv the shim recorded.
def run_case(sandbox, argv)
  shim_dir = File.join(sandbox, "shim")
  shim_log = File.join(shim_dir, "bundle-argv.log")
  tree     = File.join(sandbox, "tree")
  FileUtils.rm_f(shim_log)

  env = {
    "PATH"             => "#{shim_dir}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH')}",
    "RUBYOPT"          => nil,
    "BUNDLE_GEMFILE"   => nil,
    "FORCE"            => nil,
    "SKIP_METADATA"    => nil,
    "SKIP_SCREENSHOTS" => nil
  }
  # bin/adopt.rb lets ENV win over the dotenv, so a stray export in the
  # operator's shell would silently replace a fixture value and change what the
  # dry-run report prints -- the shape 05-18 hit when a leaked key switched a
  # refusal off. Every key the script reads is cleared for the child.
  FIXTURE.each_key { |k| env[k] = nil }

  out, err, status = Open3.capture3(
    env, RbConfig.ruby, File.join(tree, "bin", "adopt.rb"), *argv, chdir: tree
  )
  logged = if File.exist?(shim_log)
             File.read(shim_log, encoding: "UTF-8").lines.map(&:chomp).reject(&:empty?)
           else
             []
           end
  Result.new(argv, status.exitstatus, out, err, logged)
end

# The pair of assertions that make "reached nothing" mean something: the shim log
# is empty AND the process did not crash on its way to leaving it empty.
def assert_reached_nothing(result, group)
  spelled = result.argv.empty? ? "(no arguments)" : result.argv.join(" ")
  assert result.shim_argv.empty?, group, REL,
         "`#{spelled}` reached the `bundle` shim #{result.shim_argv.length} time(s), " \
         "expected 0#{result.shim_argv.empty? ? '' : " -- recorded: #{result.shim_argv.join(' | ')}"}. " \
         "Reaching the shim means this process would have run the adopt lane against the " \
         "live App Store Connect record"
  assert !result.stderr.match?(BACKTRACE), group, REL,
         "`#{spelled}` exited deliberately rather than by raising -- a crash also leaves the " \
         "shim log empty, so an empty log is evidence only when there is no backtrace beside it"
end

# ─── the sandbox ─────────────────────────────────────────────────────────────

script_before = begin
  File.read(SCRIPT, encoding: "UTF-8")
rescue SystemCallError => e
  cannot_run("#{REL} could not be read in #{ROOT}: #{e.message}")
end

counts  = {}
sandbox = nil

begin
  sandbox = Dir.mktmpdir("adopt-argv-gate")

  tree     = File.join(sandbox, "tree")
  shim_dir = File.join(sandbox, "shim")
  FileUtils.mkdir_p(File.join(tree, "bin"))
  FileUtils.mkdir_p(shim_dir)

  copy = File.join(tree, "bin", "adopt.rb")
  FileUtils.cp(SCRIPT, copy)
  File.write(
    File.join(tree, ".bootstrap.env"),
    FIXTURE.map { |k, v| "#{k}=#{v}" }.join("\n") + "\n"
  )

  shim_log = File.join(shim_dir, "bundle-argv.log")
  shim     = File.join(shim_dir, "bundle")
  File.write(shim, <<~SH)
    #!/bin/sh
    # Any invocation is the failure condition of test/adopt_argv_test.rb: for a
    # non-consenting argv, bin/adopt.rb must never reach the adopt lane.
    printf '%s\\n' "$*" >> "#{shim_log}"
    exit 0
  SH
  File.chmod(0o755, shim)

  # Belt and braces. If the handoff is ever respelled to name fastlane directly,
  # that invocation is recorded here rather than escaping to the real one.
  fastlane_shim = File.join(shim_dir, "fastlane")
  File.write(fastlane_shim, <<~SH)
    #!/bin/sh
    printf 'fastlane %s\\n' "$*" >> "#{shim_log}"
    exit 0
  SH
  File.chmod(0o755, fastlane_shim)

  puts
  puts "bin/adopt.rb front door — observed by running a sandbox copy, never this tree:"
  puts

  # ─── A0: harness integrity, BEFORE anything is run or believed ─────────────
  assert File.file?(copy) && !File.size(copy).zero?, "A0", REL,
         "the script was copied into the sandbox and is non-empty; every case below runs " \
         "THIS copy, never #{SCRIPT}"
  assert File.read(copy, encoding: "UTF-8") == script_before, "A0", REL,
         "the sandbox copy is byte-identical to the tracked script, so a green result is " \
         "about the real file rather than about a fixture that drifted from it"
  assert File.expand_path("..", File.dirname(copy)) == File.expand_path(tree), "A0", REL,
         "the copy sits at <sandbox>/tree/bin/, so the script's own REPO_ROOT resolves to " \
         "the sandbox tree and its dotenv read cannot reach this repository's"
  assert File.expand_path(sandbox) != File.expand_path(ROOT) &&
         !File.expand_path(sandbox).start_with?(File.expand_path(ROOT) + File::SEPARATOR),
         "A0", REL,
         "the sandbox is outside this repository (#{sandbox}), so no run below can see the " \
         "real .bootstrap.env"
  assert File.executable?(shim), "A0", "shim/bundle",
         "the capturing `bundle` shim is executable; a non-executable shim would be skipped " \
         "on PATH and the real `bundle` would be reached instead"
  assert FIXTURE.keys.sort ==
         %w[APP_NAME ASC_API_KEY_ID ASC_API_KEY_ISSUER_ID BUNDLE_ID FASTLANE_TEAM_ID],
         "A0", ".bootstrap.env",
         "the fixture supplies every variable the script requires, so a refusal below is " \
         "about the argument and never about an incomplete fixture"
  assert FIXTURE["BUNDLE_ID"].start_with?("com.example."), "A0", ".bootstrap.env",
         "the fixture identity is synthetic and in the documentation-reserved namespace, so " \
         "it can never name a real App Store record"

  # ─── A1: the positive control, FIRST ───────────────────────────────────────
  bare = run_case(sandbox, [])
  counts["bare"] = bare.shim_argv.length
  assert bare.shim_argv.length == 1, "A1", REL,
         "the positive control: a bare, fully-configured invocation DOES reach the `bundle` " \
         "shim exactly once (found #{bare.shim_argv.length}). Without this, every 'the shim " \
         "log is empty' assertion below could be satisfied by a harness that is simply " \
         "incapable of reaching the shim at all"
  assert bare.shim_argv.first.to_s.include?("exec fastlane adopt_existing_app"), "A1", REL,
         "the recorded argv is the lane handoff itself (#{bare.shim_argv.first.inspect}), so " \
         "the shim is observing the exec this suite is about rather than some unrelated child"
  assert bare.status.zero?, "A1", REL,
         "the bare invocation exits with the shim's own status (got #{bare.status.inspect}). " \
         "Recorded to make the point that the exit code discriminates NOTHING here: it is 0 " \
         "whether the lane ran or usage printed, which is why every case asserts the count"
  assert !bare.stderr.match?(BACKTRACE), "A1", REL,
         "the bare invocation reached the exec without raising, so the harness is exercising " \
         "the script's real path"

  # ─── A2: the usage flags ───────────────────────────────────────────────────
  %w[--help -h].each do |flag|
    res = run_case(sandbox, [flag])
    counts[flag] = res.shim_argv.length
    printed = res.stdout + res.stderr

    assert res.status.zero?, "A2", REL,
           "`#{flag}` exits 0 (got #{res.status.inspect}) -- asking what a command does is " \
           "not an error"
    assert printed.downcase.include?("adopt"), "A2", REL,
           "`#{flag}` prints usage naming the command it describes"
    assert printed.include?("App Store Connect"), "A2", REL,
           "`#{flag}`'s usage says the command contacts App Store Connect -- the fact a " \
           "reader typing it does not yet have, and the whole reason this flag existing is " \
           "not enough on its own"
    assert printed.include?("fastlane/metadata") && printed.include?("fastlane/screenshots"),
           "A2", REL,
           "`#{flag}`'s usage names both local trees an adoption overwrites"
    assert_reached_nothing(res, "A2")
  end

  # ─── A3: refusal by name, flag-shaped and not ──────────────────────────────
  # Two shapes on purpose. A parser that only inspects arguments beginning with a
  # dash would ignore the second and fall through to the lane, which is the exact
  # failure this gate exists for.
  [["--bogus"], ["adopt-everything"]].each do |argv|
    offender = argv.first
    res = run_case(sandbox, argv)
    counts[offender] = res.shim_argv.length
    printed = res.stdout + res.stderr

    assert !res.status.zero?, "A3", REL,
           "`#{offender}` exits non-zero (got #{res.status.inspect}); exiting 0 for an " \
           "argument nobody parsed is how a usage probe became a live call"
    assert res.status != 1, "A3", REL,
           "`#{offender}` uses an exit code distinguishable from a preflight refusal, which " \
           "is 1 (got #{res.status.inspect}) -- 'I do not understand you' is a different " \
           "outcome from 'this fork is not ready to adopt'"
    assert printed.include?(offender), "A3", REL,
           "the refusal names #{offender.inspect} verbatim rather than printing a generic " \
           "error; an argument that is refused without being named reads as ignored"
    assert_reached_nothing(res, "A3")
  end

  # ─── A4: the dry run ───────────────────────────────────────────────────────
  dry = run_case(sandbox, ["--dry-run"])
  counts["--dry-run"] = dry.shim_argv.length
  printed = dry.stdout + dry.stderr

  assert dry.status.zero?, "A4", REL,
         "`--dry-run` exits 0 (got #{dry.status.inspect})"
  assert printed.include?(FIXTURE["APP_NAME"]), "A4", REL,
         "the dry run names the app it WOULD adopt, resolved from the sandbox fixture " \
         "(#{FIXTURE['APP_NAME'].inspect}). That string exists only in the sandbox, so this " \
         "assertion is also the measurement that the run read the fixture dotenv and never " \
         "this repository's"
  assert printed.include?(FIXTURE["BUNDLE_ID"]), "A4", REL,
         "the dry run names the bundle id it WOULD adopt (#{FIXTURE['BUNDLE_ID'].inspect})"
  assert printed.downcase.include?("would"), "A4", REL,
         "the dry run reports in the conditional -- what it WOULD do -- rather than " \
         "narrating something it did"
  assert printed.include?("fastlane/metadata") && printed.include?("fastlane/screenshots"),
         "A4", REL,
         "the dry run names what would be overwritten, which is the question somebody runs " \
         "it to answer"
  assert_reached_nothing(dry, "A4")
rescue StandardError => e
  # A crash is not a pass. The subject of this suite is an unwanted EXECUTION, so
  # an exception that leaves the shim log empty is exactly the shape that reads as
  # success to anything counting FAIL lines. It gets one.
  @checks += 1
  @failures += 1
  puts "FAIL A0 #{REL}: the harness raised #{e.class}: " \
       "#{e.message.to_s.gsub(/\s*\n\s*/, ' ')} -- the suite did not finish, so nothing " \
       "below it was observed"
ensure
  FileUtils.remove_entry(sandbox) if sandbox && File.exist?(sandbox)
end

# ─── A5: restoration ─────────────────────────────────────────────────────────
assert sandbox && !File.exist?(sandbox), "A5", "-",
       "the sandbox was removed (#{sandbox})"
assert File.read(SCRIPT, encoding: "UTF-8") == script_before, "A5", REL,
       "the tracked script is byte-identical to what it was before this suite ran -- this " \
       "suite reads it and copies it, and never executes it in place"

# ─── the transcript line ─────────────────────────────────────────────────────
exit_code = @failures.zero? ? 0 : 1
puts
puts "RESULT control=adopt-argv-front-door exit=#{exit_code} " \
     "shim_invocations_bare=#{counts.fetch('bare', -1)} " \
     "shim_invocations_help=#{counts.fetch('--help', -1)} " \
     "shim_invocations_h=#{counts.fetch('-h', -1)} " \
     "shim_invocations_bogus=#{counts.fetch('--bogus', -1)} " \
     "shim_invocations_positional=#{counts.fetch('adopt-everything', -1)} " \
     "shim_invocations_dry_run=#{counts.fetch('--dry-run', -1)} " \
     "restored=ok"
puts
puts "#{@checks} check(s), #{@failures} failure(s)"
exit exit_code
