#!/usr/bin/env ruby
# frozen_string_literal: true

# Ask App Store Connect what it actually stored, and report the answer verbatim
# -- including the HTTP status code.
#
# Why this exists: Phase 2 makes irreversible account decisions (bundle IDs, app
# records, permanent SKUs) whose outcomes live entirely inside Apple's systems.
# Every claim about that state has to be evidenced by an observed response, and
# before this script nothing in this repository could produce one. `fastlane
# list_certs` covers certificates only. The `bootstrap_asc` lane verifies that a
# record exists but cannot read `sku` or `primaryLocale`, and its remediation
# text at fastlane/Fastfile:1349-1352 tells the reader to create one record with
# "Platforms: iOS + macOS" -- the Universal Purchase shape decision D-05
# declined (correction C-10). So the probe is the instrument the rest of the
# phase measures with, and it is built and calibrated before any Apple-touching
# task runs.
#
# Why the status code is the product, not an implementation detail: the ACCT-04
# submission probe exists to discriminate 403 (the key's role is insufficient)
# from 409/422 (the role is sufficient and the record simply has no build). Any
# transport that answers those two the same way produces a check which passes
# identically whether or not the key can do the job. See the comment above
# asc_request.
#
# Dependencies: Ruby stdlib only -- net/http, openssl, json, time, uri. No gem,
# no Gemfile entry, no Gemfile.lock change, no test framework. The one exception
# is token minting, which reaches into fastlane's Spaceship exactly as
# bin/lib/bootstrap.rb does; that path -- and only that path -- must be run
# under the pinned bundle:
#
#   /opt/homebrew/opt/ruby@3.3/bin/bundle exec ruby tools/asc-probe.rb ...
#
# Never a bare `bundle`: brew's unversioned ruby is 4.0.x and resolves
# vendor/bundle/ruby/4.0.0, which does not exist (Makefile:45-53).
#
# Usage (run from the repository root):
#   ruby tools/asc-probe.rb --help
#   ruby tools/asc-probe.rb read-back bundle-id --identifier com.example.app
#   ruby tools/asc-probe.rb read-back bundle-id --identifier com.example.app \
#        --fixture test/fixtures/response.json      # offline; no credentials
#   ruby tools/asc-probe.rb census --out /tmp/census-before.json
#   ruby tools/asc-probe.rb census-diff --before /tmp/before.json \
#        --after /tmp/after.json
#   ruby tools/asc-probe.rb submission-probe --app-id 6749152233 --label primary
#   ruby tools/asc-probe.rb probe-compare --primary /tmp/primary.json \
#        --control /tmp/control.json
#
# Secrets: this file never prints the bearer token, the .p8, or
# ASC_API_KEY_P8_BASE64. Token acquisition is isolated in asc_token, no
# request headers are ever echoed, and every response body reaching stderr is
# truncated to BODY_PREVIEW characters. Anything this tool prints may be pasted
# into a tracked SUMMARY, so nothing secret may reach stdout or stderr.

require "json"
require "net/http"
require "openssl"
require "time"
require "uri"

# The host is a constant and is NEVER taken from argv: argv must not be able to
# redirect a request signed with this team's key to some other host.
API_HOST = "api.appstoreconnect.apple.com"

# The team every measurement in this phase is made against. Stamped into every
# success report, because a bare value with no team is a future defect:
# .github/workflows/release.yml:35 carries certificate caps measured against
# team A1B2C3D4E5, not ours, and nothing in the file says so (correction C-05).
EXPECTED_TEAM = "G5H628C6WR"

# The closed set exposed by Spaceship::ConnectAPI::BundleIdPlatform in the
# locked fastlane 2.238.0 (correction C-02). Apple's own API enum additionally
# has UNIVERSAL; spaceship does not expose it, and decision D-05 declined the
# Universal Purchase model it implies. Duplicated here deliberately rather than
# derived from the gem, so this validation does not depend on the thing it is
# validating -- and so the probe runs without the bundle.
BUNDLE_ID_PLATFORMS = %w[IOS MAC_OS].freeze

# The closed set of certificate types the release lane mints (C-06,
# .github/workflows/release.yml:7, .github/workflows/canary-local-mode.yml:24).
# Duplicated here deliberately rather than derived from the census this tool
# just produced, for the reason test/docs_structure_test.rb:63-67 gives about
# its own verdict vocabulary: a check that reads its vocabulary out of the
# artifact under test accepts whatever that artifact happens to say, which is
# not a check. The census reports these three even at zero occupancy, so an
# empty type is visibly zero rather than silently absent.
RELEASE_CERT_TYPES = %w[DISTRIBUTION DEVELOPMENT MAC_INSTALLER_DISTRIBUTION].freeze

# Bundle identifiers and app bundle ids are the only argv values interpolated
# into an outbound request path, so they are constrained to a shape carrying no
# path, query or regex metacharacters.
IDENTIFIER_RE = /\A[A-Za-z0-9.\-]+\z/

# How much of a response body reaches stderr on a failure. Enough to identify
# Apple's error code, short of pasting an entire payload into a terminal that
# may be screenshotted into a tracked document.
BODY_PREVIEW = 400

# Everything bearer_token needs before it is worth calling Spaceship at all.
# fastlane/Fastfile:108 does ENV.fetch("ASC_API_KEY_P8_BASE64") while
# .bootstrap.env supplies only ASC_API_KEY_P8_PATH, so a direct invocation dies
# with an opaque KeyError naming nothing actionable (Pitfall 7, confirmed live
# in plan 02-01). This probe names the missing variable instead.
TOKEN_ENV_VARS = %w[ASC_API_KEY_ID ASC_API_KEY_ISSUER_ID].freeze
KEY_MATERIAL_VARS = %w[ASC_API_KEY_P8_BASE64 ASC_API_KEY_P8_PATH].freeze

