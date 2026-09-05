#!/usr/bin/env ruby
# frozen_string_literal: true

# Contract test for tools/check-contamination.rb — the whole-tree template-identity
# contamination gate (IDENT-11 as amended by D-69; ROADMAP Phase 4 criterion 1 as
# amended by D-65) — and for tools/identity-allowlist.txt, which is itself a gate.
#
# Why this exists.
#
#   Criterion 1 says the template identity appears nowhere in the tree. Measured on
#   2026-09-02 (04-CONTEXT C-20) that is false by 40-odd files, and the occurrences are
#   five different kinds of thing: historical record (CHANGELOG.md), guards and fixtures
#   whose literal IS the check (bin/adopt.rb:68 rejects `com.indiagram.smokeapp`;
#   fastlane/Fastfile's adopt_existing_app guard; test/identity_test.rb), docs describing the
#   template, template files this fork has not synced, and — until 04-05 — strings shipped
#   in the binary. A gate that simply deleted every occurrence would delete the guards.
#
#   So the gate is scan + allowlist. And an allowlist is where the hole gets drilled:
#   test/identity_test.rb:46-54 refuses a repo-wide grep for exactly that reason. The
#   answer D-65 chose is that the allowlist is a gate too. Every row is a dated
#   measurement triple in this project's established shape (docs/APPLE-ACCOUNT-STATE.md:41-46
#   — "a value, its measurement date, and the thing it was measured against are one unit;
#   recording two of the three records nothing") plus an expected COUNT, so that a real
#   regression sitting beside a legitimate guard literal changes the number and fails.
#   A row that matches nothing fails. A row without a date fails. A duplicate fails. A
#   path-level `*` row fails everywhere except CHANGELOG.md, which accumulates mentions
#   every phase. Each of those five failure modes is driven red below, and again on the
#   live tree in this plan's evidence file.
#
# Failure-line contract — do not change the shape (test/identity_test.rb:36-44):
#
#     FAIL <group> <path>: <message>
#
# one line, no leading whitespace. This file's group token is `CT`. Five Phase 3 negative
# controls grep for that shape; a message split across two lines makes all of them vacuous.
#
# This file deliberately CONTAINS the literals it is about — `SmokeApp`, `HelloApp`,
# `com.indiagram.smokeapp`, `com.example.helloapp` — because they are the fixtures. It
# therefore carries its own dated, counted row in tools/identity-allowlist.txt, and the
# real-tree case below asserts that the row exists and that its count equals what this
# file independently measures. That is the self-exclusion problem answered with a number
# instead of with an exemption.
#
# Runnable from the repository root or from test/, under BOTH pinned interpreters:
#   /opt/homebrew/opt/ruby@3.3/bin/ruby test/contamination_test.rb
#   /opt/homebrew/opt/ruby@4.0/bin/ruby test/contamination_test.rb
#
# Ruby stdlib only (open3, tmpdir, fileutils, rbconfig) — no gems, which is what keeps
# the `review notes` job's `bundler-cache: false` honest. The GATE itself has ZERO
# require lines, asserted below so it cannot rot. Every shell-out is an argv array.

require "open3"
require "tmpdir"
require "fileutils"
require "rbconfig"

ROOT          = File.expand_path("..", __dir__)
GATE_REL      = "tools/check-contamination.rb"
ALLOWLIST_REL = "tools/identity-allowlist.txt"
GATE          = File.join(ROOT, GATE_REL)
ALLOWLIST     = File.join(ROOT, ALLOWLIST_REL)

# Frozen, never derived from the gate (test/docs_structure_test.rb:87-91's idiom): a test
# that read its literal set out of the file under test would accept whatever that file
# happened to say, which is not a test.
LITERALS           = %w[smokeapp helloapp].freeze
PATH_LEVEL_ALLOWED = %w[CHANGELOG.md].freeze
SELF_ROWS          = [GATE_REL, "test/contamination_test.rb"].freeze
ISO_DATE           = /\A\d{4}-\d{2}-\d{2}\z/
# The reason vocabulary of 04-CONTEXT C-20's five classes, plus `self:`.
REASON_CLASSES     = ["historical record:", "guard:", "fixture:", "template doc:",
                      "not-synced template file (Phase 5):", "self:"].freeze

# Hermetic git: the developer's global config must not decide whether a fixture file is
# ignored, which branch `init` creates, or which template dir seeds hooks.
GIT_ENV = { "GIT_CONFIG_GLOBAL" => "/dev/null", "GIT_CONFIG_SYSTEM" => "/dev/null" }.freeze

# The env hash clears LC_ALL/LANG/LC_CTYPE so the encoding case fails against a gate that
# inherits the locale (UL-012 / commit 3b1efb9), rather than restating the fix.
NO_LOCALE = { "LC_ALL" => nil, "LANG" => nil, "LC_CTYPE" => nil }.freeze

@failures = 0
@checks   = 0

def assert(condition, group, path, label)
  @checks += 1
  if condition
    puts "  ✓ #{group} #{path}: #{label}"
  else
    puts "FAIL #{group} #{path}: #{label.to_s.gsub(/\s*\n\s*/, ' ')}"
    @failures += 1
  end
end

def verdict!
  puts
  if @failures.zero?
    puts "All #{@checks} contamination-gate assertions passed."
    exit 0
  else
    puts "#{@failures} of #{@checks} contamination-gate assertion(s) failed."
    exit 1
  end
end

# ─── the gate must exist before anything can be asserted about it ────────────
# File.exist? first, and a clean exit rather than a crash: "the file was never there" is
# a distinct outcome from "the check ran and failed", and this file must say which.

unless File.exist?(GATE)
  assert false, "CT", GATE_REL, "gate missing"
  assert File.exist?(ALLOWLIST), "CT", ALLOWLIST_REL, "allowlist missing"
  verdict!
end

# ─── harness ─────────────────────────────────────────────────────────────────

def git(root, *args)
  out, err, status = Open3.capture3(GIT_ENV, "git", *args, chdir: root)
  raise "harness: git #{args.join(' ')} failed in #{root}: #{err}#{out}" unless status.success?
end

# A throwaway git repository containing exactly the given paths, committed. The parent
# tmpdir also holds the fixture allowlist, OUTSIDE the repo, so it is never itself a
# tracked file the gate would scan or a row could go stale against.
def with_repo(files)
  Dir.mktmpdir("contamination-test") do |base|
    root = File.join(base, "repo")
    FileUtils.mkdir_p(root)
    files.each do |rel, content|
      path = File.join(root, rel)
      FileUtils.mkdir_p(File.dirname(path))
      if content.is_a?(String) && content.encoding == Encoding::BINARY
        File.binwrite(path, content)
      else
        File.write(path, content)
      end
    end
    git(root, "init", "-q")
    unless files.empty?
      git(root, "add", "-A", ".")
      git(root, "-c", "user.email=t@local.invalid", "-c", "user.name=t",
          "commit", "-q", "-m", "fixture")
    end
    yield root, File.join(base, "allowlist.txt")
  end
end

