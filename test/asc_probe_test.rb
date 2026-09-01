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
require "time"

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

# ---------------------------------------------------------------------------
# census — ACCT-05's instrument
# ---------------------------------------------------------------------------

# The closed set of certificate types the release lane mints (C-06,
# .github/workflows/release.yml:7, .github/workflows/canary-local-mode.yml:24).
# Deliberately duplicated here rather than read back out of the census the probe
# produced, exactly as test/docs_structure_test.rb:63-67 duplicates the verdict
# vocabulary: a test that derived its vocabulary from the artifact under test
# would accept whatever that artifact happened to say, which is not a test.
RELEASE_CERT_TYPES = %w[DISTRIBUTION DEVELOPMENT MAC_INSTALLER_DISTRIBUTION].freeze

# The exact fields ACCT-05 records, per fastlane/Fastfile:862-870 (list_certs)
# and ASC OpenAPI 4.4.1 components.schemas.Certificate. Also duplicated rather
# than derived.
CENSUS_ENTRY_KEYS = %w[id display_name expiration_date].freeze

# An ASC /v1/certificates response body, built from [id, type, display, expiry]
# tuples so a fixture's contents are readable at the call site.
#
# certificateContent is present in every entry ON PURPOSE. Apple returns it, so
# a fixture without it could not tell "the census drops the certificate payload"
# apart from "the census never had one to drop" — the same self-invalidating
# shape as an ASCII fixture for an encoding test (gen_review_notes_test.rb:237-240).
def certificates_body(entries)
  {
    "data" => entries.map do |id, type, display_name, expiration|
      {
        "type" => "certificates",
        "id" => id,
        "attributes" => {
          "certificateType" => type,
          "displayName" => display_name,
          "expirationDate" => expiration,
          "serialNumber" => "SERIAL-#{id}",
          "platform" => "IOS",
          "certificateContent" => "MIIFtSECRETCERTIFICATEPAYLOADzzz",
          "activated" => true
        }
      }
    end
  }
end

# Two DISTRIBUTION and one DEVELOPMENT, so the grouping assertion has two
# distinct counts to get wrong.
#
# Display names are organization strings and Apple's own "Created via API"
# literal, never an individual's name. This fixture carried a real person's
# given name from 2026-09-01 until the Phase 2 close-out found it: certificate
# displayName is a field Apple populates from whoever generated the certificate,
# so copying a live census into a fixture copies a name in with it. The
# fork-owned-document sweep in test/docs_structure_test.rb did not catch it
# because that sweep covers documents, and this is a test file.
CERT_ENTRIES = [
  ["CERTDIST1", "DISTRIBUTION", "Apple Distribution: Indiagram", "2027-05-01T12:00:00.000+0000"],
  ["CERTDIST2", "DISTRIBUTION", "Apple Distribution: Indiagram (2)", "2027-06-01T12:00:00.000+0000"],
  ["CERTDEV1",  "DEVELOPMENT",  "Created via API", "2027-07-01T12:00:00.000+0000"]
].freeze

# A census document built INDEPENDENTLY of the probe, so the diff cases are not
# testing the census writer and the diff reader against each other's bugs.
def census_doc(entries, team: "G5H628C6WR", measured_at: "2026-09-01T10:00:00Z")
  census = {}
  RELEASE_CERT_TYPES.each { |type| census[type] = [] }
  entries.each do |id, type, display_name, expiration|
    (census[type] ||= []) << {
      "id" => id, "display_name" => display_name, "expiration_date" => expiration
    }
  end
  doc = { "census" => census }
  doc["team"] = team unless team.nil?
  doc["measured_at"] = measured_at unless measured_at.nil?
  doc
end

def write_json(dir, name, doc)
  path = File.join(dir, name)
  File.write(path, JSON.pretty_generate(doc), encoding: "UTF-8")
  path
end

# Every id in a census document, whatever type it sits under.
def census_ids(doc)
  doc.fetch("census", {}).values.flatten.map { |entry| entry["id"] }
end

# 29. The envelope. Its three top-level keys are the contract docs/APPLE-ACCOUNT-STATE.md
#     is summarised from, so they are asserted exactly rather than by inclusion.
with_fixtures do |dir|
  certs = write_fixture(dir, "certs.json", certificates_body(CERT_ENTRIES))
  out_path = File.join(dir, "census.json")
  out, err, code = probe("census", "--fixture", certs, "--out", out_path)
  assert_eq code, 0, "census: a 200 certificates response exits 0 (stderr: #{err.strip})"
  assert_eq File.file?(out_path), true, "census: --out writes the file it was given"

  doc = File.file?(out_path) ? JSON.parse(File.read(out_path, encoding: "UTF-8")) : {}
  assert_eq doc.keys.sort, %w[census measured_at team],
            "census: the envelope's top-level keys are exactly team, measured_at, census"
  assert_eq doc["team"], "G5H628C6WR",
            "census: the census carries the team it was measured against (C-05)"

  parsed_time = begin
    Time.iso8601(doc["measured_at"].to_s)
  rescue StandardError
    nil
  end
  assert_eq parsed_time.nil?, false, "census: measured_at parses as ISO-8601"
  assert_eq doc["measured_at"].to_s.end_with?("Z"), true, "census: measured_at is UTC"
  assert_eq out.strip.empty?, false, "census: --out still reports where it wrote to"
