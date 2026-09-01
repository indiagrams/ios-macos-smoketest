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
#      so "the file exists" is not a check — every required variable has to be
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
# where <group> is G1..G5 and <path> is the file the assertion is about, or a
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
# test that read its file list out of tools/preflight-identity.rb, or its
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
# Ruby core only. No `require` of any kind — not even stdlib — because the
# `review notes` job runs with `bundler-cache: false` on the stated basis that
# the generator and both suites are stdlib-only, and the plan's verify asserts
# zero require lines. Every shell-out is an explicit argv array, never a shell
# string. There is no broad rescue anywhere in this file.

ROOT = File.expand_path("..", __dir__)

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

# ─── G1 / G5 vocabulary — the tracked schema and the gitignored value ────────
IDENTITY_XCCONFIG = "app/Identity.xcconfig"
LOCAL_XCCONFIG    = "app/Local.xcconfig"
REQUIRED_VARS     = %w[BUNDLE_ID APP_PRODUCT_NAME DISPLAY_NAME COPYRIGHT].freeze

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
PREFLIGHT             = "tools/preflight-identity.rb"
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

identity_text = identity_exists ? read_utf8(IDENTITY_XCCONFIG) : ""
REQUIRED_VARS.each do |key|
  # Anchored, non-empty-value regex (tools/gen-review-notes.rb:223). The
  # trailing \S is load-bearing: `BUNDLE_ID =` with nothing after the equals
  # sign fails here, which is exactly the case Xcode silently treats as "".
  assert identity_text.match?(/^[ \t]*#{Regexp.escape(key)}[ \t]*=[ \t]*\S/),
         "G1", IDENTITY_XCCONFIG, "defines #{key} with a non-empty value"
end

# ─── G2: the five criterion-1 files carry no SmokeApp literal ────────────────

puts
puts "G2 — criterion 1: no `#{FORBIDDEN_LITERAL}` literal in the five named files:"

CRITERION_ONE_FILES.each do |rel|
  unless File.exist?(File.join(ROOT, rel))
    assert false, "G2", rel, "file does not exist, so it cannot be asserted literal-free"
    next
  end
  hits = line_numbers(read_utf8(rel)) { |line| line.include?(FORBIDDEN_LITERAL) }
  assert hits.empty?, "G2", rel,
         "contains no `#{FORBIDDEN_LITERAL}` literal" \
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
scan_out, scan_exit = run(%w[git ls-files -z --] + CACHE_FLAG_SCAN_PATHS)
cache_hits = []
if scan_exit.zero?
  scan_out.split("\0").each do |rel|
    next unless File.file?(File.join(ROOT, rel))

    hits = line_numbers(read_utf8(rel)) { |line| line.scrub("?") =~ CACHE_FLAG }
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

# ─── verdict ─────────────────────────────────────────────────────────────────

puts
if @failures.zero?
  puts "All #{@checks} identity assertions passed."
  exit 0
else
  puts "#{@failures} of #{@checks} identity assertion(s) failed."
  exit 1
end