# Runs the gate. Combined stdout+stderr is returned separately so the exit-2 cases can
# assert CANNOT RUN lands on stderr.
#
# `domain_text:` is opt-in. When it is nil the gate is called WITHOUT
# --domain-allowlist, which in override mode means "no domain rows at all" — that is what
# lets 04-07's twenty-one cases keep their exact call shape and their exact outcomes: a
# fixture tree judged against the TRACKED domain rows would report every one of those rows
# stale, which says nothing about either file. Passing a String (even "") writes it to a
# fixture path beside the identity allowlist and passes the knob.
def gate(root, allowlist_path, allowlist_text = nil, domain_text: nil, env: {}, extra: [])
  File.write(allowlist_path, allowlist_text) unless allowlist_text.nil?
  argv = [RbConfig.ruby, GATE, "--root", root, "--allowlist", allowlist_path]
  unless domain_text.nil?
    domain_path = File.join(File.dirname(allowlist_path), "domain-allowlist.txt")
    File.write(domain_path, domain_text)
    argv += ["--domain-allowlist", domain_path]
  end
  out, err, status = Open3.capture3(env, *argv + extra, chdir: ROOT)
  [out.to_s, err.to_s, status.exitstatus]
end

def row(path, count, date, reason)
  "#{path}\t#{count}\t#{date}\t#{reason}\n"
end

# A domain-allowlist row: domain<TAB>local-part<TAB>ISO-date<TAB>reason.
def drow(domain, local, date, reason)
  "#{domain}\t#{local}\t#{date}\t#{reason}\n"
end

# Fixture addresses are BUILT, never written literally. This file is tracked, and the gate
# it tests sweeps the tracked tree for address-shaped strings — so a literal fixture
# address here would have to be given a domain row to keep the tree green, and the row for
# the domain this plan's live red control uses would make that control vacuous. Splitting
# every fixture across the `@` keeps the source free of anything the EMAIL regex matches.
def addr(local, domain)
  "#{local}@#{domain}"
end

# The literal sweep, measured here rather than asked of the gate.
def hit_count(absolute)
  File.read(absolute, encoding: "UTF-8").each_line.count do |line|
    d = line.scrub("?").downcase
    LITERALS.any? { |l| d.include?(l) }
  end
end

TWO_HITS  = "SmokeApp on line one\nplain\ncom.indiagram.smokeapp on line three\n"
NO_HITS   = "nothing to see here\njust text\n"

puts "CT — tools/check-contamination.rb, the D-65 whole-tree contamination gate:"

# ─── 1. clean tree, empty allowlist ──────────────────────────────────────────
with_repo("a.txt" => NO_HITS) do |root, al|
  out, _err, code = gate(root, al, "")
  assert code.zero? && out.include?("0 unallowed"), "CT", "-",
         "clean tree with an empty allowlist exits 0 and reports 0 unallowed (exit=#{code}, out=#{out.inspect})"
end

# ─── 2. a hit with no row fails, naming the count and the first line ─────────
with_repo("a.txt" => TWO_HITS) do |root, al|
  out, _err, code = gate(root, al, "")
  assert code == 1 && out.include?("FAIL contamination a.txt: 2 line(s) — first at line 1"),
         "CT", "a.txt",
         "an unallowed file fails with its count and first line (exit=#{code}, out=#{out.inspect})"
end

# ─── 3. the same file with a correct row passes ──────────────────────────────
with_repo("a.txt" => TWO_HITS) do |root, al|
  out, _err, code = gate(root, al, row("a.txt", 2, "2026-09-02", "fixture: two literals"))
  assert code.zero? && out.include?("1 allowlisted") && out.include?("0 unallowed"),
         "CT", "a.txt",
         "a dated row with the right count allowlists the file (exit=#{code}, out=#{out.inspect})"
end

# ─── 4. a short count fails — D-65's whole reason for counting rows ──────────
with_repo("a.txt" => TWO_HITS) do |root, al|
  out, _err, code = gate(root, al, row("a.txt", 1, "2026-09-02", "guard: undercounted"))
  assert code == 1 && out.include?("FAIL allowlist a.txt: expected 1 line(s), found 2"),
         "CT", "a.txt",
         "a row whose count is short fails, so a regression beside a guard literal cannot hide " \
         "(exit=#{code}, out=#{out.inspect})"
end

# ─── 5. a row for a path that is not tracked at all is stale ─────────────────
with_repo("a.txt" => TWO_HITS) do |root, al|
  text = row("a.txt", 2, "2026-09-02", "fixture: real") + row("never.txt", 1, "2026-09-02", "fixture: stale")
  out, _err, code = gate(root, al, text)
  assert code == 1 && out.include?("FAIL allowlist never.txt: entry matches nothing (stale or misspelled)"),
         "CT", "never.txt",
         "a row for an untracked path fails as stale (exit=#{code}, out=#{out.inspect})"
end

# ─── 6. a row for a tracked file with zero hits is equally stale ─────────────
with_repo("a.txt" => TWO_HITS, "clean.txt" => NO_HITS) do |root, al|
  text = row("a.txt", 2, "2026-09-02", "fixture: real") + row("clean.txt", 1, "2026-09-02", "fixture: stale")
  out, _err, code = gate(root, al, text)
  assert code == 1 && out.include?("FAIL allowlist clean.txt: entry matches nothing (stale or misspelled)"),
         "CT", "clean.txt",
         "a row for a tracked file with no hits fails as stale (exit=#{code}, out=#{out.inspect})"
end

# ─── 7. an undated row fails (docs_structure_test.rb:633-642's rule) ─────────
with_repo("a.txt" => TWO_HITS) do |root, al|
  out, _err, code = gate(root, al, row("a.txt", 2, "yesterday", "fixture: undated"))
  assert code == 1 && out.include?("FAIL allowlist a.txt: undated or malformed row"),
         "CT", "a.txt",
         "a row whose date is not ISO-8601 fails (exit=#{code}, out=#{out.inspect})"
end

# ─── 8. a row missing a column fails as malformed ────────────────────────────
with_repo("a.txt" => TWO_HITS) do |root, al|
  out, _err, code = gate(root, al, "a.txt\t2\tfixture: no date column\n")
  assert code == 1 && out.include?("FAIL allowlist a.txt: undated or malformed row"),
         "CT", "a.txt",
         "a row with three cells instead of four fails as malformed (exit=#{code}, out=#{out.inspect})"
end

# ─── 9. a non-integer count fails as malformed ───────────────────────────────
with_repo("a.txt" => TWO_HITS) do |root, al|
  out, _err, code = gate(root, al, row("a.txt", "two", "2026-09-02", "fixture: word count"))
  assert code == 1 && out.include?("FAIL allowlist a.txt: undated or malformed row"),
         "CT", "a.txt",
         "a row whose count is not a positive integer fails as malformed (exit=#{code}, out=#{out.inspect})"
end

# ─── 10. duplicate rows fail ─────────────────────────────────────────────────
with_repo("a.txt" => TWO_HITS) do |root, al|
  text = row("a.txt", 2, "2026-09-02", "fixture: one") + row("a.txt", 2, "2026-09-02", "fixture: two")
  out, _err, code = gate(root, al, text)
  assert code == 1 && out.include?("FAIL allowlist a.txt: duplicate row"),
         "CT", "a.txt",
         "two rows for one path fail (exit=#{code}, out=#{out.inspect})"
end

# ─── 11. a path-level `*` row is refused everywhere but CHANGELOG.md ─────────
with_repo("b.txt" => TWO_HITS) do |root, al|
  out, _err, code = gate(root, al, row("b.txt", "*", "2026-09-02", "fixture: wildcard"))
  assert code == 1 && out.include?("FAIL allowlist b.txt: path-level row not permitted (only CHANGELOG.md)"),
         "CT", "b.txt",
         "a `*` count outside #{PATH_LEVEL_ALLOWED.join(', ')} is refused (exit=#{code}, out=#{out.inspect})"
end

