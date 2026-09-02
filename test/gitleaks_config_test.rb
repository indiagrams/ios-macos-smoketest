#!/usr/bin/env ruby
# frozen_string_literal: true

# Contract test for `.gitleaks.toml` — the allowlist that makes the secret scan
# (D-62, IDENT-12) able to pass on this repository's history — and for the two
# places the gitleaks version is pinned.
#
# Why a config file needs its own gate.
#
#   gitleaks with `[extend] useDefault = true` reports TEN findings on this
#   repository's history (04-RESEARCH §Q3, measured 2026-09-02): a documented
#   placeholder issuer id in the bootstrap docs, a `curl -u` example in
#   fastlane/Fastfile.local.example that reads ENV rather than a literal, and a
#   CHANGELOG line naming ASC metadata fields next to a URL. None is a secret.
#   Without a `.gitleaks.toml` the gate therefore cannot go green on HEAD, and a
#   gate that cannot pass is a gate somebody disables within a week.
#
#   But an allowlist is where the hole gets drilled. Driven red in this plan's
#   evidence and in the research before it: a single `[[allowlists]]` entry with
#   `regexTarget = "line"` and a match-everything regex turns an injected
#   high-entropy token from exit 42 into exit 0. The scan still runs, still
#   prints "no leaks found", still reports green — and sees nothing. The config
#   is a gate, so the config gets a gate.
#
# The failure modes this file rejects, each driven red against a fixture below
# and again on a real file in
# .planning/…/evidence/04-09-T2-gitleaks-controls.txt:
#
#   1. a catch-all regex (the frozen CATCH_ALL set) or any regex under six
#      characters — the "swallow everything" edit;
#   2. a `paths` regex that matches no tracked file — a rule that has rotted
#      into a permanent exemption for a file that no longer exists;
#   3. `regexTarget = "line"` without `paths` — a line-target rule is
#      repo-wide unless it is path-scoped, which is the catch-all shape wearing
#      a longer regex;
#   4. a `description` that does not begin with an ISO date — the measurement
#      triple of docs/APPLE-ACCOUNT-STATE.md:41-46 ("a value, its measurement
#      date, and the thing it was measured against are one unit"); an undated
#      suppression cannot be re-checked;
#   5. a key outside the gitleaks allowlist vocabulary — a typo'd key is
#      silently ignored by the scanner, so `regextarget = "line"` would produce
#      a rule that does not do what its author read.
#
# It also asserts the PIN, which is deliberately written in two places:
# `VERSION` in tools/gitleaks.rb is what executes, and the version in the
# workflow step's `name:` is what a reader sees in the Actions log. Two places
# that can disagree is a defect unless something compares them. This does.
#
# Failure-line contract — do not change the shape (test/identity_test.rb:36-44,
# test/contamination_test.rb:29-35):
#
#     FAIL <group> <path>: <message>
#
# one line, no leading whitespace. This file's group token is `GL`.
#
# Modes:
#   ruby test/gitleaks_config_test.rb                 # the full suite
#   ruby test/gitleaks_config_test.rb --config PATH   # validate one config only
#
# The second mode exists so a config OUTSIDE this repository — the scratch
# clone in which the catch-all hole is demonstrated — can be run through the
# same reader that guards the real one, rather than through a description of it.
#
# Runnable from the repository root or from test/, under BOTH pinned
# interpreters:
#   /opt/homebrew/opt/ruby@3.3/bin/ruby test/gitleaks_config_test.rb
#   /opt/homebrew/opt/ruby@4.0/bin/ruby test/gitleaks_config_test.rb
#
# Ruby stdlib only (open3) — no gems, which is what keeps the `review notes`
# job's `bundler-cache: false` honest. Every shell-out is an argv array.

require "open3"

ROOT         = File.expand_path("..", __dir__)
CONFIG_REL   = ".gitleaks.toml"
WRAPPER_REL  = "tools/gitleaks.rb"
WORKFLOW_REL = ".github/workflows/review-notes.yml"

