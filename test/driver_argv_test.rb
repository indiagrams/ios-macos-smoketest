#!/usr/bin/env ruby
# frozen_string_literal: true

# The front-door gate for every bin/ driver whose last act launches a
# subprocess (gaps GAP-05-02 and GAP-05-03, ledger row UL-051).
#
# WHY THIS EXISTS, AND WHY IT IS ONE SUITE OVER A TABLE RATHER THAN ONE PER
# DRIVER
#
# On 2026-09-03 a `ruby bin/adopt.rb --help`, typed as a usage probe during
# planning, drove the real adoption lane against the live App Store
# Connect record: it overwrote 13 tracked files under fastlane/metadata/,
# created 10 untracked ones, and put a keychain unlock prompt on the operator's
# desktop. The script parsed no arguments, so the argument most likely to be
# typed by somebody who does not yet know what a command does was the argument
# that ran it. Plan 05-19 gave that one script a front door and a gate.
#
# A read-only audit on 2026-09-04 then found the SAME shape in two more drivers,
# which is what makes this a class rather than one bug:
#
#   bin/submit.rb  parsed ZERO arguments and ends in
#                  a shell-out of bundle / exec / fastlane / <platform> / lane.
#                  Its safety was never a guard: `auto_submit` reads
#                  SUBMIT_FOR_REVIEW and never argv, that key is unset in this
#                  fork, so the lane resolved to the staging one -- still an App
#                  Store Connect mutation -- and the script's own closing banner
#                  tells the reader how to remove that safety. After which
#                  `bin/submit.rb --help` submits the app for App Store review.
#
#   bin/ship.rb    SNIFFED two arguments with ARGV.include? and parsed none.
#                  Sniffing matches exactly or not at all, so --help, --dryrun,
#                  --dry_run and every typo alike yielded dry_run="false" and a
#                  REAL ship. The script had a dry-run mode and no way to
#                  discover it -- worse than having none, because the reader who
#                  types --help to find the flag triggers the thing the flag
#                  exists to prevent.
#
# An incidental safety is the shape GAP-05-02 already cost this repository once:
# an unset locale used to crash bin/adopt.rb before its exec, so the obvious
# probe was safe ONLY because of that defect, and UL-048's encoding pin removed
# the accident that was guarding it. Safety nobody chose is safety that leaves
# without notice.
#
# WHAT IS ASSERTED, AND WHY IT IS AN OBSERVATION RATHER THAN A READING
#
# Grepping a driver for a help flag would prove nothing about what the process
# does. So every EXECUTED case below RUNS the script -- never the tracked copy in
# this working tree, always a copy inside Dir.mktmpdir beside a synthetic fixture
# dotenv and a synthetic Identity.xcconfig -- with a directory first on PATH
# holding a `bundle`, a `fastlane` and a `gh` that record their argv to one log
# and exit 0. REACHING THAT LOG IS THE FAILURE CONDITION for a non-consenting
# argument. This is test/setup_github_test.rb:161-170's established shape, for
# the same reason: the scripts under test are ones whose only unguarded path is a
# live production call, so they are never run anywhere they could reach it.
#
# THE EXIT CODE DISCRIMINATES NOTHING HERE, deliberately. The shims exit 0, so on
# an unfixed script `--help` exits 0 by running the lane and on a fixed one it
# exits 0 by printing usage -- identical codes, opposite behaviour. Every case
# therefore asserts the shim invocation count NUMERICALLY, and pairs it with a
# backtrace check, because a crash also leaves the log empty.
#
# THE POSITIVE CONTROL IS NOT OPTIONAL, AND IT RUNS FIRST, PER DRIVER. "The shim
# log is empty" is trivially satisfied by a harness that can never reach the
# shim at all -- a broken PATH, a copy that dies on its first line, a fixture
# missing a required key. 05-19 MEASURED that: with the shim directory dropped
# from PATH, five emptiness assertions passed vacuously and only the positive
# control noticed. A1 proves this harness can observe a subprocess launch, for
# each executed driver, BEFORE any emptiness assertion about that driver is
# believed.
#
# THE TWO DRIVERS THAT ARE NOT EXECUTED ARE STILL ASSERTED, NOT COMMENTED.
# bin/mint-local-certs.rb is safe because a RELEASE_MODE=ci guard refuses before
# it touches the login keychain; bin/verify-testflight.rb is safe because every
# App Store Connect call it makes is a query and the one subprocess it launches
# is a git tag fetch, not a lane. Both facts are asserted against their source, so
# an edit that removes the guard or adds a write turns this gate red. An unnamed
# safe driver is indistinguishable from an unaudited one.
#
#   bin/mint-local-certs.rb is additionally OBSERVED, but only on its refusing
#   path: run under the ci-mode fixture it must exit non-zero naming the guard,
#   with the log empty. Its consenting path is never run here, because that path
#   mints certificates into the operator's real login keychain -- there is no
#   sandbox for that, so there is no positive control for it and this file says
#   so rather than pretending otherwise.
#
#   bin/verify-testflight.rb is never run at all: it requires the spaceship gem
#   and its first act after config is a live App Store Connect query. Static
#   assertions only, and that limit is stated here rather than left to be
#   inferred from their absence. Its static assertion was WEAKENED FROM THE PLAN
#   ON PURPOSE, because the plan's audit table was wrong by omission: this driver
#   does launch a subprocess (`git fetch --tags --quiet origin`, at :83). It is a
#   read, so the safe disposition stands -- but the gate asserts the property
#   that is true (no launch site hands off to a lane) rather than the tidier one
#   that is not (no launch site at all).
#
# THE REAL .bootstrap.env IS NEVER VISIBLE TO ANY RUN. Every fixture is synthetic
# and lives in the sandbox; each child's REPO_ROOT resolves to the sandbox tree,
# not to this repository, because REPO_ROOT is derived from the running script's
# own __dir__. The dry-run assertions name FIXTURE identity strings -- values
# that cannot come from a real dotenv or a real xcconfig -- so the isolation is
# measured rather than asserted.
#
# THE GATE-COLLISION HAZARD. This file greps driver source for lane names and for
# App Store Connect write verbs. Those patterns are ASSEMBLED FROM PARTS AT
# RUNTIME rather than written as literals, so this file is not itself a match for
# them, and A0 MEASURES that it finds zero candidates in its own source for that
# reason instead of self-excluding by path.
#
# FAILURE-LINE CONTRACT -- one line per failure, no leading whitespace, so that
# negative controls can grep it:
#
#     FAIL <group> <path>: <message>
#
#   A0  harness integrity: the copies, the fixtures, the shims, the isolation,
#       and the runtime assembly of every pattern used below
#   A1  positive control, per executed driver: a bare, fully-configured
#       invocation DOES reach the shim
#   A2  --help and -h print usage naming the driver, exit 0, and reach nothing
#   A3  an unrecognised argument -- flag-shaped or not -- is refused BY NAME at a
#       documented, distinguishable exit code, and reaches nothing
#   A4  the dry-run contract, which differs per driver and is stated per driver
#   A5  near-miss spellings of --dry-run are REFUSED rather than silently
#       treated as a real run
#   A6  bin/mint-local-certs.rb: the RELEASE_MODE guard refuses, observed
#   A7  the two measured-safe drivers, asserted against their source
#   A8  restoration: the sandbox is gone and this repository was never the subject
#
# WHAT A GREEN RUN DOES NOT PROVE. It says the front doors refuse. It says
# nothing about the release, staging, submission or adoption lanes themselves,
# which this suite never reaches by
# construction, and nothing about whether a run somebody consents to does the
# right thing.
#
# DEPENDENCIES: Ruby core and stdlib only (open3, tmpdir, fileutils, rbconfig).
# No gem, no framework, no network, no .bootstrap.env and no generated project,
# so it is eligible for the required `review notes` context on a bare clone.
#
# Run under BOTH pinned interpreters:
#   /opt/homebrew/opt/ruby@3.3/bin/ruby test/driver_argv_test.rb
#   /opt/homebrew/opt/ruby@4.0/bin/ruby test/driver_argv_test.rb