end

# 30. Grouping by certificate type, and the three release types present even when
#     one of them is empty — an absent type is invisible; a zero is a measurement.
with_fixtures do |dir|
  certs = write_fixture(dir, "certs.json", certificates_body(CERT_ENTRIES))
  out_path = File.join(dir, "census.json")
  _out, _err, code = probe("census", "--fixture", certs, "--out", out_path)
  assert_eq code, 0, "census: grouping run exits 0"
  doc = File.file?(out_path) ? JSON.parse(File.read(out_path, encoding: "UTF-8")) : {}
  census = doc["census"] || {}

  assert_eq census["DISTRIBUTION"].is_a?(Array) && census["DISTRIBUTION"].length, 2,
            "census: two DISTRIBUTION certificates are grouped under DISTRIBUTION"
  assert_eq census["DEVELOPMENT"].is_a?(Array) && census["DEVELOPMENT"].length, 1,
            "census: one DEVELOPMENT certificate is grouped under DEVELOPMENT"
  RELEASE_CERT_TYPES.each do |type|
    assert_eq census.key?(type), true,
              "census: #{type} is present as a key even with zero entries"
  end
  assert_eq census["MAC_INSTALLER_DISTRIBUTION"], [],
            "census: a type the team has none of reads as an explicit empty list"
end

# 31. What a census entry may and may not contain. certificateContent is the
#     certificate payload and this file is summarised into a tracked document
#     (T-02-14); createdDate does not exist on Certificate at all (C-E), and
#     inventing one is how R-04's false "revokes the oldest by creation date"
#     claim survived in the repo.
with_fixtures do |dir|
  certs = write_fixture(dir, "certs.json", certificates_body(CERT_ENTRIES))
  out_path = File.join(dir, "census.json")
  probe("census", "--fixture", certs, "--out", out_path)
  raw = File.file?(out_path) ? File.read(out_path, encoding: "UTF-8") : ""
  doc = raw.empty? ? {} : JSON.parse(raw)
  entry = (doc.dig("census", "DISTRIBUTION") || [{}]).first || {}

  assert_eq entry.keys.sort, CENSUS_ENTRY_KEYS.sort,
            "census: an entry carries exactly id, display_name and expiration_date"
  assert_eq entry["id"], "CERTDIST1", "census: the certificate id is recorded verbatim"
  assert_eq entry["display_name"], "Apple Distribution: Indiagram",
            "census: the display name is recorded verbatim"
  assert_eq entry["expiration_date"], "2027-05-01T12:00:00.000+0000",
            "census: the expiration date is recorded verbatim (the only ordering proxy, C-E)"
  assert_eq raw.include?("SECRETCERTIFICATEPAYLOAD"), false,
            "census: the certificate payload never reaches the census file (T-02-14)"
  assert_eq raw.downcase.include?("createddate") || raw.include?("created_date"), false,
            "census: no created date is invented — Certificate has none (C-E)"
  assert_eq raw.include?("serialNumber") || raw.include?("serial_number"), false,
            "census: fields ACCT-05 does not need are not carried along"
end

# 32. A certificate type outside the release lane's three is still reported.
#     Reporting only the closed set would hide occupancy that competes for the
#     same team, which is the measurement ACCT-05 exists to produce.
with_fixtures do |dir|
  extra = CERT_ENTRIES + [["CERTDEVID1", "DEVELOPER_ID_APPLICATION", "Developer ID Application: Indiagram",
                           "2028-01-01T12:00:00.000+0000"]]
  certs = write_fixture(dir, "certs-extra.json", certificates_body(extra))
  out_path = File.join(dir, "census.json")
  _out, _err, code = probe("census", "--fixture", certs, "--out", out_path)
  assert_eq code, 0, "census: an unlisted certificate type does not fail the run"
  doc = File.file?(out_path) ? JSON.parse(File.read(out_path, encoding: "UTF-8")) : {}
  assert_eq (doc["census"] || {}).key?("DEVELOPER_ID_APPLICATION"), true,
            "census: a type outside the release set is reported, not dropped"
end

