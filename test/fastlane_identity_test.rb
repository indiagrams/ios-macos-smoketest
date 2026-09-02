#!/usr/bin/env ruby
# frozen_string_literal: true

# Durable guard for D-58: fastlane resolves the app's identity from
# app/Identity.xcconfig through bin/lib/xcconfig.rb, with ENV as the only
# override and a NAMED FAILURE when the value is missing (IDENT-05).
#
# Why this file exists, and why it asserts a SHAPE rather than a literal:
#
#   The fork's fastlane/Fastfile used to end its resolution chain with
#   `|| "SmokeApp"` / `|| "com.indiagram.smokeapp"`. Upstream's post-#281 copy
#   deleted those two literals and wrote `|| "HelloApp"` / `|| "com.example.helloapp"`
#   in their place. The literal changed; the defect did not. A fallback default
#   means a fork whose identity file is missing, empty or commented out does not
#   fail — it ships under a plausible fake identity, and the first thing that
#   notices is Apple. That is this project's dominant failure mode (a check that
#   structurally cannot fail) wearing a different hat, so the assertion below is
#   on the `|| "…"` SHAPE with all four literals in one alternation, not on any
#   one of them.
#
#   The second half is the `.bootstrap.env` tier. It was a per-fork file that is
#   GITIGNORED, so a fresh clone resolved identity from a file it did not have,
#   and a forker editing app/Identity.xcconfig saw fastlane ignore the edit. D-58
#   (as amended 2026-09-02) does NOT delete the keys from .bootstrap.env — doctor
#   still validates them and reports disagreement, and Phase 5 removes them — it
#   deletes every RELEASE-PATH CONSUMER of them. That is what assertions FL19 and
#   FL20 pin: no File operation on the file from fastlane, and every surviving
#   mention of it in the Fastfile is about App Store Connect credentials, the
#   team id, PLATFORMS or `make ship`'s env export. Those are real and stay.
#
#   The third half is the failure construct, and it is measured, not chosen.
#   Inside a fastlane Appfile, CredentialsManager::AppfileConfig#try_fetch_value
#   wraps the evaluation in `rescue => ex; puts(ex.to_s); return nil`. Against
#   bundled fastlane 2.238.0 on 2026-09-02, a `raise` in the Appfile printed its
#   message three times (the Appfile is re-evaluated on every fetch) and the lane
#   ran to completion with `app_identifier=nil`, exit 0. FastlaneCore::UI.user_error!
#   raises FastlaneError < StandardError and is swallowed identically. `abort`
#   raises SystemExit, which `rescue => ex` does not catch: message on stderr,
#   exit 1. So FL9/FL10/FL11 are not style rules — `raise` in that file is the
#   silent-substitution defect D-58 exists to remove.
#
# Failure-line contract (same shape as test/identity_test.rb, deliberately —
# negative controls grep for it): every failed assertion prints ONE line, no
# leading whitespace,
#
#     FAIL FL <path>: <message>
#
# where <path> is the file the assertion is about, or `-` when it is not
# file-scoped.
#
# WHAT THIS CANNOT DO. It reads TEXT. It cannot observe that fastlane actually
# aborts, because fastlane is a gem and this file runs on the `review notes`
# runner with bundler-cache: false and no gems installed. The abort is observed
# through fastlane itself, locally and both directions, in
# .planning/phases/04-identity-consumers-ci-gates/evidence/04-04-T2-fastlane-integration-controls.txt
# (a comment-only fixture → exit 1 with the named message and no app_identifier
# line; the live file → the real bundle id, exit 0). A text guard that claimed
# to prove the runtime behaviour would be exactly the kind of check this
# repository keeps deleting.
#
# Ruby core only: one require-family line, a require_relative of
# bin/lib/xcconfig.rb, which itself has ZERO require lines (asserted by
# test/xcconfig_test.rb, so it cannot rot). That is what keeps
# `bundler-cache: false` in .github/workflows/review-notes.yml honest.
#
# Run under BOTH pinned interpreters:
#   /opt/homebrew/opt/ruby@3.3/bin/ruby test/fastlane_identity_test.rb
#   /opt/homebrew/opt/ruby@4.0/bin/ruby test/fastlane_identity_test.rb

require_relative "../bin/lib/xcconfig"

ROOT     = File.expand_path("..", __dir__)
APPFILE  = "fastlane/Appfile"
FASTFILE = "fastlane/Fastfile"
IDENTITY = "app/Identity.xcconfig"

# Both template identities. The fork's pair and upstream's pair: D-58 removes the
# fallback SHAPE, so a future sync that reintroduces upstream's spelling is caught
# by the same assertion that caught the fork's.
TEMPLATE_IDENTITIES = %w[SmokeApp com.indiagram.smokeapp HelloApp com.example.helloapp].freeze
FALLBACK_SHAPE      = /\|\|\s*"(?:SmokeApp|com\.indiagram\.smokeapp|HelloApp|com\.example\.helloapp)"/

