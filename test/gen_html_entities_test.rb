#!/usr/bin/env ruby
# frozen_string_literal: true

# Contract test for tools/gen-html-entities.rb and the two TRACKED Swift tables
# it generates (APP-03's data half).
#
# WHY THIS EXISTS, AND WHY IT IS IN RUBY
#
# The entity table's failure mode is SILENT. A packing format whose delimiter is
# also an entity target loses records and still compiles clean -- measured on
# this tree: a ';'/'=' pack parses to 2122 of 2125 with `swiftc -typecheck`
# exiting 0 and emitting no diagnostic at all. Nothing in the Swift toolchain
# notices. A count assertion is the only thing that does.
#
# So the count is asserted HERE, in Ruby, and not only in a Swift unit test. The
# `review notes` job runs on ubuntu-latest with NO XCODE, which means these
# assertions run on every pull request while a Swift test of the same property
# would run only in the macOS matrix. It is also where the `invisible_character`
# regression is caught: the generated tables must be pure ASCII, and that is a
# byte-level property of a tracked file, which is a thing Ruby can see without a
# compiler.
#
# WHAT IT DELIBERATELY DOES NOT DO
#
# It does not re-fetch the WHATWG document. The generator's --check does not
# either; the network is touched once, at generation time, on a developer's
# machine (APP-11). This suite reads two tracked files and shells out to the
# generator's own --check with an argv ARRAY.
#
# It also does not restate the generator's parser. The record and field counts
# below are taken by counting DELIMITERS in the raw source text, which is an
# independent measurement: if the format were ever regenerated with ';' and '='
# the delimiter counts would collapse to zero while the declared recordCount
# stayed at its old value, and that disagreement is the red.
#
# FAILURE-LINE CONTRACT -- do not change the shape. Controls grep it.
# One line per failure, no leading whitespace:
#
#     FAIL <group> <path>: <message>
#
#   H1  both tables exist, and are big enough for the checks below to mean anything
#   H2  each header carries the do-not-hand-edit notice and names its generator
#   H3  neither table contains a byte outside ASCII
#   H4  each file's recordCount is positive, matches its own delimiter count,
#       and the two SUM to the frozen total
#   H5  the three delimiter-colliding entities are present, exactly once, with
#       their exact targets
#   H6  the generator's own front door: --check exits 0, unknown argv exits 1,
#       and there is no destination flag
#
# DEPENDENCIES: Ruby stdlib only (open3, rbconfig). No gem, no framework, no
# rake task -- the `review notes` job runs with bundler-cache disabled.

require "open3"
require "rbconfig"

ROOT      = File.expand_path("..", __dir__)
GENERATOR = "tools/gen-html-entities.rb"
DEST_ROOT = "app/Shared/Engine"
TABLES    = %w[HTMLEntityTableA.swift HTMLEntityTableB.swift].freeze

# Frozen, and the same number the generator freezes: the count of
# semicolon-terminated named references in html.spec.whatwg.org/entities.json,
# measured 2026-09-04 against the 145,897-byte document. A drift here is a
# signal that the spec table changed, not a number to bump.
EXPECTED_RECORDS = 2125

# A floor, not an expectation. Its only job is to stop an EMPTY or truncated
# file satisfying the ASCII and delimiter checks vacuously -- this repository's
# dominant defect class is an assertion that passes because nothing was there.
MIN_TABLE_BYTES = 20_000

# The packed format, RESTATED here rather than imported, so this file is a
# contract and not an echo of the generator's own constants.
FLD = "\\u{2}"
REC = "\\u{1}"

# The three entities whose TARGETS are the characters a ';'/'=' pack would have
# used as delimiters, with the exact scalars each must carry. &equals; and
# &semi; are the records such a pack loses outright; &bne; is the one it can
# keep by accident, because "=" followed by U+20E5 is a single grapheme cluster
# and Swift's Character-based split does not break inside one. Spot-checking
# &bne; alone would therefore report a broken format healthy, which is why all
# three are named and why the counts above exist.
CANARIES = {
  "equals" => [0x3D],
  "semi"   => [0x3B],
  "bne"    => [0x3D, 0x20E5]
}.freeze

@checks   = 0
@failures = 0

def assert(condition, group, path, label)
  @checks += 1
  if condition
    puts "  ok #{group} #{path}: #{label}"
  else
    # One line, always. A message that put the group on one line and the path on
    # another would make every control grepping `^FAIL H4 ...` vacuous.
    puts "FAIL #{group} #{path}: #{label.to_s.gsub(/\s*\n\s*/, ' ')}"
    @failures += 1
  end
end

