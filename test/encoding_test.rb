#!/usr/bin/env ruby
# frozen_string_literal: true

# The sweep gate for the locale-inheritance class (UL-048; gap GAP-05-01).
#
# WHY THIS EXISTS
#
# Ruby decides the encoding of a file it reads from the environment. With LANG
# and LC_ALL unset, Encoding.default_external is US-ASCII on both pinned
# interpreters (3.3.12 and 4.0.6, both re-measured 2026-09-04), so a read with
# no explicit encoding hands back a String tagged US-ASCII whose bytes are not.
# The read itself is silent. The next `strip`, the next concatenation, or the
# next regex raises -- ArgumentError or Encoding::CompatibilityError -- and the
# caller gets a backtrace where a named refusal belonged.
#
# This repository has now produced FOUR instances of that one defect:
#
#   1. tools/gen-review-notes.rb, fixed in commit 3b1efb9 (UL-012).
#   2. Bootstrap::Config.parse, fixed by plan 05-09, which killed both
#      `make doctor` and `make bootstrap-fork` for every forker whose locale was
#      unset, because the example dotenv the template tells forkers to copy
#      carries 52 lines of non-ASCII itself.
#   3. bin/lib/bootstrap.rb's metadata scan, which is what fixing (2) EXPOSED:
#      execution finally got far enough to reach it. UAT found it killing
#      `make doctor` at the metadata-scanning step on a fresh clone.
#   4. bin/adopt.rb's dotenv parse -- the same shape as (2), in a second file,
#      never swept. `make adopt` exists to stop a forker clobbering a live App
#      Store listing, and the crash landed BEFORE all three of its own guards.
#
# Three one-site fixes did not hold. So this file does not check two sites; it
# demands a stated verdict for EVERY read of a file in the tracked tree. An
# unclassified site is the fifth instance waiting.
#
# HOW IT AVOIDS TURNING ITSELF GREEN
#
# A scanner whose subject is the syntax its own source would have to contain is
# the sharpest possible instance of a hazard that hit six consecutive plans in
# this phase: writing a literal into a file that another gate sweeps turns that
# gate green by existing. So every pattern below is ASSEMBLED FROM FRAGMENTS at
# runtime and no call form is ever spelled out here -- not in code, not in a
# comment, not in an exemption reason. There is NO self-exclusion entry: this
# file is enumerated exactly like every other, and group E5 MEASURES that it
# yields zero candidates. Self-exclusion is a permanent hole; measurement is not.
#
# FAILURE-LINE CONTRACT -- do not change the shape. Negative controls grep it.
# One line per failure, no leading whitespace:
#
#     FAIL <group> <path>: <message>
#
#   E1  every candidate call site carries a verdict
#   E2  every exemption still matches exactly one real site
#   E3  non-vacuity: the enumeration and the candidate set are not empty
#   E4  the dynamic discriminator: real code, real bytes, locale cleared
#   E5  this file yields no candidates, and does so without excluding itself
#
# DEPENDENCIES: Ruby core only, zero require-family lines. The `review notes`
# job runs it with bundler-cache disabled, so a gem here would break that job.

ROOT = File.expand_path("..", __dir__)

# --- fragments -----------------------------------------------------------
# Nothing below is ever written as a whole token. `RECEIVER + SEP + VERB + OPEN`
# is only ever composed at runtime, which is what keeps this file out of its own
# candidate set for a reason that can be measured rather than asserted.
SEP   = "."
OPEN  = "("
UTF8  = "UTF" + "-8"
ENC_K = "encod" + "ing"

RECEIVERS   = %w[File IO].freeze
TEXT_VERBS  = %w[read readlines foreach open].freeze
BIN_VERBS   = %w[binread binreadlines].freeze
STREAM_VERB = %w[each line].join("_")

def call_forms(verbs)
  RECEIVERS.product(verbs).map { |recv, verb| recv + SEP + verb + OPEN }
