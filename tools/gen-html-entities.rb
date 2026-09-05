#!/usr/bin/env ruby
# frozen_string_literal: true

# Generate app/Shared/Engine/HTMLEntityTableA.swift and HTMLEntityTableB.swift
# from the WHATWG named-character-reference table — or, with --check, assert the
# properties of the two tracked files without fetching anything.
#
# WHY THIS EXISTS
#
# APP-03's decoder needs all 2125 semicolon-terminated named references. A table
# that large is not something a human maintains by hand and not something a
# reviewer can diff usefully if it is fetched at runtime, so it is GENERATED and
# TRACKED: the output is reviewable, the input is a stated source of truth, and
# regenerating it is one command. tools/gen-review-notes.rb is the analog and
# this file copies its discipline deliberately — frozen constants, an argv case
# that rejects unknown flags, no broad rescue, UTF-8 pinned on every read.
#
# THE PACKING FORMAT, AND THE MEASURED DEFECT IT EXISTS TO AVOID
#
# The obvious pack is "NAME=TARGET;NAME=TARGET;...". It silently loses SIX
# records, because three entity TARGETS are the delimiter characters:
#
#     &equals;  -> U+003D            &semi;  -> U+003B
#     &bne;     -> U+003D U+20E5
#
# Escaping them at generation time does not help: \u{3B} resolves to a literal
# ';' at runtime, before the parser splits. Measured: 2125 records in, 2119 out,
# with a green compile and no warning anywhere. So the record delimiter is
# U+0001 and the field delimiter is U+0002. The MINIMUM target codepoint in the
# whole table is U+0009 (&Tab;) and the minimum name character is a letter, so
# neither delimiter can occur in the data by construction.
#
# A format argument is not a guarantee, so --check PARSES the emitted table with
# the same splitting rule the Swift side uses and asserts the count. A count
# assertion is the only thing that catches this class; a compile does not.
#
# WHY EVERY SCALAR IS A \u{...} ESCAPE
#
# 17 entities target invisible or format characters (&ZeroWidthSpace; U+200B,
# &zwnj; U+200C, &InvisibleTimes;, &NoBreak; and 13 more). Written as literal
# characters they produce 6 `invisible_character` errors under this repo's own
# `swiftlint --strict`. Every target scalar is therefore emitted as an escape and
# the generated files are pure ASCII — a property --check re-measures byte by
# byte rather than trusting.
#
# WHY THE LEGACY FORMS ARE EXCLUDED
#
# The spec table carries 2231 references; 106 of them omit the trailing ';'
# (&amp without the semicolon, and friends). This app reports an unterminated
# entity as a NAMED ERROR rather than guessing, so carrying them would make the
# table disagree with the product decision. The exclusion is counted, not
# assumed: the generator dies unless 2231 - 2125 == 106.
#
# WHAT THIS TABLE IS AND IS NOT FOR
#
# It is the DECODE direction. The ENCODE direction escapes exactly five
# characters — & < > " ' — the OWASP set, with & escaped first (RESEARCH
# assumption A1, decided in plan 06-05). Encoding all 2125 named entities would
# turn "cafe<e-acute>" into "caf&eacute;", which is not what anyone types this
# tool for. The encoder itself lands in plan 06-06; the decision is recorded
# here because it defines this table's scope.
#
# NETWORK POLICY
#
# The download happens ONCE, at generation time, on a developer's machine. The
# app never touches the network (APP-11) and neither does CI: --check reads the
# two tracked Swift files and re-derives their properties, it does not fetch.
# --source PATH regenerates offline from a saved copy, and the sha256 of the
# JSON actually used is printed so it can be recorded as evidence.
#
# Usage (run from the repository root):
#   ruby tools/gen-html-entities.rb                 # fetch and write both tables
#   ruby tools/gen-html-entities.rb --source PATH   # write from a saved entities.json
#   ruby tools/gen-html-entities.rb --check         # verify the tracked tables; no network
#   ruby tools/gen-html-entities.rb --help
#
# Exit codes:
#   0  clean
#   1  at least one `FAIL entities <path>: <reason>` line was printed on stdout
#   2  CANNOT RUN, reported on stderr with no verdict — the check did not happen
#
# THERE IS NO DESTINATION FLAG. This script writes TRACKED SOURCE FILES, and an
# argv-supplied destination in a script that writes tracked files is how a
# --dry-run becomes a live write. The two destinations are DEST_ROOT plus a
# constant filename and argv cannot reach either; `--dest anything` is rejected
# as an unknown argument like any other. test/gen_html_entities_test.rb asserts
# that, so it is a measured property rather than a claim in a comment.
#
# DEPENDENCIES: Ruby stdlib only — `json` and, on the fetch path, `open-uri`.
# No gem, no Gemfile entry, so the `review notes` job keeps bundler-cache: false.
# NOTE FOR A LATER READER: the ZERO-require rule binds tools/check-contamination.rb
# and bin/lib/xcconfig.rb specifically, because those two are loaded by gates that
# must not drag anything in. It does not bind every file in tools/ —
# tools/gen-review-notes.rb's own siblings require open3, tmpdir and friends. Do
# not "fix" the require below; `json` ships with the interpreter.

