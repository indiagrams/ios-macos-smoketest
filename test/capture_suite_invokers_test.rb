#!/usr/bin/env ruby
# frozen_string_literal: true

# B-01 / UL-101 — every path able to run the macOS App Store capture suite is on a
# declared allowlist, and this gate FAILS the day a new one appears.
#
# WHY THIS EXISTS
#
#   D-155 recorded, as a measured fact, that exactly TWO paths run
#   AppMacOSUITests/AppStoreScreenshotTests. There are FOUR. The two it missed run
#   the suite by SCHEME INCLUSION -- `xcodebuild test -scheme App-macOS` with no
#   -only-testing runs every target in that scheme's Test action, and that action
#   includes AppMacOSUITests -- so neither path ever NAMES the suite and a grep for
#   the suite name is structurally blind to both. That is UL-073's shape a second
#   time in this repository.
#
#   The consequence was not cosmetic. One of the two missed paths is
#   .github/workflows/pr.yml's macOS matrix cell, which is BOTH required status
#   contexts "app (macOS)" and "app (Tuist macOS)" in branch protection on main.
#   Plan 08.6-03 ships a default-STRICT refusal: on a display too short to hold the
#   capture window, the suite now fails instead of skipping unless the run declares
#   itself a non-capture run. Shipped against the undercount, that refusal would
#   have turned both required contexts red on every pull request -- every PR
#   unmergeable, with no way out but an admin edit to protection.
#
#   THE FIX FOR A MISCOUNT IS NOT A BETTER COUNT. A corrected number decays the
#   moment somebody adds a workflow; it decays silently, and the next person to
#   read D-155 believes it. So the number is INSTRUMENTED: this file enumerates
#   invokers BY SCHEME MEMBERSHIP, compares them against an allowlist that records
#   what is known about each, and goes red when the set changes in either
#   direction.
#
# WHAT IT ASSERTS, AND WHY EACH CLAUSE IS THERE
#
#   1. The two generator manifests AGREE about which targets each scheme's Test
#      action runs. A file listed on one generator only silently loses a platform,
#      and this gate's whole premise is that scheme membership is knowable.
#   2. The capture suite really is in the target this gate tracks. If the class
#      moves to another target, every clause below keeps passing while answering
#      about the wrong population.
#   3. Every DISCOVERED invoker is on the allowlist -- a new one fails by name.
#   4. Every ALLOWLISTED path is still discovered, with the recorded number of
#      invocation sites. This half matters as much as clause 3 and is the one a
#      reader is likeliest to think redundant: it is what fails when the SCANNER
#      goes blind. A gate that silently matches nothing passes clause 3 perfectly
#      and forever. It also catches a second invocation added to a file already on
#      the list.
#   5. Every invoker whose allowlist row names a declaration file actually has the
#      declaration in that file -- otherwise the row is a claim, not a check.
#
# HOW AN INVOKER IS DECIDED, AND WHICH WAY IT ERRS
#
#   For each `xcodebuild test` / `test-without-building` command found under the
#   scanned roots (continuation lines joined first):
#
#     * resolve its -scheme. A literal wins; `${{ matrix.scheme }}` resolves to the
#       scheme values declared in that same workflow; anything else is UNRESOLVED.
#     * if the scheme resolves and NONE of its candidates runs the capture target,
#       the command is not an invoker.
#     * parse -only-testing:. No selectors at all means the WHOLE scheme runs, so
#       the capture suite runs. Selectors that name the capture target with no
#       class, or name the capture suite class explicitly, run it; selectors naming
#       a different class in that target do NOT -- which is how the four
#       CaptureDeclarationProbe steps are correctly excluded. That is parsed from
#       the flag, never taken from a neighbouring comment.
#     * -skip-testing: covering the capture suite removes it again.
#
#   WHERE IT IS UNCERTAIN IT ERRS TOWARD *MORE* INVOKERS, deliberately. An
#   unresolved scheme, or an unresolvable shell expansion sitting where scoping
#   flags go (ci/test-migrate-identity.sh's MACOS_SCOPE_FLAGS array is exactly
#   that), counts as running the suite. A false positive costs one allowlist row
#   and a sentence explaining it. A false negative is a path that can reach
#   ci/extract-mac-screenshots.sh:53's rm with nobody watching.
#
# DRIVING IT RED
#
#   --root DIR points the whole scan at a COPY of the tree, so the planted fifth
#   invoker this file shipped with was added to a copy and never to the real
#   workflows (D-163, standing rule 8). The planted diff is kept as
#   evidence/08.6-03-fake-invoker.diff and the observed red is in
#   evidence/08.6-03-guard.txt.