# ─── 12. CHANGELOG.md may carry `*`, but only while it still matches ─────────
with_repo("CHANGELOG.md" => TWO_HITS) do |root, al|
  out, _err, code = gate(root, al, row("CHANGELOG.md", "*", "2026-09-02", "historical record: accumulates every phase"))
  assert code.zero? && out.include?("1 allowlisted"), "CT", "CHANGELOG.md",
         "CHANGELOG.md accepts a path-level row (exit=#{code}, out=#{out.inspect})"
end

with_repo("CHANGELOG.md" => NO_HITS) do |root, al|
  out, _err, code = gate(root, al, row("CHANGELOG.md", "*", "2026-09-02", "historical record: accumulates every phase"))
  assert code == 1 && out.include?("FAIL allowlist CHANGELOG.md: entry matches nothing (stale or misspelled)"),
         "CT", "CHANGELOG.md",
         "even the path-level row goes stale when it stops matching (exit=#{code}, out=#{out.inspect})"
end

# ─── 13. both template identities, in any letter case (IN-05) ────────────────
with_repo("c.txt" => "helloapp\nCOM.EXAMPLE.HELLOAPP\nsmokeApp\n") do |root, al|
  out, _err, code = gate(root, al, "")
  assert code == 1 && out.include?("FAIL contamination c.txt: 3 line(s) — first at line 1"),
         "CT", "c.txt",
         "both template identities match in any letter case (exit=#{code}, out=#{out.inspect})"
end

# ─── 14. substring, not word: false positives are cheap, false negatives are the defect ──
with_repo("d.txt" => "SmokeAppliance\n") do |root, al|
  out, _err, code = gate(root, al, "")
  assert code == 1 && out.include?("FAIL contamination d.txt: 1 line(s) — first at line 1"),
         "CT", "d.txt",
         "the match is a substring, so SmokeAppliance counts too (exit=#{code}, out=#{out.inspect})"
end

# ─── 15. a binary tracked file is skipped, not scanned and not crashed on ────
binary = (+"\x00\x01\x02SmokeApp\x00").force_encoding(Encoding::BINARY)
with_repo("bin.dat" => binary) do |root, al|
  out, _err, code = gate(root, al, "")
  assert code.zero? && out.include?("1 skipped-binary") && out.include?("0 unallowed"),
         "CT", "bin.dat",
         "a NUL-carrying tracked file is skipped as binary rather than scanned (exit=#{code}, out=#{out.inspect})"
end

# ─── 16. untracked files are invisible — git ls-files only ───────────────────
with_repo("a.txt" => NO_HITS) do |root, al|
  File.write(File.join(root, "untracked.txt"), TWO_HITS)
  out, _err, code = gate(root, al, "")
  assert code.zero? && !out.include?("untracked.txt"), "CT", "untracked.txt",
         "an untracked file carrying the literal is ignored (exit=#{code}, out=#{out.inspect})"
end

# ─── 17. the WORKING TREE is read, not the committed blob ────────────────────
with_repo("a.txt" => NO_HITS) do |root, al|
  File.write(File.join(root, "a.txt"), NO_HITS + "SmokeApp\n")
  out, _err, code = gate(root, al, "")
  assert code == 1 && out.include?("FAIL contamination a.txt: 1 line(s) — first at line 3"),
         "CT", "a.txt",
         "an uncommitted append is counted, because the gate reads the working tree (exit=#{code}, out=#{out.inspect})"
end

# ─── 18. non-ASCII content under an unset locale (UL-012) ────────────────────
with_repo("e.txt" => "© Indiagram\nplain\n") do |root, al|
  out, err, code = gate(root, al, "", env: NO_LOCALE)
  assert code.zero? && !err.include?("ArgumentError") && !err.include?("invalid byte"),
         "CT", "e.txt",
         "a © with LANG/LC_ALL/LC_CTYPE unset scans without raising (exit=#{code}, err=#{err.inspect})"
end

# ─── 19. the override says so out loud ───────────────────────────────────────
with_repo("a.txt" => NO_HITS) do |root, al|
  out, _err, _code = gate(root, al, "")
  assert out.include?("! contamination: scanning") && out.include?("(override) — not the tracked tree"),
         "CT", "-",
         "--root/--allowlist print a loud override banner (out=#{out.inspect})"
end

# ─── 20. a repository listing no files gets NO verdict, not a green one ──────
with_repo({}) do |root, al|
  out, err, code = gate(root, al, "")
  assert code == 2 && err.include?("CANNOT RUN"), "CT", "-",
         "a tree where git ls-files lists nothing exits 2 with CANNOT RUN, never 0 " \
         "(exit=#{code}, out=#{out.inspect}, err=#{err.inspect})"
end

# ─── 21. an unreadable allowlist gets no verdict either ──────────────────────
with_repo("a.txt" => NO_HITS) do |root, al|
  missing = File.join(File.dirname(al), "no-such-allowlist.txt")
  argv = [RbConfig.ruby, GATE, "--root", root, "--allowlist", missing]
  out, err, status = Open3.capture3(*argv, chdir: ROOT)
  assert status.exitstatus == 2 && err.include?("CANNOT RUN"), "CT", "-",
         "an unreadable allowlist exits 2 with CANNOT RUN (exit=#{status.exitstatus}, " \
         "out=#{out.inspect}, err=#{err.inspect})"
end

# ─── 22. the real tree, with no overrides ────────────────────────────────────

puts
puts "CT — the live tree and the tracked allowlist:"

real_out, real_err, real_status = Open3.capture3(RbConfig.ruby, GATE, chdir: ROOT)
real_code = real_status.exitstatus
assert real_code.zero? && real_out.include?("0 unallowed"), "CT", "-",
       "the gate is green on HEAD with 0 unallowed " \
       "(exit=#{real_code}, out=#{real_out.inspect}, err=#{real_err.inspect})"
assert !real_out.include?("(override)"), "CT", "-",
       "with no --root/--allowlist the override banner is absent"

# ─── 23. the tracked allowlist, parsed with the same grammar ─────────────────

assert File.exist?(ALLOWLIST), "CT", ALLOWLIST_REL, "exists"

allowlist_rows = []
malformed      = []
if File.exist?(ALLOWLIST)
  File.read(ALLOWLIST, encoding: "UTF-8").each_line.with_index(1) do |line, n|
    line = line.chomp
    next if line.strip.empty? || line.start_with?("#")

    cells = line.split("\t", -1)
    if cells.length != 4 || cells.any? { |c| c.strip.empty? } ||
       !(cells[1] == "*" || cells[1] =~ /\A[1-9]\d*\z/) || cells[2] !~ ISO_DATE
      malformed << "line #{n}: #{line.inspect}"
      next
    end
    allowlist_rows << { path: cells[0], count: cells[1], date: cells[2], reason: cells[3], line: n }
  end
end

assert malformed.empty?, "CT", ALLOWLIST_REL,
       "every data row is path<TAB>count<TAB>ISO-date<TAB>reason with a positive-integer or `*` count" \
       "#{malformed.empty? ? '' : " — offending: #{malformed.join('; ')}"}"

dupes = allowlist_rows.map { |r| r[:path] }.tally.select { |_, n| n > 1 }.keys
assert dupes.empty?, "CT", ALLOWLIST_REL,
       "no path appears twice#{dupes.empty? ? '' : " — #{dupes.join(', ')}"}"

wild = allowlist_rows.select { |r| r[:count] == "*" }.map { |r| r[:path] } - PATH_LEVEL_ALLOWED
assert wild.empty?, "CT", ALLOWLIST_REL,
       "only #{PATH_LEVEL_ALLOWED.join(', ')} carries a path-level `*` row" \
       "#{wild.empty? ? '' : " — #{wild.join(', ')}"}"

