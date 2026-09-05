#!/usr/bin/env ruby
# frozen_string_literal: true

# Durable identity guard for the fork's build identity (IDENT-01, IDENT-07,
# IDENT-08, IDENT-09; ROADMAP Phase 3 criteria 1 and 4).
#
# Why this exists: three specific defects, each observed in this repository
# rather than imagined.
#
#   1. Fork identity was a literal scattered across tracked files. On the state
#      this test was first run against (main @ 6a93204), the string `SmokeApp`
#      appeared at ci/local-check.sh:68-97, ci/local-release-check.sh:11-477,
#      fastlane/Snapfile:23-24, fastlane/MacSnapfile:9-10 and .gitignore:18-19.
#      A rename that misses one of those files leaves CI building a project the
#      manifests no longer generate, and nothing fails until a release does.
#   2. The Team ID's old mechanism wrote the real value into tracked manifests
#      on its SUCCESS path (C-13): `DEVELOPMENT_TEAM: "TEAM_ID_PLACEHOLDER"` sits
#      in app/project.yml and app/Project.swift, and bin/rename.sh Step H
#      substitutes the real team into those tracked files. Success meant the
#      Team ID was one `git add` away from a public repository.
#   3. A missing key inside a PRESENT xcconfig exits 0 and builds green with an
#      empty CFBundleIdentifier (RESEARCH Pitfall 1). `BUNDLE_ID =` with nothing
#      after the equals sign is exactly what Xcode treats as the empty string,
#      and so is `BUNDLE_ID = // disabled` (`//` opens a comment; T-03-06), so
#      "the file exists" is not a check — every required variable has to be
#      asserted non-empty, one assertion per variable so the message names it.
#
# This project's dominant defect is a check that structurally cannot fail —
# sixteen instances in Phase 2, three more caught in Phase 3's own plans before
# execution — so every assertion below has a fixture that makes it go red, and
# this file was observed RED on unmodified HEAD before anything it checks was
# changed. A test written after the rename would pass immediately and prove
# nothing. The observation is recorded in the Phase 3 evidence directory and
# in 03-01-SUMMARY.md.
#
# Failure-line contract (five later negative controls grep for it — do not
# change the shape): every failed assertion prints ONE line, no leading
# whitespace, of the form
#
#     FAIL <group> <path>: <message>
#
# where <group> is G1..G8 and <path> is the file the assertion is about, or a
# single `-` when the assertion is not file-scoped (the G4 cache-flag sweep and
# the G3 path-scoped git-grep sweep).
#
# Grep-gate hygiene — read before adding an assertion:
#   The vocabulary this file checks for (`SmokeApp`, the Team ID, the
#   placeholder) is discussed in prose all over this repository — CHANGELOG.md,
#   AGENTS.md, docs/UPSTREAM-LEDGER.md and the comments in this very file all
#   legitimately contain `SmokeApp`. A repo-wide grep would therefore either
#   need a self-exclusion list (which is where the hole gets drilled) or report
#   a meaningless number. Every assertion below reads an EXPLICIT, frozen list
#   of files. This test is deliberately NOT in that list, so no self-exclusion
#   is needed and no hole can be drilled here.
#
# Every constant below is duplicated deliberately rather than derived from the
# artifact under test (the idiom from test/docs_structure_test.rb:87-91): a
# test that read its file list out of bin/preflight-identity.rb, or its
# variable list out of app/Identity.xcconfig, would accept whatever that file
# happened to say, which is not a test.
#
# Runnable locally, from the repository root or from test/:
#   ruby test/identity_test.rb
#
# Run it under BOTH pinned interpreters — Phase 2 found a real bug visible only
# under the pinned 3.3, and on this machine ambient `ruby` IS 3.3, so the
# second path must be spelled out:
#   /opt/homebrew/opt/ruby@3.3/bin/ruby test/identity_test.rb
#   /opt/homebrew/opt/ruby@4.0/bin/ruby test/identity_test.rb
#
# Ruby core only. Exactly ONE `require`-family line — `require_relative
# "../bin/lib/xcconfig"`, a relative load of a file in this repository that
# itself has zero `require` lines, not even a stdlib one (test/xcconfig_test.rb
# asserts that, so it cannot rot). Nothing outside Ruby core is loaded on any
# path, which is the basis for the `review notes` job's `bundler-cache: false`.
# Every shell-out is an explicit argv array, never a shell string. There is no
# broad rescue anywhere in this file.