# ─── frozen vocabulary: never derived from the file under test ───────────────
# gitleaks' own allowlist keys (README, 8.30.1). `condition`, `targetRules` and
# the singular legacy `[allowlist]` table are deliberately absent: this fork's
# config uses the array form and none of those keys, and a key appearing here
# should be a decision, not a discovery.
ALLOWED_KEYS = %w[description paths regexTarget regexes stopwords commits].freeze
# Every regex that matches everything, spelled out rather than detected. A
# predicate that tried to decide "does this regex match everything" in general
# is undecidable in the useful direction; a frozen list of the shapes somebody
# actually types is honest about what it covers, and MIN_REGEX_LEN catches the
# short novel ones.
CATCH_ALL = [
  ".+", ".*", "^.*$", "^.+$", "\\A.*\\z", "\\A.+\\z",
  "[\\s\\S]+", "[\\s\\S]*", "(?s).+", "(?s).*", "."
].freeze
MIN_REGEX_LEN = 6
ISO_DATE      = /\A\d{4}-\d{2}-\d{2}\b/
VERSION_PIN   = /VERSION\s*=\s*"(\d+\.\d+\.\d+)"/
STEP_PIN      = /^\s*-?\s*name:.*gitleaks\s+(\d+\.\d+\.\d+)/
# stdlib the wrapper may require. A gem require outside this list would make
# `bundler-cache: false` in review-notes.yml a lie on the next run.
WRAPPER_STDLIB = %w[digest open3 tmpdir fileutils rbconfig].freeze

GIT_ENV = { "GIT_CONFIG_GLOBAL" => "/dev/null", "GIT_CONFIG_SYSTEM" => "/dev/null" }.freeze

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

def fail_line(path, message)
  @checks += 1
  puts "FAIL GL #{path}: #{message.to_s.gsub(/\s*\n\s*/, ' ')}"
  @failures += 1
end

def verdict!(noun = "gitleaks-config")
  puts
  if @failures.zero?
    puts "All #{@checks} #{noun} assertions passed."
    exit 0
  else
    puts "#{@failures} of #{@checks} #{noun} assertion(s) failed."
    exit 1
  end
end

# Pin UTF-8 explicitly rather than inheriting the locale (the fork's idiom since
# commit 3b1efb9): with LANG unset Ruby's default external encoding is US-ASCII
# and a regex over text containing a non-ASCII byte raises instead of matching.
def utf8(text)
  text = text.dup.force_encoding(Encoding::UTF_8)
  text.valid_encoding? ? text : text.scrub("?")
end

def read_utf8(path)
  utf8(File.binread(path))
end

def tracked_files(dir)
  out, _err, status = Open3.capture3(GIT_ENV, "git", "ls-files", "-z", chdir: dir)
  return nil unless status.success?

  utf8(out).split("\u0000").reject(&:empty?)
rescue StandardError
  nil
end

# ─── the reader ──────────────────────────────────────────────────────────────
# A line-based reader for THIS file's shape, not a TOML implementation: an
# `[extend]` table, `[[allowlists]]` array-of-tables, `key = value` where value
# is a boolean, a "quoted" string, or an array of literal strings that may span
# lines. Anything it cannot read is reported as a failure rather than skipped —
# a config with a line this reader ignores is a config whose contents this test
# has not actually checked.
#
# Bracket counting is done on a MASKED copy in which every string literal is
# blanked, so a regex containing a character class cannot close an array early
# or hold one open forever.
def mask_literals(str)
  str.gsub(/'''.*?'''/m) { |m| " " * m.length }
     .gsub(/"(?:[^"\\]|\\.)*"/) { |m| " " * m.length }
end

def literal_items(str)
  items = []
  str.scan(/'''(.*?)'''|"((?:[^"\\]|\\.)*)"/m) do |triple, dq|
    items << (triple || dq.to_s.gsub(/\\(.)/) { Regexp.last_match(1) })
  end
  items
end

