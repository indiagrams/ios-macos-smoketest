#!/usr/bin/env ruby
# frozen_string_literal: true

# Unit test for the doctor's VERIFICATION TIERS (D-64, IDENT-13).
#
# WHY THIS EXISTS
#
# Upstream's ci/check-app-icon.sh header records the failure this file is the
# answer to: "doctor's Icon1024 step compares the icon's hash against
# ICON_1024_PATH, so pointing that at a placeholder reports 'done'. Presence was
# verified; content never was." That cost a full App Review cycle on a Guideline
# 2.3.8 rejection. Every CI cell was green. 04-05 hit the same shape from another
# angle — a binary scan that returned 0 for strings that were definitely present.
#
# So "tier" in this project means DEPTH OF VERIFICATION, not surface (D-64):
#
#   tier 1  the thing exists
#   tier 2  its content is not the template's
#   tier 3  the value the build or Apple actually resolves is not the template's
#
# The tests below pin three things, and the third is the one that makes the other
# two hold over time:
#
#   1. Bootstrap::IdentityAdopted climbs the tiers and, on failure, names the
#      TIER and the OFFENDING VALUE — not a generic "identity check failed".
#   2. Bootstrap::Icon1024 verifies the icon's CONTENT (via ci/check-app-icon.sh)
#      and not merely that a file with the right hash is in place.
#   3. Bootstrap::Runner#render_result turns a :done from a step that did not
#      reach its own MIN_TIER into [:blocked, …]. The guard lives in the RUNNER,
#      so a future step cannot opt out of it by being sloppy. A step's own
#      discipline is exactly what failed in the icon story.
#
# Runnable locally under both pinned interpreters:
#   ruby test/doctor_identity_test.rb
#   /opt/homebrew/opt/ruby@4.0/bin/ruby test/doctor_identity_test.rb
#
# CI caller: .github/workflows/review-notes.yml's Ruby step, inside the job
# named `review notes` — one of the nine required status contexts. That runner
# is ubuntu-latest with bundler-cache: false, no Xcode, no .bootstrap.env and
# NO GENERATED app/App.xcodeproj, so nothing here may depend on any of them.
# The tier-3 group below substitutes a fixture project directory for exactly
# that reason; see check_identity's `xcodeproj:` argument.
#
# Stdlib only, and NO network / Apple / xcodebuild: Sh.run is stubbed with a
# lambda table keyed on argv[0..1], the same shape test/gh_secrets_test.rb uses.

$LOAD_PATH.unshift File.expand_path("../bin", __dir__)
require "lib/bootstrap"
require "tempfile"
require "tmpdir"
require "stringio"
require "digest"

@failures = 0

def assert_eq(actual, expected, label)
  if actual == expected
    puts "  ✓ #{label}"
  else
    puts "  ✗ #{label}"
    puts "    expected: #{expected.inspect}"
    puts "    actual:   #{actual.inspect}"
    @failures += 1
  end
end

def assert(cond, label)
  assert_eq(!!cond, true, label)
end

def assert_blocked(result, needle, label)
  unless result.is_a?(Array) && result[0] == :blocked
    puts "  ✗ #{label}"
    puts "    expected: [:blocked, /#{needle}/]"
    puts "    actual:   #{result.inspect}"
    @failures += 1
    return
  end
  if result[1].include?(needle)
    puts "  ✓ #{label}"
  else
    puts "  ✗ #{label}"
    puts "    expected message to contain: #{needle.inspect}"
    puts "    actual message:              #{result[1].inspect}"
    @failures += 1
  end
end

def assert_warn(result, needle, label)
  unless result.is_a?(Array) && result[0] == :warn
    puts "  ✗ #{label}"
    puts "    expected: [:warn, /#{needle}/]"
    puts "    actual:   #{result.inspect}"
    @failures += 1
    return
  end
  if result[1].include?(needle)
    puts "  ✓ #{label}"
  else
    puts "  ✗ #{label}"
    puts "    expected message to contain: #{needle.inspect}"
    puts "    actual message:              #{result[1].inspect}"
    @failures += 1
  end
end

# ─── Preconditions: fail loudly and specifically if the surface is absent ─────
#
# This is the RED assertion. Before the implementation lands, the file must say
# WHICH constant is missing rather than dying on a NameError backtrace.

missing = []
missing << "IdentityAdopted not defined" unless Bootstrap.const_defined?(:IdentityAdopted)
missing << "Step#detail not defined" unless Bootstrap::Step.method_defined?(:detail)
missing << "Step#tier_reached not defined" unless Bootstrap::Step.method_defined?(:tier_reached)
missing << "Runner#render_result not defined" unless Bootstrap::Runner.method_defined?(:render_result)
# 05-17. app/Identity.xcconfig:39-44 carries `#include? "Local.xcconfig"` and
# .bootstrap.env.example ships FASTLANE_TEAM_ID, but until this step existed NOTHING
# wrote the file in between: 05-11 enumerated bin/lib/bootstrap.rb's file-write call
# sites and found zero, with a positive control proving the predicate could see
# (re-measured 2026-09-03 — bootstrap 0 / grep_raw 1, against 14 in
# tools/migrate-identity.rb, 13 in bin/preflight-identity.rb, 4 in bin/rename.sh).
# A fresh forker's first signed iOS build was the discovery mechanism.
missing << "LocalSigningTeam not defined — nothing writes app/Local.xcconfig from FASTLANE_TEAM_ID" unless Bootstrap.const_defined?(:LocalSigningTeam)
unless missing.empty?
  missing.each { |m| puts "  FAIL DR bin/lib/bootstrap.rb: #{m}" }
  puts
  puts "FAILED (#{missing.length} missing definition(s))"
  exit 1
end

# ─── Harness ──────────────────────────────────────────────────────────────────