# D-65's line that must stay true: nothing that ships in the binary is permitted. 04-05
# removed all six app/Shared occurrences, and this is the assertion that keeps it removed.
shipped = allowlist_rows.map { |r| r[:path] }.select { |p| p.start_with?("app/") }
assert shipped.empty?, "CT", ALLOWLIST_REL,
       "no row is under app/ — nothing shipped in the binary is allowlisted" \
       "#{shipped.empty? ? '' : " — #{shipped.join(', ')}"}"

live = allowlist_rows.select { |r| r[:reason].downcase.include?("live config") }.map { |r| r[:path] }
assert live.empty?, "CT", ALLOWLIST_REL,
       "no row's reason is live config — C-20 class 4 is fixed at the source, never permitted" \
       "#{live.empty? ? '' : " — #{live.join(', ')}"}"

offclass = allowlist_rows.reject { |r| REASON_CLASSES.any? { |c| r[:reason].start_with?(c) } }
assert offclass.empty?, "CT", ALLOWLIST_REL,
       "every reason opens with one of C-20's class names (#{REASON_CLASSES.join(' ')})" \
       "#{offclass.empty? ? '' : " — offending: #{offclass.map { |r| "line #{r[:line]}" }.join(', ')}"}"

# The self-exclusion answered with a number: the two files that necessarily contain the
# literals carry rows whose counts equal what this test measures independently.
SELF_ROWS.each do |rel|
  found = allowlist_rows.find { |r| r[:path] == rel }
  measured = File.exist?(File.join(ROOT, rel)) ? hit_count(File.join(ROOT, rel)) : -1
  assert !found.nil? && found[:count] == measured.to_s, "CT", rel,
         "carries a `self:` row whose count equals the #{measured} line(s) measured here " \
         "(row=#{found ? found[:count] : 'absent'})"
end

# ─── 24. zero requires in the gate ───────────────────────────────────────────
gate_requires = File.read(GATE, encoding: "UTF-8").lines.grep(/\A\s*require\b/)
assert gate_requires.empty?, "CT", GATE_REL,
       "has zero require-family lines, which is the basis for review-notes.yml's bundler-cache: false" \
       "#{gate_requires.empty? ? '' : " — #{gate_requires.map(&:strip).join('; ')}"}"

# ═══════════════════════════════════════════════════════════════════════════════
# D-67 — personal information, gated by a FAIL-CLOSED DOMAIN ALLOWLIST
# D-68 — the `vars.*` assertion (the construction half of criterion 2)
# ═══════════════════════════════════════════════════════════════════════════════
#
# A deny-list catches only what someone already thought of. The rule here is the other
# way round: any address-shaped string fails unless its DOMAIN carries a dated, reasoned
# row, and the row may restrict the local part. An address on a domain nobody has thought
# about yet fails by default, which is the whole point.
#
# The regex is `test/docs_structure_test.rb:671`'s, verbatim. That sweep runs over five
# fork-owned documents; run tree-wide the same regex matches the macOS icon filenames
# (`icon_512x512@2x.png` and its four sibling sizes), which are not addresses at all. That
# false-positive class is excluded in CODE, by one anchored regex, and this file proves the
# exclusion is both load-bearing (remove it and the icon filenames go red — see this plan's
# evidence file) and NARROW: a `@2x.io` lookalike is still reported.

puts
puts "CT — D-67 personal information: the fail-closed domain allowlist:"

TODAY = "2026-09-02"

# ─── 25. an address on an unknown domain fails, with no rows at all ──────────
with_repo("a.md" => "contact: #{addr('someone', 'newdomain.io')}\n") do |root, al|
  out, _err, code = gate(root, al, "", domain_text: "")
  assert code == 1 &&
         out.include?("FAIL pii a.md:1: #{addr('someone', 'newdomain.io')} — domain newdomain.io not allowlisted"),
         "CT", "a.md",
         "an address on an un-rowed domain fails closed, naming path, line, address and domain " \
         "(exit=#{code}, out=#{out.inspect})"
end

# ─── 26. a `*` local-part row admits the whole domain ────────────────────────
with_repo("a.md" => "contact: #{addr('someone', 'newdomain.io')}\n") do |root, al|
  out, _err, code = gate(root, al, "", domain_text: drow("newdomain.io", "*", TODAY, "fixture: any local part"))
  assert code.zero? && out.include?("1 addresses seen, 0 unallowed"),
         "CT", "a.md",
         "a dated `*` row admits every local part on that domain (exit=#{code}, out=#{out.inspect})"
end

# ─── 27. a restricted row admits ONE local part and refuses the others ───────
with_repo("a.md" => "#{addr('other', 'newdomain.io')}\n") do |root, al|
  out, _err, code = gate(root, al, "", domain_text: drow("newdomain.io", "someone", TODAY, "fixture: one local part"))
  assert code == 1 &&
         out.include?("FAIL pii a.md:1: #{addr('other', 'newdomain.io')} — local part other not permitted for newdomain.io"),
         "CT", "a.md",
         "a row naming a local part refuses every other local part on the same domain " \
         "(exit=#{code}, out=#{out.inspect})"
end

# ─── 28. the domain is case-insensitive; the local part is not (RFC 5321) ────
with_repo("a.md" => "#{addr('maintainers', 'INDIAGRAM.COM')}\n") do |root, al|
  out, _err, code = gate(root, al, "", domain_text: drow("indiagram.com", "maintainers", TODAY, "fixture: published contact"))
  assert code.zero? && out.include?("0 unallowed"),
         "CT", "a.md",
         "an upper-case DOMAIN still matches its row — domains are case-insensitive " \
         "(exit=#{code}, out=#{out.inspect})"
end

with_repo("a.md" => "#{addr('Maintainers', 'indiagram.com')}\n") do |root, al|
  out, _err, code = gate(root, al, "", domain_text: drow("indiagram.com", "maintainers", TODAY, "fixture: published contact"))
  assert code == 1 && out.include?("local part Maintainers not permitted for indiagram.com"),
         "CT", "a.md",
         "a differently-cased LOCAL PART is a different local part (RFC 5321) and fails " \
         "(exit=#{code}, out=#{out.inspect})"
end

# ─── 29. the macOS icon filenames are not addresses ──────────────────────────
ICON_JSON = %({ "filename" : "#{addr('icon_512x512', '2x.png')}" }\n)
with_repo("Contents.json" => ICON_JSON) do |root, al|
  out, _err, code = gate(root, al, "", domain_text: "")
  assert code.zero? && out.include?("0 addresses seen"),
         "CT", "Contents.json",
         "an icon filename is excluded BEFORE the address regex runs, so it is not even counted " \
         "(exit=#{code}, out=#{out.inspect})"
end

# ─── 30. …and the exclusion is narrow: a lookalike TLD is still reported ─────
with_repo("a.md" => "#{addr('icon_512x512', '2x.io')}\n") do |root, al|
  out, _err, code = gate(root, al, "", domain_text: "")
  assert code == 1 && out.include?("domain 2x.io not allowlisted"),
         "CT", "a.md",
         "the non-address rule is anchored on the .png class only — a @2x.io lookalike is a finding " \
         "(exit=#{code}, out=#{out.inspect})"
end

# ─── 31. the ssh remote user is a row, not a person ──────────────────────────
GITHUB_ROW = drow("github.com", "git", TODAY, "fixture: ssh user, not a person")
with_repo("a.md" => "#{addr('git', 'github.com')}\n") do |root, al|
  out, _err, code = gate(root, al, "", domain_text: GITHUB_ROW)
  assert code.zero? && out.include?("0 unallowed"), "CT", "a.md",
         "the ssh remote user is admitted by its own restricted row (exit=#{code}, out=#{out.inspect})"
