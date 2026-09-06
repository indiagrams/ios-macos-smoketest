#!/usr/bin/env ruby
# frozen_string_literal: true

# PRIV-01 — the app's privacy manifest declares EXACTLY the required-reason API
# categories the app's own Swift uses. Both directions. Nothing more, nothing less.
#
# WHY THIS EXISTS
#
#   Apple's rule is not "declare at least what you use". It is "you may use these
#   APIs and the data derived from their use for the DECLARED REASONS ONLY", which
#   makes an over-declaration a false statement rather than a harmless extra, and an
#   under-declaration an upload rejection (ITMS-91053; an invalid reason for a
#   declared category is ITMS-91055). Since 1 May 2024 a submission that fails
#   either half is not accepted by App Store Connect.
#
#   On this tree, TODAY, both sides are legitimately EMPTY: no Swift compiled into
#   either application target touches a required-reason API, and the manifest
#   declares nothing. That is a correct green — and it is exactly why the three red
#   controls recorded in
#   .planning/phases/07-…/evidence/07-04-privacy-gate.txt are mandatory rather than
#   decorative. A gate that has only ever seen empty-versus-empty has not been shown
#   to detect anything.
#
# THE TRAP THIS FILE IS BUILT AROUND, AND IT IS LOADED IN BOTH DIRECTIONS
#
#   The single occurrence of the store-type word this gate sweeps for, anywhere
#   under app/Shared/ today, is inside an XML COMMENT in the gate's own subject
#   file — app/Shared/PrivacyInfo.xcprivacy. So:
#
#     * a scan whose population is "every file under app/Shared" reports a use that
#       does not exist, and goes RED ON A CORRECT TREE today; and
#     * once 07-05 fills the manifest, that same comment would SATISFY the forward
#       direction with no Swift using anything at all — the gate green because of
#       its own configuration file.
#
#   Two mitigations, both required, both present here:
#     (a) the population is `*.swift` ONLY, drawn from the two application targets'
#         `sources:` lists, and nothing else is ever read as source; and
#     (b) every category constant and every symbol name below is ASSEMBLED FROM
#         SPACED CHARACTERS AT RUN TIME and is never spelled as a literal, in code
#         or in prose, anywhere in this file. That route is recorded on stdout as
#         privacy_category_tokens=assembled. It is the shape
#         tools/check-contamination.rb and test/app_offline_test.rb:190-215 already
#         use (D-92), pointed here at the phase's own subject.
#
#   One layer up again: a COMMENT-BLIND scan of this tree is RED ON A CORRECT TREE
#   for a second, independent reason — app/Shared/Engine/HTMLEntityTablePacking.swift
#   line 10 mentions a git porcelain flag whose name is also a file-metadata syscall,
#   inside a comment. So comments are stripped before anything is counted, by the
#   56-line state machine copied whole from test/app_offline_test.rb:267-322, and
#   the stripped and unstripped hit counts are BOTH printed so the stripper's work is
#   visible rather than assumed. The `comment-blindness` control proves that stripper
#   is load-bearing.
#
# WHAT IS ASSERTED, AND OVER WHICH POPULATION
#
#   P1  the Swift population is the UNION of the two APPLICATION targets' sources,
#       enumerated from BOTH generator manifests, each contribution counted          once
#   P2  the two manifests agree on what those sources are                            once
#   P3  the manifest file exists, is non-empty, and parses                           once
#   P4  all four required keys are present AND correctly typed                       per key
#   P5  the collected-data-types array is present and EMPTY                          once
#   P6  where plutil exists, Apple's parse and this file's parse agree exactly       once
#   P7  FORWARD: every category the Swift uses is declared, naming file/line/symbol   per category
#   P8  REVERSE: every declared category is used, naming the category                per entry
#   P9  every declared category is one of Apple's five                               per entry
#   P10 every declared reason is non-empty and valid FOR THAT CATEGORY               per entry
#   P11 when --archive is supplied, the bundle's EMBEDDED manifest is the source one  per bundle
#
#   P1 is asserted BEFORE anything iterates. A population that has stopped being
#   enumerated looks exactly like a population with nothing wrong in it, and `.each`
#   over an empty collection asserts nothing while printing success.
#
# FAILURE-LINE CONTRACT — do not change the shape. Controls grep it.
# One line per failure, no leading whitespace:
#
#     FAIL privacy <path>: <reason>
#
# Named reasons, never codes. Labelled counts printed even on success. A single
# combined exit at the bottom, never an early exit-1. A tree that could not be
# scanned exits 2 with CANNOT RUN on stderr and prints NO verdict — "nobody looked"
# must never read as "it is clean".
#
# Ruby stdlib only, TWO requires, both default gems shipped with the interpreter, so
# the `review notes` job's `bundler-cache: false` stays honest — there is no gem to
# install:
#
#   digest          sha256 of the manifest, printed on every run as a recorded fact
#                   and ASSERTED equal between the source manifest and a bundle's
#                   embedded copy when --archive is supplied. It is deliberately NOT
#                   frozen against a dated constant: 07-05 fills this manifest, and a
#                   frozen hash would turn a planned edit into a gate failure.
#   rexml/document  the manifest is parsed STRUCTURALLY, by walking elements. REXML
#                   walks elements, so XML comments are structurally invisible to it
#                   — which is the property that makes this a parse rather than a
#                   hopeful regex. Measured 2026-09-05: bare-requires under ruby
#                   3.3.12 and ruby 4.0.6 on this machine, and these gates are
#                   invoked as plain `ruby test/…`, never `bundle exec`.
#
# NOT REUSED: test/app_offline_test.rb's `<key>`-scanning plist helper. Measured
# insufficient here — the category constant and the reason code are <string> VALUES,
# not <key>s, so neither ever appears in that helper's output at all.
#
# Every shell-out is an argv array. Every read of a text file pins its encoding on
# the call (UL-048).
#
# Runnable from the repository root, under BOTH pinned interpreters:
#   /opt/homebrew/opt/ruby@3.3/bin/ruby test/privacy_manifest_test.rb
#   /opt/homebrew/opt/ruby@4.0/bin/ruby test/privacy_manifest_test.rb
#
# Options:
#   --root DIR      scan a different tree (used by the negative controls)
#   --archive PATH  a built .app whose EMBEDDED manifest is checked too (plan 07-13)