require "optparse"
require "set"

DEFAULT_ROOT = File.expand_path("..", __dir__)
root = DEFAULT_ROOT
OptionParser.new do |o|
  o.banner = "usage: ruby test/capture_suite_invokers_test.rb [--root DIR]"
  o.on("--root DIR", "scan the tree under DIR instead of #{DEFAULT_ROOT}") { |d| root = File.expand_path(d) }
end.parse!
ROOT = root

# The target the capture suite belongs to, and the class itself. Both are asserted
# below rather than assumed.
CAPTURE_TARGET = "AppMacOSUITests"
CAPTURE_SUITE  = "AppStoreScreenshotTests"
CAPTURE_SUITE_FILE = "app/MacOSUITests/#{CAPTURE_SUITE}.swift"

XCODEGEN_MANIFEST = "app/project.yml"
TUIST_MANIFEST    = "app/Project.swift"

# The declaration a fork-owned invoker sets. The TEST_RUNNER_ prefix is the carrier
# and is stripped in transit; the Swift guard reads the bare name (UL-100).
DECLARATION_KEY = "TEST_RUNNER_CAPTURE_NON_STRICT"

# Where commands are looked for. Directories are walked; a plain file is read as
# itself. Kept explicit so the POPULATION is visible rather than implied.
SCAN_ROOTS = [".github/workflows", "ci", "bin", "tools", "fastlane", "Makefile"].freeze

# THE ALLOWLIST. One row per FILE, because line numbers move and a row keyed to one
# is a row that rots. `sites` is how many capture-suite invocations that file is
# known to contain, and a mismatch in EITHER direction is a failure.
#
#   reaches_rm   does this path go on to ci/extract-mac-screenshots.sh:53's rm?
#   owner        fork (we may edit it) or template (D-131, byte-identical pin)
#   declared_in  where its non-capture declaration lives, or why it has none
ALLOWLIST = [
  {
    path: "ci/take-screenshots.sh",
    sites: 1,
    reaches_rm: true,
    owner: "template",
    declared_in: "NONE-BY-DESIGN",
    note: "THE capture path, and the only one that reaches the rm (:187 -> " \
          "ci/extract-mac-screenshots.sh:53). It must NEVER declare: the strict default is " \
          "the whole protection, and a declaration here would restore the tile-destroying skip"
  },
  {
    path: ".github/workflows/review-notes.yml",
    sites: 1,
    reaches_rm: false,
    owner: "fork",
    declared_in: "PENDING-08.6-07",
    note: "the ui-drive-half macOS cell, which names the capture suite explicitly. Its " \
          "declaration and the two D-158 controls are plan 08.6-07's, on a hosted runner, " \
          "because that is the machine supplying the 1024x768 display the controls need"
  },
  {
    path: ".github/workflows/pr.yml",
    sites: 1,
    reaches_rm: false,
    owner: "fork",
    declared_in: ".github/workflows/pr.yml",
    note: "B-01 invoker 3 — implicit, by scheme inclusion, and BOTH required contexts " \
          "app (macOS) and app (Tuist macOS). Undeclared, the refusal makes every PR unmergeable"
  },
  {
    path: "ci/test-migrate-identity.sh",
    sites: 2,
    reaches_rm: false,
    owner: "template",
    declared_in: ".github/workflows/migrate.yml",
    note: "B-01 invoker 4 — implicit, scoped only when MIGRATE_MACOS_ONLY_TESTING is set and " \
          ":410 defaults it OFF. TEMPLATE-OWNED, so the declaration is set in the fork-owned " \
          "workflow step that invokes it and propagates through the shell into the script's " \
          "xcodebuild child. Not one template byte moves (D-131)"
  }
].freeze

@checks   = 0
@failures = 0

def assert(condition, label)
  @checks += 1
  if condition
    puts "  ✓ #{label}"
  else
    puts "  ✗ #{label}"
    @failures += 1
  end
end

# UTF-8 pinned, never inherited -- with LANG unset `Encoding.default_external` is
# US-ASCII and these files carry em dashes (UL-012 / UL-048).
def read_source(relative)
  path = File.join(ROOT, relative)
  return nil unless File.file?(path)

  File.read(path, encoding: "UTF-8")
end

# ── The manifests: which targets does each scheme's Test action run? ───────────