end

with_repo("a.md" => "#{addr('me', 'github.com')}\n") do |root, al|
  out, _err, code = gate(root, al, "", domain_text: GITHUB_ROW)
  assert code == 1 && out.include?("local part me not permitted for github.com"),
         "CT", "a.md",
         "a person at that same domain is NOT admitted by the ssh-user row (exit=#{code}, out=#{out.inspect})"
end

puts
puts "CT — the domain allowlist is itself a gate:"

# ─── 32. a wildcard or non-hostname domain cell is refused by grammar ────────
["*.example.com", "*", "example"].each do |bad|
  with_repo("a.md" => "#{addr('someone', 'newdomain.io')}\n") do |root, al|
    out, _err, code = gate(root, al, "", domain_text: drow(bad, "*", TODAY, "fixture: catch-all attempt"))
    assert code == 1 && out.include?("FAIL allowlist #{bad}: domain row malformed (wildcard or not a hostname)"),
           "CT", bad,
           "a domain cell that is a wildcard or not a hostname is refused, so the list cannot be " \
           "turned into a blanket exemption by one character (exit=#{code}, out=#{out.inspect})"
  end
end

# ─── 33. an undated domain row fails, exactly as an undated identity row does ─
with_repo("a.md" => "#{addr('someone', 'newdomain.io')}\n") do |root, al|
  out, _err, code = gate(root, al, "", domain_text: drow("newdomain.io", "*", "yesterday", "fixture: undated"))
  assert code == 1 && out.include?("FAIL allowlist newdomain.io: undated or malformed row"),
         "CT", "newdomain.io",
         "a domain row without an ISO date fails (exit=#{code}, out=#{out.inspect})"
end

with_repo("a.md" => "#{addr('someone', 'newdomain.io')}\n") do |root, al|
  out, _err, code = gate(root, al, "", domain_text: "newdomain.io\t*\t#{TODAY}\n")
  assert code == 1 && out.include?("FAIL allowlist newdomain.io: undated or malformed row"),
         "CT", "newdomain.io",
         "a domain row with three cells instead of four fails as malformed (exit=#{code}, out=#{out.inspect})"
end

# ─── 34. a row matching no address anywhere is stale ─────────────────────────
with_repo("a.md" => "#{addr('someone', 'newdomain.io')}\n") do |root, al|
  text = drow("newdomain.io", "*", TODAY, "fixture: real") +
         drow("unused.org", "*", TODAY, "fixture: stale")
  out, _err, code = gate(root, al, "", domain_text: text)
  assert code == 1 &&
         out.include?("FAIL allowlist unused.org: entry matches nothing (no address on this domain in the tree)"),
         "CT", "unused.org",
         "a domain row that matches no address in the tree fails, so the list cannot rot into an " \
         "exemption (exit=#{code}, out=#{out.inspect})"
end

puts
puts "CT — D-68 the vars.* assertion:"

# The one file whose `vars.` reads are legitimate after D-56 deleted the repository
# variables, and how many lines it may carry. Frozen here, never derived from the gate.
VARS_ALLOW_REL = ".github/workflows/dependabot-automerge.yml"
VARS_ALLOW_N   = 3

def dependabot_yaml(n)
  (["name: dependabot automerge\non:\n  pull_request:\njobs:\n  merge:\n    if: >\n"] +
   Array.new(n) { |i| "      github.actor == 'dependabot[bot]' && vars.DEPENDABOT_AUTOMERGE == 'tier#{i}'\n" }).join
end

# ─── 35. a vars.* read in any other workflow fails, with file and line ───────
with_repo(VARS_ALLOW_REL => dependabot_yaml(VARS_ALLOW_N),
          ".github/workflows/w.yml" => "jobs:\n  a:\n    steps:\n      - run: echo ${{ vars.APP_NAME }}\n") do |root, al|
  out, _err, code = gate(root, al, "", domain_text: "")
  assert code == 1 && out.include?("FAIL vars .github/workflows/w.yml:4: reads vars.* outside the allowlist"),
         "CT", ".github/workflows/w.yml",
         "a vars.* read outside the frozen allowlist fails with its file and line " \
         "(exit=#{code}, out=#{out.inspect})"
end

# ─── 36. the allowlisted file passes at exactly its frozen count ─────────────
with_repo(VARS_ALLOW_REL => dependabot_yaml(VARS_ALLOW_N)) do |root, al|
  out, _err, code = gate(root, al, "", domain_text: "")
  assert code.zero? && out.include?("vars: #{VARS_ALLOW_N} reads, 0 unallowed"),
         "CT", VARS_ALLOW_REL,
         "the one allowlisted workflow passes at exactly #{VARS_ALLOW_N} reads " \
         "(exit=#{code}, out=#{out.inspect})"
end

# ─── 37. …and fails at any other count, in either direction ─────────────────
[[4, "found 4"], [2, "found 2"]].each do |n, tail|
  with_repo(VARS_ALLOW_REL => dependabot_yaml(n)) do |root, al|
    out, _err, code = gate(root, al, "", domain_text: "")
    assert code == 1 &&
           out.include?("FAIL vars #{VARS_ALLOW_REL}: expected #{VARS_ALLOW_N} vars.* line(s), #{tail}"),
           "CT", VARS_ALLOW_REL,
           "a count of #{n} fails against the frozen #{VARS_ALLOW_N} — a fourth dependency cannot be " \
           "added under cover of the allowlisted file (exit=#{code}, out=#{out.inspect})"
  end
end

# ─── 38. deleting the allowlisted file is a finding, not a green run ─────────
with_repo(".github/workflows/w.yml" => "jobs:\n  a:\n    steps:\n      - run: true\n") do |root, al|
  out, _err, code = gate(root, al, "", domain_text: "")
  assert code == 1 &&
         out.include?("FAIL vars #{VARS_ALLOW_REL}: expected #{VARS_ALLOW_N} vars.* line(s), found 0"),
         "CT", VARS_ALLOW_REL,
         "a tree that has workflows but has lost the allowlisted one fails rather than reporting zero " \
         "reads (exit=#{code}, out=#{out.inspect})"
end

# ─── 39. `vars.` outside .github/workflows/ is prose, not a read ─────────────
with_repo("docs/x.md" => "The workflows used to read vars.APP_NAME and vars.BUNDLE_ID.\n") do |root, al|
  out, _err, code = gate(root, al, "", domain_text: "")
  assert code.zero? && out.include?("vars: 0 reads, 0 unallowed"),
         "CT", "docs/x.md",
         "the vars scope is .github/workflows/ only — a doc quoting vars. is not a read " \
         "(exit=#{code}, out=#{out.inspect})"
end

# ─── 40. an address beside a © under an unset locale (UL-012) ───────────────
with_repo("e.md" => "© Indiagram\n#{addr('someone', 'newdomain.io')}\n") do |root, al|
  out, err, code = gate(root, al, "", domain_text: drow("newdomain.io", "*", TODAY, "fixture: any"),
                        env: NO_LOCALE)
  assert code.zero? && !err.include?("ArgumentError") && !err.include?("invalid byte"),
         "CT", "e.md",
         "an address on a © line scans without raising when LANG/LC_ALL/LC_CTYPE are unset " \
         "(exit=#{code}, out=#{out.inspect}, err=#{err.inspect})"
end

# ─── 41. the live tree, and the tracked domain allowlist ─────────────────────

puts
puts "CT — the live tree: pii and vars:"

