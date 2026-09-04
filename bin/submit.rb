#!/usr/bin/env ruby
# frozen_string_literal: true

# `make submit` driver — stage and (optionally) submit the latest TestFlight
# build for App Store review across the platforms configured in PLATFORMS.
#
# Two-stage cadence:
#
#   `SUBMIT_FOR_REVIEW=false` (default in `.bootstrap.env.example`)
#     Stages the version: uploads screenshots + metadata + attaches the build
#     + fills export-compliance answers, but does NOT click "Submit for
#     Review". The version sits in App Store Connect's "Prepare for
#     Submission" state — review the prepared listing in the web UI, then
#     click Submit yourself. Recommended for first releases until you trust
#     your screenshots / metadata / CHANGELOG pipeline.
#
#   `SUBMIT_FOR_REVIEW=true`
#     Stages + auto-submits. Version goes straight to "Waiting for Review".
#     Recommended once you trust the pipeline.
#
# Per-invocation override (env wins over `.bootstrap.env`):
#   SUBMIT_FOR_REVIEW=true  make submit   # one-off auto-submit
#   SUBMIT_FOR_REVIEW=false make submit   # one-off stage when env says true
#
# Single-platform override (when both are configured):
#   PLATFORMS=ios   make submit
#   PLATFORMS=macos make submit
#
# Pre-flight gates:
#   - PLATFORMS resolves to ≥1 platform
#   - fastlane/screenshots/en-US/ has ≥1 PNG/JPG for each active platform
#   - fastlane/metadata/en-US/ exists
#
# GH Release side-effect (#175): only fires on the real submit path
# (SUBMIT_FOR_REVIEW=true). Staging is reversible; creating a "submitted"
# Release for a version that may never get submitted would be misleading.
#
# Usage:
#   bundle exec ruby bin/submit.rb             # stage or submit — contacts App Store Connect
#   bundle exec ruby bin/submit.rb --dry-run   # report the resolved target and lane; contacts nothing
#   bundle exec ruby bin/submit.rb --help      # print usage; -h is an alias
#
# Exit-code contract, in bin/preflight-identity.rb's shape. It is documented
# because this driver's failure mode is a write to production state, and a caller
# has to be able to tell "I do not understand you" apart from "this fork is not
# ready to submit" and from "the lane itself failed":
#
#   Exit | Meaning                                        | Message must name
#   -----+------------------------------------------------+---------------------------------
#   0    | -h / --help printed usage; or --dry-run        | — (usage; or the resolved app
#        | reported the target and stopped; or every      |     name, bundle id, platforms
#        | configured platform staged or submitted        |     and lane)
#   1    | an invocation or preflight refusal: identity   | the missing value; the invalid
#        | unresolvable, PLATFORMS invalid or empty, or   | PLATFORMS entries; or the missing
#        | metadata / screenshots missing                 | directory, by path
#   2    | the fastlane lane failed for ≥1 platform       | every failed platform
#   3    | unknown or malformed argv                      | the offending argument, verbatim
#
# WHY 3 AND NOT 2 for bad argv, which is what bin/adopt.rb uses. Exit 2 was
# already spoken for here, by "the lane failed", long before this front door
# existed. Redefining a live exit code to match a sibling would be a behaviour
# change wearing a consistency costume, so the code differs and the table says so.
#
# WHY THIS FRONT DOOR EXISTS AT ALL. Until 2026-09-04 this file parsed no
# arguments: `bin/submit.rb --help` was silently a write to App Store Connect.
# Its only safety was that SUBMIT_FOR_REVIEW is unset in most forks, so the lane
# resolved to the staging one — and the banner below tells the reader how to
# remove exactly that, after which a usage probe submits the app for review. On
# 2026-09-03 the same shape in bin/adopt.rb turned a typed `--help` into a live
# lane that overwrote 13 tracked files. Safety nobody chose is safety that leaves
# without notice, so an unrecognised argument is refused here rather than ignored.
#
# test/driver_argv_test.rb is the durable guard, and it observes this file by
# RUNNING a copy of it in a temp directory with capturing `bundle`, `fastlane`
# and `gh` shims first on PATH — reaching one of those shims from a
# non-consenting argument is its failure condition. It never runs this script in
# place, and neither should you.

