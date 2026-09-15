#!/usr/bin/env ruby
# frozen_string_literal: true

# Source invariants that a compiler, a linter and a formatter all accept happily
# and that a shipped app is nonetheless wrong without.
#
# Both clauses below exist because a MEASURED defect was, at the moment it was
# fixed, protected by nothing but a comment asking the next reader not to undo it.
# This project's own recurring lesson is that a claim is not a measurement; a
# comment is a claim.
#
#   1. UL-087 — a `private` type in the macOS scene's root content type.
#      SwiftUI names the window's persisted identity after the ROOT CONTENT TYPE:
#      the `NSWindow Frame ...` and `NSSplitView Subview Frames ...` defaults keys
#      and the restoration state. A private (or fileprivate) type's runtime name
#      renders as `(unknown context at $<address>)`, and that address moves with
#      ASLR on EVERY LAUNCH. Measured 2026-09-12: 50 distinct identities in one
#      preferences file, a fresh key pair per launch; and on CI, once one launch
#      had saved restorable state, every later launch "restored" a window no
#      process could match and presented NONE -- foreground, menu bar built,
#      windows=0. The macOS sweep failed 3/3 that way and passed once the type was
#      made internal (ddc4eb8). An internal type's name is stable across launches.
#      A three-process `swiftc` probe confirmed the rule in isolation: `private`
#      and `fileprivate` names carried three different addresses, `internal` none.
#
#   2. CR-01 — an App Review submission lane with no opt-in guard.
#      `fastlane/Fastfile.local` overrides `submit_for_review` on BOTH platforms
#      and each override writes a REVIEW SUBMISSION to App Store Connect, which
#      this fork cannot take back: UL-018 records one unplanned call permanently
#      consuming record 6807393045's single open iOS review slot, still occupied,
#      with no API route to remove it. The macOS lane was gated from the start; the
#      iOS lane was NOT, from `f6f2789` until the Phase 8 close-out measured it --
#      i.e. the safeguard sat on the platform that does not carry the hazard, while
#      `PLATFORMS=ios,macos` dispatches iOS FIRST and `bin/submit.rb` records a
#      failure and CONTINUES.
#
# GREP-GATE HYGIENE. Neither clause is a whole-file grep: each one extracts the
# declaration or the lane body it judges, so this file's own prose describing the
# forbidden shapes cannot satisfy or violate it.

ROOT = File.expand_path("..", __dir__)

APP_SWIFT     = "app/Shared/App.swift"
FASTFILE_LOCAL = "fastlane/Fastfile.local"

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
  unless File.file?(path)
    puts "  ✗ #{relative}: file does not exist"
    @failures += 1
    return ""
  end
  File.read(path, encoding: "UTF-8")
end

puts "#{APP_SWIFT} — UL-087, no private type in the scene's root content type:"

app_swift = read_source(APP_SWIFT)