def xcodegen_test_targets(text)
  return nil if text.nil?

  schemes = {}
  current = nil
  in_test = false
  in_targets = false
  text.lines.each do |line|
    if (m = line.match(/\A  ([A-Za-z][\w.-]*):\s*\z/))
      current = m[1]
      in_test = false
      in_targets = false
      schemes[current] ||= []
      next
    end
    next if current.nil?

    if line.match?(/\A    ([a-z]+):\s*\z/)
      in_test = line.match?(/\A    test:\s*\z/)
      in_targets = false
    end
    in_targets = true if in_test && line.match?(/\A      targets:\s*\z/)
    next unless in_test && in_targets

    if (m = line.match(/\A        - ([A-Za-z][\w.-]*)\s*\z/))
      schemes[current] << m[1]
    elsif line.match?(/\A    [a-z]/)
      in_targets = false
    end
  end
  schemes.reject { |_, v| v.empty? }
end

def tuist_test_targets(text)
  return nil if text.nil?

  schemes = {}
  text.scan(/\.scheme\(\s*name:\s*"([^"]+)".*?testAction:\s*\.targets\(\s*\[([^\]]*)\]/m) do |name, list|
    schemes[name] = list.scan(/"([^"]+)"/).flatten
  end
  schemes.reject { |_, v| v.empty? }
end

# ── Command extraction ────────────────────────────────────────────────────────

# Flags no real `xcodebuild test` invocation goes without. Requiring one of them is
# what separates an invocation from a MENTION -- this repository has a step named
# "xcodebuild test — ...", an `echo "... xcodebuild test did not produce one"` and a
# `step "Capture macOS screenshots (xcodebuild test)"`, none of which run anything,
# and all three of which a bare token match counts as invokers. Every genuine
# invocation carries at least one of these; a sentence carries none.
INVOCATION_FLAGS = ["-project", "-workspace", "-scheme", "-xctestrun", "-destination"].freeze

# Joins backslash continuations so a multi-line invocation is one string, while
# reporting the line the command STARTS on. Works identically for a shell script and
# for a workflow `run: |` block. Line numbers are the real file's, not the joined
# text's: a number that silently drifts is worse than no number, because it reads
# like a measurement.
def commands_in(text)
  lines = text.lines
  found = []
  index = 0
  while index < lines.length
    start = index
    command = +""
    loop do
      raw = lines[index] || ""
      command << raw.sub(/\\\s*\z/, " ").chomp
      break unless raw.rstrip.end_with?("\\") && index + 1 < lines.length

      index += 1
    end
    index += 1
    next if lines[start].lstrip.start_with?("#")
    next unless command.match?(/xcodebuild\s+(test|test-without-building)\b/)
    next unless INVOCATION_FLAGS.any? { |flag| command.include?("#{flag} ") || command.include?("#{flag}:") }

    found << [command.strip, start + 1]
  end
  found
end

def scan_files
  files = []
  SCAN_ROOTS.each do |entry|
    path = File.join(ROOT, entry)
    if File.directory?(path)
      files.concat(Dir.glob(File.join(path, "**", "*")).select { |f| File.file?(f) })
    elsif File.file?(path)
      files << path
    end
  end
  files.map { |f| f.delete_prefix("#{ROOT}/") }.sort.uniq
end

# ── Resolution ────────────────────────────────────────────────────────────────

MATRIX_INTERPOLATION = /\$\{\{\s*matrix\.(\w+)\s*\}\}/