USAGE = <<~TXT
  usage: ruby tools/asc-probe.rb <subcommand> [options]

    read-back bundle-id --identifier <id> --expect-platform <IOS|MAC_OS>
    read-back app       --bundle-id <id> [--expect-sku <sku>]
                                         [--expect-locale <locale>]
                                         [--expect-name <name>]
    census              [--out <path>]
    census-diff         --before <path> --after <path>
    submission-probe    --app-id <asc app id> [--platform IOS|MAC_OS]
                                              [--label <text>]
    probe-compare       --primary <path> --control <path>

  common options:
    --fixture <path>  read a saved response envelope from disk instead of
                      calling #{API_HOST}. Offline; needs no credentials.
    -h, --help        print this message

  exit codes, read-back:
    0  the resource was found AND every --expect-* assertion held
    1  a usage error, a transport failure, or an assertion that did not hold
    2  the resource was not found (App Store Connect returned an empty "data")

  exit codes, census-diff:
    0  the id set is unchanged or grew
    1  an id present in --before is absent from --after (a removal)
    2  a malformed census: no team, no measured_at, or a team that is not
       this one. This tool only ever reports; it revokes nothing (D-39).

  exit codes, submission-probe:
    0  the request completed and its status was printed. The verdict is the
       caller's: one status code is an observation, not a conclusion.
    1  a usage error, a transport failure, or a missing --app-id

  exit codes, probe-compare:
    0  the two observations carry different status codes
    1  a usage error, or an observation carrying no status
    3  both observations carry the SAME status code: PROBE DISCARDED. The
       probe did not discriminate. Do not reinterpret it (A1).

  Live calls need the pinned bundle:
    /opt/homebrew/opt/ruby@3.3/bin/bundle exec ruby tools/asc-probe.rb ...
TXT

# Every failure path is explicit and loud. There is no broad rescue anywhere in
# this file, and that is a deliberate departure from the analog this file's
# transport was copied from. bin/lib/bootstrap.rb:961 ends its ASC helper with a
# blanket `rescue StandardError` yielding nil, and bootstrap.rb:951 discards any
# non-2xx the same way. Both are correct there -- it is a warn-only doctor check
# whose worst outcome is a missing warning. Both would be fatal here, because
# this probe's entire output is a status code: collapsing 403 and 409 into the
# same nil destroys the only discrimination the probe exists to make.
def die(message)
  warn "asc-probe: #{message}"
  exit 1
end

# Not found is a distinct outcome from a failure, and it gets a distinct code.
# A query that matches nothing and an assertion that therefore never executes is
# the classic vacuous-truth gate -- the failure mode this whole phase is
# organised around avoiding. Exit 2 makes "nothing was there" impossible to read
# as "everything checked out".
def not_found(filter)
  warn "asc-probe: not found: #{filter} — App Store Connect returned an empty " \
       "\"data\" array. Nothing was asserted, because there was nothing to " \
       "assert against."
  exit 2
end

# Every read pins UTF-8 explicitly rather than inheriting the locale. With LANG
# unset -- cron, launchd, a bare container, `env -i`, a CI runner -- Ruby
# defaults Encoding.default_external to US-ASCII, and any non-ASCII byte then
# blows up inside JSON.parse instead of producing a verdict. UL-012 is the live
# instance: this exact bug shipped in tools/gen-review-notes.rb and needed
# PR #2 to fix. An App Store Connect app name or display name carrying a
# diacritic is entirely reachable input.
def read_utf8(path)
  File.read(path, encoding: "UTF-8")
end

# Argv arrives tagged with Encoding.default_external, which is US-ASCII under a
# cleared locale. Comparing such a string against a UTF-8 value parsed out of a
# response returns false even when the bytes match, so every argv value that is
# ever compared or interpolated is re-tagged here.
def utf8_arg(value)
  value.to_s.dup.force_encoding(Encoding::UTF_8)
end

def preview(body)
  text = body.to_s
  text.length > BODY_PREVIEW ? "#{text[0, BODY_PREVIEW]}… (truncated)" : text
end

def parse_json(raw, source)
  JSON.parse(raw)
rescue JSON::ParserError => e
  die "#{source}: not valid JSON — #{e.message[0, 200]}"
end

def validate_identifier!(value, flag)
  return if value.match?(IDENTIFIER_RE)

  die "invalid #{flag} #{value.inspect}: must match #{IDENTIFIER_RE.inspect} — " \
      "letters, digits, '.' and '-' only. This value is interpolated into an " \
      "outbound request path, so path and query metacharacters are rejected " \
      "before any request is made."
end