require "digest"
require "rexml/document"

USAGE = "Usage: ruby test/privacy_manifest_test.rb [--root DIR] [--archive PATH]"

def no_verdict(message)
  warn "CANNOT RUN: #{message}"
  exit 2
end

root    = nil
archive = ENV["PRIVACY_MANIFEST_ARCHIVE"]
argv    = ARGV.dup
until argv.empty?
  case (arg = argv.shift)
  when "--root"       then root    = argv.shift or no_verdict("--root needs a directory. #{USAGE}")
  when "--archive"    then archive = argv.shift or no_verdict("--archive needs a path. #{USAGE}")
  when "-h", "--help" then puts USAGE ; exit 0
  else no_verdict("unrecognised argument #{arg.inspect}. #{USAGE}")
  end
end

ROOT    = root.nil? ? File.expand_path("..", __dir__) : File.expand_path(root)
ARCHIVE = archive

# ─── the tokens, ASSEMBLED — never spelled ───────────────────────────────────
# Written SPACED and joined at run time. Nothing below spells a category constant
# or a symbol name, so this file cannot be swept green by its own source and its
# own subject file cannot satisfy it. `privacy_category_tokens=assembled` records
# the route on stdout.

def asm(spaced)
  spaced.split(" ").join
end

PFX = asm("N S P r i v a c y A c c e s s e d A P I C a t e g o r y")

# ─── frozen, dated measurements ──────────────────────────────────────────────
# A value, its measurement date and the thing it was measured against are ONE
# UNIT. None of these is a number to bump: a phase whose facts legitimately change
# RE-MEASURES the triple and writes the new date beside it.

MEASURED_ON      = "2026-09-05"
MEASURED_AGAINST = "developer.apple.com DocC JSON for " \
                   "bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/" \
                   "nsprivacyaccessedapitype (the HTML page is JS-rendered and returns an " \
                   "empty body to a plain fetch; the JSON behind it is the machine-readable " \
                   "source), fetched #{MEASURED_ON}"

MANIFEST_REL   = "app/Shared/PrivacyInfo.xcprivacy"
MANIFEST_YML   = "app/project.yml"
MANIFEST_SWIFT = "app/Project.swift"
ARCHIVE_LEAF   = File.basename(MANIFEST_REL)

# Measured #{MEASURED_ON}: the two application targets' sources hold 32 Swift files,
# all of them under Shared. The floor's job is to refuse a VACUOUS pass, not to
# freeze the file count — the exact number is printed on every run.
SWIFT_FLOOR = 20