DOMAIN_ALLOWLIST_REL = "tools/domain-allowlist.txt"
DOMAIN_ALLOWLIST     = File.join(ROOT, DOMAIN_ALLOWLIST_REL)
# A hostname, lower case, no wildcard. Frozen here rather than read out of the gate.
DOMAIN_RE            = /\A[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}\z/
# The org domain, and the ONE local part D-67 permits on it. Spelled as two cells, never
# as an address, for the reason given at `addr` above.
ORG_DOMAIN           = "indiagram.com"
ORG_LOCAL            = "maintainers"

# The lower bound exists so that "0 unallowed" cannot be produced by an enumeration
# that saw nothing — a green from a predicate that cannot see is the shape this file
# exists to refuse. It is a FLOOR, not a count: the exact figure belongs to the tree
# and moves whenever a file carrying addresses is added or removed.
#
# History, so the number is a dated measurement rather than a remembered one:
#   62  2026-09-02  original, when the bound was written as >= 40
#   35  2026-09-03  plan 05-12 deleted the rename self-check and its three shell
#                   harnesses; those files carried 31 of the tree's addresses —
#                   22 on the acme.com fixture domain, 4 on example.com, 3 on the
#                   github.com ssh-user row and 2 on the org domain. The acme.com
#                   row was REMOVED in the same commit, because after the deletion
#                   it matched nothing anywhere and a row matching nothing fails
#                   by design.
# Re-based to 30, which is below the measured 34 and far above the vacuous zero this
# assertion is about. Never raise it to the current measurement to "tighten" it: that
# turns a floor into a count nobody re-measures, and the counted assertions in this
# project live in tools/identity-allowlist.txt where they carry a date and a reason.
MIN_ADDRESSES_SEEN = 30

seen = real_out[/pii: (\d+) addresses seen, (\d+) unallowed/, 1].to_i
assert real_code.zero? && real_out.include?("addresses seen, 0 unallowed") &&
         seen >= MIN_ADDRESSES_SEEN,
       "CT", "-",
       "the gate is green on HEAD with 0 unallowed addresses, having actually seen some " \
       "(#{seen}, floor #{MIN_ADDRESSES_SEEN}) (exit=#{real_code}, out=#{real_out.inspect})"

assert real_out.include?("vars: #{VARS_ALLOW_N} reads, 0 unallowed"), "CT", "-",
       "HEAD carries exactly #{VARS_ALLOW_N} vars.* reads, all in the allowlisted workflow " \
       "(out=#{real_out.inspect})"

assert File.exist?(DOMAIN_ALLOWLIST), "CT", DOMAIN_ALLOWLIST_REL, "exists"

domain_rows = []
domain_bad  = []
if File.exist?(DOMAIN_ALLOWLIST)
  File.read(DOMAIN_ALLOWLIST, encoding: "UTF-8").each_line.with_index(1) do |line, n|
    line = line.chomp
    next if line.strip.empty? || line.start_with?("#")

    cells = line.split("\t", -1)
    if cells.length != 4 || cells.any? { |c| c.strip.empty? } || cells[2] !~ ISO_DATE
      domain_bad << "line #{n}: #{line.inspect}"
      next
    end
    domain_rows << { domain: cells[0], local: cells[1], date: cells[2], reason: cells[3], line: n }
  end
end

assert domain_bad.empty?, "CT", DOMAIN_ALLOWLIST_REL,
       "every data row is domain<TAB>local-part<TAB>ISO-date<TAB>reason" \
       "#{domain_bad.empty? ? '' : " — offending: #{domain_bad.join('; ')}"}"

nonhost = domain_rows.reject { |r| r[:domain] =~ DOMAIN_RE }.map { |r| r[:domain] }
assert nonhost.empty?, "CT", DOMAIN_ALLOWLIST_REL,
       "every domain cell is a lower-case hostname — no wildcard, no catch-all" \
       "#{nonhost.empty? ? '' : " — #{nonhost.join(', ')}"}"

starred = domain_rows.map { |r| r[:domain] }.select { |d| d.include?("*") }
assert starred.empty?, "CT", DOMAIN_ALLOWLIST_REL,
       "no domain cell contains `*`#{starred.empty? ? '' : " — #{starred.join(', ')}"}"

dupe_domains = domain_rows.map { |r| [r[:domain], r[:local]] }.tally.select { |_, n| n > 1 }.keys
assert dupe_domains.empty?, "CT", DOMAIN_ALLOWLIST_REL,
       "no domain/local-part pair appears twice" \
       "#{dupe_domains.empty? ? '' : " — #{dupe_domains.map(&:first).join(', ')}"}"

# D-67's line that must stay true: the org domain is admitted through ONE local part, the
# published contact. Any other row on it would re-admit the addresses IDENT-06 removed.
org = domain_rows.select { |r| r[:domain] == ORG_DOMAIN }
assert org.length == 1 && org.first[:local] == ORG_LOCAL, "CT", DOMAIN_ALLOWLIST_REL,
       "exactly one #{ORG_DOMAIN} row and its local part is the published contact " \
       "(found #{org.map { |r| r[:local] }.inspect})"

# ─── 42. the vars.* allowlist, re-measured here rather than asked of the gate ─
workflow_files = IO.popen(%w[git ls-files -z .github/workflows], chdir: ROOT, &:read)
                   .split("\0").reject(&:empty?)
assert workflow_files.include?(VARS_ALLOW_REL), "CT", VARS_ALLOW_REL, "is tracked"

vars_by_file = workflow_files.each_with_object({}) do |rel, acc|
  n = File.read(File.join(ROOT, rel), encoding: "UTF-8").each_line.count { |l| l.scrub("?").include?("vars.") }
  acc[rel] = n if n.positive?
end
assert vars_by_file == { VARS_ALLOW_REL => VARS_ALLOW_N }, "CT", "-",
       "measured independently: the only workflow reading vars.* is the allowlisted one, " \
       "with exactly #{VARS_ALLOW_N} lines (found #{vars_by_file.inspect})"

# ─── 43. the gate names the domain allowlist, and still requires nothing ─────
gate_text = File.read(GATE, encoding: "UTF-8")
assert gate_text.include?(DOMAIN_ALLOWLIST_REL), "CT", GATE_REL,
       "names #{DOMAIN_ALLOWLIST_REL} — the key link the plan's frontmatter asserts"
assert gate_text.include?(VARS_ALLOW_REL), "CT", GATE_REL,
       "names #{VARS_ALLOW_REL} — the one file whose vars.* reads are frozen"


# ═══════════════════════════════════════════════════════════════════════════════
# D-91 / D-92 — TEMPLATE IDENTITY WRITTEN AS PROSE (IDENT-15, criterion 7)
# ═══════════════════════════════════════════════════════════════════════════════
#
# LITERALS matches contiguous stems, so `fastlane/metadata/en-US/name.txt` carried the
# pre-Phase-3 display name — spelled with a space — through three phases of green identity
# gates. That is UL-044. The site was patched; the class is what these cases close.
#
# FIXTURE TERMS ARE BUILT, NEVER SPELLED, exactly as `addr` above builds fixture addresses
# and for exactly the same reason: THIS FILE IS TRACKED AND SWEPT BY THE GATE IT TESTS. A
# literal term here would be matched by the predicate under test, would need an allowlist
# row bought to keep the tree green, and would move this file's own dated count from 10.
# That trap has landed fourteen times in this project; the draft of the gate's own comment
# block hit it a fifteenth time and was caught by a mechanical sweep, not by reading. The
# terms below are therefore assembled from character arrays, the shape
# test/docs_structure_test.rb:698-700 uses and the gate itself now uses.
#
# ACCEPTED COST, stated: a reader cannot see which terms these are without running it.

