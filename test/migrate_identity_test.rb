#!/usr/bin/env ruby
# frozen_string_literal: true

# Unit test for tools/migrate-identity.rb — three-state detection, the exit-code
# contract, and the argv parser (IDENT-14, D-70).
#
# WHY THIS EXISTS
#
# A migration that reports success without having looked at the tree is this
# project's signature failure mode, observed rather than imagined. Upstream's
# post-#281 `check_idempotency` keys on ONE signal (app/Identity.xcconfig
# exists), which is true post-#281 and false pre-#281 — so on exactly the tree
# this migration exists to serve it answers "not migrated" for the right reason
# and "migrated" for the wrong one. And bin/rename.sh's own three-state detector
# returns a bare 0/1/2 with no message at all, so a partial tree is reported by a
# number. D-70 rejected a silent idempotent exit 0 BY NAME: it is
# indistinguishable from a migration that did nothing because it could not see
# the fork's state.
#
# So every assertion below checks the exit code AND the message together. A
# command that exits 3 on a partially-migrated tree while naming nothing has
# satisfied the number and defeated the point; `assert_exit` fails it.
#
# THE STATES, AND WHY EACH SIGNAL IS SPELLED OUT HERE
#
#   never-migrated       none of the four signals present  -> exit 0 (--dry-run)
#   already fully mig.   all four present                  -> exit 0, LOUD
#   partially migrated   any mixture                       -> exit 3, naming each
#
# Every constant below is duplicated deliberately rather than derived from the
# file under test — the rule test/identity_test.rb:56-60 states: a test that
# reads its expectations out of its subject accepts whatever that subject
# happens to say, which is not a test. The four signal labels, the five exit
# codes and the three state names are written out here by hand, and a rewording
# on either side is meant to break this file.
#
# FAILURE-LINE CONTRACT
#
# This file adopts test/identity_test.rb's one-line contract —
#
#     FAIL <group> <path>: <message>
#
# — and NOT the `✗` shape from test/parser_test.rb. The choice is stated once,
# here, and kept: the red controls that drive this suite against a deliberately
# broken command grep for `^FAIL`, and a two-line failure would make every one of
# them vacuous. Detail lines (expected/actual) follow the FAIL line, indented,
# and never begin with FAIL.
#
# HOW IT INVOKES THE COMMAND
#
# Through the interpreter running THIS file (RbConfig.ruby), never through the
# command's `#!/usr/bin/env ruby` shebang. Running the suite under 4.0.6 while
# the subprocess silently resolved PATH's ruby — which on a bare shell here is
# /usr/bin/ruby 2.6.10 — would make "green under both pinned interpreters" a
# claim about one interpreter. Executability is asserted separately, by mode.
#
# Runnable locally, from the repository root, under BOTH pinned interpreters —
# and it must pass under both, spelled out because on this machine ambient
# `ruby` IS 3.3 and the second path is the one that gets skipped:
#   /opt/homebrew/opt/ruby@3.3/bin/ruby test/migrate_identity_test.rb
#   /opt/homebrew/opt/ruby@4.0/bin/ruby test/migrate_identity_test.rb
# Never /usr/bin/ruby (2.6.10).
#
# CI caller: .github/workflows/migrate.yml, added by plan 05-05. Until then this
# suite has no CI caller and is run by hand — stated out loud rather than left
# to be discovered, because a suite nobody runs is not a gate.
#
# Ruby core only, three `require`s, no gem — which is what lets a caller in the
# `review notes` job keep `bundler-cache: false`. Every shell-out is an explicit
# argv array, never a shell string. No broad rescue: the only rescue in this file
# names Errno::ENOENT, and it exists to tell "the command is not there" apart
# from "the command failed".
#
# THE MUTATION HALF (group M7, plan 05-03)
#
# M7 runs the command against a REAL git repository built in a temp dir, because
# the clean-tree gate, the on-main gate, the Team-ID ignore gate and the rollback
# are all git operations and a synthetic directory cannot exercise any of them.
#
# Two fixture knobs of the command's own contract are driven here, and both
# announce themselves on stderr — asserted, because a silent knob is a way to
# disable a gate without anything going red:
#
#   MIGRATE_IDENTITY_TOOL_DIR    resolves xcodebuild and xcodegen from a fixture
#                                bin directory instead of PATH. Without it these
#                                cases would say something different on a machine
#                                with Xcode than on one without, which is not a
#                                test. git is deliberately NOT resolved through it.
#   MIGRATE_IDENTITY_FAIL_AFTER  raises after a named mutation stage, which is the
#                                only way to reach the rollback path from a test
#                                without breaking the command on purpose.
#
# The fixture xcodebuild emits a -showBuildSettings dump shaped like the real one
# (four-space indent, "KEY = value", one "Build settings for action" header),
# carrying the values a PRE-#281 renamed fork actually resolves: PRODUCT_NAME is
# the TARGET name including its platform suffix, because nothing sets it (A-05);
# CFBundleDisplayName is not a build setting at all and has to be read out of the
# generated plist; and NSHumanReadableCopyright is an INFOPLIST_KEY_ on iOS but a
# plist property on macOS. All three shapes were read off e773cfc:app/project.yml
# rather than assumed.

require "tmpdir"
require "fileutils"
require "rbconfig"

# The one xcconfig reader (D-57). M7 asserts the command's written
# app/Identity.xcconfig THROUGH it rather than by grepping the file: a writer
# whose output only a second parser can read is the shape UL-044 was made of.
# bin/lib/xcconfig.rb has zero require lines of its own, so this pulls in no gem
# and `review notes` keeps bundler-cache: false.
require_relative "../bin/lib/xcconfig"

ROOT = File.expand_path("..", __dir__)

# The subject. Its path is a decision recorded in the file's own header:
# fork-owned tooling lives in tools/, because bin/refork-smoketest.sh deletes
# this repository and recreates it from the template (AGENTS.md:271).
COMMAND_RELATIVE = "tools/migrate-identity.rb"
COMMAND = File.join(ROOT, COMMAND_RELATIVE)

# The interpreter this file is running under, so the subprocess is the same
# Ruby. See "HOW IT INVOKES THE COMMAND" above.
RUBY = RbConfig.ruby

# ─── the exit-code contract, duplicated deliberately ─────────────────────────
EXIT_OK       = 0  # migrated, or already fully migrated (reported LOUDLY)
EXIT_ARGV     = 1  # unknown or malformed argv
EXIT_UNKNOWN  = 2  # not a tree this command understands
EXIT_PARTIAL  = 3  # partially migrated — names every mixed signal
EXIT_MUTATION = 4  # a mutation-phase refusal (plan 05-03)

# ─── the three state names, duplicated deliberately ──────────────────────────
STATE_NEVER   = "never-migrated"
STATE_FULL    = "already fully migrated"
STATE_PARTIAL = "partially migrated"

# ─── the four D-70 signals, measured across seven refs (05-RESEARCH.md:515) ──
# These strings are the CONTRACT, not a description of it: the command prints
# them and this file asserts them, and neither derives them from the other.
SIGNAL_IDENTITY     = "app/Identity.xcconfig exists"
SIGNAL_APP_SWIFT    = "app/Shared/App.swift exists"
SIGNAL_PROJECT_NAME = "app/project.yml name: is App"
SIGNAL_ENTITLEMENTS = "app/iOS/App.entitlements exists"
ALL_SIGNALS = [SIGNAL_IDENTITY, SIGNAL_APP_SWIFT, SIGNAL_PROJECT_NAME, SIGNAL_ENTITLEMENTS].freeze

