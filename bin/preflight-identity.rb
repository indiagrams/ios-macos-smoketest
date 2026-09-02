#!/usr/bin/env ruby
# frozen_string_literal: true

# Refuse to generate a project against an incomplete identity — and NAME the
# variable that is missing, before either generator runs.
#
# Why this exists: app/Identity.xcconfig is the tracked source of truth for
# BUNDLE_ID, APP_PRODUCT_NAME, DISPLAY_NAME and COPYRIGHT (D-45, D-49). Nothing
# in XcodeGen or Tuist asserts that a variable a manifest references actually
# exists. If a key is missing from a present Identity.xcconfig, `$(BUNDLE_ID)`
# resolves to the empty string, BOTH generators exit 0 and write a project, and
# the macOS build then succeeds with an empty CFBundleIdentifier (RESEARCH
# Pitfall 1, observed on Xcode 26.1.1). That is the phase's worst failure mode:
# every exit code on the path is 0 and the defect surfaces as an unlaunchable
# .app. This script is ROADMAP criterion 5 / IDENT-09: generation fails loudly,
# naming the specific missing variable, instead of exiting 0 with a hole in it.
#
# Language: Ruby. This is a decision, not a default. `git ls-files tools/`
# returns exactly two files, both Ruby (asc-probe.rb, gen-review-notes.rb); the
# fork owns no shell script anywhere. The `review notes` job — one of the nine
# required status contexts — runs ubuntu-latest with bundler-cache: false and
# no Xcode, and already runs four Ruby entry points, so a Ruby preflight joins
# that step with no new tooling. COPYRIGHT carries © (U+00A9), and the fork's
# idiom for reading that safely is an explicit `encoding: "UTF-8"`, which
# bin/lib/xcconfig.rb pins on every read (commit 3b1efb9 is this repository's
# own fix for inheriting the locale instead). The consequence of
# the decision: 03-RESEARCH.md observed exit 2 / exit 3 / "no project written"
# against a BASH draft of this gate. Those observations do not transfer across
# implementations, so every exit path below was re-observed against THIS file,
# under both pinned interpreters (03-02-SUMMARY.md, evidence/03-02-T*.txt).
#
# Exit-code contract:
#
#   Exit | Meaning                                              | Message must name
#   -----+------------------------------------------------------+---------------------------------------------
#   0    | every required variable present and non-empty        | — (prints `identity preflight ok`)
#   1    | unknown or malformed argv                            | the offending argument and the usage line
#   2    | app/Identity.xcconfig not found, or not a regular    | the resolved absolute path and the CWD;
#        | file (a directory at that path is "not found" here); | for an include, the include and where it
#        | or present but not resolvable, because a hard        | was looked for
#        | `#include` in it is missing or the includes cycle    |
#   3    | one or more required variables missing or empty      | every missing variable, comma-separated
#        | (a value that is only a `//` comment is empty)        |
#   4    | --require-team given and the team is unresolvable    | DEVELOPMENT_TEAM and app/Local.xcconfig
#
# Exit 2 versus exit 3 is the tools/asc-probe.rb idiom: not found is a distinct
# outcome from a failure, and it gets a distinct code, so "the file was never
# there" can never be read as "the file was checked".
#
# Usage:
#   ruby bin/preflight-identity.rb                  # from the repository root (CI)
#   ruby ../bin/preflight-identity.rb               # from app/ — XcodeGen's preGenCommand
#   ruby bin/preflight-identity.rb --require-team   # additionally require a resolvable DEVELOPMENT_TEAM
#   ruby bin/preflight-identity.rb --config PATH    # check PATH instead of app/Identity.xcconfig (fixtures only)
#
# Ruby stdlib only. No gem, no Gemfile entry, no test framework. This file has
# exactly ONE `require`-family line — `require_relative "lib/xcconfig"`, a
# RELATIVE load of a sibling file in this repository which itself has zero
# `require` lines, not even a stdlib one (test/xcconfig_test.rb asserts that, so
# it cannot rot). Nothing outside Ruby core is loaded on any path, which is what
# lets the `review notes` required-context job keep `bundler-cache: false`; a
# `require` of anything outside core would force it to true.
#
# Why the parser and not a predicate in this file: until 04-03 this file carried
# its own `defines_non_empty?`, byte-identical by design to a copy in
# test/identity_test.rb, while ci/local-release-check.sh and fastlane read the
# same xcconfig two more ways — four readers, mutually incompatible, each right
# about the happy value and wrong about the next one (C-17, UL-031, UL-032).
# D-57 is one body; this is one of its callers.

# The single load. `__dir__`-relative, so it resolves the same from the
# repository root (CI), from app/ (XcodeGen's preGenCommand) and from anywhere
# else a caller happens to stand.
require_relative "lib/xcconfig"

# Paths are resolved from __dir__, never from the CWD. XcodeGen's preGenCommand
# runs with CWD = app/ (both `cd app && xcodegen generate` and
# `xcodegen generate -s app/project.yml`, observed); CI runs from the repository
# root. One constant is correct under both, and there is no positional path
# argument for a caller to get wrong.
IDENTITY_XCCONFIG = File.expand_path("../app/Identity.xcconfig", __dir__)
LOCAL_XCCONFIG = File.expand_path("../app/Local.xcconfig", __dir__)