# Apple's five categories. There are exactly five; all five appear in the raw JSON
# and there are no others. Measured against MEASURED_AGAINST.
CATEGORY_SUFFIX = {
  "file-timestamp"   => asm("F i l e T i m e s t a m p"),
  "system-boot-time" => asm("S y s t e m B o o t T i m e"),
  "disk-space"       => asm("D i s k S p a c e"),
  "active-keyboards" => asm("A c t i v e K e y b o a r d s"),
  "user-defaults"    => asm("U s e r D e f a u l t s")
}.freeze

CATEGORY = CATEGORY_SUFFIX.transform_values { |suffix| PFX + suffix }.freeze
SLUG_FOR = CATEGORY.invert.freeze

# The symbols Apple names, per category. MANY-TO-MANY BY CONSTRUCTION: three of
# them (the attribute-list syscalls) belong to TWO categories each, and a
# symbol-keyed hash would silently drop one of the two.
#
# The store-type group carries two symbols Apple's page does NOT name — the SwiftUI
# property wrappers that read and write that same store. [ASSUMED, and conservative
# on purpose: it can only make this gate stricter. An app that persisted entirely
# through the property wrapper would be invisible to a gate that looked for the
# store type alone.]
SYMBOLS = {
  "file-timestamp" => [
    asm("c r e a t i o n D a t e"), asm("m o d i f i c a t i o n D a t e"),
    asm("f i l e M o d i f i c a t i o n D a t e"),
    asm("c o n t e n t M o d i f i c a t i o n D a t e K e y"),
    asm("c r e a t i o n D a t e K e y"), asm("g e t a t t r l i s t"),
    asm("g e t a t t r l i s t b u l k"), asm("f g e t a t t r l i s t"),
    asm("s t a t"), asm("f s t a t"),
    asm("f s t a t a t"), asm("l s t a t"),
    asm("g e t a t t r l i s t a t")
  ].freeze,
  "system-boot-time" => [
    asm("s y s t e m U p t i m e"), asm("m a c h _ a b s o l u t e _ t i m e")
  ].freeze,
  "disk-space" => [
    asm("v o l u m e A v a i l a b l e C a p a c i t y K e y"),
    asm("v o l u m e A v a i l a b l e C a p a c i t y F o r I m p o r t a n t U s a g e K e y"),
    asm("v o l u m e A v a i l a b l e C a p a c i t y F o r O p p o r t u n i s t i c U s a g e K e y"),
    asm("v o l u m e T o t a l C a p a c i t y K e y"),
    asm("s y s t e m F r e e S i z e"), asm("s y s t e m S i z e"),
    asm("s t a t f s"), asm("s t a t v f s"),
    asm("f s t a t f s"), asm("f s t a t v f s"),
    asm("g e t a t t r l i s t"), asm("f g e t a t t r l i s t"),
    asm("g e t a t t r l i s t a t")
  ].freeze,
  "active-keyboards" => [
    asm("a c t i v e I n p u t M o d e s")
  ].freeze,
  "user-defaults" => [
    asm("U s e r D e f a u l t s"), asm("A p p S t o r a g e"),
    asm("S c e n e S t o r a g e")
  ].freeze
}.freeze

# The complete reason table, per category. A reason valid for one category is
# INVALID for another, and that is specifically what ITMS-91055 rejects, so the
# pairing is asserted rather than the membership.
REASONS = {
  "file-timestamp"   => %w[DDA9.1 C617.1 3B52.1 0A2A.1].freeze,
  "system-boot-time" => %w[35F9.1 8FFB.1 3D61.1].freeze,
  "disk-space"       => %w[85F4.1 E174.1 7D9E.1 B728.1].freeze,
  "active-keyboards" => %w[3EC4.1 54BD.1].freeze,
  "user-defaults"    => %w[CA92.1 1C8F.1 C56D.1 AC6B.1].freeze
}.freeze

# The four keys Apple's spec requires present even when empty, and the type each
# must have. A key present with the WRONG TYPE is a plist that lints fine and
# means nothing.
REQUIRED_KEYS = {
  "NSPrivacyTracking"           => :boolean,
  "NSPrivacyTrackingDomains"    => :array,
  "NSPrivacyCollectedDataTypes" => :array,
  "NSPrivacyAccessedAPITypes"   => :array
}.freeze

TYPE_KEY    = "NSPrivacyAccessedAPIType"
TYPES_KEY   = "NSPrivacyAccessedAPITypes"
REASONS_KEY = "NSPrivacyAccessedAPITypeReasons"
COLLECT_KEY = "NSPrivacyCollectedDataTypes"

# ─── assertion harness (test/app_offline_test.rb:217-241, verbatim) ──────────

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
    puts "All #{@checks} privacy-manifest assertions passed."
    exit 0
  else
    puts "#{@failures} of #{@checks} privacy-manifest assertion(s) failed."
    exit 1
  end