# `com.indiagram.smokeapp` survives in fastlane/Fastfile for exactly one reason:
# the `adopt_existing_app` lane hard-stops when APP_IDENTIFIER still equals the
# template placeholder, because adopting a live App Store record only makes sense
# against a real bundle id. That is a GUARD literal (D-65 class 2) — a value the
# code refuses — not a fallback. It occurs twice: the `if` comparison and the
# message that quotes it back. The count is frozen so that a THIRD occurrence,
# which would mean a new fallback or a new hardcode, fails this test rather than
# hiding behind the guard's exemption.
GUARD_LITERAL       = "com.indiagram.smokeapp"
GUARD_OCCURRENCES   = 2

# The only subjects a surviving `.bootstrap.env` mention in fastlane/Fastfile may
# have. All four are credentials or process config, none is identity: the ASC API
# key, the Apple Developer team, the platform list, and `make ship`'s env export.
# D-58 removes identity consumers, not the file.
BOOTSTRAP_ENV_ALLOWED_SUBJECTS = /ASC_API_KEY|FASTLANE_TEAM_ID|PLATFORMS|auto-exports env/

# ─── harness (test/identity_test.rb:139-208, one-line FAIL contract) ──────────

@failures = 0
@checks   = 0

def assert(condition, path, label)
  @checks += 1
  if condition
    puts "  ✓ FL #{path}: #{label}"
  else
    puts "FAIL FL #{path}: #{label.to_s.gsub(/\s*\n\s*/, ' ')}"
    @failures += 1
  end
end

# UTF-8 pinned, never inherited: with LANG unset Ruby defaults
# Encoding.default_external to US-ASCII and a non-ASCII byte raises out of a
# regex match instead of exiting 0 or 1 (UL-012, commit 3b1efb9).
def read_utf8(relative)
  File.read(File.join(ROOT, relative), encoding: "UTF-8")
end

# Argv array only — a shell string would let a path with a space change what runs.
def run(argv)
  out = IO.popen(argv, "r", err: [:child, :out], chdir: ROOT, &:read)
  [out.to_s, $?.exitstatus]
end

def lines_matching(text, pattern)
  text.lines.each_with_index.filter_map { |line, i| i + 1 if line.match?(pattern) }
end

appfile_exists  = File.exist?(File.join(ROOT, APPFILE))
fastfile_exists = File.exist?(File.join(ROOT, FASTFILE))
appfile         = appfile_exists  ? read_utf8(APPFILE)  : ""
fastfile        = fastfile_exists ? read_utf8(FASTFILE) : ""

# ─── FL1-FL15: fastlane/Appfile ──────────────────────────────────────────────

puts "FL — #{APPFILE} resolves app_identifier through the shared parser, with abort (D-58):"

assert appfile_exists, APPFILE, "exists"

assert !appfile.include?("_fork_config") && !appfile.include?("_FORK_CONFIG"),
       APPFILE, "defines and calls no _fork_config / _FORK_CONFIG .env reader"