# Every value a workflow declares for a matrix key, taken from the file's own
# `include:` rows. Non-vacuity is the caller's job: an interpolation that resolves
# to NOTHING must be loud, not silently empty.
def matrix_values(text, key)
  text.scan(/^\s*#{Regexp.escape(key)}:\s*(.+?)\s*$/).flatten
      .map { |v| v.strip.sub(/\A["']/, "").sub(/["']\z/, "") }
      .reject { |v| v.empty? || v.start_with?("#") }
end

def resolve_schemes(command, text)
  raw = command[/-scheme\s+("[^"]*"|'[^']*'|\S+)/, 1]
  return [:none] if raw.nil?

  raw = raw.gsub(/\A["']|["']\z/, "")
  if (m = raw.match(MATRIX_INTERPOLATION))
    values = matrix_values(text, m[1])
    return values.empty? ? [:unresolved] : values
  end
  return [:unresolved] if raw.include?("$")

  [raw]
end

# `-only-testing:X` and `-only-testing X` are both accepted by xcodebuild.
def selectors(command, flag, text)
  raw = command.scan(/#{Regexp.escape(flag)}[:= ]\s*("[^"]*"|'[^']*'|\S+)/).flatten
  raw.flat_map do |token|
    token = token.gsub(/\A["']|["']\z/, "")
    if (m = token.match(MATRIX_INTERPOLATION))
      values = matrix_values(text, m[1])
      values.flat_map { |v| v.scan(/#{Regexp.escape(flag)}:(\S+)/).flatten }
    else
      [token]
    end
  end
end

# Does this selector cause the capture SUITE to run? The target segment may carry a
# shell interpolation prefix -- the template spells it "${APP_NAME}MacOSUITests" --
# so the comparison is on the resolved tail.
def selects_capture_suite?(selector)
  target, klass, = selector.split("/")
  return false if target.nil?

  target = target.sub(/\A\$\{[^}]*\}/, "").sub(/\A\$\w+/, "")
  bare_target = CAPTURE_TARGET.sub(/\AApp/, "")
  return false unless target == CAPTURE_TARGET || target == bare_target || target.end_with?(bare_target)

  klass.nil? || klass.empty? || klass == CAPTURE_SUITE
end

# An unresolvable expansion sitting where scoping flags go. Counted as "might be
# unscoped", which is the direction this gate errs in.
def opaque_scoping?(command)
  command.match?(/\$\{[A-Z_]+\[@\]/) || command.match?(/"\$\{?[A-Z_]+_FLAGS/)
end

puts "capture-suite invokers — B-01 / UL-101, enumerated by SCHEME MEMBERSHIP:"
puts

# ── Clause 1 + 2: the premise ─────────────────────────────────────────────────

xcodegen = xcodegen_test_targets(read_source(XCODEGEN_MANIFEST))
tuist    = tuist_test_targets(read_source(TUIST_MANIFEST))

assert !xcodegen.nil? && !xcodegen.empty?,
       "#{XCODEGEN_MANIFEST}: test actions parsed for #{xcodegen&.length || 0} scheme(s) — " \
       "an unparsed manifest would make every clause below answer about nothing"
assert !tuist.nil? && !tuist.empty?,
       "#{TUIST_MANIFEST}: test actions parsed for #{tuist&.length || 0} scheme(s)"

xcodegen ||= {}
tuist ||= {}

shared = (xcodegen.keys & tuist.keys).sort
assert !shared.empty?, "both manifests declare the same scheme names (shared: #{shared.join(', ')})"
disagreements = shared.reject { |s| xcodegen[s].sort == tuist[s].sort }
assert disagreements.empty?,
       "the two generators AGREE on every shared scheme's Test action targets " \
       "(#{disagreements.empty? ? 'no disagreement' : disagreements.map { |s| "#{s}: xcodegen=#{xcodegen[s].sort.join('+')} tuist=#{tuist[s].sort.join('+')}" }.join('; ')}) " \
       "— a target present on one generator only silently loses a platform, and this gate's " \
       "whole premise is that scheme membership is knowable"

capture_schemes = (xcodegen.keys | tuist.keys).select do |scheme|
  [xcodegen[scheme], tuist[scheme]].compact.any? { |targets| targets.include?(CAPTURE_TARGET) }
end.sort
assert !capture_schemes.empty?,
       "#{CAPTURE_TARGET} is in the Test action of #{capture_schemes.length} scheme(s) " \
       "(#{capture_schemes.empty? ? 'NONE — this gate would find no invokers and pass vacuously' : capture_schemes.join(', ')})"

suite_source = read_source(CAPTURE_SUITE_FILE)
assert !suite_source.nil? && suite_source.match?(/class\s+#{Regexp.escape(CAPTURE_SUITE)}\b/),
       "#{CAPTURE_SUITE_FILE}: still declares #{CAPTURE_SUITE} — if the suite moves to another " \
       "target, every clause below keeps passing while answering about the wrong population"

# ── Discovery ─────────────────────────────────────────────────────────────────

discovered = Hash.new { |h, k| h[k] = [] }
examined = 0

scan_files.each do |relative|
  text = read_source(relative)
  next if text.nil? || !text.valid_encoding?

  commands_in(text).each do |command, number|
    examined += 1
    schemes = resolve_schemes(command, text)
    runs_capture_scheme =
      if schemes == [:none] || schemes.include?(:unresolved)
        true # no scheme to read (an -xctestrun run) or one this gate cannot resolve: err wide
      else
        schemes.any? { |s| capture_schemes.include?(s) }
      end
    next unless runs_capture_scheme

    only = selectors(command, "-only-testing", text)
    skip = selectors(command, "-skip-testing", text)
    runs_suite =
      if only.empty?
        true # the whole scheme's Test action
      elsif opaque_scoping?(command)
        true
      else
        only.any? { |s| selects_capture_suite?(s) }
      end
    runs_suite = false if runs_suite && skip.any? { |s| selects_capture_suite?(s) }
    next unless runs_suite

    discovered[relative] << number
  end
end

assert examined.positive?,
       "found #{examined} xcodebuild test invocation(s) under #{SCAN_ROOTS.join(' ')} — zero " \
       "would mean the scanner is blind and every clause below is vacuous"
assert !discovered.empty?,
       "found #{discovered.values.flatten.length} capture-suite invocation(s) in " \
       "#{discovered.length} file(s) — zero would mean this gate matches nothing and passes forever"

# ── Clause 3: nothing undeclared ──────────────────────────────────────────────

allowed = ALLOWLIST.map { |row| row[:path] }.to_set
undeclared = discovered.keys.reject { |p| allowed.include?(p) }.sort
assert undeclared.empty?,
       "every discovered invoker is on the allowlist " \
       "(#{undeclared.empty? ? 'none undeclared' : "UNDECLARED: #{undeclared.map { |p| "#{p}:#{discovered[p].join(',')}" }.join(' ')}"}) " \
       "— an UNDECLARED invoker runs AppMacOSUITests without saying it is a non-capture run, so " \
       "on a short display (a hosted runner is 1024x768) the capture suite will REFUSE and this " \
       "path goes red. Decide which it is: if it cannot reach ci/extract-mac-screenshots.sh's " \
       "rm, set #{DECLARATION_KEY}=1 in its step's env: block and add a row to ALLOWLIST here; " \
       "if it CAN reach the rm, it must stay strict and the row says so"

# ── Clause 4: nothing has gone quiet ──────────────────────────────────────────

ALLOWLIST.each do |row|
  sites = discovered[row[:path]]
  assert sites.length == row[:sites],
         "#{row[:path]}: #{sites.length} capture-suite invocation(s) found, #{row[:sites]} " \
         "declared#{sites.empty? ? '' : " (lines #{sites.join(', ')})"} — a count that DROPPED " \
         "means this gate has gone blind to a path that still exists; a count that ROSE means a " \
         "new invocation was added to a file already on the list, which clause 3 cannot see. " \
         "Row: reaches_rm=#{row[:reaches_rm]} owner=#{row[:owner]} declared_in=#{row[:declared_in]}"
end

# ── Clause 5: a declaration a row claims is a declaration that exists ─────────

ALLOWLIST.each do |row|
  case row[:declared_in]
  when "NONE-BY-DESIGN", "PENDING-08.6-07"
    next
  else
    text = read_source(row[:declared_in])
    assert !text.nil? && text.include?(DECLARATION_KEY),
           "#{row[:path]}: its declaration is in #{row[:declared_in]}, and that file carries " \
           "#{DECLARATION_KEY} — without it this invoker refuses on a hosted runner. The " \
           "prefixed spelling in an env: block is the one measured to arrive; the same name " \
           "appended to the xcodebuild command line is consumed as a build setting (UL-100)"
  end
end

# ── Named facts, so a change is visible without re-reading this file ──────────

puts
puts "capture_suite_target=#{CAPTURE_TARGET} suite=#{CAPTURE_SUITE}"
puts "capture_suite_schemes=#{capture_schemes.join(',')}"
puts "capture_suite_commands_examined=#{examined}"
puts "capture_suite_invokers=#{discovered.length} sites=#{discovered.values.flatten.length}"
discovered.keys.sort.each do |path|
  row = ALLOWLIST.find { |r| r[:path] == path }
  puts "  #{path}:#{discovered[path].join(',')} reaches_rm=#{row ? row[:reaches_rm] : 'UNDECLARED'} " \
       "owner=#{row ? row[:owner] : 'UNDECLARED'} declared_in=#{row ? row[:declared_in] : 'UNDECLARED'}"
end
pending = ALLOWLIST.select { |r| r[:declared_in] == "PENDING-08.6-07" }.map { |r| r[:path] }
puts "capture_suite_declarations_pending=#{pending.empty? ? 'none' : pending.join(',')}"
puts
if @failures.zero?
  puts "All #{@checks} capture-suite-invoker assertions passed."
  exit 0
else
  puts "#{@failures} of #{@checks} assertion(s) failed."
  exit 1
end
