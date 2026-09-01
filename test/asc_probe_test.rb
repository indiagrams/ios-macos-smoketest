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
@checks = 0

def assert_eq(actual, expected, label)
  @checks += 1
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

def app_body(bundle_id: IOS_ID, sku: "shipkitpipes-ios-001", locale: "en-US",
             name: "Shipkit Pipes", count: 1)
  {
    "data" => Array.new(count) do |i|
      {
        "type" => "apps",
        "id" => "APP#{i}",
        "attributes" => {
          "name" => name,
          "bundleId" => bundle_id,
          "sku" => sku,
          "primaryLocale" => locale,
          "contentRightsDeclaration" => nil
        }
      }
    end
  }
end

# An ASC error body, carrying a marker string. Cases assert the marker survives
# into stderr, which is what proves the *body* half of the [status, body] tuple
# reached the caller rather than only the status.
def error_body(marker, status: "403")
  {
    "errors" => [
      {
        "id" => "00000000-0000-0000-0000-000000000000",
        "status" => status,
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
  _out, err, code = probe("read-back", "bundle-id", "--identifier", IOS_ID,
                          "--expect-platform", "IOS", "--fixture", absent)
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
  f409 = write_fixture(dir, "conflict.json", error_body("marker-409-state-conflict", status: "409"), status: 409)

  _out, err403, code403 = probe("read-back", "bundle-id", "--identifier", IOS_ID,
                                "--expect-platform", "IOS", "--fixture", f403)
  _out, err409, code409 = probe("read-back", "bundle-id", "--identifier", IOS_ID,
                                "--expect-platform", "IOS", "--fixture", f409)

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
  out, err, code = probe("read-back", "bundle-id", "--identifier", IOS_ID,
                         "--expect-platform", "IOS", "--fixture", ok)
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
  out, err, code = probe("read-back", "bundle-id", "--identifier", IOS_ID,
                         "--expect-platform", "IOS", "--fixture", utf8, env: NO_LOCALE)
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
_out, err, code = probe("read-back", "bundle-id", "--identifier", IOS_ID, "--expect-platform", "IOS")
assert_eq code, 1, "credentials: a live call with no credentials exits 1"
assert_eq err.include?("ASC_API_KEY_ID"), true, "credentials: stderr names the missing variable"
assert_eq err.include?("KeyError"), false, "credentials: the failure is a message, not an opaque KeyError"

# ---------------------------------------------------------------------------
# read-back bundle-id — ACCT-01's instrument
# ---------------------------------------------------------------------------

# 15. The happy path, and the wrong-platform variant one argument away from it.
with_fixtures do |dir|
  ios   = write_fixture(dir, "bundleid-ios.json", bundle_id_body(platform: "IOS"))
  macos = write_fixture(dir, "bundleid-macos.json", bundle_id_body(platform: "MAC_OS"))

  _out, err, code = probe("read-back", "bundle-id", "--identifier", IOS_ID,
                          "--expect-platform", "IOS", "--fixture", ios)
  assert_eq code, 0, "bundle-id: a matching platform exits exactly 0 (stderr: #{err.strip})"

  # NEGATIVE CONTROL: the same call, same flags, against a record whose platform
  # is MAC_OS. If this exited 0 the platform assertion would never have run.
  _out, err, code = probe("read-back", "bundle-id", "--identifier", IOS_ID,
                          "--expect-platform", "IOS", "--fixture", macos)
  assert_eq code, 1, "bundle-id: expecting IOS against a MAC_OS record exits exactly 1"
  assert_eq err.include?("IOS"), true, "bundle-id: the mismatch report names the expected platform"
  assert_eq err.include?("MAC_OS"), true, "bundle-id: the mismatch report names the actual platform"

  # And the mirror image, so neither direction is passing by accident.
  _out, _err, code = probe("read-back", "bundle-id", "--identifier", IOS_ID,
                           "--expect-platform", "MAC_OS", "--fixture", ios)
  assert_eq code, 1, "bundle-id: expecting MAC_OS against an IOS record exits exactly 1"

  _out, _err, code = probe("read-back", "bundle-id", "--identifier", MACOS_ID,
                           "--expect-platform", "MAC_OS",
                           "--fixture", write_fixture(dir, "bundleid-macos-2.json",
                                                      bundle_id_body(identifier: MACOS_ID, platform: "MAC_OS")))
  assert_eq code, 0, "bundle-id: the macOS record with MAC_OS exits exactly 0"
end

# 16. THE VACUOUS-TRUTH GATE. An empty data array must exit 2, never 0.
#
# 02-RESEARCH.md states it directly: "a query that returns [] and an assertion
# that never executes is the classic vacuous-truth gate." A bogus identifier is
# the negative control ACCT-01 and ACCT-03 both name, and it is only a control
# if "nothing matched" is impossible to read as "everything checked out".
with_fixtures do |dir|
  empty = write_fixture(dir, "bundleid-empty.json", { "data" => [] })
  out, err, code = probe("read-back", "bundle-id", "--identifier", "com.indiagram.does-not-exist",
                         "--expect-platform", "IOS", "--fixture", empty)
  assert_eq code, 2, "bundle-id: an empty data array exits exactly 2, not 0 and not 1"
  assert_eq err.include?("not found"), true, "bundle-id: stderr says the identifier was not found"
  assert_eq err.include?("com.indiagram.does-not-exist"), true,
            "bundle-id: stderr names the filter that matched nothing"
  assert_eq out.strip.empty?, true, "bundle-id: a not-found result prints no success report"
end

# 17. Two matches is a failure, not a pick-the-first: an assertion applied to an
#     arbitrary member of an ambiguous result set proves nothing.
with_fixtures do |dir|
  two = write_fixture(dir, "bundleid-two.json", bundle_id_body(count: 2))
  _out, err, code = probe("read-back", "bundle-id", "--identifier", IOS_ID,
                          "--expect-platform", "IOS", "--fixture", two)
  assert_eq code, 1, "bundle-id: a filter matching two records exits exactly 1"
  assert_eq err.include?("2"), true, "bundle-id: the ambiguity report names the match count"
end

# 18. --expect-platform is validated against the closed BundleIdPlatform set
#     BEFORE any request. The fixture path below does not exist, so a probe that
#     validated after fetching would name the fixture instead of the platform.
with_fixtures do |dir|
  absent = File.join(dir, "never-created.json")
  _out, err, code = probe("read-back", "bundle-id", "--identifier", IOS_ID,
                          "--expect-platform", "BOGUS", "--fixture", absent)
  assert_eq code, 1, "bundle-id: an --expect-platform outside the closed set exits 1"
  assert_eq err.include?("BOGUS"), true, "bundle-id: stderr names the rejected platform"
  assert_eq err.include?(absent), false,
            "bundle-id: the platform is rejected BEFORE any request is made"

  # UNIVERSAL is in Apple's own API enum but is not exposed by spaceship, and
  # D-05 declined the Universal Purchase model it implies (C-02).
  _out, _err, code = probe("read-back", "bundle-id", "--identifier", IOS_ID,
                           "--expect-platform", "UNIVERSAL", "--fixture", absent)
  assert_eq code, 1, "bundle-id: UNIVERSAL is rejected — spaceship does not expose it (C-02)"
end

# 19. An identifier carrying path or query metacharacters is rejected before it
#     can be interpolated into a signed request path (T-02-07).
with_fixtures do |dir|
  absent = File.join(dir, "never-created.json")
  ["com.indiagram/evil", "com.indiagram?filter=x", "com.indiagram evil"].each do |bad|
    _out, err, code = probe("read-back", "bundle-id", "--identifier", bad,
                            "--expect-platform", "IOS", "--fixture", absent)
    assert_eq code, 1, "bundle-id: identifier #{bad.inspect} is rejected"
    assert_eq err.include?(absent), false,
              "bundle-id: identifier #{bad.inspect} is rejected BEFORE any request is made"
  end
end

# 20. --expect-platform is required, not optional: an omitted assertion is an
#     assertion that cannot fail.
_out, err, code = probe("read-back", "bundle-id", "--identifier", IOS_ID)
assert_eq code, 1, "bundle-id: omitting --expect-platform exits 1"
assert_eq err.include?("--expect-platform"), true, "bundle-id: stderr names the missing assertion flag"

# 21. Flags belonging to the other noun are rejected rather than silently ignored.
with_fixtures do |dir|
  ios = write_fixture(dir, "bundleid-ios.json", bundle_id_body)
  _out, err, code = probe("read-back", "bundle-id", "--identifier", IOS_ID,
                          "--expect-platform", "IOS", "--expect-sku", "x", "--fixture", ios)
  assert_eq code, 1, "bundle-id: --expect-sku is rejected, not ignored"
  assert_eq err.include?("--expect-sku"), true, "bundle-id: stderr names the inapplicable flag"
end

# ---------------------------------------------------------------------------
# read-back app — ACCT-03's instrument
# ---------------------------------------------------------------------------

# 22. The happy path. /v1/apps is get-only in ASC OpenAPI 4.4.1 (F-1/R-01), so
#     this subcommand reads state a human created and never writes any.
with_fixtures do |dir|
  ok = write_fixture(dir, "app-ok.json", app_body)
  out, err, code = probe("read-back", "app", "--bundle-id", IOS_ID,
                         "--expect-sku", "shipkitpipes-ios-001",
                         "--expect-locale", "en-US",
                         "--expect-name", "Shipkit Pipes",
                         "--fixture", ok)
  assert_eq code, 0, "app: matching sku, locale and name exits exactly 0 (stderr: #{err.strip})"

  parsed = out.strip.empty? ? {} : JSON.parse(out)
  assert_eq parsed["team"], "G5H628C6WR", "app: the report carries the team it was measured against (C-05)"
  assert_eq parsed["measured_at"].to_s.end_with?("Z"), true, "app: the report carries a UTC measured_at"
  assert_eq out.scan(/measured_at/).length, 1, "app: measured_at appears exactly once in the report"
  assert_eq parsed.dig("attributes", "sku"), "shipkitpipes-ios-001",
            "app: the full attribute set Apple returned is printed, not an echo of the flags"
  assert_eq parsed.dig("attributes", "primaryLocale"), "en-US",
            "app: primaryLocale is reported (D-32 set it explicitly rather than by default)"
end

# 23. NEGATIVE CONTROL for the SKU assertion — the one field that is genuinely
#     permanent per record (R-02). A wrong expectation must be caught, which is
#     what proves the assertion executes at all rather than being skipped.
with_fixtures do |dir|
  ok = write_fixture(dir, "app-ok.json", app_body)
  _out, err, code = probe("read-back", "app", "--bundle-id", IOS_ID,
                          "--expect-sku", "shipkitpipes-ios-999", "--fixture", ok)
  assert_eq code, 1, "app: a wrong --expect-sku exits exactly 1"
  assert_eq err.include?("shipkitpipes-ios-999"), true, "app: the report names the expected SKU"
  assert_eq err.include?("shipkitpipes-ios-001"), true, "app: the report names the actual SKU"
end

# 24. The same for locale and name, and for the bundleId the filter was built
#     from — a filter is not evidence that Apple stored what was asked for.
with_fixtures do |dir|
  wrong_locale = write_fixture(dir, "app-fr.json", app_body(locale: "fr-FR"))
  _out, err, code = probe("read-back", "app", "--bundle-id", IOS_ID,
                          "--expect-locale", "en-US", "--fixture", wrong_locale)
  assert_eq code, 1, "app: a wrong --expect-locale exits exactly 1"
  assert_eq err.include?("fr-FR"), true, "app: the locale report names the actual value"

  wrong_name = write_fixture(dir, "app-name.json", app_body(name: "Smoke App"))
  _out, err, code = probe("read-back", "app", "--bundle-id", IOS_ID,
                          "--expect-name", "Shipkit Pipes", "--fixture", wrong_name)
  assert_eq code, 1, "app: a wrong --expect-name exits exactly 1"
  assert_eq err.include?("Smoke App"), true, "app: the name report names the actual value"

  wrong_bundle = write_fixture(dir, "app-bundle.json", app_body(bundle_id: "com.indiagram.smokeapp"))
  _out, err, code = probe("read-back", "app", "--bundle-id", IOS_ID, "--fixture", wrong_bundle)
  assert_eq code, 1, "app: a record whose bundleId is not the one filtered for exits 1"
end

# 25. The vacuous-truth gate again, on the ACCT-03 path.
with_fixtures do |dir|
  empty = write_fixture(dir, "app-empty.json", { "data" => [] })
  out, err, code = probe("read-back", "app", "--bundle-id", "com.indiagram.does-not-exist",
                         "--expect-sku", "shipkitpipes-ios-001", "--fixture", empty)
  assert_eq code, 2, "app: an empty data array exits exactly 2, never 0"
  assert_eq err.include?("not found"), true, "app: stderr says the bundle id was not found"
  assert_eq out.strip.empty?, true, "app: a not-found result prints no success report"
end

# 26. Two matches on the app filter.
with_fixtures do |dir|
  two = write_fixture(dir, "app-two.json", app_body(count: 2))
  _out, err, code = probe("read-back", "app", "--bundle-id", IOS_ID,
                          "--expect-sku", "shipkitpipes-ios-001", "--fixture", two)
  assert_eq code, 1, "app: a filter matching two records exits exactly 1"
  assert_eq err.include?("2"), true, "app: the ambiguity report names the match count"
end

# 27. app-side argv validation.
with_fixtures do |dir|
  absent = File.join(dir, "never-created.json")
  _out, err, code = probe("read-back", "app", "--bundle-id", "com.indiagram/evil", "--fixture", absent)
  assert_eq code, 1, "app: a --bundle-id with a path metacharacter is rejected"
  assert_eq err.include?(absent), false, "app: the bundle id is rejected BEFORE any request is made"

  ok = write_fixture(dir, "app-ok.json", app_body)
  _out, err, code = probe("read-back", "app", "--bundle-id", IOS_ID,
                          "--expect-platform", "IOS", "--fixture", ok)
  assert_eq code, 1, "app: --expect-platform is rejected, not ignored"
  assert_eq err.include?("--expect-platform"), true, "app: stderr names the inapplicable flag"

  _out, err, code = probe("read-back", "app", "--fixture", ok)
  assert_eq code, 1, "app: omitting --bundle-id exits 1"
  assert_eq err.include?("--bundle-id"), true, "app: stderr names the missing required flag"
end

# 28. The request paths are percent-encoded, because filter[...] carries
#     brackets that must not reach the wire raw. Asserted against the source,
#     since the suite never issues a live request.
source = File.read(SCRIPT, encoding: "UTF-8")
assert_eq source.include?("filter%5Bidentifier%5D"), true,
          "source: the bundleIds filter percent-encodes its brackets"
assert_eq source.include?("filter%5BbundleId%5D"), true,
          "source: the apps filter percent-encodes its brackets"
assert_eq source.include?("return nil unless"), false,
          "source: the transport never collapses a response to nil"
assert_eq source.scan(/^\s+rescue StandardError/).empty?, true,
          "source: there is no broad rescue in the probe"

if @failures.zero?
  puts "\nAll #{@checks} asc-probe regression assertions passed."
  exit 0
else
  puts "\n#{@failures} of #{@checks} asc-probe assertion(s) failed."
  exit 1
end