def prose(words, separator = " ")
  words.map(&:join).join(separator)
end

# One qualifier+subject phrase per strict source, and the narrow pair term. Built, not spelled.
STRICT_SWIFT   = prose([%w[d e m o], %w[a p p]])
STRICT_CATALOG = prose([%w[b e t a], %w[v e r s i o n]])
STRICT_META    = prose([%w[t r i a l], %w[b u i l d]])
NARROW_SPACED  = prose([%w[s m o k e], %w[a p p]])
NARROW_HYPHEN  = prose([%w[s m o k e], %w[a p p]], "-")
# A word that is a 2.2 noun on its own but NOT a term, because it qualifies nothing. This
# is the "Use an example" case (06-RESEARCH Open Question 5) and the HTML-entity Greek
# letter case, both of which occur legitimately in app/Shared today.
BARE_NOUN      = prose([%w[e x a m p l e]])
# And the IDENTIFIER-shaped template stem, built for a second and sharper reason: this
# file carries a dated row in tools/identity-allowlist.txt whose COUNT is the number of
# its lines matching LITERALS. Spelling one more moves that count, and the gate caught
# exactly that during this plan's own execution — `expected 10 line(s), found 11` — which
# is D-65's counted rows doing the job they were added for, on the executor who added
# them. The fixture file the gate reads still contains the literal; this source does not.
IDENT_LITERAL  = %w[S m o k e A p p].join

# The four strict sources, named exactly as the gate names them on its summary lines.
PROSE_SOURCES = %w[catalog plist-inputs app-shared store-metadata].freeze

# A fixture tree carrying one tracked file in EACH of the four strict sources. Without
# this, a case about one source would be confounded by the population-empty rule firing
# for the other three, and the assertion would pass for the wrong reason.
def strict_tree(extra = {})
  {
    "app/Shared/App.swift"             => "// nothing interesting\n",
    "app/Shared/Localizable.xcstrings" => "{ \"strings\" : { } }\n",
    "app/project.yml"                  => "name: App\n",
    "fastlane/metadata/en-US/name.txt" => "A Real Product Name\n",
  }.merge(extra)
end

puts
puts "CT — D-91/D-92 the prose population: template identity written as prose:"

# ─── P1. the strict population is clean and reports each source separately ───
with_repo(strict_tree) do |root, al|
  out, _err, code = gate(root, al, "")
  # Guarded enumeration: an .each over an empty list asserts nothing (.continue-here.md
  # blocking row 9). Assert the collection is non-empty and print its size FIRST.
  assert PROSE_SOURCES.size == 4, "CT", "-",
         "the fixture knows all #{PROSE_SOURCES.size} strict source names (#{PROSE_SOURCES.join(', ')})"
  missing = PROSE_SOURCES.reject { |s| out.include?("prose_strict: #{s} 1 files, 0 hits") }
  assert code.zero? && missing.empty?, "CT", "-",
         "a clean strict tree exits 0 and prints ALL FOUR sources with their own counts — " \
         "never a union#{missing.empty? ? '' : " — missing: #{missing.join(', ')}"} " \
         "(exit=#{code}, out=#{out.inspect})"
  assert out.include?("prose_narrow: 0 files, 0 hits") && out.include?("prose_excluded=0"),
         "CT", "-",
         "the narrow population and the exclusion count are printed too (out=#{out.inspect})"
end

# ─── P2. control prose-strict-swift: a term in an app/Shared/ Swift string ───
with_repo(strict_tree("app/Shared/Views/RootView.swift" =>
                      "import SwiftUI\nlet s = \"This #{STRICT_SWIFT} does nothing\"\n")) do |root, al|
  out, _err, code = gate(root, al, "")
  assert code == 1 &&
           out.include?("FAIL prose app/Shared/Views/RootView.swift:2: #{STRICT_SWIFT} — " \
                        "template identity as prose in the app-shared source"),
         "CT", "app/Shared/Views/RootView.swift",
         "a prose term in an app/Shared/ Swift string fails, NAMING the term and the source " \
         "(exit=#{code}, out=#{out.inspect})"
  assert out.include?("prose_strict: app-shared 2 files, 1 hits"), "CT", "-",
         "and the app-shared source's own hit count moves to 1 (out=#{out.inspect})"
end

# ─── P3. control prose-strict-catalog: the same union, a DIFFERENT source ────
# The point of a second case is not a second term: it is that the catalog is attributed to
# its OWN source, so a per-source count can show which half of the union went quiet.
with_repo(strict_tree("app/Shared/Localizable.xcstrings" =>
                      "{ \"strings\" : { \"k\" : \"#{STRICT_CATALOG}\" } }\n")) do |root, al|
  out, _err, code = gate(root, al, "")
  assert code == 1 &&
           out.include?("FAIL prose app/Shared/Localizable.xcstrings:1: #{STRICT_CATALOG} — " \
                        "template identity as prose in the catalog source"),
         "CT", "app/Shared/Localizable.xcstrings",
         "a prose term in the string catalog fails and is attributed to the CATALOG source, " \
         "not to app-shared, even though it lives under app/Shared/ (exit=#{code}, out=#{out.inspect})"
  assert out.include?("prose_strict: catalog 1 files, 1 hits") &&
           out.include?("prose_strict: app-shared 1 files, 0 hits"),
         "CT", "-",
         "each source's contribution is its own number (out=#{out.inspect})"
end

# ─── P4. the store metadata source — UL-044's own population ─────────────────
with_repo(strict_tree("fastlane/metadata/en-US/subtitle.txt" => "A #{STRICT_META}\n")) do |root, al|
  out, _err, code = gate(root, al, "")
  assert code == 1 &&
           out.include?("FAIL prose fastlane/metadata/en-US/subtitle.txt:1: #{STRICT_META} — " \
                        "template identity as prose in the store-metadata source"),
         "CT", "fastlane/metadata/en-US/subtitle.txt",
         "App Store metadata is in the strict population — the file class UL-044 was found in, " \
         "which no rendered-string check would ever see (exit=#{code}, out=#{out.inspect})"
end

# ─── P5. control prose-narrow-tree: the spaced display name OUTSIDE app/ ─────
with_repo(strict_tree("docs/SOMETHING.md" => "The #{NARROW_SPACED} was renamed.\n")) do |root, al|
  out, _err, code = gate(root, al, "")
  assert code == 1 &&
           out.include?("FAIL prose docs/SOMETHING.md:1: #{NARROW_SPACED} — the template " \
                        "identity as prose, and docs/SOMETHING.md carries no allowlist row"),
         "CT", "docs/SOMETHING.md",
         "the narrow list runs tree-wide, so the spaced display name fails in a file that is " \
         "in no strict source at all (exit=#{code}, out=#{out.inspect})"
end

# ─── P6. the hyphen is not a hiding place ────────────────────────────────────
with_repo(strict_tree("docs/SOMETHING.md" => "The #{NARROW_HYPHEN} was renamed.\n")) do |root, al|
  out, _err, code = gate(root, al, "")
  assert code == 1 && out.include?("FAIL prose docs/SOMETHING.md:1: #{NARROW_HYPHEN}"),
         "CT", "docs/SOMETHING.md",
         "a hyphen reads to App Review exactly as a space does and is matched too " \
         "(exit=#{code}, out=#{out.inspect})"
end