# The four identity variables a migrated app/Identity.xcconfig must define with
# a non-empty value. Same list as bin/preflight-identity.rb's REQUIRED_VARS,
# written out again here for the same reason.
REQUIRED_VARS = %w[BUNDLE_ID APP_PRODUCT_NAME DISPLAY_NAME COPYRIGHT].freeze

# The fixture's structural token. Never a real fork name: a run against a
# fixture must be unmistakable in a log.
TOKEN = "MigrateFixture"

# ─── harness ─────────────────────────────────────────────────────────────────

@failures = 0
@checks   = 0

def fail_line(group, message)
  # One line, always. A message that put the group on one line and the detail on
  # another would make every `^FAIL <group>` control vacuous.
  puts "FAIL #{group} #{COMMAND_RELATIVE}: #{message.to_s.gsub(/\s*\n\s*/, ' ')}"
  @failures += 1
end

def assert(condition, group, label)
  @checks += 1
  if condition
    puts "  ✓ #{group} #{label}"
  else
    fail_line(group, label)
  end
end

# The two fixture knobs of the command's contract, always passed explicitly so a
# developer who has one exported cannot change what this suite measures. A nil
# value UNSETS the variable in the child, which is what makes the default run in
# every case below a genuinely default run.
FAIL_AFTER_ENV = "MIGRATE_IDENTITY_FAIL_AFTER"
TOOL_DIR_ENV   = "MIGRATE_IDENTITY_TOOL_DIR"
CLEAN_ENV      = { FAIL_AFTER_ENV => nil, TOOL_DIR_ENV => nil }.freeze

# Runs an argv array from the repository root, returning [combined stdout+stderr,
# exit status]. Argv array only — a shell string would let a path with a space or
# a metacharacter change what is executed. Returns [nil, nil] when the command
# itself is not there, which is a THIRD outcome and must not read as a failed
# assertion about a command that ran.
#
# `env` is merged over CLEAN_ENV, so every invocation starts from both knobs
# unset and only the case's own knob is in effect.
def run(argv, env: {})
  out = IO.popen([CLEAN_ENV.merge(env), *argv], "r", err: [:child, :out], chdir: ROOT, &:read)
  [out.to_s, $?.exitstatus]
rescue Errno::ENOENT
  [nil, nil]
end

# The whole point of D-70, in one helper.
#
# Three distinguishable failure modes, because each is a different defect:
#
#   1. command not found        — the subject is absent; every other assertion
#                                 in this file is meaningless
#   2. wrong exit code          — the command decided something else
#   3. right code, wrong message— the command exited correctly while naming
#                                 nothing, which is exactly the silent-success
#                                 shape D-70 rejects and the reason this helper
#                                 exists instead of a bare exit-code check
#
# `needles` is a String or an Array of Strings; every one must appear in the
# combined stdout+stderr.
def assert_exit(argv, expected_code, needles, group, label, env: {})
  @checks += 1
  needles = Array(needles)
  out, code = run([RUBY, COMMAND, *argv], env: env)

  if code.nil?
    fail_line(group, "#{label} — command not found at #{COMMAND}")
    return out
  end

  unless code == expected_code
    fail_line(group, "#{label} — expected exit #{expected_code}, got #{code}")
    puts "    argv:   #{argv.inspect}"
    puts "    output: #{out.to_s.strip.inspect}"
    return out
  end

  absent = needles.reject { |n| out.include?(n) }
  unless absent.empty?
    fail_line(group, "#{label} — exit #{code} was right but the message named nothing")
    puts "    expected message to contain: #{absent.map(&:inspect).join(', ')}"
    puts "    actual message:              #{out.to_s.strip.inspect}"
    return out
  end

  puts "  ✓ #{group} #{label}"
  out
end

# ─── fixture builders ────────────────────────────────────────────────────────
#
# Every tree is built inside Dir.mktmpdir and every invocation that reads a tree
# passes an explicit --root at it. Nothing in this file points the command at the
# repository root: a detection bug that mistook this repository for a migration
# target would, once plan 05-03 lands the mutation half, rewrite the developer's
# own checkout.
#
# binwrite, not write: with LANG unset Ruby sets Encoding.default_external to
# US-ASCII, and writing the © (U+00A9) in the COPYRIGHT fixture below through a
# transcoding write raises instead of producing the byte. Commit 3b1efb9 is this
# repository's own instance of inheriting the locale (UL-012).

def write_file(dir, relative, text)
  path = File.join(dir, relative)
  FileUtils.mkdir_p(File.dirname(path))
  File.binwrite(path, text)
  path
end

def project_yml(name)
  <<~YML
    # Fixture manifest. Only the `name:` line is read by the detector.
    name: #{name}

    targets:
      #{name}-iOS:
        type: application
  YML
end

def main_swift(token)
  <<~SWIFT
    import SwiftUI

    @main
    struct #{token}Main: App {
        var body: some Scene { WindowGroup { Text("fixture") } }
    }
  SWIFT
end

ENTITLEMENTS = <<~XML
  <?xml version="1.0" encoding="UTF-8"?>
  <plist version="1.0"><dict/></plist>
XML

def identity_xcconfig(omit: [])
  rows = {
    "BUNDLE_ID"        => "com.indiagram.migratefixture.ios",
    "APP_PRODUCT_NAME" => "MigrateFixture",
    "DISPLAY_NAME"     => "Migrate Fixture",
    "COPYRIGHT"        => "Copyright © 2026 Fixture. All rights reserved."
  }
  body = rows.reject { |k, _| omit.include?(k) }
             .map { |k, v| "#{k.ljust(16)} = #{v}" }
             .join("\n")
  "// fixture identity — not a release configuration\n#{body}\n"
end

# All four signals absent: a pre-#281 fork that ran the rename and has never
# been migrated. This is the population IDENT-14 serves.
def build_never_migrated(dir)
  write_file(dir, "app/project.yml", project_yml(TOKEN))
  write_file(dir, "app/Shared/#{TOKEN}.swift", main_swift(TOKEN))
  write_file(dir, "app/iOS/#{TOKEN}.entitlements", ENTITLEMENTS)
  dir
end

# All four signals present: the shape this repository's HEAD is in.
def build_fully_migrated(dir, omit_vars: [])
  write_file(dir, "app/project.yml", project_yml("App"))
  write_file(dir, "app/Shared/App.swift", main_swift("App"))
  write_file(dir, "app/iOS/App.entitlements", ENTITLEMENTS)
  write_file(dir, "app/Identity.xcconfig", identity_xcconfig(omit: omit_vars))
  dir
end

# A mixture: the xcconfig landed, the structure did not. The state D-70 exists
# to refuse — and the one a single-signal detector calls "already migrated".
def build_partially_migrated(dir)
  write_file(dir, "app/project.yml", project_yml(TOKEN))
  write_file(dir, "app/Shared/#{TOKEN}.swift", main_swift(TOKEN))
  write_file(dir, "app/iOS/#{TOKEN}.entitlements", ENTITLEMENTS)
  write_file(dir, "app/Identity.xcconfig", identity_xcconfig)
  dir
end

# An init only — no commit, no config, no network. Used by the one M6 case that
# has to reach the mutation-phase gates, which are gated on the tree being a git
# repository because the rollback D-70 requires is a git operation.
#
# The prose here deliberately does not spell a backticked git invocation: plan
# 05-03's acceptance criterion greps this file for one, to prove every shell-out
# is an argv array. Measured 2026-09-03 — the criterion matched two COMMENTS in
# the committed file and no code, so the grep was honest about the file and wrong
# about the defect. The comments were reworded rather than the criterion relaxed.
def git_init(dir)
  IO.popen(["git", "init", "-q", dir], "r", err: [:child, :out], &:read)
  $?.exitstatus.zero? && File.exist?(File.join(dir, ".git"))
end

# ─── M7 fixtures: a real repository, a fixture toolchain, a real rollback ────

