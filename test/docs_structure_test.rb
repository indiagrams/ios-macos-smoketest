#!/usr/bin/env ruby
# frozen_string_literal: true

# Structural regression test for the four fork-owned documents.
#
# Why this exists: docs/REVIEW-ARGUMENTS.md, docs/UPSTREAM-LEDGER.md,
# docs/CONTRIBUTING-UPSTREAM.md and docs/PRODUCT-IDENTITY.md each carry a
# guarantee this project depends on, and every one of those guarantees is
# structural rather than prose. A missing heading, an emptied pre-mortem row, a
# seventh verdict value, a guideline citation that drifted into the notes block
# — none of those break a build, none of them look wrong at a glance, and all of
# them are only discovered by the person they were supposed to protect, at the
# moment it is too late to matter. Prose rots silently. This file is what makes
# it rot loudly.
#
# What each document owes, and therefore what is asserted here:
#   - REVIEW-ARGUMENTS.md   the argument headings exist, the competitive scan is
#                           dated and its assumption verdicts resolved, the
#                           pre-mortem is populated and rebutted, and the
#                           verbatim notes block is argument-free (D-27) and
#                           free of the forbidden framings (D-24).
#   - UPSTREAM-LEDGER.md    the eight-column shape, unique IDs, a per-row SCOPE
#                           test, and a Verdict drawn from the closed
#                           six-value vocabulary. That vocabulary is the only
#                           property the column has: the close-out contract is a
#                           grep over it, and a seventh value silently makes that
#                           grep lie.
#   - CONTRIBUTING-UPSTREAM.md  it references CONTRIBUTING.md rather than
#                           duplicating it (D-21), documents a flow that can
#                           actually work (`format-patch`), reaches the ledger,
#                           and never suggests the impossible cross-repo PR.
#   - PRODUCT-IDENTITY.md   the three identity strings are actually recorded.
#
# Grep-gate hygiene — read before adding an assertion:
#   These documents discuss the very tokens this file checks for. REVIEW-ARGUMENTS.md
#   explains in prose why the notes carry no guideline citation; UPSTREAM-LEDGER.md
#   prints its own close-out grep. A count-based match over a whole file would
#   therefore match the prose describing the check and report a meaningless
#   result. Every assertion below either extracts the specific section or parses
#   the specific table first. Do not replace one with a whole-file grep.
#
# Unlike its sibling test/gen_review_notes_test.rb, which builds throwaway trees
# because the generator must be verifiable on its own, this suite asserts
# against the REAL files in the repository. That is the entire point: it is the
# repository's own documents that are under guarantee.
#
# Runnable locally:
#   ruby test/docs_structure_test.rb
#
# Wired into .github/workflows/review-notes.yml.
# Ruby stdlib only. No gem, no framework, no rake task — matching test/parser_test.rb.

require "date"

ROOT = File.expand_path("..", __dir__)

REVIEW_ARGUMENTS   = "docs/REVIEW-ARGUMENTS.md"
UPSTREAM_LEDGER    = "docs/UPSTREAM-LEDGER.md"
CONTRIBUTING_UP    = "docs/CONTRIBUTING-UPSTREAM.md"
PRODUCT_IDENTITY   = "docs/PRODUCT-IDENTITY.md"
ALL_DOCS           = [REVIEW_ARGUMENTS, UPSTREAM_LEDGER, CONTRIBUTING_UP, PRODUCT_IDENTITY].freeze

# The closed set from UPSTREAM-LEDGER.md §"Verdict vocabulary". Deliberately
# duplicated here rather than parsed out of the document: a test that derived the
# vocabulary from the file under test would accept whatever that file happened to
# say, which is not a test.
VERDICTS = %w[Pending Submitted Merged Denied Out-of-scope Fork-only].freeze

@failures = 0
@checks   = 0

def assert(condition, label)
  @checks += 1
  if condition
    puts "  ✓ #{label}"
  else
    puts "  ✗ #{label}"
    @failures += 1
  end
end

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

def read_doc(relative)
  path = File.join(ROOT, relative)
  unless File.exist?(path)
    puts "  ✗ #{relative}: file does not exist"
    @failures += 1
    return ""
  end
  File.read(path)