require "json"

# ─── frozen constants: none of these is derived from the subject ─────────────

# The source is a constant and is NEVER taken from argv. --source may point at a
# local COPY of this document, which is a read; it can never redirect a write.
SPEC_URL = "https://html.spec.whatwg.org/entities.json"

# Every destination lives under the shared engine directory — the only tree
# compiled into both app targets and both unit-test bundles.
DEST_ROOT = "app/Shared/Engine/"

# The two generated enums, in order. Filenames are <enum>.swift.
ENUM_NAMES = %w[HTMLEntityTableA HTMLEntityTableB].freeze

# Chunks per enum. The Swift side reads `chunks`; splitting the packed text
# keeps any single literal small enough that type-checking stays cheap.
CHUNKS_PER_ENUM = 2

# Measured 2026-09-04 against html.spec.whatwg.org/entities.json, 145897 bytes,
# sha256 d741d877ac77c4194c4ad526b5b4a19aef8dfe411ab840a466891cdbb9f362e6.
# A count that drifts is a SIGNAL that the spec table changed — it is not a
# number to bump. Re-measure, read the diff, then move it deliberately.
EXPECTED_TOTAL      = 2231
EXPECTED_TERMINATED = 2125
EXPECTED_LEGACY     = 106

# ONE point of truth for the two delimiters. The emitter and the --check parser
# both read these, so the format cannot be changed on one side only -- and so the
# delimiter red control is a one-line mutation of real code rather than a rewrite
# that could be argued to have tested something else.
#
# U+0001 and U+0002 are below the table's minimum target scalar (U+0009), which
# is what makes them safe. Setting them to 0x3B and 0x3D reproduces the measured
# landmine, and --check then fires on the count.
REC_SCALAR = 0x01
FLD_SCALAR = 0x02

# Source-level SPELLINGS. These are the ASCII characters the Swift compiler turns
# into one scalar, not the scalar itself.
REC_ESCAPE = format("\\u{%x}", REC_SCALAR)
FLD_ESCAPE = format("\\u{%x}", FLD_SCALAR)

# Max characters of packed text per physical line. 4 spaces of indent plus the
# trailing line-continuation backslash keeps every emitted line under
# .swiftlint.yml's 140-character line_length warning, which --strict makes an error.
MAX_LINE_CONTENT = 132

# The three entities whose TARGETS are the delimiters a ';'-separated pack would
# have used. Point (d) of --check is the specific regression for the measured
# landmine, so these are named individually with their expected targets.
DELIMITER_CANARIES = {
  "equals" => [0x3D],
  "semi"   => [0x3B],
  "bne"    => [0x3D, 0x20E5]
}.freeze

USAGE = <<~TXT
  usage: ruby tools/gen-html-entities.rb [--check] [--source <path>]
    --check          verify the tracked tables under #{DEST_ROOT}; never fetches
    --source <path>  read a saved copy of entities.json instead of #{SPEC_URL}
    --help           print this and exit 0
  Writes #{ENUM_NAMES.map { |n| "#{DEST_ROOT}#{n}.swift" }.join(' and ')}.
  There is no destination flag: the write targets are constants.