# The fixture identity, as the fixture xcodebuild reports it. Never a real fork's
# values, and never the template's two literals (tools/check-contamination.rb
# would be right to fail this file if it carried either).
FIXTURE_BUNDLE_ID   = "com.fixture.migratefixture"
# The ampersand and the angle brackets are deliberate. A generated Info.plist is
# XML, so these arrive at the reader as &amp;, &lt; and &gt; — and MEASURED in
# the ground-truth fixture, e773cfc's own copyright placeholder is
# "TODO Copyright © <Your Org>. All rights reserved.", which the macOS plist
# carries as &lt;Your Org&gt;. Without them the suite passed against a command
# whose XML unescape had been deleted: the control could not go red because the
# fixture had nothing to unescape. Copyright is additionally the one value that
# arrives from a DIFFERENT source on each platform — an INFOPLIST_KEY_ build
# setting on iOS, a plist property on macOS — so a missing unescape makes the two
# platforms disagree and the run refuses.
FIXTURE_DISPLAY     = "Migrate & Fixture"
FIXTURE_COPYRIGHT   = "Copyright © 2026 <Fixture Org>. All rights reserved."
# Ten upper-case alphanumerics, the Apple Team ID shape, and obviously synthetic.
FIXTURE_TEAM_ID     = "FIXTURE001"
TEAM_ID_PLACEHOLDER = "TEAM_ID_PLACEHOLDER"
# RFC 2606 .invalid, and the local part carries no person's name. The domain has
# a row in tools/domain-allowlist.txt naming exactly this use.
FIXTURE_GIT_EMAIL   = "t@local.invalid"

# The two gitignored files the rollback must not destroy. Their bytes are
# asserted identical afterwards, so the content matters only in that it is
# distinctive and non-empty.
BOOTSTRAP_ENV_FIXTURE  = "# fixture .bootstrap.env — precious, gitignored, never in git\nAPP_NAME=MigrateFixture\n"
LOCAL_XCCONFIG_FIXTURE = "// fixture app/Local.xcconfig — precious, gitignored, never in git\n"

# git, always as an argv array and always through `run`, so a missing git binary
# is [nil, nil] rather than an exception out of a fixture builder.
def git(chdir, *argv)
  run(["git", "-C", chdir, *argv])
end

# Author identity supplied per-invocation with -c, never written to a config, so
# the fixture cannot pick up or leave behind a developer's own identity.
def git_commit_all(chdir, message)
  _, add_code = git(chdir, "-c", "user.email=#{FIXTURE_GIT_EMAIL}", "-c", "user.name=fixture",
                    "add", "-A")
  return false unless add_code&.zero?

  _, code = git(chdir, "-c", "user.email=#{FIXTURE_GIT_EMAIL}", "-c", "user.name=fixture",
                "commit", "-q", "-m", message)
  code&.zero?
end

def write_exec(path, body)
  FileUtils.mkdir_p(File.dirname(path))
  File.binwrite(path, body)
  File.chmod(0o755, path)
  path
end

# The fixture xcodebuild. Assembled line by line rather than from one interpolated
# heredoc, because a Ruby heredoc that interpolates would eat every shell `$` in
# it — the class of silent-mutation defect plans 05-01 and 05-02 each hit once.
# The two interpolated lines are the only two, and both are asserted present by
# the builder below.
def xcodebuild_stub(ios_product:, macos_product:, blocks: 1, exit_code: 0,
                    configuration: "Debug")
  lines = ["#!/bin/sh"]
  lines << "# fixture xcodebuild — emits a -showBuildSettings dump, writes nothing."
  if exit_code != 0
    lines << 'echo "xcodebuild: error: fixture failure, no such scheme" >&2'
    lines << "exit #{exit_code}"
    return "#{lines.join("\n")}\n"
  end

  lines << 'scheme=""'
  lines << 'want=""'
  lines << 'for a in "$@"; do'
  lines << '  if [ "$want" = "1" ]; then scheme="$a"; want=""; fi'
  lines << '  if [ "$a" = "-scheme" ]; then want="1"; fi'
  lines << 'done'
  # pwd, never $PWD: Process.spawn(chdir:) does not update the child's PWD
  # variable, so $PWD would name the caller's directory instead of the tree the
  # command was pointed at. Measured while writing this fixture.
  lines << 'srcroot="$(pwd)/app"'
  lines << 'case "$scheme" in'
  lines << "  *-macOS) plist='macOS/Generated-Info.plist'; product='#{macos_product}' ;;"
  lines << "  *)       plist='iOS/Generated-Info.plist'; product='#{ios_product}' ;;"
  lines << 'esac'
  lines << 'emit() {'
  lines << '  echo "Build settings for action build and target $scheme:"'
  lines << "  echo \"    CONFIGURATION = #{configuration}\""
  lines << '  echo "    INFOPLIST_FILE = $plist"'
  lines << "  echo \"    PRODUCT_BUNDLE_IDENTIFIER = #{FIXTURE_BUNDLE_ID}\""
  lines << '  echo "    PRODUCT_NAME = $product"'
  lines << '  echo "    SRCROOT = $srcroot"'
  # iOS carries copyright as an INFOPLIST_KEY_ build setting and macOS carries it
  # as a plist property — measured on e773cfc:app/project.yml:64 and :86, and the
  # reason the command needs both readers.
  lines << '  case "$scheme" in'
  lines << '    *-macOS) : ;;'
  lines << "    *) echo \"    INFOPLIST_KEY_NSHumanReadableCopyright = #{FIXTURE_COPYRIGHT}\" ;;"
  lines << '  esac'
  lines << '}'
  blocks.times { lines << "emit" }
  lines << "exit 0"
  "#{lines.join("\n")}\n"
end

# A fixture bin directory for MIGRATE_IDENTITY_TOOL_DIR. `parent` must NOT be the
# fixture repository root: these files are not part of the tree under test and
# would make it dirty.
def build_tool_dir(parent, xcodegen: true, **stub_options)
  bin = File.join(parent, "fixture-bin")
  FileUtils.mkdir_p(bin)
  write_exec(File.join(bin, "xcodegen"), "#!/bin/sh\necho 'Version: 0.0.0-fixture'\nexit 0\n") if xcodegen
  unless stub_options[:absent]
    body = xcodebuild_stub(ios_product: stub_options.fetch(:ios_product, "#{TOKEN}-iOS"),
                           macos_product: stub_options.fetch(:macos_product, "#{TOKEN}-macOS"),
                           blocks: stub_options.fetch(:blocks, 1),
                           exit_code: stub_options.fetch(:exit_code, 0),
                           configuration: stub_options.fetch(:configuration, "Debug"))
    write_exec(File.join(bin, "xcodebuild"), body)
  end
  bin
end

def fixture_project_yml(token, team_id)
  <<~YML
    # Fixture manifest, shaped like a pre-#281 renamed fork's.
    name: #{token}

    settings:
      base:
        MARKETING_VERSION: "0.0.1"
        DEVELOPMENT_TEAM: "#{team_id}"   # substituted at fork creation by the retired script
        CODE_SIGN_STYLE: Automatic

    targets:
      #{token}-iOS:
        type: application
      #{token}-macOS:
        type: application
  YML
end

def fixture_project_swift(token, team_id)
  <<~SWIFT
    import ProjectDescription

    let baseSettings: SettingsDictionary = [
        "MARKETING_VERSION": "0.0.1",
        // DEVELOPMENT_TEAM is substituted at fork creation by the retired script.
        "DEVELOPMENT_TEAM": "#{team_id}",
        "CODE_SIGN_STYLE": "Automatic",
    ]

    let project = Project(name: "#{token}")
  SWIFT
end

