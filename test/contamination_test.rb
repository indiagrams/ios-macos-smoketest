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
#   fastlane/Fastfile's adopt_existing_app guard; ci/test-rename*.sh), docs describing the
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
def gate(root, allowlist_path, allowlist_text = nil, env: {}, extra: [])
  File.write(allowlist_path, allowlist_text) unless allowlist_text.nil?
  argv = [RbConfig.ruby, GATE, "--root", root, "--allowlist", allowlist_path] + extra
  out, err, status = Open3.capture3(env, *argv, chdir: ROOT)
  [out.to_s, err.to_s, status.exitstatus]
end

def row(path, count, date, reason)
  "#{path}\t#{count}\t#{date}\t#{reason}\n"
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

verdict!