TXT

# ─── verdict plumbing ────────────────────────────────────────────────────────
#
# One line per failure, no leading whitespace, so a negative control can grep
# `^FAIL entities `. Refusing to run is NOT the same as passing: that path exits
# 2 on stderr and prints no verdict at all.

@failures = 0

def fail!(path, reason)
  puts "FAIL entities #{path}: #{reason.to_s.gsub(/\s*\n\s*/, ' ')}"
  @failures += 1
end

def die(path, reason)
  fail!(path, reason)
  exit 1
end

def cannot_run(message)
  warn "gen-html-entities CANNOT RUN: #{message}"
  exit 2
end

# The FAIL line stays one line (controls grep `^FAIL entities `); the usage
# block follows it as ordinary output rather than being folded into it.
def die_usage(reason)
  fail! "-", reason
  puts USAGE
  exit 1
end

# ─── argv ────────────────────────────────────────────────────────────────────

def parse_args(argv)
  check  = false
  source = nil

  index = 0
  while index < argv.length
    case argv[index]
    when "--check"
      check = true
    when "--source"
      index += 1
      die_usage("--source requires a value") if argv[index].nil?
      source = argv[index]
    when "-h", "--help"
      puts USAGE
      exit 0
    else
      # Unknown argv is rejected, never ignored: a typo'd flag must not look
      # like a successful run, and `--dest <path>` must land here rather than
      # anywhere that could move a write.
      die_usage("unknown argument #{argv[index].inspect}")
    end
    index += 1
  end

  die_usage("--source is meaningless with --check: --check never reads the spec") if check && source
  [check, source]
end

# ─── reading the spec ────────────────────────────────────────────────────────

def load_spec(source)
  raw =
    if source
      unless File.file?(source)
        cannot_run("--source #{source.inspect}: not a readable file")
      end
      begin
        File.read(source, encoding: "UTF-8")
      rescue SystemCallError => e
        cannot_run("--source #{source.inspect}: #{e.message}")
      end
    else
      fetch_spec
    end

  digest = sha256(raw)
  parsed =
    begin
      JSON.parse(raw)
    rescue JSON::ParserError => e
      cannot_run("the entity document is not JSON: #{e.message}")
    end
  [parsed, digest, raw.bytesize]
end

def fetch_spec
  require "open-uri"
  begin
    URI.parse(SPEC_URL).open("r") { |io| io.read.force_encoding(Encoding::UTF_8) }
  rescue SocketError, SystemCallError, OpenURI::HTTPError, Net::OpenTimeout => e
    cannot_run("could not fetch #{SPEC_URL}: #{e.class}: #{e.message} — " \
               "re-run with --source pointing at a saved copy")
  end
end

def sha256(text)
  require "digest"
  Digest::SHA256.hexdigest(text)
end

# Returns [[name_without_ampersand_and_semicolon, [codepoints]], ...] sorted by
# name, and dies unless all three frozen counts hold.
def terminated_records(spec)
  total = spec.length
  if total != EXPECTED_TOTAL
    die "-", "the spec table holds #{total} named references, expected #{EXPECTED_TOTAL}. " \
             "The upstream table changed; read the diff before moving the constant."
  end

  terminated = spec.keys.select { |k| k.end_with?(";") }.sort
  legacy     = total - terminated.length

  if terminated.length != EXPECTED_TERMINATED
    die "-", "the spec table holds #{terminated.length} semicolon-terminated references, " \
             "expected #{EXPECTED_TERMINATED}."
  end
  if legacy != EXPECTED_LEGACY
    die "-", "the spec table holds #{legacy} legacy semicolon-optional references, " \
             "expected #{EXPECTED_LEGACY}."
  end

  terminated.map do |key|
    name = key[1..-2]
    unless name.match?(/\A[A-Za-z][A-Za-z0-9]*\z/)
      die "-", "reference #{key.inspect} has a name outside [A-Za-z][A-Za-z0-9]*; the packed " \
               "format assumes ASCII names with no delimiter characters."
    end
    cps = spec[key]["codepoints"]
    if !cps.is_a?(Array) || cps.empty?
      die "-", "reference #{key.inspect} has no codepoints array."
    end
    if cps.any? { |c| c < 0x09 }
      die "-", "reference #{key.inspect} targets a codepoint below U+0009, which collides " \
               "with the U+0001/U+0002 delimiters this format depends on."
    end
    [name, cps]
  end
