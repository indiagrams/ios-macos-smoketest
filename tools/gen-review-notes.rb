#!/usr/bin/env ruby
# frozen_string_literal: true

# Generate fastlane/metadata/review_information/notes.txt from the delimited
# block in docs/REVIEW-ARGUMENTS.md — or, with --check, fail when the two have
# drifted apart.
#
# Why this exists: docs/REVIEW-ARGUMENTS.md is the source of truth for the text
# App Review actually reads. Before this script, notes.txt was a hand-maintained
# "TODO:" placeholder with nothing connecting it to the reasoning that produced
# it, so the argument that shipped to Apple could quietly stop being the argument
# that was reasoned about — and nobody would find out until a rejection landed.
# --check turns that guarantee from a convention into a mechanism: divergence
# fails closed in CI instead of surfacing at submit time. (PRINCIPLES #7: the
# why, not the what.)
#
# Why --check also inspects APP_REVIEW_NOTES: fastlane's read_review_field
# resolves ENV["APP_REVIEW_NOTES"] -> notes.txt -> omit, and
# .bootstrap.env.example actively recommends the env-var route. A check that
# only compared two files would be green while the env var silently overrode
# both — false assurance about the exact property this script exists to
# guarantee. So the check asserts the property, not the diff.
#
# Usage (run from the repository root):
#   ruby tools/gen-review-notes.rb                    # write notes.txt
#   ruby tools/gen-review-notes.rb --check            # verify; exit 1 on drift
#   ruby tools/gen-review-notes.rb --id macos --dest fastlane/metadata/...
#
# Ruby stdlib only. No gem, no Gemfile entry, no test framework.

# The source is a constant and is NEVER taken from argv: argv must not be able
# to redirect where the outbound text comes from.
SRC = "docs/REVIEW-ARGUMENTS.md"

DEFAULT_DEST = "fastlane/metadata/review_information/notes.txt"
DEFAULT_ID   = "core"

# Every destination must live under fastlane's metadata tree — the only place
# whose contents are meant to reach Apple.
DEST_ROOT = "fastlane/metadata/"

# Headroom under the App Store Connect "Notes" field cap, widely reported as
# 4000 characters. That 4000 figure is UNVERIFIED against any Apple first-party
# page (see RESEARCH Assumptions Log A1); Phase 8/9 verifies the real ceiling
# empirically at submit time. 3500 leaves margin so a late edit cannot overflow
# it without this script noticing first.
LIMIT = 3500

# The id is the only argv value interpolated into the sentinel strings, so it is
# constrained to a shape that contains no path or regex metacharacters.
ID_RE = /\A[a-z][a-z0-9_-]*\z/

ENV_NAME      = "APP_REVIEW_NOTES"
BOOTSTRAP_ENV = ".bootstrap.env"

USAGE = <<~TXT
  usage: ruby tools/gen-review-notes.rb [--check] [--id <id>] [--dest <path>]
    --check        verify the destination matches the block instead of writing it
    --id <id>      block id inside #{SRC} (default: #{DEFAULT_ID})
    --dest <path>  destination under #{DEST_ROOT} (default: #{DEFAULT_DEST})
TXT

# Every failure path is explicit and loud. There is no broad rescue anywhere in
# this file: a silently tolerated error here means wrong text reaching Apple.
def die(message)
  warn "gen-review-notes: #{message}"
  exit 1
end

def parse_args(argv)
  check = false
  id    = DEFAULT_ID
  dest  = DEFAULT_DEST

  index = 0
  while index < argv.length
    case argv[index]
    when "--check"
      check = true
    when "--id"
      index += 1
      die "--id requires a value\n#{USAGE}" if argv[index].nil?
      id = argv[index]
    when "--dest"
      index += 1
      die "--dest requires a value\n#{USAGE}" if argv[index].nil?
      dest = argv[index]
    when "-h", "--help"
      puts USAGE
      exit 0
    else
      # Unknown argv is rejected, never ignored: a typo'd flag must not look
      # like a successful run.
      die "unknown argument #{argv[index].inspect}\n#{USAGE}"
    end
    index += 1
  end

  [check, id, dest]
end

def validate_id!(id)
  return if id.match?(ID_RE)

  die "invalid --id #{id.inspect}: must match #{ID_RE.inspect} — a lowercase " \
      "letter followed by lowercase letters, digits, '_' or '-'. The id is " \
      "interpolated into the BEGIN:REVIEW-NOTES sentinel, so path and regex " \
      "metacharacters are rejected."
end

def validate_dest!(dest)
  if dest.start_with?("/") || dest.match?(/\A[A-Za-z]:/)
    die "invalid --dest #{dest.inspect}: absolute paths are rejected; the " \
        "destination must be a repo-relative path under #{DEST_ROOT}."
  end

  if dest.split("/").include?("..")
    die "invalid --dest #{dest.inspect}: contains a '..' path segment; the " \
        "destination must stay inside #{DEST_ROOT}."
  end

  return if dest.start_with?(DEST_ROOT)

  die "invalid --dest #{dest.inspect}: must begin with #{DEST_ROOT} — only " \
      "fastlane's metadata tree is transmitted to App Review."