end

# Returns the text from the heading matching `heading` up to (not including) the
# next heading at the same level or shallower. Section extraction, rather than a
# whole-file grep, is what keeps these assertions from matching the prose that
# describes them.
def section(text, heading)
  lines = text.lines
  start = lines.index { |l| l =~ heading }
  return nil if start.nil?

  level = lines[start][/\A#+/].length
  stop  = lines.each_with_index.find do |l, i|
    i > start && l =~ /\A\#{1,#{level}}\s/
  end
  lines[start...(stop ? stop[1] : lines.length)].join
end

# Splits one Markdown table row into its cells. `"| a | b |".split("|")` yields
# ["", " a ", " b "], so dropping the leading empty element gives the cells;
# Ruby drops the trailing empty element for us.
def cells(row)
  row.split("|")[1..].to_a.map(&:strip)
end

# The table rows of a section: lines that begin with a pipe, with the
# `|---|---|` separator dropped.
def table_rows(text)
  text.lines.map(&:strip).select { |l| l.start_with?("|") }.reject { |l| l =~ /\A\|[\s:|-]+\|\z/ }
end

# Drops HTML comment regions. Used only for the forbidden-framing assertion, so
# that a note left for a later reader can name a banned phrase in order to
# explain the ban without tripping the ban. Comments never reach App Review.
def without_html_comments(text)
  text.gsub(/<!--.*?-->/m, "")
end

puts "Document structure tests:"
puts

# ─── docs/REVIEW-ARGUMENTS.md ────────────────────────────────────────────────

review = read_doc(REVIEW_ARGUMENTS)

puts "#{REVIEW_ARGUMENTS} — required headings:"

{
  "competitive scan"                => /^## Competitive scan \(run \d{4}-\d{2}-\d{2}\)/,
  "guideline 4.2 argument"          => /^## Guideline 4\.2\b/,
  "guideline 4.3(b) argument"       => /^## Guideline 4\.3\(b\)/,
  "macOS addendum"                  => /^## macOS addendum/,
  "hostile read pre-mortem"         => /^## Hostile read/,
  "pre-drafted Resolution Center reply" => /^## Pre-drafted Resolution Center reply/,
  "verbatim notes block"            => /^## Verbatim notes block/
}.each do |what, pattern|
  assert review =~ pattern, "#{REVIEW_ARGUMENTS}: the #{what} heading is present"
end

puts
puts "#{REVIEW_ARGUMENTS} — competitive scan is dated and resolved:"

scan_date = review[/^## Competitive scan \(run (\d{4}-\d{2}-\d{2})\)/, 1]
parsed_scan_date =
  begin
    scan_date && Date.strptime(scan_date, "%Y-%m-%d").strftime("%Y-%m-%d") == scan_date
  rescue ArgumentError
    false
  end
assert parsed_scan_date,
       "#{REVIEW_ARGUMENTS}: the competitive scan heading carries a real ISO date (found #{scan_date.inspect})"

verdicts_section = section(review, /^### Assumption verdicts/)
assert !verdicts_section.nil?, "#{REVIEW_ARGUMENTS}: an 'Assumption verdicts' section exists"

%w[A3 A4].each do |aid|
  line = (verdicts_section || "").lines.find { |l| l.include?("#{aid} —") }
  assert !line.nil? && line !~ /UNVERIFIED/i,
         "#{REVIEW_ARGUMENTS}: assumption #{aid}'s verdict line is resolved, not UNVERIFIED"
end

puts
puts "#{REVIEW_ARGUMENTS} — the pre-mortem table is populated and rebutted:"

premortem = section(review, /^## Hostile read/) || ""
pm_rows   = table_rows(premortem)
pm_header = pm_rows.find { |r| cells(r).any? { |c| c.casecmp("rebuttal").zero? } }

assert !pm_header.nil?,
       "#{REVIEW_ARGUMENTS}: the pre-mortem table has a header row naming a Rebuttal column"

pm_header_cells = pm_header ? cells(pm_header) : []
rebuttal_idx = pm_header_cells.index { |c| c.casecmp("rebuttal").zero? }
residual_idx = pm_header_cells.index { |c| c.downcase.start_with?("residual") }

assert !residual_idx.nil?,
       "#{REVIEW_ARGUMENTS}: the pre-mortem table has a Residual-risk column"

objection_rows = pm_rows.select { |r| cells(r).first.to_s =~ /\AH\d+\z/ }

assert objection_rows.length >= 4,
       "#{REVIEW_ARGUMENTS}: the pre-mortem table has at least 4 objection rows (found #{objection_rows.length})"

if rebuttal_idx && residual_idx
  empty_rebuttals = objection_rows.reject { |r| !cells(r)[rebuttal_idx].to_s.empty? }
                                  .map { |r| cells(r).first }
  assert empty_rebuttals.empty?,
         "#{REVIEW_ARGUMENTS}: every pre-mortem objection row has a non-empty Rebuttal cell" \
         "#{empty_rebuttals.empty? ? '' : " (empty: #{empty_rebuttals.join(', ')})"}"

  empty_residual = objection_rows.reject { |r| !cells(r)[residual_idx].to_s.empty? }
                                 .map { |r| cells(r).first }
  assert empty_residual.empty?,
         "#{REVIEW_ARGUMENTS}: every pre-mortem objection row has a non-empty Residual-risk cell" \
         "#{empty_residual.empty? ? '' : " (empty: #{empty_residual.join(', ')})"}"
end

puts
puts "#{REVIEW_ARGUMENTS} — the id=core notes block is well-formed and argument-free:"

begin_count = review.scan(/<!--\s*BEGIN:REVIEW-NOTES\s+id=core\s*-->/).length
end_count   = review.scan(/<!--\s*END:REVIEW-NOTES\s+id=core\s*-->/).length

assert_eq begin_count, 1, "#{REVIEW_ARGUMENTS}: exactly one BEGIN:REVIEW-NOTES id=core sentinel"
assert_eq end_count,   1, "#{REVIEW_ARGUMENTS}: exactly one matching END:REVIEW-NOTES id=core sentinel"

core_body = review[
  /<!--\s*BEGIN:REVIEW-NOTES\s+id=core\s*-->\n(.*?)<!--\s*END:REVIEW-NOTES\s+id=core\s*-->/m, 1
].to_s

assert !core_body.strip.empty?,
       "#{REVIEW_ARGUMENTS}: the id=core block body is non-empty"
assert !core_body.strip.start_with?("TODO"),
       "#{REVIEW_ARGUMENTS}: the id=core block body does not begin with TODO"

# D-27 made mechanical. The notes describe the app; they never argue a guideline.
# Scoped to the extracted block precisely because the surrounding document
# explains at length WHY the block carries no citation — a whole-file grep here
# would match that explanation and pass for the wrong reason.
{
  "4.3(b)"    => /4\.3\(b\)/,
  "4.2"       => /\b4\.2\b/,
  "guideline" => /guideline/i
}.each do |what, pattern|
  assert core_body !~ pattern,
         "#{REVIEW_ARGUMENTS}: the id=core block contains no guideline citation (#{what}) — D-27"
end

puts
puts "#{REVIEW_ARGUMENTS} — the forbidden framings are absent (D-24):"

review_prose = without_html_comments(review)
[
  "comprehensive toolkit",
  "the only app",
  "more tools than"
].each do |framing|
  assert review_prose !~ /#{Regexp.escape(framing)}/i,
         "#{REVIEW_ARGUMENTS}: does not use the forbidden framing #{framing.inspect} — D-24"
end

# ─── docs/UPSTREAM-LEDGER.md ─────────────────────────────────────────────────

puts
puts "#{UPSTREAM_LEDGER} — the ledger table shape:"

ledger      = read_doc(UPSTREAM_LEDGER)
ledger_rows = table_rows(ledger)
ledger_head = ledger_rows.find { |r| cells(r).first == "ID" }

assert !ledger_head.nil?, "#{UPSTREAM_LEDGER}: a table header row beginning with an ID column exists"

head_cells = ledger_head ? cells(ledger_head) : []
assert_eq head_cells,
          ["ID", "Date", "Phase", "Learning", "SCOPE test", "Verdict", "PR", "Notes"],
          "#{UPSTREAM_LEDGER}: the header names all eight columns in order"

verdict_idx = head_cells.index("Verdict")
scope_idx   = head_cells.index("SCOPE test")

data_rows = ledger_rows.select { |r| cells(r).first.to_s =~ /\AUL-\d{3}\z/ }
assert !data_rows.empty?,
       "#{UPSTREAM_LEDGER}: at least one UL-NNN data row exists (found #{data_rows.length})"

if verdict_idx
  # The closed-vocabulary gate. A seventh value here would not break anything
  # visibly — it would just make the close-out grep quietly under-report.
  bad = data_rows.filter_map do |r|
    c = cells(r)
    verdict = c[verdict_idx].to_s
    "#{c.first} => #{verdict.inspect}" unless verdict =~ /\A(#{VERDICTS.join('|')})\b/
  end
  assert bad.empty?,
         "#{UPSTREAM_LEDGER}: every Verdict is drawn from the closed vocabulary " \
         "(#{VERDICTS.join(' | ')})#{bad.empty? ? '' : " — offending: #{bad.join('; ')}"}"
end

ids  = data_rows.map { |r| cells(r).first }
dupe = ids.tally.select { |_, n| n > 1 }.keys
assert dupe.empty?,
       "#{UPSTREAM_LEDGER}: UL IDs are unique#{dupe.empty? ? '' : " — duplicated: #{dupe.join(', ')}"}"

if scope_idx
  missing_scope = data_rows.filter_map { |r| cells(r).first if cells(r)[scope_idx].to_s.empty? }
  assert missing_scope.empty?,
         "#{UPSTREAM_LEDGER}: every row records a SCOPE test answer (UP-03 stays auditable per row)" \
         "#{missing_scope.empty? ? '' : " — missing: #{missing_scope.join(', ')}"}"
end

# ─── docs/CONTRIBUTING-UPSTREAM.md ───────────────────────────────────────────

puts
puts "#{CONTRIBUTING_UP} — references rather than duplicates, and documents a flow that works:"

contributing = read_doc(CONTRIBUTING_UP)

assert contributing.include?("](../CONTRIBUTING.md)"),
       "#{CONTRIBUTING_UP}: links ../CONTRIBUTING.md rather than restating it — D-21"
assert contributing.include?("format-patch"),
       "#{CONTRIBUTING_UP}: mentions format-patch, so the documented flow is one that can actually work"
assert contributing.include?("](UPSTREAM-LEDGER.md)"),
       "#{CONTRIBUTING_UP}: links UPSTREAM-LEDGER.md, so the log step is reachable"
assert contributing !~ %r{pr create\s+--repo\s+indiagrams/apple-shipkit},
       "#{CONTRIBUTING_UP}: never suggests a cross-repo `pr create --repo indiagrams/apple-shipkit` — " \
       "the two repos share no fork network, so that command cannot work"

# ─── docs/PRODUCT-IDENTITY.md ────────────────────────────────────────────────

puts
puts "#{PRODUCT_IDENTITY} — the identity strings are recorded:"

identity = read_doc(PRODUCT_IDENTITY)

{
  "the App Store display name" => "Shipkit Pipes",
  "the iOS bundle ID"          => "com.indiagram.shipkitpipes.ios",
  "the macOS bundle ID"        => "com.indiagram.shipkitpipes.macos"
}.each do |what, value|
  assert identity.include?(value), "#{PRODUCT_IDENTITY}: records #{what} (#{value})"
end

# ─── across all four documents ───────────────────────────────────────────────

puts
puts "all four documents — no leaked contact address:"

EMAIL = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/

leaked = ALL_DOCS.filter_map do |doc|
  m = read_doc(doc)[EMAIL]
  "#{doc} (#{m})" if m
end
assert leaked.empty?,
       "no fork-owned document contains an email-shaped string" \
       "#{leaked.empty? ? '' : " — found in #{leaked.join('; ')}"}"

puts
if @failures.zero?
  puts "All #{@checks} document structure assertions passed."
  exit 0
else
  puts "#{@failures} of #{@checks} assertion(s) failed."
  exit 1
end