# A Config with every REQUIRED_ALWAYS key filled, so nothing in the step under
# test trips over an unrelated missing field. APP_NAME/BUNDLE_ID default to the
# sound fixture's values; callers override to drive the D-59 disagreement case.
def config_for(app_name: "ShipkitPipes", bundle_id: "com.indiagram.shipkitpipes.ios", extra: {})
  values = {
    "APP_NAME" => app_name,
    "BUNDLE_ID" => bundle_id,
    "DISPLAY_NAME" => "Shipkit Pipes",
    "APP_EMAIL" => "placeholder@example.com",
    "GENERATOR" => "xcodegen",
    "RELEASE_MODE" => "local",
    "FASTLANE_TEAM_ID" => "PLACEHOLD9",
    "ASC_API_KEY_ID" => "PLACEHOLDER",
    "ASC_API_KEY_ISSUER_ID" => "PLACEHOLDER",
    "ASC_API_KEY_P8_PATH" => "/dev/null",
    "GH_ORG" => "indiagrams",
    "GH_APP_REPO" => "ios-macos-smoketest"
  }.merge(extra)
  Bootstrap::Config.new(values)
end

SOUND_XCCONFIG = <<~XC
  // fixture
  BUNDLE_ID        = com.indiagram.shipkitpipes.ios
  APP_PRODUCT_NAME = ShipkitPipes
  DISPLAY_NAME     = Shipkit Pipes
  COPYRIGHT        = Copyright © 2026 Indiagram LLC. All rights reserved.
XC

def write_fixture(dir, text, name = "Identity.xcconfig")
  path = File.join(dir, name)
  File.write(path, text)
  path
end

# Stub Bootstrap::Sh.run with a table keyed on argv[0..1]. An unstubbed command
# raises rather than shelling out — a test that silently ran xcodebuild would be
# the same class of defect this file exists to catch.
def with_sh_stub(table)
  original = Bootstrap::Sh.method(:run)
  Bootstrap::Sh.define_singleton_method(:run) do |*cmd, **_kw|
    handler = table[cmd[0..1]]
    raise "unstubbed Sh.run: #{cmd.inspect}" if handler.nil?
    handler.call(cmd)
  end
  yield
ensure
  Bootstrap::Sh.define_singleton_method(:run, original)
end

def with_env(pairs)
  old = {}
  pairs.each { |k, v| old[k] = ENV[k]; v.nil? ? ENV.delete(k) : ENV[k] = v }
  yield
ensure
  old.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
end

def capture_stderr
  old = $stderr
  $stderr = StringIO.new
  yield
  $stderr.string
ensure
  $stderr = old
end

# UTF-8 pinned, never inherited. .bootstrap.env.example and bin/lib/bootstrap.rb
# both carry non-ASCII bytes (`—`, `©`); with LANG unset Ruby defaults
# Encoding.default_external to US-ASCII and a non-ASCII byte raises
# ArgumentError out of a regex match instead of exiting 0 or 1. Commit 3b1efb9
# is this repository's own instance of that defect (UL-012).
def read_utf8(relative)
  File.read(Bootstrap::REPO_ROOT.join(relative).to_s, encoding: "UTF-8")
end

# Runs an argv ARRAY from the repository root — never a string, which would
# re-enter /bin/sh. Returns [combined stdout+stderr, exit status]. The exit
# status is the point: `git grep` exits 0 on a match, 1 on no match and 128 on
# an error, and only "no match" is evidence of absence.
def run_argv(argv)
  out = IO.popen(argv, "r", err: [:child, :out], chdir: Bootstrap::REPO_ROOT.to_s, &:read)
  [out.to_s, $?.exitstatus]
end

XCODEBUILD_PRESENT = { %w[which xcodebuild] => ->(_) { ["/usr/bin/xcodebuild\n", true] } }.freeze

def settings_dump(bundle_id:, product_name:)
  <<~DUMP
    Build settings for action build and target App-iOS:
        PRODUCT_BUNDLE_IDENTIFIER = #{bundle_id}
        PRODUCT_MODULE_NAME = App_iOS
        PRODUCT_NAME = #{product_name}
        PRODUCT_TYPE = com.apple.product-type.application
  DUMP
end

# `xcodeproj:` substitutes the generated project directory the tier-3 gate looks
# for. app/App.xcodeproj is GITIGNORED — XcodeGen or Tuist generates it — so on a
# fresh checkout (a CI runner, a clone, a forker who has not run `make bootstrap`
# yet) it does not exist, and `check` short-circuits to a tier-2 warn before
# xcodebuild is ever consulted. Measured 2026-09-03: seven assertions in the
# tier-3 group below failed exactly that way in a clone with no generated
# project, while passing on a machine that happened to have one. Substituting a
# fixture directory keeps this a unit test of how `check` reads xcodebuild's
# OUTPUT — which is already stubbed — instead of a test of whether this machine
# has generated a project.
def check_identity(xcconfig_path, config, sh_table, xcodeproj: nil)
  with_env("IDENTITY_XCCONFIG" => xcconfig_path) do
    step = Bootstrap::IdentityAdopted.new(config)
    unless xcodeproj.nil?
      fixture = Pathname.new(xcodeproj)
      step.define_singleton_method(:xcodeproj_path) { fixture }
    end
    result = nil
    capture_stderr { result = with_sh_stub(sh_table) { step.check } }
    [step, result]
  end
end

# A generated project is a DIRECTORY (`.xcodeproj` is a bundle), which is what
# the tier-3 gate tests for.
def write_xcodeproj_fixture(dir, name = "App.xcodeproj")
  path = File.join(dir, name)
  Dir.mkdir(path)
  path
end

puts "Bootstrap::IdentityAdopted — tier 1 (the thing exists)"

Dir.mktmpdir do |dir|
  ghost = File.join(dir, "Nope.xcconfig")
  _step, result = check_identity(ghost, config_for, {})
  assert_blocked(result, "tier 1 failed: #{ghost} is missing",
                 "missing xcconfig is tier 1, and the message names the path")
end

puts
puts "Bootstrap::IdentityAdopted — tier 2 (content is not the template's)"

Dir.mktmpdir do |dir|
  path = write_fixture(dir, SOUND_XCCONFIG.sub("com.indiagram.shipkitpipes.ios", "com.indiagram.smokeapp"))
  _step, result = check_identity(path, config_for(bundle_id: "com.indiagram.smokeapp"), {})
  assert_blocked(result, "tier 2 failed: BUNDLE_ID = com.indiagram.smokeapp (template identity)",
                 "the template bundle id is named with its value")
end