require "open3"
require "tmpdir"
require "fileutils"
require "rbconfig"

ROOT = File.expand_path("..", __dir__)

# ─── patterns assembled at runtime, never written as literals ────────────────
#
# Six consecutive plans in this phase were bitten by a gate matching its own
# source. Nothing below appears verbatim in this file, and A0 measures that.
STAGE_LANE  = %w[stage for review].join("_")
SUBMIT_LANE = %w[submit for review].join("_")
ADOPT_LANE  = %w[adopt existing app].join("_")
SUBMIT_KEY  = %w[SUBMIT FOR REVIEW].join("_")
RELEASE_KEY = %w[RELEASE MODE].join("_")

# What an App Store Connect WRITE looks like in a driver. Read verbs (.all,
# .find, .get) are deliberately absent: bin/verify-testflight.rb is expected to
# use them, and a pattern that matched them would make A7 vacuous in the other
# direction.
ASC_WRITE_VERBS = %w[create update delete post patch save destroy].freeze
ASC_WRITE_PATTERNS = (
  ASC_WRITE_VERBS.map { |v| Regexp.new(Regexp.escape(".#{v}") + '[!(]') } +
  [SUBMIT_LANE, STAGE_LANE].map { |lane| Regexp.new(Regexp.escape(lane)) }
).freeze

# A subprocess launch, in any of the spellings this repository uses.
LAUNCH_PATTERNS = [
  Regexp.new(Regexp.escape("exec") + '\('),
  Regexp.new(Regexp.escape("system") + '\('),
  Regexp.new(Regexp.escape("Sh.") + '(?:run|stream)')
].freeze

# What an unhandled Ruby exception leaves on stderr. An empty shim log is only
# evidence when the process exited deliberately: a crash also reaches nothing.
BACKTRACE = /\.rb:\d+:in /

# Synthetic, and deliberately in the reserved-for-documentation namespace so it
# cannot collide with any real fork's identity. If one of these strings ever
# appears in output that came from a real config -- or a real value appears in
# output that should have come from here -- the isolation has broken and A4 says
# so by name.
FIXTURE_APP_NAME     = "Driver Argv Fixture"
FIXTURE_PRODUCT_NAME = "DriverArgvFixture"
FIXTURE_BUNDLE_ID    = "com.example.driverargv.fixture"
FIXTURE_TEAM         = "FIXTURETEAM"
FIXTURE_ORG          = "example-org"
FIXTURE_REPO         = "example-app"