# 33. Without --out the envelope goes to stdout, so the census composes with a pipe.
with_fixtures do |dir|
  certs = write_fixture(dir, "certs.json", certificates_body(CERT_ENTRIES))
  out, _err, code = probe("census", "--fixture", certs)
  assert_eq code, 0, "census: no --out exits 0"
  doc = out.strip.empty? ? {} : JSON.parse(out)
  assert_eq doc.keys.sort, %w[census measured_at team],
            "census: stdout carries the same three-key envelope"
end

# 34. Zero certificates is a measurement, not a failure — occupancy 0 is exactly
#     what ACCT-05 may need to record. It must still be a full envelope.
with_fixtures do |dir|
  certs = write_fixture(dir, "certs-empty.json", { "data" => [] })
  out, _err, code = probe("census", "--fixture", certs)
  assert_eq code, 0, "census: an empty certificate list exits 0 — zero occupancy is a measurement"
  doc = out.strip.empty? ? {} : JSON.parse(out)
  RELEASE_CERT_TYPES.each do |type|
    assert_eq (doc["census"] || {})[type], [],
              "census: #{type} reads as an explicit empty list when the team has none"
  end
end

# 35. A non-2xx is reported verbatim rather than written out as an empty census.
#     A census file created from a 403 would be a fabricated measurement.
with_fixtures do |dir|
  denied = write_fixture(dir, "certs-403.json", error_body("marker-census-forbidden"), status: 403)
  out_path = File.join(dir, "census.json")
  _out, err, code = probe("census", "--fixture", denied, "--out", out_path)
  assert_eq code, 1, "census: a 403 exits 1"
  assert_eq err.include?("403"), true, "census: the 403 is reported verbatim"
  assert_eq File.file?(out_path), false, "census: no census file is written from a failed measurement"
end

# 36. The offline guarantee on the one path that has no fixture.
_out, err, code = probe("census")
assert_eq code, 1, "census: a live census with no credentials exits 1"
assert_eq err.include?("ASC_API_KEY_ID"), true, "census: stderr names the missing credential"

# 37. A display name with a diacritic, read under a cleared locale (UL-012).
with_fixtures do |dir|
  named = write_fixture(dir, "certs-utf8.json",
                        certificates_body([["CERT1", "DISTRIBUTION", "Apple Distribution: Café Müller",
                                            "2027-05-01T12:00:00.000+0000"]]))
  out, err, code = probe("census", "--fixture", named, env: NO_LOCALE)
  assert_eq code, 0, "census: a non-ASCII display name is read under a cleared locale (stderr: #{err.strip})"
  assert_eq out.include?("Café Müller"), true, "census: the non-ASCII display name survives intact"
end

# ---------------------------------------------------------------------------
# census-diff — ACCT-05b's "nothing was revoked" proof
# ---------------------------------------------------------------------------

# 38. Two identical censuses. Nothing disappeared, so exit 0.
with_fixtures do |dir|
  before = write_json(dir, "before.json", census_doc(CERT_ENTRIES))
  after  = write_json(dir, "after.json", census_doc(CERT_ENTRIES, measured_at: "2026-09-01T11:00:00Z"))
  _out, err, code = probe("census-diff", "--before", before, "--after", after)
  assert_eq code, 0, "census-diff: an unchanged id set exits 0 (stderr: #{err.strip})"
end

# 39. The set grew. A mint that CREATED is the ACCT-04b evidence (VALIDATION.md's
#     correction note), so an addition must be reported and must not be a failure.
with_fixtures do |dir|
  grown = CERT_ENTRIES + [["CERTDIST3", "DISTRIBUTION", "Apple Distribution: Indiagram (3)",
                           "2027-08-01T12:00:00.000+0000"]]
  before = write_json(dir, "before.json", census_doc(CERT_ENTRIES))
  after  = write_json(dir, "after.json", census_doc(grown))
  out, err, code = probe("census-diff", "--before", before, "--after", after)
  assert_eq code, 0, "census-diff: an id set that grew exits 0"
  assert_eq (out + err).include?("CERTDIST3"), true,
            "census-diff: the added id is reported — it is ACCT-04b's CREATED evidence"
end

