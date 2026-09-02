#!/usr/bin/env ruby
# frozen_string_literal: true

# tools/check-contamination.rb — does the TEMPLATE's identity still appear anywhere in
# this fork's tracked tree, other than where a dated, counted, reasoned row says it may?
#
# IDENT-11, as amended by D-69; ROADMAP Phase 4 criterion 1, as amended by D-65.
#
# ─── NOT THE SAME FILE AS ci/check-identity.sh ───────────────────────────────────────
# This repository contains two identity checks whose names invite confusion, and they ask
# OPPOSITE questions. Upstream's `ci/check-identity.sh` is a COMPLETENESS check: is the
# fork's own identity present and non-empty everywhere the build needs it? It wraps
# `bin/preflight-identity.rb` and is called from `pr.yml`'s non-required `config` job and
# from `ci/local-check.sh`. This file is a CONTAMINATION check: is the TEMPLATE's identity
# absent everywhere it is not explicitly permitted? A green run of one says nothing about
# the other. (The collision is recorded in docs/UPSTREAM-LEDGER.md with a proposal to
# rename upstream's script `ci/check-identity-complete.sh`.)
#
# ─── WHY THIS LIVES IN tools/ AND NOT bin/ (D-69) ────────────────────────────────────
# IDENT-11's original wording named `bin/check-identity.sh`. `bin/` and `ci/` are
# template-owned (AGENTS.md), and `bin/refork-smoketest.sh` DELETES this repository and
# recreates it from the template — so a fork-authored file at a template-owned path is
# removed wholesale on the next refork. That would silently delete this phase's main gate,
# which is the same failure class as UL-003. Fork-owned tooling goes in `tools/`, beside
# `preflight-identity.rb`'s siblings, and it is Ruby rather than bash so it inherits the
# conventions those neighbours already establish.
#
# ─── WHY A SCAN ALONE IS NOT ENOUGH ──────────────────────────────────────────────────
# 04-CONTEXT C-20 measured the tree on 2026-09-02: roughly 40 tracked files carry the
# literals, in five different classes.
#
#   1. Historical record that must not change — CHANGELOG.md, docs/UPSTREAM-LEDGER.md,
#      docs/APPLE-ACCOUNT-STATE.md.
#   2. Guards and fixtures where the literal IS the check — bin/adopt.rb:68 exists
#      precisely to reject `com.indiagram.smokeapp`; fastlane/Fastfile's
#      adopt_existing_app guard does the same; ci/test-rename*.sh must contain the name
#      the rename is supposed to remove; test/identity_test.rb asserts its absence and so
#      must spell it. A GATE THAT DELETED THESE WOULD DELETE THE GUARDS.
#   3. Docs describing the template — MIGRATING-TO-TUIST.md and friends.
#   4. Template files this fork has not synced yet (Phase 5, D-59).
#   5. Strings shipped in the binary. 04-05 removed all six of these from app/Shared/;
#      tools/identity-allowlist.txt carries NO row under app/ and test/contamination_test.rb
#      asserts it stays that way.
#
# ─── AND WHY THE ALLOWLIST IS ITSELF A GATE ──────────────────────────────────────────
# test/identity_test.rb:46-54 refuses a repo-wide grep because it "would either need a
# self-exclusion list (which is where the hole gets drilled) or report a meaningless
# number". D-65 took the allowlist anyway and closed the hole with numbers:
#
#   * every row is a dated measurement triple — path, COUNT, ISO date — plus a reason,
#     the shape docs/APPLE-ACCOUNT-STATE.md:41-46 defines ("recording two of the three
#     records nothing");
#   * a row whose path matches nothing FAILS, so the list cannot rot into an exemption;
#   * a row whose count is short FAILS, so a real regression sitting on the line below a
#     legitimate guard literal is caught — this is why path-level-only rows were rejected;
#   * an undated, malformed or duplicated row FAILS;
#   * a path-level `*` row is permitted for CHANGELOG.md alone, because it accumulates
#     mentions every phase and a per-occurrence list there would need editing forever.
#
# Bump a count only together with a reason edit and a new date. A count that drifted is a
# signal, not an annoyance.
#
# ─── CONTRACT ────────────────────────────────────────────────────────────────────────
#
#   Usage: ruby tools/check-contamination.rb [--root DIR] [--allowlist PATH] [--quiet]
#
#   --root / --allowlist are FIXTURE KNOBS for test/contamination_test.rb. When either is
#   given the gate says so out loud on stdout, so no CI log can show a green run that was
#   secretly taken against a throwaway tree (the shape bin/preflight-identity.rb's
#   --config banner established).
#   --quiet suppresses the summary line only; FAIL lines and the override banner always print.
#
#   | Exit | Meaning                                                                     |
#   |------|-----------------------------------------------------------------------------|
#   | 0    | every occurrence is covered by a valid row; no allowlist row is broken       |
#   | 1    | at least one FAIL line was printed                                          |
#   | 2    | NO VERDICT — `CANNOT RUN: …` on stderr. git ls-files failed or listed        |
#   |      | nothing, or the allowlist could not be read. "The tree was never scanned"    |
#   |      | must never be readable as "the tree was checked".                            |
#
#   Failure lines — one line each, no leading whitespace (five Phase 3 negative controls
#   grep for this shape; do not change it):
#
#     FAIL contamination <path>: <N> line(s) — first at line <L>
#     FAIL allowlist <path>: entry matches nothing (stale or misspelled)
#     FAIL allowlist <path>: expected <N> line(s), found <M>
#     FAIL allowlist <path>: undated or malformed row
#     FAIL allowlist <path>: duplicate row
#     FAIL allowlist <path>: path-level row not permitted (only CHANGELOG.md)
#
#   Summary: contamination: <F> files scanned, <A> allowlisted, <U> unallowed,
#            <S> allowlist failures, <B> skipped-binary
#
# ─── WHAT THIS CHECK CANNOT SEE ──────────────────────────────────────────────────────
#   * Untracked files. The subject is what is IN the repository; `git ls-files` defines it.
#   * Binary files. A tracked file whose first 8000 bytes contain a NUL is skipped and
#     counted as skipped-binary (git's own heuristic). An identity string inside a PNG or
#     an .xcassets blob is invisible here.
#   * Meaning. The match is a case-insensitive SUBSTRING, so `SmokeAppliance` counts. False
#     positives are cheap — add a row — and false negatives are the entire defect this
#     exists to prevent, so the match is deliberately broad.
#   * Identities other than the two template ones below. This is a contamination check,
#     not a completeness check; see the ci/check-identity.sh note above.
#
# ─── RUN IT LOCALLY, UNDER BOTH PINNED INTERPRETERS ──────────────────────────────────
#   /opt/homebrew/opt/ruby@3.3/bin/ruby tools/check-contamination.rb
#   /opt/homebrew/opt/ruby@4.0/bin/ruby tools/check-contamination.rb
#   /opt/homebrew/opt/ruby@3.3/bin/ruby test/contamination_test.rb
#
# ZERO require lines, not even stdlib — that is what lets `review notes` keep
# `bundler-cache: false`, and test/contamination_test.rb asserts it so it cannot rot.
# Every shell-out is an explicit argv array, never a shell string.