# The single point of token acquisition, so every other code path can be driven
# offline with --fixture. Guarded rather than left to raise: an opaque KeyError
# out of a fetch tells the reader nothing about which of three variables in two
# files is missing.
#
# Returns the Token object rather than only its text, because the census needs
# spaceship's own client authenticated (Spaceship::ConnectAPI.token = ...) while
# asc_request needs nothing but the JWT string. bearer_token below is the thin
# wrapper for the second case, and it remains the only thing asc_request sees.
def asc_token
  missing = TOKEN_ENV_VARS.select { |name| ENV[name].to_s.strip.empty? }
  unless missing.empty?
    die "#{missing.join(' and ')} #{missing.length == 1 ? 'is' : 'are'} not set. " \
        "A live App Store Connect call needs #{TOKEN_ENV_VARS.join(', ')} and " \
        "one of #{KEY_MATERIAL_VARS.join(' / ')}. Load them with " \
        "`set -a; . ./.bootstrap.env; set +a`, or pass --fixture to run offline."
  end

  if KEY_MATERIAL_VARS.all? { |name| ENV[name].to_s.strip.empty? }
    die "no App Store Connect key material: set #{KEY_MATERIAL_VARS.join(' or ')}. " \
        ".bootstrap.env supplies only ASC_API_KEY_P8_PATH, so a direct " \
        "invocation must export the base64 itself."
  end

  require "spaceship"

  # The key material is passed EXPLICITLY. Spaceship's Token.create resolves it
  # from its own arguments or from SPACESHIP_CONNECT_API_KEY /
  # SPACESHIP_CONNECT_API_KEY_FILEPATH, and then does an unconditional
  # `key ||= File.binread(filepath)` (spaceship/connect_api/token.rb:63 in the
  # locked fastlane 2.238.0). With neither supplied that is File.binread(nil),
  # which raises `TypeError: no implicit conversion of nil into String` --
  # naming none of the four variables the caller actually has to set. This
  # probe's whole reason for guarding the environment above is to never produce
  # that class of message, so it hands the material over rather than hoping
  # some other process exported spaceship's own variable names.
  key_id = ENV.fetch("ASC_API_KEY_ID")
  issuer_id = ENV.fetch("ASC_API_KEY_ISSUER_ID")
  base64_key = ENV["ASC_API_KEY_P8_BASE64"].to_s.strip

  if base64_key.empty?
    Spaceship::ConnectAPI::Token.create(
      key_id: key_id, issuer_id: issuer_id, filepath: ENV.fetch("ASC_API_KEY_P8_PATH")
    )
  else
    Spaceship::ConnectAPI::Token.create(
      key_id: key_id, issuer_id: issuer_id, key: base64_key, is_key_content_base64: true
    )
  end
end

# Only the JWT's text leaves here, and it goes straight into a request header.
# It is never logged, printed, or interpolated into a message.
def bearer_token
  asc_token.text
end

# The request construction below is copied from bin/lib/bootstrap.rb:951-962.
# The error handling deliberately is NOT.
#
# Handling chosen: return [status, body] for every response Apple gives us,
# whatever the status, and let each caller decide what the status means. A
# transport-level exception -- DNS, TCP, TLS, timeout -- is a distinct thing
# from a response, and it dies loudly rather than being folded into the same
# nil as a 403.
#
# Handling rejected: bootstrap.rb's pair of lines that discard any non-2xx and
# then swallow every exception into nil. Why the rejected one proves nothing:
# ACCT-04's whole design is a submission call whose meaning is 403 versus
# 409/422. Given nil for both, the probe reports "no answer" in the case where
# the key IS sufficient and in the case where it is NOT, and a green run then
# certifies a key that cannot ship. That is 02-PATTERNS.md finding 2 and
# Pitfall 1 -- "the submission probe that cannot fail" -- reduced to two lines
# of copy-paste. This was observed, not assumed: reintroducing the collapse
# turns test/asc_probe_test.rb's 403-vs-409 discrimination case red.
def asc_request(method, path, body: nil, fixture: nil)
  return fixture_response(fixture) unless fixture.nil?

  uri = URI("https://#{API_HOST}#{path}")
  request = case method
            when :get  then Net::HTTP::Get.new(uri)
            when :post then Net::HTTP::Post.new(uri)
            else die "unsupported HTTP method #{method.inspect}"
            end
  request["Authorization"] = "Bearer #{bearer_token}"
  unless body.nil?
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(body)
  end

  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 30) do |http|
    http.request(request)
  end

  [response.code.to_i, response.body.to_s]
rescue SocketError, SystemCallError, IOError, Timeout::Error, OpenSSL::SSL::SSLError => e
  # Narrow on purpose: these are the ways a request fails to produce a response
  # at all. A response, of any status, is never routed through here.
  die "transport failure on #{method.to_s.upcase} #{path}: #{e.class}: #{e.message[0, 200]}"
end

# The offline half of the transport. The envelope carries the status alongside
# the body precisely so a fixture can exercise a 403 or a 409 -- a fixture that
# could only ever be a 200 would be unable to test the property this tool exists
# to guarantee.
#
# Accepted shapes:
#   {"status": 409, "body": {...}}   envelope (body may also be a string)
#   <raw response JSON>              status read from an accompanying
#                                    "<path>.status" file, defaulting to 200
def fixture_response(path)
  die "--fixture #{path}: no such file — nothing to read a response from." unless File.file?(path)

  raw = read_utf8(path)
  parsed = parse_json(raw, "--fixture #{path}")

  if parsed.is_a?(Hash) && parsed.key?("status") && parsed.key?("body")
    status = parsed["status"]
    die "--fixture #{path}: \"status\" must be an integer, got #{status.inspect}" unless status.is_a?(Integer)

    body = parsed["body"]
    return [status, body.is_a?(String) ? body : JSON.generate(body)]
  end

  sidecar = "#{path}.status"
  status = File.file?(sidecar) ? read_utf8(sidecar).strip.to_i : 200
  [status, raw]
end