Dir.mktmpdir do |dir|
  # Lowercased on purpose: a rename that lower-cases the template name has not
  # adopted anything, and a case-sensitive compare would call it adopted.
  path = write_fixture(dir, SOUND_XCCONFIG.sub("ShipkitPipes", "helloapp"))
  _step, result = check_identity(path, config_for(app_name: "helloapp"), {})
  assert_blocked(result, "tier 2 failed: APP_PRODUCT_NAME = helloapp (template identity)",
                 "template identity compare is case-insensitive")
end

Dir.mktmpdir do |dir|
  placeholder = "TODO Copyright © 2026 <Your Org>. All rights reserved."
  path = write_fixture(dir, SOUND_XCCONFIG.sub(/COPYRIGHT.*$/, "COPYRIGHT        = #{placeholder}"))
  _step, result = check_identity(path, config_for, {})
  assert_blocked(result, "tier 2 failed: COPYRIGHT = #{placeholder} (template identity)",
                 "the copyright placeholder is template identity, prefix-matched")
end

Dir.mktmpdir do |dir|
  # `// disabled` is UL-031's shape: the line is present, so a presence check
  # passes; the parser cuts at `//`, so the VALUE is empty.
  path = write_fixture(dir, SOUND_XCCONFIG.sub(/DISPLAY_NAME.*$/, "DISPLAY_NAME     = // disabled"))
  _step, result = check_identity(path, config_for, {})
  assert_blocked(result, "tier 2 failed: DISPLAY_NAME is missing or empty in #{path}",
                 "a comment-only value is empty, not present")
end

Dir.mktmpdir do |dir|
  path = write_fixture(dir, SOUND_XCCONFIG)
  _step, result = check_identity(path, config_for(bundle_id: "com.indiagram.stale.ios"), {})
  assert_blocked(result, ".bootstrap.env BUNDLE_ID = com.indiagram.stale.ios disagrees",
                 "D-59: .bootstrap.env disagreeing with the xcconfig is a tier 2 failure")
  assert(result[1].include?("BUNDLE_ID = com.indiagram.shipkitpipes.ios"),
         "the disagreement message carries BOTH values, not just the complaint")
end

Dir.mktmpdir do |dir|
  path = write_fixture(dir, SOUND_XCCONFIG)
  _step, result = check_identity(path, config_for(app_name: "StalePipes"), {})
  assert_blocked(result, ".bootstrap.env APP_NAME = StalePipes disagrees",
                 "D-59: APP_NAME is compared against APP_PRODUCT_NAME")
end

puts
puts "Bootstrap::IdentityAdopted — tier 3 (what the build actually resolves)"

Dir.mktmpdir do |dir|
  path = write_fixture(dir, SOUND_XCCONFIG)
  table = XCODEBUILD_PRESENT.merge(
    %w[xcodebuild -project] => ->(_) { ["xcodebuild: error: could not open project\n", false] }
  )
  step, result = check_identity(path, config_for, table, xcodeproj: write_xcodeproj_fixture(dir))
  assert_blocked(result, "tier 3: no verdict — xcodebuild exit",
                 "a failed xcodebuild is NO VERDICT, never :done")
  assert_eq(step.tier_reached, 2, "a no-verdict tier 3 leaves tier_reached at 2")
end

# The branch a fresh checkout actually takes: xcodebuild is present, the
# project is not. It had no coverage until the CI-eligibility check for this
# suite hit it. `table` is XCODEBUILD_PRESENT with NO xcodebuild -project
# handler, so if the gate ever stopped returning before shelling out, the stub
# would raise "unstubbed Sh.run" rather than quietly passing.
Dir.mktmpdir do |dir|
  path  = write_fixture(dir, SOUND_XCCONFIG)
  ghost = File.join(dir, "Ungenerated.xcodeproj")
  step, result = check_identity(path, config_for, XCODEBUILD_PRESENT, xcodeproj: ghost)
  assert_warn(result, "tier 3 not reached: #{ghost} does not exist",
              "an ungenerated project is a warn that NAMES the path, never a silent done")
  assert_eq(step.tier_reached, 2, "tier_reached stays 2 when the project was never generated")
end

Dir.mktmpdir do |dir|
  path = write_fixture(dir, SOUND_XCCONFIG)
  table = { %w[which xcodebuild] => ->(_) { ["", false] } }
  step, result = check_identity(path, config_for, table)
  assert_warn(result, "verified to tier 2; tier 3 not reached:",
              "no xcodebuild on PATH is an explicit warn, never a silent done")
  assert(result[1].include?("xcodebuild"), "the warn names WHY tier 3 was not reached")
  assert_eq(step.tier_reached, 2, "tier_reached is 2 when tier 3 is unreachable")
end

Dir.mktmpdir do |dir|
  path = write_fixture(dir, SOUND_XCCONFIG)
  table = XCODEBUILD_PRESENT.merge(
    %w[xcodebuild -project] => lambda { |cmd|
      raise "expected -showBuildSettings, got #{cmd.inspect}" unless cmd.include?("-showBuildSettings")
      raise "doctor must never run `xcodebuild test`" if cmd.include?("test")
      [settings_dump(bundle_id: "com.indiagram.shipkitpipes.ios", product_name: "ShipkitPipes"), true]
    }
  )
  step, result = check_identity(path, config_for, table, xcodeproj: write_xcodeproj_fixture(dir))
  assert_eq(result, :done, "a sound tree whose build agrees is :done")
  assert_eq(step.tier_reached, 3, "tier_reached is 3")
  assert(step.detail.to_s.start_with?("verified to tier 3:"),
         "detail names the tier reached, so :done is never bare")
  assert(step.detail.to_s.include?("com.indiagram.shipkitpipes.ios") &&
         step.detail.to_s.include?("ShipkitPipes"),
         "detail carries the verified values")
end

Dir.mktmpdir do |dir|
  path = write_fixture(dir, SOUND_XCCONFIG)
  table = XCODEBUILD_PRESENT.merge(
    %w[xcodebuild -project] => lambda { |_|
      [settings_dump(bundle_id: "com.indiagram.smokeapp", product_name: "SmokeApp"), true]
    }
  )
  _step, result = check_identity(path, config_for, table, xcodeproj: write_xcodeproj_fixture(dir))
  assert_blocked(result,
                 "tier 3 failed: PRODUCT_BUNDLE_IDENTIFIER resolved to com.indiagram.smokeapp",
                 "a stale generated project is caught at tier 3 even though tier 2 passed")
  assert(result[1].include?("com.indiagram.shipkitpipes.ios"),
         "the tier 3 message names what the xcconfig says as well as what the build resolved")
