#!/usr/bin/env ruby
# frozen_string_literal: true

# The store URLs: agreement offline, reachability on request.
#
# META-06's Automated Command in 08-VALIDATION.md reads `curl -sI "$URL" | head -1`,
# and that string was in NO file. Measured 2026-09-16 across `ci/ .github/workflows/
# test/ Makefile bin/`: zero hits, against a positive control of 7 files mentioning
# the host. A command named in a validation map and present nowhere is the same
# failure mode as an assertion that cannot fail -- the map claims coverage that no
# process performs.
#
# WHY TWO MODES, AND WHY THE DEFAULT IS THE OFFLINE ONE.
# Every gate in test/ is offline by construction -- app_offline_test.rb,
# app_source_rules_test.rb, screenshot_set_test.rb -- and the required `review notes`
# job runs with `bundler-cache: false` on exactly that basis. A network call inside a
# required context would make the workflow's own offline claim untrue, and would block
# a merge on someone else's DNS. So: the default mode touches nothing, and `--live` is
# called ONLY by the scheduled non-required workflow and by hand from the runbook
# (D-166).
#
# WHY THE OFFLINE HALF IS NOT MERELY A SHAPE CHECK. A rename that updates `fastlane/`
# but not `app/Identity.xcconfig` ships a LISTING url and a PLIST url pointing at
# different origins, and nothing existing catches it: built_plist_test.rb's equality
# assertion compares the built bundle against the xcconfig, so it stays green while
# both disagree with the store listing. The agreement clause below is the only place
# those two trees are compared.
#
# AND WHY `authority` IS ASSERTED SEPARATELY FROM `scheme`. `//` opens a comment at
# any position in an xcconfig value, so `PRIVACY_POLICY_URL = https://host/privacy/`
# resolves to the four characters `https:` -- which URI.parse accepts happily as a
# scheme with a nil host. That is a real defect this repository has already paid for
# (the $(URL_SLASH) indirection at Identity.xcconfig:69 exists because of it), and a
# reader that checks only the scheme would pass it.
#
# D-167 requires this instrument to have been SEEN FAILING before it is trusted.
# Three reds are recorded in evidence/08.6-08-meta06.txt: an http scheme, a host
# mismatch, and a dead host under --live bounded by an explicit timeout.
#
# GREP-GATE HYGIENE. No clause here is a whole-file grep; each one parses the value it
# judges, so this comment's own mention of `http://` and of a dead host cannot satisfy
# or violate anything below.

require "uri"
require "net/http"
require "openssl"

ROOT = File.expand_path("..", __dir__)

# One HEAD per distinct URL, and no request may hang: a scheduled job that blocks is
# worse than one that fails, because nothing reports it.
OPEN_TIMEOUT = 5
READ_TIMEOUT = 5

@checks   = 0
@failures = 0

def assert(condition, label)
  @checks += 1
  if condition
    puts "  ✓ #{label}"
  else
    puts "  ✗ #{label}"
    @failures += 1
  end
end

root = ROOT
live = false
args = ARGV.dup
until args.empty?
  case (arg = args.shift)
  when "--root" then root = File.expand_path(args.shift.to_s)
  when "--live" then live = true
  when "--help", "-h"
    puts "usage: store_urls_test.rb [--root DIR] [--live]"
    exit 0
  else
    warn "unknown argument #{arg.inspect}"
    exit 2
  end
end

# UTF-8 pinned, never inherited -- with LANG unset Encoding.default_external is
# US-ASCII (UL-012 / UL-048).
def read_text(path)
  File.read(path, encoding: "UTF-8").strip
end

listing_files = Dir.glob(File.join(root, "fastlane/metadata*/en-US/*_url.txt")).sort
xcconfig_path = File.join(root, "app/Identity.xcconfig")

puts "store URLs — root=#{root} mode=#{live ? 'live' : 'offline'}"
puts

assert !listing_files.empty?, "at least one tracked *_url.txt exists under fastlane/metadata*/en-US/"