def parse_config(text)
  entries = []
  extend_table = nil
  current = nil
  errors = []
  lines = text.split("\n")
  i = 0
  while i < lines.length
    line = lines[i].strip
    i += 1
    next if line.empty? || line.start_with?("#")

    if line == "[[allowlists]]"
      current = { "__index" => entries.length + 1, "__keys" => [] }
      entries << current
      next
    end
    if (m = line.match(/\A\[([A-Za-z0-9_.-]+)\]\z/))
      if m[1] == "extend"
        current = { "__index" => 0, "__keys" => [] }
        extend_table = current
      else
        current = nil
      end
      next
    end
    unless (m = line.match(/\A([A-Za-z0-9_]+)\s*=\s*(.*)\z/))
      errors << "unparseable line #{i}: #{line[0, 60]}"
      next
    end
    key = m[1]
    rest = m[2]
    # Multi-line array: keep consuming until the brackets balance in the masked copy.
    if rest.lstrip.start_with?("[")
      buffer = rest
      while mask_literals(buffer).count("[") > mask_literals(buffer).count("]")
        if i >= lines.length
          errors << "unterminated array for key #{key.inspect}"
          break
        end
        buffer = "#{buffer}\n#{lines[i]}"
        i += 1
      end
      value = literal_items(buffer)
    elsif rest.start_with?("'''") || rest.start_with?('"')
      value = literal_items(rest).first
      errors << "unreadable string value for key #{key.inspect} on line #{i}" if value.nil?
    elsif %w[true false].include?(rest)
      value = (rest == "true")
    else
      errors << "unreadable value for key #{key.inspect} on line #{i}: #{rest[0, 40]}"
      next
    end
    if current.nil?
      errors << "key #{key.inspect} on line #{i} belongs to no [extend] or [[allowlists]] table"
      next
    end
    current["__keys"] << key
    current[key] = value
  end
  { "extend" => extend_table, "allowlists" => entries, "errors" => errors }
end

# ─── the validator ───────────────────────────────────────────────────────────
# Returns an array of messages. Empty means the config is acceptable. It never
# prints: the caller decides whether a message is a failure (the real config) or
# the expected outcome (a fixture).
def validate_config(text, tracked)
  parsed = parse_config(text)
  problems = parsed["errors"].dup

  ext = parsed["extend"]
  if ext.nil?
    problems << "[extend] table missing — the built-in rule set must be inherited, " \
                "not replaced (a config without it scans for nothing but its own rules)"
  elsif ext["useDefault"] != true
    problems << "[extend] useDefault is not true"
  end

  entries = parsed["allowlists"]
  problems << "no [[allowlists]] entries" if entries.empty?

  entries.each do |entry|
    n = entry["__index"]
    unknown = entry["__keys"] - ALLOWED_KEYS
    unknown.each { |k| problems << "entry #{n}: unknown key #{k.inspect} (a key gitleaks ignores silently)" }

    desc = entry["description"]
    if desc.nil?
      problems << "entry #{n}: description missing"
    elsif !desc.match?(ISO_DATE)
      problems << "entry #{n}: description does not begin with an ISO date: #{desc[0, 50].inspect}"
    end

    regexes = Array(entry["regexes"])
    paths   = Array(entry["paths"])
    (regexes + paths).each do |rx|
      if CATCH_ALL.include?(rx)
        problems << "entry #{n}: catch-all regex #{rx.inspect} — this entry would swallow every finding"
      elsif rx.length < MIN_REGEX_LEN
        problems << "entry #{n}: catch-all risk, regex #{rx.inspect} is shorter than #{MIN_REGEX_LEN} characters"
      end
    end

    if entry["regexTarget"] == "line" && paths.empty?
      problems << "entry #{n}: regexTarget = \"line\" without paths — a line-target rule is repo-wide"
    end

    if regexes.empty? && paths.empty? && Array(entry["stopwords"]).empty? && Array(entry["commits"]).empty?
      problems << "entry #{n}: matches nothing"
    end

    next if tracked.nil?

    paths.each do |p|
      begin
        rx = Regexp.new(p)
      rescue RegexpError => e
        problems << "entry #{n}: paths entry #{p.inspect} is not a valid regex (#{e.message})"
        next
      end
      next if tracked.any? { |f| rx.match?(f) }

      problems << "entry #{n}: stale paths entry #{p.inspect} matches no tracked file"
    end
  end

  problems