# Every key the sandbox config carries. The union of what the five drivers read,
# so a refusal below is about the ARGUMENT and never about an incomplete fixture.
FIXTURE_ENV = {
  "APP_NAME"              => FIXTURE_APP_NAME,
  "BUNDLE_ID"             => FIXTURE_BUNDLE_ID,
  "APP_EMAIL"             => "driver-argv@example.com",
  "GENERATOR"             => "xcodegen",
  RELEASE_KEY             => "ci",
  "PLATFORMS"             => "ios",
  "FASTLANE_TEAM_ID"      => FIXTURE_TEAM,
  "ASC_API_KEY_ID"        => "FIXTUREKEYID",
  "ASC_API_KEY_ISSUER_ID" => "00000000-0000-0000-0000-000000000000",
  "ASC_API_KEY_P8_PATH"   => "asc-fixture.p8",
  "GH_ORG"                => FIXTURE_ORG,
  "GH_APP_REPO"           => FIXTURE_REPO,
  "KEYCHAIN_PASSWORD_FILE" => "keychain-password.txt"
}.freeze

# The library files the drivers require. Copied rather than stubbed: a stub would
# make a green result be about the stub.
LIB_FILES = %w[bootstrap.rb xcconfig.rb version_resolver.rb].freeze

DRIVERS = %w[
  bin/submit.rb
  bin/ship.rb
  bin/adopt.rb
  bin/mint-local-certs.rb
  bin/verify-testflight.rb
].freeze

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
  puts "FAIL A0 -: cannot run -- #{message}"
  puts
  puts "driver argv gate CANNOT RUN: #{message}"
  exit 2
end

Result = Struct.new(:rel, :argv, :status, :stdout, :stderr, :shim_argv) do
  def printed
    stdout + stderr
  end

  def spelled
    argv.empty? ? "(no arguments)" : argv.join(" ")
  end
end

# ─── the executed-driver table ───────────────────────────────────────────────
#
# `refusal_exit` differs on purpose and is not an oversight. bin/adopt.rb had
# exit 2 free and 05-19 used it. bin/submit.rb and bin/ship.rb already document
# exit 2 as "the lane / the workflow run failed", a real outcome that predates
# this work, so taking it for argv would have redefined an existing code -- which
# is a behaviour change wearing a consistency costume. They use 3, and both say
# so in their own header tables.
EXECUTED = [
  {
    rel: "bin/submit.rb",
    slug: "submit",
    launcher: "bundle",
    a1_expect: "bundle exec fastlane ios #{STAGE_LANE}",
    a1_why: "the staging lane handoff -- an App Store Connect mutation",
    usage_must: [
      ["bin/submit.rb", "the usage names the driver it describes"],
      ["App Store Connect", "the usage says the command contacts App Store Connect"],
      [SUBMIT_KEY, "the usage names the variable that decides between staging and submitting"],
      [STAGE_LANE, "the usage names the lane a bare run resolves to today"],
      [SUBMIT_LANE, "the usage names the lane a bare run resolves to once that variable is true"]
    ],
    unknown: ["--bogus", "submit-everything"],
    refusal_exit: 3,
    dry_run: {
      flag: "--dry-run",
      reaches_shim: false,
      must_include: [
        [FIXTURE_PRODUCT_NAME, "the resolved app name, read from the sandbox xcconfig"],
        [FIXTURE_BUNDLE_ID, "the resolved bundle id"],
        [STAGE_LANE, "the lane this invocation WOULD have run"],
        ["ios", "the resolved platform list"]
      ]
    }
  },
  {
    rel: "bin/ship.rb",
    slug: "ship",
    launcher: "gh",
    a1_expect: "gh workflow run release.yml",
    a1_why: "the release workflow dispatch -- a real ship",
    usage_must: [
      ["bin/ship.rb", "the usage names the driver it describes"],
      ["App Store Connect", "the usage says where a ship ends up"],
      ["--dry-run", "the usage names the flag that makes a run harmless, which was undiscoverable before"],
      ["--force", "the usage names the other flag the script already honoured"]
    ],
    unknown: ["--bogus", "ship-everything"],
    refusal_exit: 3,
    # ship.rb's --dry-run does NOT mean "contact nothing". It means "dispatch the
    # release workflow with dry_run=true", and that spelling is the contract this
    # plan is forbidden to change. So the assertion is that the flag is HONOURED
    # and that the honouring is visible in the recorded argv -- not that the log
    # is empty. The emptiness property belongs to the near misses below, which is
    # where the defect actually lives.
    dry_run: {
      flag: "--dry-run",
      reaches_shim: true,
      log_must_include: "dry_run=true",
      log_must_exclude: "dry_run=false"
    },
    near_misses: %w[--dryrun --dry_run --DRY-RUN],
    also_accepted: ["--force"]
  },
  {
    rel: "bin/adopt.rb",
    slug: "adopt",
    launcher: "bundle",
    a1_expect: "bundle exec fastlane #{ADOPT_LANE}",
    a1_why: "the adoption lane handoff -- the call that overwrote 13 tracked files",
    usage_must: [
      ["adopt", "the usage names the command it describes"],
      ["App Store Connect", "the usage says the command contacts App Store Connect"],
      ["fastlane/metadata", "the usage names the first local tree an adoption overwrites"],
      ["fastlane/screenshots", "the usage names the second local tree an adoption overwrites"]
    ],
    unknown: ["--bogus", "adopt-everything"],
    refusal_exit: 2,
    dry_run: {
      flag: "--dry-run",
      reaches_shim: false,
      must_include: [
        [FIXTURE_APP_NAME, "the app it WOULD adopt, resolved from the sandbox dotenv"],
        [FIXTURE_BUNDLE_ID, "the bundle id it WOULD adopt"],
        ["fastlane/metadata", "the first tree it WOULD overwrite"],
        ["fastlane/screenshots", "the second tree it WOULD overwrite"]
      ]
    }
  }
].freeze