# Refusing a verdict is not the same as passing. Exit 2, never 0, and always
# with a FAIL line so a control grepping the contract still sees one.
def no_verdict(message)
  puts "FAIL H1 -: cannot run -- #{message}"
  puts
  puts "entity table gate CANNOT RUN: #{message}"
  exit 2
end

def verdict!
  puts
  if @failures.zero?
    puts "All #{@checks} entity-table assertions passed."
    exit 0
  else
    puts "#{@failures} of #{@checks} entity-table assertion(s) failed."
    exit 1
  end
end

# The packed source text of one record, built the way the generator builds it.
def record_text(name, codepoints)
  name + FLD + codepoints.map { |c| format("\\u{%x}", c) }.join + REC
end

# ─── H1: the subjects exist, and are not empty ───────────────────────────────
#
# BEFORE any iteration over their contents. An `each` over an empty collection
# asserts nothing and reports success, and a zero-byte file would satisfy both
# the ASCII check and every `count` below.

no_verdict("#{GENERATOR} is missing from #{ROOT}") unless File.file?(File.join(ROOT, GENERATOR))

assert TABLES.length == 2, "H1", DEST_ROOT,
       "the table enumeration names #{TABLES.length} files (expected 2: #{TABLES.join(', ')}); " \
       "an empty enumeration would make every assertion below vacuous"

sources = {}
TABLES.each do |name|
  rel = File.join(DEST_ROOT, name)
  abs = File.join(ROOT, rel)
  unless File.file?(abs)
    assert false, "H1", rel,
           "the generated table is missing -- regenerate with: ruby #{GENERATOR}"
    next
  end
  # UTF-8 pinned rather than inherited from the locale (UL-048). These files are
  # asserted ASCII-only two groups below, but the READ must not depend on that
  # being true: an unpinned read of a file that had regressed to holding
  # non-ASCII would raise a backtrace where a named refusal belongs.
  text = File.read(abs, encoding: "UTF-8")
  sources[rel] = text
  assert text.bytesize >= MIN_TABLE_BYTES, "H1", rel,
         "the table is #{text.bytesize} bytes (floor #{MIN_TABLE_BYTES}); a truncated or empty " \
         "file would satisfy the ASCII and delimiter checks below while carrying nothing"
end

if sources.length != TABLES.length
  assert false, "H1", DEST_ROOT,
         "only #{sources.length} of #{TABLES.length} tables could be read, so the sum assertion " \
         "in H4 cannot be made at all -- a partial result here is not a partial pass"
  verdict!
end

puts "  .. enumerated #{sources.length} generated table(s), " \
     "#{sources.values.sum(&:bytesize)} bytes total"

# ─── H2: the header says what it is and how to regenerate it ────────────────

sources.each do |rel, text|
  head = text.lines.first(40).join
  assert head.include?("Do not hand-edit"), "H2", rel,
         "the header carries the literal notice 'Do not hand-edit'; without it the next reader " \
         "to spot a wrong entity fixes it in place and the fix dies at the next regeneration"
  assert head.include?(GENERATOR), "H2", rel,
         "the header names #{GENERATOR}, so 'do not hand-edit' is actionable rather than a scold"
end

# ─── H3: pure ASCII ─────────────────────────────────────────────────────────
#
# This is the `invisible_character` regression. 17 entities target invisible or
# format characters (U+200B, U+200C and friends); written as literal characters
# they are 6 errors under `swiftlint --strict`. Asserted here, in the job that
# has no Xcode, so it fails on every pull request rather than only in the macOS
# matrix.

sources.each do |rel, text|
  offending = text.each_byte.with_index.find { |b, _i| b > 0x7F }
  assert offending.nil?, "H3", rel,
         offending ? format("byte offset %d is 0x%02X, outside ASCII; every scalar must be a " \
                            "backslash-u escape or swiftlint --strict reports invisible_character",
                            offending[1], offending[0])
                   : "every byte is ASCII, so no scalar in the table can be an invisible character"
end

# ─── H4: the counts, per file AND summed ────────────────────────────────────
#
# Two separate reads plus the sum, never one number. A union that has stopped
# drawing from one source looks identical to one that never did, and the
# one-record-short case is invisible to every per-file check
# (control=entities-count in the plan's evidence file measured exactly that).