end

# ─── helpers ─────────────────────────────────────────────────────────────────

# argv array, never a shell string: quoting has silently changed a candidate set
# in this repository before.
def capture(*argv, chdir: ROOT)
  out = IO.popen(argv, chdir: chdir, err: File::NULL, &:read)
  [out.to_s, $?&.exitstatus]
rescue SystemCallError => e
  ["", "unavailable: #{e.message}"]
end

def tool?(name)
  _out, status = capture("/usr/bin/env", "which", name, chdir: ROOT)
  status == 0
end

def unquote(str)
  str.strip.sub(/\A["']/, "").sub(/["']\z/, "")
end

# Swift comments removed while LINE STRUCTURE IS PRESERVED, so a hit still reports
# its line. String literals are deliberately NOT stripped: a symbol spelled inside
# a string is not a comment and this gate errs toward reporting it.
# Copied whole from test/app_offline_test.rb:267-322 — a lighter version is what
# makes this gate red on a correct tree.
def strip_swift_comments(src)
  out   = +""
  i     = 0
  n     = src.length
  state = :code
  depth = 0
  while i < n
    ch = src[i]
    nx = src[i + 1]
    case state
    when :code
      if ch == "/" && nx == "/"
        state = :line ; out << "  " ; i += 2
      elsif ch == "/" && nx == "*"
        state = :block ; depth = 1 ; out << "  " ; i += 2
      elsif ch == "#" && nx == "\""
        state = :raw ; out << ch << nx ; i += 2
      elsif src[i, 3] == '"""'
        state = :mstring ; out << '"""' ; i += 3
      elsif ch == "\""
        state = :string ; out << ch ; i += 1
      else
        out << ch ; i += 1
      end
    when :line
      if ch == "\n" then state = :code ; out << ch else out << " " end
      i += 1
    when :block
      if ch == "/" && nx == "*"
        depth += 1 ; out << "  " ; i += 2
      elsif ch == "*" && nx == "/"
        depth -= 1 ; out << "  " ; i += 2 ; state = :code if depth.zero?
      else
        out << (ch == "\n" ? ch : " ") ; i += 1
      end
    when :string
      if ch == "\\"       then out << ch << (nx || "") ; i += 2
      elsif ch == "\"" || ch == "\n" then state = :code ; out << ch ; i += 1
      else out << ch ; i += 1
      end
    when :mstring
      if ch == "\\"          then out << ch << (nx || "") ; i += 2
      elsif src[i, 3] == '"""' then state = :code ; out << '"""' ; i += 3
      else out << ch ; i += 1
      end
    when :raw
      if src[i, 2] == "\"#" then state = :code ; out << "\"#" ; i += 2
      else out << ch ; i += 1
      end
    end
  end
  out
end

SYMBOL_RE = SYMBOLS.transform_values do |syms|
  Regexp.new("\\b(?:#{syms.sort_by { |s| -s.length }.map { |s| Regexp.escape(s) }.join('|')})\\b")
end.freeze

# [[slug, line, symbol], …] — every occurrence, not the first, so a second use in
# the same file is still named.
def symbol_hits(text)
  found = []
  text.each_line.with_index(1) do |line, number|
    SYMBOL_RE.each do |slug, re|
      offset = 0
      while (m = re.match(line, offset))
        found << [slug, number, m[0]]
        offset = m.end(0)
      end
    end
  end
  found
end

# ─── the structural plist parse ──────────────────────────────────────────────
# Elements, not text. REXML walks elements, so an XML comment is structurally
# invisible to it — which is the whole reason this is a parse and not a regex that
# happens to work today.

def plist_value(el)
  case el.name
  when "dict"    then el.elements.to_a.each_slice(2).to_h { |k, v| [k.text.to_s.strip, plist_value(v)] }
  when "array"   then el.elements.map { |e| plist_value(e) }
  when "string"  then el.text.to_s
  when "true"    then true
  when "false"   then false
  when "integer" then el.text.to_i
  when "real"    then el.text.to_f
  else "<#{el.name}>"
  end
end

def parse_plist_text(text)
  doc  = REXML::Document.new(text)
  root = doc.elements["plist"]
  return nil if root.nil?
  first = root.elements[1]
  return nil if first.nil?
  plist_value(first)
rescue REXML::ParseException
  nil
end

# ─── P1: the population, from BOTH manifests, BEFORE anything iterates ───────
# NOT `git ls-files 'app/*.swift'`. That is 75 files on this tree, 42 of them
# test-target sources plus the Tuist manifest itself, and a required-reason symbol
# in a test file is not in the shipped binary. What DEFINES this population is the
# `sources:` list of the two APPLICATION targets, and it is read out of both
# generator manifests so a manifest that stopped contributing moves a number.

# XcodeGen: indentation-structural. Target names at indent 2 under `targets:`, the
# `type:`/`sources:` keys at 4, `- path:` entries at 6, `excludes:` at 8 and its
# items at 10.
def yml_app_target_sources(text)
  result    = {}
  target    = nil
  is_app    = false
  entries   = nil
  in_target = false
  in_source = false
  in_excl   = false
  flush = lambda do
    result[target] = entries if target && is_app && entries
  end
  text.each_line do |raw|
    line = raw.chomp
    next if line.strip.empty?
    stripped = line.strip
    next if stripped.start_with?("#")
    indent = line[/\A */].length
    if indent.zero?
      flush.call
      in_target = (stripped == "targets:")
      target = nil ; is_app = false ; entries = nil ; in_source = false ; in_excl = false
      next
    end
    next unless in_target
    if indent == 2 && stripped.end_with?(":")
      flush.call
      target  = stripped.chomp(":")
      is_app  = false
      entries = []
      in_source = false ; in_excl = false
      next
    end
    next if target.nil?
    if indent == 4
      in_source = (stripped == "sources:")
      in_excl   = false
      is_app    = true if stripped == "type: application"
      next
    end
    next unless in_source
    if indent == 6 && stripped.start_with?("- path:")
      entries << [unquote(stripped.sub("- path:", "")), []]
      in_excl = false
    elsif indent == 8 && stripped == "excludes:"
      in_excl = true
    elsif in_excl && indent == 10 && stripped.start_with?("- ")
      entries.last[1] << unquote(stripped.sub("- ", ""))
    end
  end
  flush.call
  result
end

# Tuist: one chunk per Target.target(, kept only when it declares the app product.
def swift_app_target_sources(text)
  result = {}
  text.split("Target.target(")[1..].to_a.each do |chunk|
    name = chunk[/name:\s*"([^"]+)"/, 1]
    next if name.nil?
    next unless chunk[/product:\s*\.app\b/]
    open_at = chunk.index(/^\s*sources:\s*\[/)
    next if open_at.nil?
    start = chunk.index("[", open_at)
    depth = 0
    stop  = start
    while stop < chunk.length
      depth += 1 if chunk[stop] == "["
      depth -= 1 if chunk[stop] == "]"
      break if depth.zero?
      stop += 1
    end
    blob     = chunk[start..stop].to_s
    excluded = blob.scan(/excluding:\s*\[([^\]]*)\]/).flatten
                   .flat_map { |inner| inner.scan(/"([^"]+)"/).flatten }
    included = blob.scan(/"([^"]+)"/).flatten - excluded
    result[name] = [included, excluded]
  end
  result