# ─── Front door: parsed BEFORE the config read and before anything that can ──
# ─── open a connection. Flag-shaped or not, an unrecognised argument is    ──
# ─── refused BY NAME. A parser that inspected only tokens beginning with a  ──
# ─── dash would ignore a bare positional and fall straight through to the   ──
# ─── lane, which is the same failure in a different costume.                ──
SUBMIT_USAGE = <<~TEXT
  bin/submit.rb — stage, or submit, the latest TestFlight build for App Store
  review, across the platforms configured in PLATFORMS.

  THIS COMMAND WRITES TO APP STORE CONNECT. A bare run resolves to one of two
  fastlane lanes, and the SUBMIT_FOR_REVIEW variable — never an argument below —
  is what decides which:

    SUBMIT_FOR_REVIEW unset or false   ->  lane: stage_for_review
        Uploads screenshots and metadata, attaches the build, fills in the
        export-compliance answers, and STOPS. The version is left in App Store
        Connect's "Prepare for Submission" state for you to submit by hand.
        Reversible — but still a write to the live record. This is what a bare
        run does in a fork that has not set the variable.

    SUBMIT_FOR_REVIEW=true             ->  lane: submit_for_review
        All of the above, and then submits. The version goes to "Waiting for
        Review" and Apple begins reviewing it. In a fork with this set, a bare
        `bin/submit.rb` submits the app for App Store review.

  The variable is read from the environment first and from .bootstrap.env
  second. No flag below can turn submission on or off; set the variable if you
  mean to change the lane.

  Usage:
    bundle exec ruby bin/submit.rb             stage or submit — contacts App Store Connect
    bundle exec ruby bin/submit.rb --dry-run   report the resolved target and lane, contact nothing
    bundle exec ruby bin/submit.rb --help      print this usage (-h is an alias)

  Environment:
    PLATFORMS=ios|macos|ios,macos      restrict this run to a subset of the configured platforms
    SUBMIT_FOR_REVIEW=true|false       choose the lane, as above
    RELEASE_SKIP_GH_RELEASE=true       skip the GitHub Release the submit path would create

  Exit codes: 0 usage, a dry run, or a completed stage/submit; 1 an invocation or
  preflight refusal; 2 the fastlane lane failed; 3 an argument this script does
  not understand.
TEXT

dry_run = false
ARGV.each do |arg|
  case arg
  when "-h", "--help"
    puts SUBMIT_USAGE
    exit 0
  when "--dry-run"
    dry_run = true
  else
    warn "[submit] Unrecognised argument: #{arg}"
    warn "[submit] App Store Connect was NOT contacted and nothing was staged or submitted."
    warn ""
    warn SUBMIT_USAGE
    exit 3
  end
end

require_relative "lib/bootstrap"

config = Bootstrap::Config.load!
config.validate!

# ─── Identity: app/Identity.xcconfig, the source of truth (A-01) ─────────────
#
# Not .bootstrap.env, which no longer carries these values. `identity!` reads
# through the one xcconfig parser, resolves its path from __dir__ rather than
# the CWD, and refuses BY NAME instead of returning a default — a submission
# banner naming the wrong app is worse than one that never printed.
begin
  app_name  = Bootstrap.identity!("APP_PRODUCT_NAME")
  bundle_id = Bootstrap.identity!("BUNDLE_ID")
rescue StandardError => e
  Bootstrap::UI.fail!(e.message)
end