end

Dir.mktmpdir do |dir|
  path = write_fixture(dir, SOUND_XCCONFIG)
  table = XCODEBUILD_PRESENT.merge(
    %w[xcodebuild -project] => lambda { |_|
      [settings_dump(bundle_id: "com.indiagram.shipkitpipes.ios", product_name: "SmokeApp"), true]
    }
  )
  _step, result = check_identity(path, config_for, table, xcodeproj: write_xcodeproj_fixture(dir))
  assert_blocked(result, "tier 3 failed: PRODUCT_NAME resolved to SmokeApp",
                 "PRODUCT_NAME is checked too, not just the bundle id")
end

puts
puts "Bootstrap::IdentityAdopted — the fixture override is loud (T-04-42)"

Dir.mktmpdir do |dir|
  path = write_fixture(dir, SOUND_XCCONFIG)
  table = { %w[which xcodebuild] => ->(_) { ["", false] } }
  err = with_env("IDENTITY_XCCONFIG" => path) do
    capture_stderr { with_sh_stub(table) { Bootstrap::IdentityAdopted.new(config_for).check } }
  end
  assert(err.include?("IDENTITY_XCCONFIG"),
         "an overridden run announces itself on stderr, so it cannot be mistaken for a real one")
  assert(err.include?(path), "the banner names the fixture it is reading")
end

Dir.mktmpdir do |_dir|
  step = with_env("IDENTITY_XCCONFIG" => nil) { Bootstrap::IdentityAdopted.new(config_for) }
  assert_eq(step.xcconfig_path.to_s,
            Bootstrap::REPO_ROOT.join("app", "Identity.xcconfig").to_s,
            "with no override the step reads the tracked app/Identity.xcconfig")
  err = with_env("IDENTITY_XCCONFIG" => nil) { capture_stderr { step.xcconfig_path } }
  assert_eq(err, "", "an un-overridden run prints no banner")
end

puts
puts "Bootstrap::IdentityAdopted — doctor is read-only"

begin
  Bootstrap::IdentityAdopted.new(config_for).do_it
  assert(false, "do_it refuses to mutate")
rescue StandardError => e
  assert(e.message.include?("app/Identity.xcconfig"),
         "do_it fails loud and names the file a human must edit")
end

puts
puts "Bootstrap::Runner#render_result — the MIN_TIER guard lives in the runner"

class FakeTierStep < Bootstrap::Step
  MIN_TIER = 2
  def name; "Fake tier step"; end
  def check; :done; end
  def do_it; nil; end
end

class FakeReachedStep < FakeTierStep
  def check
    @tier_reached = 2
    :done
  end
end

class FakeTierlessStep < Bootstrap::Step
  def name; "Fake tierless step"; end
  def check; :done; end
  def do_it; nil; end
end

runner = Bootstrap::Runner.new(config_for)

liar = FakeTierStep.new(config_for)
assert_blocked(runner.render_result(liar, liar.check),
               "claims done at tier nil; minimum is 2",
               "a :done from a step that never set a tier is rendered blocked")

honest = FakeReachedStep.new(config_for)
assert_eq(runner.render_result(honest, honest.check), :done,
          "a :done from a step that reached its minimum passes through")

tierless = FakeTierlessStep.new(config_for)
assert_eq(runner.render_result(tierless, tierless.check), :done,
          "a step with no MIN_TIER is unaffected (every pre-existing step)")

warned = FakeTierStep.new(config_for)
assert_eq(runner.render_result(warned, [:warn, "x"]), [:warn, "x"],
          "the guard only rewrites :done — warn/pending/blocked pass through")

puts
puts "Bootstrap::Icon1024 — content, not presence (the motivating failure)"

ICON_TARGET = Bootstrap::REPO_ROOT.join("app", "iOS", "Assets.xcassets", "AppIcon.appiconset", "Icon-1024.png")
ICON_SCRIPT = Bootstrap::REPO_ROOT.join("ci", "check-app-icon.sh").to_s
assert(ICON_TARGET.file?, "precondition: the tracked 1024 icon exists")
assert(File.file?(ICON_SCRIPT), "precondition: ci/check-app-icon.sh exists (04-01 sync)")

Dir.mktmpdir do |dir|
  # An ICON_1024_PATH whose bytes are identical to the tracked icon: the hash
  # equality that used to be the whole check now passes, and the CONTENT check
  # is the only thing left standing between this and App Review.
  src = File.join(dir, "Icon-1024.png")
  File.write(src, File.binread(ICON_TARGET))

  cfg = config_for(extra: { "ICON_1024_PATH" => src })

  # `bash -c "<script> 2>&1"`: the script writes its FAIL lines to stderr and
  # Sh.run discards stderr, so a plain `bash <script>` would leave the blocked
  # message with nothing but the script's banner to quote.
  script_out = "==> App icon check\n" \
               "  FAIL iOS 1024 icon: looks like a placeholder — flat colour or bare gradient (spread 0, need >= 40).\n" \
               "\nFAILED: releasing this icon invites a Guideline 2.3.8 rejection.\n"
  table = { %w[bash -c] => lambda { |cmd|
    raise "the icon check must run ci/check-app-icon.sh" unless cmd.last.include?("check-app-icon.sh")
    raise "stderr must be captured — that is where the reason is" unless cmd.last.include?("2>&1")
    [script_out, false]
  } }
  step = Bootstrap::Icon1024.new(cfg)
  result = with_sh_stub(table) { step.check }
  assert_blocked(result, "tier 2 failed: icon is the template placeholder",
                 "matching hashes are NOT enough: a placeholder is blocked")
  assert(result[1].include?("check-app-icon.sh"),
         "the message cites the script that judged it")
  assert(result[1].include?("spread 0"),
         "and quotes the script's FAIL line, not its banner (stderr is captured)")

  table_ok = { %w[bash -c] => ->(_) { ["  ok   iOS 1024 icon 1024x1024, no alpha, spread 282\npassed\n", true] } }
  step_ok = Bootstrap::Icon1024.new(cfg)
  assert_eq(with_sh_stub(table_ok) { step_ok.check }, :done, "real artwork is :done")
  assert_eq(step_ok.tier_reached, 2, "and it reached tier 2")
  assert(step_ok.detail.to_s.start_with?("verified to tier 2:"), "with a tier detail line")