bootstrap_hits = lines_matching(appfile, /\.bootstrap\.env/)
assert bootstrap_hits.empty?, APPFILE,
       "never names .bootstrap.env — the Appfile carries no identity tier and no credential " \
       "documentation#{bootstrap_hits.empty? ? '' : " (found at line(s) #{bootstrap_hits.join(', ')})"}"

fallback_hits = lines_matching(appfile, FALLBACK_SHAPE)
assert fallback_hits.empty?, APPFILE,
       "has no `|| \"<template identity>\"` fallback default" \
       "#{fallback_hits.empty? ? '' : " — found at line(s) #{fallback_hits.join(', ')}"}"

TEMPLATE_IDENTITIES.each do |literal|
  assert !appfile.include?(literal), APPFILE,
         "contains no `#{literal}` literal (the Appfile has no guard exemption — every " \
         "occurrence here would be a hardcoded identity)"
end

assert appfile.include?("Xcconfig.value("), APPFILE,
       "resolves through Xcconfig.value — `value`, not `own`, because fastlane wants the " \
       "identity the BUILD resolves, which follows `#include? \"Local.xcconfig\"`"

assert appfile.include?("Identity.xcconfig"), APPFILE, "names app/Identity.xcconfig as the source"

assert appfile.match?(/load\s+File\.join\(root,\s*"bin",\s*"lib",\s*"xcconfig\.rb"\)/), APPFILE,
       "loads bin/lib/xcconfig.rb by absolute path built from the repo root"

assert appfile.match?(/File\.expand_path\("\.\.",\s*Dir\.pwd\)/), APPFILE,
       "resolves the repo root with File.expand_path(\"..\", Dir.pwd) — inside the Appfile eval " \
       "Dir.pwd is fastlane/ and __dir__ is nil (measured, fastlane 2.238.0)"

assert !appfile.match?(/(^|[^_a-zA-Z])__dir__/), APPFILE,
       "does not use __dir__, which is nil inside the Appfile eval"

assert appfile.include?("abort"), APPFILE,
       "fails with `abort` — the ONLY construct AppfileConfig.try_fetch_value does not swallow " \
       "(measured: raise and UI.user_error! ran the lane to exit 0 with app_identifier=nil)"

raise_hits = lines_matching(appfile, /(?:^|[^\w.])raise\b/)
assert raise_hits.empty?, APPFILE,
       "contains no `raise` — it is rescued and the lane continues with a nil identity" \
       "#{raise_hits.empty? ? '' : " (found at line(s) #{raise_hits.join(', ')})"}"

assert !appfile.include?("user_error!"), APPFILE,
       "contains no UI.user_error! — FastlaneError < StandardError, swallowed the same way"

assert appfile.match?(/ENV\["BUNDLE_ID"\]/), APPFILE,
       "keeps ENV[\"BUNDLE_ID\"] as the explicit override, ahead of the file"

assert appfile.include?("IDENTITY_XCCONFIG"), APPFILE,
       "honours ENV[\"IDENTITY_XCCONFIG\"] as the file path (the controls need it)"

assert appfile.match?(/warn .*IDENTITY_XCCONFIG/), APPFILE,
       "prints a warning line when IDENTITY_XCCONFIG is set — an override that points a real " \
       "ship at a fixture must be loud (T-04-16)"

# ─── FL16-FL36: fastlane/Fastfile ────────────────────────────────────────────

puts
puts "FL — #{FASTFILE} resolves APP_IDENTIFIER / APP_NAME through the shared parser (D-58):"

assert fastfile_exists, FASTFILE, "exists"

assert !fastfile.include?("_fork_config") && !fastfile.include?("_FORK_CONFIG"),
       FASTFILE, "defines and calls no _fork_config / _FORK_CONFIG .env reader"

file_op_hits = lines_matching(fastfile, /File\.[a-z_]+[?!]?\([^)]*bootstrap[_.]env/i)
assert file_op_hits.empty?, FASTFILE,
       "performs no File operation on .bootstrap.env — nothing in fastlane READS it" \
       "#{file_op_hits.empty? ? '' : " (found at line(s) #{file_op_hits.join(', ')})"}"

bad_subject = lines_matching(fastfile, /\.bootstrap\.env/).reject do |n|
  fastfile.lines[n - 1].match?(BOOTSTRAP_ENV_ALLOWED_SUBJECTS)
end
assert bad_subject.empty?, FASTFILE,
       "every surviving .bootstrap.env mention is about credentials, the team, PLATFORMS or " \
       "`make ship`'s env export — never about identity (D-58 removes the consumers, Phase 5 " \
       "removes the keys)#{bad_subject.empty? ? '' : " — off-subject at line(s) #{bad_subject.join(', ')}"}"

fastfile_fallbacks = lines_matching(fastfile, FALLBACK_SHAPE)
assert fastfile_fallbacks.empty?, FASTFILE,
       "has no `|| \"<template identity>\"` fallback default — upstream replaced the fork's two " \
       "literals with HelloApp / com.example.helloapp, which is the same defect" \
       "#{fastfile_fallbacks.empty? ? '' : " — found at line(s) #{fastfile_fallbacks.join(', ')}"}"

assert fastfile.include?('Xcconfig.value(IDENTITY_XCCONFIG, "BUNDLE_ID")'), FASTFILE,
       "resolves APP_IDENTIFIER with Xcconfig.value(IDENTITY_XCCONFIG, \"BUNDLE_ID\")"

assert fastfile.include?('Xcconfig.value(IDENTITY_XCCONFIG, "APP_PRODUCT_NAME")'), FASTFILE,
       "resolves APP_NAME from APP_PRODUCT_NAME in the xcconfig — the name the build gives the " \
       "product, not a second copy in a second file"

assert fastfile.match?(/^APP_IDENTIFIER\s*=\s*ENV\["BUNDLE_ID"\]\s*\|\|\s*Xcconfig\.value/), FASTFILE,
       "APP_IDENTIFIER reads ENV[\"BUNDLE_ID\"] first, then the parser — ENV stays the explicit override"

assert fastfile.match?(/^APP_NAME\s*=\s*ENV\["APP_NAME"\]\s*\|\|\s*Xcconfig\.value/), FASTFILE,
       "APP_NAME reads ENV[\"APP_NAME\"] first, then the parser"

assert fastfile.match?(/abort\s+"IDENTITY: BUNDLE_ID is missing or empty/), FASTFILE,
       "aborts by name when BUNDLE_ID is missing or empty (same failure shape as the Appfile, " \
       "so one message is learned once)"

assert fastfile.match?(/abort\s+"IDENTITY: APP_PRODUCT_NAME is missing or empty/), FASTFILE,
       "aborts by name when APP_PRODUCT_NAME is missing or empty"

# Scoped to the two guards on purpose: `fastfile.match?(/\.empty\?/)` passes on the
# pre-edit file, because the Fastfile calls .empty? in half a dozen unrelated lanes.
# An assertion that is green before the change it is about is not an assertion.
%w[APP_IDENTIFIER APP_NAME].each do |const|
  assert fastfile.match?(/if #{const}\.nil\?\s*\|\|\s*#{const}\.empty\?/), FASTFILE,
         "guards #{const} with `.nil? || .empty?` and not truthiness — Xcconfig.value returns " \
         "\"\" for a comment-only or empty assignment, and \"\" is TRUTHY in Ruby, so an `||` " \
         "chain would sail straight past it with an empty identity"
end

assert fastfile.include?("IDENTITY_XCCONFIG"), FASTFILE,
       "honours ENV[\"IDENTITY_XCCONFIG\"] as the file path, with the same override banner"

assert fastfile.match?(/File\.expand_path\("\.\.\/bin\/lib\/xcconfig\.rb",\s*File\.dirname\(__FILE__\)\)/),
       FASTFILE,
       "loads bin/lib/xcconfig.rb relative to itself — the Fastfile IS loaded by file, so " \
       "File.dirname(__FILE__) works here (Fastfile's Fastfile.local import already uses it)"

# 04-01's D-47 constants: the schemes and artefact names are PROJECT constants,
# not derived from APP_NAME. Regressing them (back to "#{APP_NAME}-iOS") makes a
# release lane look for build/<APP_NAME>-<version>.ipa while
# ci/local-release-check.sh writes build/App-<version>.ipa (UL-024).
{
  "IOS_SCHEME"       => '"App-iOS"',
  "MACOS_SCHEME"     => '"App-macOS"',
  "IPA_NAME_PATTERN" => '"App-%s.ipa"',
  "PKG_NAME_PATTERN" => '"App-%s.pkg"',
}.each do |const, literal|
  assert fastfile.match?(/^#{const}\s*=\s*#{Regexp.escape(literal)}/), FASTFILE,
         "still spells the D-47 constant #{const} = #{literal} (not derived from APP_NAME)"
end

assert fastfile.include?("bundle_name   = APP_NAME"), FASTFILE,
       "keeps `bundle_name = APP_NAME` — the one real consumer of the name, which names the " \
       "App ID on Apple's side, and therefore the reason APP_NAME is resolved at all"

assert fastfile.include?(%(if app_identifier == "#{GUARD_LITERAL}")), FASTFILE,
       "keeps the adopt_existing_app hard-stop on the template placeholder (a guard literal, " \
       "D-65 class 2 — a value the code REFUSES, the opposite of a fallback)"

guard_count = fastfile.scan(GUARD_LITERAL).length
assert guard_count == GUARD_OCCURRENCES, FASTFILE,
       "contains exactly #{GUARD_OCCURRENCES} occurrences of `#{GUARD_LITERAL}` — the " \
       "adopt_existing_app guard's comparison and the message that quotes it back — found " \
       "#{guard_count}"

# ─── FL37-FL40: the file both of them read, and both files parse ─────────────

puts
puts "FL — the source both files resolve, and their syntax:"

identity_path = File.join(ROOT, IDENTITY)
%w[BUNDLE_ID APP_PRODUCT_NAME].each do |key|
  resolved = File.exist?(identity_path) ? Xcconfig.value(identity_path, key) : nil
  assert !resolved.nil? && !resolved.empty? && !TEMPLATE_IDENTITIES.include?(resolved),
         IDENTITY,
         "resolves #{key} to a non-empty value that is not a template identity " \
         "(the Appfile and the Fastfile both read this key from this file, independently — " \
         "they share no Ruby constants)"
end

[APPFILE, FASTFILE].each do |rel|
  _out, status = run(["ruby", "-c", rel])
  assert status&.zero?, rel, "passes `ruby -c` (both are plain Ruby; a syntax error here " \
                             "takes down every lane at load time)"
end

# ─── verdict ─────────────────────────────────────────────────────────────────

puts
if @failures.zero?
  puts "All #{@checks} fastlane identity assertions passed."
  exit 0
else
  puts "#{@failures} of #{@checks} fastlane identity assertion(s) failed."
  exit 1
end
