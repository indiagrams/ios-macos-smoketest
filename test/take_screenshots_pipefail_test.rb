#!/usr/bin/env ruby
# frozen_string_literal: true

# D-170 — the one line in `ci/take-screenshots.sh` that makes a failing macOS
# capture test STOP the run before anything deletes the existing tiles.
#
# WHY THIS EXISTS
#
#   `ci/take-screenshots.sh` runs the macOS capture suite as
#
#       xcodebuild test-without-building … 2>&1 | xcbeautify --quiet || { … exit 1; }
#
#   and then, on the next line, calls `ci/extract-mac-screenshots.sh`, whose `rm`
#   at `:53` DELETES the eight `fastlane/Mac_screenshots/en-US/macos-*.png` tiles
#   BEFORE it discovers whether the run produced any attachment at all -- its "no
#   attachments found" exit is at `:156`, a hundred lines later. Those tiles are
#   untracked and gitignored (`.gitignore:68`), so nothing restores them.
#
#   A shell pipeline's exit status is its LAST command's. `xcbeautify` succeeds at
#   formatting a failing build's output, so `|| { … exit 1; }` would be BLIND and
#   the run would continue into the delete -- except that `set -euo pipefail` at
#   the top of the file makes the pipeline report the failing member instead. That
#   one line is the whole abort. Re-measured in this shell, both directions
#   (08.6-01, Part 3):
#
#       zsh -c 'set -euo pipefail; false | cat; echo status=$?'   -> no output, shell exit 1
#       zsh -c 'set -eu;           false | cat; echo status=$?'   -> status=0,  shell exit 0
#
#   WITHOUT `pipefail` the pipeline REPORTS SUCCESS. The Swift-side refusal this
#   phase ships (`app/MacOSUITests/CaptureFit.swift`) protects the tiles only
#   because a refusal becomes a non-zero exit that stops the script. Drop
#   `pipefail` and the guard keeps failing correctly and stops mattering.
#
# THE TRAP THIS FILE IS BUILT AROUND
#
#   `ci/take-screenshots.sh` is a template-owned file (D-131). This fork does not edit it
#   and must not: it is byte-identical to its upstream pin today, and keeping it
#   that way is the property `tools/gates/template-identity-check.sh` enforces. So
#   this test's job is NOT to stop this fork from changing the line. It is to FIRE
#   THE DAY UPSTREAM DROPS IT, in a re-adoption that otherwise looks clean.
#
#   That is why every assertion below is TEXTUAL, and it is textual ON PURPOSE.
#   There is no way to execute the property -- proving the abort by running it
#   means running a capture, and a capture is the thing whose failure mode this
#   guards. A later reader must not "fix" this file for being a string match; the
#   string IS the subject.
#
#   Comment lines are stripped before the shell script is searched. A future
#   upstream revision that DELETES the line while mentioning it in a comment
#   ("we no longer set …") would otherwise satisfy a whole-file match and this
#   gate would report green on exactly the change it exists to catch (standing
#   rule 10: `grep -c` counts comments).
#
#   AND NOTHING HERE ASSERTS ANYTHING ABOUT THE SWIFT GUARD'S LOGIC. D-170 is
#   explicit about it: a ruby test reading Swift source to re-state what the guard
#   does is the vacuous shape this project keeps finding -- it passes while the
#   compiled behaviour is anything at all. The guard's own logic is exercised by
#   `evidence/08.6-03-decision-harness.swift`, which COMPILES the shipped file.
#   Nothing below opens a `.swift` file.
#
# DRIVING IT RED
#
#   `--root DIR` points every read at a COPY of the tree, so the two controls this
#   file shipped with -- the line deleted, and the line weakened to `set -eu` --
#   were observed against copies and never by editing the shipped script (D-163,
#   standing rule 8). Both reds and the restored green are recorded in
#   `evidence/08.6-03-guard.txt`.

require "optparse"

DEFAULT_ROOT = File.expand_path("..", __dir__)
root = DEFAULT_ROOT
OptionParser.new do |o|
  o.banner = "usage: ruby test/take_screenshots_pipefail_test.rb [--root DIR]"
  o.on("--root DIR", "read the tree under DIR instead of #{DEFAULT_ROOT}") { |d| root = File.expand_path(d) }
