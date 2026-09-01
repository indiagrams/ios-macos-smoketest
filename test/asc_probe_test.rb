#!/usr/bin/env ruby
# frozen_string_literal: true

# Regression test for tools/asc-probe.rb.
#
# Why this exists: every Phase 2 claim about what Apple actually stored has to
# be evidenced by an observed response, and tools/asc-probe.rb is the instrument
# that produces those observations. An instrument nobody has calibrated is worse
# than no instrument, because it converts "we did not look" into "the probe says
# we are fine." This project's dominant defect is a check that structurally
# cannot fail -- six instances so far, one of them inside this phase's own
# validation document -- so every assertion below has a fixture that makes it go
# red.
#
# The load-bearing case is status-code preservation. bin/lib/bootstrap.rb:951-962
# ends its ASC helper by collapsing every non-2xx response to nil, which is
# correct for the warn-only doctor check it was written for and fatal here: the
# ACCT-04 submission probe exists precisely to discriminate 403 (insufficient
# role) from 409/422 (sufficient role, build-less record). Cases 10 and 11 pin
# that discrimination in both directions -- a collapse-to-nil transport makes
# them indistinguishable, which is exactly what the negative control confirmed.
#
# Design constraint: this suite must NOT reach App Store Connect. Every case
# that needs a response passes --fixture and reads a saved envelope from a
# throwaway Dir.mktmpdir tree; the one case that deliberately omits --fixture
# asserts that the probe dies on missing credentials *before* opening a socket.
# probe() merges a base environment that clears ASC_API_KEY_ID,
# ASC_API_KEY_ISSUER_ID, ASC_API_KEY_P8_BASE64, ASC_API_KEY_P8_PATH and
# FASTLANE_TEAM_ID to nil, so no case can accidentally authenticate with a
# developer's real exported credentials and touch live Apple state.
#
# Runnable locally, with no bundle and no credentials:
#   ruby test/asc_probe_test.rb
#
# No gem, no framework, no rake task -- matching test/gen_review_notes_test.rb
# and test/parser_test.rb.

require "open3"
require "tmpdir"
require "fileutils"
require "json"
require "rbconfig"

SCRIPT = File.expand_path("../tools/asc-probe.rb", __dir__)

IOS_ID   = "com.indiagram.shipkitpipes.ios"
MACOS_ID = "com.indiagram.shipkitpipes.macos"

# Cleared for every invocation. A suite that inherited these could mint a real
# JWT and reach Apple; the credential clearing is what makes "offline" a
# mechanism rather than a convention.
CREDENTIAL_VARS = %w[
  ASC_API_KEY_ID
  ASC_API_KEY_ISSUER_ID
  ASC_API_KEY_P8_BASE64
  ASC_API_KEY_P8_PATH
  FASTLANE_TEAM_ID
].freeze

# Clearing the locale is what makes the encoding cases regression tests rather
# than restatements of the fix: with LANG unset Ruby sets
# Encoding.default_external to US-ASCII, and a bare File.read then produces a
# string whose bytes cannot be parsed as JSON. UL-012 is the live instance --
# Phase 1 shipped exactly this bug in tools/gen-review-notes.rb (PR #2).
NO_LOCALE = { "LC_ALL" => nil, "LANG" => nil, "LC_CTYPE" => nil }.freeze

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

# Runs the probe as a subprocess with credentials explicitly cleared.
def probe(*args, env: {})
  base = {}
  CREDENTIAL_VARS.each { |name| base[name] = nil }
  stdout, stderr, status = Open3.capture3(base.merge(env), RbConfig.ruby, SCRIPT, *args)
  [stdout, stderr, status.exitstatus]
end

def with_fixtures
  Dir.mktmpdir("asc-probe-test") { |dir| yield dir }
end

# Writes the on-disk response envelope the probe's --fixture path consumes:
# an explicit HTTP status alongside the body, so a case can exercise a 403 or a
# 409 without a network. Parameterised so the failing variant of any case is one
# argument away rather than a copy-pasted second fixture.
def write_fixture(dir, name, body, status: 200)
  path = File.join(dir, name)
  File.write(path, JSON.pretty_generate("status" => status, "body" => body), encoding: "UTF-8")
  path
end