declared = {}
sources.each do |rel, text|
  matches = text.scan(/static let recordCount: Int = (\d+)/)
  assert matches.length == 1, "H4", rel,
         "carries exactly one generated `static let recordCount: Int` (found #{matches.length}); " \
         "zero means nothing to assert and more than one means it is ambiguous which was read"
  next unless matches.length == 1

  count = matches[0][0].to_i
  declared[rel] = count
  assert count.positive?, "H4", rel,
         "declares recordCount #{count}, which is positive; a zero would let the sum below be " \
         "satisfied by one file carrying everything and the other carrying nothing"

  # Independent of the declared number and of the generator's own parser: count
  # the DELIMITERS in the raw source. A table regenerated with ';' and '='
  # collapses these to zero while recordCount keeps its old value.
  assert text.scan(REC).length == count, "H4", rel,
         "holds #{text.scan(REC).length} record delimiters against a declared recordCount of " \
         "#{count}; the packed format is losing records or the delimiter changed"
  assert text.scan(FLD).length == count, "H4", rel,
         "holds #{text.scan(FLD).length} field delimiters against a declared recordCount of " \
         "#{count}; every record carries exactly one"
end

if declared.length == TABLES.length
  total = declared.values.sum
  assert total == EXPECTED_RECORDS, "H4", DEST_ROOT,
         "the two tables declare #{declared.map { |k, v| "#{File.basename(k)}=#{v}" }.join(' + ')} " \
         "= #{total} records, expected #{EXPECTED_RECORDS} -- the count of semicolon-terminated " \
         "named references in html.spec.whatwg.org/entities.json, measured 2026-09-04"
else
  assert false, "H4", DEST_ROOT,
         "only #{declared.length} of #{TABLES.length} tables yielded a recordCount, so the sum " \
         "was not computed; a missing half is not a passing half"
end

# ─── H5: the delimiter-colliding entities, each named ───────────────────────

assert CANARIES.length == 3, "H5", DEST_ROOT,
       "the canary set names #{CANARIES.length} entities (expected 3); an empty set would make " \
       "the loop below iterate nothing and report success"

whole = sources.values.join
CANARIES.each do |name, codepoints|
  wanted = record_text(name, codepoints)
  # Bounded on the left so a longer name ending in the same letters (subne,
  # vsubne, bnequiv) cannot satisfy the assertion on the short one's behalf.
  hits = whole.scan(/(?<![A-Za-z0-9])#{Regexp.escape(wanted)}/).length
  assert hits == 1, "H5", DEST_ROOT,
         "the entity named '#{name}' appears exactly once with its exact target " \
         "#{codepoints.map { |c| format('U+%04X', c) }.join(' ')} (found #{hits}); this is one of " \
         "the three records a ';'-delimited pack loses or silently corrupts"
end

# ─── H6: the generator's own front door ─────────────────────────────────────
#
# argv ARRAY through Open3.capture3, never a shell string: quoting has silently
# changed what a command meant in this project before.

def run_generator(*args)
  out, err, status = Open3.capture3(RbConfig.ruby, File.join(ROOT, GENERATOR), *args, chdir: ROOT)
  [out.to_s, err.to_s, status.exitstatus]
end

check_out, check_err, check_code = run_generator("--check")
assert check_code.zero?, "H6", GENERATOR,
       "--check exits 0 on the committed tree (got #{check_code}; stdout: #{check_out.strip}; " \
       "stderr: #{check_err.strip})"
assert check_out.include?("records=#{EXPECTED_RECORDS}"), "H6", GENERATOR,
       "--check prints a labelled summary naming records=#{EXPECTED_RECORDS}, so a green run " \
       "says WHAT it verified rather than only that it finished (got: #{check_out.strip})"

_bogus_out, _bogus_err, bogus_code = run_generator("--bogus")
assert bogus_code == 1, "H6", GENERATOR,
       "an unrecognised flag exits 1 rather than being ignored (got #{bogus_code}); a typo'd flag " \
       "must not look like a successful run"

# The no-destination-flag property, MEASURED rather than trusted to a comment.
# This generator writes TRACKED SOURCE FILES; an argv-supplied destination is how
# a --dry-run becomes a live write, so the flag must not exist at all.
_dest_out, _dest_err, dest_code = run_generator("--dest", "/tmp/anywhere")
assert dest_code == 1, "H6", GENERATOR,
       "there is no destination flag: --dest falls through to the unknown-argument branch and " \
       "exits 1 (got #{dest_code}). The write targets are constants under #{DEST_ROOT}/ and argv " \
       "cannot reach them"

# No broad rescue. A silently swallowed error in a generator that writes tracked
# source is a wrong table landing green.
generator_source = File.read(File.join(ROOT, GENERATOR), encoding: "UTF-8")
bare = generator_source.lines.each_with_index.select do |line, _i|
  line.match?(/^\s*rescue\s*(=>|$)/)
end
assert bare.empty?, "H6", GENERATOR,
       "every `rescue` names a specific error class (found #{bare.length} bare: " \
       "#{bare.map { |l, i| "line #{i + 1}" }.join(', ')})"

verdict!