# XcodeGen's generated plist, tab-indented like the real one. The display name
# lives ONLY here — it is not a build setting in a pre-#281 fork, which is why
# the command needs a plist read at all.

# XcodeGen writes a plist, and a plist is XML, so a value carrying &, < or >
# arrives escaped. The fixture escapes on the way in for the same reason the
# command unescapes on the way out; asserting the round trip is what makes the
# unescape load-bearing.
def xml_escape(text)
  text.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
end

def generated_plist(display:, copyright: nil)
  rows = ["\t<key>CFBundleDisplayName</key>", "\t<string>#{xml_escape(display)}</string>"]
  unless copyright.nil?
    rows << "\t<key>NSHumanReadableCopyright</key>"
    rows << "\t<string>#{xml_escape(copyright)}</string>"
  end
  <<~XML
    <?xml version="1.0" encoding="UTF-8"?>
    <plist version="1.0">
    <dict>
    #{rows.join("\n")}
    \t<key>CFBundleShortVersionString</key>
    \t<string>$(MARKETING_VERSION)</string>
    </dict>
    </plist>
  XML
end

def fixture_gitignore(ignore_local_xcconfig)
  rows = ["app/*.xcodeproj/", "app/*.xcworkspace/", "app/*/Generated-Info.plist", ".bootstrap.env"]
  rows << "app/Local.xcconfig" if ignore_local_xcconfig
  "#{rows.join("\n")}\n"
end

# A pre-#281 renamed fork in a real git repository with one commit and a CLEAN
# working tree. Returns nil on success, or a String naming what went wrong —
# never raises, so a fixture failure arrives as a FAIL line rather than as a
# backtrace where a named refusal belongs.
def build_migration_fixture(dir, branch: "main", team_id: FIXTURE_TEAM_ID,
                            ignore_local_xcconfig: true, with_local_xcconfig: true,
                            with_xcodeproj: true)
  FileUtils.mkdir_p(dir)
  write_file(dir, "app/project.yml", fixture_project_yml(TOKEN, team_id))
  write_file(dir, "app/Project.swift", fixture_project_swift(TOKEN, team_id))
  write_file(dir, "app/Shared/#{TOKEN}.swift", main_swift(TOKEN))
  write_file(dir, "app/iOS/#{TOKEN}.entitlements", ENTITLEMENTS)
  write_file(dir, "app/macOS/#{TOKEN}.entitlements", ENTITLEMENTS)
  write_file(dir, ".gitignore", fixture_gitignore(ignore_local_xcconfig))
  # Gitignored, exactly as they are in a real tree.
  write_file(dir, "app/iOS/Generated-Info.plist", generated_plist(display: FIXTURE_DISPLAY))
  write_file(dir, "app/macOS/Generated-Info.plist",
             generated_plist(display: FIXTURE_DISPLAY, copyright: FIXTURE_COPYRIGHT))
  write_file(dir, "app/#{TOKEN}.xcodeproj/project.pbxproj", "// fixture project\n") if with_xcodeproj
  write_file(dir, ".bootstrap.env", BOOTSTRAP_ENV_FIXTURE)
  write_file(dir, "app/Local.xcconfig", LOCAL_XCCONFIG_FIXTURE) if with_local_xcconfig

  _, init_code = run(["git", "init", "-q", "-b", branch, dir])
  return "git init -b #{branch} failed in #{dir}" unless init_code&.zero?
  return "could not commit the fixture tree in #{dir}" unless git_commit_all(dir, "fixture base")

  porcelain, status_code = git(dir, "status", "--porcelain")
  return "git status failed in #{dir}" unless status_code&.zero?
  return "fixture tree is not clean after the base commit: #{porcelain.inspect}" unless porcelain.to_s.strip.empty?

  nil
end

# nil when the file is not there, rather than an exception.
#
# MEASURED, and the reason this helper exists rather than a bare File.binread:
# with the -x variant substituted for -fd in the rollback's clean — the one-character
# change T-05-12 is about — the suite exited 1 with ZERO `FAIL` lines, because
# the assertion raised Errno::ENOENT on the file the rollback had just deleted.
# Exit 1 is the right code by luck, and a red control that greps for `^FAIL`
# would have recorded "no failure detected" against a rollback that destroyed the
# forker's gitignored secrets. A missing file is now a named FAIL line.
def bytes_of(path)
  File.file?(path) ? File.binread(path) : nil
end

def text_of(path)
  File.file?(path) ? File.read(path, encoding: "UTF-8") : nil
end

def head_of(dir)
  out, code = git(dir, "rev-parse", "HEAD")
  code&.zero? ? out.to_s.strip : nil
end

def porcelain_of(dir)
  out, code = git(dir, "status", "--porcelain")
  code&.zero? ? out.to_s : nil
end

# ─── Preconditions: fail loudly and specifically if the subject is absent ─────
#
# This is the RED assertion. Before tools/migrate-identity.rb lands, this file
# must say WHICH path is missing, on one FAIL line, and exit 1 — never an
# Errno::ENOENT backtrace out of IO.popen, which would be a stack trace where a
# named refusal belongs.

missing = []
if !File.exist?(COMMAND)
  missing << "not found at #{COMMAND} — plan 05-02 Task 2 has not landed yet"
elsif !File.executable?(COMMAND)
  missing << "present at #{COMMAND} but not executable (expected mode 100755)"
end

if missing.empty?
  help_out, help_code = run([RUBY, COMMAND, "--help"])
  if help_code.nil?
    missing << "could not be executed at #{COMMAND}"
  elsif help_code != EXIT_OK
    missing << "--help exited #{help_code}, expected #{EXIT_OK} (output: #{help_out.to_s.strip.inspect})"
  elsif !help_out.include?("migrate-identity")
    missing << "--help printed no usage line naming migrate-identity (output: #{help_out.to_s.strip.inspect})"
  end
end

unless missing.empty?
  missing.each { |m| puts "FAIL M0 #{COMMAND_RELATIVE}: #{m}" }
  puts
  puts "FAILED (#{missing.length} precondition(s) unmet) — this is the RED half of plan 05-02"
  exit 1
end

# ─── M1: argv is parsed, and unknown argv is REJECTED, never ignored ─────────

puts "M1 — argv: a typo must not look like a successful run:"

assert_exit ["--help"], EXIT_OK, ["usage:", "migrate-identity", "--root", "--dry-run"],
            "M1", "--help exits 0 and prints the usage line"

assert_exit ["--bogus", "--dry-run"], EXIT_ARGV, ["--bogus", "usage:"],
            "M1", "an unknown argument exits 1 naming the argument and the usage"

assert_exit ["--root"], EXIT_ARGV, ["--root requires a PATH argument", "usage:"],
            "M1", "--root with no value exits 1 naming the requirement"

assert_exit ["--root", "--dry-run"], EXIT_ARGV, ["--root requires a PATH argument"],
            "M1", "--root swallowing the next flag as its value exits 1"

assert_exit ["--root", "/a", "--root", "/b", "--dry-run"], EXIT_ARGV,
            ["--root given more than once", "usage:"],
            "M1", "--root given twice exits 1 rather than picking one"

# ─── M2: a tree this command does not understand is a DISTINCT outcome ───────
#
# Exit 2 is the tools/asc-probe.rb idiom restated at bin/preflight-identity.rb:32-48:
# "not found" is a different answer from "checked and wrong", and it gets its own
# code so a caller can never read one as the other.

puts "M2 — exit 2: not a tree this command understands:"