end

def normalise_glob(path)
  path.sub(%r{/\*\*/?\z}, "").sub(%r{/\z}, "")
end

yml_abs   = File.join(ROOT, MANIFEST_YML)
swift_abs = File.join(ROOT, MANIFEST_SWIFT)
no_verdict("#{MANIFEST_YML} not found under #{ROOT} — the population cannot be enumerated") unless File.file?(yml_abs)
no_verdict("#{MANIFEST_SWIFT} not found under #{ROOT} — the population cannot be enumerated") unless File.file?(swift_abs)

yml_targets   = yml_app_target_sources(File.read(yml_abs, encoding: "UTF-8"))
swift_targets = swift_app_target_sources(File.read(swift_abs, encoding: "UTF-8"))

no_verdict("#{MANIFEST_YML} declared no application targets in #{ROOT}") if yml_targets.empty?
no_verdict("#{MANIFEST_SWIFT} declared no application targets in #{ROOT}") if swift_targets.empty?

yml_norm = yml_targets.transform_values do |entries|
  inc = entries.map { |path, _ex| normalise_glob(path) }
  exc = entries.flat_map { |path, ex| ex.map { |e| normalise_glob("#{path}/#{e}") } }
  [inc.sort, exc.sort]
end
swift_norm = swift_targets.transform_values do |(inc, exc)|
  [inc.map { |p| normalise_glob(p) }.sort, exc.map { |p| normalise_glob(p) }.sort]
end