# 40. THE REMOVAL CASE. ACCT-05b's whole point, and the case 02-VALIDATION.md
#     requires be proven with a SYNTHETIC fixture: nothing is ever revoked to
#     test this (D-39).
#
#     The fixture sanity assertion below is not ceremony. 02-PATTERNS.md names
#     this exact hazard: "a census-diff fixture whose 'removed id' is not
#     actually present in the *before* set asserts nothing" — the Phase 2
#     analogue of gen_review_notes_test.rb:237-240's ASCII fixture that passed
#     against the unfixed generator. So the before file is asserted to contain
#     the id whose absence the case is about.
with_fixtures do |dir|
  removed_id = "CERTDIST2"
  before_doc = census_doc(CERT_ENTRIES)
  after_doc  = census_doc(CERT_ENTRIES.reject { |entry| entry[0] == removed_id })

  assert_eq census_ids(before_doc).include?(removed_id), true,
            "census-diff fixture: the removed id IS present in the before census"
  assert_eq census_ids(after_doc).include?(removed_id), false,
            "census-diff fixture: the removed id is absent from the after census"

  before = write_json(dir, "before.json", before_doc)
  after  = write_json(dir, "after.json", after_doc)
  _out, err, code = probe("census-diff", "--before", before, "--after", after)
  assert_eq code, 1, "census-diff: an id present in before and absent from after exits exactly 1"
  assert_eq err.include?(removed_id), true, "census-diff: stderr names the removed certificate id"
  assert_eq err.include?("DISTRIBUTION"), true, "census-diff: stderr names the removed certificate's type"
  assert_eq err.include?("Apple Distribution: Indiagram (2)"), true,
            "census-diff: stderr names the removed certificate's display name"

  # The mirror direction: the same two files swapped is an addition, not a
  # removal. A diff that flagged both directions would be a permanently red
  # gate rather than a detector.
  _out, _err, code = probe("census-diff", "--before", after, "--after", before)
  assert_eq code, 0, "census-diff: the same pair reversed is an addition and exits 0"
end

# 41. WRONG TEAM. A census that does not carry THIS team's id is the C-05 failure
#     repeating — release.yml:35 carries caps measured against A1B2C3D4E5 and
#     nothing in the file says so. Diffing it silently would launder that mistake.
with_fixtures do |dir|
  good = write_json(dir, "good.json", census_doc(CERT_ENTRIES))
  foreign = write_json(dir, "foreign.json", census_doc(CERT_ENTRIES, team: "A1B2C3D4E5"))

  _out, err, code = probe("census-diff", "--before", foreign, "--after", good)
  assert_eq code, 2, "census-diff: a before census from team A1B2C3D4E5 exits exactly 2"
  assert_eq err.include?("A1B2C3D4E5"), true, "census-diff: stderr names the foreign team it found"
  assert_eq err.include?("G5H628C6WR"), true, "census-diff: stderr names the team it required"

  _out, _err, code = probe("census-diff", "--before", good, "--after", foreign)
  assert_eq code, 2, "census-diff: an after census from the wrong team exits exactly 2"

  no_team = write_json(dir, "no-team.json", census_doc(CERT_ENTRIES, team: nil))
  _out, err, code = probe("census-diff", "--before", no_team, "--after", good)
  assert_eq code, 2, "census-diff: a census with no team key at all exits exactly 2"
  assert_eq err.include?("team"), true, "census-diff: stderr says the team is missing"
end

# 42. NO DATE. An undated measurement cannot self-invalidate, which is the whole
#     point of the dated-triple discipline in 02-VALIDATION.md.
with_fixtures do |dir|
  good = write_json(dir, "good.json", census_doc(CERT_ENTRIES))
  undated = write_json(dir, "undated.json", census_doc(CERT_ENTRIES, measured_at: nil))

  _out, err, code = probe("census-diff", "--before", undated, "--after", good)
  assert_eq code, 2, "census-diff: a census with no measured_at exits exactly 2"
  assert_eq err.include?("measured_at"), true, "census-diff: stderr names the missing key"

  _out, _err, code = probe("census-diff", "--before", good, "--after", undated)
  assert_eq code, 2, "census-diff: an undated after census exits exactly 2"

  no_census = write_json(dir, "no-census.json",
                         { "team" => "G5H628C6WR", "measured_at" => "2026-09-01T10:00:00Z" })
  _out, _err, code = probe("census-diff", "--before", no_census, "--after", good)
  assert_eq code, 2, "census-diff: a document with no census key exits exactly 2"
end

# 43. Argv. A diff missing half its input is a usage error, not an empty diff
#     that trivially passes.
with_fixtures do |dir|
  good = write_json(dir, "good.json", census_doc(CERT_ENTRIES))

  _out, err, code = probe("census-diff", "--before", good)
  assert_eq code, 1, "census-diff: omitting --after exits 1"
  assert_eq err.include?("--after"), true, "census-diff: stderr names the missing flag"

  _out, err, code = probe("census-diff", "--after", good)
  assert_eq code, 1, "census-diff: omitting --before exits 1"
  assert_eq err.include?("--before"), true, "census-diff: stderr names the missing flag"

  absent = File.join(dir, "nope.json")
  _out, err, code = probe("census-diff", "--before", absent, "--after", good)
  assert_eq code, 1, "census-diff: a census file that does not exist exits 1"
  assert_eq err.include?(absent), true, "census-diff: stderr names the unreadable path"

  garbage = File.join(dir, "garbage.json")
  File.write(garbage, "not json at all", encoding: "UTF-8")
  _out, _err, code = probe("census-diff", "--before", garbage, "--after", good)
  assert_eq code, 1, "census-diff: a census file that is not JSON exits 1"