end.parse!
ROOT = root

CAPTURE_SCRIPT = "ci/take-screenshots.sh"

# The exact text asserted. Spelled once, so the message and the assertion cannot
# disagree about what is being looked for.
STRICT_LINE = "set -euo pipefail"

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
    return nil
  end
  File.read(path, encoding: "UTF-8")
end

# Shell comments stripped, so a comment MENTIONING a line cannot stand in for the
# line. `#!` on line 1 is a comment to this filter too, which is correct: nothing
# below is asserted about the shebang.
def code_lines(text)
  text.lines.each_with_index
      .reject { |l, _| l.lstrip.start_with?("#") }
      .map { |l, i| [l, i + 1] }
end

puts "#{CAPTURE_SCRIPT} — D-170, the abort that stands between a failing capture and the tile delete:"

script = read_source(CAPTURE_SCRIPT)

if script.nil?
  puts
  puts "#{@failures} of #{@checks} assertion(s) failed."
  exit 1
end

code = code_lines(script)

# 1 — THE FILE IS THERE AND IS NOT EMPTY. Without this, every clause below would
# be asserting over an empty array and would pass by vacuity, which is the
# failure mode this repository has shipped more than once.
assert !code.empty?,
       "#{CAPTURE_SCRIPT}: has #{code.length} non-comment line(s) — a clause over an empty " \
       "file asserts nothing"

# 2 — THE STRICT LINE ITSELF, as its own statement and not as a substring of prose.
strict_hits = code.select { |line, _| line.strip == STRICT_LINE }.map { |_, number| number }
assert !strict_hits.empty?,
       "#{CAPTURE_SCRIPT}: carries `#{STRICT_LINE}` as an executable statement " \
       "(found #{strict_hits.length}). Without `pipefail` a pipeline reports its LAST " \
       "command's status, so a FAILING capture test formatted by a SUCCEEDING xcbeautify " \
       "exits 0, the `|| { … exit 1; }` guard never fires, and the run continues into " \
       "ci/extract-mac-screenshots.sh — whose rm at :53 deletes the untracked, gitignored " \
       "macos-*.png tiles before it discovers at :156 that there are no attachments. This " \
       "file is TEMPLATE-OWNED (D-131) and this fork does not edit it, so a red here means " \
       "UPSTREAM dropped the line: do not patch it locally, re-pin or raise it upstream"

# 3 — AND THE SHAPE THE LINE EXISTS FOR IS STILL THERE. `pipefail` present over a
# script that no longer pipes into a formatter, or no longer guards the pipe, is a
# line protecting nothing — and this tripwire would keep reporting green over it.
# Matched structurally (a pipe into the formatter, on a line that opens an `||`
# block) rather than by naming any test suite: the suite name belongs to the
# Swift side and naming it here is how a ruby file starts asserting about Swift.
guarded = code.select { |l, _| l.include?("| xcbeautify") && l.include?("|| {") }
assert !guarded.empty?,
       "#{CAPTURE_SCRIPT}: still pipes into the formatter under an `|| { … }` guard " \
       "(found #{guarded.length} such invocation(s)) — `#{STRICT_LINE}` protects THAT shape, " \
       "and a script that no longer has it has moved the hazard somewhere this gate is not " \
       "looking"

# And the guard's body actually aborts. A `|| { echo …; }` that only warns leaves
# the run walking into the delete just as surely as a blind pipeline does.
aborting = script.scan(/\|\| \{(.*?)\n\s*\}/m).flatten.count { |body| body =~ /^\s*exit 1\s*$/ }
assert aborting.positive?,
       "#{CAPTURE_SCRIPT}: at least one `|| { … }` guard ends in `exit 1` rather than only " \
       "warning (found #{aborting}) — a guard that fires and continues is the same outcome " \
       "as a guard that never fires"

puts
puts "take_screenshots_pipefail_root=#{ROOT}"
puts "take_screenshots_pipefail_strict_lines=#{strict_hits.join(',')}"
puts "take_screenshots_pipefail_guarded_pipes=#{guarded.length} aborting_guards=#{aborting}"
puts
if @failures.zero?
  puts "All #{@checks} take-screenshots pipefail assertions passed."
  exit 0
else
  puts "#{@failures} of #{@checks} assertion(s) failed."
  exit 1
end
