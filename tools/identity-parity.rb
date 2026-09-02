#!/usr/bin/env ruby
# frozen_string_literal: true

# Criterion 3's instrument: prove that XcodeGen (app/project.yml) and Tuist
# (app/Project.swift) resolve the SAME identity, by diffing the output of
# `xcodebuild -showBuildSettings` across both generated projects.
#
# Criterion 3 is a -showBuildSettings diff or it is nothing. Reading the two
# manifests and judging them "equivalent" is forbidden (03-CONTEXT blocking
# constraint 3), and for a concrete reason: Xcode's layering rules are
# counter-intuitive here. A value in an xcconfig is OVERRIDDEN by anything a
# manifest writes into the .pbxproj's build-settings dictionary, so two
# manifests that both "point at Identity.xcconfig" can still resolve different
# identities if either one also writes a literal into the project. Only the
# resolved settings — what xcodebuild reports after every layer has been
# applied — can be compared factually. That is what this tool compares.
#
# What this tool CANNOT see, stated so nobody reads more into a green run:
# `xcodebuild -showBuildSettings` exits 0 and emits the full settings dump on
# a broken hard `#include "Missing.xcconfig"` (03-RESEARCH Pitfall 4, observed
# on Xcode 26.1.1); only a real `xcodebuild build` reports
# `could not find included file`. So this tool is NECESSARY for criterion 3
# but not SUFFICIENT: pair it with at least one real build per platform
# (03-09 locally; the template-owned pr.yml matrix on four cells).
#
# Where this runs: locally, by hand, and its output is recorded as dated
# evidence under .planning/. There is no fork-owned macOS CI surface in this
# repository — the fork's only workflow (`review notes`) runs ubuntu-latest,
# and all three macos-15 jobs live in template-owned .github/workflows/pr.yml
# (03-PATTERNS correction 5). A gate that needs xcodebuild therefore either
# runs here and is transcribed, or goes upstream. There is no third option.
#
# How the comparison is made. Both generators write to the SAME path —
# XcodeGen produces app/<NAME>.xcodeproj; Tuist produces app/<NAME>.xcodeproj
# AND app/<NAME>.xcworkspace — so they overwrite each other. The tool
# therefore generates with XcodeGen, extracts, generates with Tuist, extracts,
# and compares the two extractions. Whatever the verdict, it regenerates with
# XcodeGen as its final step, because ci/local-check.sh and the lefthook
# pre-push hook both expect XcodeGen's output on disk. Everything it writes is
# already gitignored (app/<NAME>.xcodeproj, app/<NAME>.xcworkspace,
# app/Derived/, .tuist/); it writes nowhere else.
#
# Extraction: for each scheme × configuration, run
#   xcodebuild -project app/<NAME>.xcodeproj -scheme <S> -configuration <C> -showBuildSettings
# strip leading whitespace, keep only the lines whose key is in IDENTITY_KEYS,
# sort. Both manifests' build actions contain only the app target, so the dump
# holds exactly one target block (03-RESEARCH §Q8, observed); the tool asserts
# that count and refuses to compare an ambiguous dump.
#
# On generator stderr: `tuist generate` prints a cosmetic
# "Invalid product name" warning whenever productName: is a build-setting
# reference such as $(APP_PRODUCT_NAME). It still generates and the value still
# resolves (03-RESEARCH Pitfall 5, observed). This tool keys off the generator's
# exit code and the project it produced, never off stderr text, and MUST NOT
# grow an assertion that generation emits no warnings — that assertion would go
# red permanently (T-03-17).
#
# WHAT THE COMPARISON COVERS — three halves, and the order they were added in
# is the argument for each of them.
#
#   1. The APP targets' identity keys (IDENTITY_KEYS, since 03-03): one
#      -showBuildSettings dump per scheme x configuration, per generator.
#   2. The UNIT-TEST bundles' TEST_HOST / BUNDLE_LOADER (D-60, 2026-09-02).
#      UL-027 escaped Phase 3 into CI precisely because half 1 could not see
#      it: TEST_HOST and BUNDLE_LOADER live on the TEST targets, and both
#      schemes' build actions contain only the app target, so the app dump
#      carries no TEST_HOST line at all — a longer IDENTITY_KEYS would have
#      found nothing and reported parity, which is a gate that cannot fail.
#      The test targets are therefore dumped with -target, one target per
#      dump. The expected value is neither a literal nor a copy of the
#      manifest: it is the HOST app target's OWN resolved
#      BUILT_PRODUCTS_DIR + EXECUTABLE_PATH, read from a second dump taken
#      with the same flags — plus BUNDLE_LOADER == TEST_HOST, plus the two
#      generators' TEST_HOST strings being identical. The defect this catches:
#      XcodeGen writes the host TARGET name into the pbxproj at generation
#      time while D-49 resolves the host's PRODUCT_NAME at BUILD time from
#      $(APP_PRODUCT_NAME), so the bundle is told to load a path nothing
#      builds and the scheme's test action fails with "Could not find test
#      host";
#      Tuist derives the same path from productName: and never broke, so the
#      failure is half-red on a two-generator matrix with no manifest diff to
#      explain it.
#
#      Paths are compared POSIX-normalised, and the raw strings are always
#      printed. Measured 2026-09-02 on this tree: XcodeGen writes the fork's
#      own spelling `$(BUILT_PRODUCTS_DIR)/$(APP_PRODUCT_NAME).app/$(APP_PRODUCT_NAME)`
#      (with `Contents/MacOS/` on macOS) while Tuist writes ONE platform-free
#      spelling for both,
#      `$(BUILT_PRODUCTS_DIR)/$(APP_PRODUCT_NAME).app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/$(APP_PRODUCT_NAME)`
#      — and `BUNDLE_EXECUTABLE_FOLDER_PATH` is EMPTY on iOS, so Tuist's
#      resolved iOS TEST_HOST is `…/ShipkitPipes.app//ShipkitPipes` with a
#      double slash where XcodeGen has one. The two paths name the same file
#      (POSIX collapses repeated slashes) and both generators' iOS test cells
#      are green in CI, so this is a spelling difference, not a defect — but a
#      byte comparison would fail on it forever, and a gate that is red for a
#      reason nobody can fix is a gate that gets deleted. So: normalise, and
#      print a NOTE naming the raw strings whenever normalisation is what made
#      them equal. Nothing is silently equalised (UL-043).
#   3. The BUILT Info.plist (D-60, UL-030). A resolved build setting is not a
#      bundle key: INFOPLIST_KEY_* reaches the bundle only under
#      GENERATE_INFOPLIST_FILE = YES, so a value can be correct in every dump
#      half 1 and half 2 read and absent from the artefact a user installs.
#      Half 3 therefore BUILDS each app unsigned and reads the bundle with
#      plutil, comparing CFBundleIdentifier / CFBundleDisplayName /
#      CFBundleName / NSHumanReadableCopyright against BUNDLE_ID /
#      DISPLAY_NAME / APP_PRODUCT_NAME / COPYRIGHT as bin/lib/xcconfig.rb
#      resolves them — the ONE reader (D-57), never a literal in this file.
#      The bundle is located from BUILT_PRODUCTS_DIR + FULL_PRODUCT_NAME /
#      INFOPLIST_PATH of a dump taken with the SAME flags as the build, never
#      by `find`: a guessed DerivedData path is how a stale artefact from an
#      earlier run gets read as this run's evidence.
#
# Halves 2 and 3 were each driven RED before they were trusted — half 2
# against a manifest carrying UL-027's original $(TARGET_NAME) spelling, half
# 3 against DISPLAY_NAME = Negative Control read from a bundle that was NOT
# rebuilt (evidence 04-12-T1 / 04-12-T2). A widening that was only ever seen
# green is not a gate, it is a decoration.
#
# THE BUILD, AND WHAT IT MUST NEVER BE. Half 3 runs the `build` action, and
# must never run the `test` one. A full-scheme macOS test run launches an
# unsigned UI-test runner and raises a Gatekeeper "damaged app" dialog on the
# operator's physical desktop (T-04-52). No code path in this file passes
# `test` to xcodebuild, none may ever be added, and the plan's verification
# greps this file for one — which is also why the prose above never puts the
# binary's name and that word on one line.
#
# --reuse-build DIR is a REUSE flag, not a cache. If the bundle is already
# there it is READ AS IT IS and NOT rebuilt, and every affected line says so.
# That is what makes the Negative Control control possible — mutate the
# xcconfig, do not rebuild, watch the artefact disagree with the file — and it
# is equally the flag's hazard: a bundle older than the manifest is exactly
# the stale-artefact false green this tool exists to eliminate, so the loud
# line is part of the contract, not noise. Without the flag every build goes
# into a fresh Dir.mktmpdir tree that is removed afterwards. Either way each
# generator builds into its OWN subdirectory (<dir>/xcodegen, <dir>/tuist):
# both generators produce the same product at the same relative path, so one
# shared tree would have let Tuist's half read XcodeGen's artefact — the same
# false green as the stale project, from the other side.
#
# --skip-plist opts out of half 3 and CHANGES THE VERDICT WORDING: the final
# line becomes `PARITY OK (build settings only; plist half skipped)`, never a
# bare `PARITY OK`, and a loud `! plist half SKIPPED by flag` precedes it. A
# skipped half that reads as full parity is T-04-50 — the tool telling you the
# artefact is right when it never opened one.
#
# Exit-code contract:
#
#   Exit | Meaning
#   -----+-------------------------------------------------------------------
#   0    | every scheme × configuration pair produced byte-identical filtered
#        | output from both generators (half 1); every unit-test bundle's
#        | TEST_HOST equalled its host target's own resolved product path,
#        | BUNDLE_LOADER equalled TEST_HOST, and both generators agreed on
#        | TEST_HOST (half 2); and, unless --skip-plist, every built
#        | Info.plist agreed with app/Identity.xcconfig on all four keys
#        | (half 3). With --skip-plist the verdict line says so in words.
#   1    | at least one comparison in any half differed (the unified diff is
#        | printed), or the argv was rejected (usage printed)
#   2    | no parity verdict was reached: a generator binary, plutil, the
#        | project, a scheme, a target or a configuration was absent; a
#        | generator exited non-zero (a signal-killed one reports 128+N);
#        | Tuist exited 0 but left XcodeGen's project.pbxproj byte-identical,
#        | so there was nothing to compare; the settings dump was ambiguous;
#        | a dump carried no line for a key the comparison needs (a setting
#        | that resolves to empty is omitted from the dump, so "absent" and
#        | "empty" are one observation here) — including a test target with
#        | no TEST_HOST; `xcodebuild build` failed in the plist half; plutil
#        | exited non-zero because the built bundle has no such key;
#        | app/Identity.xcconfig does not assign one of the four keys, or
#        | assigns it empty; no known platform row matched --schemes, so
#        | halves 2 and 3 had nothing to run against; --skip-generate was
#        | given; OR the final `xcodegen generate` that restores the tree
#        | failed — a parity verdict may have been printed above, but exit 0
#        | also vouches for the on-disk project being XcodeGen's, and after
#        | a failed restore it is Tuist's
#
# Exit 2 is the tools/asc-probe.rb:159-171 idiom. A query that matches nothing
# and an assertion that therefore never executes is the classic vacuous-truth
# gate; a distinct "I don't know" code makes "nothing was there" impossible to
# read as "everything checked out".
#
# Why --skip-generate can never exit 0: there is exactly one project path on
# disk, and both generators write to it. "Compare whatever is already there"
# means extracting the same project twice, which is a comparison that can only
# be green — the self-invalidating shape this phase exists to eliminate
# (T-03-12, 03-RESEARCH Pitfall 2's stale-project false green). So the flag is
# inspect-only: it prints the resolved identity block of the project on disk
# and exits 2, stating that no cross-generator comparison was made. Use it to
# read resolved settings, or to observe the absent-project path without
# generating; never as a gate. The main path guards the same shape from the
# other side: it fingerprints project.pbxproj after XcodeGen and refuses, exit
# 2, if Tuist exited 0 without changing a byte of it.
#
# Every run prints the installed xcodegen / tuist / xcodebuild versions beside
# the pins read from .tool-versions. A recorded fact without the tool version
# it was measured against is the "copying a measurement forward" anti-pattern.
# (.tool-versions pins xcodegen 2.45.4 while 2.46.0 is installed; that drift
# is a finding this phase records, not one this tool silences.)
#
# Usage (run from anywhere; paths resolve from this file's location):
#   ruby tools/identity-parity.rb                        # all three halves; builds
#   ruby tools/identity-parity.rb --skip-plist           # halves 1 and 2 only
#   ruby tools/identity-parity.rb --reuse-build /tmp/dd  # build once, reuse after
#   ruby tools/identity-parity.rb --project-name Legacy --schemes Legacy-iOS,Legacy-macOS
#   ruby tools/identity-parity.rb --configurations Release,Debug
#   ruby tools/identity-parity.rb --unit-test-targets NoSuch,AppMacOSTests   # exit 2 control
#   ruby tools/identity-parity.rb --skip-generate        # inspect-only, exits 2
#
# The plist half BUILDS: four unsigned builds on a full run (two generators x
# two platforms), 3-5 minutes each on the machine this was written on. Halves
# 1 and 2 are dumps only and take seconds. --reuse-build is how the red
# controls are driven without paying for a rebuild.
#
# Dependencies, stated exactly. No gem, no Gemfile entry, no test framework.
# Two load statements, both deliberate and both added with the D-60 widening:
#
#   require_relative "../bin/lib/xcconfig"  — the ONE xcconfig reader (D-57),
#       itself zero-require, so this stays gem-free. The plist half needs the
#       VALUES of BUNDLE_ID / APP_PRODUCT_NAME / DISPLAY_NAME / COPYRIGHT, and
#       a fifth hand-rolled reader in this file is the exact defect that module
#       exists to have removed (UL-032). It is core-only, and must stay so.
#   require "tmpdir"                        — stdlib, for the scratch
#       derivedData tree the plist half builds into when --reuse-build is not
#       given. Unlike bin/lib/xcconfig.rb this file is never loaded into
#       fastlane's process and never runs on the `review notes` ubuntu runner
#       (it needs Xcode), so the zero-require discipline that module is held to
#       does not bind here — but the requires are named rather than assumed.
#
# Every subprocess is an explicit argv array; there is no shell string, and the
# only rescue in this file names Xcconfig::MissingInclude.