end

# 44. ROUND TRIP. The diff must consume what the census actually writes, not only
#     the hand-built document the cases above use.
with_fixtures do |dir|
  certs = write_fixture(dir, "certs.json", certificates_body(CERT_ENTRIES))
  fewer = write_fixture(dir, "certs-fewer.json",
                        certificates_body(CERT_ENTRIES.reject { |entry| entry[0] == "CERTDEV1" }))
  before = File.join(dir, "census-before.json")
  after  = File.join(dir, "census-after.json")
  same   = File.join(dir, "census-same.json")

  probe("census", "--fixture", certs, "--out", before)
  probe("census", "--fixture", certs, "--out", same)
  probe("census", "--fixture", fewer, "--out", after)

  _out, _err, code = probe("census-diff", "--before", before, "--after", same)
  assert_eq code, 0, "census-diff: two censuses the probe itself wrote diff clean"

  _out, err, code = probe("census-diff", "--before", before, "--after", after)
  assert_eq code, 1, "census-diff: a certificate missing from a probe-written census exits 1"
  assert_eq err.include?("CERTDEV1"), true, "census-diff: the removed id from the round trip is named"
end

# 45. Source assertions for the certificate half. Asserted against the source
#     because the guarantee is the ABSENCE of a code path, which no fixture can
#     demonstrate: there is no input that makes a revocation that does not exist
#     happen (T-02-13, D-39, C-G).
census_source = File.read(SCRIPT, encoding: "UTF-8")
code_lines = census_source.lines.reject { |line| line.start_with?("#") }.join
assert_eq code_lines.include?("delete_certificate"), false,
          "source: no revocation code path exists in the probe (D-39, T-02-13)"
assert_eq code_lines.match?(/\bcap\b *= *[0-9]|maximum *= *[0-9]/), false,
          "source: no numeric certificate quota is encoded (C-A, Pitfall 4)"
assert_eq code_lines.downcase.include?("createddate") || code_lines.include?("created_date"), false,
          "source: no created date is referenced — Certificate has none (C-E)"
assert_eq code_lines.include?("certificate_content") || code_lines.include?("certificateContent"), false,
          "source: the certificate payload is never read into the census (T-02-14)"
assert_eq census_source.include?("Spaceship::ConnectAPI::Certificate.all"), true,
          "source: the census enumerates with the same call fastlane list_certs uses"
assert_eq code_lines.include?("DELETE"), false,
          "source: the tool contains no certificate deletion request (C-G exists; D-39 forbids it)"

# ---------------------------------------------------------------------------
# submission-probe — ACCT-04's write-path instrument
# ---------------------------------------------------------------------------

# The keys 02-09 pastes into its SUMMARY, duplicated here rather than read back
# out of the probe's own output.
PROBE_KEYS = %w[label app_id platform team status body_excerpt measured_at].freeze

APP_ID = "6749152233"

# What App Store Connect returns when a review submission is refused. The status
# lives in the ENVELOPE, not in this body -- that separation is the point: the
# body is context, the HTTP status is the observation.
def review_error_body(marker, status: "403", code: "FORBIDDEN_ERROR")
  {
    "errors" => [
      {
        "id" => "11111111-2222-3333-4444-555555555555",
        "status" => status,
        "code" => code,
        "title" => marker,
        "detail" => "The request could not be completed."
      }
    ]
  }
end

# 46. THE LOAD-BEARING CASE FOR ACCT-04. Three statuses, each reported verbatim,
#     each exiting 0 — because a completed request is an observation, and the
#     tool's job ends at reporting it. 403 means the key's role does not permit
#     Submit apps; 409/422 mean it does and the record was refused on business
#     grounds. That mapping is assumption A1 and is NOT asserted here, because
#     the tool does not make it.
with_fixtures do |dir|
  observations = {}
  { 403 => "marker-403-role-refused",
    409 => "marker-409-record-conflict",
    422 => "marker-422-unprocessable" }.each do |status, marker|
    fixture = write_fixture(dir, "submit-#{status}.json",
                            review_error_body(marker, status: status.to_s), status: status)
    out, err, code = probe("submission-probe", "--app-id", APP_ID, "--fixture", fixture)
    assert_eq code, 0, "submission-probe: a #{status} is a completed request and exits 0 (stderr: #{err.strip})"

    parsed = out.strip.empty? ? {} : JSON.parse(out)
    observations[status] = parsed
    assert_eq parsed["status"], status,
              "submission-probe: the #{status} is reported verbatim in the status field"
    assert_eq parsed["body_excerpt"].to_s.include?(marker), true,
              "submission-probe: the #{status} response body reaches the caller alongside the status"
    assert_eq out.include?("SUFFICIENT"), false,
              "submission-probe: the #{status} run renders no verdict — that needs two runs (02-09)"
  end

  # THE DISCRIMINATION. Asserted on the PARSED status field rather than on a
  # substring of raw output, so a formatting change cannot make this pass while
  # the discrimination is gone.
  assert_eq observations[403]["status"] == observations[409]["status"], false,
            "submission-probe: 403 and 409 produce different status values"
  assert_eq observations[403]["status"] == observations[422]["status"], false,
            "submission-probe: 403 and 422 produce different status values"
  assert_eq [observations[403]["status"], observations[409]["status"], observations[422]["status"]],
            [403, 409, 422],
            "submission-probe: each of the three statuses survives as itself"