ROOT = File.expand_path("..", __dir__)

# The xcconfig questions below are asked through the SAME parser the gate uses
# (D-57), not through a private copy of its predicate. Until 04-03 this file
# carried a `defines_non_empty?` that was byte-identical to
# bin/preflight-identity.rb's by design, with a comment telling the next reader
# to keep them so — which is a guard that goes green whenever the gate is wrong
# in the same way, and is the shape that produced UL-031 (both bodies shared the
# `\S` regex and passed together on an identity Xcode resolved to nothing).
# INDEPENDENCE NOW COMES FROM ELSEWHERE, and this is the load-bearing sentence:
# test/xcconfig_test.rb pins the parser against 52 fixtures whose expected
# values were OBSERVED with `xcodebuild -showBuildSettings` on Xcode 26.1.1, not
# derived from any reader in this tree. A second hand-rolled predicate here
# would not have been a second opinion; the Xcode probe is.
require_relative "../bin/lib/xcconfig"

# ─── G2 vocabulary — ROADMAP criterion 1's explicit file list ────────────────
# Five files, in this order, asserted SEPARATELY: one reintroduction proves one
# branch, not five.
CRITERION_ONE_FILES = %w[
  ci/local-check.sh
  ci/local-release-check.sh
  fastlane/Snapfile
  fastlane/MacSnapfile
  .gitignore
].freeze
FORBIDDEN_LITERAL = "SmokeApp"
# Matched case-insensitively: the template's other spelling is the placeholder
# bundle id `com.indiagram.smokeapp`, which a case-sensitive `include?` ticked
# straight past (03-REVIEW IN-05 — observed passing 24/24 with that string
# appended to .gitignore before this was widened). None of the five files
# carries the lowercase form today; this stops one arriving unnoticed.

# ─── G1 / G5 vocabulary — the tracked schema and the gitignored value ────────
IDENTITY_XCCONFIG = "app/Identity.xcconfig"
LOCAL_XCCONFIG    = "app/Local.xcconfig"
REQUIRED_VARS     = %w[BUNDLE_ID APP_PRODUCT_NAME DISPLAY_NAME COPYRIGHT].freeze

# ─── G6 / G7 vocabulary — the two store-metadata files generated from the ────
# ─── identity config ─────────────────────────────────────────────────────────
#
# Both files are GENERATED from app/Identity.xcconfig by
# Bootstrap::StoreMetadataGenerated (D-74, A-07): copyright.txt from COPYRIGHT,
# name.txt from ASC_APP_NAME when it is set and from DISPLAY_NAME otherwise.
# Until that step existed, bin/rename.sh was the only writer of either file and
# Phase 5 retires it. (This paragraph replaced "Nothing generates one from the
# other", which was true when G6 was written and stopped being true with A-07.)
#
# A generator upstream of a tracked file is NOT what makes the tracked file
# correct, which is why these two groups did not go away when the generator
# arrived: nothing re-runs the generator on a hand edit, `deliver` uploads what
# is on disk, and a tracked generated file drifts the moment anyone touches it.
# These groups are the CI-side guard that neither copy has been edited away from
# its source.
#
# What each one costs if it drifts:
#   copyright.txt — D-51: the organisation name must match Apple's enrollment
#     record character for character, in the binary AND on the listing. COPYRIGHT
#     reaches the built plists from Identity.xcconfig; the listing's copyright is
#     what `deliver` reads from this file (Fastfile `copyright:`, overridable by
#     ASC_COPYRIGHT).
#   name.txt — UL-044: a stale display name shipped here through three phases of
#     green gates because nothing ever compared the two. It has NO override at
#     all — fastlane/Fastfile:678 reads it with a bare File.read, there is no
#     Deliverfile, and build_asc_metadata_args does not carry `name` — so
#     whatever this file holds simply IS the App Store listing name.
COPYRIGHT_TXT     = "fastlane/metadata/copyright.txt"
NAME_TXT          = "fastlane/metadata/en-US/name.txt"