# P2. Both manifests, compared. tools/identity-parity.rb does not look at sources
# lists, so a pair that disagreed here would be invisible to it.
assert yml_norm == swift_norm, "privacy", "#{MANIFEST_YML} + #{MANIFEST_SWIFT}",
       "the two generator manifests declare the same application-target sources " \
       "(xcodegen: #{yml_norm.inspect} / tuist: #{swift_norm.inspect}). A disagreement means " \
       "one generator ships Swift the other does not, and this gate would be scanning only " \
       "half the shipped code"

def population_for(norm, root)
  files = {}
  norm.each do |target, (included, excluded)|
    included.each do |dir|
      base = File.join(root, "app", dir)
      Dir.glob(File.join(base, "**", "*.swift")).sort.each do |abs|
        rel = abs.sub("#{root}/", "")
        next if excluded.any? { |ex| rel.start_with?("app/#{ex}/") }
        (files[rel] ||= []) << [target, dir]
      end
    end
  end
  files
end

yml_pop   = population_for(yml_norm, ROOT)
swift_pop = population_for(swift_norm, ROOT)

no_verdict("the #{MANIFEST_YML} application targets globbed no Swift under #{ROOT} — " \
           "a scan over an empty population asserts nothing and prints success") if yml_pop.empty?
no_verdict("the #{MANIFEST_SWIFT} application targets globbed no Swift under #{ROOT} — " \
           "a scan over an empty population asserts nothing and prints success") if swift_pop.empty?

population = (yml_pop.keys | swift_pop.keys).sort
no_verdict("the union of both manifests' application-target sources holds #{population.length} " \
           "Swift file(s) under #{ROOT}, below the floor of #{SWIFT_FLOOR} measured on " \
           "#{MEASURED_ON} (32). Re-measure the triple; do not lower the floor") if population.length < SWIFT_FLOOR

def contribution(population, prefix)
  population.count { |rel| rel.start_with?(prefix) }
end

from_shared = contribution(population, "app/Shared/")
from_ios    = contribution(population, "app/iOS/")
from_macos  = contribution(population, "app/macOS/")

# ─── P3–P6: the manifest, parsed twice ───────────────────────────────────────

manifest_abs = File.join(ROOT, MANIFEST_REL)
exists = File.file?(manifest_abs)
assert exists, "privacy", MANIFEST_REL,
       "the privacy manifest exists; a missing file would satisfy every declaration " \
       "assertion below while proving nothing about what the app ships"
no_verdict("#{MANIFEST_REL} not found under #{ROOT} — there is nothing to compare the " \
           "#{population.length}-file population against") unless exists

manifest_bytes = File.binread(manifest_abs)
manifest_sha   = Digest::SHA256.hexdigest(manifest_bytes)
manifest_format = manifest_bytes.start_with?("bplist00") ? "binary" : "xml"

assert !manifest_bytes.strip.empty?, "privacy", MANIFEST_REL, "the privacy manifest is non-empty"

have_plutil  = tool?("plutil")
parse_route  = have_plutil ? "rexml+plutil" : "rexml"
no_verdict("#{MANIFEST_REL} is a BINARY plist and plutil is not on this machine, so it " \
           "cannot be parsed structurally here") if manifest_format == "binary" && !have_plutil

rexml_parsed = manifest_format == "xml" ? parse_plist_text(File.read(manifest_abs, encoding: "UTF-8")) : nil

apple_parsed = nil
if have_plutil
  lint_out, lint_status = capture("plutil", "-lint", manifest_abs)
  assert lint_status == 0, "privacy", MANIFEST_REL,
         "plutil -lint accepts the file (#{lint_out.strip})"
  # ONE whole-file conversion. A per-key `-extract <Boolean> json` FAILS with
  # "Invalid object in plist for JSON format" on a CORRECT manifest — measured
  # #{MEASURED_ON} — so the four keys are never read one at a time.
  xml_out, xml_status = capture("plutil", "-convert", "xml1", "-o", "-", manifest_abs)
  assert xml_status == 0, "privacy", MANIFEST_REL,
         "plutil -convert re-emits the whole file in one pass"
  apple_parsed = parse_plist_text(xml_out) if xml_status == 0
end

plist = rexml_parsed || apple_parsed
no_verdict("#{MANIFEST_REL} did not parse as a property list with a dictionary root") unless plist.is_a?(Hash)

# P6. Apple's parser, where it exists, must produce the same STRUCTURE. Apple's
# re-emission is different TEXT — comments gone, whitespace normalised — so an
# agreement here is evidence about the structure rather than about the bytes.
if rexml_parsed && apple_parsed
  assert rexml_parsed == apple_parsed, "privacy", MANIFEST_REL,
         "Apple's parser and this file's parser agree on the whole structure exactly. " \
         "A disagreement means the element walk in this gate is wrong, which is the " \
         "failure mode a text-level regex would never surface"
