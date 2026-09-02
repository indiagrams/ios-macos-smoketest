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

def check_identity(xcconfig_path, config, sh_table)
  with_env("IDENTITY_XCCONFIG" => xcconfig_path) do
    step = Bootstrap::IdentityAdopted.new(config)
    result = nil
    capture_stderr { result = with_sh_stub(sh_table) { step.check } }
    [step, result]
  end
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
  step, result = check_identity(path, config_for, table)
  assert_blocked(result, "tier 3: no verdict — xcodebuild exit",
                 "a failed xcodebuild is NO VERDICT, never :done")
  assert_eq(step.tier_reached, 2, "a no-verdict tier 3 leaves tier_reached at 2")
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
  step, result = check_identity(path, config_for, table)
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
  _step, result = check_identity(path, config_for, table)
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
  _step, result = check_identity(path, config_for, table)
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

  table = { ["bash", ICON_SCRIPT] => ->(_) { ["  FAIL iOS 1024 icon: looks like a placeholder\nFAILED\n", false] } }
  step = Bootstrap::Icon1024.new(cfg)
  result = with_sh_stub(table) { step.check }
  assert_blocked(result, "tier 2 failed: icon is the template placeholder",
                 "matching hashes are NOT enough: a placeholder is blocked")
  assert(result[1].include?("check-app-icon.sh"),
         "the message cites the script that judged it")

  table_ok = { ["bash", ICON_SCRIPT] => ->(_) { ["  ok   iOS 1024 icon 1024x1024, no alpha, spread 282\npassed\n", true] } }
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
assert_eq(pipeline[pipeline.index(Bootstrap::RenameStub) + 1], Bootstrap::IdentityAdopted,
          "IdentityAdopted sits immediately after RenameStub")

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
if @failures.zero?
  puts "PASSED"
  exit 0
else
  puts "FAILED (#{@failures} assertion(s))"
  exit 1
end