end

# ─── mode: --config PATH ─────────────────────────────────────────────────────
argv = ARGV.dup
config_arg = nil
until argv.empty?
  arg = argv.shift
  case arg
  when "--config" then config_arg = argv.shift or abort("--config needs a path")
  when "-h", "--help"
    puts "Usage: ruby test/gitleaks_config_test.rb [--config PATH]"
    exit 0
  else abort("unknown argument #{arg.inspect}. Usage: ruby test/gitleaks_config_test.rb [--config PATH]")
  end
end

if config_arg
  path = File.expand_path(config_arg)
  unless File.file?(path)
    fail_line(config_arg, "missing")
    verdict!
  end
  problems = validate_config(read_utf8(path), tracked_files(File.dirname(path)))
  if problems.empty?
    assert true, "GL", config_arg, "structurally acceptable"
  else
    problems.each { |p| fail_line(config_arg, p) }
  end
  verdict!
end

# ─── the real config ─────────────────────────────────────────────────────────
# File.file? first, and a clean exit rather than a crash: "the file was never
# there" is a distinct outcome from "the check ran and failed", and this file
# must say which.
config_path = File.join(ROOT, CONFIG_REL)
unless File.file?(config_path)
  fail_line(CONFIG_REL, "missing")
  verdict!
end

tracked = tracked_files(ROOT)
assert !tracked.nil? && !tracked.empty?, "GL", CONFIG_REL,
       "git ls-files returned tracked paths (the stale-entry rule needs them)"

config_text = read_utf8(config_path)
problems = validate_config(config_text, tracked)
if problems.empty?
  assert true, "GL", CONFIG_REL,
         "every entry dated, path- or match-scoped, no catch-all, no stale path"
else
  problems.each { |p| fail_line(CONFIG_REL, p) }
end

parsed_real = parse_config(config_text)
assert parsed_real["allowlists"].length >= 1, "GL", CONFIG_REL,
       "at least one [[allowlists]] entry (#{parsed_real['allowlists'].length} present)"

# ─── the fixtures: each failure mode, driven red against a string ────────────
# The fixtures are strings rather than files so this test needs no scratch
# directory and no cleanup; the same reader and the same validator run over
# them. Each case asserts that the rejection MENTIONS its reason, so a fixture
# that started failing for an unrelated reason cannot masquerade as coverage.
BASE = <<~TOML
  [extend]
  useDefault = true
TOML

FIXTURES = [
  ["catch-all", BASE + <<~TOML, /catch-all regex/],
    [[allowlists]]
    description = "2026-09-02 control"
    paths = ['''CHANGELOG\\.md''']
    regexTarget = "line"
    regexes = ['''.+''']
  TOML
  ["short-regex", BASE + <<~TOML, /shorter than 6 characters/],
    [[allowlists]]
    description = "2026-09-02 control"
    paths = ['''CHANGELOG\\.md''']
    regexTarget = "match"
    regexes = ['''key''']
  TOML
  ["stale-path", BASE + <<~TOML, /stale paths entry/],
    [[allowlists]]
    description = "2026-09-02 control"
    paths = ['''docs/THIS-FILE-DOES-NOT-EXIST\\.md''']
    regexTarget = "match"
    regexes = ['''ASC_API_KEY_ISSUER_ID=''']
  TOML
  ["line-target-without-paths", BASE + <<~TOML, /regexTarget = "line" without paths/],
    [[allowlists]]
    description = "2026-09-02 control"
    regexTarget = "line"
    regexes = ['''marketing_url=''']
  TOML
  ["undated-description", BASE + <<~TOML, /does not begin with an ISO date/],
    [[allowlists]]
    description = "documented placeholder issuer id"
    regexTarget = "match"
    regexes = ['''ASC_API_KEY_ISSUER_ID=12345678-abcd-''']
  TOML
  ["unknown-key", BASE + <<~TOML, /unknown key/],
    [[allowlists]]
    description = "2026-09-02 control"
    regextarget = "match"
    regexes = ['''ASC_API_KEY_ISSUER_ID=12345678-abcd-''']
  TOML
  ["no-extend", <<~TOML, /\[extend\] table missing/],
    [[allowlists]]
    description = "2026-09-02 control"
    regexTarget = "match"
    regexes = ['''ASC_API_KEY_ISSUER_ID=12345678-abcd-''']
  TOML
  ["extend-false", <<~TOML, /useDefault is not true/]
    [extend]
    useDefault = false

    [[allowlists]]
    description = "2026-09-02 control"
    regexTarget = "match"
    regexes = ['''ASC_API_KEY_ISSUER_ID=12345678-abcd-''']
  TOML
].freeze

