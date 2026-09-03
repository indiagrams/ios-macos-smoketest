#!/usr/bin/env ruby
# frozen_string_literal: true

# Durable guard for D-56: the bootstrap tooling creates NO GitHub Actions
# repository variables, so deleting APP_NAME / BUNDLE_ID from the live repo is
# a decision rather than a temporary state.
#
# WHY THIS FILE EXISTS
#
#   `Bootstrap::GHSecrets#do_it` used to end with:
#
#       variables = { "APP_NAME" => config["APP_NAME"], "BUNDLE_ID" => config["BUNDLE_ID"] }
#       variables.each { |key, val| Sh.run!("gh", "variable", "set", key, "--body", val, ...) }
#
#   and `check` returned :pending until both existed. So `make bootstrap-fork`
#   — and `bin/refork-smoketest.sh`, which calls it — RE-CREATED both variables
#   from the gitignored `.bootstrap.env` on the next run, with no output that
#   said so. Deleting them once would have looked done and silently come undone
#   the next time anyone bootstrapped: UL-003's shape (a repo whose own tooling
#   reverses a decision made against the repo), which is exactly what D-63 is
#   fixing for branch protection. D-56 as amended therefore requires the
#   GHSecrets edit to land in the SAME change as the live deletion, with this
#   test observed RED against the unedited code first.
#
#   The values were not merely redundant, they were WRONG. Measured 2026-09-02
#   (04-CONTEXT C-16): the live `BUNDLE_ID` variable read `com.indiagram.smokeapp`
#   — the TEMPLATE's bundle id — while the app's own is
#   `com.indiagram.shipkitpipes.ios`, and `release.yml` hard-errored if the
#   variable was unset. The release path was wired to the wrong app and nothing
#   had caught it because no build had ever been uploaded. Identity now resolves
#   in every workflow from `app/Identity.xcconfig` through `bin/lib/xcconfig.rb`
#   (D-57), which is the one file the BUILD resolves it from.
#
# WHAT THIS ASSERTS, AND HOW
#
#   Behaviourally, not textually, for the part that matters: `Bootstrap::Sh.run!`,
#   `Bootstrap::Sh.run`, `Bootstrap::Sh.ok?` and `IO.popen` are replaced with
#   capturing stubs that execute NOTHING, `GHSecrets#do_it` and `#check` are then
#   really invoked against a Tempfile `.bootstrap.env`, and the captured argv list
#   is the subject. That is why a stub, not a mock of the class under test: the
#   question is "what commands would a bootstrap run issue", and the only honest
#   way to ask it is to let the real method body run.
#
#   NEVER against the real `.bootstrap.env`: it is gitignored per-fork state, it
#   carries the operator's ASC ids, and a test that reads it would pass or fail
#   depending on whose machine it ran on. The fixture below is entirely synthetic.
#
#   One assertion IS textual (GHS7) and deliberately so: it scans the whole of
#   bin/lib/bootstrap.rb, not just GHSecrets, because a `gh variable set` added
#   to some OTHER step would resurrect the variables just as effectively and
#   would not be caught by exercising this one class.
#
# Failure-line contract (same shape as test/identity_test.rb and
# test/fastlane_identity_test.rb, deliberately — negative controls grep for it):
# every failed assertion prints ONE line, no leading whitespace,
#
#     FAIL GHS <path>: <message>
#
# Ruby core + stdlib only (tempfile / tmpdir / fileutils / pathname, all of which
# bin/lib/bootstrap.rb already requires), so the hermetic `parser-regression`
# job in .github/workflows/bootstrap-doctor-matrix.yml runs it with
# `bundler-cache: false`.
#
# Run under BOTH pinned interpreters:
#   /opt/homebrew/opt/ruby@3.3/bin/ruby test/gh_secrets_test.rb
#   /opt/homebrew/opt/ruby@4.0/bin/ruby test/gh_secrets_test.rb

$LOAD_PATH.unshift File.expand_path("../bin", __dir__)
require "lib/bootstrap"
require "tempfile"
require "tmpdir"
require "fileutils"
require "stringio"

ROOT      = File.expand_path("..", __dir__)
BOOTSTRAP = "bin/lib/bootstrap.rb"

# ─── harness (one-line FAIL contract) ────────────────────────────────────────

@failures = 0
@checks   = 0

