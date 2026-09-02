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
#   Usage: ruby tools/check-contamination.rb [--root DIR] [--allowlist PATH]
#                                            [--domain-allowlist PATH] [--quiet]
#
#   --root / --allowlist / --domain-allowlist are FIXTURE KNOBS for
#   test/contamination_test.rb. When any is given the gate says so out loud on stdout, so no
#   CI log can show a green run that was secretly taken against a throwaway tree (the shape
#   bin/preflight-identity.rb's --config banner established). In that override mode a
#   missing --domain-allowlist means NO domain rows rather than the tracked ones — see the
#   note beside the argument parsing.
#   --quiet suppresses the summary lines only; FAIL lines and the override banner always print.
#
#   | Exit | Meaning                                                                     |
#   |------|-----------------------------------------------------------------------------|
#   | 0    | every occurrence is covered by a valid row; no allowlist row is broken       |
#   | 1    | at least one FAIL line was printed                                          |
#   | 2    | NO VERDICT — `CANNOT RUN: …` on stderr. git ls-files failed or listed        |
#   |      | nothing, or either allowlist could not be read. "The tree was never scanned" |
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
#     FAIL pii <path>:<line>: <address> — domain <domain> not allowlisted
#     FAIL pii <path>:<line>: <address> — local part <lp> not permitted for <domain>
#     FAIL allowlist <domain>: domain row malformed (wildcard or not a hostname)
#     FAIL allowlist <domain>: undated or malformed row
#     FAIL allowlist <domain>: entry matches nothing (no address on this domain in the tree)
#     FAIL allowlist <domain>: duplicate row for local part <lp>
#     FAIL vars <path>:<line>: reads vars.* outside the allowlist
#     FAIL vars <path>: expected <N> vars.* line(s), found <M>
#
#   Summary: contamination: <F> files scanned, <A> allowlisted, <U> unallowed,
#            <S> allowlist failures, <B> skipped-binary
#            pii: <P> addresses seen, <U> unallowed; vars: <V> reads, <U> unallowed
#
# ─── PERSONAL INFORMATION, FAIL-CLOSED BY DOMAIN (D-67) ──────────────────────────────
# The second rule this file carries. Any address-shaped string in any tracked file FAILS
# unless its domain has a dated, reasoned row in tools/domain-allowlist.txt, and the row
# may pin the local part. That direction is the whole point: a deny-list of known-bad
# values catches only what someone already thought of and is green for every address
# nobody has thought about yet, which is precisely the case this gate exists for.
#
# The address regex is test/docs_structure_test.rb:671's, verbatim. That sweep covers five
# fork-owned documents; this one covers the tree, and tree-wide the same regex matches the
# macOS icon filenames under app/macOS/Assets.xcassets — `icon_<size>@2x.png` is
# `local-part @ domain . tld` to a regex and is not an address to anyone else. Measured
# 2026-09-02: twelve such matches across five sizes in four files.
#
# So NOT_AN_ADDRESS removes that class from a line BEFORE the address regex runs. It is
# ONE anchored expression, not a path exemption and not a domain row, because:
#
#   * a path exemption would blind the gate to a real address in the same file;
#   * a `2x.png` DOMAIN row would admit `anything@2x.png` and read as if `.png` were a TLD;
#   * and the rule has to be provably load-bearing rather than decorative — remove it and
#     the twelve icon filenames go red, which is a recorded control in this plan's
#     evidence, while a `@2x.io` lookalike is STILL reported, which is a test case.
#
# WHAT IS DELIBERATELY NOT A ROW. The org domain is admitted through exactly one local
# part, the published contact used by SECURITY.md and CODE_OF_CONDUCT.md. The two other
# org addresses this fork had grown — a bootstrap contact and a throwaway git author, both
# spelled with the repository's own name — are NOT rows: they were replaced with
# `.invalid` addresses (RFC 2606) at their source on 2026-09-02, and the absence of a row
# is what makes IDENT-06's removal enforced rather than remembered. Adding a second row on
# the org domain would silently re-admit them; test/contamination_test.rb asserts there is
# exactly one, and asserts which local part it names.
#
# ─── NO WORKFLOW READS vars.* OUTSIDE ONE FILE (D-68) ────────────────────────────────
# ROADMAP Phase 4 criterion 2 says a fork's pull request behaves identically to an internal
# one. D-56 deleted the APP_NAME / BUNDLE_ID repository variables, which is what made that
# true; VARS_ALLOW is what keeps it true. Exactly three lines of
# .github/workflows/dependabot-automerge.yml may read `vars.`, and every other read under
# .github/workflows/ fails. The count is frozen here, so a fourth read cannot be added
# under cover of the one allowlisted file either.
#
# Scope is `.github/workflows/` ONLY. `vars.` in a doc or a script is prose about
# workflows, not a workflow-context read, and a gate that flagged prose would be trained
# away within a phase. The one thing this cannot see is a workflow deleted outright, so the
# count check applies whenever the tree has any tracked workflow at all: a tree with
# workflows but without the allowlisted one reports `found 0` rather than `0 reads`.
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