# ─── the sandbox ─────────────────────────────────────────────────────────────

sources_before = {}
DRIVERS.each do |rel|
  sources_before[rel] = begin
    File.read(File.join(ROOT, rel), encoding: "UTF-8")
  rescue SystemCallError => e
    cannot_run("#{rel} could not be read in #{ROOT}: #{e.message}")
  end
end

counts  = Hash.new { |h, k| h[k] = {} }
sandbox = nil
tree    = nil
shim_log = nil

# Runs a sandbox copy with the shim directory first on PATH. Returns the exit
# status, both streams, and every argv the shims recorded.
run_case = lambda do |rel, argv, extra_env = {}|
  FileUtils.rm_f(shim_log)
  shim_dir = File.join(sandbox, "shim")

  env = {
    "PATH"             => "#{shim_dir}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH')}",
    "RUBYOPT"          => nil,
    "BUNDLE_GEMFILE"   => nil,
    "FORCE"            => nil,
    "SKIP_METADATA"    => nil,
    "SKIP_SCREENSHOTS" => nil,
    "BOOTSTRAP_ENV"    => nil,
    "IDENTITY_XCCONFIG" => nil
  }
  # Both bin/adopt.rb and bin/submit.rb let ENV win over the config file, so a
  # stray export in the operator's shell would silently replace a fixture value
  # and change what a dry-run report prints -- the shape 05-18 hit when a leaked
  # key switched a refusal off. Every key any driver reads is cleared for the
  # child, then the caller's overrides are applied on top.
  FIXTURE_ENV.each_key { |k| env[k] = nil }
  env[SUBMIT_KEY] = nil
  env.merge!(extra_env)

  out, err, status = Open3.capture3(
    env, RbConfig.ruby, File.join(tree, rel), *argv, chdir: tree
  )
  # UL-048's class, arriving through process output rather than a file read.
  # Open3 tags what it captures with Encoding.default_external, which is US-ASCII
  # when LANG and LC_ALL are unset -- and every driver's output carries em dashes
  # and box-drawing rules. Concatenating or matching those bytes then raises
  # ArgumentError, which would make this suite red on any runner without a
  # locale. There is no encoding argument to give a captured stream, so the bytes
  # are re-tagged at the boundary, once, before any assertion touches them.
  out = out.dup.force_encoding(Encoding::UTF_8).scrub
  err = err.dup.force_encoding(Encoding::UTF_8).scrub
  logged = if File.exist?(shim_log)
             File.read(shim_log, encoding: "UTF-8").lines.map(&:chomp).reject(&:empty?)
           else
             []
           end
  Result.new(rel, argv, status.exitstatus, out, err, logged)
end

# The pair of assertions that make "reached nothing" mean something: the shim log
# is empty AND the process did not crash on its way to leaving it empty.
assert_reached_nothing = lambda do |result, group|
  assert result.shim_argv.empty?, group, result.rel,
         "`#{result.spelled}` reached the capturing shims #{result.shim_argv.length} time(s), " \
         "expected 0#{result.shim_argv.empty? ? '' : " -- recorded: #{result.shim_argv.join(' | ')}"}. " \
         "Reaching a shim means this process would have launched the real subprocess against " \
         "live App Store Connect state"
  assert !result.stderr.match?(BACKTRACE), group, result.rel,
         "`#{result.spelled}` exited deliberately rather than by raising -- a crash also leaves " \
         "the shim log empty, so an empty log is evidence only when there is no backtrace " \
         "beside it"
end