# ─── frozen constants: never derived from the subject under test ─────────────────────
# The two template identities. Matching is done on the DOWNCASED line against these two
# stems, which covers `SmokeApp`, `com.indiagram.smokeapp`, `HelloApp`,
# `com.example.helloapp` and every letter-case variant (the IN-05 cases at
# test/identity_test.rb:90-94). The full bundle ids are spelled here for the reader; the
# frozen stems are what the code uses.
LITERALS           = %w[smokeapp helloapp].freeze
PATH_LEVEL_ALLOWED = %w[CHANGELOG.md].freeze
DEFAULT_ALLOWLIST  = "tools/identity-allowlist.txt"
BINARY_PROBE_BYTES = 8000
ISO_DATE           = /\A\d{4}-\d{2}-\d{2}\z/
USAGE              = "Usage: ruby tools/check-contamination.rb [--root DIR] [--allowlist PATH] [--quiet]"

def no_verdict(message)
  warn "CANNOT RUN: #{message}"
  exit 2
end

# ─── arguments ───────────────────────────────────────────────────────────────────────

root      = nil
allowlist = nil
quiet     = false
argv      = ARGV.dup

until argv.empty?
  arg = argv.shift
  case arg
  when "--root"      then root      = argv.shift or no_verdict("--root needs a directory")
  when "--allowlist" then allowlist = argv.shift or no_verdict("--allowlist needs a path")
  when "--quiet"     then quiet     = true
  when "-h", "--help" then puts USAGE
                           exit 0
  else no_verdict("unknown argument #{arg.inspect}. #{USAGE}")
  end
end

override  = !root.nil? || !allowlist.nil?
repo_root = File.expand_path("..", __dir__)
root      = root.nil? ? repo_root : File.expand_path(root)
allowlist = allowlist.nil? ? File.join(repo_root, DEFAULT_ALLOWLIST) : File.expand_path(allowlist)

# Out loud, on stdout, before anything else: a green line in a CI log must never be
# ambiguous about which tree produced it.
puts "! contamination: scanning #{root} with #{allowlist} (override) — not the tracked tree" if override

# ─── the tracked file list ───────────────────────────────────────────────────────────
# Argv array, never a shell string. `git ls-files -z` is what defines "in the repository";
# an exit code other than 0, or an empty list, is a reason to refuse a verdict, not to
# report a clean tree.