require_relative "../bin/lib/xcconfig"
require "tmpdir"

# The identity key set, duplicated deliberately and never derived from the
# settings dump: a filter computed from the thing it filters cannot fail.
# DEVELOPMENT_TEAM is listed precisely so that it is ABSENT from both sides
# after this phase's changes — a symmetric absence is criterion 4's evidence
# that no team is in tracked build config. With no team set, xcodebuild emits
# no DEVELOPMENT_TEAM line at all and instead emits the undocumented internal
# `_DEVELOPMENT_TEAM_IS_EMPTY = YES`; that line is reported as corroboration
# only and is never gated on.
IDENTITY_KEYS = %w[
  PRODUCT_BUNDLE_IDENTIFIER
  PRODUCT_NAME
  FULL_PRODUCT_NAME
  INFOPLIST_KEY_NSHumanReadableCopyright
  DEVELOPMENT_TEAM
  MARKETING_VERSION
  CURRENT_PROJECT_VERSION
  SWIFT_VERSION
].freeze

# Half 2's keys. TARGET_NAME is read from the test dump for one purpose: to
# print, beside a failing TEST_HOST, the target name UL-027's XcodeGen would
# have spelled it from — so the transcript shows the mechanism and not just a
# mismatch.
TEST_BUNDLE_KEYS = %w[TEST_HOST BUNDLE_LOADER TARGET_NAME].freeze

