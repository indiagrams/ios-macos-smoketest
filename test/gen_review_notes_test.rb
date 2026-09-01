#!/usr/bin/env ruby
# frozen_string_literal: true

# Regression test for tools/gen-review-notes.rb.
#
# Why this exists: D-13 states that the argument reaching App Review is the
# argument that was reasoned about, and it states it mechanically rather than by
# convention. The mechanism is the generator, so the mechanism needs pinning —
# an unverified drift check is worse than none, because it converts "we are not
# sure" into "CI says we are fine."
#
# The load-bearing case is the APP_REVIEW_NOTES override (Pitfall 3).
# fastlane's read_review_field resolves ENV["APP_REVIEW_NOTES"] -> notes.txt ->
# omit, and .bootstrap.env.example recommends the env-var route, so the template
# actively steers a forker onto the path that defeats the generator. A check
# that only compared two files would stay green while Apple received completely
# different text. Cases 9, 10 and 11 pin both directions of that: a non-empty
# assignment in either the process environment or .bootstrap.env fails the
# build, and an empty assignment does not.
#
# Design constraint: this suite must NOT read or write the real
# docs/REVIEW-ARGUMENTS.md or the real fastlane/metadata/review_information/
# notes.txt. Those do not exist in usable form while this plan runs, and the
# generator must be verifiable on its own. Every case builds a throwaway repo
# tree with Dir.mktmpdir, invokes the generator there as a subprocess with an
# explicit environment, and lets the block form of mktmpdir clean up.
#
# Runnable locally:
#   ruby test/gen_review_notes_test.rb
#
# No gem, no framework, no rake task — matching test/parser_test.rb.

require "open3"
require "tmpdir"
require "fileutils"
require "rbconfig"

SCRIPT = File.expand_path("../tools/gen-review-notes.rb", __dir__)
DOC    = "docs/REVIEW-ARGUMENTS.md"
NOTES  = "fastlane/metadata/review_information/notes.txt"

@failures = 0

def assert_eq(actual, expected, label)
  if actual == expected
    puts "  ✓ #{label}"
  else
    puts "  ✗ #{label}"
    puts "    expected: #{expected.inspect}"
    puts "    actual:   #{actual.inspect}"
    @failures += 1
  end
end

# Builds a throwaway repo-shaped tree containing only the paths the generator
# touches, writes the fixture document, and yields the tree root.
def with_tree(markdown)
  Dir.mktmpdir("gen-review-notes-test") do |root|
    FileUtils.mkdir_p(File.join(root, "docs"))
    FileUtils.mkdir_p(File.join(root, File.dirname(NOTES)))
    File.write(File.join(root, DOC), markdown)
    yield root
  end
end

# Runs the generator inside the throwaway tree. APP_REVIEW_NOTES is explicitly
# cleared unless a case passes its own value, so the suite is unaffected by
# whatever the developer happens to have exported.
def gen(root, *args, env: {})
  base = { "APP_REVIEW_NOTES" => nil }
  stdout, stderr, status = Open3.capture3(
    base.merge(env), RbConfig.ruby, SCRIPT, *args, chdir: root
  )
  [stdout, stderr, status.exitstatus]
end

def notes_at(root)
  path = File.join(root, NOTES)
  File.exist?(path) ? File.read(path) : nil
end

def doc_with(body, id: "core")
  [
    "# Review arguments (fixture)",
    "",
    "Prose above the block, which must never be extracted.",
    "",
    "<!-- BEGIN:REVIEW-NOTES id=#{id} -->",
    body,
    "<!-- END:REVIEW-NOTES id=#{id} -->",
    "",
    "Prose below the block, which must never be extracted.",
    ""
  ].join("\n")
end

puts "gen-review-notes regression tests:"

# 1. Extraction — the block body, and nothing around it.
with_tree(doc_with("First argument line.\nSecond argument line.\nThird argument line.")) do |root|
  _out, err, code = gen(root)
  assert_eq code, 0, "extraction: generating from a well-formed fixture exits 0 (stderr: #{err.strip})"
  assert_eq notes_at(root),
            "First argument line.\nSecond argument line.\nThird argument line.\n",
            "extraction: notes.txt holds exactly the block body, no sentinels, no surrounding prose"
end

# 2. Normalization — trailing whitespace and a blank final line are removed,
#    exactly one terminating newline survives. This is what makes the .md/.txt
#    comparison stable despite .editorconfig trimming one and not the other.
with_tree(doc_with("Alpha line   \nBeta line\t\n   \n")) do |root|
  gen(root)
  assert_eq notes_at(root), "Alpha line\nBeta line\n",
            "normalization: per-line rstrip, trailing blank lines dropped, single final newline"
end

# 3. Second-block isolation — the contract Phase 8's macOS addendum depends on.
two_blocks = [
  "# Review arguments (fixture)",
  "",
  "<!-- BEGIN:REVIEW-NOTES id=core -->",
  "Core body line.",
  "<!-- END:REVIEW-NOTES id=core -->",
  "",
  "<!-- BEGIN:REVIEW-NOTES id=macos -->",
  "macOS addendum line.",
  "<!-- END:REVIEW-NOTES id=macos -->",
  ""
].join("\n")