# Hand-rolled and index-walked, matching tools/gen-review-notes.rb:70-100. The
# `else` branch rejects unknown argv rather than ignoring it: a typo'd flag must
# not look like a successful run. A leading positional verb is the only
# extension over the Phase 1 precedent; no argument-parsing library is
# introduced, because reaching for OptionParser here would be the first
# structural departure from that precedent and it buys nothing this loop does
# not already do.
def parse_read_back_args(argv)
  options = { identifier: nil, bundle_id: nil, fixture: nil, expect: {} }

  index = 0
  while index < argv.length
    case argv[index]
    when "--identifier"
      index += 1
      die "--identifier requires a value\n#{USAGE}" if argv[index].nil?
      options[:identifier] = utf8_arg(argv[index])
    when "--bundle-id"
      index += 1
      die "--bundle-id requires a value\n#{USAGE}" if argv[index].nil?
      options[:bundle_id] = utf8_arg(argv[index])
    when "--expect-platform"
      index += 1
      die "--expect-platform requires a value\n#{USAGE}" if argv[index].nil?
      options[:expect]["platform"] = utf8_arg(argv[index])
    when "--expect-sku"
      index += 1
      die "--expect-sku requires a value\n#{USAGE}" if argv[index].nil?
      options[:expect]["sku"] = utf8_arg(argv[index])
    when "--expect-locale"
      index += 1
      die "--expect-locale requires a value\n#{USAGE}" if argv[index].nil?
      options[:expect]["primaryLocale"] = utf8_arg(argv[index])
    when "--expect-name"
      index += 1
      die "--expect-name requires a value\n#{USAGE}" if argv[index].nil?
      options[:expect]["name"] = utf8_arg(argv[index])
    when "--fixture"
      index += 1
      die "--fixture requires a value\n#{USAGE}" if argv[index].nil?
      options[:fixture] = utf8_arg(argv[index])
    when "-h", "--help"
      puts USAGE
      exit 0
    else
      die "unknown argument #{argv[index].inspect}\n#{USAGE}"
    end
    index += 1
  end

  options
end

def require_flag!(value, flag, context)
  return value unless value.nil?

  die "#{context} requires #{flag}\n#{USAGE}"
end

# A flag that belongs to the other noun is rejected rather than parsed and
# ignored. Silently accepting --expect-sku on a bundle-id read-back would
# produce a green run in which the SKU was never checked -- an assertion the
# caller believes ran and did not.
def reject_flags!(present, allowed, context)
  offenders = present.keys - allowed
  return if offenders.empty?

  die "#{offenders.map { |k| FLAG_FOR_KEY.fetch(k, k) }.join(', ')} " \
      "#{offenders.length == 1 ? 'is' : 'are'} not valid for #{context}\n#{USAGE}"
end

# Attribute key -> the flag a caller typed, so an error message names what the
# caller wrote rather than the JSON field it maps to.
FLAG_FOR_KEY = {
  "platform" => "--expect-platform",
  "sku" => "--expect-sku",
  "primaryLocale" => "--expect-locale",
  "name" => "--expect-name",
  "bundleId" => "--bundle-id",
  "identifier" => "--identifier"
}.freeze

# Collects every mismatch rather than dying on the first, so one run tells the
# caller everything Apple disagrees with instead of one thing at a time.
def compare(mismatches, key, expected, actual)
  return if expected.nil?
  return if expected == actual

  mismatches << "expected #{key}=#{expected.inspect}, got #{actual.inspect}"
end

# Fetches the single record a filter is expected to match, and refuses every
# other cardinality. Zero matches exit 2 (see not_found); more than one is a
# failure rather than a pick-the-first, because an assertion applied to an
# arbitrary member of an ambiguous result set is not an assertion.
def fetch_one(path, filter, fixture)
  status, body = asc_request(:get, path, fixture: fixture)

  unless status.between?(200, 299)
    die "GET #{path} returned HTTP #{status} — #{preview(body)}"
  end

  parsed = parse_json(body, "response to GET #{path}")
  data = parsed.is_a?(Hash) ? parsed["data"] : nil
  die "response to GET #{path} has no \"data\" array — #{preview(body)}" unless data.is_a?(Array)

  not_found(filter) if data.empty?

  if data.length > 1
    die "ambiguous: #{filter} matched #{data.length} records. An assertion " \
        "applied to an arbitrary one of them would prove nothing; narrow the " \
        "filter or investigate the duplicates."
  end

  entry = data[0]
  [entry.is_a?(Hash) ? (entry["attributes"] || {}) : {}, entry.is_a?(Hash) ? entry["id"] : nil]
end

# Always prints the full attribute set Apple returned, not an echo of what was
# asked about, so the caller records what was actually stored. team and
# measured_at are stamped in so every report is already the dated triple
# 02-VALIDATION.md requires rather than a bare value a later reader has to date
# from memory.
def report(subcommand, resource, filter, id, attributes, mismatches)
  unless mismatches.empty?
    mismatches.each { |mismatch| warn "asc-probe: #{mismatch}" }
    warn "asc-probe: #{subcommand} FAILED — App Store Connect did not store " \
         "what was expected for #{filter}."
    exit 1
  end

  puts JSON.pretty_generate(
    "subcommand" => subcommand,
    "team" => EXPECTED_TEAM,
    "measured_at" => Time.now.utc.iso8601,
    "resource" => resource,
    "filter" => filter,
    "id" => id,
    "attributes" => attributes
  )
end