FIXTURES.each do |name, text, expected|
  found = validate_config(text, tracked)
  assert found.any? { |p| p.match?(expected) }, "GL", "fixture[#{name}]",
         "rejected for #{expected.source} (got: #{found.empty? ? 'nothing' : found.join(' | ')[0, 120]})"
end

# The positive fixture: the same shape WITHOUT the defect passes, so the
# rejections above are not a validator that rejects everything.
CLEAN_FIXTURE = <<~TOML
  [extend]
  useDefault = true

  [[allowlists]]
  description = "2026-09-02 control"
  paths = ['''CHANGELOG\\.md''']
  regexTarget = "line"
  regexes = ['''marketing_url=|privacy_policy_url=''']
TOML
clean_problems = validate_config(CLEAN_FIXTURE, tracked)
assert clean_problems.empty?, "GL", "fixture[clean]",
       "accepted (#{clean_problems.join(' | ')})"

# ─── the pin, in the two places it is written ────────────────────────────────
wrapper_path  = File.join(ROOT, WRAPPER_REL)
workflow_path = File.join(ROOT, WORKFLOW_REL)

wrapper_version = nil
if File.file?(wrapper_path)
  wrapper_text = read_utf8(wrapper_path)
  wrapper_version = wrapper_text[VERSION_PIN, 1]
  assert !wrapper_version.nil?, "GL", WRAPPER_REL, "declares VERSION = \"x.y.z\""

  requires = wrapper_text.scan(%r{^\s*require\s+["']([a-z0-9_/]+)["']}).flatten
  assert (requires - WRAPPER_STDLIB).empty?, "GL", WRAPPER_REL,
         "requires stdlib only (#{requires.join(', ')}) — bundler-cache: false depends on it"

  assert wrapper_text.include?("is-shallow-repository"), "GL", WRAPPER_REL,
         "asserts the checkout is not shallow in code, not only via fetch-depth: 0"
  assert wrapper_text.include?("--exit-code"), "GL", WRAPPER_REL,
         "separates findings from tool errors with --exit-code"
  assert wrapper_text.include?(CONFIG_REL), "GL", WRAPPER_REL,
         "passes #{CONFIG_REL} with --config"
else
  fail_line(WRAPPER_REL, "missing")
end

if File.file?(workflow_path)
  workflow_text = read_utf8(workflow_path)
  step_version = workflow_text[STEP_PIN, 1]
  assert !step_version.nil?, "GL", WORKFLOW_REL,
         "a step name states the pinned gitleaks version (what a reader sees in the Actions log)"
  if step_version && wrapper_version
    assert step_version == wrapper_version, "GL", WORKFLOW_REL,
           "step name pins #{step_version.inspect}, #{WRAPPER_REL} executes " \
           "#{wrapper_version.inspect} — the two statements of the pin disagree"
  end
  assert workflow_text.include?("ruby tools/gitleaks.rb"), "GL", WORKFLOW_REL,
         "runs the wrapper"
  assert workflow_text.include?("fetch-depth: 0"), "GL", WORKFLOW_REL,
         "checks out full history (the wrapper refuses a shallow checkout)"
  assert !workflow_text.include?("gitleaks-action"), "GL", WORKFLOW_REL,
         "does not use gitleaks-action (org-owned repos need a commercial licence; the binary is MIT)"
else
  fail_line(WORKFLOW_REL, "missing")
end

verdict!