end

# 47. The report's shape. 02-09 pastes this JSON into a tracked SUMMARY, so its
#     keys are a contract and its excerpt is bounded.
with_fixtures do |dir|
  fixture = write_fixture(dir, "submit-409.json",
                          review_error_body("marker-409", status: "409"), status: 409)
  out, _err, code = probe("submission-probe", "--app-id", APP_ID,
                          "--platform", "MAC_OS", "--label", "primary", "--fixture", fixture)
  assert_eq code, 0, "submission-probe: a labelled run exits 0"
  parsed = out.strip.empty? ? {} : JSON.parse(out)

  assert_eq parsed.keys.sort, PROBE_KEYS.sort,
            "submission-probe: the report carries exactly the observation keys"
  assert_eq parsed["label"], "primary", "submission-probe: --label is carried into the report"
  assert_eq parsed["app_id"], APP_ID, "submission-probe: the app id is carried into the report"
  assert_eq parsed["platform"], "MAC_OS", "submission-probe: --platform is carried into the report"
  assert_eq parsed["team"], "G5H628C6WR", "submission-probe: the observation names its team (C-05)"
  assert_eq parsed["measured_at"].to_s.end_with?("Z"), true,
            "submission-probe: the observation is dated in UTC"
end

# 48. --platform defaults to IOS and is validated against the closed set BEFORE
#     any request. The fixture below does not exist, so a probe that validated
#     after fetching would name the fixture instead of the platform.
with_fixtures do |dir|
  fixture = write_fixture(dir, "submit-409.json",
                          review_error_body("marker-409", status: "409"), status: 409)
  out, _err, code = probe("submission-probe", "--app-id", APP_ID, "--fixture", fixture)
  assert_eq code, 0, "submission-probe: omitting --platform is allowed"
  parsed = out.strip.empty? ? {} : JSON.parse(out)
  assert_eq parsed["platform"], "IOS", "submission-probe: --platform defaults to IOS"

  absent = File.join(dir, "never-created.json")
  _out, err, code = probe("submission-probe", "--app-id", APP_ID,
                          "--platform", "BOGUS", "--fixture", absent)
  assert_eq code, 1, "submission-probe: a platform outside the closed set exits 1"
  assert_eq err.include?("BOGUS"), true, "submission-probe: stderr names the rejected platform"
  assert_eq err.include?(absent), false,
            "submission-probe: the platform is rejected BEFORE any request is made"

  _out, _err, code = probe("submission-probe", "--app-id", APP_ID,
                           "--platform", "UNIVERSAL", "--fixture", absent)
  assert_eq code, 1, "submission-probe: UNIVERSAL is rejected — spaceship does not expose it (C-02)"
end

# 49. Argv. A probe that ran against no app is not an observation.
_out, err, code = probe("submission-probe")
assert_eq code, 1, "submission-probe: omitting --app-id exits 1"
assert_eq err.include?("--app-id"), true, "submission-probe: stderr names the missing flag"

with_fixtures do |dir|
  absent = File.join(dir, "never-created.json")
  _out, err, code = probe("submission-probe", "--app-id", "6749152233/../../evil", "--fixture", absent)
  assert_eq code, 1, "submission-probe: an app id carrying path metacharacters is rejected"
  assert_eq err.include?(absent), false,
            "submission-probe: the app id is rejected BEFORE any request is made"

  _out, err, code = probe("submission-probe", "--app-id", APP_ID, "--fixture", absent)
  assert_eq code, 1, "submission-probe: a fixture that cannot be read exits 1"
  assert_eq err.include?(absent), true, "submission-probe: stderr names the unreadable fixture"
end

