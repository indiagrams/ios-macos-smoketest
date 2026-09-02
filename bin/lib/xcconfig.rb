# frozen_string_literal: true

# Xcconfig — the ONE reader for app/Identity.xcconfig (D-57).
#
# Why this exists: on 2026-09-02 this repository had three readers of the same
# file, and they disagreed with each other and with Xcode.
#
#   1. bin/preflight-identity.rb answers only "is this key non-empty". It has
#      no value extractor at all — it is a gate, not a parser.
#   2. ci/local-release-check.sh:152 captured `([^[:space:]/]+)`, which stops at
#      the first space or slash. Against the live file it returned BUNDLE_ID and
#      APP_PRODUCT_NAME correctly and truncated DISPLAY_NAME to `Shipkit` and
#      COPYRIGHT to `Copyright`. It was correct for BUNDLE_ID only, and only
#      because that value happens to contain no spaces (UL-032).
#   3. fastlane/Fastfile's `_fork_config` is a `.env` parser. Pointed at an
#      xcconfig it would not cut `//`, and it would turn the D-49 header line
#      `// PRODUCT_NAME = $(APP_PRODUCT_NAME) in each manifest` into a key,
#      because that comment contains an `=`.
#
# And before Phase 3 the preflight's own predicate ended in `=[ \t]*\S`, which
# matched the first `/` of a commented-out value: `BUNDLE_ID = // disabled`
# passed the gate and resolved to the empty string in Xcode (UL-031, T-03-06).
#
# Every one of those was a hand-rolled reader that was right about the happy
# value and wrong about the next one. This module is the single body, and
# test/xcconfig_test.rb is the fixture set that keeps it honest: 45 assertions,
# whose expected values were OBSERVED with `xcodebuild -showBuildSettings` on
# Xcode 26.1.1 (04-RESEARCH.md Q1, probe 2026-09-02) and recorded in
# evidence/03-SEC-T0306-comment-value-fix.txt. Do not change a behaviour below
# without re-measuring against Xcode and moving the fixture in the same commit.
#
# The semantics reproduced, all observed rather than assumed:
#
#   - the LAST assignment wins, including across `#include` boundaries, in file
#     order — so an include is position-sensitive
#   - `//` opens a comment at ANY position in a value: `K = value // note` is
#     `value`, `K = // disabled` and `K = //` are BOTH the empty string, and
#     `K = https://example.com/x` is `https:`. A lone `/` and `a/b` are values.
#   - quotes are literal characters, not delimiters: `K = "q"` is `"q"`
#   - the split is on the FIRST `=` only: `K = a=b` is `a=b`
#   - `KEY[sdk=iphoneos*]` conditional assignments are SDK-scoped. A text
#     parser cannot know the SDK, so they are IGNORED and the base assignment
#     wins — see "what this cannot see" below.
#   - `$(VAR)` expands from the resolved set, an undefined reference is empty,
#     and `$(inherited)` is empty in an xcconfig-only context
#   - `#include?` of a missing file is silent; a hard `#include` of a missing
#     file, and an include cycle, are NAMED errors
#
# Contract:
#
#   Xcconfig.value(path, key)  ->  String  the resolved value
#                                  ""      assigned, but empty or comment-only
#                                  nil     never assigned
#                                  raises  Xcconfig::MissingInclude
#
#   The ""-versus-nil distinction is load-bearing: "the key is there but Xcode
#   reads nothing" and "the key is not there" are different defects and get
#   different messages. Callers that only need a gate must treat BOTH as failure.
#
#   CLI: ruby bin/lib/xcconfig.rb <file> <KEY>
#
#   Exit | Meaning                                     | Message names
#   -----+---------------------------------------------+---------------------------
#   0    | resolved to a non-empty value               | — (prints the value)
#   2    | fewer than two arguments                    | the usage line
#   3    | the key is undefined, or resolves to empty  | the key and the file
#   1    | a hard `#include` miss, an include cycle, or | the include, or the path
#        | an unreadable path (Errno) — never silent    |
#
#   Exit 3 reuses bin/preflight-identity.rb's meaning ("a required value is
#   missing or empty") so a shell caller can treat the two the same way. Exit 2
#   is "no verdict", the tools/asc-probe.rb idiom: "the tool was called wrong"
#   can never be read as "the value was checked".
#
# WHAT THIS CANNOT SEE. It is a text parser, not a build. It cannot resolve
# `KEY[sdk=…]` — during the probe `PROBE_COND` was `base` for App-macOS and
# `ios-only` for `App-iOS -sdk iphoneos`, and nothing in the file says which
# build you meant, so the conditional line is skipped rather than guessed at.
# It cannot see a real build's `$(inherited)` chain, which reaches into the
# project and target levels above this file. And it does not know the build
# settings Xcode injects, so `$(SRCROOT)` and friends resolve to empty here.
# Anything that depends on those must go through `xcodebuild -showBuildSettings`
# (that is what tools/identity-parity.rb is for), not through this module.
#
# Ruby stdlib only, and specifically ZERO `require` lines — not even a stdlib
# one. fastlane/Appfile `load`s this file into fastlane's process, and
# bin/preflight-identity.rb (itself zero-require, so that the `review notes`
# required context can keep `bundler-cache: false`) `require_relative`s it.
# test/xcconfig_test.rb asserts the zero-require property so it cannot rot.
#
# `File.read(path, encoding: "UTF-8")` is mandatory and never `File.read(path)`:
# COPYRIGHT carries `©` (U+00A9), and with LANG unset Ruby defaults
# Encoding.default_external to US-ASCII and a non-ASCII byte raises out of a
# regex match. Commit 3b1efb9 is this repository's own instance of that
# defect (UL-012); the test drives the CLI with LC_ALL/LANG/LC_CTYPE cleared.
#
# Run the contract test under BOTH pinned interpreters:
#   /opt/homebrew/opt/ruby@3.3/bin/ruby test/xcconfig_test.rb
#   /opt/homebrew/opt/ruby@4.0/bin/ruby test/xcconfig_test.rb
#
# The `if $PROGRAM_NAME == __FILE__` tail at the bottom makes this file both a
# library and a command, so bash callers can shell out to it instead of growing
# a fourth reader. No other file in this repository uses that idiom (verified
# with `git grep` over `*.rb`, 2026-09-02); it is introduced here deliberately,
# because the alternative is a `bin/` wrapper whose only job is argv shuffling.