# ─── G8 vocabulary — the app's own user-visible copy ─────────────────────────
#
# Two files, and BOTH of them, because they carry the SAME string: the Swift
# source as a literal, and the string catalog as the KEY and its `en` value. An
# assertion over the Swift surface alone goes green while a retired instruction
# is still shipping in the catalog — measured, not imagined: A-08's original
# wording named only the Swift file, and the catalog was found by grepping for
# the string rather than by reading the plan.
#
# AMENDED 2026-09-05 (plan 06-14, D-66 / PRIV-06). Phase 6 replaced the
# placeholder root view wholesale and DELETED it, together with the two template
# rows it resolved from the catalog — which is precisely what the previous
# wording of this comment said was coming. The three assertion shapes below are
# UNCHANGED. Only the POPULATION and the POSITIVE ANCHOR moved, which is the
# least an amendment can change and still be honest:
#
#   * the Swift member is now app/Shared/Views/OutputAccessory.swift, the file
#     that renders the add-step control and labels it;
#   * the anchor is now `Add step`. It was chosen because it is the phase's
#     primary call to action, it is on every output on every surface, and its
#     absence would mean APP-08 had regressed — so an anchor that goes missing
#     is a real regression rather than a copy edit. It also lands in the catalog
#     as BOTH the key and its `en` value, so the count below survives at 2,
#     unchanged;
#   * RETIRED_SCRIPT and the negative half are untouched, now applied over the
#     new population. "The shipped app does not tell its user to run a retired
#     script" is exactly as valid over the new UI as it was over the old one.
#
# SCOPE, stated so it is not widened by the next reader. This group asserts the
# absence of ONE retired command and the presence of ONE anchor. It is
# deliberately NOT a check on app-facing prose in general: that population is
# criterion 7's (tools/check-contamination.rb, IDENT-15) over tracked files, and
# criterion 6's (the rendered-string sweep, D-93/D-94) over what a running app
# puts on screen. Three populations on purpose, and this is the narrowest.
APP_COPY_FILES  = %w[app/Shared/Views/OutputAccessory.swift app/Shared/Localizable.xcstrings].freeze
# The retired script, spelled without its `bin/` prefix so the assertion also
# catches a bare `rename.sh --help` written from inside bin/.
RETIRED_SCRIPT  = "rename.sh"
# The POSITIVE half. Without it, deleting the label outright — or emptying the
# catalog — satisfies the negative half completely, which is the shape 05-11
# recorded as "a scope assertion needs a positive half or an empty file satisfies
# it". Spelled here as a frozen constant rather than read out of either file.
APP_COPY_STRING = "Add step"
# In the catalog the same string is BOTH the key and its `en` value, so it must
# appear exactly twice. The pairing is asserted as a COUNT rather than by parsing
# JSON on purpose: this file carries exactly ONE require-family line
# (require_relative "../bin/lib/xcconfig"), which is what the `review notes` job's
# bundler-cache: false rests on, and `require "json"` would be a second.
#
# The Swift member must carry the anchor exactly ONCE, and that exactness is the
# point rather than an accident: a prose mention of the anchor in a comment in
# that file inflates the count just as surely as a second rendered label would.
# Plan 06-14 reworded one such comment rather than relaxing this half to `>= 1`
# — a file swept by a content gate must not spell the gate's own subject.
APP_COPY_CATALOG_OCCURRENCES = 2

# ─── G3 vocabulary — the Team ID and where it must never appear ──────────────
# TEAM_ID is the literal VALUE. The assertions below use the value, never the
# seven-character string "TEAM_ID" itself — `TEAM_ID_PLACEHOLDER` contains that
# string on HEAD and is exactly the placeholder this group must tolerate.
TEAM_ID            = "G5H628C6WR"
# Any Apple Team ID is ten upper-case alphanumerics. `TEAM_ID_PLACEHOLDER` does
# NOT match this: `_` is a word character, so there is no \b before `PLACEHOLDER`
# and no ten-character run inside it has a boundary on both sides. That is why
# this group is green on HEAD and why it is the group whose both-directions
# control runs in 03-01 Task 2 (a real Team ID in each manifest, and an invented
# ten-character token, each driven red and restored).
TEAM_ID_SHAPE      = /\b[A-Z0-9]{10}\b/
BUILD_CONFIG_FILES = %w[app/project.yml app/Project.swift].freeze
# The path-scoped sweep for the literal value. Six occurrences OUTSIDE these
# paths survive by design under D-48 / C-11 and are deliberately not swept:
# docs/APPLE-ACCOUNT-STATE.md (the Against column of every measurement triple),
# docs/PRODUCT-IDENTITY.md, tools/asc-probe.rb (EXPECTED_TEAM, the C-05 guard),
# test/asc_probe_test.rb, test/docs_structure_test.rb, CHANGELOG.md.
TEAM_ID_SWEEP_PATHS = %w[app/ ci/ fastlane/ .github/ Makefile].freeze