def assert(condition, path, label)
  @checks += 1
  if condition
    puts "  ✓ GHS #{path}: #{label}"
  else
    puts "FAIL GHS #{path}: #{label.to_s.gsub(/\s*\n\s*/, ' ')}"
    @failures += 1
  end
end

# UTF-8 pinned, never inherited: with LANG unset Ruby defaults
# Encoding.default_external to US-ASCII and a non-ASCII byte raises out of a
# regex match instead of exiting 0 or 1 (UL-012, commit 3b1efb9).
def read_utf8(relative)
  File.read(File.join(ROOT, relative), encoding: "UTF-8")
end

# ─── capturing stubs ─────────────────────────────────────────────────────────

# Every argv array any stub saw, in order. This is the subject of the test.
CAPTURED = []

# Bootstrap::Sh is `module_function`, so each method exists twice: as a private
# instance method and as a singleton. GHSecrets calls the singleton form
# (`Sh.run!`), so that is the one replaced. Nothing here spawns a process.
module Bootstrap
  module Sh
    class << self
      def run!(*cmd, env: {}, cwd: nil)
        CAPTURED << cmd
        ""
      end

      def run(*cmd, env: {}, cwd: nil)
        CAPTURED << cmd
        [STUB_OUTPUT.call(cmd), true]
      end

      def ok?(*cmd, env: {}, cwd: nil)
        CAPTURED << cmd
        true
      end
    end
  end
end

# What a stubbed `gh … list` prints. `check` parses the first whitespace-
# delimited field of each line, so the shape matters more than the columns.
# Deliberately answers `gh variable list` with a repo that has NO APP_NAME and
# NO BUNDLE_ID — the post-deletion live state — so that a `check` which still
# consulted variables would report :pending forever and be caught below.
STUB_OUTPUT = lambda do |cmd|
  if cmd[0, 3] == %w[gh secret list]
    Bootstrap::REQUIRED_SECRETS.map { |s| "#{s}\tUpdated 2026-09-02" }.join("\n") + "\n"
  elsif cmd[0, 3] == %w[gh variable list]
    "DEPENDABOT_AUTOMERGE\ttrue\t2026-09-02\n"
  else
    ""
  end
end

# GHSecrets#do_it pipes each secret's VALUE to `gh secret set` over stdin rather
# than passing it as `--body`, so that the value never appears in a process
# listing. That is correct and stays; it just means the secret half is captured
# here rather than through Sh. `system("true")` is what makes the `$?.success?`
# check downstream of the popen see a successful status without a `gh` on PATH.
class << IO
  alias_method :popen_before_gh_secrets_test, :popen

  def popen(*args, **kwargs, &blk)
    argv = args.first
    if argv.is_a?(Array) && argv.first == "gh"
      CAPTURED << argv
      sink = StringIO.new
      blk&.call(sink)
      system("true")
      return ""
    end
    popen_before_gh_secrets_test(*args, **kwargs, &blk)
  end
end

# ─── synthetic .bootstrap.env ────────────────────────────────────────────────

# Every REQUIRED_ALWAYS key plus the CI-only one, with placeholder values, so
# the Config is complete without ever touching the operator's real file. The
# two identity keys carry obviously-fixture values: if either ever reached
# `gh variable set` again, the assertion below would name it.
tmpdir = Dir.mktmpdir("gh-secrets-test")
p8_path = File.join(tmpdir, "AuthKey_FIXTURE.p8")
File.write(p8_path, "-----BEGIN PRIVATE KEY-----\nfixture\n-----END PRIVATE KEY-----\n")
kc_path = File.join(tmpdir, "keychain-password")

FIXTURE_ENV = <<~ENVFILE
  APP_NAME=Fixture
  BUNDLE_ID=com.example.fixture
  DISPLAY_NAME=Fixture App
  APP_EMAIL=fixture@local.invalid
  GENERATOR=xcodegen
  RELEASE_MODE=ci
  PLATFORMS=ios,macos
  FASTLANE_TEAM_ID=FIXTURETEAM
  ASC_API_KEY_ID=FIXTUREKEYID
  ASC_API_KEY_ISSUER_ID=00000000-0000-0000-0000-000000000000
  ASC_API_KEY_P8_PATH=#{p8_path}
  KEYCHAIN_PASSWORD_FILE=#{kc_path}
  GH_ORG=fixture-org
  GH_APP_REPO=fixture-repo
ENVFILE

env_file = Tempfile.new([".bootstrap.env", ""])
env_file.write(FIXTURE_ENV)
env_file.flush

