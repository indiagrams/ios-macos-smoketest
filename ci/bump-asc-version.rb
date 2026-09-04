#!/usr/bin/env ruby
# ci/bump-asc-version.rb — bump the App Store version_string for both
# iOS and macOS records on App Store Connect, and select the matching
# TestFlight build for each.
#
# Run via ci/bump-asc-version.sh (which sources .bootstrap.env and uses brew Ruby).
# Direct invocation:
#   bundle exec ruby ci/bump-asc-version.rb v0.0.11
#
# Idempotent: skips bump/attach steps that are already at the target.
#
# Configuration:
#   The bundle id is resolved from app/Identity.xcconfig — the one tracked file the
#   BUILD resolves it from (D-45/D-58) — through bin/lib/xcconfig.rb, the one reader
#   (D-57). APP_BUNDLE_ID and BUNDLE_ID remain explicit environment overrides, in that
#   order. THERE IS NO THIRD TIER AND NO LITERAL DEFAULT: this script used to fall back
#   to the template's placeholder bundle id, which meant a fork with a missing or
#   commented-out value would silently ask App Store Connect about someone else's app
#   record — and then bump ITS version — instead of failing. A named failure is the
#   only safe outcome.
#
# Exit-code contract, in bin/preflight-identity.rb's shape. It is documented
# because this script WRITES to App Store Connect and a caller has to be able to
# tell "I do not understand you" apart from "Apple said no":
#
#   Exit | Meaning                                        | Message must name
#   -----+------------------------------------------------+---------------------------------
#   0    | -h / --help printed usage; or the bump ran     | — (usage; or the transcript)
#   1    | the app or its identity could not be resolved  | the bundle id or the config path
#   2    | an argument this script does not understand    | the argument, verbatim
#
# WHY THE VERSION IS SHAPE-CHECKED AND NOT MERELY PRESENT. Until 2026-09-04 the
# only argument check here was `ARGV.empty?`, and ARGV[0] went to
# patch_app_store_version as the versionString for BOTH platforms with nothing
# looking at it. Measured offline against a stub Spaceship on 2026-09-04:
# `ci/bump-asc-version.rb --help` produced two ASC writes, {versionString:
# "--help"} on IOS and on MAC_OS, at exit 0. That is the bin/adopt.rb incident of
# 2026-09-03 in a second costume, one level out — the receiver is the App Store
# record rather than 13 tracked files.
#
# Guarding only the ci/bump-asc-version.sh wrapper would not have closed it: the
# header above documents `bundle exec ruby ci/bump-asc-version.rb v0.0.11` as a
# supported entry point, so this file needs its own front door.

# The release tag shape, anchored at BOTH ends. Partial-match anchoring is how a
# flag with a version buried in it would pass. This is deliberately the same
# shape ci/local-release-check.sh:205 enforces on the release path, so the two
# ends of one release cannot disagree about what a version is; the leading `v` is
# optional here because the wrapper and this file's own header both document the
# bare form as well.
VERSION_SHAPE = /\Av?[0-9]+\.[0-9]+\.[0-9]+(?:[-+].+)?\z/.freeze

USAGE = <<~TEXT
  ci/bump-asc-version.rb — bump the App Store version for both platform records
  on App Store Connect and attach the matching TestFlight build.

  This WRITES to App Store Connect. It PATCHes the edit-state App Store version
  for iOS and for macOS, and selects a build against each.

  Usage:
    bundle exec ruby ci/bump-asc-version.rb v0.0.11
    bundle exec ruby ci/bump-asc-version.rb --help    print this usage (-h is an alias)

  Normally reached through ci/bump-asc-version.sh, which sources .bootstrap.env
  and pins Ruby first.

  There is no --dry-run. Nothing here previews a write, and a flag that implied
  one would be lying — read the ASC record in the web UI instead.

  Exit codes: 0 usage, or the bump ran; 1 the app or its identity could not be
  resolved; 2 an argument this script does not understand.
TEXT