# The required list is a frozen constant, duplicated deliberately, and is NEVER
# read out of the file under test. A gate that derived its required list from
# its subject would accept whatever the subject happened to say.
REQUIRED_VARS = %w[BUNDLE_ID APP_PRODUCT_NAME DISPLAY_NAME COPYRIGHT].freeze

# The team variable is checked only under --require-team; see the flag below
# for the verified reason it is not part of REQUIRED_VARS.
TEAM_VAR = "DEVELOPMENT_TEAM"

# Every failure line carries this prefix so it is greppable out of a
# generator's interleaved output.
FAIL_PREFIX = "IDENTITY PREFLIGHT FAILED:"

USAGE = <<~USAGE
  usage: ruby bin/preflight-identity.rb [--require-team] [--config PATH]
    --require-team   also require DEVELOPMENT_TEAM to resolve from app/Local.xcconfig (exit 4 if not)
    --config PATH    check PATH instead of app/Identity.xcconfig; prints a banner to stderr on every use
    -h, --help       print this usage and exit 0
USAGE

# Every failure path is explicit and loud. There is no broad rescue anywhere in
# this file: a silently tolerated error here means a project generated against
# an empty identity, which is exactly the defect this file exists to prevent.
def fail_with(code, message)
  warn "#{FAIL_PREFIX} #{message}"
  exit code
end

# --- argv -------------------------------------------------------------------
# Exactly two flags are accepted. Unknown argv is rejected, never ignored: a
# typo'd flag must not look like a successful run.

require_team = false
config_override = nil
argv = ARGV.dup
until argv.empty?
  arg = argv.shift
  case arg
  when "--require-team"
    # Opt-in, and NOT passed by app/project.yml's preGenCommand. Verified
    # reason, not a safety argument: the six required `app (…)` status contexts
    # build unsigned — .github/workflows/pr.yml passes CODE_SIGN_IDENTITY="",
    # CODE_SIGNING_REQUIRED=NO and CODE_SIGNING_ALLOWED=NO on all three build
    # steps (lines 252-254, 273-275, 289-291, read 2026-09-01), and GitHub
    # runners have no app/Local.xcconfig because it is gitignored. A team check
    # inside preGenCommand would therefore fail every one of those six required
    # contexts on every pull request. Do not "fix" this by making it default.
    require_team = true
  when "--config"
    path = argv.shift
    if path.nil? || path.empty? || path.start_with?("--")
      warn "#{FAIL_PREFIX} --config requires a PATH argument\n#{USAGE}"
      exit 1
    end
    unless config_override.nil?
      warn "#{FAIL_PREFIX} --config given more than once\n#{USAGE}"
      exit 1
    end
    config_override = File.expand_path(path)
  when "-h", "--help"
    puts USAGE
    exit 0
  else
    warn "#{FAIL_PREFIX} unknown argument #{arg.inspect}\n#{USAGE}"
    exit 1
  end
end

config = config_override || IDENTITY_XCCONFIG

# Loud on every use, so an overridden run can never be mistaken for a default
# one in a log. The hole this flag would otherwise open — pointing the gate at
# a fixture during a real generate — is closed on the other side by
# test/identity_test.rb G4, which asserts app/project.yml's preGenCommand
# passes no --config.
unless config_override.nil?
  warn "IDENTITY PREFLIGHT: ==== --config OVERRIDE IN EFFECT ===="
  warn "IDENTITY PREFLIGHT: default config #{IDENTITY_XCCONFIG} was NOT checked"
  warn "IDENTITY PREFLIGHT: checking override #{config_override} instead"
end

# --- exit 2: the file is not there ------------------------------------------
# File.file?, not File.exist?: a directory (or a socket, a fifo) at the path
# passes File.exist? and then the read raises Errno::EISDIR — Ruby's exit 1
# with a backtrace, which the contract reserves for malformed argv, so a
# caller branching on the code misreads "the file is not there" as "you called
# me wrong" (03-REVIEW IN-01, reproduced with --config app under both pinned
# interpreters). A non-regular path is "not found" for this gate's purposes.

unless File.file?(config)
  state = if File.directory?(config)
            "is a directory, not a file"
          elsif File.exist?(config)
            "is not a regular file"
          else
            "not found"
          end
  fail_with 2, "#{config} #{state} (cwd: #{Dir.pwd}). " \
               "app/Identity.xcconfig is the tracked identity source of truth (D-45); " \
               "generation must not proceed without it."
end

