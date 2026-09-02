#!/usr/bin/env ruby
# frozen_string_literal: true

# Criterion 3's instrument: prove that XcodeGen (app/project.yml) and Tuist
# (app/Project.swift) resolve the SAME identity, by diffing the output of
# `xcodebuild -showBuildSettings` across both generated projects.
#
# Criterion 3 is a -showBuildSettings diff or it is nothing. Reading the two
# manifests and judging them "equivalent" is forbidden (03-CONTEXT blocking
# constraint 3), and for a concrete reason: Xcode's layering rules are
# counter-intuitive here. A value in an xcconfig is OVERRIDDEN by anything a
# manifest writes into the .pbxproj's build-settings dictionary, so two
# manifests that both "point at Identity.xcconfig" can still resolve different
# identities if either one also writes a literal into the project. Only the
# resolved settings — what xcodebuild reports after every layer has been
# applied — can be compared factually. That is what this tool compares.
#
# What this tool CANNOT see, stated so nobody reads more into a green run:
# `xcodebuild -showBuildSettings` exits 0 and emits the full settings dump on
# a broken hard `#include "Missing.xcconfig"` (03-RESEARCH Pitfall 4, observed
# on Xcode 26.1.1); only a real `xcodebuild build` reports
# `could not find included file`. So this tool is NECESSARY for criterion 3
# but not SUFFICIENT: pair it with at least one real build per platform
# (03-09 locally; the template-owned pr.yml matrix on four cells).
#
# Where this runs: locally, by hand, and its output is recorded as dated
# evidence under .planning/. There is no fork-owned macOS CI surface in this
# repository — the fork's only workflow (`review notes`) runs ubuntu-latest,
# and all three macos-15 jobs live in template-owned .github/workflows/pr.yml
# (03-PATTERNS correction 5). A gate that needs xcodebuild therefore either
# runs here and is transcribed, or goes upstream. There is no third option.
#
# How the comparison is made. Both generators write to the SAME path —
# XcodeGen produces app/<NAME>.xcodeproj; Tuist produces app/<NAME>.xcodeproj
# AND app/<NAME>.xcworkspace — so they overwrite each other. The tool
# therefore generates with XcodeGen, extracts, generates with Tuist, extracts,
# and compares the two extractions. Whatever the verdict, it regenerates with
# XcodeGen as its final step, because ci/local-check.sh and the lefthook
# pre-push hook both expect XcodeGen's output on disk. Everything it writes is
# already gitignored (app/<NAME>.xcodeproj, app/<NAME>.xcworkspace,
# app/Derived/, .tuist/); it writes nowhere else.
#
# Extraction: for each scheme × configuration, run
#   xcodebuild -project app/<NAME>.xcodeproj -scheme <S> -configuration <C> -showBuildSettings
# strip leading whitespace, keep only the lines whose key is in IDENTITY_KEYS,
# sort. Both manifests' build actions contain only the app target, so the dump
# holds exactly one target block (03-RESEARCH §Q8, observed); the tool asserts
# that count and refuses to compare an ambiguous dump.
#
# On generator stderr: `tuist generate` prints a cosmetic
# "Invalid product name" warning whenever productName: is a build-setting
# reference such as $(APP_PRODUCT_NAME). It still generates and the value still
# resolves (03-RESEARCH Pitfall 5, observed). This tool keys off the generator's
# exit code and the project it produced, never off stderr text, and MUST NOT
# grow an assertion that generation emits no warnings — that assertion would go
# red permanently (T-03-17).
#
# Exit-code contract:
#
#   Exit | Meaning
#   -----+-------------------------------------------------------------------
#   0    | every scheme × configuration pair produced byte-identical filtered
#        | output from both generators
#   1    | at least one pair differed (the unified diff is printed), or the
#        | argv was rejected (usage printed)
#   2    | no parity verdict was reached: a generator binary, the project, a
#        | scheme, or a configuration was absent; a generator exited non-zero
#        | (a signal-killed one reports 128+N); Tuist exited 0 but left
#        | XcodeGen's project.pbxproj byte-identical, so there was nothing
#        | to compare; the settings dump was ambiguous; --skip-generate was
#        | given; OR the final `xcodegen generate` that restores the tree
#        | failed — a parity verdict may have been printed above, but exit 0
#        | also vouches for the on-disk project being XcodeGen's, and after
#        | a failed restore it is Tuist's
#
# Exit 2 is the tools/asc-probe.rb:159-171 idiom. A query that matches nothing
# and an assertion that therefore never executes is the classic vacuous-truth
# gate; a distinct "I don't know" code makes "nothing was there" impossible to
# read as "everything checked out".
#
# Why --skip-generate can never exit 0: there is exactly one project path on
# disk, and both generators write to it. "Compare whatever is already there"
# means extracting the same project twice, which is a comparison that can only
# be green — the self-invalidating shape this phase exists to eliminate
# (T-03-12, 03-RESEARCH Pitfall 2's stale-project false green). So the flag is
# inspect-only: it prints the resolved identity block of the project on disk
# and exits 2, stating that no cross-generator comparison was made. Use it to
# read resolved settings, or to observe the absent-project path without
# generating; never as a gate. The main path guards the same shape from the
# other side: it fingerprints project.pbxproj after XcodeGen and refuses, exit
# 2, if Tuist exited 0 without changing a byte of it.
#
# Every run prints the installed xcodegen / tuist / xcodebuild versions beside
# the pins read from .tool-versions. A recorded fact without the tool version
# it was measured against is the "copying a measurement forward" anti-pattern.
# (.tool-versions pins xcodegen 2.45.4 while 2.46.0 is installed; that drift
# is a finding this phase records, not one this tool silences.)
#
# Usage (run from anywhere; paths resolve from this file's location):
#   ruby tools/identity-parity.rb
#   ruby tools/identity-parity.rb --project-name Legacy --schemes Legacy-iOS,Legacy-macOS
#   ruby tools/identity-parity.rb --configurations Release,Debug
#   ruby tools/identity-parity.rb --skip-generate        # inspect-only, exits 2
#
# Ruby core only: no require, no gem, no Gemfile entry, no test framework.
# Every subprocess is an explicit argv array; there is no shell string and no
# broad rescue anywhere in this file.