end

# Defeats the .editorconfig asymmetry (Markdown keeps trailing whitespace,
# everything else is trimmed) and matches the .strip that read_review_field
# applies, so the comparison is between the values fastlane would actually see.
def normalize(text)
  text.to_s.lines.map(&:rstrip).join("\n").strip + "\n"
end

# Line-oriented on purpose: two literal sentinel comparisons are the whole job,
# and a Markdown parser would be a dependency bought for nothing.
# Every read below pins UTF-8 explicitly rather than inheriting the locale.
# With LANG unset -- cron, launchd, a bare container, `env -i` -- Ruby defaults
# Encoding.default_external to US-ASCII, and any non-ASCII byte then raises
# ArgumentError out of a regex match instead of exiting 0 or 1. That is not
# exotic input: an App Review contact named Mueller or Jose, or a curly
# apostrophe anywhere in the notes prose, is enough. A drift gate that dies
# with a stack trace instead of a verdict is worse than no gate, because the
# caller cannot tell "in sync" from "crashed".
def read_utf8(path)
  File.read(path, encoding: "UTF-8")
end

def extract(path, id)
  die "#{path}: not found — run this from the repository root." unless File.file?(path)

  begin_marker = "<!-- BEGIN:REVIEW-NOTES id=#{id} -->"
  end_marker   = "<!-- END:REVIEW-NOTES id=#{id} -->"

  saw_begin = false
  keep      = false
  body      = []

  File.foreach(path, encoding: "UTF-8") do |line|
    if line.include?(begin_marker)
      saw_begin = true
      keep = true
      next
    end
    if line.include?(end_marker)
      keep = false
      next
    end
    body << line if keep
  end

  unless saw_begin
    die "#{path}: no '#{begin_marker}' sentinel found — cannot resolve block id=#{id}."
  end

  text = normalize(body.join)
  die "#{path}: block id=#{id} is empty after normalization." if text.strip.empty?

  text
end

def guard_text!(text)
  if text.start_with?("TODO")
    die "review notes begin with \"TODO\": read_review_field in " \
        "fastlane/Fastfile drops any TODO-prefixed value, so the notes field " \
        "would be omitted from the submission entirely."
  end

  return unless text.length > LIMIT

  die "review notes are #{text.length} characters, over the #{LIMIT}-character limit."
end

def first_diff_line(expected, actual)
  expected_lines = expected.lines
  actual_lines   = actual.lines
  [expected_lines.length, actual_lines.length].max.times do |i|
    return i + 1 if expected_lines[i] != actual_lines[i]
  end
  0
end

def run_check(text, dest, id)
  # 1. The file itself must match the block.
  current = File.exist?(dest) ? normalize(read_utf8(dest)) : ""
  if current != text
    warn "gen-review-notes: DRIFT: #{dest} does not match block id=#{id} in #{SRC}"
    warn "  first differing line: #{first_diff_line(text, current)}"
    warn "  regenerate with: ruby tools/gen-review-notes.rb"
    exit 1
  end

  # 2. The override path must be closed. This is what makes --check assert the
  #    property rather than merely diff two files.
  env_value = ENV[ENV_NAME].to_s.strip
  unless env_value.empty?
    die "#{ENV_NAME} is set in the environment. read_review_field in " \
        "fastlane/Fastfile prefers the env var over #{dest}, so a matching " \
        "file is not what Apple would receive. Unset #{ENV_NAME}."
  end

  if File.exist?(BOOTSTRAP_ENV) &&
     read_utf8(BOOTSTRAP_ENV).match?(/^[ \t]*#{ENV_NAME}[ \t]*=[ \t]*\S/)
    die "#{ENV_NAME} is assigned a non-empty value in #{BOOTSTRAP_ENV}. " \
        "read_review_field in fastlane/Fastfile prefers the env var over " \
        "#{dest}, so a matching file is not what Apple would receive. Leave " \
        "#{ENV_NAME} empty; these notes are generated."
  end

  puts "review notes in sync: id=#{id} -> #{dest}"
end

def run_write(text, dest, id)
  directory = File.dirname(dest)
  unless Dir.exist?(directory)
    die "#{directory}: directory does not exist — create it before generating #{dest}."
  end

  File.write(dest, text, encoding: "UTF-8")
  puts "wrote #{dest} (#{text.length} chars, id=#{id})"
end

check, id, dest = parse_args(ARGV)
validate_id!(id)
validate_dest!(dest)

text = extract(SRC, id)
guard_text!(text)

if check
  run_check(text, dest, id)
else
  run_write(text, dest, id)
end
