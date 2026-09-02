#!/usr/bin/env ruby
# frozen_string_literal: true

# Contract test for bin/lib/xcconfig.rb — the ONE xcconfig reader (D-57).
#
# Why this exists: C-17 measured three mutually incompatible readers in this
# repository on 2026-09-02. bin/preflight-identity.rb answers only "is this key
# non-empty" and has no value extractor at all. ci/local-release-check.sh:152's
# capture is ([^[:space:]/]+), which returns BUNDLE_ID correctly and truncates
# DISPLAY_NAME to `Shipkit` and COPYRIGHT to `Copyright` (UL-032).
# fastlane/Fastfile's _fork_config is a .env parser: pointed at an xcconfig it
# would not cut `//`, and it would turn the D-49 comment line
# `// PRODUCT_NAME = $(APP_PRODUCT_NAME) in each manifest` into a bogus key,
# because that comment contains an `=`. UL-031 was the same shape once more —
# a `=[ \t]*\S` match that accepted `BUNDLE_ID = // disabled` as non-empty.
#
# Each of those was a hand-rolled reader that was correct on the happy value
# and wrong on the next one. One body is the fix; this fixture set is what
# makes it a fix rather than a fourth reader.
#
# Every expected value below was OBSERVED, not reasoned about. The fifteen
# semantic rows come from `xcodebuild -showBuildSettings` on Xcode 26.1.1
# (04-RESEARCH.md Q1, probe run 2026-09-02); the `//` rows come from
# evidence/03-SEC-T0306-comment-value-fix.txt. Do NOT "correct" a row here to
# match an implementation — re-measure against Xcode and change both.
#
# Output / exit contract:
#
#   Line                                    | Meaning
#   ----------------------------------------+---------------------------------
#   ✓ <label>                               | one observed row agrees
#   ✗ <label> then expected:/actual:        | the parser disagrees with Xcode
#   FAIL xcconfig - : <LoadError message>   | bin/lib/xcconfig.rb is absent
#   xcconfig_test: N checks, M failures     | always the last line
#
#   Exit 0 = every row agrees. Exit 1 = at least one row disagrees, or the
#   module could not be loaded at all — the RED state this file was born in
#   (04-02-T1-parser-red.txt).
#
# What this test CANNOT see: whether Xcode still behaves this way (the rows are
# a recording of one Xcode version, not a live oracle); SDK-conditional
# `KEY[sdk=…]` assignments, where it asserts only that the base assignment wins,
# which is all a text parser can know; and a real build's `$(inherited)` chain,
# which reaches outside the xcconfig file entirely.
#
# The live-file cases drive app/Identity.xcconfig through the CLI only. They
# never read or print app/Local.xcconfig and never assert on DEVELOPMENT_TEAM.
#
# Run locally under BOTH pinned interpreters:
#   /opt/homebrew/opt/ruby@3.3/bin/ruby test/xcconfig_test.rb
#   /opt/homebrew/opt/ruby@4.0/bin/ruby test/xcconfig_test.rb
# Wired into .github/workflows/review-notes.yml's ordered `review notes` step.
#
# Ruby stdlib only — no gem require anywhere, asserted below against the parser
# itself. review-notes.yml sets `bundler-cache: false` on the strength of that.

require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"

ROOT   = File.expand_path("..", __dir__)
PARSER = File.join(ROOT, "bin", "lib", "xcconfig.rb")
LIVE   = File.join(ROOT, "app", "Identity.xcconfig")

# The four keys app/Identity.xcconfig owns (D-45). Duplicated here on purpose
# rather than read out of the file under test — the idiom from
# test/docs_structure_test.rb:87-91.
LIVE_KEYS = %w[BUNDLE_ID APP_PRODUCT_NAME DISPLAY_NAME COPYRIGHT].freeze

# Clearing the locale is what makes the © case a regression test for UL-012 /
# commit 3b1efb9 rather than a restatement of the fix: with LANG unset Ruby
# defaults Encoding.default_external to US-ASCII, and a parser that read the
# file without an explicit encoding would raise instead of printing.
NO_LOCALE = { "LC_ALL" => nil, "LANG" => nil, "LC_CTYPE" => nil }.freeze