# Parsed BEFORE the App Store Connect library is required, so a refusal never
# depends on a gem being installed or on a credential being readable — and so a
# probe cannot reach a network call by way of a slow require succeeding.
target = nil
ARGV.each do |arg|
  case arg
  when "-h", "--help"
    puts USAGE
    exit 0
  when VERSION_SHAPE
    if target
      warn "[bump-asc-version] Two versions given: #{target.inspect} and #{arg.inspect}"
      warn "[bump-asc-version] Nothing was contacted and nothing was written."
      warn ""
      warn USAGE
      exit 2
    end
    target = arg.sub(/\Av/, '')
  else
    warn "[bump-asc-version] Unrecognised argument: #{arg}"
    warn "[bump-asc-version] Expected a version such as v0.0.11. Nothing was contacted " \
         "and nothing was written."
    warn ""
    warn USAGE
    exit 2
  end
end

if target.nil?
  warn "[bump-asc-version] No version given."
  warn ""
  warn USAGE
  exit 2
end

require 'spaceship'
require 'base64'
require_relative '../bin/lib/xcconfig'

token = Spaceship::ConnectAPI::Token.create(
  key_id:    ENV.fetch("ASC_API_KEY_ID"),
  issuer_id: ENV.fetch("ASC_API_KEY_ISSUER_ID"),
  key:       Base64.strict_decode64(ENV.fetch("ASC_API_KEY_P8_BASE64"))
)
Spaceship::ConnectAPI.token = token

identity  = ENV["IDENTITY_XCCONFIG"] || File.expand_path("../app/Identity.xcconfig", __dir__)
# `.empty?` and not truthiness: Xcconfig.value returns "" for an assignment that is
# present but empty or commented out (`BUNDLE_ID = // disabled` — `//` opens a comment
# at any position, T-03-06/UL-031), and "" is TRUTHY in Ruby, so an `||` chain would
# sail straight past it and send the empty string to Apple.
bundle_id = ENV["APP_BUNDLE_ID"] || ENV["BUNDLE_ID"] || Xcconfig.value(identity, "BUNDLE_ID")
if bundle_id.nil? || bundle_id.empty?
  abort "IDENTITY: BUNDLE_ID is missing or empty in #{identity} " \
        "(set it there, or export BUNDLE_ID to override)"
end

app = Spaceship::ConnectAPI::App.find(bundle_id) \
  or abort "error: app #{bundle_id} not found on ASC"

puts "App: #{app.name} (#{app.id})"
puts "Target version: #{target}"

[Spaceship::ConnectAPI::Platform::IOS,
 Spaceship::ConnectAPI::Platform::MAC_OS].each do |plat|
  puts "\n=== #{plat} ==="

  v = app.get_edit_app_store_version(platform: plat)
  unless v
    puts "  warn: no edit-state version exists. Create one in ASC web UI first."
    next
  end

  if v.version_string == target
    puts "  version already at #{target} — skipping bump"
  else
    puts "  bumping #{v.version_string} → #{target}…"
    Spaceship::ConnectAPI.patch_app_store_version(
      app_store_version_id: v.id,
      attributes: { versionString: target }
    )
    v = app.get_edit_app_store_version(platform: plat)
    puts "  bumped (id=#{v.id})"
  end

  builds = app.get_builds(includes: 'preReleaseVersion').select do |b|
    pre = b.pre_release_version
    pre && pre.version == target && pre.platform == plat.to_s
  end

  if builds.empty?
    puts "  warn: no TestFlight build at v#{target} for #{plat} — upload one with"
    puts "        fastlane release tag:v#{target}"
    next
  end

  build = builds.max_by { |b| b.uploaded_date.to_s }
  puts "  build: bundleVersion=#{build.version} uploaded=#{build.uploaded_date}"

  current = Spaceship::ConnectAPI.get_app_store_version(
    app_store_version_id: v.id, includes: 'build'
  ).to_models.first

  if current.build && current.build.id == build.id
    puts "  build already attached"
  else
    puts "  attaching build…"
    current.select_build(build_id: build.id)
    puts "  attached"
  end
end

puts "\n✓ Done. ASC versions bumped + builds attached."
puts "  Next: re-run upload_metadata + upload_screenshots to refresh per-version"
puts "  fields, then ios/mac submit_for_review when ready."