Dir.mktmpdir("migrate-shape") do |tmp|
  absent = File.join(tmp, "no-such-tree")
  assert_exit ["--root", absent, "--dry-run"], EXIT_UNKNOWN, [absent, "not found", "cwd"],
              "M2", "a --root that does not exist exits 2 naming the absolute path and the cwd"

  regular = write_file(tmp, "a-file", "not a tree\n")
  assert_exit ["--root", regular, "--dry-run"], EXIT_UNKNOWN, [regular, "is not a directory", "cwd"],
              "M2", "a --root that is a regular file exits 2 naming what it is"

  bare = File.join(tmp, "bare")
  FileUtils.mkdir_p(bare)
  assert_exit ["--root", bare, "--dry-run"], EXIT_UNKNOWN, [bare, "app/project.yml", "cwd"],
              "M2", "a directory with no app/project.yml exits 2 naming the manifest"
end

# ─── M3: the three D-70 states, each exiting distinguishably ─────────────────

puts "M3 — three states, three exits, every one of them named:"

Dir.mktmpdir("migrate-never") do |tmp|
  build_never_migrated(tmp)
  assert_exit ["--root", tmp, "--dry-run"], EXIT_OK, [STATE_NEVER, TOKEN],
              "M3", "a never-migrated tree exits 0 in --dry-run naming the state and the token"
end

Dir.mktmpdir("migrate-full") do |tmp|
  build_fully_migrated(tmp)
  assert_exit ["--root", tmp, "--dry-run"], EXIT_OK, [STATE_FULL, *ALL_SIGNALS],
              "M3", "a fully-migrated tree exits 0 LOUDLY naming all four satisfied signals"
end

Dir.mktmpdir("migrate-partial") do |tmp|
  build_partially_migrated(tmp)
  # The comma-separated list is asserted as ONE needle, in order: a message that
  # named only the first mixed signal would pass three separate `include?`
  # checks against a list it never printed.
  mixed = [SIGNAL_APP_SWIFT, SIGNAL_PROJECT_NAME, SIGNAL_ENTITLEMENTS].join(", ")
  assert_exit ["--root", tmp, "--dry-run"], EXIT_PARTIAL,
              [STATE_PARTIAL, "satisfied signal(s): #{SIGNAL_IDENTITY}", "unsatisfied signal(s): #{mixed}"],
              "M3", "a partially-migrated tree exits 3 naming EVERY mixed signal, comma-separated"
end

# ─── M4: refusals that name what was found, not that something was wrong ─────

puts "M4 — a tree whose identity cannot be read one way is refused, not guessed:"

Dir.mktmpdir("migrate-token") do |tmp|
  # Two independent derivations disagree: the manifest says one token, the
  # @main struct says another. A tree whose identity cannot be read the same way
  # twice is not one this command understands.
  write_file(tmp, "app/project.yml", project_yml(TOKEN))
  write_file(tmp, "app/Shared/OtherToken.swift", main_swift("OtherToken"))
  assert_exit ["--root", tmp, "--dry-run"], EXIT_UNKNOWN, [TOKEN, "OtherToken", "disagree"],
              "M4", "disagreeing token derivations exit 2 naming every value found"
end

Dir.mktmpdir("migrate-two-mains") do |tmp|
  # A half-moved @main: the migration renamed the file but the old one is still
  # on disk. Two entry points is not a state to pick a winner from.
  write_file(tmp, "app/project.yml", project_yml(TOKEN))
  write_file(tmp, "app/Shared/#{TOKEN}.swift", main_swift(TOKEN))
  write_file(tmp, "app/Shared/OtherToken.swift", main_swift("OtherToken"))
  assert_exit ["--root", tmp, "--dry-run"], EXIT_UNKNOWN, ["more than one", TOKEN, "OtherToken"],
              "M4", "two @main structs exit 2 naming both, rather than picking the first"
end

Dir.mktmpdir("migrate-two-projects") do |tmp|
  # A stale generated project beside a fresh one. Both are gitignored and
  # regenerable, so the refusal is cheap to act on — and guessing is not.
  build_fully_migrated(tmp)
  FileUtils.mkdir_p(File.join(tmp, "app/App.xcodeproj"))
  FileUtils.mkdir_p(File.join(tmp, "app/#{TOKEN}.xcodeproj"))
  assert_exit ["--root", tmp, "--dry-run"], EXIT_UNKNOWN,
              ["more than one generated project", "App.xcodeproj", "#{TOKEN}.xcodeproj"],
              "M4", "two app/*.xcodeproj exit 2 naming both, rather than picking the first"
end

Dir.mktmpdir("migrate-holes") do |tmp|
  # Structure fully migrated, values not: an app/Identity.xcconfig with a hole in
  # it. `BUNDLE_ID =` with nothing after the equals sign is what Xcode reads as
  # the empty string, both generators exit 0, and the built app carries an empty
  # CFBundleIdentifier (RESEARCH Pitfall 1). "The file exists" is not a check.
  build_fully_migrated(tmp, omit_vars: ["BUNDLE_ID"])
  assert_exit ["--root", tmp, "--dry-run"], EXIT_PARTIAL,
              [STATE_PARTIAL, "missing required variable(s): BUNDLE_ID"],
              "M4", "a present-but-incomplete app/Identity.xcconfig exits 3 naming the variable"
end

Dir.mktmpdir("migrate-include") do |tmp|
  build_fully_migrated(tmp)
  write_file(tmp, "app/Identity.xcconfig",
             "#include \"absent-include.xcconfig\"\n#{identity_xcconfig}")
  assert_exit ["--root", tmp, "--dry-run"], EXIT_UNKNOWN,
              ["absent-include.xcconfig", "could not be resolved"],
              "M4", "an unresolvable #include exits 2 naming the include, never 'that key is empty'"
end

# ─── M5: a fixture run can never be mistaken for a real one in a log ─────────

puts "M5 — the --root knob announces itself (T-05-06):"

Dir.mktmpdir("migrate-banner") do |tmp|
  build_fully_migrated(tmp)
  assert_exit ["--root", tmp, "--dry-run"], EXIT_OK,
              ["ROOT OVERRIDE IN EFFECT", ROOT, "was NOT inspected", tmp],
              "M5", "--root banners both the default root it skipped and the override it took"
end

# The paired assertion Shared Pattern 3 requires, and the reason the one above is
# not vacuous: a banner printed unconditionally would satisfy the assertion above
# on every run while telling a log reader nothing. This is the only case in the
# file that runs with no --root, and it is safe because --dry-run writes nothing
# and this repository is a fully-migrated tree, so it reaches the report and
# stops there.
default_out, default_code = run([RUBY, COMMAND, "--dry-run"])
assert default_code == EXIT_OK && !default_out.to_s.include?("ROOT OVERRIDE IN EFFECT"),
       "M5",
       "a default run prints NO override banner (exit #{default_code.inspect}, " \
       "banner present: #{default_out.to_s.include?('ROOT OVERRIDE IN EFFECT')})"

# ─── M6: the mutation phase refuses distinguishably, and does not backtrace ──
#
# Without --dry-run the never-migrated path reaches the mutation half, which
# plan 05-03 implements. Until then it must refuse with a CODE, not with an
# uncaught NotImplementedError: Ruby exits 1 on an uncaught exception, and exit 1
# is spoken for by malformed argv, so a caller branching on the code would read
# "not implemented yet" as "you called me wrong" (the 03-REVIEW IN-01 shape).

puts "M6 — the mutation phase is refused by code, not by backtrace:"

Dir.mktmpdir("migrate-nogit") do |tmp|
  build_never_migrated(tmp)
  assert_exit ["--root", tmp], EXIT_UNKNOWN, [tmp, "not a git repository"],
              "M6", "mutating a tree with no git repository exits 2 — rollback needs one"
end