end

Dir.mktmpdir do |dir|
  # A source that differs from the target is still :pending — do_it copies it.
  # The content check must not run before the file is even in place.
  src = File.join(dir, "other.png")
  File.write(src, "not the tracked icon")
  cfg = config_for(extra: { "ICON_1024_PATH" => src })
  assert_eq(Bootstrap::Icon1024.new(cfg).check, :pending,
            "an un-copied icon is pending, unchanged")
end

result = Bootstrap::Icon1024.new(config_for).check
assert_warn(result, "ICON_1024_PATH unset",
            "the ICON_1024_PATH-unset branch is untouched (doctor on HEAD stays exit 0)")

assert_eq(Bootstrap::Icon1024.const_get(:MIN_TIER), 2, "Icon1024 declares MIN_TIER = 2")
assert_eq(Bootstrap::IdentityAdopted.const_get(:MIN_TIER), 2, "IdentityAdopted declares MIN_TIER = 2")
assert_eq(Bootstrap::Step.const_get(:MIN_TIER), nil, "Step's default MIN_TIER is nil")

puts
puts "Registration"

pipeline = Bootstrap::Runner::PIPELINE
assert(pipeline.include?(Bootstrap::IdentityAdopted), "IdentityAdopted is in PIPELINE")
assert(pipeline.include?(Bootstrap::IdentityPresent), "IdentityPresent is in PIPELINE")
assert_eq(pipeline[pipeline.index(Bootstrap::IdentityPresent) + 1], Bootstrap::IdentityAdopted,
          "IdentityAdopted sits immediately after IdentityPresent")
assert_eq(Bootstrap::IdentityPresent.const_get(:MIN_TIER), 1,
          "IdentityPresent declares MIN_TIER = 1 — presence-plus-resolution, not content")
assert(!Bootstrap.const_defined?(:RenameStub),
       "RenameStub is gone: nothing in the pipeline renames any more (A-01)")

puts
puts "Config — BOOTSTRAP_ENV fixture override, equally loud"

Tempfile.create(["bootstrap", ".env"]) do |f|
  f.write("APP_NAME=FixtureApp\nBUNDLE_ID=com.fixture.app\nRELEASE_MODE=local\n")
  f.flush
  err = with_env("BOOTSTRAP_ENV" => f.path) do
    cfg = nil
    captured = capture_stderr { cfg = Bootstrap::Config.load! }
    assert_eq(cfg["APP_NAME"], "FixtureApp", "BOOTSTRAP_ENV points Config at the fixture")
    captured
  end
  assert(err.include?("BOOTSTRAP_ENV"), "the config override announces itself on stderr too")
end

puts
puts "Bootstrap::IdentityPresent — A-01: bootstrap READS and VERIFIES identity"

# The three keys Phase 5 retired from .bootstrap.env, SPELLED HERE and
# deliberately not imported from bin/lib/bootstrap.rb. A guard that read its
# expectations out of the file under test would accept whatever that file
# happened to say, which is not a guard — test/identity_test.rb:56-60 states the
# rule, and this file now leans on it twice.
RETIRED_ENV_KEYS = %w[APP_NAME BUNDLE_ID DISPLAY_NAME].freeze

# Same shape as check_identity above, for the step that runs immediately before
# IdentityAdopted. Every fixture goes through IDENTITY_XCCONFIG; nothing here
# reads the tracked app/Identity.xcconfig, so a broken fixture can never be
# mistaken for a broken repository.
def check_present(xcconfig_path)
  with_env("IDENTITY_XCCONFIG" => xcconfig_path) do
    step = Bootstrap::IdentityPresent.new(config_for)
    result = nil
    capture_stderr { result = step.check }
    [step, result]
  end
end

# THE DISCRIMINATOR. Without a case that reaches :done through the same knob and
# the same probe, the two blocked cases below prove only that something is
# broken rather than that the step tells the cases apart.
Dir.mktmpdir do |dir|
  path = write_fixture(dir, SOUND_XCCONFIG)
  step, result = check_present(path)
  assert_eq(result, :done, "a fixture whose four keys all resolve is :done")
  assert_eq(step.tier_reached, 1, "and it reached tier 1 — presence plus resolution")
end

Dir.mktmpdir do |dir|
  # `// disabled` is UL-031's shape: the line is PRESENT, so a presence check
  # passes, while Xcconfig.value cuts at `//` and the value is empty. Xcode
  # reads it as empty too, which is why this must never be :done.
  path = write_fixture(dir, SOUND_XCCONFIG.sub(/APP_PRODUCT_NAME.*$/) { "APP_PRODUCT_NAME = // disabled" })
  _step, result = check_present(path)
  assert_blocked(result, "APP_PRODUCT_NAME (assigned, but resolves to nothing",
                 "a `//`-commented APP_PRODUCT_NAME is blocked, and the message names the key")
end

Dir.mktmpdir do |dir|
  # Assigned to nothing at all. "" and nil are the same failure to Xcode, so they
  # are the same failure here — but the message says WHICH, because a forker
  # needs to know whether they deleted the line or commented it out.
  path = write_fixture(dir, SOUND_XCCONFIG.sub(/DISPLAY_NAME.*$/) { "DISPLAY_NAME     =" })
  _step, result = check_present(path)
  assert_blocked(result, "DISPLAY_NAME (assigned, but resolves to nothing",
                 "an empty DISPLAY_NAME is blocked, and the message names the key")
end

begin
  Bootstrap::IdentityPresent.new(config_for).do_it
  assert(false, "IdentityPresent#do_it refuses — bootstrap never writes identity (A-01)")
rescue StandardError => e
  assert(e.message.include?("tools/migrate-identity.rb"),
         "do_it points a stuck fork at the migration command")
  assert(e.message.include?("docs/MIGRATING-FROM-RENAME.md"),
         "do_it points a stuck fork at the runbook, not only the command")
end