end

# P4. Presence AND type.
REQUIRED_KEYS.each do |key, kind|
  present = plist.key?(key)
  assert present, "privacy", MANIFEST_REL,
         "the required key #{key} is present; Apple's spec requires all " \
         "#{REQUIRED_KEYS.length} even when empty"
  next unless present
  value = plist[key]
  ok = kind == :boolean ? (value == true || value == false) : value.is_a?(Array)
  assert ok, "privacy", MANIFEST_REL,
         "#{key} is #{kind == :boolean ? 'a Boolean' : 'an Array'}; found " \
         "#{value.class}. A key present with the wrong type is a plist that lints " \
         "fine and means nothing"
end

# P5. Collected data types, empty and asserted so by name.
collected = plist[COLLECT_KEY]
assert collected.is_a?(Array) && collected.empty?, "privacy", MANIFEST_REL,
       "#{COLLECT_KEY} is present and EMPTY — this app collects no data, and that is " \
       "a claim worth failing on rather than a default worth assuming; found " \
       "#{collected.inspect}"

# ─── P7–P10: the two directions ──────────────────────────────────────────────

used          = {}
stripped_hits = 0
raw_hits      = 0
scanned_bytes = 0

population.each do |rel|
  abs = File.join(ROOT, rel)
  next unless File.file?(abs)
  raw = File.read(abs, encoding: "UTF-8")
  scanned_bytes += raw.bytesize
  found = symbol_hits(strip_swift_comments(raw))
  stripped_hits += found.length
  raw_hits      += symbol_hits(raw).length
  found.each { |slug, line, symbol| (used[slug] ||= []) << [rel, line, symbol] }
end

declared_entries = plist.fetch(TYPES_KEY, [])
declared_entries = [] unless declared_entries.is_a?(Array)
declared_slugs   = []
declared_labels  = []

# FORWARD. Runs to completion.
used.keys.sort.each do |slug|
  sites = used[slug]
  assert declared_entries.any? { |e| e.is_a?(Hash) && e[TYPE_KEY] == CATEGORY[slug] },
         "privacy", MANIFEST_REL,
         "the app targets' Swift uses the #{slug} category at " \
         "#{sites.map { |f, l, s| "#{f}:#{l} #{s}" }.join(', ')} but the manifest declares " \
         "no entry for it. Apple rejects that at upload (ITMS-91053), and this is the " \
         "direction a manifest goes stale in — the code moves, the manifest does not"
end

# REVERSE. Also runs to completion. Apple permits the DECLARED reasons only, so an
# unused declaration is a false statement, not a harmless extra.
declared_entries.each_with_index do |entry, index|
  where = "#{MANIFEST_REL}[#{index}]"
  unless entry.is_a?(Hash)
    assert false, "privacy", where,
           "the entry in #{TYPES_KEY} is a dictionary; found #{entry.class}"
    next
  end
  constant = entry[TYPE_KEY]
  slug     = SLUG_FOR[constant]
  declared_labels << (slug || constant.to_s)
  assert !slug.nil?, "privacy", where,
         "the declared category is one of Apple's #{CATEGORY.length}, measured " \
         "#{MEASURED_ON} against #{MEASURED_AGAINST}; found #{constant.inspect}. An " \
         "unrecognised constant is not a category Apple validates — it is a typo that " \
         "declares nothing"
  next if slug.nil?
  declared_slugs << slug

  assert used.key?(slug), "privacy", where,
         "the manifest declares the #{slug} category but no comment-stripped Swift in " \
         "the two application targets uses it. Apple's own words: you may use these APIs " \
         "and the data derived from their use for the declared reasons ONLY, which makes " \
         "an unused declaration a false statement rather than a harmless extra"

  reasons = entry[REASONS_KEY]
  assert reasons.is_a?(Array) && !reasons.empty?, "privacy", where,
         "#{REASONS_KEY} is a NON-EMPTY array for the #{slug} category; found " \
         "#{reasons.inspect}. A declared category with no reason is exactly what " \
         "ITMS-91055 rejects"
  next unless reasons.is_a?(Array)

  valid = REASONS.fetch(slug)
  bad   = reasons.reject { |r| valid.include?(r) }
  assert bad.empty?, "privacy", where,
         "every reason declared for the #{slug} category is valid FOR THAT CATEGORY " \
         "(#{valid.join(', ')}, measured #{MEASURED_ON}); found #{bad.join(', ')}. A " \
         "reason valid for another category is an invalid reason here, which is the " \
         "specific ITMS-91055 rejection"