with_tree(two_blocks) do |root|
  gen(root)
  assert_eq notes_at(root), "Core body line.\n",
            "block isolation: default invocation emits only the id=core body"
  gen(root, "--id", "macos")
  assert_eq notes_at(root), "macOS addendum line.\n",
            "block isolation: --id macos emits only the id=macos body"
end

# 4. Missing block — a doc with no matching sentinels fails loudly.
with_tree(doc_with("Body.", id: "macos")) do |root|
  _out, err, code = gen(root)
  assert_eq code, 1, "missing block: absent id=core sentinels exit 1"
  assert_eq err.include?("core"), true, "missing block: stderr names the id that could not be resolved"
  assert_eq notes_at(root), nil, "missing block: nothing is written to the destination"
end

# 5. TODO guard — read_review_field drops TODO-prefixed values, which would
#    omit the notes field from the submission entirely rather than fail.
with_tree(doc_with("TODO: write the real review notes.")) do |root|
  _out, err, code = gen(root)
  assert_eq code, 1, "TODO guard: a block starting with TODO exits 1"
  assert_eq err.include?("TODO"), true, "TODO guard: stderr names the TODO prefix as the cause"
end

# 6. Length guard — reports the measured length and the limit, not just failure.
with_tree(doc_with("x" * 3600)) do |root|
  _out, err, code = gen(root)
  assert_eq code, 1, "length guard: a block over the cap exits 1"
  assert_eq err.include?("3601"), true, "length guard: stderr reports the actual character count"
  assert_eq err.include?("3500"), true, "length guard: stderr reports the limit"
end

# 7. --check in sync.
with_tree(doc_with("In-sync argument body.")) do |root|
  gen(root)
  _out, err, code = gen(root, "--check")
  assert_eq code, 0, "--check: an in-sync tree exits 0 (stderr: #{err.strip})"
end

# 8. --check drift — the negative case D-13 exists for.
with_tree(doc_with("In-sync argument body.")) do |root|
  gen(root)
  File.open(File.join(root, NOTES), "a") { |f| f.puts "Sneaked-in edit that never passed review." }
  _out, err, code = gen(root, "--check")
  assert_eq code, 1, "--check: an edited notes.txt exits 1"
  assert_eq err.include?(NOTES), true, "--check: drift message names the destination path"
end

# 9. --check with .bootstrap.env setting the override. The tree is otherwise
#    perfectly in sync — which is exactly why a file-only diff would pass here.
with_tree(doc_with("In-sync argument body.")) do |root|
  gen(root)
  File.write(File.join(root, ".bootstrap.env"), "APP_NAME=Whatever\nAPP_REVIEW_NOTES=something else entirely\n")
  _out, err, code = gen(root, "--check")
  assert_eq code, 1, "--check: a non-empty APP_REVIEW_NOTES in .bootstrap.env exits 1 despite the file matching"
  assert_eq err.include?("APP_REVIEW_NOTES"), true, "--check: .bootstrap.env override message names the variable"
end

# 10. --check with the process environment setting the override.
with_tree(doc_with("In-sync argument body.")) do |root|
  gen(root)
  _out, err, code = gen(root, "--check", env: { "APP_REVIEW_NOTES" => "something else entirely" })
  assert_eq code, 1, "--check: APP_REVIEW_NOTES in the process environment exits 1 despite the file matching"
  assert_eq err.include?("APP_REVIEW_NOTES"), true, "--check: environment override message names the variable"
end

# 11. --check with an empty assignment. A placeholder line is not an override
#     and must not fail the build — a check that cried wolf here would be
#     disabled within a week.
with_tree(doc_with("In-sync argument body.")) do |root|
  gen(root)
  File.write(File.join(root, ".bootstrap.env"), "APP_NAME=Whatever\nAPP_REVIEW_NOTES=\n")
  _out, err, code = gen(root, "--check")
  assert_eq code, 0, "--check: an empty APP_REVIEW_NOTES= assignment is not an override (stderr: #{err.strip})"
end

# 12. --id validation.
with_tree(doc_with("Body.")) do |root|
  _out, err, code = gen(root, "--id", "../../etc")
  assert_eq code, 1, "--id validation: a traversal-shaped id exits 1"
  assert_eq err.include?("../../etc"), true, "--id validation: stderr names the rejected id"
end

# 13. --dest validation.
with_tree(doc_with("Body.")) do |root|
  _out, err, code = gen(root, "--dest", "../outside.txt")
  assert_eq code, 1, "--dest validation: a destination outside fastlane/metadata/ exits 1"
  assert_eq err.include?("outside.txt"), true, "--dest validation: stderr names the rejected destination"
end

# 14. Unknown arguments are rejected rather than ignored.
with_tree(doc_with("Body.")) do |root|
  _out, _err, code = gen(root, "--frobnicate")
  assert_eq code, 1, "argv handling: an unrecognised flag exits 1 instead of running silently"
end

if @failures.zero?
  puts "\nAll gen-review-notes regression tests passed."
  exit 0
else
  puts "\n#{@failures} test(s) failed."
  exit 1
end