# Past the git-repository check the tool gates and the clean-tree gate run, in
# bin/rename.sh:904-1000's order. This tree was inited and never committed, so
# every file in it is untracked and the clean-tree gate is what stops it — which
# is the point: the refusal that reaches the operator must be the FIRST unmet
# precondition, not the last one. The tool directory is supplied so the case says
# the same thing on a machine with Xcode and on one without.
Dir.mktmpdir("migrate-git") do |box|
  tmp = File.join(box, "repo")
  FileUtils.mkdir_p(tmp)
  build_never_migrated(tmp)
  bin = build_tool_dir(box)
  if git_init(tmp)
    assert_exit ["--root", tmp], EXIT_MUTATION,
                ["working tree not clean", tmp],
                "M6", "a mutating run on a dirty tree exits 4 naming the clean-tree gate",
                env: { TOOL_DIR_ENV => bin }
  else
    fail_line("M6", "could not init the fixture git tree at #{tmp} — git is required by this case")
    @checks += 1
  end
end

# ─── M7: the mutation phase — gates in front, rollback underneath ────────────
#
# Everything below runs against a REAL git repository with a real commit and a
# clean working tree. ci/test-verify-rename.sh:100-108 is the precedent for the
# snapshot-and-compare shape used here rather than a checkout restore: a checkout
# cannot reach a post-mutation state that was never committed, and the whole
# question these cases ask is what the tree looks like after an uncommitted
# mutation was undone.

puts
puts "M7 — the gates in front of the mutation, in bin/rename.sh's order:"

# ── the toolchain gate, and the knob that makes every case below deterministic ─

Dir.mktmpdir("migrate-tools") do |box|
  repo = File.join(box, "repo")
  if (why = build_migration_fixture(repo))
    fail_line("M7-tools", why)
    @checks += 1
  else
    empty_bin = build_tool_dir(box, xcodegen: false, absent: true)
    assert_exit ["--root", repo], EXIT_MUTATION, ["xcodegen", empty_bin],
                "M7-tools", "a toolchain with no xcodegen exits 4 naming the tool and where it looked",
                env: { TOOL_DIR_ENV => empty_bin }

    # The paired assertion. A banner printed unconditionally would satisfy the
    # one below on every run while telling a log reader nothing; a default run
    # must be silent about a knob nobody set.
    bin = build_tool_dir(box)
    out = assert_exit ["--root", repo], EXIT_MUTATION,
                      ["MIGRATE_IDENTITY_TOOL_DIR override in effect", bin, "FIXTURE"],
                      "M7-tools", "the tool-directory knob announces itself on stderr",
                      env: { TOOL_DIR_ENV => bin }
    assert !out.to_s.include?("xcodegen not found"),
           "M7-tools", "the announced run got PAST the toolchain gate (a banner on a refused run proves nothing)"
  end
end

# ── clean tree, before anything is written ────────────────────────────────────

Dir.mktmpdir("migrate-dirty") do |box|
  repo = File.join(box, "repo")
  if (why = build_migration_fixture(repo))
    fail_line("M7-clean-tree", why)
    @checks += 1
  else
    bin = build_tool_dir(box)
    File.binwrite(File.join(repo, "app/project.yml"),
                  "#{File.read(File.join(repo, 'app/project.yml'), encoding: 'UTF-8')}\n# forker's uncommitted edit\n")
    before_head      = head_of(repo)
    before_porcelain = porcelain_of(repo)

    assert_exit ["--root", repo], EXIT_MUTATION, ["working tree not clean", repo],
                "M7-clean-tree", "one uncommitted modification exits 4 naming the gate",
                env: { TOOL_DIR_ENV => bin }

    assert porcelain_of(repo) == before_porcelain && head_of(repo) == before_head,
           "M7-clean-tree",
           "the refusal left the tree EXACTLY as it found it — the forker's uncommitted work is " \
           "what the MUTATION_STARTED latch exists to protect (porcelain before " \
           "#{before_porcelain.inspect}, after #{porcelain_of(repo).inspect})"

    assert !File.exist?(File.join(repo, "app/Identity.xcconfig")),
           "M7-clean-tree", "the gate fired BEFORE any write — app/Identity.xcconfig does not exist"
  end
end

# ── on main, and the branch case that must NOT be a refusal ───────────────────

Dir.mktmpdir("migrate-branch") do |box|
  repo = File.join(box, "repo")
  if (why = build_migration_fixture(repo, branch: "main"))
    fail_line("M7-on-main", why)
    @checks += 1
  else
    bin = build_tool_dir(box)
    _, co = git(repo, "checkout", "-q", "-b", "side-branch")
    if co&.zero?
      assert_exit ["--root", repo], EXIT_MUTATION, ["side-branch", "main"],
                  "M7-on-main", "a repository that HAS main, checked out elsewhere, exits 4 naming both",
                  env: { TOOL_DIR_ENV => bin }
    else
      fail_line("M7-on-main", "could not create the side branch in #{repo}")
      @checks += 1
    end
  end
end

Dir.mktmpdir("migrate-nomain") do |box|
  repo = File.join(box, "repo")
  # A fixture clone can legitimately be on any branch, and 05-01's harness
  # force-sets main for exactly this reason. Absence of main is a WARNING, not a
  # refusal — asserted, because a gate that refuses here would refuse every
  # fixture and would then be deleted rather than fixed.
  if (why = build_migration_fixture(repo, branch: "work"))
    fail_line("M7-on-main", why)
    @checks += 1
  else
    bin = build_tool_dir(box)
    assert_exit ["--root", repo], EXIT_MUTATION,
                ["no main branch", "work", "PARTIAL MIGRATION LEFT IN PLACE"],
                "M7-on-main", "a repository with no main branch WARNS and proceeds",
                env: { TOOL_DIR_ENV => bin }
  end
end

puts
puts "M7 — the Team ID reaches only a path git confirms is ignored:"

Dir.mktmpdir("migrate-placeholder") do |box|
  repo = File.join(box, "repo")
  if (why = build_migration_fixture(repo, team_id: TEAM_ID_PLACEHOLDER))
    fail_line("M7-team-id", why)
    @checks += 1
  else
    bin  = build_tool_dir(box)
    head = head_of(repo)
    local_before = bytes_of(File.join(repo, "app/Local.xcconfig"))

    assert_exit ["--root", repo], EXIT_MUTATION, [TEAM_ID_PLACEHOLDER, "app/project.yml"],
                "M7-team-id", "an unsubstituted placeholder is refused by name, not written anywhere",
                env: { TOOL_DIR_ENV => bin }

    assert bytes_of(File.join(repo, "app/Local.xcconfig")) == local_before &&
           porcelain_of(repo).to_s.strip.empty? && head_of(repo) == head,
           "M7-team-id", "the placeholder refusal wrote nothing and rolled the tree back"
  end
end

Dir.mktmpdir("migrate-norow") do |box|
  repo = File.join(box, "repo")
  # MEASURED on e773cfc:.gitignore — a pre-#281 fork has NO app/Local.xcconfig
  # row, because that file is a post-#281 concept. Refusing on a missing row
  # would refuse the entire population this command exists for, so the row is
  # added and git is asked AGAIN. git stays the arbiter.
  if (why = build_migration_fixture(repo, ignore_local_xcconfig: false, with_local_xcconfig: false))
    fail_line("M7-team-id", why)
    @checks += 1
  else
    bin = build_tool_dir(box)
    assert_exit ["--root", repo], EXIT_MUTATION,
                ["added app/Local.xcconfig to .gitignore", "PARTIAL MIGRATION LEFT IN PLACE"],
                "M7-team-id",
                "a tree with no .gitignore row gains one and the migration proceeds",
                env: { TOOL_DIR_ENV => bin }

    assert text_of(File.join(repo, ".gitignore")).to_s.include?("app/Local.xcconfig"),
           "M7-team-id", ".gitignore gained the row, so the write happened behind a real ignore"

    local = File.join(repo, "app/Local.xcconfig")
    assert File.file?(local) && Xcconfig.own(local)["DEVELOPMENT_TEAM"] == FIXTURE_TEAM_ID,
           "M7-team-id", "and the Team ID then landed in it"

    # The row is what makes the write safe, so prove git agrees rather than
    # trusting that the text was appended.
    _, ignored = git(repo, "check-ignore", "-q", "--", "app/Local.xcconfig")
    assert ignored&.zero?, "M7-team-id",
           "git itself now reports app/Local.xcconfig as ignored (check-ignore exit #{ignored.inspect})"
  end