# The module has to load before anything can be asserted about it. A LoadError
# is a FAILURE of this test, not a crash of it — that is the whole of the RED
# observation, and it must be legible in a transcript.
begin
  require_relative "../bin/lib/xcconfig"
rescue LoadError => e
  puts "FAIL xcconfig - : #{e.message}"
  puts "xcconfig_test: 0 checks, 1 failures"
  exit 1
end

@checks   = 0
@failures = 0

def assert_eq(actual, expected, label)
  @checks += 1
  if actual == expected
    puts "  ✓ #{label}"
  else
    puts "  ✗ #{label}"
    puts "    expected: #{expected.inspect}"
    puts "    actual:   #{actual.inspect}"
    @failures += 1
  end
end

# Value-free assertion: used wherever printing the actual would print something
# read out of the live tree.
def assert(condition, label)
  @checks += 1
  if condition
    puts "  ✓ #{label}"
  else
    puts "  ✗ #{label}"
    @failures += 1
  end
end

# A throwaway tree per case. Include cases need real relative paths on disk, so
# a Tempfile per fixture is not enough; block form so nothing survives a
# failure.
def with_tree(files)
  Dir.mktmpdir("xcconfig-test") do |root|
    files.each do |name, body|
      path = File.join(root, name)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, body, encoding: "UTF-8")
    end
    yield root
  end
end

# Drives the CLI as a real subprocess under the interpreter running this test,
# so the exit code observed is the one a shell caller would see.
def cli(*argv, env: {})
  stdout, stderr, status = Open3.capture3({}.merge(env), RbConfig.ruby, PARSER, *argv)
  [stdout, stderr, status.exitstatus]
end

# ─── The fifteen Xcode-observed rows ─────────────────────────────────────────
#
# One file, because that is how Xcode read them during the probe. Interior
# whitespace in PROBE_SPACES is load-bearing; the tabs in PROBE_TAB are written
# as \t so no editor can helpfully expand them.
MAIN = <<~CFG
  // Identity-style header. The next line is the D-49 comment that contains an
  // `=` — a .env parser turns it into a key, and that is the point:
  // PRODUCT_NAME = $(APP_PRODUCT_NAME) in each manifest
  APP_PRODUCT_NAME = ShipkitPipes
  PROBE_REF = $(APP_PRODUCT_NAME) Pro
  PROBE_QUOTED = "quoted value"
  PROBE_EQUALS = a=b
  PROBE_SPACES = two  spaces   kept
  PROBE_NOSPACE=tight
  PROBE_TAB\t=\ttabbed
  PROBE_COND = base
  PROBE_COND[sdk=iphoneos*] = ios-only
  PROBE_INHERIT = $(inherited) extra
  PROBE_EMPTYPAREN = $(UNDEFINED_VAR)x
  PROBE_TRAILING = value // note
  PROBE_DISABLED = // disabled
  PROBE_SLASHSLASH = //
  PROBE_URL = https://example.com/x
  PROBE_SLASH = /
  PROBE_AB = a/b
  PROBE_CYCLE_A = $(PROBE_CYCLE_B)
  PROBE_CYCLE_B = $(PROBE_CYCLE_A)
  #include? "Missing-File.xcconfig"
CFG

puts "xcconfig — the fifteen rows observed on Xcode 26.1.1 (RESEARCH Q1):"