begin
  sandbox = Dir.mktmpdir("driver-argv-gate")

  tree     = File.join(sandbox, "tree")
  shim_dir = File.join(sandbox, "shim")
  shim_log = File.join(shim_dir, "subprocess-argv.log")

  FileUtils.mkdir_p(File.join(tree, "bin", "lib"))
  FileUtils.mkdir_p(File.join(tree, "app"))
  FileUtils.mkdir_p(File.join(tree, "fastlane", "metadata", "en-US"))
  FileUtils.mkdir_p(File.join(tree, "fastlane", "screenshots", "en-US"))
  FileUtils.mkdir_p(File.join(tree, "fastlane", "Mac_screenshots", "en-US"))
  FileUtils.mkdir_p(shim_dir)

  DRIVERS.each { |rel| FileUtils.cp(File.join(ROOT, rel), File.join(tree, rel)) }
  LIB_FILES.each do |f|
    FileUtils.cp(File.join(ROOT, "bin", "lib", f), File.join(tree, "bin", "lib", f))
  end

  File.write(
    File.join(tree, ".bootstrap.env"),
    FIXTURE_ENV.map { |k, v| "#{k}=#{v}" }.join("\n") + "\n"
  )
  File.write(File.join(tree, "app", "Identity.xcconfig"), <<~XCCONFIG)
    // Synthetic fixture for test/driver_argv_test.rb. Never a real identity.
    BUNDLE_ID        = #{FIXTURE_BUNDLE_ID}
    APP_PRODUCT_NAME = #{FIXTURE_PRODUCT_NAME}
    DISPLAY_NAME     = #{FIXTURE_APP_NAME}
    COPYRIGHT        = Copyright 2026 Example Org. All rights reserved.
  XCCONFIG
  # bin/lib/bootstrap.rb's asc_env base64-encodes this file's bytes, so it has to
  # exist and be readable. It is not a key and cannot authenticate anything.
  File.write(File.join(tree, "asc-fixture.p8"), "NOT-A-KEY-fixture-bytes-for-driver-argv-gate\n")
  File.write(File.join(tree, "keychain-password.txt"), "fixture\n")
  # bin/submit.rb's preflight requires at least one image per active platform.
  File.write(File.join(tree, "fastlane", "metadata", "en-US", "description.txt"), "fixture\n")
  File.write(File.join(tree, "fastlane", "screenshots", "en-US", "01-fixture.png"), "not-a-png\n")
  File.write(File.join(tree, "fastlane", "Mac_screenshots", "en-US", "01-fixture.png"), "not-a-png\n")

  # ─── the capturing shims ───────────────────────────────────────────────────
  #
  # `bundle` for bin/submit.rb and bin/adopt.rb, `gh` for bin/ship.rb's CI-mode
  # dispatch, and `fastlane` belt-and-braces in case a handoff is ever respelled
  # to name it directly. One shared log, each line prefixed with the program, so
  # an assertion can tell which subprocess was reached.
  %w[bundle fastlane].each do |name|
    path = File.join(shim_dir, name)
    File.write(path, <<~SH)
      #!/bin/sh
      # Any invocation is a failure condition of test/driver_argv_test.rb for a
      # non-consenting argv: no driver may reach a lane without being asked to.
      printf '#{name} %s\\n' "$*" >> "#{shim_log}"
      exit 0
    SH
    File.chmod(0o755, path)
  end

  # `gh` additionally answers, because bin/ship.rb polls it in a loop and an
  # always-empty answer would make the positive control take 45 seconds to reach
  # a failure instead of 5 seconds to reach the dispatch. The two `run list`
  # queries are told apart by the --json field set bin/ship.rb asks for: the
  # in-progress check asks for databaseId,status and must find nothing (so the
  # script proceeds to dispatch, which is what A1 observes), while the
  # post-dispatch lookup asks for databaseId,status,createdAt and gets an id.
  gh = File.join(shim_dir, "gh")
  File.write(gh, <<~SH)
    #!/bin/sh
    printf 'gh %s\\n' "$*" >> "#{shim_log}"
    case "$*" in
      *databaseId,status,createdAt*) echo 999999 ;;
      *"run view"*)                  echo "completed success" ;;
      *)                             : ;;
    esac
    exit 0
  SH
  File.chmod(0o755, gh)

  puts
  puts "bin/ driver front doors — observed by running sandbox copies, never this tree:"
  puts

  # ─── A0: harness integrity, BEFORE anything is run or believed ─────────────
  DRIVERS.each do |rel|
    copy = File.join(tree, rel)
    assert File.file?(copy) && !File.size(copy).zero?, "A0", rel,
           "the script was copied into the sandbox and is non-empty; every case below runs " \
           "THIS copy, never #{File.join(ROOT, rel)}"
    assert File.read(copy, encoding: "UTF-8") == sources_before[rel], "A0", rel,
           "the sandbox copy is byte-identical to the tracked script, so a green result is " \
           "about the real file rather than about a fixture that drifted from it"
  end

  assert LIB_FILES.all? { |f| File.file?(File.join(tree, "bin", "lib", f)) }, "A0", "bin/lib",
         "the real bin/lib/*.rb the drivers require were copied too (#{LIB_FILES.join(', ')}), " \
         "so a driver's config read and identity read are the real ones rather than stubs"
  assert File.expand_path(sandbox) != File.expand_path(ROOT) &&
         !File.expand_path(sandbox).start_with?(File.expand_path(ROOT) + File::SEPARATOR),
         "A0", "-",
         "the sandbox is outside this repository (#{sandbox}), so no run below can see the " \
         "real .bootstrap.env or the real app/Identity.xcconfig"
  assert File.expand_path(File.join(tree, "bin", "lib", "..", "..")) == File.expand_path(tree),
         "A0", "-",
         "bin/lib sits two levels under the sandbox tree root, so each driver's REPO_ROOT -- " \
         "computed from its own __dir__ -- resolves to the sandbox and its config read cannot " \
         "reach this repository's"
  assert %w[bundle fastlane gh].all? { |n| File.executable?(File.join(shim_dir, n)) },
         "A0", "shim/",
         "all three capturing shims are executable; a non-executable shim would be skipped on " \
         "PATH and the real program would be reached instead"
  assert FIXTURE_ENV["BUNDLE_ID"].start_with?("com.example.") &&
         FIXTURE_ENV["GH_ORG"].start_with?("example-"),
         "A0", ".bootstrap.env",
         "the fixture identity is synthetic and in the documentation-reserved namespace, so it " \
         "can never name a real App Store record or a real GitHub repository"

  # The gate-collision measurement. Six consecutive plans in this phase were bitten
  # by a gate that matched its own source; this one assembles every pattern from
  # parts at runtime and MEASURES the consequence rather than excluding itself by
  # path -- a self-exclusion would still be there after somebody pasted a literal in.
  self_source = File.read(__FILE__, encoding: "UTF-8")
  leaked = [STAGE_LANE, SUBMIT_LANE, ADOPT_LANE].reject { |s| self_source.scan(s).empty? }
  assert leaked.empty?, "A0", "test/driver_argv_test.rb",
         "every lane name this suite matches against driver source is assembled from parts at " \
         "runtime and appears ZERO times as a literal in this file, so a future grep for one " \
         "of them cannot be fooled by this suite's own text: #{leaked.inspect}"
  assert ASC_WRITE_PATTERNS.none? { |p| self_source.match?(p) }, "A0", "test/driver_argv_test.rb",
         "the App Store Connect write patterns find ZERO candidates in this suite's own " \
         "source -- measured, not self-excluded by path, so A7 below cannot be reading its " \
         "own reflection"
  assert LAUNCH_PATTERNS.none? { |p| self_source.match?(p) }, "A0", "test/driver_argv_test.rb",
         "so do the subprocess-launch patterns. This suite launches children through " \
         "Open3, deliberately spelled differently from anything it greps for, so the same " \
         "measurement holds for A7's second half"

  # ─── A1: the positive controls, FIRST, per executed driver ────────────────
  EXECUTED.each do |d|
    bare = run_case.call(d[:rel], [])
    counts[d[:slug]]["bare"] = bare.shim_argv.length

    assert bare.shim_argv.length >= 1, "A1", d[:rel],
           "the positive control: a bare, fully-configured invocation DOES reach a capturing " \
           "shim (found #{bare.shim_argv.length}). Without this, every 'the shim log is empty' " \
           "assertion below could be satisfied by a harness that is simply incapable of " \
           "reaching a shim at all -- 05-19 measured exactly that, and only this control noticed"
    assert bare.shim_argv.any? { |l| l.include?(d[:a1_expect]) }, "A1", d[:rel],
           "the recorded argv contains #{d[:a1_expect].inspect} -- #{d[:a1_why]} -- so the shim " \
           "is observing the launch this suite is about rather than some unrelated child " \
           "(recorded: #{bare.shim_argv.join(' | ')})"
    assert !bare.stderr.match?(BACKTRACE), "A1", d[:rel],
           "the bare invocation reached the launch without raising, so the harness is " \
           "exercising the script's real path rather than dying early"
  end

  # ─── A2: the usage flags ───────────────────────────────────────────────────
  EXECUTED.each do |d|
    %w[--help -h].each do |flag|
      res = run_case.call(d[:rel], [flag])
      counts[d[:slug]][flag] = res.shim_argv.length

      assert res.status.zero?, "A2", d[:rel],
             "`#{flag}` exits 0 (got #{res.status.inspect}) -- asking what a command does is " \
             "not an error"
      d[:usage_must].each do |needle, why|
        assert res.printed.include?(needle), "A2", d[:rel],
               "`#{flag}` prints usage containing #{needle.inspect}: #{why}"
      end
      assert_reached_nothing.call(res, "A2")
    end
  end

  # ─── A3: refusal by name, flag-shaped and not ──────────────────────────────
  # Two shapes on purpose. A parser that only inspects arguments beginning with a
  # dash would ignore the second and fall through to the launch, which is the
  # exact failure this gate exists for.
  EXECUTED.each do |d|
    d[:unknown].each do |offender|
      res = run_case.call(d[:rel], [offender])
      counts[d[:slug]][offender] = res.shim_argv.length

      assert !res.status.zero?, "A3", d[:rel],
             "`#{offender}` exits non-zero (got #{res.status.inspect}); exiting 0 for an " \
             "argument nobody parsed is how a usage probe became a live call"
      assert res.status == d[:refusal_exit], "A3", d[:rel],
             "`#{offender}` uses this driver's documented argv exit code #{d[:refusal_exit]} " \
             "(got #{res.status.inspect}), which is distinguishable from 1 (a preflight " \
             "refused) and from 2 (the lane or workflow run itself failed) -- 'I do not " \
             "understand you' is a different outcome from either"
      assert res.printed.include?(offender), "A3", d[:rel],
             "the refusal names #{offender.inspect} verbatim rather than printing a generic " \
             "error; an argument that is refused without being named reads as ignored"
      assert_reached_nothing.call(res, "A3")
    end
  end

  # ─── A4: the dry-run contract, per driver ──────────────────────────────────
  EXECUTED.each do |d|
    spec = d[:dry_run]
    res  = run_case.call(d[:rel], [spec[:flag]])
    counts[d[:slug]][spec[:flag]] = res.shim_argv.length

    assert res.status.zero?, "A4", d[:rel],
           "`#{spec[:flag]}` exits 0 (got #{res.status.inspect})"

    if spec[:reaches_shim]
      # ship.rb's dry run is a REAL dispatch carrying dry_run=true; the flag's
      # meaning is the contract and this plan does not change it. What is asserted
      # is that the flag was PARSED and that the parse is visible in the argv that
      # was actually launched -- the near misses in A5 are where emptiness matters.
      joined = res.shim_argv.join(" | ")
      assert joined.include?(spec[:log_must_include]), "A4", d[:rel],
             "`#{spec[:flag]}` is HONOURED and the honouring is visible in the launched argv: " \
             "expected #{spec[:log_must_include].inspect} in #{joined.inspect}. This driver's " \
             "dry run dispatches with the dry-run input set rather than contacting nothing, " \
             "and that spelling is the pre-existing contract"
      assert !joined.include?(spec[:log_must_exclude]), "A4", d[:rel],
             "`#{spec[:flag]}` does NOT launch with #{spec[:log_must_exclude].inspect}, which " \
             "is what a run that silently ignored the flag would have done"
      assert !res.stderr.match?(BACKTRACE), "A4", d[:rel],
             "`#{spec[:flag]}` reached the dispatch without raising"
    else
      spec[:must_include].each do |needle, why|
        assert res.printed.include?(needle), "A4", d[:rel],
               "the dry run names #{needle.inspect}: #{why}. These strings exist only in the " \
               "sandbox fixtures, so this is also the measurement that the run read the " \
               "fixture config and never this repository's"
      end
      assert res.printed.downcase.include?("would"), "A4", d[:rel],
             "the dry run reports in the conditional -- what it WOULD do -- rather than " \
             "narrating something it did"
      assert_reached_nothing.call(res, "A4")
    end
  end

  # ─── A5: near-miss spellings ───────────────────────────────────────────────
  #
  # THE defect, in its own group. ARGV.include? matches exactly or not at all, so
  # before this gate every spelling below yielded dry_run="false" and a REAL ship
  # -- from an operator who had just typed the flag whose entire purpose is to
  # make the run harmless. A refusal is the only safe answer: guessing which flag
  # was meant is how a typo becomes a release.
  EXECUTED.each do |d|
    (d[:near_misses] || []).each do |offender|
      res = run_case.call(d[:rel], [offender])
      counts[d[:slug]][offender] = res.shim_argv.length

      assert res.status == d[:refusal_exit], "A5", d[:rel],
             "`#{offender}` -- a near miss for this driver's dry-run flag -- is REFUSED at " \
             "exit #{d[:refusal_exit]} (got #{res.status.inspect}) rather than silently " \
             "becoming a real run"
      assert res.printed.include?(offender), "A5", d[:rel],
             "the refusal names #{offender.inspect} verbatim, so the operator can see which " \
             "spelling was wrong instead of guessing"
      assert_reached_nothing.call(res, "A5")
    end

    (d[:also_accepted] || []).each do |flag|
      res = run_case.call(d[:rel], [flag])
      counts[d[:slug]][flag] = res.shim_argv.length

      assert res.status != d[:refusal_exit], "A5", d[:rel],
             "`#{flag}` is still ACCEPTED (got exit #{res.status.inspect}) -- its spelling is " \
             "the pre-existing contract, and a front door that refused it would be a " \
             "regression wearing a fix's clothes"
      assert res.shim_argv.any?, "A5", d[:rel],
             "`#{flag}` still reaches the launch, so the new parser did not quietly turn a " \
             "consenting argument into a no-op"
    end
  end

  # ─── A6: the guarded driver, observed on its refusing path only ────────────
  mint = "bin/mint-local-certs.rb"
  mint_res = run_case.call(mint, [])
  counts["mint"]["bare"] = mint_res.shim_argv.length

  assert !mint_res.status.zero?, "A6", mint,
         "under the ci-mode fixture this driver REFUSES (got exit #{mint_res.status.inspect}) " \
         "rather than proceeding -- and this fork is ci mode, which is why it is measured-safe " \
         "rather than in need of a front door"
  assert mint_res.printed.include?(RELEASE_KEY) || mint_res.printed.include?("local-mode-only"),
         "A6", mint,
         "the refusal names the guard that refused, so this observation is evidence the script " \
         "RAN and reached its guard rather than dying before it -- the anti-vacuity control " \
         "for a driver whose consenting path cannot be sandboxed"
  assert_reached_nothing.call(mint_res, "A6")

  # ─── A7: the two measured-safe drivers, asserted against their source ──────
  mint_src = sources_before[mint]
  assert mint_src.include?("ci_mode?"), "A7", mint,
         "the RELEASE_MODE guard is still present in the source. It is asserted rather than " \
         "commented: an unnamed safe driver is indistinguishable from an unaudited one, and a " \
         "later edit that drops this guard must turn this gate red"
  guard_at = mint_src.index("ci_mode?")
  work_at  = mint_src.index("do_it")
  assert guard_at && work_at && guard_at < work_at, "A7", mint,
         "the guard sits BEFORE the step that mints certificates into the login keychain " \
         "(guard at offset #{guard_at.inspect}, work at #{work_at.inspect}) -- a guard after " \
         "the work would read as present and protect nothing"

  verify = "bin/verify-testflight.rb"
  verify_src = sources_before[verify]
  write_hits = ASC_WRITE_PATTERNS.select { |p| verify_src.match?(p) }
  assert write_hits.empty?, "A7", verify,
         "no App Store Connect WRITE verb appears in this driver (#{ASC_WRITE_VERBS.join(', ')}, " \
         "or either submission lane name); it queries and reports, which is why it needs no " \
         "front door. Matched: #{write_hits.map(&:source).inspect}"
  # MEASURED 2026-09-04, and it corrects the audit table this plan was written
  # from. That table said "read-only against ASC, no writes found" and stopped
  # there. This driver is not launch-free: bin/verify-testflight.rb:83 shells out
  # to a `git fetch --tags --quiet origin`, a network call, to make the local tag
  # list current before deriving the expected version from it. That is still a
  # READ, so the disposition does not change -- but "launches nothing" would have
  # been a false statement in a gate whose whole point is that a safe driver is
  # named safe WITH its reason. The property asserted is therefore the true one:
  # every launch it makes is a git query, and none of them is a lane handoff.
  launch_lines = verify_src.lines.each_with_index
                           .select { |line, _| LAUNCH_PATTERNS.any? { |p| line.match?(p) } }
  lane_lines = launch_lines.select { |line, _| line.include?("fastlane") || line.include?("bundle") }
  assert lane_lines.empty?, "A7", verify,
         "every subprocess this driver launches is a git query -- none of the " \
         "#{launch_lines.length} launch site(s) hands off to a fastlane lane, so there is no " \
         "lane for an unparsed argument to fall through into, which is the property that " \
         "makes it safe without a front door. Lane-shaped launches found at line(s): " \
         "#{lane_lines.map { |_, i| i + 1 }.inspect}"
  assert launch_lines.map { |line, _| line }.all? { |line| line.include?("git") }, "A7", verify,
         "and each of those #{launch_lines.length} launch site(s) names git, so the sentence " \
         "above is a measurement of what they ARE rather than only of what they are not"
  # The measurement that the two assertions above are not vacuous: the same
  # patterns, run against a driver that DOES write and DOES launch, must hit.
  assert ASC_WRITE_PATTERNS.any? { |p| sources_before["bin/submit.rb"].match?(p) },
         "A7", "bin/submit.rb",
         "the write patterns DO match a driver that mutates App Store Connect, so the empty " \
         "result for #{verify} above is a property of that file rather than of a pattern that " \
         "matches nothing"
  assert LAUNCH_PATTERNS.any? { |p| sources_before["bin/submit.rb"].match?(p) },
         "A7", "bin/submit.rb",
         "the launch patterns DO match a driver that launches a subprocess, for the same reason"