def bundle_id_body(identifier: IOS_ID, platform: "IOS", name: "Shipkit Pipes", count: 1)
  {
    "data" => Array.new(count) do |i|
      {
        "type" => "bundleIds",
        "id" => "BUNDLEID#{i}",
        "attributes" => {
          "identifier" => identifier,
          "name" => name,
          "platform" => platform,
          "seedId" => "G5H628C6WR"
        }
      }
    end
  }
end

# An ASC error body, carrying a marker string. Cases assert the marker survives
# into stderr, which is what proves the *body* half of the [status, body] tuple
# reached the caller rather than only the status.
def error_body(marker)
  {
    "errors" => [
      {
        "id" => "00000000-0000-0000-0000-000000000000",
        "status" => "403",
        "code" => "FORBIDDEN_ERROR",
        "title" => marker,
        "detail" => "Provided user is not authorized to perform this operation."
      }
    ]
  }
end

puts "asc-probe regression tests:"

# 1. No argv at all. A tool invoked with nothing must say what it wants.
_out, err, code = probe
assert_eq code, 1, "argv: no subcommand exits 1"
assert_eq err.include?("usage:"), true, "argv: no subcommand prints the usage block to stderr"

# 2. Unknown subcommand is rejected loudly, not ignored.
_out, err, code = probe("frobnicate")
assert_eq code, 1, "argv: an unknown subcommand exits 1"
assert_eq err.include?("asc-probe: "), true, "argv: stderr carries the tool-name prefix"
assert_eq err.include?('unknown subcommand "frobnicate"'), true,
          "argv: stderr names the rejected subcommand verbatim"

# 3. read-back with no noun.
_out, err, code = probe("read-back")
assert_eq code, 1, "argv: read-back with no noun exits 1"
assert_eq err.include?("read-back"), true, "argv: stderr names the subcommand that needs a noun"

# 4. Unknown read-back noun.
_out, err, code = probe("read-back", "frobnicate")
assert_eq code, 1, "argv: an unknown read-back noun exits 1"
assert_eq err.include?('unknown read-back noun "frobnicate"'), true,
          "argv: stderr names the rejected noun verbatim"

# 5. Help is a success, and advertises the surface the rest of the phase calls.
out, _err, code = probe("--help")
assert_eq code, 0, "--help: exits 0"
assert_eq out.include?("read-back"), true, "--help: stdout documents the read-back subcommand"
out, _err, code = probe("-h")
assert_eq code, 0, "-h: exits 0"
assert_eq out.include?("read-back"), true, "-h: stdout documents the read-back subcommand"

# 6. Unknown flags are rejected rather than ignored: a typo'd flag must not look
#    like a successful run.
_out, err, code = probe("read-back", "bundle-id", "--nonsense", "x")
assert_eq code, 1, "argv: an unrecognised flag exits 1"
assert_eq err.include?('unknown argument "--nonsense"'), true,
          "argv: stderr names the rejected flag verbatim"

# 7. A flag with no value is a usage error naming the flag, not a nil that
#    silently becomes a query for the empty string.
_out, err, code = probe("read-back", "bundle-id", "--identifier")
assert_eq code, 1, "argv: --identifier with no value exits 1"
assert_eq err.include?("--identifier"), true, "argv: stderr names the flag that is missing its value"

_out, err, code = probe("read-back", "bundle-id", "--identifier", IOS_ID, "--fixture")
assert_eq code, 1, "argv: --fixture with no value exits 1"
assert_eq err.include?("--fixture"), true, "argv: stderr names --fixture as the flag missing its value"

# 8. A required flag that was never supplied.
_out, err, code = probe("read-back", "bundle-id")
assert_eq code, 1, "argv: read-back bundle-id without --identifier exits 1"
assert_eq err.include?("--identifier"), true, "argv: stderr names the missing required flag"

# 9. A --fixture path that does not exist fails loudly rather than being read as
#    an empty response (which would look like "not found").
with_fixtures do |dir|
  absent = File.join(dir, "does-not-exist.json")
  _out, err, code = probe("read-back", "bundle-id", "--identifier", IOS_ID, "--fixture", absent)
  assert_eq code, 1, "--fixture: a missing fixture file exits 1"
  assert_eq err.include?(absent), true, "--fixture: stderr names the path that could not be read"
end