# The host app target's own resolved product location. EXECUTABLE_PATH is what
# makes the expected TEST_HOST derived rather than copied; INFOPLIST_PATH is
# how half 3 finds the plist inside the bundle without knowing which platform
# it is looking at (it is `X.app/Info.plist` on iOS and
# `X.app/Contents/Info.plist` on macOS, and the dump says which).
HOST_PRODUCT_KEYS = %w[BUILT_PRODUCTS_DIR EXECUTABLE_PATH FULL_PRODUCT_NAME INFOPLIST_PATH].freeze

# Half 3's four comparisons: a key in the BUILT bundle, and the
# app/Identity.xcconfig variable it must equal. Left side read with plutil from
# the artefact, right side resolved by bin/lib/xcconfig.rb from the tracked
# file. Neither side is a literal in this file — a "expected" string spelled
# here would be a fifth reader of the identity, and it would go stale the first
# time the fork rebrands.
PLIST_EXPECTATIONS = [
  %w[CFBundleIdentifier      BUNDLE_ID],
  %w[CFBundleDisplayName     DISPLAY_NAME],
  %w[CFBundleName            APP_PRODUCT_NAME],
  %w[NSHumanReadableCopyright COPYRIGHT],
].freeze

# The structural constants (D-47): the project is `App`, the schemes and the
# app targets are `App-iOS` / `App-macOS`, the unit-test bundles are `AppTests`
# / `AppMacOSTests`. Rows are matched against --schemes by scheme name, so a
# run restricted to one scheme runs halves 2 and 3 for that platform only, and
# a run whose schemes match NO row gets a no-verdict rather than a silent skip.
#
# build_flags are the flags half 3's build AND its dump both take. iOS builds
# for the simulator: an unsigned device build is possible but the simulator is
# what Phase 3 measured the built plists on (03-09), and it needs no signing
# identity at all. The UI-test bundles (AppUITests / AppMacOSUITests) are
# deliberately absent from this table: they carry TEST_TARGET_NAME, which is a
# target name and correct as such, and no TEST_HOST — there is nothing here for
# them to be compared against.
PLATFORMS = [
  {
    scheme: "App-iOS", host_target: "App-iOS", unit_test_target: "AppTests",
    build_flags: ["-sdk", "iphonesimulator", "-destination", "generic/platform=iOS Simulator"],
  },
  {
    scheme: "App-macOS", host_target: "App-macOS", unit_test_target: "AppMacOSTests",
    build_flags: ["-destination", "platform=macOS"],
  },
].freeze

# Halves 2 and 3 run at Debug, whatever --configurations asks of half 1: Debug
# is the configuration both schemes' test actions use, so it is the one whose
# TEST_HOST a real test run would resolve, and the one whose bundle a
# developer runs. Stated rather than implied, because a Release-only invocation
# would otherwise look like it had checked something it had not.
ARTEFACT_CONFIGURATION = "Debug"

# Unbuffered stdout, so a captured transcript reads in the order events
# happened rather than with every stderr line hoisted above the stdout block.
$stdout.sync = true

ROOT             = File.expand_path("..", __dir__)
APP_DIR          = File.join(ROOT, "app")
TOOL_VERSIONS    = File.join(ROOT, ".tool-versions")
IDENTITY_XCCONFIG = File.join(APP_DIR, "Identity.xcconfig")

DEFAULT_PROJECT_NAME   = "App"
DEFAULT_SCHEMES        = %w[App-iOS App-macOS].freeze
DEFAULT_CONFIGURATIONS = %w[Release Debug].freeze

REQUIRED_TOOLS = %w[xcodegen tuist xcodebuild].freeze
# plutil is required only when half 3 runs; a --skip-plist run must not fail
# for the absence of a binary it never invokes.
PLIST_TOOLS = %w[plutil].freeze