# ACCT-01's instrument. --expect-platform is REQUIRED, not optional: a
# read-back with no assertion in it is a request, not a gate, and correction
# C-02 is the reason the accepted set is exactly two values -- spaceship's
# BundleIdPlatform in the locked fastlane 2.238.0 exposes IOS and MAC_OS and
# nothing else, and D-05 declined the Universal Purchase model UNIVERSAL implies.
def read_back_bundle_id(options)
  reject_flags!(options[:expect], ["platform"], "read-back bundle-id")
  die "read-back bundle-id does not take --bundle-id; use --identifier\n#{USAGE}" unless options[:bundle_id].nil?

  identifier = require_flag!(options[:identifier], "--identifier", "read-back bundle-id")
  validate_identifier!(identifier, "--identifier")

  platform = require_flag!(options[:expect]["platform"], "--expect-platform", "read-back bundle-id")
  unless BUNDLE_ID_PLATFORMS.include?(platform)
    die "invalid --expect-platform #{platform.inspect}: must be one of " \
        "#{BUNDLE_ID_PLATFORMS.join(', ')}. Apple's API enum also has " \
        "UNIVERSAL, but spaceship does not expose it and D-05 declined the " \
        "Universal Purchase model it implies (C-02)."
  end

  filter = "filter[identifier]=#{identifier}"
  path = "/v1/bundleIds?filter%5Bidentifier%5D=#{identifier}&limit=200"
  attributes, id = fetch_one(path, filter, options[:fixture])

  mismatches = []
  compare(mismatches, "platform", platform, attributes["platform"])
  compare(mismatches, "identifier", identifier, attributes["identifier"])

  report("read-back bundle-id", "bundleIds", filter, id, attributes, mismatches)
end

# ACCT-03's instrument. /v1/apps is get-only in ASC OpenAPI 4.4.1 (F-1/R-01),
# so this reads a record a human created in the web UI and never writes one.
# Of the four attributes it asserts on, only sku is genuinely permanent (R-02);
# the others are read back anyway, because "what Apple stored" is the evidence
# this phase records, not "what was typed into the form".
def read_back_app(options)
  reject_flags!(options[:expect], %w[sku primaryLocale name], "read-back app")
  die "read-back app does not take --identifier; use --bundle-id\n#{USAGE}" unless options[:identifier].nil?

  bundle_id = require_flag!(options[:bundle_id], "--bundle-id", "read-back app")
  validate_identifier!(bundle_id, "--bundle-id")

  filter = "filter[bundleId]=#{bundle_id}"
  path = "/v1/apps?filter%5BbundleId%5D=#{bundle_id}&limit=200"
  attributes, id = fetch_one(path, filter, options[:fixture])

  mismatches = []
  compare(mismatches, "bundleId", bundle_id, attributes["bundleId"])
  compare(mismatches, "sku", options[:expect]["sku"], attributes["sku"])
  compare(mismatches, "primaryLocale", options[:expect]["primaryLocale"], attributes["primaryLocale"])
  compare(mismatches, "name", options[:expect]["name"], attributes["name"])

  report("read-back app", "apps", filter, id, attributes, mismatches)
end

def run_read_back(argv)
  noun = argv[0]
  case noun
  when nil
    die "read-back requires a noun: bundle-id or app\n#{USAGE}"
  when "-h", "--help"
    puts USAGE
    exit 0
  when "bundle-id"
    read_back_bundle_id(parse_read_back_args(argv[1..] || []))
  when "app"
    read_back_app(parse_read_back_args(argv[1..] || []))
  else
    die "unknown read-back noun #{noun.inspect}\n#{USAGE}"
  end
end

# ---------------------------------------------------------------------------
# census — ACCT-05's instrument
# ---------------------------------------------------------------------------

# Enumeration chosen: Spaceship::ConnectAPI::Certificate.all, the identical call
# fastlane/Fastfile:862-870's list_certs lane already makes. Enumeration rejected:
# a hand-rolled paginated walker over the certificates collection. Why the
# rejected one is worse: 02-RESEARCH.md §"Don't Hand-Roll" names list_certs as
# ACCT-05's instrument -- id, certificate_type, display_name and expiration_date
# are exactly its four fields -- so the only thing missing was the dated JSON
# envelope, and a second enumeration would be a second thing to keep correct
# against Apple's pagination for no gain.
#
# The single mapping point for both halves of the census: the live path passes
# spaceship's attribute readers, the --fixture path passes App Store Connect's
# raw JSON keys, and both land here. Keeping it one function keeps the offline
# suite honest about what it covers -- only the four field accessors differ
# between live and fixture, and nothing else about the census is unexercised.
#
# Three fields, deliberately. The certificate payload attribute Apple also
# returns is NOT read: this file is summarised into the tracked
# docs/APPLE-ACCOUNT-STATE.md, and a certificate body has no business there
# (T-02-14). There is likewise no creation-date field to read -- ASC API 4.4.1's
# Certificate schema has no such attribute (C-E), and R-04 records that the
# repo's "revokes the oldest cert by creation date" claim is false partly
# because of that. expiration_date is the only ordering proxy that exists.
def certificate_record(id, certificate_type, display_name, expiration_date)
  type = certificate_type.to_s
  die "certificate #{id.inspect} has no certificate type — a census entry that " \
      "cannot be attributed to a type is not a measurement." if type.strip.empty?

  [type, {
    "id" => id,
    "display_name" => display_name,
    "expiration_date" => expiration_date
  }]
end

# The live half. Never reached by the offline suite, by design (no plan before
# 02-09/02-10 makes an Apple call).
def certificate_records_live
  require "spaceship"

  Spaceship::ConnectAPI.token = asc_token
  Spaceship::ConnectAPI::Certificate.all.map do |certificate|
    certificate_record(certificate.id, certificate.certificate_type,
                       certificate.display_name, certificate.expiration_date)
  end
end

# The offline half, reading the same envelope every other --fixture path reads.
# A non-2xx dies rather than producing an empty census: a census file written
# out of a 403 would be a fabricated measurement, and it would then be diffed
# and summarised as though it were an observation.
def certificate_records_fixture(path)
  status, body = fixture_response(path)
  unless status.between?(200, 299)
    die "--fixture #{path} carries HTTP #{status} — #{preview(body)}. No census " \
        "is written from a response that never listed anything."
  end

  parsed = parse_json(body, "--fixture #{path}")
  data = parsed.is_a?(Hash) ? parsed["data"] : nil
  die "--fixture #{path} has no \"data\" array — #{preview(body)}" unless data.is_a?(Array)

  data.map do |entry|
    attributes = entry.is_a?(Hash) ? (entry["attributes"] || {}) : {}
    certificate_record(entry.is_a?(Hash) ? entry["id"] : nil,
                       attributes["certificateType"],
                       attributes["displayName"],
                       attributes["expirationDate"])
  end