# ─── No write path exists, asserted on the text (A-01) ───────────────────────
#
# "Bootstrap reads and verifies, never writes" is a property of the FILE, not of
# any one step, so it is checked by reading bin/lib/bootstrap.rb rather than by
# calling something. The window spans one line back and two forward, because the
# shape that would sneak past a line-only predicate is a path assigned on one
# line and written on the next.

WRITE_FORMS  = /\b(?:File\.write|File\.binwrite|IO\.write|File\.open\s*\()/
IDENTITY_REF = /Identity\.xcconfig|identity_xcconfig_path/

# [line number, source line] for every write form in `lines`.
def write_sites(lines)
  lines.each_with_index.filter_map { |line, i| [i + 1, line.strip] if line =~ WRITE_FORMS }
end

# Of those, the ones whose statement also names the identity config.
def identity_write_offenders(lines)
  write_sites(lines).select do |(lineno, _src)|
    lines[[lineno - 2, 0].max...(lineno + 2)].join =~ IDENTITY_REF
  end
end

bootstrap_lines = read_utf8("bin/lib/bootstrap.rb").lines
sites = write_sites(bootstrap_lines)

# The predicate must be able to SEE a write before its silence means anything.
# bin/lib/bootstrap.rb does write files (the decoded .p8), so an empty scan here
# would mean the regex stopped matching, not that the writes went away.
assert(!sites.empty?,
       "precondition: the write-form scan finds #{sites.length} write(s) in bin/lib/bootstrap.rb " \
       "at line(s) #{sites.map(&:first).join(', ')} — a scan that found none would be vacuous")

# And it must be able to FIRE. Planted here rather than in a one-off transcript,
# so the proof cannot go stale: narrow the regex and this goes red in the same
# run as the assertion it protects.
planted = <<~PLANT.lines
  path = Bootstrap.identity_xcconfig_path
  File.write(path, rendered)
PLANT
assert_eq(identity_write_offenders(planted).map(&:first), [2],
          "the offender predicate FIRES on a planted two-line write to the identity config")

offenders = identity_write_offenders(bootstrap_lines)
offender_note = offenders.map { |(n, s)| "bin/lib/bootstrap.rb:#{n}: #{s}" }.join("; ")
assert(offenders.empty?,
       "bin/lib/bootstrap.rb writes no identity config — it reads and verifies (A-01)" +
       (offenders.empty? ? "" : " — FOUND #{offender_note}"))

# ─── Config::REQUIRED_ALWAYS no longer requires the retired keys ─────────────

required_always = Bootstrap::Config::REQUIRED_ALWAYS
RETIRED_ENV_KEYS.each do |key|
  assert(!required_always.include?(key),
         "Config::REQUIRED_ALWAYS does not require #{key} (A-01 removed it from .bootstrap.env)")
end
assert(required_always.include?("APP_EMAIL"),
       "Config::REQUIRED_ALWAYS still requires APP_EMAIL — the removal was three keys, not the list")

puts
puts "A-02 — the residual-key guard: the keys are gone, and nothing reads them"

# HALF ONE: the tracked template no longer ships the keys, so a fork scaffolded
# from it is not handed a value whose only consumer is gone.
example_lines = read_utf8(".bootstrap.env.example").lines
example_residue = example_lines.each_with_index.filter_map do |line, i|
  m = line.match(/^(#{RETIRED_ENV_KEYS.join('|')})=/)
  "#{m[1]} at .bootstrap.env.example:#{i + 1}" if m
end
residue_note = example_residue.join("; ")
assert(example_residue.empty?,
       ".bootstrap.env.example carries no #{RETIRED_ENV_KEYS.join(' / ')} assignment" +
       (example_residue.empty? ? "" : " — FOUND #{residue_note}"))

# The same non-vacuity proof the write scan gets: the matcher must be able to see
# a key assignment at all, or "no residue" would mean the regex stopped matching
# rather than that the residue went away.
assert_eq(example_lines.count { |l| l.match?(/^APP_EMAIL=/) }, 1,
          "precondition: the line matcher still sees .bootstrap.env.example's APP_EMAIL assignment")

# HALF TWO: nothing under bin/ ci/ fastlane/ reads one of them off the config
# object. This is the half that makes this file CI-worthy — it reads only tracked
# files, so it needs no .bootstrap.env on the runner.
#
# git grep exits 0 on a match, 1 on nothing matched, and 128 on an error. ONLY
# "nothing matched" is a pass: a 128 means the grep itself failed and is evidence
# for NEITHER side. The exact code is asserted rather than the output being
# tested for emptiness, because a broken invocation also prints nothing.
RESIDUAL_READER_RE = 'config\[.(APP_NAME|BUNDLE_ID|DISPLAY_NAME).\]'
reader_out, reader_exit =
  run_argv(["git", "grep", "-nE", RESIDUAL_READER_RE, "--", "bin/", "ci/", "fastlane/"])

reader_label =
  case reader_exit
  when 1
    "nothing under bin/ ci/ fastlane/ reads #{RETIRED_ENV_KEYS.join(' / ')} off the config object " \
    "(git grep exit 1 = nothing matched)"
  when 0
    named = RETIRED_ENV_KEYS.select { |k| reader_out.include?(k) }
    sites = reader_out.lines.map { |l| l.split(":", 3)[0, 2].join(":") }
    "git grep exit 0 — a reader SURVIVED: #{named.join(', ')} at #{sites.join(', ')}"
  else
    "git grep exited #{reader_exit}: the grep itself failed, which is evidence for NEITHER side " \
    "(128 = error). Output: #{reader_out.strip.inspect}"
  end
assert_eq(reader_exit, 1, reader_label)

# NON-VACUITY, proved two ways, because an exit-1 grep is exactly the shape that
# reads as a pass when it is really a broken invocation (this project has been
# bitten by `! grep` twice — grep exits 2 on ERROR as well as 1 on no-match).
#
# 1. The PATTERN. Compiled as a Ruby Regexp — equivalent to the ERE for the
#    constructs it uses (an escaped bracket, a dot, an alternation) — and driven
#    against planted reads. The definitive proof for the git-grep form is the
#    key-residue-reader control, which plants a real read in bin/ and watches
#    this assertion go red; this is the standing regression net for it.
residual_re = Regexp.new(RESIDUAL_READER_RE)
RETIRED_ENV_KEYS.each do |key|
  assert(residual_re.match?(%(  x = config["#{key}"])),
         "the residual-reader pattern matches a planted double-quoted #{key} read")
  assert(residual_re.match?(%(  x = config['#{key}'])),
         "the residual-reader pattern matches a planted single-quoted #{key} read")
end
assert(!residual_re.match?(%(  x = config["GENERATOR"])),
       "and it does NOT match a config read that is not one of the retired keys")

# 2. The INVOCATION. Same tool, same pathspec, a pattern known to match there,
#    so the exit 1 above is absence rather than a pathspec typo or a dead repo.
_probe_out, probe_exit =
  run_argv(["git", "grep", "-nE", 'config\\[', "--", "bin/", "ci/", "fastlane/"])
assert_eq(probe_exit, 0,
          "precondition: git grep with this pathspec DOES find config reads under " \
          "bin/ ci/ fastlane/ (probe exit=#{probe_exit}), so exit 1 above is absence")
# ─── Bootstrap::LocalSigningTeam — the app/Local.xcconfig writer (05-17, UP-04) ────
#
# WHAT THIS GROUP CAN AND CANNOT SEE, stated because the distinction is the whole
# reason these assertions are shaped the way they are.
#
# These are UNIT assertions on the WRITER, run against a tmpdir fixture. They do NOT
# run xcodebuild. This suite's CI caller is the `review notes` job — ubuntu-latest,
# no Xcode, no generated app/App.xcodeproj (see this file's header) — so an
# `xcodebuild -showBuildSettings` here would either fail the required context on
# every pull request or need an if-present guard, and an if-present guard is silent
# on precisely the runner it would be guarding. That is the same
# `each`-over-an-empty-collection shape R3 in test/rename_scope_test.rb was just
# strengthened against; importing it here to satisfy a plan sentence would have been
# trading one vacuity for another.
#
# The RESOLVED-BUILD-SETTING half is a LOCAL measurement, recorded as evidence rather
# than asserted here, and it was taken both ways on 2026-09-03 with
# `xcodebuild -showBuildSettings -target` (a TARGET, not a scheme: 05-07 measured that
# a target reads its own SDKROOT and does not go through destination resolution):
#
#   app/Local.xcconfig absent  -> App-macOS reports NO DEVELOPMENT_TEAM line at all,
#                                 only `_DEVELOPMENT_TEAM_IS_EMPTY = YES`; App-iOS
#                                 reports none either. Undefined, not empty — which is
#                                 what app/Identity.xcconfig:39-43 claims, now measured
#                                 rather than repeated from its comment.
#   written by this step       -> both targets report `DEVELOPMENT_TEAM = <the value>`
#                                 and macOS flips to `_DEVELOPMENT_TEAM_IS_EMPTY = NO`.
#
# So: this group pins the writer's behaviour and its refusals; the evidence file pins
# that what it writes is what the build resolves. Neither claims to be the other.

puts
puts "Bootstrap::LocalSigningTeam — the Team ID reaches the build without a hand-created file"

# The step with its ONE path resolver substituted, exactly as check_identity substitutes
# xcodeproj_path above. A second resolver inside the step is how one of check/do_it
# would quietly stop being covered, so both go through this method.
def local_team_step(config, path)
  step   = Bootstrap::LocalSigningTeam.new(config)
  target = Pathname.new(path)
  step.define_singleton_method(:local_xcconfig_path) { target }
  step
end

# PLACEHOLD9 is ten upper-case alphanumerics — the shape Apple issues and the shape
# docs/APPLE-PREREQS.md:48 tells a forker to expect. config_for already uses it, so
# nothing here introduces a new Team-ID-shaped token into the tree.
FIXTURE_TEAM  = "PLACEHOLD9"
OTHER_TEAM    = "OTHERTEAM1"

Dir.mktmpdir do |dir|
  target = File.join(dir, "Local.xcconfig")
  step   = local_team_step(config_for, target)

  assert_eq(step.check.is_a?(Array) ? step.check[0] : step.check, :pending,
            "an absent app/Local.xcconfig is :pending — the file is written, not demanded")
  assert(step.check[1].to_s.include?(target),
         "and the pending message names the file it is going to write")

  step.do_it
  assert(File.file?(target), "do_it creates the file")

  # Read back through Xcconfig — the ONE parser (D-57), the same one Xcode's
  # `#include?` and bin/preflight-identity.rb --require-team resolve through. A text
  # compare here would pass on a file whose value the parser cannot actually see,
  # which is UL-031's exact shape (`KEY = // disabled` satisfies a presence regex and
  # resolves to nothing).
  assert_eq(Xcconfig.own(target)["DEVELOPMENT_TEAM"], FIXTURE_TEAM,
            "and the parser resolves the value that came from FASTLANE_TEAM_ID")

  assert_eq(step.check, :done, "a written, agreeing file is :done")
  assert_eq(step.tier_reached, 2, "and it reached tier 2 — the VALUE agrees, not merely the file exists")

  # UTF-8 on the write, never inherited. The header this step writes carries an em
  # dash (U+2014), so an unpinned File.write raises Encoding::UndefinedConversionError
  # with LANG unset. UL-012 / commit 3b1efb9 was this repository's first instance of
  # inherited encoding and 05-09's Config.parse was the second; the pin is what keeps
  # this from being the third. Driven red with LC_ALL/LANG/LC_CTYPE cleared, recorded
  # in the phase evidence file rather than asserted from the comment.
  assert(File.read(target, encoding: "UTF-8").valid_encoding?,
         "the file it wrote is valid UTF-8")
  assert(File.read(target, encoding: "UTF-8").include?("—"),
         "and carries the non-ASCII byte that makes the write's UTF-8 pin load-bearing")
end

# An ABSENT value is a NAMED refusal, never an empty write. app/Identity.xcconfig:39-44
# records that an UNDEFINED DEVELOPMENT_TEAM and an EMPTY one differ, and .continue-here.md
# records the measurement behind it: a macOS build SUCCEEDS on an empty value with
# "Sign to Run Locally" and says nothing. So an empty write would convert a loud
# failure into a silent wrong one — worse than no write at all.
Dir.mktmpdir do |dir|
  target = File.join(dir, "Local.xcconfig")
  step   = local_team_step(config_for(extra: { "FASTLANE_TEAM_ID" => "" }), target)

  assert_blocked(step.check, "FASTLANE_TEAM_ID",
                 "an absent FASTLANE_TEAM_ID is blocked, and the message names the key")
  assert(step.check[1].to_s.include?(".bootstrap.env"),
         "and names the file the value has to come from")
  assert(!File.exist?(target), "and NOTHING was written — an empty DEVELOPMENT_TEAM is worse than none")

  raised = begin
             step.do_it
             nil
           rescue StandardError => e
             e.message
           end
  assert(!raised.nil? && raised.include?("FASTLANE_TEAM_ID"),
         "do_it RAISES rather than writing a blank (message: #{raised.inspect})")
  assert(!File.exist?(target), "and still nothing was written after do_it")
end

# A MALFORMED value is a named refusal too, and each case says what it found.
# Ten upper-case alphanumerics: `abcde12345` (case), `ABCDE1234` (short),
# `ABCDE123456` (long), `ABCDE 1234` (a space — the shape a trailing dotenv comment
# or a pasted "Team ID: X" leaves behind).
%w[abcde12345 ABCDE1234 ABCDE123456].each do |bad|
  Dir.mktmpdir do |dir|
    target = File.join(dir, "Local.xcconfig")
    step   = local_team_step(config_for(extra: { "FASTLANE_TEAM_ID" => bad }), target)
    assert_blocked(step.check, bad.inspect,
                   "a malformed FASTLANE_TEAM_ID (#{bad.inspect}) is blocked, and the message quotes it")
    assert(!File.exist?(target), "and #{bad.inspect} produced no file")
  end
end

Dir.mktmpdir do |dir|
  target = File.join(dir, "Local.xcconfig")
  step   = local_team_step(config_for(extra: { "FASTLANE_TEAM_ID" => "ABCDE 1234" }), target)
  assert_blocked(step.check, "ABCDE 1234",
                 "a value with an embedded space is blocked rather than written")
  assert(!File.exist?(target), "and produced no file")
end

# DISAGREEMENT is a refusal, not an overwrite. tools/migrate-identity.rb's move_team_id
# already refuses at exit 4 rather than "overwrite a Team ID a forker put there by
# hand", and docs/APPLE-ACCOUNT-STATE.md:99 records that the two consumers
# (.bootstrap.env's FASTLANE_TEAM_ID, app/Local.xcconfig's DEVELOPMENT_TEAM) are meant
# to hold the SAME value. So a divergence is a real finding: this step surfaces it and
# declines to choose, which makes it a drift check as well as a writer.
Dir.mktmpdir do |dir|
  target = File.join(dir, "Local.xcconfig")
  File.write(target, "DEVELOPMENT_TEAM = #{OTHER_TEAM}\n", encoding: "UTF-8")
  before = File.read(target, encoding: "UTF-8")
  step   = local_team_step(config_for, target)

  result = step.check
  assert_blocked(result, OTHER_TEAM, "a file assigning a DIFFERENT team is blocked, naming what is there")
  assert(result[1].to_s.include?(FIXTURE_TEAM), "and naming what .bootstrap.env says")
  assert_eq(File.read(target, encoding: "UTF-8"), before,
            "and check changed nothing on disk")

  raised = begin
             step.do_it
             nil
           rescue StandardError => e
             e.message
           end
  assert(!raised.nil?, "do_it refuses to overwrite a Team ID somebody else put there")
  assert_eq(File.read(target, encoding: "UTF-8"), before, "and the existing value survived")
end

# A file that exists but assigns nothing is :pending, and do_it APPENDS rather than
# truncating — a forker's other per-clone settings are not this step's to delete.
Dir.mktmpdir do |dir|
  target = File.join(dir, "Local.xcconfig")
  File.write(target, "// my own note\nOTHER_LOCAL_SETTING = keep-me\n", encoding: "UTF-8")
  step = local_team_step(config_for, target)

  assert_eq(step.check.is_a?(Array) ? step.check[0] : step.check, :pending,
            "a file with no DEVELOPMENT_TEAM assignment is :pending")
  step.do_it
  after = File.read(target, encoding: "UTF-8")
  assert(after.include?("OTHER_LOCAL_SETTING = keep-me"),
         "and do_it APPENDS — the forker's other settings survive")
  assert_eq(Xcconfig.own(target)["DEVELOPMENT_TEAM"], FIXTURE_TEAM,
            "and the team now resolves")
end

# In PIPELINE, and positioned after identity is verified. The ORDER is the assertion,
# not the membership: a writer that ran before IdentityAdopted would be generating
# from an identity nothing had checked.
pipeline_17 = Bootstrap::Runner::PIPELINE
assert(pipeline_17.include?(Bootstrap::LocalSigningTeam), "LocalSigningTeam is in PIPELINE")
assert(pipeline_17.index(Bootstrap::LocalSigningTeam).to_i > pipeline_17.index(Bootstrap::IdentityAdopted).to_i,
       "and it runs AFTER IdentityAdopted (at #{pipeline_17.index(Bootstrap::LocalSigningTeam).inspect}, " \
       "IdentityAdopted at #{pipeline_17.index(Bootstrap::IdentityAdopted).inspect})")
assert(pipeline_17.index(Bootstrap::LocalSigningTeam).to_i < pipeline_17.index(Bootstrap::LocalKeychainCerts).to_i,
       "and BEFORE LocalKeychainCerts, the first step that cares which team signs")

# docs/BOOTSTRAP.md states the step count as a NUMBER. A doc that says 22 while the
# constant says 23 is the inferring-a-fact-from-a-doc class this project has been
# bitten by eight times, so the number is asserted against the constant rather than
# left to be noticed.
doc_bootstrap = read_utf8("docs/BOOTSTRAP.md")
assert(doc_bootstrap.include?("The pipeline has #{pipeline_17.length} step classes"),
       "docs/BOOTSTRAP.md states the pipeline's real step count (#{pipeline_17.length})")
assert(doc_bootstrap.include?("| #{pipeline_17.length} | `#{pipeline_17.last.name.split('::').last}`"),
       "and its numbered table's last row is the constant's last step at ##{pipeline_17.length}")

puts
if @failures.zero?
  puts "PASSED"
  exit 0
else
  puts "FAILED (#{@failures} assertion(s))"
  exit 1
end