# D-67. EMAIL is test/docs_structure_test.rb:671's expression, character for character —
# one regex for the tree, not a second opinion about what an address looks like.
EMAIL                     = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/
# The one non-address class: macOS icon filenames. Anchored on `@<digit>x.png` so a
# lookalike on any real TLD is still reported. Removing this entry must turn the icon
# filenames red — that is the proof it is load-bearing, and it is a recorded control.
NOT_AN_ADDRESS            = [/[A-Za-z0-9_]+@\dx\.png\b/].freeze
DEFAULT_DOMAIN_ALLOWLIST  = "tools/domain-allowlist.txt"
# A lower-case hostname with a TLD. No `*`, no bare label: a catch-all row is the one edit
# that would turn a fail-closed list into a blanket exemption.
DOMAIN_RE                 = /\A[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}\z/
LOCAL_RE                  = /\A(\*|[A-Za-z0-9._%+-]+)\z/

# D-68. Frozen, never derived from the tree: the only workflow permitted to read `vars.`,
# and exactly how many lines of it may.
VARS                      = /vars\./
VARS_ALLOW                = { ".github/workflows/dependabot-automerge.yml" => 3 }.freeze
VARS_SCOPE                = ".github/workflows/"

USAGE              = "Usage: ruby tools/check-contamination.rb [--root DIR] [--allowlist PATH] " \
                     "[--domain-allowlist PATH] [--quiet]"

def no_verdict(message)
  warn "CANNOT RUN: #{message}"
  exit 2
end

# ─── arguments ───────────────────────────────────────────────────────────────────────

root       = nil
allowlist  = nil
domain_arg = nil
quiet      = false
argv       = ARGV.dup

until argv.empty?
  arg = argv.shift
  case arg
  when "--root"       then root       = argv.shift or no_verdict("--root needs a directory")
  when "--allowlist"  then allowlist  = argv.shift or no_verdict("--allowlist needs a path")
  when "--domain-allowlist"
    domain_arg = argv.shift or no_verdict("--domain-allowlist needs a path")
  when "--quiet"      then quiet      = true
  when "-h", "--help" then puts USAGE
                           exit 0
  else no_verdict("unknown argument #{arg.inspect}. #{USAGE}")
  end
end

override  = !root.nil? || !allowlist.nil? || !domain_arg.nil?
repo_root = File.expand_path("..", __dir__)
root      = root.nil? ? repo_root : File.expand_path(root)
allowlist = allowlist.nil? ? File.join(repo_root, DEFAULT_ALLOWLIST) : File.expand_path(allowlist)

# The two fixture knobs go together. In override mode a missing --domain-allowlist means
# NO domain rows, not the tracked ones: judging a throwaway tree against the real rows
# would report every one of them stale and would say nothing about either file. Outside
# override mode the tracked list is the only list.
domain_allowlist = if !domain_arg.nil?
                     File.expand_path(domain_arg)
                   elsif override
                     nil
                   else
                     File.join(repo_root, DEFAULT_DOMAIN_ALLOWLIST)
                   end

# Out loud, on stdout, before anything else: a green line in a CI log must never be
# ambiguous about which tree produced it.
if override
  puts "! contamination: scanning #{root} with #{allowlist} and " \
       "#{domain_allowlist || 'no domain rows'} (override) — not the tracked tree"
end

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

scanned           = 0
skipped_binary    = 0
hits              = {} # rel => [count, first_line]
addresses         = [] # [rel, line_number, address] — every occurrence, D-67
vars_seen         = Hash.new(0) # rel => how many lines under .github/workflows/ read vars.
vars_lines        = [] # [rel, line_number]
workflows_present = false

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
  in_vars_scope = rel.start_with?(VARS_SCOPE)
  workflows_present ||= in_vars_scope

  File.read(path, encoding: "UTF-8").each_line.with_index(1) do |line, number|
    text = line.scrub("?")
    down = text.downcase

    # D-67. The non-address class is removed from the line BEFORE the address regex sees
    # it, so an icon filename is never even counted as an address seen. The substitution
    # is a space, not the empty string, so it cannot splice two neighbours into one match.
    scrubbed = NOT_AN_ADDRESS.inject(text) { |acc, re| acc.gsub(re, " ") }
    scrubbed.scan(EMAIL) { |match| addresses << [rel, number, match] }

    # D-68. Workflows only: `vars.` anywhere else is prose about workflows.
    if in_vars_scope && text.match?(VARS)
      vars_seen[rel] += 1
      vars_lines << [rel, number]
    end

    if LITERALS.any? { |literal| down.include?(literal) }
      count += 1
      first ||= number
    end
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