# 50. The offline guarantee for the one path with no fixture: the POST is never
#     issued from the suite, because the probe dies on credentials first.
_out, err, code = probe("submission-probe", "--app-id", APP_ID)
assert_eq code, 1, "submission-probe: a live POST with no credentials exits 1"
assert_eq err.include?("ASC_API_KEY_ID"), true, "submission-probe: stderr names the missing credential"

# 51. A 400-character bound on the excerpt, asserted against a body that is
#     genuinely longer — a short body could not tell truncation from its absence.
with_fixtures do |dir|
  long = write_fixture(dir, "submit-long.json",
                       { "errors" => [{ "detail" => "x" * 5000, "title" => "marker-long" }] },
                       status: 422)
  out, _err, code = probe("submission-probe", "--app-id", APP_ID, "--fixture", long)
  assert_eq code, 0, "submission-probe: a long body still exits 0"
  parsed = out.strip.empty? ? {} : JSON.parse(out)
  assert_eq parsed["body_excerpt"].to_s.length <= 400, true,
            "submission-probe: body_excerpt is at most 400 characters"
  assert_eq parsed["body_excerpt"].to_s.include?("x" * 100), true,
            "submission-probe: the excerpt is the start of the real body, not a placeholder"
end

# 52. A 201 would mean the record accepted a submission. It is still just a
#     status: the tool reports it and exits 0 rather than declaring anything.
with_fixtures do |dir|
  created = write_fixture(dir, "submit-201.json",
                          { "data" => { "type" => "reviewSubmissions", "id" => "SUB1" } }, status: 201)
  out, _err, code = probe("submission-probe", "--app-id", APP_ID, "--fixture", created)
  assert_eq code, 0, "submission-probe: a 201 exits 0 like every other completed request"
  parsed = out.strip.empty? ? {} : JSON.parse(out)
  assert_eq parsed["status"], 201, "submission-probe: a 201 is reported verbatim too"
end

# 53. Encoding, on the write path, under a cleared locale (UL-012).
with_fixtures do |dir|
  accented = write_fixture(dir, "submit-utf8.json",
                           review_error_body("Réservé — Café Müller", status: "409"), status: 409)
  out, err, code = probe("submission-probe", "--app-id", APP_ID, "--fixture", accented, env: NO_LOCALE)
  assert_eq code, 0, "submission-probe: a non-ASCII body is read under a cleared locale (stderr: #{err.strip})"
  assert_eq out.include?("Café Müller"), true, "submission-probe: the non-ASCII body survives intact"
end

# ---------------------------------------------------------------------------
# probe-compare — the pair, and the outcome that says the pair proves nothing
# ---------------------------------------------------------------------------

# 54. Two observations that differ. The pair discriminates; what the two codes
#     MEAN is A1's mapping and remains 02-09's reading, never this tool's.
with_fixtures do |dir|
  f403 = write_fixture(dir, "submit-403.json", review_error_body("m403"), status: 403)
  f409 = write_fixture(dir, "submit-409.json", review_error_body("m409", status: "409"), status: 409)
  primary = File.join(dir, "primary.json")
  control = File.join(dir, "control.json")

  out, _err, _code = probe("submission-probe", "--app-id", APP_ID, "--label", "primary", "--fixture", f409)
  File.write(primary, out, encoding: "UTF-8")
  out, _err, _code = probe("submission-probe", "--app-id", APP_ID, "--label", "control", "--fixture", f403)
  File.write(control, out, encoding: "UTF-8")

  out, err, code = probe("probe-compare", "--primary", primary, "--control", control)
  assert_eq code, 0, "probe-compare: two different statuses exit 0 (stderr: #{err.strip})"
  assert_eq out.include?("409"), true, "probe-compare: the primary status is named"
  assert_eq out.include?("403"), true, "probe-compare: the control status is named"
  assert_eq (out + err).include?("SUFFICIENT"), false,
            "probe-compare: no sufficiency verdict is rendered — the reading is A1's, not the tool's"
  assert_eq (out + err).include?("DISCARDED"), false,
            "probe-compare: a discriminating pair is not discarded"
end

# 55. THE INDETERMINATE OUTCOME. Both keys returned the same code, so the probe
#     did not discriminate and MUST be discarded rather than reinterpreted
#     (02-RESEARCH.md A1's mitigation; 02-VALIDATION.md ACCT-04's control column:
#     "Same code from both ⇒ discard the probe, do not reinterpret it").
#
#     It gets its own exit code because a tool that can only say pass/fail cannot
#     express the one answer that matters when the control fails.
with_fixtures do |dir|
  f403 = write_fixture(dir, "submit-403.json", review_error_body("m403"), status: 403)
  primary = File.join(dir, "primary.json")
  control = File.join(dir, "control.json")

  out, _err, _code = probe("submission-probe", "--app-id", APP_ID, "--label", "primary", "--fixture", f403)
  File.write(primary, out, encoding: "UTF-8")
  out, _err, _code = probe("submission-probe", "--app-id", APP_ID, "--label", "control", "--fixture", f403)
  File.write(control, out, encoding: "UTF-8")

  out, err, code = probe("probe-compare", "--primary", primary, "--control", control)
  assert_eq code, 3, "probe-compare: two identical statuses exit exactly 3, not 0 and not 1"
  assert_eq (out + err).include?("PROBE DISCARDED"), true,
            "probe-compare: the indeterminate outcome is named in full"
  assert_eq (out + err).include?("SUFFICIENT"), false,
            "probe-compare: a discarded probe yields no verdict of any kind"