end

# ─── emitting ────────────────────────────────────────────────────────────────

def packed_record(name, cps)
  name + FLD_ESCAPE + cps.map { |c| format("\\u{%x}", c) }.join + REC_ESCAPE
end

# Greedy fill with WHOLE records. A line is never split inside a record and
# never inside a \u{...} escape: a line that ended mid-escape would end in a
# backslash that Swift reads as the line continuation, silently changing the
# string. The longest single record is about 60 characters, well under the cap.
def pack_lines(records)
  lines = []
  current = String.new
  records.each do |text|
    if !current.empty? && current.length + text.length > MAX_LINE_CONTENT
      lines << current
      current = String.new
    end
    current << text
  end
  lines << current unless current.empty?
  lines
end

def split_evenly(items, parts)
  per = (items.length.to_f / parts).ceil
  (0...parts).map { |i| items[i * per, per] || [] }
end

def swift_literal(lines, indent)
  pad = " " * indent
  body = lines.each_with_index.map do |line, i|
    pad + line + (i == lines.length - 1 ? "" : "\\")
  end
  (["\"\"\""] + body + [pad + "\"\"\""]).join("\n")
end

def file_header(enum_name, index)
  half = index.zero? ? "first" : "second"
  # PURE ASCII, header included. The whole file is asserted ASCII-only by
  # --check, by test/gen_html_entities_test.rb and by the plan's own
  # `LC_ALL=C grep -c '[^[:print:][:space:]]'` acceptance line, so a stray
  # em dash in prose would fail the same gate a stray U+200B in DATA would.
  <<~SWIFT
    // #{enum_name} - GENERATED FILE. Do not hand-edit.
    //
    // Regenerate with:  ruby tools/gen-html-entities.rb
    // Verify with:      ruby tools/gen-html-entities.rb --check
    //
    // Source of truth: html.spec.whatwg.org/entities.json, the WHATWG named
    // character reference table. This file carries the #{half} half of the 2125
    // SEMICOLON-TERMINATED references. The 106 legacy semicolon-optional forms are
    // deliberately EXCLUDED: this app reports an unterminated entity as a named
    // error (encode.error.html.unterminated) rather than guessing at one.
    //
    // FORMAT. Records are delimited by U+0001, fields within a record by U+0002:
    //
    //     NAME <U+0002> TARGET-SCALARS <U+0001>
    //
    // WHY NOT ';' OR '='. Three entity targets ARE those characters: the entity
    // named "equals" is U+003D, "semi" is U+003B, and "bne" is U+003D U+20E5. So a
    // ';'-separated pack loses six records with a green compile and no warning.
    // Measured: 2125 in, 2119 out. Escaping does not help, because a backslash-u
    // escape for U+003B is a literal ';' by the time the parser runs. U+0001 and
    // U+0002 cannot occur in the data: the minimum target scalar in the whole
    // table is U+0009 and every name is ASCII letters and digits.
    //
    // WHY EVERY SCALAR IS AN ESCAPE. 17 entities target invisible or format
    // characters. Written literally they produce `invisible_character` errors under
    // swiftlint --strict, so this file is pure ASCII and stays that way.
    //
    // SCOPE. This is the DECODE direction. The encoder escapes exactly five
    // characters - ampersand, less-than, greater-than, double quote, apostrophe -
    // with the ampersand first; it does not use this table.
    //
    // recordCount below is THIS FILE's contribution, asserted separately from its
    // sibling's rather than as a union. A union that has stopped drawing from one
    // source looks identical to one that never did.
  SWIFT
end