# ─── the domain allowlist, parsed and judged (D-67) ──────────────────────────────────
# Grammar: domain<TAB>local-part<TAB>YYYY-MM-DD<TAB>reason. The domain must be a lower-case
# hostname with a TLD and no `*`; the local part is `*` (any) or one exact local part.
# Domains are compared case-insensitively and local parts EXACTLY: RFC 5321 §2.4 leaves
# local-part case-sensitivity to the receiving host, so two spellings are two addresses.

domain_rows     = []
domain_failures = [] # [label, message]

unless domain_allowlist.nil?
  unless File.file?(domain_allowlist) && File.readable?(domain_allowlist)
    no_verdict("domain allowlist is not a readable file: #{domain_allowlist}")
  end

  domain_text = begin
    File.read(domain_allowlist, encoding: "UTF-8")
  rescue SystemCallError => e
    no_verdict("domain allowlist could not be read: #{domain_allowlist} (#{e.message})")
  end

  domain_seen = {}
  domain_text.each_line.with_index(1) do |line, number|
    raw = line.chomp
    next if raw.strip.empty? || raw.lstrip.start_with?("#")

    cells  = raw.split("\t", -1)
    domain = cells[0].to_s.strip
    local  = cells[1].to_s.strip
    label  = domain.empty? ? "line #{number}" : domain

    if cells.length != 4 || cells.any? { |cell| cell.strip.empty? } ||
       cells[2].strip !~ ISO_DATE || local !~ LOCAL_RE
      domain_failures << [label, "undated or malformed row"]
      next
    end

    # Checked after the structural rules so that a catch-all row gets the message that
    # names what is actually wrong with it, rather than a generic one.
    unless domain =~ DOMAIN_RE
      domain_failures << [label, "domain row malformed (wildcard or not a hostname)"]
      next
    end

    if domain_seen.key?([domain, local])
      domain_failures << [label, "duplicate row for local part #{local}"]
      next
    end
    domain_seen[[domain, local]] = true

    domain_rows << { domain: domain, local: local, date: cells[2].strip, reason: cells[3].strip }
  end
end

# Every occurrence is judged, not every distinct address: two spellings on one line and the
# same address in two files are two things a reader has to look at.
pii_failures  = [] # [rel, line, message]
domains_found = {}

addresses.each do |rel, number, address|
  local, _, domain = address.rpartition("@")
  down             = domain.downcase
  domains_found[down] = true

  matching = domain_rows.select { |r| r[:domain] == down }
  if matching.empty?
    pii_failures << [rel, number, "#{address} — domain #{down} not allowlisted"]
    next
  end
  next if matching.any? { |r| r[:local] == "*" || r[:local] == local }

  pii_failures << [rel, number, "#{address} — local part #{local} not permitted for #{down}"]
end

# A row that matches nothing is the shape an exemption rots into, so it fails here exactly
# as a stale identity row does. Staleness is judged on the DOMAIN alone, which is what the
# message says: a row restricting a local part is doing its job even when every address on
# that domain is currently refused.
domain_rows.each do |r|
  next if domains_found.key?(r[:domain])

  domain_failures << [r[:domain], "entry matches nothing (no address on this domain in the tree)"]
end

# ─── the vars.* assertion (D-68) ─────────────────────────────────────────────────────

vars_failures = [] # [label, message]

vars_lines.each do |rel, number|
  next if VARS_ALLOW.key?(rel)

  vars_failures << ["#{rel}:#{number}", "reads vars.* outside the allowlist"]
end

# The count is checked only once the tree has workflows at all — a fixture repository with
# none is not a repository that lost its dependabot configuration. Given workflows, a
# missing allowlisted file reports `found 0` rather than passing silently.
if workflows_present
  VARS_ALLOW.each do |rel, expected|
    found = vars_seen[rel]
    next if found == expected

    vars_failures << [rel, "expected #{expected} vars.* line(s), found #{found}"]
  end
end

# ─── report ──────────────────────────────────────────────────────────────────────────

unallowed.sort.each do |rel, (count, first)|
  puts "FAIL contamination #{rel}: #{count} line(s) — first at line #{first}"
end
failures.each do |path, message|
  puts "FAIL allowlist #{path}: #{message}"
end
domain_failures.each do |label, message|
  puts "FAIL allowlist #{label}: #{message}"
end
pii_failures.each do |rel, number, message|
  puts "FAIL pii #{rel}:#{number}: #{message}"
end
vars_failures.each do |label, message|
  puts "FAIL vars #{label}: #{message}"
end

unless quiet
  puts "contamination: #{scanned} files scanned, #{allowlisted} allowlisted, " \
       "#{unallowed.size} unallowed, #{failures.size + domain_failures.size} allowlist failures, " \
       "#{skipped_binary} skipped-binary"
  puts "pii: #{addresses.size} addresses seen, #{pii_failures.size} unallowed; " \
       "vars: #{vars_lines.size} reads, #{vars_failures.size} unallowed"
end

exit(unallowed.empty? && failures.empty? && domain_failures.empty? &&
     pii_failures.empty? && vars_failures.empty? ? 0 : 1)