# --- exit 3: a required variable is missing or present-but-empty -------------
# Resolution goes through Xcconfig (D-57) — the same body test/identity_test.rb
# and ci/local-release-check.sh read through, so the gate, its guard and the
# release path cannot disagree about what "the value" is. `value` returns nil
# for a key that was never assigned and "" for one that is assigned but empty,
# comment-only, or resolves through undefined references to nothing; a gate
# treats both as missing, which is exactly what the deleted `defines_non_empty?`
# did. The parser also does what that predicate could not: it follows
# `#include?`, so a variable supplied by an included file counts, and it cuts
# `//` at any position, which is the UL-031 hole.
#
# Collect every miss before reporting, so one run names all of them rather
# than only the first.

begin
  missing = REQUIRED_VARS.reject do |key|
    value = Xcconfig.value(config, key)
    !value.nil? && !value.empty?
  end
rescue Xcconfig::MissingInclude => e
  # A hard `#include` that is not there, or an include cycle. The parser raises
  # rather than returning what it managed to read, deliberately (04-02): "your
  # include is broken" must never arrive as "that key is empty". So it maps onto
  # exit 2 — the config could not be READ — and never onto exit 3, and a caller
  # branching on the code is not told a variable is missing from a file that was
  # never resolvable in the first place. Xcode refuses this file too. The
  # predicate deleted above read the text line by line, never saw the include at
  # all, and exited 0 on it (baseline recorded in
  # .planning/…/evidence/04-03-T1-preflight-baseline-vs-after.txt).
  fail_with 2, "#{config} could not be resolved: #{e.message}. " \
               "Fix the #include, or make it optional (`#include?`, which is silent when the " \
               "file is absent), before generating."
end

unless missing.empty?
  fail_with 3, "#{config} is missing required variable(s): #{missing.join(", ")}. " \
               "Each must be defined with a non-empty value; a missing key resolves to the " \
               "empty string and both generators would exit 0 with an empty CFBundleIdentifier."
end

# --- exit 4: --require-team and the team does not resolve --------------------
# Local.xcconfig is the sibling of whichever config is being checked
# (app/Local.xcconfig by default), which is exactly the file
# `#include? "Local.xcconfig"` in Identity.xcconfig reads. It is read directly
# here rather than through the include, so the two questions below stay
# separable — see the comment on `tracked_team`.

if require_team
  local = config_override.nil? ? LOCAL_XCCONFIG : File.expand_path("Local.xcconfig", File.dirname(config))

  # TWO DIFFERENT QUESTIONS, and asking the wrong one here is a false security
  # warning on every developer machine.
  #
  # This branch asks the IDENT-08 leak question: is a Team ID sitting in a file
  # that is IN GIT? That is about one file's own text. `Xcconfig.value` answers
  # the other question — what would Xcode resolve DEVELOPMENT_TEAM to here — and
  # app/Identity.xcconfig ends with `#include? "Local.xcconfig"` (D-50), so on
  # every machine that has the gitignored file `value` returns the LOCAL team and
  # this branch would announce a tracked-file leak that does not exist. Measured
  # 2026-09-02: a fixture whose own text assigns no team resolved to `LOCALONLY9`
  # through `value`. `Xcconfig.own` does not follow includes, and is the question
  # actually being asked. Raw and unexpanded, matching the deleted predicate.
  tracked_team = Xcconfig.own(config)[TEAM_VAR]

  if !tracked_team.nil? && !tracked_team.empty?
    # Satisfies the check, but this is precisely the leak IDENT-08 removes:
    # a Team ID defined in the tracked file is a Team ID in git.
    warn "IDENTITY PREFLIGHT WARNING (IDENT-08): #{TEAM_VAR} is defined in #{config}, " \
         "which is tracked. The Team ID belongs in gitignored app/Local.xcconfig only; " \
         "a value in the tracked file is exactly the leak this phase removes."
  else
    # Same File.file? discipline as the exit-2 branch above: a directory named
    # Local.xcconfig must produce the exit-4 message, not an EISDIR backtrace.
    local_is_file = File.file?(local)
    local_team = begin
                   local_is_file ? Xcconfig.value(local, TEAM_VAR) : nil
                 rescue Xcconfig::MissingInclude => e
                   fail_with 2, "#{local} could not be resolved: #{e.message}."
                 end
    unless !local_team.nil? && !local_team.empty?
      # This message has to exist because Xcode's own behaviour is useless
      # here: on iOS it says `requires a development team` (names the concept,
      # not the variable or the file); on macOS it says NOTHING AT ALL — the
      # build succeeds with `Signing Identity: "Sign to Run Locally"` (C-16,
      # observed on Xcode 26.1.1). Neither names DEVELOPMENT_TEAM or the file
      # that should have defined it. This one does.
      state = if local_is_file
                "present but does not define #{TEAM_VAR} with a non-empty value"
              elsif File.exist?(local)
                "present but not a regular file"
              else
                "not found"
              end
      fail_with 4, "#{TEAM_VAR} is unresolvable: app/Local.xcconfig (#{local}) is #{state}. " \
                   "Create app/Local.xcconfig (gitignored) containing `#{TEAM_VAR} = <your Team ID>`; " \
                   "it is never committed. Note that Xcode would not report this on macOS " \
                   "(the build succeeds with an ad-hoc signature)."
    end
  end
end

puts "identity preflight ok"
exit 0