end

# Groups by type, and always emits the three types the release lane mints even
# when the team holds none of one. An absent key reads as "not measured"; an
# empty array reads as "measured, and there are zero" -- and zero occupancy is
# precisely a thing ACCT-05 may need to record.
#
# Types outside RELEASE_CERT_TYPES are reported too. They occupy the same team
# and a census that hid them would understate what is there.
def build_census(records)
  census = {}
  RELEASE_CERT_TYPES.each { |type| census[type] = [] }
  records.each { |type, entry| (census[type] ||= []) << entry }
  census
end

def parse_census_args(argv)
  options = { fixture: nil, out: nil }

  index = 0
  while index < argv.length
    case argv[index]
    when "--fixture"
      index += 1
      die "--fixture requires a value\n#{USAGE}" if argv[index].nil?
      options[:fixture] = utf8_arg(argv[index])
    when "--out"
      index += 1
      die "--out requires a value\n#{USAGE}" if argv[index].nil?
      options[:out] = utf8_arg(argv[index])
    when "-h", "--help"
      puts USAGE
      exit 0
    else
      die "unknown argument #{argv[index].inspect}\n#{USAGE}"
    end
    index += 1
  end

  options
end

# The envelope is the product. team and measured_at are stamped in rather than
# left to the caller because a bare occupancy number is a future defect: the
# caps at .github/workflows/release.yml:35-37 were measured 2026-05-08 against
# team A1B2C3D4E5 and nothing in that file says so (C-05).
#
# No quota, cap or maximum appears anywhere in this file. Apple publishes no
# numeric per-team certificate limit (C-A), so there is no authority to encode.
# The census reports occupancy; capacity is an empirical outcome of an actual
# create attempt and belongs to the human-gated plan that makes one.
def run_census(argv)
  options = parse_census_args(argv)

  records = options[:fixture].nil? ? certificate_records_live
                                   : certificate_records_fixture(options[:fixture])
  census = build_census(records)
  document = {
    "team" => EXPECTED_TEAM,
    "measured_at" => Time.now.utc.iso8601,
    "census" => census
  }
  json = JSON.pretty_generate(document)

  if options[:out].nil?
    puts json
    return
  end

  File.write(options[:out], "#{json}\n", encoding: "UTF-8")
  counts = census.map { |type, entries| "#{type}=#{entries.length}" }.join(" ")
  puts "census written to #{options[:out]} — team=#{document['team']} " \
       "measured_at=#{document['measured_at']} #{counts}"
end

# ---------------------------------------------------------------------------
# census-diff — ACCT-05b's "nothing was revoked" proof
# ---------------------------------------------------------------------------

# A census that cannot be trusted is worse than no census, so a malformed one
# gets its own exit code rather than being folded into the general failure or,
# worse, diffed anyway. Exit 2 here is "this file is not a measurement of this
# team", which is a different thing from "a certificate disappeared" (exit 1).
def malformed_census(message)
  warn "asc-probe: malformed census: #{message}"
  exit 2
end

def load_census(path, flag)
  die "#{flag} #{path}: no such file — nothing to diff." unless File.file?(path)

  document = parse_json(read_utf8(path), "#{flag} #{path}")
  unless document.is_a?(Hash)
    die "#{flag} #{path}: expected a census object, got #{document.class}"
  end

  team = document["team"]
  if team.nil?
    malformed_census "#{flag} #{path} carries no \"team\". A census that does " \
                     "not say which team it was measured against cannot be " \
                     "diffed against one that does — that is C-05 repeating."
  end
  unless team == EXPECTED_TEAM
    malformed_census "#{flag} #{path} was measured against team #{team.inspect}, " \
                     "not #{EXPECTED_TEAM}. Diffing another team's occupancy " \
                     "against ours would produce a removal report about " \
                     "certificates that were never here."
  end
  if document["measured_at"].to_s.strip.empty?
    malformed_census "#{flag} #{path} carries no \"measured_at\". An undated " \
                     "measurement cannot go stale, so it can never be known to " \
                     "be wrong."
  end
  unless document["census"].is_a?(Hash)
    malformed_census "#{flag} #{path} carries no \"census\" object."
  end

  document
end

# id => the type and display name it was recorded under, so a removal report can
# name the certificate a human would have to go looking for.
def census_index(document)
  index = {}
  document["census"].each do |type, entries|
    next unless entries.is_a?(Array)

    entries.each do |entry|
      next unless entry.is_a?(Hash)

      id = entry["id"]
      next if id.nil?

      index[id] = { "certificate_type" => type, "display_name" => entry["display_name"] }
    end
  end
  index
end

def parse_census_diff_args(argv)
  options = { before: nil, after: nil }

  index = 0
  while index < argv.length
    case argv[index]
    when "--before"
      index += 1
      die "--before requires a value\n#{USAGE}" if argv[index].nil?
      options[:before] = utf8_arg(argv[index])
    when "--after"
      index += 1
      die "--after requires a value\n#{USAGE}" if argv[index].nil?
      options[:after] = utf8_arg(argv[index])
    when "-h", "--help"
      puts USAGE
      exit 0
    else
      die "unknown argument #{argv[index].inspect}\n#{USAGE}"
    end
    index += 1
  end

  options
end