# ─── G4 vocabulary — the generation gate and the flag that bypasses it ───────
PROJECT_YML           = "app/project.yml"
PREFLIGHT             = "bin/preflight-identity.rb"
# XcodeGen's own documentation: preGenCommand does not run when the project is
# not regenerated because nothing changed under the cache. A gate one flag away
# from being bypassed needs an assertion that nobody passes that flag.
CACHE_FLAG            = /--use-cache|xcodegen[^|]*-c\b/
CACHE_FLAG_SCAN_PATHS = %w[Makefile ci/ .github/workflows/].freeze

# ─── harness (test/docs_structure_test.rb:167-208, adapted to the one-line
# ─── FAIL contract above) ─────────────────────────────────────────────────────

@failures = 0
@checks   = 0

def assert(condition, group, path, label)
  @checks += 1
  if condition
    puts "  ✓ #{group} #{path}: #{label}"
  else
    # One line, always: a message that put the group on one line and the path
    # on another would make every control that greps `^FAIL G3 app/project.yml`
    # vacuous, which is the defect this whole phase exists to avoid.
    puts "FAIL #{group} #{path}: #{label.to_s.gsub(/\s*\n\s*/, ' ')}"
    @failures += 1
  end
end

# UTF-8 pinned, never inherited. app/Identity.xcconfig carries `©` (U+00A9) in
# COPYRIGHT and app/project.yml already does at its copyright lines; with LANG
# unset Ruby defaults Encoding.default_external to US-ASCII and a non-ASCII
# byte raises ArgumentError out of a regex match instead of exiting 0 or 1.
# Commit 3b1efb9 is this repository's own instance of that defect (UL-012).
def read_utf8(relative)
  File.read(File.join(ROOT, relative), encoding: "UTF-8")
end

# Runs an argv array from the repository root, returning [combined stdout+stderr,
# exit status]. Argv array only — a shell string would let a path with a space
# or a metacharacter change what is executed.
def run(argv)
  out = IO.popen(argv, "r", err: [:child, :out], chdir: ROOT, &:read)
  [out.to_s, $?.exitstatus]
end

# 1-based line numbers in `text` for which the block is true.
def line_numbers(text)
  text.lines.each_with_index.filter_map { |line, i| i + 1 if yield(line) }
end

# ─── G1: app/Identity.xcconfig exists, is tracked, defines four variables ────

puts "G1 — #{IDENTITY_XCCONFIG} is the tracked source of truth (D-45):"

identity_exists = File.exist?(File.join(ROOT, IDENTITY_XCCONFIG))
assert identity_exists, "G1", IDENTITY_XCCONFIG, "exists"

tracked_out, tracked_exit = run(%w[git ls-files --] + [IDENTITY_XCCONFIG])
assert tracked_exit.zero? && !tracked_out.strip.empty?,
       "G1", IDENTITY_XCCONFIG,
       "is tracked (git ls-files names it; exit=#{tracked_exit}, output=#{tracked_out.strip.inspect})"

# The parser takes a PATH, not text: it follows `#include` relative to the
# including file, which is the whole reason it is a parser and not a regex. The
# `identity_exists` guard is not a second predicate — without it a missing file
# would raise Errno::ENOENT here and replace every remaining FAIL line with a
# backtrace, and the assertion directly above has already reported that defect.
identity_path = File.join(ROOT, IDENTITY_XCCONFIG)
REQUIRED_VARS.each do |key|
  value = identity_exists ? Xcconfig.value(identity_path, key) : nil
  assert !value.nil? && !value.empty?,
         "G1", IDENTITY_XCCONFIG, "defines #{key} with a non-empty value (after its // comment, if any, is cut off)"
end

# ─── G2: the five criterion-1 files carry no SmokeApp literal ────────────────

puts
puts "G2 — criterion 1: no `#{FORBIDDEN_LITERAL}` literal, in any letter case, in the five named files:"