# ─── Resolve effective platforms (PLATFORMS env wins over config) ────────────
raw_platforms = ENV["PLATFORMS"].to_s.strip.empty? ? config.platforms.join(",") : ENV["PLATFORMS"]
platforms = raw_platforms.split(",").map(&:strip).reject(&:empty?)
valid = %w[ios macos]
bad = platforms - valid
unless bad.empty?
  Bootstrap::UI.fail!("PLATFORMS must be a subset of #{valid.inspect} (got #{bad.inspect})")
end
if platforms.empty?
  Bootstrap::UI.fail!("PLATFORMS resolved to empty. Set PLATFORMS in .bootstrap.env or pass PLATFORMS=ios|macos.")
end

# ─── Resolve auto-submit toggle (env wins over config; default false) ────────
def truthy?(v)
  %w[true 1 yes].include?(v.to_s.strip.downcase)
end

raw_submit = ENV.key?("SUBMIT_FOR_REVIEW") ? ENV["SUBMIT_FOR_REVIEW"] : config["SUBMIT_FOR_REVIEW"]
auto_submit = truthy?(raw_submit)

# --dry-run stops HERE: after identity, platforms and the lane have resolved, so
# the report names real values, and BEFORE the preflight gates below, so it
# REPORTS on missing metadata or screenshots rather than refusing over them. A
# dry run uploads nothing, so those gates have nothing to protect here; the same
# reasoning, and the same placement, as bin/adopt.rb's dry run relative to its
# clean-tree gate. The gates below are untouched and still fire for every real
# invocation.
if dry_run
  lane_preview   = auto_submit ? "submit_for_review" : "stage_for_review"
  submit_source  = ENV.key?("SUBMIT_FOR_REVIEW") ? "the environment" : ".bootstrap.env"
  metadata_state = Dir.exist?("fastlane/metadata/en-US") ? "present" : "MISSING — a real run refuses here"
  shots = {
    "ios"   => "fastlane/screenshots/en-US",
    "macos" => "fastlane/Mac_screenshots/en-US"
  }
  puts "[submit] DRY RUN — App Store Connect was NOT contacted; nothing was staged or submitted."
  puts "[submit] Would act on:  #{app_name} (#{bundle_id})"
  puts "[submit] Would run:     fastlane <platform> #{lane_preview}"
  puts "[submit] Would target:  #{platforms.join(', ')}"
  puts "[submit] Lane chosen by SUBMIT_FOR_REVIEW=#{raw_submit.to_s.strip.empty? ? '(unset)' : raw_submit} " \
       "read from #{submit_source}; set it to true and a bare run submits for review."
  puts "[submit] Would upload from:"
  puts "  fastlane/metadata/en-US/     #{metadata_state}"
  platforms.each do |p|
    dir = shots.fetch(p, shots["ios"])
    hits = Dir.glob(File.join(dir, "*.{png,jpg,jpeg,PNG,JPG,JPEG}")).length
    puts "  #{dir}/  #{hits} image(s)#{hits.zero? ? ' — a real run refuses here' : ''}"
  end
  exit 0
end

# ─── Pre-flight: screenshots + metadata exist ────────────────────────────────
unless Dir.exist?("fastlane/metadata/en-US")
  Bootstrap::UI.fail!("fastlane/metadata/en-US/ missing. Fill in metadata text files before submitting.")
end

screenshots_dir = "fastlane/screenshots/en-US"
unless Dir.exist?(screenshots_dir)
  Bootstrap::UI.fail!("#{screenshots_dir}/ missing. Run `make screenshots` first.")
end