# Pure offline logic on two files, which is what makes it fully fixture-testable
# and is why ACCT-05b can be proven without touching a real certificate.
#
# This subcommand reports; it never acts. There is no code path in this file
# that revokes anything, and that absence is the mitigation for T-02-13: the API
# does expose a certificate-removal endpoint (C-G), so D-39's "never revoke
# without asking" has to be enforced by the shape of the tool rather than by
# Apple. A removal detected here is a finding for a human, not a trigger.
def run_census_diff(argv)
  options = parse_census_diff_args(argv)
  before_path = require_flag!(options[:before], "--before", "census-diff")
  after_path = require_flag!(options[:after], "--after", "census-diff")

  before = load_census(before_path, "--before")
  after = load_census(after_path, "--after")

  before_index = census_index(before)
  after_index = census_index(after)

  removed = before_index.keys - after_index.keys
  added = after_index.keys - before_index.keys

  added.each do |id|
    entry = after_index[id]
    puts "added: #{id} type=#{entry['certificate_type']} " \
         "display_name=#{entry['display_name'].inspect}"
  end

  unless removed.empty?
    removed.each do |id|
      entry = before_index[id]
      warn "asc-probe: removed: #{id} type=#{entry['certificate_type']} " \
           "display_name=#{entry['display_name'].inspect}"
    end
    warn "asc-probe: census-diff FAILED — #{removed.length} certificate " \
         "id(s) present in #{before_path} (measured #{before['measured_at']}) " \
         "are absent from #{after_path} (measured #{after['measured_at']}). " \
         "Team #{EXPECTED_TEAM} is shared; investigate before doing anything else."
    exit 1
  end

  puts "census-diff: #{before_index.length} certificate(s) before, " \
       "#{after_index.length} after; no id disappeared " \
       "(#{before['measured_at']} → #{after['measured_at']})"
end

# ---------------------------------------------------------------------------
# submission-probe — ACCT-04's write-path instrument
# ---------------------------------------------------------------------------

# Endpoint chosen: POST /v1/reviewSubmissions. It is a WRITE, and Apple's spec
# declares 403 and 409/422 as distinct responses for this operation (ASC OpenAPI
# 4.4.1, paths./v1/reviewSubmissions.post.responses: 201 | 400 | 401 | 403 | 409
# | 422 | 429). Only data.relationships.app is required; attributes.platform is
# nullable. Against a record with no build and no version the call cannot
# succeed, so it creates no state -- what it yields is a status code.
#
# Endpoint rejected: GET /v1/apps/{id}/reviewSubmissions. Every role in Apple's
# roles matrix can read it, so a read-based probe returns the same answer for a
# key that may submit and a key that may not: a gate that cannot fail, which is
# Pitfall 1 exactly. Also rejected: POST /v1/betaAppReviewSubmissions -- that is
# the TestFlight beta path and it requires a build relationship, and no build
# exists in this phase by construction.
#
# The two observations that discriminate: 403 means the key's role does not
# permit `Submit apps`; 409/422 mean it does, and the request was refused on
# business grounds (no build, no version).
#
# THAT MAPPING IS ASSUMPTION A1, NOT A FACT ASSERTED BY APPLE. The spec
# enumerates which codes this operation *can* return; it says nothing about
# which one applies in this scenario. That is precisely why the Developer-role
# negative control in 02-09 is mandatory rather than decorative, and why this
# tool renders no verdict: a status code from one key is an observation, and a
# sufficiency reading needs two. If both keys answer the same code, the probe
# did not discriminate and is discarded rather than reinterpreted -- see
# probe-compare below, which is the only place the pair is ever looked at.
SUBMISSION_PATH = "/v1/reviewSubmissions"

# attributes.platform is nullable in the spec; this probe sends it anyway, so
# the observation records which platform was asked about rather than leaving a
# later reader to guess. IOS is the default because the iOS record is the one
# 02-09 probes first.
DEFAULT_SUBMISSION_PLATFORM = "IOS"

# The exact prefix, with no truncation marker appended: a caller checking
# `body_excerpt.length <= 400` must get an exact answer, and a suffix would push
# the string past the bound it is there to satisfy. Bounded at all because a
# response body reaching a terminal may be pasted into a tracked document, and
# because request headers -- which carry the bearer token -- are never logged
# anywhere in this file (T-02-15).
def excerpt(body)
  body.to_s[0, BODY_PREVIEW].to_s
end

def submission_request_body(app_id, platform)
  {
    "data" => {
      "type" => "reviewSubmissions",
      "attributes" => { "platform" => platform },
      "relationships" => { "app" => { "data" => { "type" => "apps", "id" => app_id } } }
    }
  }
end

def parse_submission_args(argv)
  options = { app_id: nil, platform: nil, label: nil, fixture: nil }

  index = 0
  while index < argv.length
    case argv[index]
    when "--app-id"
      index += 1
      die "--app-id requires a value\n#{USAGE}" if argv[index].nil?
      options[:app_id] = utf8_arg(argv[index])
    when "--platform"
      index += 1
      die "--platform requires a value\n#{USAGE}" if argv[index].nil?
      options[:platform] = utf8_arg(argv[index])
    when "--label"
      index += 1
      die "--label requires a value\n#{USAGE}" if argv[index].nil?
      options[:label] = utf8_arg(argv[index])
    when "--fixture"
      index += 1
      die "--fixture requires a value\n#{USAGE}" if argv[index].nil?
      options[:fixture] = utf8_arg(argv[index])
    when "-h", "--help"
      puts USAGE
      exit 0
    else
      die "unknown argument #{argv[index].inspect}\n#{USAGE}"
    end
    index += 1
  end

  options
end