# The types the scene's content is wrapped in. `.background(Foo(...))` is the one
# that bit; the general clause is "whatever the WindowGroup body composes in".
# `background(` with NO leading dot: `uiTestWindowSize()` calls it as a method on
# `self` from inside a `View` extension, so an anchored `\.background(` matched
# nothing -- caught here by this clause's own "would assert nothing" guard on its
# first run, which is the shape the rest of this phase kept failing to have.
wrapped = app_swift.scan(/\bbackground\(\s*([A-Z][A-Za-z0-9_]*)\s*\(/).flatten.uniq
assert !wrapped.empty?,
       "#{APP_SWIFT}: found the type(s) wrapped into the scene's content " \
       "(#{wrapped.empty? ? 'NONE — this clause would assert nothing' : wrapped.join(', ')})"

wrapped.each do |type|
  decl = app_swift.lines.find { |l| l =~ /^\s*(?:public |internal |private |fileprivate )?(?:final )?(?:struct|class|enum)\s+#{Regexp.escape(type)}\b/ }
  assert !decl.nil?, "#{APP_SWIFT}: #{type} is declared in this file"
  next if decl.nil?

  assert decl !~ /^\s*(?:private|fileprivate)\s/,
         "#{APP_SWIFT}: #{type} is NOT private/fileprivate (UL-087 — a private type " \
         "in the scene's root content type gives the macOS window a per-launch " \
         "ASLR-derived identity, and the app eventually presents no window at all). " \
         "Declared as: #{decl.strip}"
end

puts
puts "#{FASTFILE_LOCAL} — CR-01, every App Review submission lane is opt-in gated:"

fastfile = read_source(FASTFILE_LOCAL)

# Extract each `override_lane :submit_for_review` body: from its own line up to
# the next lane override or platform block, whichever comes first.
lines  = fastfile.lines
starts = lines.each_index.select { |i| lines[i] =~ /^\s*override_lane\s+:submit_for_review\s+do\b/ }

assert starts.length >= 2,
       "#{FASTFILE_LOCAL}: found both platforms' submit_for_review overrides " \
       "(found #{starts.length}). The macOS one has been gated since it was written; " \
       "the iOS one is the half CR-01 found ungated"

starts.each do |i|
  stop = lines.each_index.find { |j| j > i && lines[j] =~ /^\s*(?:override_lane|platform)\s/ } || lines.length
  body = lines[i...stop].join
  # Which platform this override belongs to: the nearest `platform :x do` above it.
  plat_line = lines[0..i].reverse.find { |l| l =~ /^\s*platform\s+:([a-z]+)\s+do/ }
  plat = plat_line ? plat_line[/^\s*platform\s+:([a-z]+)/, 1] : "unknown"

  assert body.include?("FORK_ALLOW_ASC_SUBMIT"),
         "#{FASTFILE_LOCAL}: the `#{plat}` submit_for_review override (line #{i + 1}) is " \
         "gated on FORK_ALLOW_ASC_SUBMIT. Ungated, one invocation writes an " \
         "irreversible REVIEW SUBMISSION — and this record's single open iOS review " \
         "slot is already occupied and not reusable (UL-018)"
end

puts
puts "UI-test launch flags — every `-UITest*` flag is passed WITH a value:"

# A bare `-Flag` in launch arguments takes the NEXT argument as its value in the
# argument domain. Run 34984109925: a valueless `-UITestPersistenceProbe` was
# followed by launchPinned's `-settings.selection encode …`, so it consumed
# `-settings.selection` and shifted every pin after it. Checked per occurrence in
# the UI-test sources, comment lines skipped; `firstIndex(of:` is a READ, not a pass.
FLAG_LITERAL = /"(-UITest[A-Za-z]+)"/
def code_lines(glob)
  Dir.glob(File.join(ROOT, glob)).sort.flat_map do |path|
    File.read(path, encoding: "UTF-8").lines.each_with_index
        .reject { |line, _| line.lstrip.start_with?("//") }
        .map { |line, i| [path.delete_prefix("#{ROOT}/"), i + 1, line] }
  end
end

app_flags = code_lines("app/Shared/**/*.swift").flat_map { |_, _, l| l.scan(FLAG_LITERAL).flatten }.uniq.sort
assert !app_flags.empty?,
       "found the `-UITest*` flags the app reads (#{app_flags.empty? ? 'NONE — this clause would assert nothing' : app_flags.join(', ')})"

passed = Hash.new(0)
%w[app/UITests/**/*.swift app/MacOSUITests/**/*.swift app/UITestSupport/**/*.swift].each do |glob|
  code_lines(glob).each do |file, number, line|
    line.to_enum(:scan, FLAG_LITERAL).each do
      match = Regexp.last_match
      next if match.pre_match =~ /firstIndex\(of:\s*\z/
      # The value is the next token, and it must not itself be a flag: `["-UITestA", "-UITestB"]`
      # passes A with NO value, which is the UL-094 defect this clause exists to catch.
      valued = match.post_match =~ /\A\s*,\s*(?!"-)[^\s\]]/
      assert valued, "#{file}:#{number}: #{match[1]} is passed with a value (line: #{line.strip})"
      passed[match[1]] += 1 if valued
    end
  end
end

app_flags.each do |flag|
  assert passed[flag].positive?, "#{flag}: the app reads it and at least one UI test passes it with a value (#{passed[flag]} found)"
end

puts
puts "app_source_rules_wrapped_types=#{wrapped.join(',')}"
puts "app_source_rules_submit_lanes=#{starts.length}"
puts "app_source_rules_uitest_flags=#{app_flags.join(',')} passes=#{passed.values.sum}"
puts
if @failures.zero?
  puts "All #{@checks} app-source-rule assertions passed."
  exit 0
else
  puts "#{@failures} of #{@checks} assertion(s) failed."
  exit 1
end