end

# The both-empty case, stated as a labelled FACT rather than by silence. On this
# tree today both sides are empty and that is CORRECT — which is why the three red
# controls in evidence/07-04-privacy-gate.txt, not this line, are what make the
# gate worth anything.
used_slugs = used.keys.sort
assert used_slugs.sort == declared_slugs.uniq.sort, "privacy", MANIFEST_REL,
       "the used set and the declared set match exactly in BOTH directions " \
       "(used: [#{used_slugs.join(', ')}] / declared: [#{declared_slugs.uniq.sort.join(', ')}])" \
       "#{used_slugs.empty? && declared_slugs.empty? ? ' — both are EMPTY, which is this ' \
       'tree\'s correct state and is asserted here rather than left as an absence' : ''}"

# ─── P11: the archive half (declared here, driven by plan 07-13) ─────────────

archive_checked = false
archive_reason  = "no --archive supplied; the SOURCE manifest was checked and the built " \
                  "bundle was not. Plan 07-13 supplies one per generator per platform"

if ARCHIVE
  bundle = File.expand_path(ARCHIVE)
  if !File.directory?(bundle)
    assert false, "privacy", bundle, "the --archive path is a bundle directory"
    archive_reason = "the --archive path #{bundle} is not a directory"
  else
    # Bundle SHAPE, never a product name: a macOS bundle nests its executable and
    # its resources under Contents/.
    nested   = File.directory?(File.join(bundle, "Contents"))
    embedded = nested ? File.join(bundle, "Contents", "Resources", ARCHIVE_LEAF)
                      : File.join(bundle, ARCHIVE_LEAF)
    embedded = File.join(bundle, "Resources", ARCHIVE_LEAF) if !nested && !File.file?(embedded)
    here = File.file?(embedded)
    assert here, "privacy", bundle,
           "the built #{nested ? 'macOS' : 'iOS'} bundle carries an embedded " \
           "#{ARCHIVE_LEAF}; a bundle without one ships no manifest at all, which is " \
           "the artefact-level form of the failure this whole gate is about"
    if here
      embedded_sha = Digest::SHA256.hexdigest(File.binread(embedded))
      assert embedded_sha == manifest_sha, "privacy", bundle,
             "the embedded manifest is byte-identical to #{MANIFEST_REL} " \
             "(source #{manifest_sha}, embedded #{embedded_sha}). This is the artefact, " \
             "not the input — a source-only gate passing over a bundle that does not " \
             "match it is the class this repository has already produced twice"
      archive_checked = true
      archive_reason  = "embedded #{ARCHIVE_LEAF} read from #{File.basename(bundle)} " \
                        "(#{nested ? 'macOS' : 'iOS'} bundle shape), sha256 #{embedded_sha}"
    else
      archive_reason = "no #{ARCHIVE_LEAF} found inside #{File.basename(bundle)}"
    end
  end
end

# ─── labelled counts, printed on success as well as on failure ───────────────

puts
puts "privacy_swift_from_shared=#{from_shared}"
puts "privacy_swift_from_ios=#{from_ios}"
puts "privacy_swift_from_macos=#{from_macos}"
puts "privacy_swift_total=#{population.length}"
puts "privacy_swift_outside_shared=#{population.length - from_shared}"
puts "privacy_swift_from_xcodegen=#{yml_pop.length}"
puts "privacy_swift_from_tuist=#{swift_pop.length}"
puts "privacy_swift_bytes_scanned=#{scanned_bytes}"
puts "privacy_swift_floor=#{SWIFT_FLOOR}"
puts "privacy_category_tokens=assembled"
puts "privacy_categories_known=#{CATEGORY.length}"
puts "privacy_symbols_swept=#{SYMBOLS.values.flatten.uniq.length}"
puts "privacy_hits_stripped=#{stripped_hits}"
puts "privacy_hits_in_comments=#{raw_hits - stripped_hits}"
puts "manifest_parse_route=#{parse_route}"
puts "privacy_manifest_format=#{manifest_format}"
puts "privacy_manifest_sha256=#{manifest_sha}"
puts "privacy_categories_used=#{used_slugs.join(',')}"
puts "privacy_categories_declared=#{declared_labels.sort.uniq.join(',')}"
used_slugs.each do |slug|
  used[slug].each { |rel, line, symbol| puts "privacy_use #{slug} #{rel}:#{line}=#{symbol}" }
end
puts "privacy_archive_checked=#{archive_checked}"
puts "privacy_archive_reason=#{archive_reason}"
puts "privacy_measured_on=#{MEASURED_ON}"

verdict!