end

TEXT_CALLS   = call_forms(TEXT_VERBS).freeze
BIN_CALLS    = call_forms(BIN_VERBS).freeze
STREAM_CALL  = (SEP + STREAM_VERB).freeze
ENC_ARGUMENT = (ENC_K + ":").freeze
# A mode string that names an encoding after a colon, e.g. the read mode plus
# ":UTF-8". Assembled, never spelled.
MODE_WITH_ENC = /["'][rwa][b+]*:[A-Za-z0-9_-]+/.freeze
MODE_BINARY   = /["'][rwa][+]*b[+]*["']/.freeze
MODE_WRITE    = /["'][wa][b+]*["']/.freeze

# --- the private reader --------------------------------------------------
# This gate must itself read files, and it must do so without spelling a call
# form. `File.method(:...)` produces the same Method object the literal call
# would, so the behaviour is identical and the source text is not a match.
READER = File.method(("op" + "en").to_sym)

def slurp(abs)
  READER.call(abs, "r:" + UTF8, &:read)
end

# --- assertions ----------------------------------------------------------
@checks   = 0
@failures = 0

def assert(condition, group, path, label)
  @checks += 1
  if condition
    puts "  ok #{group} #{path}: #{label}"
  else
    # One line, always. A message that put the group on one line and the path on
    # another would make every control that greps `^FAIL E1 bin/adopt.rb` vacuous,
    # which is the defect this whole phase exists to avoid.
    puts "FAIL #{group} #{path}: #{label.to_s.gsub(/\s*\n\s*/, ' ')}"
    @failures += 1
  end
end

def no_verdict(message)
  # Refusing a verdict is not the same as passing. Exit 2, never 0.
  puts "FAIL E3 -: cannot run -- #{message}"
  puts
  puts "encoding gate CANNOT RUN: #{message}"
  exit 2
end

# --- the exemption table -------------------------------------------------
# Keyed by path plus a CONTENT ANCHOR, never by line number: a line number goes
# stale the moment anything above it moves, and a stale key silently stops
# matching, which is a hole rather than a failure. Group E2 asserts every entry
# matches EXACTLY ONE candidate in the current tree -- zero is stale, more than
# one is ambiguous, and both are failures.
#
# Every reason below was MEASURED, not reasoned about. The measurements live in
# .planning evidence for plan 05-18.
EXEMPTIONS = [
  {
    path:   "bin/lib/bootstrap.rb",
    anchor: "out_err",
    reason: "Not a file read. This iterates the combined-output handle yielded by " \
            "Open3.popen2e, so the encoding comes from the child spawn rather than " \
            "from a path on disk and no encoding argument is accepted here. Measured " \
            "2026-09-04 under a cleared locale on 3.3.12 and 4.0.6: the iteration, the " \
            "echo to the caller's IO and the append to the capture buffer all complete " \
            "without raising. NOTE, recorded rather than fixed here: the buffer it " \
            "returns is tagged US-ASCII and reports valid_encoding? false, so a caller " \
            "that later matches a regex against it would raise. That is a separate " \
            "defect about process output, not about reading a tracked file."
  },
  {
    path:   "tools/check-contamination.rb",
    anchor: "allowlist_text",
    reason: "Iterates a String that was already read from disk with an explicit " \
            "encoding a few lines above, so the encoding is pinned upstream of this " \
            "line and pinning again is impossible. This is why the orchestrator " \
            "measured this whole file exiting 0 with the locale cleared."
  },
  {
    path:   "tools/check-contamination.rb",
    anchor: "domain_text",
    reason: "Same shape as the allowlist entry above: the String was read with an " \
            "explicit encoding upstream of this line."
  },
  {
    path:   "tools/gitleaks.rb",
    anchor: "reader",
    reason: "Not a file read. This iterates the read end of an IO.pipe carrying a " \
            "child process's interleaved output. Every line is passed through the " \
            "file's own utf8() helper on the very next line, which force-encodes and " \
            "scrubs before the line is appended, printed or matched -- that helper IS " \
            "the pin, and it is on the path of every single line, verified by reading " \
            "the loop body rather than by assuming it."
  },
  {
    path:   "tools/identity-parity.rb",
    anchor: "stdout]",
    reason: "Not a file read. This iterates a String captured from a generator's " \
            "standard output; there is no path and no encoding argument to give. " \
            "Measured 2026-09-04 under a cleared locale on both interpreters: " \
            "iterating it and interpolating each line into the log message completes " \
            "without raising."
  },
  {
    path:   "tools/identity-parity.rb",
    anchor: "stderr]",
    reason: "Same as the standard-output entry above, for the error stream."
  },
  {
    path:   "test/sh_stream_test.rb",
    anchor: "body",
    reason: "The subject under test is stream buffering, and this test writes the " \
            "bytes it later reads back into its own temporary file, so it controls " \
            "them and they are pure ASCII. Pinning here would change what is being " \
            "measured rather than fix anything."
  },
  {
    path:   "test/sh_stream_test.rb",
    anchor: "mid_run",
    reason: "Same temporary file, same test-controlled ASCII bytes, mid-run assertion."
  },
  {
    path:   "test/sh_stream_test.rb",
    anchor: "empty?",
    reason: "Same temporary file, same test-controlled ASCII bytes; this is the " \
            "control assertion proving the redirect assertions discriminate."
  },
  {
    path:   "tools/gen-html-entities.rb",
    anchor: "swift_source",
    reason: "Not a file read. This iterates a String the caller already pulled off " \
            "disk with an explicit encoding a few lines above, so the encoding is " \
            "pinned upstream of this line and pinning again is impossible -- the " \
            "same shape as the two check-contamination.rb entries. There is a " \
            "second, stronger reason here: the subject is a GENERATED Swift table " \
            "whose every scalar is a backslash-u escape, and the very same method " \
            "that produced this String asserts byte by byte that it holds nothing " \
            "above 0x7F before this line runs. An all-ASCII String cannot raise on " \
            "the locale. Measured 2026-09-04 on 3.3.12 and 4.0.6 with LC_ALL, LANG " \
            "and LC_CTYPE all cleared: the generator reports EXT=US-ASCII and its " \
            "--check still exits 0 over both tracked tables."
  }
].freeze

# --- enumeration ---------------------------------------------------------
# git ls-files, as an argv array through IO.popen -- never a shell string, and
# never a shell `git grep`, because quoting has silently changed a candidate set
# in this project before. An exit code other than zero, or an empty list, is a
# reason to refuse a verdict rather than to report a clean tree.
listing = begin
  IO.popen(%w[git ls-files -z], chdir: ROOT, err: File::NULL, &:read)
rescue SystemCallError => e
  no_verdict("git ls-files could not run in #{ROOT}: #{e.message}")
end
no_verdict("git ls-files exited #{$?&.exitstatus.inspect} in #{ROOT}") unless $?&.success?

tracked = listing.to_s.split("\0").reject(&:empty?).sort
no_verdict("git ls-files listed no tracked files in #{ROOT}") if tracked.empty?

RUBYISH = ->(rel) { rel.end_with?(".rb") || rel == "fastlane/Fastfile" }
scanned = tracked.select { |rel| RUBYISH.call(rel) }

# --- the candidate scan --------------------------------------------------
Candidate = Struct.new(:rel, :line_no, :text)

candidates = []
unreadable = []
scanned.each do |rel|
  abs = File.join(ROOT, rel)
  next unless File.file?(abs)

  content = begin
    slurp(abs)
  rescue SystemCallError => e
    unreadable << [rel, e.message]
    next
  end

  content.lines.each_with_index do |text, idx|
    hit = TEXT_CALLS.any? { |form| text.include?(form) } ||
          BIN_CALLS.any?  { |form| text.include?(form) } ||
          text.include?(STREAM_CALL)
    candidates << Candidate.new(rel, idx + 1, text.chomp) if hit
  end
end

# --- E3: non-vacuity, BEFORE any iteration over the collections ----------
# An `each` over an empty collection asserts nothing and reports success; that
# is one of the recorded ways a result has lied in this phase, and it is why
# these four assertions come first rather than last.
assert scanned.length >= 20, "E3", "-",
       "the enumeration found #{scanned.length} Ruby-ish tracked files (floor 20); " \
       "an empty or tiny enumeration would make every assertion below vacuous"
assert candidates.length >= 15, "E3", "-",
       "the scan found #{candidates.length} candidate call sites (floor 15); a scan " \
       "that found none would pass silently while checking nothing"
%w[bin/lib/bootstrap.rb bin/adopt.rb fastlane/Fastfile test/encoding_test.rb].each do |known|
  assert scanned.include?(known), "E3", known,
         "known-positive path is present in the enumeration; if it were absent, a " \
         "clean result about it would mean only that nobody looked"
end
assert candidates.any? { |c| c.rel == "bin/lib/bootstrap.rb" }, "E3", "bin/lib/bootstrap.rb",
       "the file carrying two of the four recorded instances yields at least one " \
       "candidate; zero would mean the patterns stopped matching reality"
assert unreadable.empty?, "E3", "-",
       "every enumerated file was readable (#{unreadable.map(&:first).join(', ')})"

# --- E2: exemption integrity, before they are trusted as verdicts --------
exempt_lines = {}
EXEMPTIONS.each do |entry|
  matches = candidates.select { |c| c.rel == entry[:path] && c.text.include?(entry[:anchor]) }
  assert matches.length == 1, "E2", entry[:path],
         "exemption anchored on '#{entry[:anchor]}' matches exactly one candidate " \
         "(found #{matches.length}); zero means the exemption is STALE and has become a " \
         "silent hole, more than one means it is ambiguous and covers a site nobody read"
  assert !entry[:reason].to_s.strip.empty?, "E2", entry[:path],
         "exemption anchored on '#{entry[:anchor]}' carries a written reason"
  matches.each { |m| exempt_lines[[m.rel, m.line_no]] = entry }
end

# --- E1: every candidate carries a verdict -------------------------------
candidates.each do |c|
  verdict =
    if exempt_lines.key?([c.rel, c.line_no])
      "exempt"
    elsif BIN_CALLS.any? { |form| c.text.include?(form) } || c.text.match?(MODE_BINARY)
      "binary"
    elsif c.text.include?(ENC_ARGUMENT) || c.text.match?(MODE_WITH_ENC)
      "pinned"
    elsif c.text.match?(MODE_WRITE)
      # UL-048's 2026-09-03 append: measured on both interpreters with the locale
      # fully cleared, the WRITE side does not raise -- Ruby does not transcode a
      # String to the default external encoding on the way out. The falsifiable
      # half of this class is the read.
      "write"
    end

  assert !verdict.nil?, "E1", c.rel,
         verdict ? "line #{c.line_no} carries the verdict #{verdict}" :
         "line #{c.line_no} reads a file with the encoding inherited from the " \
         "environment and no stated verdict. With the locale unset that String is " \
         "tagged US-ASCII and the next strip, concatenation or regex raises. Give the " \
         "call an explicit encoding, use the binary form for key material, or add an " \
         "EXEMPTIONS entry in test/encoding_test.rb with a measured reason: #{c.text.strip}"
end

# --- E5: this file is scanned, and yields nothing, without excluding itself
own = candidates.select { |c| c.rel == "test/encoding_test.rb" }
assert own.empty?, "E5", "test/encoding_test.rb",
       "the gate's own source yields zero candidates (found #{own.length}: " \
       "#{own.map(&:line_no).join(', ')}). It is enumerated like every other file and " \
       "there is no self-exclusion entry anywhere in this file; it is clean because " \
       "every pattern is composed from fragments at runtime and no call form is ever " \
       "spelled out. A scanner that had to exclude itself would carry a permanent hole"
assert EXEMPTIONS.none? { |e| e[:path] == "test/encoding_test.rb" }, "E5", "test/encoding_test.rb",
       "there is no exemption entry for this file, so E5 above is a measurement rather " \
       "than a consequence of opting out"

# --- E4: the dynamic discriminator ---------------------------------------
# Source text is not behaviour. This spawns a locale-cleared child that loads the
# real bootstrap library and runs the REAL metadata-scanning step against the
# REAL tracked copyright file, which carries U+00A9 as the bytes c2 a9. That
# needs no dotenv, no secret and no Xcode, so it is safe in a bare clone -- which
# is the point, because the required context runs on a bare clone.
#
# The child rescues Exception and prints a sentinel either way, so a LoadError or
# a missing file surfaces as a named failure instead of as an exception with zero
# FAIL lines -- the crash-as-detection lie, which is especially easy to walk into
# here because the subject of this whole gate IS a crash.
child_script = <<~CHILD
  puts "EXT=" + Encoding.default_external.to_s
  begin
    require File.expand_path("bin/lib/bootstrap.rb", Dir.pwd)
    Bootstrap::ScanMetadata.new(nil).check
    puts "SCAN=ok"
  rescue Exception => e
    puts "SCAN=raised " + e.class.to_s + ": " + e.message.lines.first.to_s.strip
  end
CHILD

ruby_bin = File.join(RbConfig::CONFIG["bindir"], RbConfig::CONFIG["ruby_install_name"])
cleared  = { "LANG" => nil, "LC_ALL" => nil, "LC_CTYPE" => nil }
child_out = begin
  IO.popen([cleared, ruby_bin, "-e", child_script], chdir: ROOT, err: [:child, :out], &:read).to_s
rescue SystemCallError => e
  "SPAWN_FAILED #{e.message}"
end

ext_line = child_out.lines.find { |l| l.start_with?("EXT=") }.to_s.strip
scan_line = child_out.lines.find { |l| l.start_with?("SCAN=") }.to_s.strip

# Assert the discriminator is LIVE before asserting the result. On a machine
# whose Ruby reports UTF-8 with the locale cleared, "it did not raise" would be
# trivially true, which is the first recorded way a result has lied here.
discriminator_live = ext_line == "EXT=US-ASCII"
assert discriminator_live, "E4", "-",
       "the locale-cleared child reports #{ext_line.empty? ? '(no EXT line at all)' : ext_line}, " \
       "and the whole discriminator is only meaningful when that is US-ASCII; anything " \
       "else means this assertion proves nothing and must be repaired, not believed"
assert !scan_line.empty?, "E4", "-",
       "the locale-cleared child produced a SCAN verdict line (got: " \
       "#{child_out.strip.lines.last.to_s.strip.inspect}); no verdict means the child " \
       "died before reporting and a silent pass here would be exactly the crash-as-" \
       "detection failure this gate exists to catch"
if discriminator_live && !scan_line.empty?
  assert scan_line == "SCAN=ok", "E4", "bin/lib/bootstrap.rb",
         "with LANG, LC_ALL and LC_CTYPE all cleared, the real metadata-scanning step " \
         "reads the real tracked copyright file and completes: #{scan_line}"
end

# --- verdict -------------------------------------------------------------
puts
puts "candidates=#{candidates.length} files=#{scanned.length} exemptions=#{EXEMPTIONS.length}"
if @failures.zero?
  puts "All #{@checks} encoding assertions passed."
  exit 0
else
  puts "#{@failures} of #{@checks} encoding assertion(s) failed."
  exit 1
end
