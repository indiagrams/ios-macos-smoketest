#!/usr/bin/env ruby
# frozen_string_literal: true

# Structural regression test for the five fork-owned documents.
#
# Why this exists: docs/REVIEW-ARGUMENTS.md, docs/UPSTREAM-LEDGER.md,
# docs/CONTRIBUTING-UPSTREAM.md, docs/PRODUCT-IDENTITY.md and
# docs/APPLE-ACCOUNT-STATE.md each carry a guarantee this project depends on,
# and every one of those guarantees is
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
#   - APPLE-ACCOUNT-STATE.md    the six-column dated-triple contract holds: every
#                           fact row carries a measurement date (or an explicit
#                           `pending NN-NN` marker naming the plan that will
#                           measure it) and, once measured, the team or key it
#                           was measured against. That convention is the file's
#                           entire value, and an unguarded convention decays
#                           exactly the way release.yml:35's A1B2C3D4E5
#                           measurement did — a number with no date and no
#                           target, indistinguishable from one that applies.
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
APPLE_ACCOUNT_STATE = "docs/APPLE-ACCOUNT-STATE.md"
# APPLE_ACCOUNT_STATE's membership here is load-bearing on its own: it is what
# puts the fifth document under the EMAIL sweep at the bottom of this file, which
# is how "no personal information is committed" stops being a habit and becomes a
# mechanism. The App Store Connect Business page displays plenty of it.
ALL_DOCS           = [REVIEW_ARGUMENTS, UPSTREAM_LEDGER, CONTRIBUTING_UP, PRODUCT_IDENTITY,
                      APPLE_ACCOUNT_STATE].freeze

# The closed set from UPSTREAM-LEDGER.md §"Verdict vocabulary". Deliberately
# duplicated here rather than parsed out of the document: a test that derived the
# vocabulary from the file under test would accept whatever that file happened to
# say, which is not a test.
VERDICTS = %w[Pending Submitted Merged Denied Out-of-scope Fork-only].freeze

# The six columns of every fact table in APPLE-ACCOUNT-STATE.md, in order.
# Duplicated here for the same reason VERDICTS is: a test that read its column
# names out of the file under test would accept whatever that file happened to
# say, which is not a test. Reordering two of these in the document is one of the
# breakages this block was watched failing on.
ACCOUNT_STATE_COLUMNS = [
  "Fact",
  "Value",
  "Measured (ISO-8601)",
  "Against (team / key / record id)",
  "Valid until",
  "Re-check command"
].freeze

# Only these sections hold fact tables. Scoping matters more here than anywhere
# else in this file: APPLE-ACCOUNT-STATE.md prints its own column names as an
# example in "How to read a row" and carries an unrelated three-row
# staleness-window table in "Staleness contract", so a whole-file table parse
# matches 22 rows where 17 belong to a fact table — and would then keep passing
# on the prose after the tables themselves had rotted away. Measured, not
# assumed; UL-010 records three near-misses of this exact shape in Phase 1.
ACCOUNT_STATE_FACT_SECTIONS = [
  /^## Apple Developer Program and account/,
  /^## ASC API key/,
  /^## Certificate census/
].freeze

# A cap is a claim about Apple's limits. Apple publishes no numeric per-team
# certificate figure at all (C-A), so any number in a Value cell is an occupancy
# count on a date, and a cell that phrases one as a cap is asserting something
# nobody measured.
ACCOUNT_STATE_CAP = /\b(caps?|quotas?|maximum|max|limits?)\b[^\S\n]*(?:of|=|is|:)?[^\S\n]*\d/i

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
  # UTF-8 pinned, never inherited. With LANG unset Encoding.default_external is
  # US-ASCII, and every document here carries em dashes — so an unpinned read
  # makes the very first regex raise `invalid byte sequence in US-ASCII` and the
  # suite dies mid-run instead of reporting a verdict. Observed: before this line
  # existed, `env -u LANG -u LC_ALL -u LC_CTYPE ruby test/docs_structure_test.rb`
  # aborted at line 206 with no exit code of its own. Same defect and same fix as
  # UL-012 in tools/gen-review-notes.rb; this file was simply never run without a
  # locale.
  File.read(path, encoding: "UTF-8")
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