USAGE = <<~TXT
  usage: ruby tools/identity-parity.rb [--project-name NAME] [--schemes A,B]
                                       [--configurations A,B] [--unit-test-targets A,B]
                                       [--skip-plist] [--reuse-build DIR] [--skip-generate]
    --project-name NAME    project name both manifests declare (default: #{DEFAULT_PROJECT_NAME})
    --schemes A,B          schemes to compare (default: #{DEFAULT_SCHEMES.join(',')})
    --configurations A,B   configurations to compare (default: #{DEFAULT_CONFIGURATIONS.join(',')})
    --unit-test-targets A,B  unit-test bundles for half 2, positional against the matched
                           schemes (default: #{PLATFORMS.map { |r| r[:unit_test_target] }.join(',')})
    --skip-plist           skip half 3 (no builds); the verdict line says so in words
    --reuse-build DIR      build half 3 into DIR/<generator> and REUSE any bundle already
                           there instead of rebuilding it (loudly). Without it, a fresh
                           Dir.mktmpdir tree is used and removed.
    --skip-generate        inspect the project already on disk; no comparison, exits 2
    -h, --help             print this and exit 0
  exit 0 = build settings, TEST_HOST/BUNDLE_LOADER and (unless --skip-plist) the built
           Info.plist all agree, across XcodeGen and Tuist
  exit 1 = at least one comparison differed (diff printed), or bad argv
  exit 2 = no verdict: absent tool/project/scheme/target/configuration or key, generator or
           build failure, a plutil miss, an unassigned or empty key in app/Identity.xcconfig,
           no platform row matching --schemes, a failed final xcodegen restore (the tree is
           Tuist's), or --skip-generate
  half 3 BUILDS: four unsigned builds on a full run, minutes each. It never runs the test action.
TXT

# Every failure path is explicit and loud, on stderr, prefixed.
def die(message)
  warn "identity-parity: #{message}"
  exit 1
end

# The distinct "I don't know" outcome.
def no_verdict(message)
  warn "identity-parity: no verdict: #{message}"
  exit 2
end

def parse_args(argv)
  opts = {
    project_name: DEFAULT_PROJECT_NAME,
    schemes: DEFAULT_SCHEMES,
    configurations: DEFAULT_CONFIGURATIONS,
    unit_test_targets: nil,
    skip_plist: false,
    reuse_build: nil,
    skip_generate: false,
  }
  index = 0
  while index < argv.length
    case argv[index]
    when "--project-name"
      index += 1
      die "--project-name requires a value\n#{USAGE}" if argv[index].nil? || argv[index].empty?
      opts[:project_name] = argv[index]
    when "--schemes"
      index += 1
      die "--schemes requires a value\n#{USAGE}" if argv[index].nil?
      opts[:schemes] = argv[index].split(",").map(&:strip).reject(&:empty?)
      die "--schemes needs at least one scheme\n#{USAGE}" if opts[:schemes].empty?
    when "--configurations"
      index += 1
      die "--configurations requires a value\n#{USAGE}" if argv[index].nil?
      opts[:configurations] = argv[index].split(",").map(&:strip).reject(&:empty?)
      die "--configurations needs at least one configuration\n#{USAGE}" if opts[:configurations].empty?
    when "--unit-test-targets"
      index += 1
      die "--unit-test-targets requires a value\n#{USAGE}" if argv[index].nil?
      opts[:unit_test_targets] = argv[index].split(",").map(&:strip).reject(&:empty?)
      die "--unit-test-targets needs at least one target\n#{USAGE}" if opts[:unit_test_targets].empty?
    when "--skip-plist"
      opts[:skip_plist] = true
    when "--reuse-build"
      index += 1
      die "--reuse-build requires a value\n#{USAGE}" if argv[index].nil? || argv[index].empty?
      opts[:reuse_build] = File.expand_path(argv[index])
    when "--skip-generate"
      opts[:skip_generate] = true
    when "-h", "--help"
      puts USAGE
      exit 0
    else
      # Unknown argv is rejected, never ignored: a typo'd flag must not look
      # like a successful run.
      die "unknown argument #{argv[index].inspect}\n#{USAGE}"
    end
    index += 1
  end
  opts
end

# Run an argv array, capturing stdout and stderr separately. No shell.
# stderr is drained on its own thread so a chatty generator cannot deadlock
# the pipe while stdout is being read.
#
# The command is passed as [cmd, argv0] rather than splatted: Process.spawn
# with a single string argument is the STRING form, which Ruby hands to
# /bin/sh whenever the string carries a metacharacter, so `Process.spawn(*argv)`
# on a one-element argv would have been a shell string after all — latent, as
# every caller here passes two or more elements, but contradicting the header's
# unconditional promise (03-REVIEW IN-04, demonstrated: the splat ran
# `true; echo INJECTED` through the shell, this form raises ENOENT on it). The
# two-element array form is never shell-interpreted, whatever argv holds.
def capture(argv, chdir: ROOT)
  out_r, out_w = IO.pipe
  err_r, err_w = IO.pipe
  pid = Process.spawn([argv[0], argv[0]], *argv[1..], chdir: chdir, in: File::NULL, out: out_w, err: err_w)
  out_w.close
  err_w.close
  err_thread = Thread.new { err_r.read }
  out = out_r.read
  err = err_thread.value
  out_r.close
  err_r.close
  Process.wait(pid)
  # A child killed by a signal (a timeout, an OOM kill, an operator's `kill`)
  # has exitstatus nil, and every caller's `status.zero?` would then raise
  # NoMethodError — Ruby's exit 1, which the contract reserves for "a pair
  # differed" (03-REVIEW WR-05, observed with SIGTERM). Report it as the
  # shell's conventional 128+N instead, so the caller's non-zero branch fires
  # and the run ends in the documented exit 2 naming the generator.
  status = $?.exitstatus || (128 + $?.termsig.to_i)
  [utf8(out), utf8(err), status]
end

# Pin UTF-8 explicitly rather than inheriting the locale (the fork's idiom
# since commit 3b1efb9): with LANG unset, Ruby's default external encoding is
# US-ASCII and a regex over a dump containing © raises instead of matching.
def utf8(text)
  text = text.dup.force_encoding(Encoding::UTF_8)
  text.valid_encoding? ? text : text.scrub("?")
end

# PATH lookup in Ruby, so a missing binary is reported by name before any
# subprocess is attempted.
def on_path?(name)
  ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
    next false if dir.empty?

    candidate = File.join(dir, name)
    File.file?(candidate) && File.executable?(candidate)
  end
end

def tool_versions_pins
  pins = {}
  return pins unless File.file?(TOOL_VERSIONS)

  File.read(TOOL_VERSIONS, encoding: "UTF-8").each_line do |line|
    next if line.start_with?("#") || line.strip.empty?

    name, version = line.split(/\s+/, 3)
    pins[name] = version if name && version
  end
  pins
end

def print_versions
  pins = tool_versions_pins
  puts "identity-parity: tool versions (installed vs .tool-versions pin)"
  {
    "xcodegen"   => %w[xcodegen --version],
    "tuist"      => %w[tuist version],
    "xcodebuild" => %w[xcodebuild -version],
  }.each do |name, argv|
    out, err, status = capture(argv)
    text = (out + err).lines.map(&:strip).reject(&:empty?).join(" | ")
    text = "(exit #{status}, no output)" if text.empty?
    pin  = pins.fetch(name, "(not pinned in .tool-versions)")
    puts "  #{name}: installed #{text} ; pinned #{pin}"
  end
end

def run_generator(label, argv)
  puts "identity-parity: #{label}: #{argv.join(' ')}  (cwd: app/)"
  out, err, status = capture(argv, chdir: APP_DIR)
  # Print what the generator said, verbatim, but do not judge it: stderr text
  # is not evidence of failure (Pitfall 5). Only the exit code is.
  out.each_line { |l| puts "  [#{label} stdout] #{l.chomp}" }
  err.each_line { |l| puts "  [#{label} stderr] #{l.chomp}" }
  no_verdict "#{argv.join(' ')} exited #{status}; no project to compare" unless status.zero?
end

def project_path(project_name)
  File.join(APP_DIR, "#{project_name}.xcodeproj")
end

def assert_project_present(project_name)
  path = project_path(project_name)
  return path if File.directory?(path) && File.file?(File.join(path, "project.pbxproj"))

  no_verdict "project #{project_name} is absent: #{path} does not exist (or has no project.pbxproj). " \
             "Nothing was compared, because there was nothing to compare against."
end

def assert_scheme_present(project, scheme)
  shared = File.join(project, "xcshareddata", "xcschemes", "#{scheme}.xcscheme")
  return if File.file?(shared)

  no_verdict "scheme #{scheme} is absent from #{project}: #{shared} does not exist. " \
             "Nothing was compared for that scheme."
end

# Extract the sorted identity block for one scheme × configuration.
def extract(project, scheme, configuration)
  argv = [
    "xcodebuild", "-project", project, "-scheme", scheme,
    "-configuration", configuration, "-showBuildSettings",
  ]
  out, err, status = capture(argv)
  unless status.zero?
    no_verdict "xcodebuild -showBuildSettings exited #{status} for scheme #{scheme} " \
               "configuration #{configuration} in #{project}:\n#{err.strip}"
  end

  blocks = out.lines.count { |l| l.include?("Build settings for action") }
  unless blocks == 1
    no_verdict "expected exactly one target block for scheme #{scheme} configuration " \
               "#{configuration}, found #{blocks}; the filter would be ambiguous. " \
               "If a scheme's build action grew a second target, switch to -target."
  end

  # The dump must be for the configuration that was asked for. A build tool
  # that silently substituted a default configuration would otherwise be
  # compared as if it were the requested one.
  stripped = out.lines.map { |l| l.sub(/\A\s+/, "").chomp }
  reported = stripped.find { |l| l.start_with?("CONFIGURATION = ") }&.delete_prefix("CONFIGURATION = ")
  unless reported == configuration
    no_verdict "configuration #{configuration} was requested for scheme #{scheme} but the settings " \
               "dump reports CONFIGURATION = #{reported.inspect}; refusing to compare a substituted configuration"
  end

  keys = Regexp.union(IDENTITY_KEYS.map { |k| Regexp.new("\\A#{Regexp.escape(k)} = ") })
  lines = stripped.select { |l| l.match?(keys) }.sort
  team_empty = out.lines.any? { |l| l.strip == "_DEVELOPMENT_TEAM_IS_EMPTY = YES" }
  [lines, team_empty]
end

def extract_all(project, schemes, configurations)
  store = {}
  schemes.each do |scheme|
    assert_scheme_present(project, scheme)
    configurations.each do |configuration|
      store[[scheme, configuration]] = extract(project, scheme, configuration)
    end
  end
  store
end

# Minimal LCS line diff, rendered in unified format. Inputs are short sorted
# key lists, so a quadratic table is fine and avoids any require.
def unified_diff(a, b, from_label, to_label)
  n = a.length
  m = b.length
  table = Array.new(n + 1) { Array.new(m + 1, 0) }
  (n - 1).downto(0) do |i|
    (m - 1).downto(0) do |j|
      table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : [table[i + 1][j], table[i][j + 1]].max
    end
  end
  hunk = []
  i = 0
  j = 0
  while i < n || j < m
    if i < n && j < m && a[i] == b[j]
      hunk << " #{a[i]}"
      i += 1
      j += 1
    elsif i < n && (j >= m || table[i + 1][j] >= table[i][j + 1])
      # Removal before insertion, as diff -u prints it.
      hunk << "-#{a[i]}"
      i += 1
    else
      hunk << "+#{b[j]}"
      j += 1
    end
  end
  ["--- #{from_label}", "+++ #{to_label}", "@@ -1,#{n} +1,#{m} @@", *hunk].join("\n")
end

def print_block(title, lines, team_empty)
  puts "--- #{title} ---"
  lines.each { |l| puts l }
  puts "(no DEVELOPMENT_TEAM line; _DEVELOPMENT_TEAM_IS_EMPTY = YES observed — corroboration only, not gated)" if team_empty
end

# ── Halves 2 and 3: reading one target's resolved settings ───────────────
#
# `selector` is the -target/-scheme choice PLUS any flag that moves the build
# products (-sdk, -destination, -derivedDataPath). The dump must be taken with
# the SAME flags as the thing it describes: BUILT_PRODUCTS_DIR under
# -derivedDataPath is not the same directory as without it, and a dump taken
# with different flags would name a path the build never wrote to.
def target_settings(project, selector, configuration, keys, what)
  argv = ["xcodebuild", "-project", project, *selector, "-configuration", configuration, "-showBuildSettings"]
  out, err, status = capture(argv)
  unless status.zero?
    no_verdict "xcodebuild -showBuildSettings exited #{status} for #{what} in #{project}:\n#{err.strip}"
  end

  blocks = out.lines.count { |l| l.include?("Build settings for action") }
  unless blocks == 1
    no_verdict "expected exactly one target block for #{what}, found #{blocks}; the read would be ambiguous"
  end

  stripped = out.lines.map { |l| l.sub(/\A\s+/, "").chomp }
  reported = stripped.find { |l| l.start_with?("CONFIGURATION = ") }&.delete_prefix("CONFIGURATION = ")
  unless reported == configuration
    no_verdict "configuration #{configuration} was requested for #{what} but the settings dump reports " \
               "CONFIGURATION = #{reported.inspect}; refusing to read a substituted configuration"
  end

  keys.each_with_object({}) do |key, found|
    line = stripped.find { |l| l.start_with?("#{key} = ") }
    # A setting that resolves to the empty string is OMITTED from the dump
    # entirely (03-09, observed), so "no line" and "empty value" are one
    # observation here — and both are a no-verdict, never a silent nil that
    # would compare equal to another silent nil on the other generator.
    no_verdict "#{what} in #{project} reports no #{key} line; there is nothing to compare" if line.nil?
    found[key] = line.delete_prefix("#{key} = ")
  end
end

# Half 2. For each platform row: the unit-test bundle's TEST_HOST/BUNDLE_LOADER
# from a -target dump, and the host app target's own BUILT_PRODUCTS_DIR +
# EXECUTABLE_PATH from a second -target dump taken with the same flags.
def test_bundle_probe(project, rows, configuration)
  rows.each_with_object({}) do |row, store|
    test_target = row[:unit_test_target]
    host_target = row[:host_target]
    t = target_settings(project, ["-target", test_target], configuration,
                        TEST_BUNDLE_KEYS, "unit-test target #{test_target}")
    h = target_settings(project, ["-target", host_target], configuration,
                        HOST_PRODUCT_KEYS, "host app target #{host_target}")
    store[test_target] = {
      host_target: host_target,
      test_host: t["TEST_HOST"],
      bundle_loader: t["BUNDLE_LOADER"],
      target_name: t["TARGET_NAME"],
      host_resolved: File.join(h["BUILT_PRODUCTS_DIR"], h["EXECUTABLE_PATH"]),
      host_built_products_dir: h["BUILT_PRODUCTS_DIR"],
      host_executable_path: h["EXECUTABLE_PATH"],
    }
  end
end

# POSIX collapses a run of slashes inside a path: `a//b` and `a/b` name the
# same file, and both generators' iOS unit-test cells are green in CI with the
# two different spellings. Comparison is therefore on this normal form, while
# every printed line shows the raw string — a normalisation you cannot see is
# indistinguishable from a comparison that was quietly weakened.
#
# The leading-`//` case POSIX leaves implementation-defined does not arise: all
# of these paths are BUILT_PRODUCTS_DIR-rooted absolutes under the build tree.
def posix_path(path)
  path.gsub(%r{/{2,}}, "/")
end

# True when two paths differ as text but name the same file. The caller prints
# the raw pair; this only decides whether it is a NOTE or a failure.
def same_path?(a, b)
  posix_path(a) == posix_path(b)
end

# One-line-versus-one-line diff, in the same unified shape half 1 prints, so a
# transcript reads the same way whichever half failed.
def value_diff(from_label, from_value, to_label, to_value)
  unified_diff(["#{from_label} = #{from_value}"], ["#{to_label} = #{to_value}"], from_label, to_label)
end

def report_test_bundles(label, probe, configuration)
  failures = 0
  probe.each do |test_target, r|
    puts "--- #{label} #{test_target} -> #{r[:host_target]} #{configuration} (TEST_HOST / BUNDLE_LOADER) ---"
    puts "TEST_HOST = #{r[:test_host]}"
    puts "BUNDLE_LOADER = #{r[:bundle_loader]}"
    puts "host BUILT_PRODUCTS_DIR = #{r[:host_built_products_dir]}"
    puts "host EXECUTABLE_PATH = #{r[:host_executable_path]}"

    if same_path?(r[:test_host], r[:host_resolved])
      puts "OK #{test_target}: TEST_HOST is the host target's own resolved product path"
      unless r[:test_host] == r[:host_resolved]
        puts "   NOTE: equal only after POSIX slash normalisation — raw TEST_HOST #{r[:test_host].inspect} " \
             "vs raw host path #{r[:host_resolved].inspect} (see the header: Tuist interpolates an empty " \
             "$(BUNDLE_EXECUTABLE_FOLDER_PATH) on iOS)"
      end
    else
      failures += 1
      puts "#{label} #{test_target}: TEST_HOST DIFFERS from #{r[:host_target]}'s resolved product path " \
           "(the test target's own name is #{r[:target_name]} — UL-027 spells TEST_HOST from the host " \
           "TARGET name, which is only right while PRODUCT_NAME equals it)"
      puts value_diff("#{label} #{test_target} TEST_HOST", r[:test_host],
                      "#{label} #{r[:host_target]} BUILT_PRODUCTS_DIR/EXECUTABLE_PATH", r[:host_resolved])
    end

    if same_path?(r[:bundle_loader], r[:test_host])
      puts "OK #{test_target}: BUNDLE_LOADER equals TEST_HOST"
      unless r[:bundle_loader] == r[:test_host]
        puts "   NOTE: equal only after POSIX slash normalisation — raw BUNDLE_LOADER " \
             "#{r[:bundle_loader].inspect} vs raw TEST_HOST #{r[:test_host].inspect}"
      end
    else
      failures += 1
      puts "#{label} #{test_target}: BUNDLE_LOADER DIFFERS from TEST_HOST"
      puts value_diff("#{label} #{test_target} BUNDLE_LOADER", r[:bundle_loader],
                      "#{label} #{test_target} TEST_HOST", r[:test_host])
    end
  end
  failures
end

def report_test_bundles_across(xcodegen_probe, tuist_probe)
  failures = 0
  xcodegen_probe.each do |test_target, xg|
    tu = tuist_probe[test_target]
    # Cannot be nil: both probes iterate the same rows. Asserted rather than
    # assumed, because a nil on both sides would compare equal.
    no_verdict "tuist produced no TEST_HOST reading for #{test_target}" if tu.nil?
    if same_path?(xg[:test_host], tu[:test_host])
      if xg[:test_host] == tu[:test_host]
        puts "--- tuist #{test_target} TEST_HOST --- identical to xcodegen"
      else
        puts "--- tuist #{test_target} TEST_HOST --- equal to xcodegen's after POSIX slash normalisation, " \
             "raw strings differ (UL-043): xcodegen #{xg[:test_host].inspect} vs tuist #{tu[:test_host].inspect}"
      end
    else
      failures += 1
      puts "--- tuist #{test_target} TEST_HOST --- DIFFERS from xcodegen"
      puts value_diff("xcodegen #{test_target} TEST_HOST", xg[:test_host],
                      "tuist #{test_target} TEST_HOST", tu[:test_host])
    end
  end
  failures
end

# ── Half 3: the built Info.plist ─────────────────────────────────────────

# The right-hand side of half 3, resolved by the ONE reader. nil (never
# assigned) and "" (assigned but empty or comment-only) are different defects
# and get different messages; both are a no-verdict, because a comparison
# against nothing is not a comparison.
def xcconfig_expectations
  PLIST_EXPECTATIONS.each_with_object({}) do |(plist_key, xcconfig_key), acc|
    value =
      begin
        Xcconfig.value(IDENTITY_XCCONFIG, xcconfig_key)
      rescue Xcconfig::MissingInclude => e
        no_verdict "app/Identity.xcconfig could not be resolved: #{e.message}"
      end
    if value.nil?
      no_verdict "#{xcconfig_key} is never assigned in #{IDENTITY_XCCONFIG}; there is nothing for the " \
                 "built #{plist_key} to be compared against"
    elsif value.empty?
      no_verdict "#{xcconfig_key} resolves to the empty string in #{IDENTITY_XCCONFIG} (assigned, but " \
                 "empty or comment-only — the UL-031 shape); refusing to compare #{plist_key} against nothing"
    end
    acc[plist_key] = value
  end
end

# Byte-level rendering, for the characters a transcript cannot be trusted on:
# COPYRIGHT carries © (U+00A9, UTF-8 c2 a9), and "it looked right in the
# terminal" is how a mojibake'd copyright reaches the App Store.
def hex_bytes(text)
  text.bytes.map { |b| format("%02x", b) }.join(" ")
end

def build_and_read_plist(label, project, rows, configuration, build_root, reuse)
  derived = File.join(build_root, label)
  rows.each_with_object({}) do |row, store|
    scheme = row[:scheme]
    flags  = [*row[:build_flags], "-derivedDataPath", derived]
    host = target_settings(project, ["-scheme", scheme, *flags], configuration,
                           HOST_PRODUCT_KEYS, "scheme #{scheme} (plist half, derivedDataPath #{derived})")
    bundle = File.join(host["BUILT_PRODUCTS_DIR"], host["FULL_PRODUCT_NAME"])
    plist  = File.join(host["BUILT_PRODUCTS_DIR"], host["INFOPLIST_PATH"])

    if reuse && File.file?(plist)
      puts "identity-parity: [#{label} #{scheme}] REUSING the bundle already at #{bundle} — NOT rebuilt " \
           "(--reuse-build). What follows describes THAT artefact, which may be older than the manifests."
    else
      argv = ["xcodebuild", "build", "-project", project, "-scheme", scheme,
              "-configuration", configuration, *flags, "CODE_SIGNING_ALLOWED=NO"]
      puts "identity-parity: [#{label} #{scheme}] #{argv.join(' ')}"
      started = Time.now
      out, err, status = capture(argv)
      elapsed = (Time.now - started).round(1)
      unless status.zero?
        no_verdict "xcodebuild build exited #{status} for scheme #{scheme} (#{label}) after #{elapsed}s; " \
                   "there is no built bundle to read:\n" \
                   "#{(out.lines.last(15) + err.lines.last(15)).map(&:chomp).join("\n")}"
      end
      puts "identity-parity: [#{label} #{scheme}] build exit 0 in #{elapsed}s"
    end

    unless File.file?(plist)
      no_verdict "no Info.plist at #{plist} after the #{label} #{scheme} step; the dump says the bundle " \
                 "belongs there, so either the build wrote nothing or --reuse-build points at an empty tree"
    end
    puts "identity-parity: [#{label} #{scheme}] reading #{plist}"

    values = PLIST_EXPECTATIONS.each_with_object({}) do |(plist_key, _), acc|
      out, err, status = capture(["plutil", "-extract", plist_key, "raw", "-o", "-", plist])
      unless status.zero?
        no_verdict "plutil -extract #{plist_key} exited #{status} on #{plist} (#{label} #{scheme}): " \
                   "#{(out + err).strip} — the key the xcconfig feeds is not in the BUILT bundle, which " \
                   "is UL-030's shape and is exactly what this half exists to catch"
      end
      acc[plist_key] = out.chomp
    end
    store[scheme] = { plist: plist, bundle: bundle, values: values }
  end
end

def report_plist(label, probe, expectations)
  failures = 0
  probe.each do |scheme, r|
    puts "--- #{label} #{scheme} built Info.plist (#{r[:plist]}) ---"
    PLIST_EXPECTATIONS.each do |plist_key, xcconfig_key|
      built    = r[:values][plist_key]
      expected = expectations[plist_key]
      if built == expected
        puts "OK #{plist_key} = #{built}   (== #{xcconfig_key} in app/Identity.xcconfig)"
      else
        failures += 1
        puts "#{label} #{scheme}: the built #{plist_key} DIFFERS from #{xcconfig_key} in app/Identity.xcconfig"
        puts value_diff("built #{plist_key}", built, "xcconfig #{xcconfig_key}", expected)
      end
      next unless plist_key == "NSHumanReadableCopyright"

      # Printed on every run, pass or fail: the © is the byte this project has
      # already been bitten by (UL-012), and bytes are the only honest reading.
      puts "   bytes(built)    = #{hex_bytes(built)}"
      puts "   bytes(xcconfig) = #{hex_bytes(expected)}"
    end
  end
  failures
end

# The whole comparison, from the first `xcodegen generate` to the verdict.
# `build_root` is nil when --skip-plist was given (half 3 does not run) and a
# directory otherwise; `reuse` is true only for --reuse-build.
def run_parity(opts, rows, build_root, reuse)
  tuist_ran = false
  restore_status = nil
  xcodegen_argv = %w[xcodegen generate]
  # The parity verdict (0 or 1) is the value of this begin block; a no_verdict
  # inside it exits 2 through the ensure. The restore's own status is kept
  # separately and judged after the block, because exit 0 must vouch for the
  # tree as well as for parity — see the check below the ensure.
  verdict = begin
    run_generator("xcodegen", xcodegen_argv)
    project = assert_project_present(opts[:project_name])

    # Fingerprint XcodeGen's pbxproj before Tuist runs. The comparison below
    # is "the project on disk after each generator", so a `tuist generate`
    # that exits 0 without rewriting the file — a Tuist/Config.swift or
    # Workspace.swift redirecting output, a wrong --project-name, a future
    # cache skip — would make the second extraction read XcodeGen's project
    # again and the verdict a false PARITY OK: the stale-project false green
    # the header says this tool exists to eliminate, closed for --skip-generate
    # and, until this check, open on the main path (03-REVIEW WR-04). XcodeGen
    # and Tuist never emit identical pbxproj bytes (their object ids differ),
    # so an unchanged file can only mean nothing was regenerated. Taken here,
    # before the halves read or build anything, so nothing in between can be
    # blamed for a change.
    pbxproj_after_xcodegen = File.binread(File.join(project, "project.pbxproj"))

    xcodegen_store = extract_all(project, opts[:schemes], opts[:configurations])
    xcodegen_tests = test_bundle_probe(project, rows, ARTEFACT_CONFIGURATION)
    xcodegen_plist =
      build_root && build_and_read_plist("xcodegen", project, rows, ARTEFACT_CONFIGURATION, build_root, reuse)

    tuist_ran = true
    run_generator("tuist", %w[tuist generate --no-open])
    project = assert_project_present(opts[:project_name])
    if File.binread(File.join(project, "project.pbxproj")) == pbxproj_after_xcodegen
      no_verdict "tuist generate exited 0 but #{project}/project.pbxproj is byte-identical to XcodeGen's " \
                 "output; nothing was regenerated, so a comparison would read the same project twice"
    end
    tuist_store = extract_all(project, opts[:schemes], opts[:configurations])
    tuist_tests = test_bundle_probe(project, rows, ARTEFACT_CONFIGURATION)
    tuist_plist =
      build_root && build_and_read_plist("tuist", project, rows, ARTEFACT_CONFIGURATION, build_root, reuse)

    differing = 0

    # ── half 1: the app targets' identity keys ──────────────────────────
    opts[:schemes].each do |scheme|
      opts[:configurations].each do |cfg|
        xg_lines, xg_team_empty = xcodegen_store[[scheme, cfg]]
        tu_lines, tu_team_empty = tuist_store[[scheme, cfg]]
        print_block("xcodegen #{scheme} #{cfg}", xg_lines, xg_team_empty)
        if xg_lines == tu_lines
          puts "--- tuist #{scheme} #{cfg} --- identical to xcodegen (#{xg_lines.length} keys)"
        else
          differing += 1
          puts "--- tuist #{scheme} #{cfg} --- DIFFERS from xcodegen"
          puts unified_diff(xg_lines, tu_lines, "xcodegen #{scheme} #{cfg}", "tuist #{scheme} #{cfg}")
        end
        if xg_team_empty != tu_team_empty
          puts "(note: _DEVELOPMENT_TEAM_IS_EMPTY differs between generators for #{scheme} #{cfg} — " \
               "corroboration only; the gated keys above are the verdict)"
        end
      end
    end

    # ── half 2: TEST_HOST / BUNDLE_LOADER (D-60, UL-027) ────────────────
    differing += report_test_bundles("xcodegen", xcodegen_tests, ARTEFACT_CONFIGURATION)
    differing += report_test_bundles("tuist", tuist_tests, ARTEFACT_CONFIGURATION)
    differing += report_test_bundles_across(xcodegen_tests, tuist_tests)

    # ── half 3: the built Info.plist (D-60, UL-030) ─────────────────────
    if build_root
      expectations = xcconfig_expectations
      puts "--- app/Identity.xcconfig, as bin/lib/xcconfig.rb resolves it ---"
      PLIST_EXPECTATIONS.each do |plist_key, xcconfig_key|
        puts "#{xcconfig_key} = #{expectations[plist_key]}   (expected as #{plist_key} in the built bundle)"
      end
      differing += report_plist("xcodegen", xcodegen_plist, expectations)
      differing += report_plist("tuist", tuist_plist, expectations)
      # No separate cross-generator plist comparison: both sides are compared
      # to the same third thing — the tracked xcconfig — so if each agrees with
      # it they agree with each other, and a comparison of the two artefacts to
      # each other would pass while both were wrong.
    end

    pairs = opts[:schemes].length * opts[:configurations].length
    bundles = rows.length
    covered = "#{pairs} scheme x configuration pair(s) across XcodeGen and Tuist; " \
              "#{bundles * 2} unit-test bundle(s) at #{ARTEFACT_CONFIGURATION} " \
              "(TEST_HOST vs the host target's resolved path, BUNDLE_LOADER vs TEST_HOST, " \
              "and TEST_HOST across generators)"
    covered += if build_root
                 "; #{bundles * 2} built Info.plist(s) vs app/Identity.xcconfig on " \
                 "#{PLIST_EXPECTATIONS.length} keys each"
               else
                 "; the built Info.plist was NOT read"
               end

    if differing.zero?
      if build_root
        puts "identity-parity: PARITY OK — #{covered}"
      else
        puts "identity-parity: PARITY OK (build settings only; plist half skipped) — #{covered}"
      end
      0
    else
      suffix = build_root ? "" : " (build settings only; plist half skipped)"
      warn "identity-parity: PARITY FAILED#{suffix} — #{differing} comparison(s) differ; #{covered}"
      1
    end
  ensure
    # Leave the tree in the XcodeGen state on every path once Tuist has
    # overwritten it, because ci/local-check.sh and the lefthook pre-push hook
    # expect XcodeGen's output. Skipped when Tuist never ran: the disk is
    # already in the XcodeGen state (or in whatever state an earlier no_verdict
    # left it, which is at most an XcodeGen project).
    if tuist_ran
      out, err, restore_status = capture(xcodegen_argv, chdir: APP_DIR)
      if restore_status.zero?
        puts "identity-parity: tree left in the XcodeGen state (xcodegen generate re-run, exit 0); " \
             "Tuist's app/#{opts[:project_name]}.xcworkspace and app/Derived/ remain, gitignored"
      else
        warn "identity-parity: final xcodegen generate exited #{restore_status}; the on-disk project is Tuist's\n" \
             "#{(out + err).strip}"
      end
    end
  end

  # A failed restore is not a parity verdict of either kind: the diff above
  # still stands, but exit 0 would tell ci/local-check.sh and the pre-push
  # hook that the project on disk is XcodeGen's when it is Tuist's, and a
  # green exit that leaves the wrong project behind is the stale-project
  # false green from the other direction (03-REVIEW IN-06). So the run ends
  # in the "I don't know" code, naming the tree state and the verdict that
  # was reached. Unreachable when tuist never ran (restore_status stays nil)
  # or when the block exited through no_verdict (already 2).
  unless restore_status.nil? || restore_status.zero?
    warn "identity-parity: no verdict: the final xcodegen generate exited #{restore_status}, so " \
         "app/#{opts[:project_name]}.xcodeproj on disk is Tuist's, not XcodeGen's; the parity verdict " \
         "printed above (#{verdict.zero? ? 'PARITY OK' : 'PARITY FAILED'}) stands, but the tree does not — " \
         "run `cd app && xcodegen generate` before trusting ci/local-check.sh or the pre-push hook"
    return 2
  end
  verdict
end

# Which platform rows halves 2 and 3 run over, and the argv checks that keep a
# restricted run from looking like a full one.
def platform_rows(opts)
  rows = PLATFORMS.select { |row| opts[:schemes].include?(row[:scheme]) }
  if rows.empty?
    no_verdict "no known platform row matches --schemes #{opts[:schemes].join(',')} " \
               "(known: #{PLATFORMS.map { |r| r[:scheme] }.join(', ')}); the TEST_HOST and plist halves " \
               "would have had nothing to run against, and a half that silently ran zero comparisons " \
               "must never be reported as a pass"
  end
  return rows unless opts[:unit_test_targets]

  unless opts[:unit_test_targets].length == rows.length
    die "--unit-test-targets lists #{opts[:unit_test_targets].length} target(s) but #{rows.length} " \
        "platform row(s) matched --schemes; the lists are positional\n#{USAGE}"
  end
  rows.each_with_index.map { |row, i| row.merge(unit_test_target: opts[:unit_test_targets][i]) }
end

def main(argv)
  opts = parse_args(argv)

  # plutil is only required when half 3 runs; a --skip-plist run must not fail
  # for the absence of a binary it never invokes.
  required = REQUIRED_TOOLS + (opts[:skip_plist] ? [] : PLIST_TOOLS)
  missing = required.reject { |t| on_path?(t) }
  no_verdict "required tool(s) not on PATH: #{missing.join(', ')}" unless missing.empty?

  print_versions
  puts "identity-parity: project=#{opts[:project_name]} schemes=#{opts[:schemes].join(',')} " \
       "configurations=#{opts[:configurations].join(',')} skip_generate=#{opts[:skip_generate]} " \
       "skip_plist=#{opts[:skip_plist]} reuse_build=#{opts[:reuse_build] || '(none)'}"

  if opts[:skip_generate]
    warn "identity-parity: --skip-generate is inspect-only: the project on disk was written by ONE " \
         "generator, so there is nothing to compare it against; no parity verdict will be produced"
    project = assert_project_present(opts[:project_name])
    store = extract_all(project, opts[:schemes], opts[:configurations])
    store.each { |(scheme, cfg), (lines, team_empty)| print_block("on-disk #{scheme} #{cfg}", lines, team_empty) }
    no_verdict "--skip-generate compared nothing across generators (inspect-only run of #{project})"
  end

  rows = platform_rows(opts)
  puts "identity-parity: halves 2/3 run at #{ARTEFACT_CONFIGURATION} over " +
       rows.map { |r| "#{r[:unit_test_target]} -> #{r[:host_target]} (scheme #{r[:scheme]})" }.join(", ")

  if opts[:skip_plist]
    warn "identity-parity: ! plist half SKIPPED by flag — verdict covers build settings only"
    return run_parity(opts, rows, nil, false)
  end

  if opts[:reuse_build]
    parent = File.dirname(opts[:reuse_build])
    unless File.directory?(parent)
      no_verdict "--reuse-build #{opts[:reuse_build]}: its parent directory #{parent} does not exist"
    end
    puts "identity-parity: plist half builds into #{opts[:reuse_build]}/<generator> and REUSES any bundle " \
         "already there instead of rebuilding it"
    return run_parity(opts, rows, opts[:reuse_build], true)
  end

  result = nil
  Dir.mktmpdir("identity-parity-") do |dir|
    puts "identity-parity: plist half builds into the scratch tree #{dir}/<generator>, removed at exit"
    result = run_parity(opts, rows, dir, false)
  end
  result
end

exit main(ARGV)