with_tree("Main.xcconfig" => MAIN) do |root|
  f = File.join(root, "Main.xcconfig")
  assert_eq Xcconfig.value(f, "PROBE_REF"),        "ShipkitPipes Pro",   "`$(APP_PRODUCT_NAME) Pro` expands from the resolved set"
  assert_eq Xcconfig.value(f, "PROBE_QUOTED"),     '"quoted value"',     "`\"quoted value\"` keeps its quotes — they are literal characters"
  assert_eq Xcconfig.value(f, "PROBE_EQUALS"),     "a=b",                "`a=b` splits on the FIRST `=` only"
  assert_eq Xcconfig.value(f, "PROBE_SPACES"),     "two  spaces   kept", "interior whitespace preserved, ends trimmed"
  assert_eq Xcconfig.value(f, "PROBE_NOSPACE"),    "tight",              "`KEY=value` with no spaces around `=`"
  assert_eq Xcconfig.value(f, "PROBE_TAB"),        "tabbed",             "tabs are valid whitespace around `=`"
  assert_eq Xcconfig.value(f, "PROBE_COND"),       "base",               "`KEY[sdk=iphoneos*]` is SDK-scoped and ignored; the base assignment wins"
  assert_eq Xcconfig.value(f, "PROBE_INHERIT"),    " extra",             "`$(inherited) extra` → ` extra`, leading space kept"
  assert_eq Xcconfig.value(f, "PROBE_EMPTYPAREN"), "x",                  "`$(UNDEFINED_VAR)x` → `x`, an undefined reference is empty"
  assert_eq Xcconfig.value(f, "PROBE_TRAILING"),   "value",              "`value // note` → `value`, the comment is cut"
  assert_eq Xcconfig.value(f, "PROBE_DISABLED"),   "",                   "`// disabled` → \"\" — UL-031's hole, the whole reason for the cut"
  assert_eq Xcconfig.value(f, "PROBE_SLASHSLASH"), "",                   "a bare `//` → \"\""
  assert_eq Xcconfig.value(f, "PROBE_URL"),        "https:",             "`https://example.com/x` → `https:` — `//` opens a comment at ANY position"
  assert_eq Xcconfig.value(f, "PROBE_SLASH"),      "/",                  "a lone `/` is a real value"
  assert_eq Xcconfig.value(f, "PROBE_AB"),         "a/b",                "a single `/` inside a value is a real value"

  assert_eq Xcconfig.value(f, "NEVER_ASSIGNED"),   nil,                  "a never-assigned key is nil, distinct from \"\""
  assert_eq Xcconfig.value(f, "PRODUCT_NAME"),     nil,                  "a `//` comment line containing `=` defines nothing (D-49 header line)"
  assert_eq Xcconfig.value(f, "APP_PRODUCT_NAME"), "ShipkitPipes",       "`#include? \"Missing-File.xcconfig\"` is silent — the file still resolves"
  assert  Xcconfig.value(f, "PROBE_CYCLE_A").is_a?(String),              "a `$(A)`→`$(B)`→`$(A)` expansion cycle terminates at the depth guard (T-04-08)"
end

# ─── Includes: position, last-wins across the boundary, hard miss, cycle ─────

puts
puts "xcconfig — #include semantics:"