# ─── P7. a dated row is the ONLY way to buy a narrow occurrence ──────────────
# The same instrument as the identifier half: one list, one date, one reason. This is what
# keeps CHANGELOG.md, docs/UPSTREAM-LEDGER.md and the ASC fixture green on the real tree
# without a second exemption surface being invented for prose.
with_repo(strict_tree("docs/SOMETHING.md" =>
                      "The #{NARROW_SPACED} was renamed.\n#{IDENT_LITERAL}\n")) do |root, al|
  out, _err, code = gate(root, al, row("docs/SOMETHING.md", 1, "2026-09-05",
                                       "historical record: names what the fork was called"))
  assert code.zero? && !out.include?("FAIL prose"), "CT", "docs/SOMETHING.md",
         "a path carrying a dated, counted, reasoned row may mention it as prose too " \
         "(exit=#{code}, out=#{out.inspect})"
end

# ─── P8. CONTROL prose-scope-empty — THE ONE MOST LIKELY TO BE SKIPPED ───────
# A population that has gone empty is NOT a clean tree. Without this the gate can silently
# stop looking: rename a directory and a union reports the same reassuring zero it reports
# when the tree is genuinely clean.
EMPTY_SOURCE_CASES = {
  "store-metadata" => "fastlane/metadata/en-US/name.txt",
  "catalog"        => "app/Shared/Localizable.xcstrings",
  "plist-inputs"   => "app/project.yml",
}.freeze
assert EMPTY_SOURCE_CASES.size == 3, "CT", "-",
       "the empty-source enumeration has #{EMPTY_SOURCE_CASES.size} cases to run — an .each " \
       "over an empty collection would assert nothing"
EMPTY_SOURCE_CASES.each do |source, path|
  with_repo(strict_tree.reject { |rel, _| rel == path }) do |root, al|
    out, _err, code = gate(root, al, "")
    assert code == 1 &&
             out.include?("FAIL prose #{source}: strict source matched no tracked file — " \
                          "the population went empty, which is not a clean tree") &&
             out.include?("prose_strict: #{source} 0 files, 0 hits"),
           "CT", path,
           "removing the last tracked file of the #{source} source FAILS rather than reading " \
           "as clean, and the source reports 0 files on its own line (exit=#{code}, out=#{out.inspect})"
  end
end

# ─── P9. the emptiness rule is scoped, so it cannot fire on a tree with no app ─
# The workflows_present analogue, asserted rather than assumed: this is precisely why the
# twenty-odd fixture cases above — none of which has an app/ directory — are still green.
with_repo("a.txt" => NO_HITS) do |root, al|
  out, _err, code = gate(root, al, "")
  assert code.zero? && !out.include?("FAIL prose"), "CT", "-",
         "a fixture repository with no app/ at all is not an application that went missing, " \
         "so the emptiness rule stays silent (exit=#{code}, out=#{out.inspect})"
  assert out.include?("prose_excluded=1"), "CT", "-",
         "and its one file is counted as excluded — a number that moves when a file is " \
         "added (out=#{out.inspect})"
end

# ─── P10. a bare 2.2 noun qualifying nothing is NOT a term ───────────────────
# Open Question 5, asserted rather than remembered. The UI-SPEC ships "Use an example" and
# the HTML entity table ships the Greek letter; a bare-noun list would go red on the app's
# own primary empty-state affordance and on its own entity table.
with_repo(strict_tree("app/Shared/Views/InputArea.swift" =>
                      "let hint = \"Use an #{BARE_NOUN}\"\n")) do |root, al|
  out, _err, code = gate(root, al, "")
  assert code.zero? && !out.include?("FAIL prose"), "CT", "app/Shared/Views/InputArea.swift",
         "a 2.2 noun that qualifies no subject is not a term — the app's own empty-state " \
         "affordance stays green (exit=#{code}, out=#{out.inspect})"
end

# ─── P11. the two standing constraints, re-confirmed AFTER the prose extension ─
# They already existed (C-26 and the zero-require rule). What is new is that the prose half
# must not have moved either: G-2 says the rewritten app/Shared must be green ON THE GATE,
# not allowlisted into green, and G-1 is what review-notes.yml's bundler-cache: false rests
# on. Re-measured here from the files rather than restated.
prose_shipped = allowlist_rows.map { |r| r[:path] }.select { |p| p.start_with?("app/") }
assert prose_shipped.empty?, "CT", ALLOWLIST_REL,
       "the prose extension bought NO row under app/ — the strict population is green on " \
       "its own merits (C-26)#{prose_shipped.empty? ? '' : " — #{prose_shipped.join(', ')}"}"

prose_gate_requires = File.read(GATE, encoding: "UTF-8").lines.grep(/\A\s*require\b/)
assert prose_gate_requires.empty?, "CT", GATE_REL,
       "and it added no require line, so bundler-cache: false still holds" \
       "#{prose_gate_requires.empty? ? '' : " — #{prose_gate_requires.map(&:strip).join('; ')}"}"

# ─── P12. D-92 on the real files: no term is spelled in either of them ───────
# Measured, not asserted by reading. Both files are admitted by counted rows, so a spelled
# term would move a count AND satisfy the predicate it configures.
D92_FILES = [GATE_REL, "test/contamination_test.rb"].freeze
assert D92_FILES.size == 2, "CT", "-",
       "the D-92 sweep has #{D92_FILES.size} files to read"
D92_TERMS = [prose([%w[d e m o], %w[a p p]]), prose([%w[b e t a], %w[v e r s i o n]]),
             prose([%w[t r i a l], %w[b u i l d]]), prose([%w[s m o k e], %w[a p p]]),
             prose([%w[s m o k e], %w[a p p]], "-"), prose([%w[s m o k e], %w[t e s t]]),
             prose([%w[h e l l o], %w[a p p]]), prose([%w[c o m i n g], %w[s o o n]])].freeze
assert D92_TERMS.size == 8, "CT", "-",
       "and #{D92_TERMS.size} built terms to look for — a sweep over an empty term list " \
       "would pass without having looked"
D92_FILES.each do |rel|
  spelled = []
  File.read(File.join(ROOT, rel), encoding: "UTF-8").each_line.with_index(1) do |line, n|
    down = line.scrub("?").downcase
    D92_TERMS.each { |t| spelled << "#{n}:#{t}" if down.include?(t) }
  end
  assert spelled.empty?, "CT", rel,
         "spells none of the #{D92_TERMS.size} prose terms it configures — D-92, the " \
         "fifteen-times trap#{spelled.empty? ? '' : " — #{spelled.join(', ')}"}"
end

# ─── P13. the real tree: the gate is green, and it actually LOOKED ───────────
# A summary line of all zeros is what a gate prints when it is working and also what it
# prints when it has stopped drawing from a source. So the file counts are asserted
# positive, per source, by name.
prose_out, _prose_err, prose_status = Open3.capture3(RbConfig.ruby, GATE, chdir: ROOT)
prose_code = prose_status.exitstatus
assert prose_code.zero? && !prose_out.include?("FAIL prose"), "CT", "-",
       "HEAD is green on the prose populations (exit=#{prose_code}, out=#{prose_out.inspect})"
empty_on_head = PROSE_SOURCES.reject do |s|
  files_seen = prose_out[/prose_strict: #{Regexp.escape(s)} (\d+) files/, 1].to_i
  files_seen.positive?
end
assert empty_on_head.empty?, "CT", "-",
       "and every one of the four strict sources scanned at least one tracked file on HEAD" \
       "#{empty_on_head.empty? ? '' : " — EMPTY: #{empty_on_head.join(', ')}"} " \
       "(out=#{prose_out.inspect})"
assert prose_out.include?("prose_narrow:") && prose_out =~ /^prose_excluded=\d+$/,
       "CT", "-",
       "the narrow line and the exclusion count are printed on HEAD too (out=#{prose_out.inspect})"

verdict!