rescue StandardError => e
  # A crash is not a pass. The subject of this suite is an unwanted EXECUTION, so
  # an exception that leaves the shim log empty is exactly the shape that reads as
  # success to anything counting FAIL lines. It gets one.
  @checks += 1
  @failures += 1
  puts "FAIL A0 -: the harness raised #{e.class}: " \
       "#{e.message.to_s.gsub(/\s*\n\s*/, ' ')} -- the suite did not finish, so nothing " \
       "below it was observed"
ensure
  FileUtils.remove_entry(sandbox) if sandbox && File.exist?(sandbox)
end

# ─── A8: restoration ─────────────────────────────────────────────────────────
assert sandbox && !File.exist?(sandbox), "A8", "-",
       "the sandbox was removed (#{sandbox})"
DRIVERS.each do |rel|
  assert File.read(File.join(ROOT, rel), encoding: "UTF-8") == sources_before[rel], "A8", rel,
         "the tracked script is byte-identical to what it was before this suite ran -- this " \
         "suite reads it and copies it, and never executes it in place"
end

# ─── the transcript lines ────────────────────────────────────────────────────
exit_code = @failures.zero? ? 0 : 1
puts
(EXECUTED.map { |d| [d[:slug], d[:rel]] } + [["mint", "bin/mint-local-certs.rb"]]).each do |slug, rel|
  recorded = counts[slug].map { |k, v| "#{k.tr(' ', '_')}=#{v}" }.join(" ")
  puts "RESULT control=driver-exec-reachable driver=#{rel} exit=#{exit_code} " \
       "shim_invocations #{recorded.empty? ? '(none recorded)' : recorded} restored=ok"
end
puts "RESULT control=driver-argv-front-door exit=#{exit_code} " \
     "drivers=#{DRIVERS.length} executed=#{EXECUTED.length} restored=ok"
puts
puts "#{@checks} check(s), #{@failures} failure(s)"
exit exit_code