end

# 56. probe-compare argv, and the observation files it refuses.
with_fixtures do |dir|
  f403 = write_fixture(dir, "submit-403.json", review_error_body("m403"), status: 403)
  primary = File.join(dir, "primary.json")
  out, _err, _code = probe("submission-probe", "--app-id", APP_ID, "--fixture", f403)
  File.write(primary, out, encoding: "UTF-8")

  _out, err, code = probe("probe-compare", "--primary", primary)
  assert_eq code, 1, "probe-compare: omitting --control exits 1"
  assert_eq err.include?("--control"), true, "probe-compare: stderr names the missing flag"

  _out, err, code = probe("probe-compare", "--control", primary)
  assert_eq code, 1, "probe-compare: omitting --primary exits 1"
  assert_eq err.include?("--primary"), true, "probe-compare: stderr names the missing flag"

  statusless = File.join(dir, "statusless.json")
  File.write(statusless, JSON.generate("label" => "primary", "app_id" => APP_ID), encoding: "UTF-8")
  _out, err, code = probe("probe-compare", "--primary", statusless, "--control", primary)
  assert_eq code, 1, "probe-compare: an observation with no status exits 1"
  assert_eq err.include?("status"), true, "probe-compare: stderr says which field was missing"

  absent = File.join(dir, "nope.json")
  _out, err, code = probe("probe-compare", "--primary", absent, "--control", primary)
  assert_eq code, 1, "probe-compare: an observation file that does not exist exits 1"
  assert_eq err.include?(absent), true, "probe-compare: stderr names the unreadable path"
end

# 57. Source assertions for the submission half. The endpoint choice is the
#     entire design, and the comment recording why is load-bearing documentation
#     that a future reader will otherwise undo.
submit_source = File.read(SCRIPT, encoding: "UTF-8")
submit_code = submit_source.lines.reject { |line| line.start_with?("#") }.join
assert_eq submit_code.include?("/v1/reviewSubmissions"), true,
          "source: the probe posts to the reviewSubmissions collection"
assert_eq submit_code.include?("betaAppReviewSubmissions"), false,
          "source: the TestFlight beta path is not used — it needs a build that does not exist"
assert_eq submit_source.include?("betaAppReviewSubmissions"), true,
          "source: the rejected beta endpoint is named in the comment, so the choice is not silent"
assert_eq submit_source.include?("GET /v1/apps/{id}/reviewSubmissions"), true,
          "source: the rejected read-based endpoint is named in the comment (Pitfall 1)"
assert_eq submit_source.match?(/\bA1\b/), true,
          "source: the comment names assumption A1 — the status mapping is not Apple's word"
assert_eq submit_code.match?(/"?(IN)?SUFFICIENT"?/), false,
          "source: the tool reports a status; it never encodes a sufficiency verdict"

# 58. The live paths fail with a message, never a stack trace — under BOTH the
#     ambient ruby and the pinned one.
#
#     This case exists because the first draft of certificate_records_live put
#     `require "spaceship"` above the credential guard. Under ruby 4.0.6 the gem
#     happens to be loadable, so the guard still ran and the suite was green;
#     under the pinned ruby 3.3 with no bundle the require blew up first and the
#     probe printed a rubygems stack trace naming kernel_require.rb. A suite run
#     on one interpreter cannot see that, which is why 02-VALIDATION.md's full
#     run is on both.
[["census"], ["submission-probe", "--app-id", "6749152233"]].each do |argv|
  _out, err, code = probe(*argv)
  label = argv.first
  assert_eq code, 1, "#{label}: a live call with no credentials exits 1"
  assert_eq err.include?("ASC_API_KEY_ID"), true,
            "#{label}: the credential guard runs before anything that needs the bundle"
  assert_eq err.include?("LoadError") || err.include?("NameError") ||
            err.include?("uninitialized constant"), false,
            "#{label}: the failure is a message, not a stack trace"
end

if @failures.zero?
  puts "\nAll #{@checks} asc-probe regression assertions passed."
  exit 0
else
  puts "\n#{@failures} of #{@checks} asc-probe assertion(s) failed."
  exit 1
end