def swift_file(enum_name, index, records)
  chunks = split_evenly(records, CHUNKS_PER_ENUM)
  parts = chunks.each_with_index.map do |chunk, i|
    lines = pack_lines(chunk.map { |name, cps| packed_record(name, cps) })
    "    /// Packed chunk #{i}: #{chunk.length} records.\n" \
    "    static let packed#{i}: String = #{swift_literal(lines, 4)}"
  end

  [
    file_header(enum_name, index).chomp,
    "",
    "enum #{enum_name} {",
    parts.join("\n\n"),
    "",
    "    /// The packed chunks in order. Concatenating them yields this file's whole half.",
    "    static let chunks: [String] = [#{(0...CHUNKS_PER_ENUM).map { |i| "packed#{i}" }.join(', ')}]",
    "",
    "    /// Records this file contributes. Generated, and asserted by",
    "    /// test/gen_html_entities_test.rb and by `gen-html-entities.rb --check`.",
    "    static let recordCount: Int = #{records.length}",
    "}",
    ""
  ].join("\n")
end

def run_write(source)
  unless Dir.exist?(DEST_ROOT)
    cannot_run("#{DEST_ROOT}: directory does not exist — run this from the repository root.")
  end

  spec, digest, bytes = load_spec(source)
  records = terminated_records(spec)
  halves  = split_evenly(records, ENUM_NAMES.length)

  ENUM_NAMES.each_with_index do |enum_name, i|
    path = File.join(DEST_ROOT, "#{enum_name}.swift")
    text = swift_file(enum_name, i, halves[i])
    bad = text.lines.find { |l| l.bytes.any? { |b| b > 0x7F } }
    if bad
      die path, "the generated text contains a non-ASCII byte, in: #{bad.strip.inspect} " \
                "- every scalar must be a \\u{...} escape and the header prose must be ASCII too"
    end
    File.write(path, text, encoding: "UTF-8")
    puts "wrote #{path} (#{halves[i].length} records, #{text.lines.length} lines)"
  end

  puts "source #{source || SPEC_URL} bytes=#{bytes} sha256=#{digest}"
  puts "entity table written: files=#{ENUM_NAMES.length} enums=#{ENUM_NAMES.length} " \
       "chunks=#{ENUM_NAMES.length * CHUNKS_PER_ENUM} records=#{records.length}"
end

# ─── --check: assert the property, do not diff two files ─────────────────────

# Decodes a Swift string literal's source text into the scalar sequence the
# compiler would produce, then splits it exactly as the Swift parser will. This
# is what makes the count assertion mean something: it measures the VALUE, not
# the spelling.
def decode_scalars(text)
  scalars = []
  text.scan(/\\u\{([0-9a-fA-F]{1,6})\}|(.)/m) do |escape, literal|
    scalars << (escape ? escape.to_i(16) : literal.ord)
  end
  scalars
end

# `swift_source` is a String that check_file already read with an explicit
# encoding and already asserted to be pure ASCII, so there is no path and no
# encoding argument at this call site. test/encoding_test.rb carries an
# EXEMPTIONS entry anchored on the parameter name, with that measurement as its
# reason.
def literal_bodies(path, swift_source)
  bodies = {}
  name = nil
  buffer = nil
  swift_source.each_line do |line|
    if buffer.nil?
      m = line.match(/^\s*static let (packed\d+): String = """\s*$/)
      next unless m

      name = m[1]
      buffer = []
    elsif line.match?(/^\s*"""\s*$/)
      bodies[name] = buffer.join
      buffer = nil
    else
      # BLOCK FORM, deliberately. A String replacement expands \0, \\ and \`
      # — and the text being rewritten here is a line that ENDS IN A BACKSLASH,
      # which is exactly the input that turns that expansion into corruption.
      stripped = line.chomp.sub(/\\\z/) { "" }
      buffer << stripped.sub(/\A\s+/) { "" }
    end
  end
  fail! path, "a packed literal is unterminated" unless buffer.nil?
  bodies
end