# Issues the write and prints what came back. Exit 0 for every completed
# request, whatever the status: the status IS the output, and deciding what it
# means from one observation is the failure this design exists to prevent.
def run_submission_probe(argv)
  options = parse_submission_args(argv)

  app_id = require_flag!(options[:app_id], "--app-id", "submission-probe")
  validate_identifier!(app_id, "--app-id")

  platform = options[:platform] || DEFAULT_SUBMISSION_PLATFORM
  unless BUNDLE_ID_PLATFORMS.include?(platform)
    die "invalid --platform #{platform.inspect}: must be one of " \
        "#{BUNDLE_ID_PLATFORMS.join(', ')}. Apple's API enum also has " \
        "UNIVERSAL, but spaceship does not expose it and D-05 declined the " \
        "Universal Purchase model it implies (C-02)."
  end

  status, body = asc_request(:post, SUBMISSION_PATH,
                             body: submission_request_body(app_id, platform),
                             fixture: options[:fixture])

  # --label exists so the two runs 02-09 makes (the real key and the
  # Developer-role control) stay self-describing in whatever file they land in.
  puts JSON.pretty_generate(
    "label" => options[:label] || "unlabelled",
    "app_id" => app_id,
    "platform" => platform,
    "team" => EXPECTED_TEAM,
    "status" => status,
    "body_excerpt" => excerpt(body),
    "measured_at" => Time.now.utc.iso8601
  )
end

# ---------------------------------------------------------------------------
# probe-compare — the pair, and the outcome that says the pair proves nothing
# ---------------------------------------------------------------------------

# Reached only with TWO observation files, so no reading of any kind can be
# produced from a single run. What it answers is one narrow question: did the
# two runs come back with different status codes?
#
# It deliberately does NOT answer "is the key sufficient". That reading depends
# on assumption A1 (see the comment above SUBMISSION_PATH) and on which key
# signed which run, and it belongs in a human-gated SUMMARY, not in a tool.
#
# The outcome that matters is the third one. 02-VALIDATION.md's ACCT-04 control
# column is explicit -- "Same code from both => discard the probe, do not
# reinterpret it" -- and 02-RESEARCH.md's A1 row says the same. So identical
# codes get their own exit code rather than being folded into either success or
# failure: an instrument that can only report pass or fail cannot express the
# one answer that matters when the control fails, and a caller forced to choose
# between the two will choose the one that lets work continue.
PROBE_DISCARDED_EXIT = 3

def load_observation(path, flag)
  die "#{flag} #{path}: no such file — nothing to compare." unless File.file?(path)

  observation = parse_json(read_utf8(path), "#{flag} #{path}")
  unless observation.is_a?(Hash)
    die "#{flag} #{path}: expected one submission-probe observation object, " \
        "got #{observation.class}"
  end
  unless observation["status"].is_a?(Integer)
    die "#{flag} #{path} carries no integer \"status\" field. Only the output " \
        "of `submission-probe` can be compared; a run that produced no status " \
        "produced no observation."
  end

  observation
end

def parse_probe_compare_args(argv)
  options = { primary: nil, control: nil }

  index = 0
  while index < argv.length
    case argv[index]
    when "--primary"
      index += 1
      die "--primary requires a value\n#{USAGE}" if argv[index].nil?
      options[:primary] = utf8_arg(argv[index])
    when "--control"
      index += 1
      die "--control requires a value\n#{USAGE}" if argv[index].nil?
      options[:control] = utf8_arg(argv[index])
    when "-h", "--help"
      puts USAGE
      exit 0
    else
      die "unknown argument #{argv[index].inspect}\n#{USAGE}"
    end
    index += 1
  end

  options
end

def observation_digest(observation)
  {
    "label" => observation["label"],
    "app_id" => observation["app_id"],
    "platform" => observation["platform"],
    "status" => observation["status"],
    "measured_at" => observation["measured_at"]
  }
end

def run_probe_compare(argv)
  options = parse_probe_compare_args(argv)
  primary_path = require_flag!(options[:primary], "--primary", "probe-compare")
  control_path = require_flag!(options[:control], "--control", "probe-compare")

  primary = load_observation(primary_path, "--primary")
  control = load_observation(control_path, "--control")

  report = {
    "team" => EXPECTED_TEAM,
    "compared_at" => Time.now.utc.iso8601,
    "primary" => observation_digest(primary),
    "control" => observation_digest(control)
  }

  if primary["status"] == control["status"]
    puts JSON.pretty_generate(report.merge("outcome" => "PROBE DISCARDED"))
    warn "asc-probe: PROBE DISCARDED — both runs returned HTTP " \
         "#{primary['status']}, so the pair does not discriminate. Do not " \
         "reinterpret it and do not record a verdict from it: with one code " \
         "answering both keys, the observation is identical whether or not the " \
         "key can do the job."
    exit PROBE_DISCARDED_EXIT
  end

  puts JSON.pretty_generate(report.merge("outcome" => "OBSERVATIONS DIFFER"))
end

# Flat entrypoint at the bottom of the file, with no __FILE__ == $0 guard --
# this script is only ever run, never required (tools/gen-review-notes.rb:243-254).
verb = ARGV[0]
case verb
when nil
  die "no subcommand given\n#{USAGE}"
when "-h", "--help"
  puts USAGE
  exit 0
when "read-back"
  run_read_back(ARGV[1..] || [])
when "census"
  run_census(ARGV[1..] || [])
when "census-diff"
  run_census_diff(ARGV[1..] || [])
when "submission-probe"
  run_submission_probe(ARGV[1..] || [])
when "probe-compare"
  run_probe_compare(ARGV[1..] || [])
else
  die "unknown subcommand #{verb.inspect}\n#{USAGE}"
end