# ─── docs/APPLE-ACCOUNT-STATE.md ─────────────────────────────────────────────

puts
puts "#{APPLE_ACCOUNT_STATE} — the six-column dated-triple contract:"

account_state = read_doc(APPLE_ACCOUNT_STATE)

assert account_state.include?("G5H628C6WR"),
       "#{APPLE_ACCOUNT_STATE}: names the team every measurement was made against (G5H628C6WR)"

ACCOUNT_STATE_FACT_SECTIONS.each do |heading|
  label = heading.source.sub(/\A\^#+\s*/, "")
  body  = section(account_state, heading)

  assert !body.nil?, "#{APPLE_ACCOUNT_STATE}: the '#{label}' section exists"
  next if body.nil?

  rows = table_rows(body)
  head = rows.find { |r| cells(r).first == "Fact" }

  assert !head.nil?,
         "#{APPLE_ACCOUNT_STATE}: '#{label}' has a fact-table header row beginning with a Fact column"
  next if head.nil?

  assert_eq cells(head), ACCOUNT_STATE_COLUMNS,
            "#{APPLE_ACCOUNT_STATE}: '#{label}' names all six columns in order"

  data_rows = rows.reject { |r| r.equal?(head) }
  assert !data_rows.empty?,
         "#{APPLE_ACCOUNT_STATE}: '#{label}' has at least one fact row (found #{data_rows.length})"

  fact_i, value_i, measured_i, against_i =
    ACCOUNT_STATE_COLUMNS.values_at(0, 1, 2, 3).map { |c| ACCOUNT_STATE_COLUMNS.index(c) }

  # The date half of the triple. A row is either measured on a real ISO-8601 day
  # or explicitly not measured yet, and "not measured yet" has to name the plan
  # that will measure it — a bare blank reads as a zero to the next person.
  undated = data_rows.filter_map do |r|
    c = cells(r)
    m = c[measured_i].to_s
    "#{c[fact_i]} => #{m.inspect}" unless m =~ /\A\d{4}-\d{2}-\d{2}\z/ || m =~ /\Apending \d{2}-\d{2}\z/
  end
  assert undated.empty?,
         "#{APPLE_ACCOUNT_STATE}: every '#{label}' row carries an ISO-8601 Measured date or an " \
         "explicit `pending NN-NN` marker#{undated.empty? ? '' : " — offending: #{undated.join('; ')}"}"

  # The target half of the triple, which is the half C-05 is missing. Pending rows
  # are exempt because they have not been measured against anything yet.
  targetless = data_rows.filter_map do |r|
    c = cells(r)
    next if c[measured_i].to_s =~ /\Apending \d{2}-\d{2}\z/

    c[fact_i] if c[against_i].to_s.empty?
  end
  assert targetless.empty?,
         "#{APPLE_ACCOUNT_STATE}: every measured '#{label}' row names what it was measured against" \
         "#{targetless.empty? ? '' : " — missing: #{targetless.join(', ')}"}"

  capped = data_rows.filter_map do |r|
    c = cells(r)
    "#{c[fact_i]} => #{c[value_i].inspect}" if c[value_i].to_s =~ ACCOUNT_STATE_CAP
  end
  assert capped.empty?,
         "#{APPLE_ACCOUNT_STATE}: no '#{label}' Value cell states a numeric cap — occupancy only" \
         "#{capped.empty? ? '' : " — offending: #{capped.join('; ')}"}"
end

# ─── across all five documents ───────────────────────────────────────────────

puts
puts "all five documents — no leaked contact address:"

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