# The identity key set, duplicated deliberately and never derived from the
# settings dump: a filter computed from the thing it filters cannot fail.
# DEVELOPMENT_TEAM is listed precisely so that it is ABSENT from both sides
# after this phase's changes — a symmetric absence is criterion 4's evidence
# that no team is in tracked build config. With no team set, xcodebuild emits
# no DEVELOPMENT_TEAM line at all and instead emits the undocumented internal
# `_DEVELOPMENT_TEAM_IS_EMPTY = YES`; that line is reported as corroboration
# only and is never gated on.
IDENTITY_KEYS = %w[
  PRODUCT_BUNDLE_IDENTIFIER
  PRODUCT_NAME
  FULL_PRODUCT_NAME
  INFOPLIST_KEY_NSHumanReadableCopyright
  DEVELOPMENT_TEAM
  MARKETING_VERSION
  CURRENT_PROJECT_VERSION
  SWIFT_VERSION
].freeze

# Unbuffered stdout, so a captured transcript reads in the order events
# happened rather than with every stderr line hoisted above the stdout block.
$stdout.sync = true

ROOT          = File.expand_path("..", __dir__)
APP_DIR       = File.join(ROOT, "app")
TOOL_VERSIONS = File.join(ROOT, ".tool-versions")

DEFAULT_PROJECT_NAME   = "App"
DEFAULT_SCHEMES        = %w[App-iOS App-macOS].freeze
DEFAULT_CONFIGURATIONS = %w[Release Debug].freeze

REQUIRED_TOOLS = %w[xcodegen tuist xcodebuild].freeze