module Xcconfig
  # An assignment line. Group 2 is the optional `[sdk=…]` condition — it is
  # captured only so it can be recognised and skipped. The key charset excludes
  # `=`, which is what makes `K = a=b` split on the first `=`. Anchored at the
  # start of the line, which is why a `//` comment line containing an `=`
  # defines nothing.
  ASSIGN  = /\A[ \t]*([A-Za-z_][A-Za-z0-9_]*)([ \t]*\[[^\]]*\])?[ \t]*=(.*)\z/
  # `#include "X"` and `#include? "X"`. Group 1 is the `?` — present means the
  # include is optional, and a missing file is a no-op.
  INCLUDE = /\A[ \t]*#include(\?)?[ \t]+"([^"]+)"/

  # Raised for a hard `#include` of a file that is not there, and for an
  # include cycle. Both are conditions under which Xcode would not build; a
  # reader that returned an empty hash instead would be the silent-empty defect
  # this module exists to remove.
  MissingInclude = Class.new(StandardError)

  # The resolved raw assignments of `path`, `{ "KEY" => raw_string }`.
  #
  # Includes are inlined AT THEIR POSITION and merged over what came before, so
  # last-assignment-wins holds across the boundary in file order — observed:
  # `K = first` / `K = second` / `#include? "Inc"` (setting `from-include`)
  # resolves to `from-include`, and the same include placed first loses to a
  # later local assignment.
  #
  # `seen` is the include stack, used for the cycle guard (T-04-07). Paths are
  # absolute, and an include is resolved relative to the file that includes it —
  # never to the process CWD, which differs between XcodeGen's preGenCommand
  # (app/), fastlane (fastlane/) and CI (the repository root).
  def self.load(path, seen = [])
    path = File.expand_path(path)
    raise MissingInclude, "include cycle at #{path} (via #{seen.join(' -> ')})" if seen.include?(path)

    values = {}
    File.read(path, encoding: "UTF-8").each_line do |line|
      line = line.chomp

      if (m = INCLUDE.match(line))
        inc = File.expand_path(m[2], File.dirname(path))
        if File.file?(inc)
          values.merge!(load(inc, seen + [path]))
        elsif m[1].nil?
          raise MissingInclude, %(#{path}: #include "#{m[2]}" not found at #{inc})
        end
        next
      end

      # m[2] is the `[sdk=…]` condition; a conditional assignment is SDK-scoped
      # and this parser has no SDK, so it is skipped rather than guessed at.
      next unless (m = ASSIGN.match(line)) && m[2].nil?

      # The `//` cut happens HERE, before anything else sees the value, and it
      # is byte-identical in spirit to bin/preflight-identity.rb's
      # defines_non_empty? and test/identity_test.rb's xcconfig_value — the
      # three must agree on what "the value" is, which is the whole point of
      # there being one of them.
      values[m[1]] = m[3].sub(%r{//.*}, "").strip
    end
    values
  end

  # `$(VAR)` and `$(inherited)` expansion against an already-resolved set.
  #
  # A reference to a key that was never assigned expands to the empty string,
  # matching Xcode (`$(UNDEFINED_VAR)x` resolved to `x`). `$(inherited)` is
  # empty in an xcconfig-only context (`$(inherited) extra` resolved to
  # ` extra`, leading space kept — which is why the `strip` above happens
  # before expansion, not after).
  #
  # The depth guard is not decoration: `A = $(B)` / `B = $(A)` is a legal pair
  # of lines a forker can write, and without the guard this recurses until the
  # stack dies (T-04-08). Past depth 10 the raw string is returned unexpanded,
  # so the caller sees `$(...)` rather than a crash or a wrong value.
  def self.expand(values, raw, depth = 0)
    return raw if depth > 10

    raw.gsub(/\$\(([A-Za-z_][A-Za-z0-9_]*)\)/) do
      name = Regexp.last_match(1)
      name == "inherited" ? "" : expand(values, values.fetch(name, ""), depth + 1)
    end
  end

  # The resolved value of `key` in `path`, as Xcode would read it.
  # nil = never assigned. "" = assigned, but empty, comment-only, or resolving
  # through undefined references to nothing.
  def self.value(path, key)
    values = load(path)
    values.key?(key) ? expand(values, values[key]) : nil
  end
end

# CLI mode: ruby bin/lib/xcconfig.rb app/Identity.xcconfig BUNDLE_ID
#
# This is what bash consumers call instead of writing a fourth reader. It
# deliberately does NOT rescue MissingInclude: a broken include is an error
# with a name, and turning it into exit 3 would make it indistinguishable from
# "that key is empty".
if $PROGRAM_NAME == __FILE__
  if ARGV.length < 2
    warn "usage: ruby #{$PROGRAM_NAME} <xcconfig-file> <KEY>"
    exit 2
  end

  path, key = ARGV
  resolved = Xcconfig.value(path, key)
  if resolved.nil? || resolved.empty?
    warn "xcconfig: #{key} is #{resolved.nil? ? 'undefined' : 'empty'} in #{path}"
    exit 3
  end
  puts resolved
end