# 10/11. THE LOAD-BEARING PAIR. asc_request must surface the status verbatim.
#
# 403 means the key's role is insufficient. 409/422 mean the role is sufficient
# and the *record* was not in a submittable state -- which is a PASS for ACCT-04.
# A transport that collapses every non-2xx to nil answers both the same way, so
# the probe would report identically whether or not the key is sufficient. These
# two cases are the only thing standing between this phase and that failure.
with_fixtures do |dir|
  f403 = write_fixture(dir, "forbidden.json", error_body("marker-403-insufficient-role"), status: 403)
  f409 = write_fixture(dir, "conflict.json", error_body("marker-409-state-conflict"), status: 409)

  _out, err403, code403 = probe("read-back", "bundle-id", "--identifier", IOS_ID, "--fixture", f403)
  _out, err409, code409 = probe("read-back", "bundle-id", "--identifier", IOS_ID, "--fixture", f409)

  assert_eq code403, 1, "transport: a 403 response exits 1"
  assert_eq err403.include?("403"), true, "transport: a 403 is reported verbatim as 403"
  assert_eq err403.include?("marker-403-insufficient-role"), true,
            "transport: the response body reaches the caller alongside the status"

  assert_eq code409, 1, "transport: a 409 response exits 1"
  assert_eq err409.include?("409"), true, "transport: a 409 is reported verbatim as 409"
  assert_eq err409.include?("marker-409-state-conflict"), true,
            "transport: the 409 response body reaches the caller alongside the status"

  # The discrimination itself. This is the assertion that goes red the moment
  # the transport starts collapsing non-2xx responses.
  assert_eq err403.include?("409"), false, "transport: the 403 report does not mention 409"
  assert_eq err409.include?("403"), false, "transport: the 409 report does not mention 403"
  assert_eq err403 == err409, false, "transport: 403 and 409 produce distinguishable reports"
end

# 12. A 2xx response is parsed and reported.
with_fixtures do |dir|
  ok = write_fixture(dir, "ok.json", bundle_id_body)
  out, err, code = probe("read-back", "bundle-id", "--identifier", IOS_ID, "--fixture", ok)
  assert_eq code, 0, "read-back: a 200 response with one matching record exits 0 (stderr: #{err.strip})"
  parsed = out.strip.empty? ? {} : JSON.parse(out)
  assert_eq parsed["attributes"].is_a?(Hash) && parsed["attributes"]["platform"], "IOS",
            "read-back: stdout reports the attributes App Store Connect actually returned"
end

# 13. ENCODING. A real non-ASCII byte in the response, read under a cleared
#     locale.
#
#     The fixture below MUST contain real non-ASCII bytes. test/gen_review_notes_test.rb:237-240
#     records the earlier draft that used the transliterations "Jose Mueller" --
#     pure ASCII, so the case passed against the unfixed generator and asserted
#     nothing. An ASC app name with a diacritic is reachable input, not exotic.
with_fixtures do |dir|
  utf8 = write_fixture(dir, "utf8.json", bundle_id_body(name: "Shipkit Pipes — Café Müller"))
  out, err, code = probe("read-back", "bundle-id", "--identifier", IOS_ID, "--fixture", utf8, env: NO_LOCALE)
  assert_eq code, 0, "encoding: a non-ASCII response is read under a cleared locale (stderr: #{err.strip})"
  assert_eq out.include?("Café Müller"), true, "encoding: the non-ASCII bytes survive to stdout intact"
  assert_eq err.include?("Error"), false, "encoding: the probe exits with a verdict, never a stack trace"
end

# 14. Credentials. Without --fixture the probe needs a real token, and with the
#     environment cleared it must die naming the missing variable BEFORE opening
#     a socket -- Pitfall 7: fastlane/Fastfile:108 does
#     ENV.fetch("ASC_API_KEY_P8_BASE64") while .bootstrap.env supplies only
#     ASC_API_KEY_P8_PATH, and the resulting KeyError names nothing useful.
#     This case is also what keeps the suite offline on the one path that has no
#     fixture.
_out, err, code = probe("read-back", "bundle-id", "--identifier", IOS_ID)
assert_eq code, 1, "credentials: a live call with no credentials exits 1"
assert_eq err.include?("ASC_API_KEY_ID"), true, "credentials: stderr names the missing variable"
assert_eq err.include?("KeyError"), false, "credentials: the failure is a message, not an opaque KeyError"

if @failures.zero?
  puts "\nAll asc-probe regression tests passed."
  exit 0
else
  puts "\n#{@failures} test(s) failed."
  exit 1
end
