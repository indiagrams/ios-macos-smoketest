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
#   - PRODUCT-IDENTITY.md   the three identity strings are actually recorded, and
#                           the EU trader-status table holds the same dated-triple
#                           contract: every observation carries an ISO-8601 date and
#                           names the account or record it was read against, with a
#                           row required for BOTH surfaces, because the account-level
#                           declaration does not evidence the per-app one (C-08/R-05).
#                           No cell may assert a status label that has no first-party
#                           Apple source (R-06).
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

# The bracket half of that vocabulary, which the closed-set check alone does not
# reach. It matches on the leading word, so `Merged` with the bracket dropped
# passes it — and the close-out grep counts only `Pending` and `Submitted`, so
# such a row reads as closed while naming nothing anyone can open. Observed:
# UL-013 rewritten to a bare `Merged` passed all 62 assertions before this block
# existed, which is the whole reason it exists. UPSTREAM-LEDGER.md's own
# vocabulary section already says the bracket is required for five of the six
# values; this is what makes saying so enforceable.
BRACKETED_VERDICTS   = %w[Submitted Merged Denied Out-of-scope Fork-only].freeze
# Two of those five must carry a pull request number specifically, not prose.
PR_NUMBER_VERDICTS   = %w[Submitted Merged].freeze

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
  /^## App IDs/,
  /^## App Store Connect app record/,
  /^## Certificate census/
].freeze

# A cap is a claim about Apple's limits. Apple publishes no numeric per-team
# certificate figure at all (C-A), so any number in a Value cell is an occupancy
# count on a date, and a cell that phrases one as a cap is asserting something
# nobody measured.
ACCOUNT_STATE_CAP = /\b(caps?|quotas?|maximum|max|limits?)\b[^\S\n]*(?:of|=|is|:)?[^\S\n]*\d/i

# The four columns of PRODUCT-IDENTITY.md's trader-status table, in order.
# Same reason as ACCOUNT_STATE_COLUMNS for being duplicated here rather than read
# out of the document: a test that took its column names from the file under test
# would accept whatever that file happened to say.
TRADER_COLUMNS = ["Surface", "Observed string", "Observed (ISO-8601)", "Against"].freeze

# The one record this project owns, and the account it lives on. Trader status has
# two independent surfaces -- an account-level declaration and a per-app one -- and
# `.planning/research/PITFALLS.md` asserts it is account-level only (C-08/R-05). A
# verification that read only the account level would report green while an app sat
# undeclared, so the table is required to carry a row measured against each. Naming
# the record id specifically is what stops "the account is Active" from being
# quietly resubmitted as evidence about the app.
TRADER_RECORD_ID  = "6807393045"
TRADER_ACCOUNT_RE = /\baccount\b/i