config = Bootstrap::Config.new(Bootstrap::Config.parse(Pathname.new(env_file.path)))
step   = Bootstrap::GHSecrets.new(config)

# ─── exercise ────────────────────────────────────────────────────────────────

check_result = step.check
check_argv   = CAPTURED.dup
CAPTURED.clear

step.do_it
do_it_argv = CAPTURED.dup

def gh_subcommand(argv, *words)
  argv.select { |cmd| cmd[0, words.length + 1] == ["gh"] + words }
end

variable_sets  = gh_subcommand(do_it_argv, "variable", "set")
secret_sets    = gh_subcommand(do_it_argv, "secret", "set")
variable_lists = gh_subcommand(check_argv, "variable", "list")
secret_lists   = gh_subcommand(check_argv, "secret", "list")

# ─── assertions ──────────────────────────────────────────────────────────────

# GHS1 is the whole point. It is phrased as a count with the offending argv in
# the message, so the RED run names the two commands it caught rather than just
# saying "expected 0".
assert variable_sets.empty?, BOOTSTRAP,
       "GHSecrets#do_it issues NO `gh variable set` calls " \
       "(a bootstrap run must not re-create the APP_NAME / BUNDLE_ID repository " \
       "variables D-56 deletes; saw #{variable_sets.length}: " \
       "#{variable_sets.map { |c| c.join(' ') }.inspect})"

assert variable_lists.empty?, BOOTSTRAP,
       "GHSecrets#check consults NO `gh variable list` " \
       "(a check that requires the variables reports :pending forever once they " \
       "are gone, which is how `make doctor` would nag a correctly-configured " \
       "fork into re-creating them; saw #{variable_lists.length})"

assert check_result == :done, BOOTSTRAP,
       "GHSecrets#check returns :done against a repo that has all 5 secrets and " \
       "NEITHER identity variable (got #{check_result.inspect}) — this is the " \
       "live post-deletion state"

assert !Bootstrap::GHSecrets.const_defined?(:REQUIRED_VARIABLES, false), BOOTSTRAP,
       "GHSecrets defines no REQUIRED_VARIABLES constant (the list of variables " \
       "the step demands is what made the variables load-bearing)"

# The step's real job must survive the edit — otherwise "no variables are set"
# would also be satisfied by a step that does nothing at all.
assert secret_sets.length == Bootstrap::REQUIRED_SECRETS.length, BOOTSTRAP,
       "GHSecrets#do_it still issues one `gh secret set` per REQUIRED_SECRETS " \
       "entry (#{Bootstrap::REQUIRED_SECRETS.length}); saw #{secret_sets.length}"

assert secret_sets.map { |c| c[3] }.sort == Bootstrap::REQUIRED_SECRETS.sort, BOOTSTRAP,
       "the five secrets set are exactly REQUIRED_SECRETS " \
       "(saw #{secret_sets.map { |c| c[3] }.sort.inspect})"

assert !secret_lists.empty?, BOOTSTRAP,
       "GHSecrets#check still lists the repo's secrets — the secrets half of the " \
       "step is untouched by D-56"

# GHS7 — textual, and whole-file on purpose: a `gh variable set` added to any
# OTHER step would resurrect the variables just as effectively as this one did.
source = read_utf8(BOOTSTRAP)
variable_set_lines = source.lines.each_with_index.filter_map do |line, i|
  i + 1 if line.match?(/"variable",\s*"set"/)
end
assert variable_set_lines.empty?, BOOTSTRAP,
       "no step anywhere in the file spawns `gh variable set` " \
       "(line(s) #{variable_set_lines.inspect})"

assert !source.match?(/REQUIRED_VARIABLES/), BOOTSTRAP,
       "the string REQUIRED_VARIABLES does not appear in the file"

assert !step.name.match?(/variable/i), BOOTSTRAP,
       "the step's doctor-facing name no longer advertises variables " \
       "(got #{step.name.inspect}) — a name is what an operator reads when " \
       "deciding whether a step did what they think"

# ─── teardown ────────────────────────────────────────────────────────────────

env_file.close!
FileUtils.remove_entry(tmpdir)

# ─── verdict ─────────────────────────────────────────────────────────────────

puts
if @failures.zero?
  puts "All #{@checks} GHSecrets assertions passed."
  exit 0
else
  puts "#{@failures} of #{@checks} GHSecrets assertion(s) failed."
  exit 1
end