with_tree("Main.xcconfig" => %(K = first\nK = second\n#include? "Inc.xcconfig"\n),
          "Inc.xcconfig"  => %(K = from-include\n)) do |root|
  assert_eq Xcconfig.value(File.join(root, "Main.xcconfig"), "K"), "from-include",
            "last assignment wins ACROSS an include placed after two local assignments"
end

with_tree("Main.xcconfig" => %(#include? "Inc.xcconfig"\nK = after\n),
          "Inc.xcconfig"  => %(K = from-include\n)) do |root|
  assert_eq Xcconfig.value(File.join(root, "Main.xcconfig"), "K"), "after",
            "an include is position-sensitive: placed FIRST, the local assignment after it wins"
end

with_tree("Main.xcconfig" => %(K = kept\n#include "Definitely-Missing.xcconfig"\n)) do |root|
  raised = nil
  begin
    Xcconfig.value(File.join(root, "Main.xcconfig"), "K")
  rescue Xcconfig::MissingInclude => e
    raised = e
  end
  assert !raised.nil?, "a hard `#include` of a missing file raises Xcconfig::MissingInclude, not a silent empty"
  assert raised && raised.message.include?("Definitely-Missing.xcconfig"),
         "the MissingInclude message names the include that could not be found"
end

with_tree("A.xcconfig" => %(#include "B.xcconfig"\n),
          "B.xcconfig" => %(#include "A.xcconfig"\n)) do |root|
  raised = nil
  begin
    Xcconfig.value(File.join(root, "A.xcconfig"), "K")
  rescue Xcconfig::MissingInclude => e
    raised = e
  end
  assert raised && raised.message.include?("cycle"),
         "an include cycle (A→B→A) raises MissingInclude naming a cycle (T-04-07)"
end

# ─── CLI contract ────────────────────────────────────────────────────────────

puts
puts "xcconfig — CLI contract (exit 0 value / exit 3 undefined-or-empty / exit 2 usage):"

with_tree("Main.xcconfig" => MAIN) do |root|
  f = File.join(root, "Main.xcconfig")

  out, _err, code = cli(f, "PROBE_REF")
  assert_eq [out, code], ["ShipkitPipes Pro\n", 0], "CLI prints the resolved value and exits 0"

  _out, err, code = cli(f, "NOPE")
  assert_eq code, 3, "CLI exits 3 on a key that was never assigned"
  assert err.include?("NOPE") && err.include?("undefined"), "CLI stderr names the key and says `undefined`"

  _out, err, code = cli(f, "PROBE_DISABLED")
  assert_eq code, 3, "CLI exits 3 on `// disabled` — the comment-only value is empty, not a value"
  assert err.include?("PROBE_DISABLED") && err.include?("empty"), "CLI stderr names the key and says `empty`"
end

with_tree("Only.xcconfig" => %(K = $(UNDEFINED)\n)) do |root|
  _out, err, code = cli(File.join(root, "Only.xcconfig"), "K")
  assert_eq code, 3, "CLI exits 3 when the value is only `$(UNDEFINED)` — assigned, resolves to nothing"
  assert err.include?("K") && err.include?("empty"), "the `$(UNDEFINED)`-only failure is reported as `empty`, not `undefined`"
end

with_tree("Main.xcconfig" => %(K = kept\n#include "Definitely-Missing.xcconfig"\n)) do |root|
  _out, err, code = cli(File.join(root, "Main.xcconfig"), "K")
  assert code != 0 && code != 3, "CLI on a hard-include miss exits non-zero and NOT 3 — it is an error, not an empty value"
  assert err.include?("MissingInclude") && err.include?("Definitely-Missing.xcconfig"),
         "the CLI propagates a NAMED MissingInclude naming the file"
end

_out, err, code = cli(LIVE)
assert_eq code, 2, "CLI with fewer than two arguments exits 2 (usage), never 0"
assert err.match?(/usage/i), "the usage message says `usage`"

# ─── The live tracked file, through the CLI only ─────────────────────────────

puts
puts "xcconfig — app/Identity.xcconfig, read through the CLI (never Local.xcconfig):"

out, _err, code = cli(LIVE, "BUNDLE_ID")
assert_eq [out.chomp, code], ["com.indiagram.shipkitpipes.ios", 0], "the live BUNDLE_ID resolves and exits 0"

LIVE_KEYS.each do |key|
  out, _err, code = cli(LIVE, key)
  assert code.zero? && !out.chomp.empty?, "the live #{key} exits 0 with a non-empty value"
end

out, _err, code = cli(LIVE, "COPYRIGHT", env: NO_LOCALE)
assert code.zero? && out.b.include?("\xC2\xA9".b),
       "COPYRIGHT keeps its © (bytes c2 a9) with LC_ALL/LANG/LC_CTYPE cleared (UL-012 / 3b1efb9)"

_out, err, code = cli(LIVE, "DEFINITELY_NOT_A_KEY")
assert_eq code, 3, "an undefined key in the live file exits 3"
assert err.include?("DEFINITELY_NOT_A_KEY"), "the live-file failure names the key"

# ─── The stdlib-only promise review-notes.yml:77 makes on this file's behalf ──

puts
puts "xcconfig — dependency discipline:"

assert File.file?(PARSER), "bin/lib/xcconfig.rb exists at the path every consumer will name"
assert_eq File.read(PARSER, encoding: "UTF-8").lines.grep(/\A\s*require\b/).map(&:strip), [],
          "bin/lib/xcconfig.rb has ZERO require lines — fastlane/Appfile `load`s it and bundler-cache is false"

puts
puts "xcconfig_test: #{@checks} checks, #{@failures} failures"
exit(@failures.zero? ? 0 : 1)