end

Dir.mktmpdir("migrate-tracked-local") do |box|
  repo = File.join(box, "repo")
  # The refusal that still has to fire, and the one that matters. MEASURED: git
  # reports a TRACKED path as not-ignored whatever .gitignore says, so a fork
  # that already committed app/Local.xcconfig cannot be given a Team ID by
  # adding a row — the file would go into the next commit (T-05-11).
  if (why = build_migration_fixture(repo, ignore_local_xcconfig: false, with_local_xcconfig: true))
    fail_line("M7-team-id", why)
    @checks += 1
  else
    bin  = build_tool_dir(box)
    head = head_of(repo)
    tracked, ls_code = git(repo, "ls-files", "--", "app/Local.xcconfig")
    assert ls_code&.zero? && tracked.to_s.strip == "app/Local.xcconfig",
           "M7-team-id", "the fixture really did commit app/Local.xcconfig (ls-files: #{tracked.to_s.strip.inspect})"

    assert_exit ["--root", repo], EXIT_MUTATION,
                ["check-ignore", "app/Local.xcconfig", "TRACKED", "git rm --cached"],
                "M7-team-id",
                "a TRACKED Local.xcconfig is refused by name and told how to fix it",
                env: { TOOL_DIR_ENV => bin }

    assert Xcconfig.own(File.join(repo, "app/Local.xcconfig"))["DEVELOPMENT_TEAM"].nil?,
           "M7-team-id", "no Team ID was written into the tracked file"

    assert porcelain_of(repo).to_s.strip.empty? && head_of(repo) == head,
           "M7-team-id", "and the .gitignore edit the refusal made on the way was rolled back"
  end
end

puts
puts "M7 — the rollback, demonstrated against an injected failure:"

# The knob's two stages, each rolled back and each measured the same four ways.
# The second stage is the one the plan did not ask for and the one that matters:
# git reset --hard cannot restore a GITIGNORED file, so a rollback after the
# Team-ID move has to have snapshotted app/Local.xcconfig itself or it leaves the
# forker's secret file rewritten while claiming the tree was restored.
[
  ["xcconfig-write", "migrate-rollback"],
  ["team-id-move",   "migrate-rollback-team-id"]
].each do |stage, slug|
  Dir.mktmpdir("migrate-rollback-#{stage}") do |box|
    repo = File.join(box, "repo")
    if (why = build_migration_fixture(repo))
      fail_line("M7-rollback", why)
      @checks += 1
      next
    end

    bin              = build_tool_dir(box)
    before_head      = head_of(repo)
    before_porcelain = porcelain_of(repo)
    before_bootstrap = bytes_of(File.join(repo, ".bootstrap.env"))
    before_local     = bytes_of(File.join(repo, "app/Local.xcconfig"))
    before_yml       = bytes_of(File.join(repo, "app/project.yml"))

    out = assert_exit ["--root", repo], EXIT_MUTATION,
                      ["MIGRATE_IDENTITY_FAIL_AFTER override in effect: will raise after #{stage}",
                       "FIXTURE", "rolled back"],
                      "M7-rollback", "#{stage}: the knob announces itself and the failure is rolled back",
                      env: { TOOL_DIR_ENV => bin, FAIL_AFTER_ENV => stage }

    after_porcelain  = porcelain_of(repo)
    after_bootstrap  = bytes_of(File.join(repo, ".bootstrap.env"))
    after_local      = bytes_of(File.join(repo, "app/Local.xcconfig"))
    head_unchanged   = head_of(repo) == before_head && !before_head.nil?
    worktree_clean   = after_porcelain.to_s.strip.empty?
    ignored_intact   = after_bootstrap == before_bootstrap && after_local == before_local
    tracked_restored = bytes_of(File.join(repo, "app/project.yml")) == before_yml
    identity_gone    = !File.exist?(File.join(repo, "app/Identity.xcconfig"))
    # THE TWO FIELDS THAT KEEP THIS CONTROL FROM BEING VACUOUS, and they were
    # added because the RED run proved it: against a command with no mutation
    # phase at all, every property above is trivially true — nothing moved, so
    # nothing needed restoring — and the transcript line printed restored=ok for
    # a run in which no rollback existed. A restoration control that passes when
    # there was nothing to restore is the self-invalidating gate, in the one
    # place this project keeps its evidence.
    knob_honoured    = out.to_s.include?("will raise after #{stage}")
    rollback_ran     = out.to_s.include?("rolled back")

    assert knob_honoured, "M7-rollback",
           "#{stage}: the injected-failure knob was honoured and said so — without this the four " \
           "properties below are true of a command that never mutated anything"
    assert rollback_ran, "M7-rollback", "#{stage}: the command reported rolling the tree back"
    assert head_unchanged, "M7-rollback", "#{stage}: HEAD unchanged (#{before_head.inspect} -> #{head_of(repo).inspect})"
    assert worktree_clean, "M7-rollback",
           "#{stage}: git status --porcelain is EMPTY after the rollback (was #{before_porcelain.inspect}, " \
           "now #{after_porcelain.inspect})"
    assert ignored_intact, "M7-rollback",
           "#{stage}: the gitignored .bootstrap.env and app/Local.xcconfig survived byte-identical — " \
           "this is what -fd rather than the -x variant buys, and what a Team-ID move has to " \
           "snapshot (still on disk after the rollback: .bootstrap.env=" \
           "#{!after_bootstrap.nil?}, app/Local.xcconfig=#{!after_local.nil?})"
    assert tracked_restored, "M7-rollback", "#{stage}: app/project.yml is byte-identical to its committed state"
    assert identity_gone, "M7-rollback", "#{stage}: the half-written app/Identity.xcconfig was removed"

    restored = knob_honoured && rollback_ran && head_unchanged && worktree_clean &&
               ignored_intact && tracked_restored && identity_gone
    puts "RESULT control=#{slug} exit=#{EXIT_MUTATION} stage=#{stage} " \
         "knob_honoured=#{knob_honoured ? 'yes' : 'no'} " \
         "rollback_ran=#{rollback_ran ? 'yes' : 'no'} " \
         "head_unchanged=#{head_unchanged ? 'yes' : 'no'} " \
         "worktree_clean=#{worktree_clean ? 'yes' : 'no'} " \
         "ignored_files_intact=#{ignored_intact ? 'yes' : 'no'} " \
         "restored=#{restored ? 'ok' : 'FAILED'}"
    out
  end
end

Dir.mktmpdir("migrate-badstage") do |box|
  repo = File.join(box, "repo")
  if (why = build_migration_fixture(repo))
    fail_line("M7-rollback", why)
    @checks += 1
  else
    bin = build_tool_dir(box)
    assert_exit ["--root", repo], EXIT_ARGV,
                ["MIGRATE_IDENTITY_FAIL_AFTER", "no-such-stage", "xcconfig-write", "team-id-move"],
                "M7-rollback", "an unknown stage is refused by name rather than silently ignored",
                env: { TOOL_DIR_ENV => bin, FAIL_AFTER_ENV => "no-such-stage" }
  end
end

puts
puts "M7 — identity read from the BUILD, written, and read back through the one parser:"