def check_file(path)
  unless File.file?(path)
    fail! path, "missing — regenerate with: ruby tools/gen-html-entities.rb"
    return nil
  end

  src = File.read(path, encoding: "UTF-8")

  offending = src.each_byte.find { |b| b > 0x7F }
  if offending
    fail! path, format("contains a literal non-ASCII byte 0x%02X; every scalar must be a " \
                       "\\u{...} escape or swiftlint --strict reports invisible_character", offending)
  end

  unless src.include?("Do not hand-edit")
    fail! path, "header does not carry the 'Do not hand-edit' notice"
  end

  bodies = literal_bodies(path, src)
  if bodies.empty?
    fail! path, "carries no `static let packedN: String` literal — nothing to parse"
    return nil
  end
  if bodies.length != CHUNKS_PER_ENUM
    fail! path, "carries #{bodies.length} packed chunks, expected #{CHUNKS_PER_ENUM}"
  end

  declared_match = src.match(/static let recordCount: Int = (\d+)/)
  unless declared_match
    fail! path, "carries no generated `static let recordCount: Int`"
    return nil
  end
  declared = declared_match[1].to_i

  scalars = bodies.keys.sort.flat_map { |k| decode_scalars(bodies[k]) }
  records = []
  malformed = 0
  scalars.chunk_while { |_a, b| b != REC_SCALAR }.each do |run|
    body = run.reject { |s| s == REC_SCALAR }
    next if body.empty?

    fields = body.chunk_while { |_a, b| b != FLD_SCALAR }
                 .map { |f| f.reject { |s| s == FLD_SCALAR } }
    if fields.length != 2 || fields[0].empty? || fields[1].empty?
      malformed += 1
      next
    end
    records << [fields[0].map { |c| c.chr(Encoding::UTF_8) }.join, fields[1]]
  end

  fail! path, "#{malformed} packed record(s) do not split into exactly two fields" if malformed.positive?

  if records.length != declared
    fail! path, "declares recordCount #{declared} but its packed chunks parse to " \
                "#{records.length} records — the packing format is losing records"
  end

  { declared: declared, parsed: records.length, records: records }
end

def run_check
  unless Dir.exist?(DEST_ROOT)
    cannot_run("#{DEST_ROOT}: directory does not exist — run this from the repository root.")
  end

  results = ENUM_NAMES.map { |n| check_file(File.join(DEST_ROOT, "#{n}.swift")) }

  if results.any?(&:nil?)
    puts "entity table CHECK FAILED: #{@failures} failure(s)"
    exit 1
  end

  # (b) the two contributions are summed, and each is reported, so a file that
  #     stopped contributing is visible rather than absorbed into a total.
  parsed_total = results.sum { |r| r[:parsed] }
  if parsed_total != EXPECTED_TERMINATED
    fail! DEST_ROOT, "the two tables parse to #{parsed_total} records, expected " \
                     "#{EXPECTED_TERMINATED} (#{ENUM_NAMES.each_with_index.map { |n, i| "#{n}=#{results[i][:parsed]}" }.join(' ')})"
  end

  # (d) the delimiter-colliding entities, named individually with their targets.
  all = results.flat_map { |r| r[:records] }.to_h
  DELIMITER_CANARIES.each do |name, expected|
    actual = all[name]
    if actual.nil?
      fail! DEST_ROOT, "&#{name}; is absent from the table — this is the exact record a " \
                       "';'-delimited pack loses"
    elsif actual != expected
      fail! DEST_ROOT, "&#{name}; targets #{actual.map { |c| format('U+%04X', c) }.join(' ')}, " \
                       "expected #{expected.map { |c| format('U+%04X', c) }.join(' ')}"
    end
  end

  if @failures.positive?
    puts "entity table CHECK FAILED: #{@failures} failure(s)"
    exit 1
  end

  puts "entity table in sync: files=#{ENUM_NAMES.length} enums=#{ENUM_NAMES.length} " \
       "chunks=#{ENUM_NAMES.length * CHUNKS_PER_ENUM} " \
       "#{ENUM_NAMES.each_with_index.map { |n, i| "#{n}=#{results[i][:parsed]}" }.join(' ')} " \
       "records=#{parsed_total}"
  exit 0
end

check, source = parse_args(ARGV)

if check
  run_check
else
  run_write(source)
end