listing = nil
begin
  listing = IO.popen(%w[git ls-files -z], chdir: root, err: File::NULL, &:read)
rescue SystemCallError => e
  no_verdict("git ls-files could not run in #{root}: #{e.message}")
end
no_verdict("git ls-files exited #{$?.exitstatus} in #{root}") unless $?&.success?

files = listing.to_s.split("\0").reject(&:empty?).sort
no_verdict("git ls-files listed no tracked files in #{root}") if files.empty?

# ─── the sweep ───────────────────────────────────────────────────────────────────────

scanned        = 0
skipped_binary = 0
hits           = {} # rel => [count, first_line]

files.each do |rel|
  path = File.join(root, rel)

  # lstat, so a symlink is "not a regular file" rather than a second read of its target;
  # a gitlink (submodule) is a directory here and is skipped the same way.
  stat = begin
    File.lstat(path)
  rescue SystemCallError
    nil
  end
  next if stat.nil? || !stat.file?

  probe = begin
    File.open(path, "rb") { |io| io.read(BINARY_PROBE_BYTES) }
  rescue SystemCallError
    nil
  end
  next if probe.nil?

  if probe.include?("\x00".b)
    skipped_binary += 1
    next
  end

  scanned += 1

  # UTF-8 pinned, never inherited from the locale: with LANG unset Ruby defaults
  # Encoding.default_external to US-ASCII and a © raises ArgumentError out of the match
  # instead of exiting 0 or 1. Commit 3b1efb9 is this repository's own instance (UL-012).
  # .scrub("?") on each line is what keeps an almost-text tracked file from raising.
  count = 0
  first = nil
  File.read(path, encoding: "UTF-8").each_line.with_index(1) do |line, number|
    down = line.scrub("?").downcase
    next unless LITERALS.any? { |literal| down.include?(literal) }

    count += 1
    first ||= number
  end

  hits[rel] = [count, first] if count.positive?
end

# ─── the allowlist, parsed and judged ────────────────────────────────────────────────
# Grammar: path<TAB>count<TAB>YYYY-MM-DD<TAB>reason. `#` comments and blank lines are
# ignored. Paths are exact tracked paths — no globs, because a glob is how one row grows
# to cover a file nobody looked at.

no_verdict("allowlist is not a readable file: #{allowlist}") unless File.file?(allowlist) && File.readable?(allowlist)

allowlist_text = begin
  File.read(allowlist, encoding: "UTF-8")
rescue SystemCallError => e
  no_verdict("allowlist could not be read: #{allowlist} (#{e.message})")
end

rows     = []
failures = [] # [path, message]
covered  = {} # every path a row MENTIONS, valid or not — so a broken row is reported once
seen     = {}

allowlist_text.each_line.with_index(1) do |line, number|
  raw = line.chomp
  next if raw.strip.empty? || raw.lstrip.start_with?("#")

  cells = raw.split("\t", -1)
  path  = cells[0].to_s.strip
  label = path.empty? ? "line #{number}" : path
  covered[path] = true unless path.empty?

  malformed = cells.length != 4 ||
              cells.any? { |cell| cell.strip.empty? } ||
              !(cells[1].strip == "*" || cells[1].strip =~ /\A[1-9]\d*\z/) ||
              cells[2].strip !~ ISO_DATE
  if malformed
    failures << [label, "undated or malformed row"]
    next
  end

  if seen.key?(path)
    failures << [path, "duplicate row"]
    next
  end
  seen[path] = true

  count = cells[1].strip
  if count == "*" && !PATH_LEVEL_ALLOWED.include?(path)
    failures << [path, "path-level row not permitted (only #{PATH_LEVEL_ALLOWED.join(', ')})"]
    next
  end

  rows << { path: path, count: count, date: cells[2].strip, reason: cells[3].strip }
end

allowlisted = 0
rows.each do |r|
  hit = hits[r[:path]]
  if hit.nil?
    failures << [r[:path], "entry matches nothing (stale or misspelled)"]
    next
  end
  if r[:count] != "*" && r[:count].to_i != hit[0]
    failures << [r[:path], "expected #{r[:count]} line(s), found #{hit[0]}"]
    next
  end
  allowlisted += 1
end

unallowed = hits.reject { |rel, _| covered.key?(rel) }

# ─── report ──────────────────────────────────────────────────────────────────────────

unallowed.sort.each do |rel, (count, first)|
  puts "FAIL contamination #{rel}: #{count} line(s) — first at line #{first}"
end
failures.each do |path, message|
  puts "FAIL allowlist #{path}: #{message}"
end

unless quiet
  puts "contamination: #{scanned} files scanned, #{allowlisted} allowlisted, " \
       "#{unallowed.size} unallowed, #{failures.size} allowlist failures, " \
       "#{skipped_binary} skipped-binary"
end

exit(unallowed.empty? && failures.empty? ? 0 : 1)
