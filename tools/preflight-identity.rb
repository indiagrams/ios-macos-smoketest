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
# idiom for reading that safely is read_utf8 (commit 3b1efb9 is this
# repository's own fix for inheriting the locale instead). The consequence of
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
#   2    | app/Identity.xcconfig not found, or not a regular    | the resolved absolute path and the CWD
#        | file (a directory at that path is "not found" here)  |
#   3    | one or more required variables missing or empty      | every missing variable, comma-separated
#        | (a value that is only a `//` comment is empty)        |
#   4    | --require-team given and the team is unresolvable    | DEVELOPMENT_TEAM and app/Local.xcconfig
#
# Exit 2 versus exit 3 is the tools/asc-probe.rb idiom: not found is a distinct
# outcome from a failure, and it gets a distinct code, so "the file was never
# there" can never be read as "the file was checked".
#
# Usage:
#   ruby tools/preflight-identity.rb                  # from the repository root (CI)
#   ruby ../tools/preflight-identity.rb               # from app/ — XcodeGen's preGenCommand
#   ruby tools/preflight-identity.rb --require-team   # additionally require a resolvable DEVELOPMENT_TEAM
#   ruby tools/preflight-identity.rb --config PATH    # check PATH instead of app/Identity.xcconfig (fixtures only)
#
# Ruby stdlib only. No gem, no Gemfile entry, no test framework, no `require`
# at all: a `require` of anything outside core would force bundler-cache: true
# on a required-context job.

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
  usage: ruby tools/preflight-identity.rb [--require-team] [--config PATH]
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

# Pin UTF-8 rather than inheriting the locale. With LANG unset — a bare
# container, `env -i`, launchd — Ruby's default external encoding is US-ASCII
# and the © in COPYRIGHT raises ArgumentError out of the regex match instead
# of producing a verdict. Same fix as tools/gen-review-notes.rb (3b1efb9).
def read_utf8(path)
  File.read(path, encoding: "UTF-8")
end

# Anchored key match, then a non-empty test on the value AFTER its `//` comment
# is cut off. Regexp.escape so a key name can never be read as a pattern. Two
# things are load-bearing, both observed on Xcode 26.1.1 via
# `xcodebuild -showBuildSettings` (evidence/03-SEC-T0306-comment-value-fix.txt):
#
#   - `BUNDLE_ID =` with nothing after the equals sign must NOT count: that is
#     precisely the case Xcode silently treats as the empty string.
#   - `//` opens a comment at ANY position in the value, not only at the start:
#     `KEY = // disabled` and `KEY = //` both resolve to "" (the key is absent
#     from the dump), `KEY = value // note` resolves to `value`, and even
#     `KEY = https://example.com/x` resolves to `https:`. A lone `/` resolves to
#     `/` and `a/b` to `a/b` — a slash is a real character; only `//` is a
#     comment opener. So the value is cut at the first `//` before the
#     non-empty test, and nothing tighter: a legitimate COPYRIGHT may contain
#     a `/`.
#
# The earlier predicate ended in `\S`, which matched the first `/` of a
# commented-out value and let `BUNDLE_ID = // temporarily disabled` through at
# exit 0 while Xcode resolved it to "" — the gate and test/identity_test.rb G1
# shared the regex and failed together (03-SECURITY.md T-03-06 / F-01,
# 03-REVIEW.md WR-01). The body below is byte-identical to the one in
# test/identity_test.rb; keep them that way.
def defines_non_empty?(text, key)
  text.each_line.any? do |line|
    value = line[/\A[ \t]*#{Regexp.escape(key)}[ \t]*=(.*)/, 1]
    !value.nil? && !value.sub(%r{//.*}, "").strip.empty?
  end
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
# passes File.exist? and then read_utf8 raises Errno::EISDIR — Ruby's exit 1
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
# Collect every miss before reporting, so one run names all of them rather
# than only the first.

identity_text = read_utf8(config)
missing = REQUIRED_VARS.reject { |key| defines_non_empty?(identity_text, key) }

unless missing.empty?
  fail_with 3, "#{config} is missing required variable(s): #{missing.join(", ")}. " \
               "Each must be defined with a non-empty value; a missing key resolves to the " \
               "empty string and both generators would exit 0 with an empty CFBundleIdentifier."
end

# --- exit 4: --require-team and the team does not resolve --------------------
# The team is resolved the way the build resolves it — from the RESOLVED set,
# not from Identity.xcconfig alone. Local.xcconfig is the sibling of whichever
# config is being checked (app/Local.xcconfig by default), which is exactly what
# `#include? "Local.xcconfig"` in Identity.xcconfig will read.

if require_team
  local = config_override.nil? ? LOCAL_XCCONFIG : File.expand_path("Local.xcconfig", File.dirname(config))

  if defines_non_empty?(identity_text, TEAM_VAR)
    # Satisfies the check, but this is precisely the leak IDENT-08 removes:
    # a Team ID defined in the tracked file is a Team ID in git.
    warn "IDENTITY PREFLIGHT WARNING (IDENT-08): #{TEAM_VAR} is defined in #{config}, " \
         "which is tracked. The Team ID belongs in gitignored app/Local.xcconfig only; " \
         "a value in the tracked file is exactly the leak this phase removes."
  else
    # Same File.file? discipline as the exit-2 branch above: a directory named
    # Local.xcconfig must produce the exit-4 message, not an EISDIR backtrace.
    local_is_file = File.file?(local)
    team_resolved = local_is_file && defines_non_empty?(read_utf8(local), TEAM_VAR)
    unless team_resolved
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