# Per-platform screenshot existence. iOS + macOS screenshots live in
# separate top-level dirs to keep deliver from cross-uploading (fastlane's
# deliver action globs ALL files under its `screenshots_path` and assigns
# display types from PNG dimensions — when iOS + macOS share one parent,
# Apple's API rejects with "Display Type Not Allowed" because a 1440×900
# macOS PNG has no valid iOS display type and vice versa).
#   - iOS:   fastlane/screenshots/en-US/
#   - macOS: fastlane/Mac_screenshots/en-US/
mac_dir = "fastlane/Mac_screenshots/en-US"
platforms.each do |p|
  if p == "macos"
    hits = Dir.glob(File.join(mac_dir, "*.{png,jpg,jpeg,PNG,JPG,JPEG}"))
    if hits.empty?
      Bootstrap::UI.fail!("No macOS screenshots in #{mac_dir}/. Run `make screenshots` (or place files in `#{mac_dir}/`) first.")
    end
  else
    hits = Dir.glob(File.join(screenshots_dir, "*.{png,jpg,jpeg,PNG,JPG,JPEG}"))
    if hits.empty?
      Bootstrap::UI.fail!("No iOS screenshots in #{screenshots_dir}/. Run `make screenshots` (or place files in `#{screenshots_dir}/`) first.")
    end
  end
end

# ─── Read marketing version for the preflight summary ────────────────────────
def read_marketing_version
  if File.exist?("app/project.yml")
    if (m = File.read("app/project.yml", encoding: "UTF-8").match(/^\s*MARKETING_VERSION\s*:\s*["']?([^"'\s#]+)/))
      return m[1]
    end
  end
  if File.exist?("app/Project.swift")
    if (m = File.read("app/Project.swift", encoding: "UTF-8").match(/"MARKETING_VERSION"\s*:\s*"([^"]+)"/))
      return m[1]
    end
  end
  nil
end

marketing = read_marketing_version

# ─── Pre-flight summary ──────────────────────────────────────────────────────
puts
puts Bootstrap::UI.bold("About to #{auto_submit ? 'SUBMIT' : 'STAGE'} #{app_name} (#{bundle_id}):")
puts "  marketing version: #{marketing || '(could not read from project file)'}"
puts "  platforms:         #{platforms.join(', ')}"
puts "  mode:              #{auto_submit ? 'submit_for_review=true (auto-submit)' : 'submit_for_review=false (stage only)'}"
if auto_submit
  puts "  GH Release:        will be created at v#{marketing}+<latest-build> if `gh` CLI is available"
  puts "                     (set RELEASE_SKIP_GH_RELEASE=true to disable)"
else
  puts "  GH Release:        skipped (only created on actual submit, not staging)"
end
puts
unless auto_submit
  puts Bootstrap::UI.dim("Staging only. After this completes:")
  puts Bootstrap::UI.dim("  1. Open https://appstoreconnect.apple.com/apps and review the prepared version")
  puts Bootstrap::UI.dim("  2. Click \"Submit for Review\" yourself when ready")
  puts Bootstrap::UI.dim("  3. To auto-submit on future runs, set SUBMIT_FOR_REVIEW=true in .bootstrap.env")
  puts
end

# ─── Dispatch per platform ───────────────────────────────────────────────────
lane = auto_submit ? "submit_for_review" : "stage_for_review"
failed = []
env = Bootstrap.asc_env(config)

platforms.each do |p|
  fastlane_platform = (p == "macos" ? "mac" : p)
  puts Bootstrap::UI.bold("→ fastlane #{fastlane_platform} #{lane}")
  ok = system(env, "bundle", "exec", "fastlane", fastlane_platform, lane)
  if ok
    puts Bootstrap::UI.ok("  #{p} #{auto_submit ? 'submitted' : 'staged'}.")
  else
    failed << p
    puts Bootstrap::UI.warn("  #{p} #{lane} failed.")
  end
  puts
end

if failed.empty?
  puts Bootstrap::UI.bold("✅ All configured platforms #{auto_submit ? 'submitted' : 'staged'}.")
  if auto_submit
    puts "App Store Connect will now route the version through review (typically 24-48h)."
  else
    puts "Open App Store Connect to review and click Submit when ready."
  end
  exit 0
else
  Bootstrap::UI.fail!("Failed for: #{failed.join(', ')}. See fastlane output above for details.")
end