CRITERION_ONE_FILES.each do |rel|
  unless File.exist?(File.join(ROOT, rel))
    assert false, "G2", rel, "file does not exist, so it cannot be asserted literal-free"
    next
  end
  hits = line_numbers(read_utf8(rel)) { |line| line.downcase.include?(FORBIDDEN_LITERAL.downcase) }
  assert hits.empty?, "G2", rel,
         "contains no `#{FORBIDDEN_LITERAL}` literal in any letter case" \
         "#{hits.empty? ? '' : " — found at line(s) #{hits.join(', ')}"}"
end

# ─── G3: no Team ID in tracked build / signing configuration (IDENT-08) ──────

puts
puts "G3 — criterion 4: the Team ID appears in no tracked build or signing config:"

BUILD_CONFIG_FILES.each do |rel|
  unless File.exist?(File.join(ROOT, rel))
    assert false, "G3", rel, "file does not exist, so it cannot be asserted Team-ID-free"
    next
  end
  text = read_utf8(rel)

  literal_hits = line_numbers(text) { |line| line.include?(TEAM_ID) }
  assert literal_hits.empty?, "G3", rel,
         "does not contain the literal Team ID #{TEAM_ID}" \
         "#{literal_hits.empty? ? '' : " — found at line(s) #{literal_hits.join(', ')}"}"

  shape_hits = text.lines.each_with_index.filter_map do |line, i|
    m = line.match(TEAM_ID_SHAPE)
    "#{i + 1}:#{m[0]}" if m
  end
  assert shape_hits.empty?, "G3", rel,
         "contains no ten-character Team-ID-shaped token (#{TEAM_ID_SHAPE.source})" \
         "#{shape_hits.empty? ? '' : " — found #{shape_hits.join(', ')}"}"
end

# git grep exits 1 when nothing matched, 0 on a match, 128 on error — only the
# "nothing matched" outcome is a pass; an error is not evidence of absence.
sweep_out, sweep_exit = run(%w[git grep -n -F -e] + [TEAM_ID, "--"] + TEAM_ID_SWEEP_PATHS)
assert sweep_exit == 1 && sweep_out.strip.empty?, "G3", "-",
       "git grep finds no #{TEAM_ID} under #{TEAM_ID_SWEEP_PATHS.join(' ')} " \
       "(exit=#{sweep_exit})#{sweep_out.strip.empty? ? '' : " — #{sweep_out.strip}"}"

# ─── G4: the generation gate is wired and cannot be cache-skipped (IDENT-09) ─

puts
puts "G4 — criterion 5: options.preGenCommand runs the preflight, and no caller bypasses it:"