# The xcconfig goes through bin/lib/xcconfig.rb and no second parser (D-57): three
# hand-rolled readers of this file once disagreed with each other and with Xcode.
require_relative "../bin/lib/xcconfig"
xcconfig_privacy = File.exist?(xcconfig_path) ? Xcconfig.value(xcconfig_path, "PRIVACY_POLICY_URL") : nil
assert !xcconfig_privacy.nil? && !xcconfig_privacy.empty?,
       "app/Identity.xcconfig defines PRIVACY_POLICY_URL (read through bin/lib/xcconfig.rb)"

entries = listing_files.map { |path| [path.sub("#{root}/", ""), read_text(path)] }
entries << ["app/Identity.xcconfig:PRIVACY_POLICY_URL", xcconfig_privacy] if xcconfig_privacy

hosts = {}
entries.each do |label, value|
  uri = begin
    URI.parse(value)
  rescue URI::InvalidURIError
    nil
  end

  assert !uri.nil?, "#{label}: parses as a URI (#{value.inspect})"
  next if uri.nil?

  assert uri.scheme == "https", "#{label}: scheme is https (#{uri.scheme.inspect})"
  # A nil host is the $(URL_SLASH) truncation defect, not a typo: `https:` alone.
  assert !uri.host.nil? && !uri.host.empty?,
         "#{label}: has an authority (#{value.inspect} -> host #{uri.host.inspect})"
  hosts[uri.host] = (hosts[uri.host] || []) << label if uri.host
end

distinct = hosts.keys.sort
assert distinct.length == 1,
       "every tracked store URL resolves to ONE host (found #{distinct.length}: #{distinct.join(', ')})"

# The two trees compared directly. built_plist_test.rb cannot see this: it compares
# the built bundle to the xcconfig, so both can drift from the listing together.
listing_privacy_path = File.join(root, "fastlane/metadata/en-US/privacy_url.txt")
if File.exist?(listing_privacy_path) && xcconfig_privacy
  listing_privacy = read_text(listing_privacy_path)
  assert listing_privacy == xcconfig_privacy,
         "the listing privacy URL and the xcconfig's PRIVACY_POLICY_URL agree " \
         "(#{listing_privacy.inspect} vs #{xcconfig_privacy.inspect})"
end

if live
  puts
  # One request per DISTINCT url: the same marketing URL appears in both metadata
  # trees, and a liveness check that scales with FILES rather than endpoints would
  # hit the same host repeatedly for no extra information.
  entries.map { |_, value| value }.uniq.sort.each do |url|
    uri = begin
      URI.parse(url)
    rescue URI::InvalidURIError
      nil
    end
    next if uri.nil? || uri.host.nil?

    started = Time.now
    status = nil
    note = nil
    hops = 0
    begin
      target = uri
      loop do
        response = Net::HTTP.start(target.host, target.port,
                                   use_ssl: target.scheme == "https",
                                   open_timeout: OPEN_TIMEOUT,
                                   read_timeout: READ_TIMEOUT) do |http|
          http.request(Net::HTTP::Head.new(target))
        end
        status = response.code.to_i
        # At most ONE redirect followed, and it is recorded rather than hidden: a
        # listing URL that has started redirecting is a finding even when the
        # destination is healthy.
        break unless status >= 300 && status < 400 && hops.zero? && response["location"]

        hops += 1
        note = "redirect->#{response['location']}"
        target = URI.join(target.to_s, response["location"])
      end
    rescue SocketError, SystemCallError, IOError, Timeout::Error, OpenSSL::SSL::SSLError => e
      # Narrow on purpose: these are the ways a request fails to produce a response.
      note = "#{e.class}: #{e.message}"
    end

    elapsed = format("%.2f", Time.now - started)
    puts "store_url_live url=#{url} status=#{status || 'none'} elapsed=#{elapsed}#{note ? " note=#{note}" : ''}"
    assert !status.nil? && status >= 200 && status < 300,
           "#{url}: reachable with a 2xx (status #{status || 'none'}#{note ? ", #{note}" : ''})"
  end
end

puts
puts "store_urls_files=#{listing_files.length}"
puts "store_urls_distinct_hosts=#{distinct.join(',')}"
puts "store_urls_mode=#{live ? 'live' : 'offline'}"
puts
if @failures.zero?
  puts "All #{@checks} store-URL assertions passed."
  exit 0
else
  puts "#{@failures} of #{@checks} assertion(s) failed."
  exit 1
end