# Neither of these strings appears in any first-party Apple source, and the
# account-level status was observed reading `Active` on 2026-09-01. They are here
# because a repo file predicted them and a gate that encoded one could never have
# fired correctly (R-06). Asserted against the OBSERVED STRING CELLS ONLY, never the
# whole section: the section's prose has to be free to explain why these two words
# are absent, and a whole-file grep would match that explanation and fail for the
# opposite of the right reason. That is the UL-010 shape, recorded three times in
# Phase 1.
UNSOURCED_TRADER_LABELS = %w[Verified Pending].freeze


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

  bracketless = data_rows.filter_map do |r|
    c       = cells(r)
    verdict = c[verdict_idx].to_s
    word    = verdict[/\A[A-Za-z][A-Za-z-]*/]
    next unless BRACKETED_VERDICTS.include?(word)

    detail = verdict[/\A#{Regexp.escape(word)}\s+\[(.+)\]\z/, 1]
    if detail.nil?
      "#{c.first} => #{verdict.inspect} (no bracketed detail)"
    elsif PR_NUMBER_VERDICTS.include?(word) && detail !~ /\A#\d+\z/
      "#{c.first} => #{verdict.inspect} (bracket is not a #N pull request number)"
    end
  end
  assert bracketless.empty?,
         "#{UPSTREAM_LEDGER}: every non-Pending Verdict carries its required bracket — a " \
         "#N pull request number for #{PR_NUMBER_VERDICTS.join('/')}, a reason for the rest" \
         "#{bracketless.empty? ? '' : " — offending: #{bracketless.join('; ')}"}"
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

# The three strings are unchanged; two of the labels are not. Universal Purchase
# was adopted on 2026-09-01 (D-44, reversing D-05), so there is no longer an "iOS
# bundle ID" and a "macOS bundle ID": one shared bundle ID serves both platforms
# on record 6807393045, and the .macos identifier is a registered App ID that no
# app record was ever created against. Both strings must still appear in the
# identity document -- the shared one because it is the identity, the unused one
# because an orphaned-but-registered identifier that goes unrecorded is exactly
# the kind of account state that later gets rediscovered as a surprise. The
# assertions were relabelled to say what is true, not relaxed to accept less.
{
  "the App Store display name"           => "Shipkit Pipes",
  "the shared iOS+macOS bundle ID"       => "com.indiagram.shipkitpipes.ios",
  "the registered but unused App ID"     => "com.indiagram.shipkitpipes.macos"
}.each do |what, value|
  assert identity.include?(value), "#{PRODUCT_IDENTITY}: records #{what} (#{value})"
end

puts
puts "#{PRODUCT_IDENTITY} — the trader-status observations are dated and targeted:"

# D-38 puts EU trader status here rather than in APPLE-ACCOUNT-STATE.md, and an
# unguarded fact table is decorative: prose rots silently, which is what this whole
# file exists to prevent. Section-extracted, never whole-file — see UNSOURCED_TRADER_LABELS.
trader = section(identity, /^## European Union trader status/)

assert !trader.nil?,
       "#{PRODUCT_IDENTITY}: the 'European Union trader status' section exists — D-38"

unless trader.nil?
  trader_rows = table_rows(trader)
  trader_head = trader_rows.find { |r| cells(r).first == "Surface" }

  assert !trader_head.nil?,
         "#{PRODUCT_IDENTITY}: the trader-status table has a header row beginning with a Surface column"

  if trader_head
    assert_eq cells(trader_head), TRADER_COLUMNS,
              "#{PRODUCT_IDENTITY}: the trader-status table names all four columns in order"

    surface_i, observed_i, date_i, against_i = 0, 1, 2, 3
    trader_data = trader_rows.reject { |r| r.equal?(trader_head) }

    # Five observations were made on 2026-09-01: the account-level status, EACH of the
    # two option labels in the Digital Services Act Compliance dialog, the per-app
    # declaration on the record, and whether that per-app surface carries a platform
    # selector. The floor is five rather than the four 02-08-PLAN.md asked for, and
    # the difference is not cosmetic: the plan's floor was written for a four-surface
    # shape, five surfaces were actually read, and a floor of four would let one of
    # the five be deleted with the suite still green. Observed doing exactly that —
    # the plan's own prescribed control, "delete one of the rows and confirm the
    # count assertion fails", PASSED against a floor of four. Second time in this
    # phase a prescribed control was itself the broken instrument (see 02-05).
    # A floor only ever moves up: a plan that adds a sixth observation raises it.
    assert trader_data.length >= 5,
           "#{PRODUCT_IDENTITY}: the trader-status table has at least 5 observation rows " \
           "(found #{trader_data.length})"

    # The date half of the triple. An observation without a day is not a measurement,
    # and trader status is enforced per submission, so the date is what a later phase
    # reads to decide the row needs re-reading.
    undated = trader_data.filter_map do |r|
      c = cells(r)
      "#{c[surface_i]} => #{c[date_i].to_s.inspect}" unless c[date_i].to_s =~ /\A\d{4}-\d{2}-\d{2}\z/
    end
    assert undated.empty?,
           "#{PRODUCT_IDENTITY}: every trader-status row carries an ISO-8601 Observed date" \
           "#{undated.empty? ? '' : " — offending: #{undated.join('; ')}"}"

    # The target half. Which account, or which record.
    targetless = trader_data.filter_map { |r| cells(r)[surface_i] if cells(r)[against_i].to_s.empty? }
    assert targetless.empty?,
           "#{PRODUCT_IDENTITY}: every trader-status row names what it was observed against" \
           "#{targetless.empty? ? '' : " — missing: #{targetless.join(', ')}"}"

    # C-08/R-05 made mechanical: both surfaces, or this is not a trader-status check.
    assert trader_data.any? { |r| cells(r)[against_i].to_s.include?(TRADER_RECORD_ID) },
           "#{PRODUCT_IDENTITY}: at least one trader-status row is observed against record " \
           "#{TRADER_RECORD_ID} — the per-app surface, which the account-level one does not evidence"
    assert trader_data.any? { |r| cells(r)[against_i].to_s =~ TRADER_ACCOUNT_RE },
           "#{PRODUCT_IDENTITY}: at least one trader-status row is observed against the account"

    # Pitfall 2. Scoped to the Observed string cells so the prose explaining the
    # absence stays legal.
    unsourced = trader_data.flat_map do |r|
      c = cells(r)
      UNSOURCED_TRADER_LABELS.filter_map do |label|
        "#{c[surface_i]} => #{label}" if c[observed_i].to_s =~ /\b#{Regexp.escape(label)}\b/
      end
    end
    assert unsourced.empty?,
           "#{PRODUCT_IDENTITY}: no trader-status Observed string cell asserts a label with no " \
           "first-party source (#{UNSOURCED_TRADER_LABELS.join(' | ')})" \
           "#{unsourced.empty? ? '' : " — offending: #{unsourced.join('; ')}"}"
  end
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