# Extract the top-level `options:` block of project.yml (up to the next
# top-level key), then the preGenCommand value inside it. Plain-text
# extraction on purpose: no YAML library (Ruby core only), and section
# extraction rather than a whole-file grep so a `preGenCommand` mentioned in a
# comment elsewhere cannot satisfy this.
def pre_gen_command(yml_text)
  lines = yml_text.lines
  start = lines.index { |l| l =~ /\Aoptions:[ \t]*(#.*)?$/ }
  return nil if start.nil?

  block = lines[(start + 1)..].take_while { |l| l =~ /\A([ \t]+\S|[ \t]*$)/ }
  idx = block.index { |l| l =~ /\A[ \t]+preGenCommand:/ }
  return nil if idx.nil?

  value = block[idx].sub(/\A[ \t]+preGenCommand:[ \t]*/, "").rstrip
  if value =~ /\A[|>][-+]?[ \t]*$/
    indent = block[idx][/\A[ \t]+/].length
    value = block[(idx + 1)..]
            .take_while { |l| l =~ /\A[ \t]*$/ || l[/\A[ \t]*/].length > indent }
            .map(&:strip).reject(&:empty?).join(" ")
  end
  value.sub(/\A(["'])(.*)\1\z/, '\2')
end

yml_text = File.exist?(File.join(ROOT, PROJECT_YML)) ? read_utf8(PROJECT_YML) : ""
pregen   = pre_gen_command(yml_text)

assert !pregen.nil?, "G4", PROJECT_YML, "declares options.preGenCommand"
assert !pregen.nil? && pregen.include?(PREFLIGHT), "G4", PROJECT_YML,
       "options.preGenCommand invokes #{PREFLIGHT}#{pregen.nil? ? '' : " (observed #{pregen.inspect})"}"
# The preflight accepts --config for its own fixtures; letting the generation
# hook redirect the gate at a fixture would be a hole. Requiring the command to
# be present here too keeps this from being vacuously true on a manifest with
# no preGenCommand at all.
assert !pregen.nil? && !pregen.include?("--config"), "G4", PROJECT_YML,
       "options.preGenCommand passes no --config flag#{pregen.nil? ? '' : " (observed #{pregen.inspect})"}"

# The cache-flag sweep over every tracked file under the three caller surfaces.
# Comment-only lines (`#` first) are not callers and are skipped: upstream's
# ci/check-identity.sh, adopted as-is in Phase 4, EXPLAINS in its header that
# preGenCommand is skipped under `xcodegen --use-cache`, which is this very
# assertion's reason for existing, not a violation of it. A flag on a live
# command line still counts, wherever on the line it sits.
scan_out, scan_exit = run(%w[git ls-files -z --] + CACHE_FLAG_SCAN_PATHS)
cache_hits = []
if scan_exit.zero?
  scan_out.split("\0").each do |rel|
    next unless File.file?(File.join(ROOT, rel))

    hits = line_numbers(read_utf8(rel)) { |line| line.scrub("?") !~ /\A[ \t]*#/ && line.scrub("?") =~ CACHE_FLAG }
    hits.each { |n| cache_hits << "#{rel}:#{n}" }
  end
end
assert scan_exit.zero? && cache_hits.empty?, "G4", "-",
       "no caller under #{CACHE_FLAG_SCAN_PATHS.join(' ')} passes XcodeGen's cache flag " \
       "(--use-cache or -c), because preGenCommand is skipped under the cache" \
       "#{scan_exit.zero? ? '' : " — git ls-files exit=#{scan_exit}"}" \
       "#{cache_hits.empty? ? '' : " — found at #{cache_hits.join(', ')}"}"

# ─── G5: Local.xcconfig gitignored, Identity.xcconfig not (IDENT-08) ─────────

puts
puts "G5 — the tracked-schema / gitignored-value split:"

# git check-ignore -q: 0 = ignored, 1 = not ignored, 128 = fatal. Each side
# asserts the exact code it needs; a 128 is not evidence for either.
_, local_ignored = run(%w[git check-ignore -q --] + [LOCAL_XCCONFIG])
assert local_ignored.zero?, "G5", LOCAL_XCCONFIG,
       "is gitignored (git check-ignore -q must exit 0; observed #{local_ignored})"

_, identity_ignored = run(%w[git check-ignore -q --] + [IDENTITY_XCCONFIG])
assert identity_ignored == 1, "G5", IDENTITY_XCCONFIG,
       "is NOT gitignored (git check-ignore -q must exit 1; observed #{identity_ignored})"

# ─── G6: the store-facing copyright equals the build-facing one (D-51) ───────

puts
puts "G6 — #{COPYRIGHT_TXT} carries the same string as COPYRIGHT in #{IDENTITY_XCCONFIG}:"

# Two tracked copies of one value, and since A-07 a generator between them
# (03-REVIEW WR-07 asked for this comparison when there was none): the generator
# closes the gap only for a tree somebody ran it on, and an edit to either copy
# afterwards would still silently make the App Store listing and the binary's
# About box disagree. D-51's character-for-character match with the enrollment
# name is only as good as the copy nobody re-checked, which is this one.
copyright_txt_exists = File.exist?(File.join(ROOT, COPYRIGHT_TXT))
assert copyright_txt_exists, "G6", COPYRIGHT_TXT, "exists"

xcconfig_copyright = identity_exists ? Xcconfig.value(identity_path, "COPYRIGHT") : nil
listing_copyright  = copyright_txt_exists ? read_utf8(COPYRIGHT_TXT).strip : nil
assert !xcconfig_copyright.nil? && xcconfig_copyright == listing_copyright,
       "G6", COPYRIGHT_TXT,
       "equals COPYRIGHT in #{IDENTITY_XCCONFIG} after its // comment is cut off " \
       "(xcconfig=#{xcconfig_copyright.inspect}, file=#{listing_copyright.inspect})"

# ─── G7: the App Store listing name equals the on-device one (UL-044) ────────

puts
puts "G7 — #{NAME_TXT} carries the same string as DISPLAY_NAME in #{IDENTITY_XCCONFIG}:"

# THIS IS THE ONE POINT WHERE CI CAN SEE THE UL-044 CLASS, because both sides are
# TRACKED. Every other place that class hides — a stale name in prose, in a
# workflow default, in a gitignored config — is invisible to a PR job by
# construction, and is deliberately left to Phase 6 (IDENT-15 / UL-045) rather
# than half-attempted here.
#
# WHAT THIS GROUP DOES NOT CHECK, stated rather than implied. The generator
# writes ASC_APP_NAME when it is set and DISPLAY_NAME otherwise; ASC_APP_NAME
# lives in gitignored .bootstrap.env, so a clone structurally cannot know which
# branch a given fork takes. This group asserts the ASC_APP_NAME-UNSET case: the
# default, the shipped configuration, and the only one derivable from a
# checkout. The name.txt-to-ASC_APP_NAME comparison is doctor-tier — it belongs
# to Bootstrap::StoreMetadataGenerated#check, on a machine that has the config —
# and no attempt is made to reproduce it here. Reading .bootstrap.env from this
# file would make the group pass or fail on ambient machine state, which is the
# defect 05-08 found one plan ago, not a stronger check.
#
# A fork that deliberately sets ASC_APP_NAME to something OTHER than DISPLAY_NAME
# will therefore see this group go red. That is a true statement about that fork
# — its tracked listing name matches nothing a reader of the repository can
# derive — but it is reported here at the wrong severity, so the failure message
# below names that cause explicitly instead of leaving a forker to guess that
# their file is corrupt.
name_txt_exists = File.exist?(File.join(ROOT, NAME_TXT))
assert name_txt_exists, "G7", NAME_TXT, "exists"

xcconfig_display_name = identity_exists ? Xcconfig.value(identity_path, "DISPLAY_NAME") : nil
listing_name          = name_txt_exists ? read_utf8(NAME_TXT).strip : nil
assert !xcconfig_display_name.nil? && xcconfig_display_name == listing_name,
       "G7", NAME_TXT,
       "equals DISPLAY_NAME in #{IDENTITY_XCCONFIG} after its // comment is cut off " \
       "(xcconfig=#{xcconfig_display_name.inspect}, file=#{listing_name.inspect}); " \
       "a mismatch here means either this file was hand-edited away from the " \
       "identity config, or ASC_APP_NAME in .bootstrap.env deliberately differs " \
       "from DISPLAY_NAME, which a clone cannot see"

# ─── G8: the app does not tell its user to run a retired script (A-08) ───────

puts
puts "G8 — no app-facing string names `#{RETIRED_SCRIPT}`, and the anchor string is present:"

APP_COPY_FILES.each do |rel|
  exists = File.exist?(File.join(ROOT, rel))
  assert exists, "G8", rel, "exists"
  next unless exists

  text = read_utf8(rel)
  hits = line_numbers(text) { |line| line.downcase.include?(RETIRED_SCRIPT.downcase) }
  assert hits.empty?, "G8", rel,
         "names no `#{RETIRED_SCRIPT}` — Phase 5 retired that script's identity " \
         "substitution, so an instruction to run it is false in the shipped app " \
         "(offending line(s): #{hits.join(', ')})"
end

# The positive half, one assertion per file so the message names which one moved.
swift_rel = APP_COPY_FILES[0]
if File.exist?(File.join(ROOT, swift_rel))
  swift_hits = read_utf8(swift_rel).scan(APP_COPY_STRING).length
  assert swift_hits == 1, "G8", swift_rel,
         "carries the anchor string exactly once (found #{swift_hits}); without " \
         "this half, deleting the label satisfies the absence check completely, and a " \
         "second hit means this file spells the anchor in prose as well as rendering it"
end

catalog_rel = APP_COPY_FILES[1]
if File.exist?(File.join(ROOT, catalog_rel))
  catalog_hits = read_utf8(catalog_rel).scan(APP_COPY_STRING).length
  assert catalog_hits == APP_COPY_CATALOG_OCCURRENCES, "G8", catalog_rel,
         "carries the anchor string exactly #{APP_COPY_CATALOG_OCCURRENCES} times, " \
         "once as the catalog KEY and once as its `en` value (found #{catalog_hits}); a " \
         "key that stops matching its source string stops resolving, silently"
end

# ─── verdict ─────────────────────────────────────────────────────────────────

puts
if @failures.zero?
  puts "All #{@checks} identity assertions passed."
  exit 0
else
  puts "#{@failures} of #{@checks} identity assertion(s) failed."
  exit 1
end
