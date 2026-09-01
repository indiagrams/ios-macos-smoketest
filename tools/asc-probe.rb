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
#
# Secrets: this file never prints the bearer token, the .p8, or
# ASC_API_KEY_P8_BASE64. Token acquisition is isolated in bearer_token, no
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

  common options:
    --fixture <path>  read a saved response envelope from disk instead of
                      calling #{API_HOST}. Offline; needs no credentials.
    -h, --help        print this message

  exit codes:
    0  the resource was found AND every --expect-* assertion held
    1  a usage error, a transport failure, or an assertion that did not hold
    2  the resource was not found (App Store Connect returned an empty "data")

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
def bearer_token
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

  token = Spaceship::ConnectAPI::Token.create(
    key_id: ENV.fetch("ASC_API_KEY_ID"),
    issuer_id: ENV.fetch("ASC_API_KEY_ISSUER_ID")
  )
  # Only the JWT's text leaves this function, and it goes straight into a
  # request header. It is never logged, printed, or interpolated into a message.
  token.text
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
else
  die "unknown subcommand #{verb.inspect}\n#{USAGE}"
end