USAGE = <<~TXT
  usage: ruby tools/identity-parity.rb [--project-name NAME] [--schemes A,B]
                                       [--configurations A,B] [--skip-generate]
    --project-name NAME    project name both manifests declare (default: #{DEFAULT_PROJECT_NAME})
    --schemes A,B          schemes to compare (default: #{DEFAULT_SCHEMES.join(',')})
    --configurations A,B   configurations to compare (default: #{DEFAULT_CONFIGURATIONS.join(',')})
    --skip-generate        inspect the project already on disk; no comparison, exits 2
    -h, --help             print this and exit 0
  exit 0 = every scheme x configuration pair identical across XcodeGen and Tuist
  exit 1 = at least one pair differed (diff printed), or bad argv
  exit 2 = no verdict: absent tool/project/scheme/configuration, generator failure, a failed final
           xcodegen restore (the tree is Tuist's), or --skip-generate
TXT

# Every failure path is explicit and loud, on stderr, prefixed.
def die(message)
  warn "identity-parity: #{message}"
  exit 1
end

# The distinct "I don't know" outcome.
def no_verdict(message)
  warn "identity-parity: no verdict: #{message}"
  exit 2
end

def parse_args(argv)
  opts = {
    project_name: DEFAULT_PROJECT_NAME,
    schemes: DEFAULT_SCHEMES,
    configurations: DEFAULT_CONFIGURATIONS,
    skip_generate: false,
  }
  index = 0
  while index < argv.length
    case argv[index]
    when "--project-name"
      index += 1
      die "--project-name requires a value\n#{USAGE}" if argv[index].nil? || argv[index].empty?
      opts[:project_name] = argv[index]
    when "--schemes"
      index += 1
      die "--schemes requires a value\n#{USAGE}" if argv[index].nil?
      opts[:schemes] = argv[index].split(",").map(&:strip).reject(&:empty?)
      die "--schemes needs at least one scheme\n#{USAGE}" if opts[:schemes].empty?
    when "--configurations"
      index += 1
      die "--configurations requires a value\n#{USAGE}" if argv[index].nil?
      opts[:configurations] = argv[index].split(",").map(&:strip).reject(&:empty?)
      die "--configurations needs at least one configuration\n#{USAGE}" if opts[:configurations].empty?
    when "--skip-generate"
      opts[:skip_generate] = true
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
  opts
end

# Run an argv array, capturing stdout and stderr separately. No shell.
# stderr is drained on its own thread so a chatty generator cannot deadlock
# the pipe while stdout is being read.
#
# The command is passed as [cmd, argv0] rather than splatted: Process.spawn
# with a single string argument is the STRING form, which Ruby hands to
# /bin/sh whenever the string carries a metacharacter, so `Process.spawn(*argv)`
# on a one-element argv would have been a shell string after all — latent, as
# every caller here passes two or more elements, but contradicting the header's
# unconditional promise (03-REVIEW IN-04, demonstrated: the splat ran
# `true; echo INJECTED` through the shell, this form raises ENOENT on it). The
# two-element array form is never shell-interpreted, whatever argv holds.
def capture(argv, chdir: ROOT)
  out_r, out_w = IO.pipe
  err_r, err_w = IO.pipe
  pid = Process.spawn([argv[0], argv[0]], *argv[1..], chdir: chdir, in: File::NULL, out: out_w, err: err_w)
  out_w.close
  err_w.close
  err_thread = Thread.new { err_r.read }
  out = out_r.read
  err = err_thread.value
  out_r.close
  err_r.close
  Process.wait(pid)
  # A child killed by a signal (a timeout, an OOM kill, an operator's `kill`)
  # has exitstatus nil, and every caller's `status.zero?` would then raise
  # NoMethodError — Ruby's exit 1, which the contract reserves for "a pair
  # differed" (03-REVIEW WR-05, observed with SIGTERM). Report it as the
  # shell's conventional 128+N instead, so the caller's non-zero branch fires
  # and the run ends in the documented exit 2 naming the generator.
  status = $?.exitstatus || (128 + $?.termsig.to_i)
  [utf8(out), utf8(err), status]
end

# Pin UTF-8 explicitly rather than inheriting the locale (the fork's idiom
# since commit 3b1efb9): with LANG unset, Ruby's default external encoding is
# US-ASCII and a regex over a dump containing © raises instead of matching.
def utf8(text)
  text = text.dup.force_encoding(Encoding::UTF_8)
  text.valid_encoding? ? text : text.scrub("?")
end

# PATH lookup in Ruby, so a missing binary is reported by name before any
# subprocess is attempted.
def on_path?(name)
  ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
    next false if dir.empty?

    candidate = File.join(dir, name)
    File.file?(candidate) && File.executable?(candidate)
  end
end

def tool_versions_pins
  pins = {}
  return pins unless File.file?(TOOL_VERSIONS)

  File.read(TOOL_VERSIONS, encoding: "UTF-8").each_line do |line|
    next if line.start_with?("#") || line.strip.empty?

    name, version = line.split(/\s+/, 3)
    pins[name] = version if name && version
  end
  pins
end

def print_versions
  pins = tool_versions_pins
  puts "identity-parity: tool versions (installed vs .tool-versions pin)"
  {
    "xcodegen"   => %w[xcodegen --version],
    "tuist"      => %w[tuist version],
    "xcodebuild" => %w[xcodebuild -version],
  }.each do |name, argv|
    out, err, status = capture(argv)
    text = (out + err).lines.map(&:strip).reject(&:empty?).join(" | ")
    text = "(exit #{status}, no output)" if text.empty?
    pin  = pins.fetch(name, "(not pinned in .tool-versions)")
    puts "  #{name}: installed #{text} ; pinned #{pin}"
  end
end

def run_generator(label, argv)
  puts "identity-parity: #{label}: #{argv.join(' ')}  (cwd: app/)"
  out, err, status = capture(argv, chdir: APP_DIR)
  # Print what the generator said, verbatim, but do not judge it: stderr text
  # is not evidence of failure (Pitfall 5). Only the exit code is.
  out.each_line { |l| puts "  [#{label} stdout] #{l.chomp}" }
  err.each_line { |l| puts "  [#{label} stderr] #{l.chomp}" }
  no_verdict "#{argv.join(' ')} exited #{status}; no project to compare" unless status.zero?
end

def project_path(project_name)
  File.join(APP_DIR, "#{project_name}.xcodeproj")
end

def assert_project_present(project_name)
  path = project_path(project_name)
  return path if File.directory?(path) && File.file?(File.join(path, "project.pbxproj"))

  no_verdict "project #{project_name} is absent: #{path} does not exist (or has no project.pbxproj). " \
             "Nothing was compared, because there was nothing to compare against."
end

def assert_scheme_present(project, scheme)
  shared = File.join(project, "xcshareddata", "xcschemes", "#{scheme}.xcscheme")
  return if File.file?(shared)

  no_verdict "scheme #{scheme} is absent from #{project}: #{shared} does not exist. " \
             "Nothing was compared for that scheme."
end

# Extract the sorted identity block for one scheme × configuration.
def extract(project, scheme, configuration)
  argv = [
    "xcodebuild", "-project", project, "-scheme", scheme,
    "-configuration", configuration, "-showBuildSettings",
  ]
  out, err, status = capture(argv)
  unless status.zero?
    no_verdict "xcodebuild -showBuildSettings exited #{status} for scheme #{scheme} " \
               "configuration #{configuration} in #{project}:\n#{err.strip}"
  end

  blocks = out.lines.count { |l| l.include?("Build settings for action") }
  unless blocks == 1
    no_verdict "expected exactly one target block for scheme #{scheme} configuration " \
               "#{configuration}, found #{blocks}; the filter would be ambiguous. " \
               "If a scheme's build action grew a second target, switch to -target."
  end

  # The dump must be for the configuration that was asked for. A build tool
  # that silently substituted a default configuration would otherwise be
  # compared as if it were the requested one.
  stripped = out.lines.map { |l| l.sub(/\A\s+/, "").chomp }
  reported = stripped.find { |l| l.start_with?("CONFIGURATION = ") }&.delete_prefix("CONFIGURATION = ")
  unless reported == configuration
    no_verdict "configuration #{configuration} was requested for scheme #{scheme} but the settings " \
               "dump reports CONFIGURATION = #{reported.inspect}; refusing to compare a substituted configuration"
  end

  keys = Regexp.union(IDENTITY_KEYS.map { |k| Regexp.new("\\A#{Regexp.escape(k)} = ") })
  lines = stripped.select { |l| l.match?(keys) }.sort
  team_empty = out.lines.any? { |l| l.strip == "_DEVELOPMENT_TEAM_IS_EMPTY = YES" }
  [lines, team_empty]
end

def extract_all(project, schemes, configurations)
  store = {}
  schemes.each do |scheme|
    assert_scheme_present(project, scheme)
    configurations.each do |configuration|
      store[[scheme, configuration]] = extract(project, scheme, configuration)
    end
  end
  store
end

# Minimal LCS line diff, rendered in unified format. Inputs are short sorted
# key lists, so a quadratic table is fine and avoids any require.
def unified_diff(a, b, from_label, to_label)
  n = a.length
  m = b.length
  table = Array.new(n + 1) { Array.new(m + 1, 0) }
  (n - 1).downto(0) do |i|
    (m - 1).downto(0) do |j|
      table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : [table[i + 1][j], table[i][j + 1]].max
    end
  end
  hunk = []
  i = 0
  j = 0
  while i < n || j < m
    if i < n && j < m && a[i] == b[j]
      hunk << " #{a[i]}"
      i += 1
      j += 1
    elsif i < n && (j >= m || table[i + 1][j] >= table[i][j + 1])
      # Removal before insertion, as diff -u prints it.
      hunk << "-#{a[i]}"
      i += 1
    else
      hunk << "+#{b[j]}"
      j += 1
    end
  end
  ["--- #{from_label}", "+++ #{to_label}", "@@ -1,#{n} +1,#{m} @@", *hunk].join("\n")
end

def print_block(title, lines, team_empty)
  puts "--- #{title} ---"
  lines.each { |l| puts l }
  puts "(no DEVELOPMENT_TEAM line; _DEVELOPMENT_TEAM_IS_EMPTY = YES observed — corroboration only, not gated)" if team_empty
end

def main(argv)
  opts = parse_args(argv)

  missing = REQUIRED_TOOLS.reject { |t| on_path?(t) }
  no_verdict "required tool(s) not on PATH: #{missing.join(', ')}" unless missing.empty?

  print_versions
  puts "identity-parity: project=#{opts[:project_name]} schemes=#{opts[:schemes].join(',')} " \
       "configurations=#{opts[:configurations].join(',')} skip_generate=#{opts[:skip_generate]}"

  if opts[:skip_generate]
    warn "identity-parity: --skip-generate is inspect-only: the project on disk was written by ONE " \
         "generator, so there is nothing to compare it against; no parity verdict will be produced"
    project = assert_project_present(opts[:project_name])
    store = extract_all(project, opts[:schemes], opts[:configurations])
    store.each { |(scheme, cfg), (lines, team_empty)| print_block("on-disk #{scheme} #{cfg}", lines, team_empty) }
    no_verdict "--skip-generate compared nothing across generators (inspect-only run of #{project})"
  end

  tuist_ran = false
  restore_status = nil
  xcodegen_argv = %w[xcodegen generate]
  # The parity verdict (0 or 1) is the value of this begin block; a no_verdict
  # inside it exits 2 through the ensure. The restore's own status is kept
  # separately and judged after the block, because exit 0 must vouch for the
  # tree as well as for parity — see the check below the ensure.
  verdict = begin
    run_generator("xcodegen", xcodegen_argv)
    project = assert_project_present(opts[:project_name])
    xcodegen_store = extract_all(project, opts[:schemes], opts[:configurations])

    # Fingerprint XcodeGen's pbxproj before Tuist runs. The comparison below
    # is "the project on disk after each generator", so a `tuist generate`
    # that exits 0 without rewriting the file — a Tuist/Config.swift or
    # Workspace.swift redirecting output, a wrong --project-name, a future
    # cache skip — would make the second extraction read XcodeGen's project
    # again and the verdict a false PARITY OK: the stale-project false green
    # the header says this tool exists to eliminate, closed for --skip-generate
    # and, until this check, open on the main path (03-REVIEW WR-04). XcodeGen
    # and Tuist never emit identical pbxproj bytes (their object ids differ),
    # so an unchanged file can only mean nothing was regenerated.
    pbxproj_after_xcodegen = File.binread(File.join(project, "project.pbxproj"))

    tuist_ran = true
    run_generator("tuist", %w[tuist generate --no-open])
    project = assert_project_present(opts[:project_name])
    if File.binread(File.join(project, "project.pbxproj")) == pbxproj_after_xcodegen
      no_verdict "tuist generate exited 0 but #{project}/project.pbxproj is byte-identical to XcodeGen's " \
                 "output; nothing was regenerated, so a comparison would read the same project twice"
    end
    tuist_store = extract_all(project, opts[:schemes], opts[:configurations])

    differing = 0
    opts[:schemes].each do |scheme|
      opts[:configurations].each do |cfg|
        xg_lines, xg_team_empty = xcodegen_store[[scheme, cfg]]
        tu_lines, tu_team_empty = tuist_store[[scheme, cfg]]
        print_block("xcodegen #{scheme} #{cfg}", xg_lines, xg_team_empty)
        if xg_lines == tu_lines
          puts "--- tuist #{scheme} #{cfg} --- identical to xcodegen (#{xg_lines.length} keys)"
        else
          differing += 1
          puts "--- tuist #{scheme} #{cfg} --- DIFFERS from xcodegen"
          puts unified_diff(xg_lines, tu_lines, "xcodegen #{scheme} #{cfg}", "tuist #{scheme} #{cfg}")
        end
        if xg_team_empty != tu_team_empty
          puts "(note: _DEVELOPMENT_TEAM_IS_EMPTY differs between generators for #{scheme} #{cfg} — " \
               "corroboration only; the gated keys above are the verdict)"
        end
      end
    end

    pairs = opts[:schemes].length * opts[:configurations].length
    if differing.zero?
      puts "identity-parity: PARITY OK — #{pairs} scheme x configuration pair(s) identical across XcodeGen and Tuist"
      0
    else
      warn "identity-parity: PARITY FAILED — #{differing} of #{pairs} pair(s) differ between XcodeGen and Tuist"
      1
    end
  ensure
    # Leave the tree in the XcodeGen state on every path once Tuist has
    # overwritten it, because ci/local-check.sh and the lefthook pre-push hook
    # expect XcodeGen's output. Skipped when Tuist never ran: the disk is
    # already in the XcodeGen state (or in whatever state an earlier no_verdict
    # left it, which is at most an XcodeGen project).
    if tuist_ran
      out, err, restore_status = capture(xcodegen_argv, chdir: APP_DIR)
      if restore_status.zero?
        puts "identity-parity: tree left in the XcodeGen state (xcodegen generate re-run, exit 0); " \
             "Tuist's app/#{opts[:project_name]}.xcworkspace and app/Derived/ remain, gitignored"
      else
        warn "identity-parity: final xcodegen generate exited #{restore_status}; the on-disk project is Tuist's\n" \
             "#{(out + err).strip}"
      end
    end
  end

  # A failed restore is not a parity verdict of either kind: the diff above
  # still stands, but exit 0 would tell ci/local-check.sh and the pre-push
  # hook that the project on disk is XcodeGen's when it is Tuist's, and a
  # green exit that leaves the wrong project behind is the stale-project
  # false green from the other direction (03-REVIEW IN-06). So the run ends
  # in the "I don't know" code, naming the tree state and the verdict that
  # was reached. Unreachable when tuist never ran (restore_status stays nil)
  # or when the block exited through no_verdict (already 2).
  unless restore_status.nil? || restore_status.zero?
    warn "identity-parity: no verdict: the final xcodegen generate exited #{restore_status}, so " \
         "app/#{opts[:project_name]}.xcodeproj on disk is Tuist's, not XcodeGen's; the parity verdict " \
         "printed above (#{verdict.zero? ? 'PARITY OK' : 'PARITY FAILED'}) stands, but the tree does not — " \
         "run `cd app && xcodegen generate` before trusting ci/local-check.sh or the pre-push hook"
    return 2
  end
  verdict
end

exit main(ARGV)