Dir.mktmpdir("migrate-write") do |box|
  repo = File.join(box, "repo")
  if (why = build_migration_fixture(repo))
    fail_line("M7-xcconfig", why)
    @checks += 1
  else
    bin              = build_tool_dir(box)
    before_bootstrap = bytes_of(File.join(repo, ".bootstrap.env"))

    out = assert_exit ["--root", repo], EXIT_MUTATION,
                      ["PARTIAL MIGRATION LEFT IN PLACE", "05-04",
                       "app/Identity.xcconfig", "app/Local.xcconfig"],
                      "M7-xcconfig",
                      "the value half completes and the structural half is refused by name",
                      env: { TOOL_DIR_ENV => bin }

    identity = File.join(repo, "app/Identity.xcconfig")
    assert File.file?(identity), "M7-xcconfig", "the tree gained app/Identity.xcconfig"

    if File.file?(identity)
      # Read back through Xcconfig.value — what Xcode would resolve — and compare
      # to the value the build reported, not merely to non-emptiness. A value
      # carrying `//` or `$(` reads back TRUNCATED or EXPANDED and would pass a
      # non-empty check while shipping the wrong string (UL-032, T-03-06).
      expected = {
        "BUNDLE_ID"        => FIXTURE_BUNDLE_ID,
        "APP_PRODUCT_NAME" => TOKEN,
        "DISPLAY_NAME"     => FIXTURE_DISPLAY,
        "COPYRIGHT"        => FIXTURE_COPYRIGHT
      }
      REQUIRED_VARS.each do |key|
        resolved = Xcconfig.value(identity, key)
        assert !resolved.nil? && !resolved.empty? && resolved == expected.fetch(key),
               "M7-xcconfig",
               "#{key} reads back through Xcconfig.value as #{expected.fetch(key).inspect} " \
               "(resolved: #{resolved.inspect})"
      end

      assert text_of(identity).to_s.include?('#include? "Local.xcconfig"'),
             "M7-xcconfig", "the written file ends with the optional include of the gitignored Local.xcconfig"
    end

    local = File.join(repo, "app/Local.xcconfig")
    assert File.file?(local) && Xcconfig.own(local)["DEVELOPMENT_TEAM"] == FIXTURE_TEAM_ID,
           "M7-team-id",
           "the Team ID landed in gitignored app/Local.xcconfig " \
           "(own: #{File.file?(local) ? Xcconfig.own(local).inspect : 'file absent'})"

    %w[app/project.yml app/Project.swift].each do |manifest|
      @checks += 1
      body = text_of(File.join(repo, manifest)).to_s
      assert !body.include?("DEVELOPMENT_TEAM = ") && !body.include?("DEVELOPMENT_TEAM\": ") &&
             !body.include?("DEVELOPMENT_TEAM: "),
             "M7-team-id", "#{manifest} no longer assigns DEVELOPMENT_TEAM"
      assert !body.include?(FIXTURE_TEAM_ID),
             "M7-team-id", "#{manifest} carries no Team-ID-shaped value at all"
    end

    assert bytes_of(File.join(repo, ".bootstrap.env")) == before_bootstrap,
           "M7-team-id", ".bootstrap.env was not touched"

    # A-05, and the one thing this command must never say. The notice states the
    # measured change and points at the doc; Apple's tolerance of it on a live
    # listing is assumption A1 in 05-RESEARCH.md and is UNVERIFIED.
    assert out.to_s.include?("the built bundle's filename and executable name change on at least one platform") &&
           out.to_s.include?("docs/MIGRATING-FROM-RENAME.md"),
           "M7-identity", "the collapse notice states the change and points at the migration doc"

    @checks += 1
    claim = out.to_s[/apple (allows|permits)|is safe|safe to change|permitted by apple/i]
    assert claim.nil?, "M7-identity",
           "the command asserts nothing about Apple's tolerance of the change (found: #{claim.inspect})"

    assert out.to_s.include?("#{TOKEN}-iOS") && out.to_s.include?("#{TOKEN}-macOS"),
           "M7-identity", "the notice names the OLD value on each platform, not just the new one"
  end
end

puts
puts "M7 — a build dump this command cannot trust is a refusal, never a guess:"

Dir.mktmpdir("migrate-two-blocks") do |box|
  repo = File.join(box, "repo")
  if (why = build_migration_fixture(repo))
    fail_line("M7-identity", why)
    @checks += 1
  else
    bin = build_tool_dir(box, blocks: 2)
    assert_exit ["--root", repo], EXIT_UNKNOWN,
                ["exactly one", "#{TOKEN}-iOS", "Debug"],
                "M7-identity", "two target blocks exit 2 naming the scheme and the configuration",
                env: { TOOL_DIR_ENV => bin }
  end
end

Dir.mktmpdir("migrate-xcb-fail") do |box|
  repo = File.join(box, "repo")
  if (why = build_migration_fixture(repo))
    fail_line("M7-identity", why)
    @checks += 1
  else
    bin = build_tool_dir(box, exit_code: 65)
    assert_exit ["--root", repo], EXIT_UNKNOWN,
                ["showBuildSettings", "65", "#{TOKEN}-iOS"],
                "M7-identity", "a non-zero xcodebuild exits 2 naming the status and the scheme",
                env: { TOOL_DIR_ENV => bin }
  end
end

Dir.mktmpdir("migrate-disagree") do |box|
  repo = File.join(box, "repo")
  if (why = build_migration_fixture(repo))
    fail_line("M7-identity", why)
    @checks += 1
  else
    # The two platforms' PRODUCT_NAME values differ by more than the suffix. A
    # migration that picked one would rename the other platform's executable to
    # something it never was.
    bin = build_tool_dir(box, ios_product: "AlphaOne-iOS", macos_product: "BetaTwo-macOS")
    assert_exit ["--root", repo], EXIT_UNKNOWN,
                ["AlphaOne", "BetaTwo", "PRODUCT_NAME"],
                "M7-identity", "PRODUCT_NAME values that disagree beyond the suffix exit 2 naming both",
                env: { TOOL_DIR_ENV => bin }
  end
end

Dir.mktmpdir("migrate-token-mismatch") do |box|
  repo = File.join(box, "repo")
  if (why = build_migration_fixture(repo))
    fail_line("M7-identity", why)
    @checks += 1
  else
    # The build agrees with itself and disagrees with the structure. That is a
    # third opinion about the fork's identity and it is not this command's to
    # reconcile (05-RESEARCH.md:309-313).
    bin = build_tool_dir(box, ios_product: "OtherName-iOS", macos_product: "OtherName-macOS")
    assert_exit ["--root", repo], EXIT_UNKNOWN,
                ["OtherName", TOKEN],
                "M7-identity", "a collapsed PRODUCT_NAME that disagrees with the structural token exits 2",
                env: { TOOL_DIR_ENV => bin }
  end
end

Dir.mktmpdir("migrate-noproject") do |box|
  repo = File.join(box, "repo")
  if (why = build_migration_fixture(repo, with_xcodeproj: false))
    fail_line("M7-identity", why)
    @checks += 1
  else
    bin = build_tool_dir(box)
    assert_exit ["--root", repo], EXIT_MUTATION,
                ["#{TOKEN}.xcodeproj", "xcodegen generate"],
                "M7-identity",
                "no generated project to read the build from exits 4 naming the path and the fix",
                env: { TOOL_DIR_ENV => bin }
  end
end

# ─── verdict ─────────────────────────────────────────────────────────────────

puts
if @failures.zero?
  puts "All #{@checks} migrate-identity assertions passed."
  exit 0
else
  puts "#{@failures} of #{@checks} migrate-identity assertion(s) failed."
  exit 1
end
