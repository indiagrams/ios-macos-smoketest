#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Criterion 2's vocabulary sweep (ROADMAP Phase 8.5 criterion 2, UP-05), narrowed
# from D-135's whole-phase population to D-149's mechanical bar: LITERAL ZERO
# over the ADDED lines of a fixed range.
#
# WHAT THIS ASSERTS. Every line this phase's own commits introduce -- the `+`
# lines of `git diff -U0 PHASE_BASE..<endpoint>`, never the `+++` file headers --
# over D-135's enumeration (every file the phase adds or modifies between
# PHASE_BASE and the endpoint) carries none of a private repository's domain
# vocabulary and none of that repository's own product name. There is no table
# that classifies a hit by which sense of the word was meant, and no construct
# that removes a path from the swept population by name -- D-149 rejected both,
# after planning proposed the first and found the second already load-bearing
# for a byte-identical adopted file (see the next paragraph).
#
# THE ONE EXCLUSION, AND WHY IT CANNOT CERTIFY ITSELF. A file this phase adopted
# byte-for-byte from a public upstream commit (D-131/UL-034) can carry a hunted
# word in its ordinary, public sense -- upstream's own generic doc uses one of
# these words about Apple's own device-registration flow, in a sentence this
# gate did not write and cannot edit. Excluding that file by NAME would be the
# kind of carve-out this project has repeatedly measured going stale the moment
# the excluded file changes for an unrelated reason. So the exclusion is a BLOB
# comparison against a commit SHA pinned once, copied from a prior plan's own
# recorded measurement, never typed from memory here: a file is excluded only
# when `git rev-parse <endpoint>:<path>` equals `git rev-parse <pin>:<path>`.
# Change one byte of that file for any reason and the equality breaks, the file
# re-enters the swept population, and every hit inside it -- including
# pre-existing ones -- goes red. The exclusion is proof, not trust.
#
# THE PRODUCT NAME IS NEVER EXCLUDED. Even inside a file the blob comparison
# above accepts, this gate still hunts the private product name and reports a hit
# there as an upstream finding, not as a pass. The name is matched by DIGEST, not by
# spelling: see PRODUCT_TERM_SHA256 below. A private product's own name
# reaching a public, byte-identical adopted file would be the one class of hit
# an exclusion built for a DIFFERENT purpose (staying honest about a file this
# fork does not own) must never quietly absorb.
#
# ITS OWN SOURCE IS SWEPT. This file is itself inside the population the moment
# it is committed -- it is a file the phase adds. Every generic hunted term
# below is built from single-character fragments at runtime, and the product
# name is held only as a digest, for exactly that reason: a
# bare literal in a comment explaining the word list would BE a hit, and if this
# file were carved out of its own population to avoid that, the carve-out would
# be the same shape D-149 rejected, wearing a different name.
#
# CLOSE-OUT RE-RUN. PHASE_BASE is the branch cut; the range is fixed at that end
# and open at the other -- `--endpoint <rev>` (or env
# DRIVE_HALF_VOCABULARY_ENDPOINT) lets the SAME gate re-run, unchanged, at
# whatever SHA the phase actually merges as, per D-149.
#
# Ruby stdlib only (digest, open3, optparse) -- no gem, matching this repository's own
# test/*_test.rb convention (test/contamination_test.rb's own self-assertion
# that its gate has zero require lines).

require "digest"
require "open3"
require "optparse"

ROOT_DEFAULT = File.expand_path("..", __dir__)

# The branch cut this range starts from -- main@8886de9, where this phase's
# branch was cut -- and D-149's fixed range start. Never re-measured; it is a
# citation, not a live quantity.
PHASE_BASE = "8886de9"

# Copied verbatim from plan 08.5-01's own evidence (`RESULT upstream_sha=`),
# which plan 08.5-01's adoption commit body also names -- never typed from
# memory, CONTEXT.md or RESEARCH.md, both of which record earlier, superseded
# measurements of the same moving upstream branch (D-131/D-149).
UPSTREAM_PIN = "32761369cc46c4bbffedef55843de469c4bb1eca"

def no_verdict(message)
  warn "CANNOT RUN: #{message}"
  exit 2
end

# Built from single-character fragments, never a bare literal -- see the header
# comment above ("ITS OWN SOURCE IS SWEPT").
def built(*chars)
  chars.join
end

GENERIC_TERMS = {
  built("b", "u", "t", "l", "e", "r") => "generic term",
  built("v", "a", "u", "l", "t") => "generic term",
  built("p", "r", "o", "v", "i", "s", "i", "o", "n", "i", "n", "g") => "generic term",
  built("a", "p", "p", "r", "o", "v", "a", "l") => "generic term",
  built("d", "e", "p", "r", "o", "v", "i", "s", "i", "o", "n") => "generic term",
  built("o", "w", "n", "e", "r") => "generic term"
}.freeze

# The private checkout's own name -- the product name -- is never excluded, even
# inside a file the blob check above accepts (see "THE PRODUCT NAME IS NEVER
# EXCLUDED" above). Unlike the six generic words, which are ordinary English,
# the name is the one secret, so it is held only as the SHA-256 of its
# lowercased form and matched token by token. A spelling assembled from
# fragments kept the word out of THIS gate's own hits, but it could still be
# read by anyone opening the file, and no literal sweep could find it. A
# digest is not encryption: someone who already guesses the name can confirm
# it. What it removes is the name being readable from the tree.
#
# Matching is unchanged from the literal version it replaces: `\b<name>\b` with
# /i matched exactly when some maximal ASCII word run equals the name ignoring
# case, and a word run is what `\w+` yields.
PRODUCT_TERM_SHA256 = "ff16f5aa9b3db370248b852937b5f79e251464b754e420d92cab264cd70bc3b7"

def product_term?(text)
  text.scan(/\w+/).any? { |token| Digest::SHA256.hexdigest(token.downcase) == PRODUCT_TERM_SHA256 }
end

options = { root: ROOT_DEFAULT, endpoint: nil, pin: nil }
OptionParser.new do |opts|
  opts.banner = "Usage: ruby test/drive_half_vocabulary_test.rb [--root DIR] [--endpoint REV] [--pin SHA]"
  opts.on("--root DIR", "git repository to sweep (default: this file's own repository)") { |v| options[:root] = v }
  opts.on("--endpoint REV", "range end (default: env DRIVE_HALF_VOCABULARY_ENDPOINT, else HEAD)") { |v| options[:endpoint] = v }
  opts.on("--pin SHA", "TEST-ONLY override of UPSTREAM_PIN; prints pin_source=override so CI can refuse it") { |v| options[:pin] = v }
  opts.on("-h", "--help", "print this help") do
    puts opts
    exit 0
  end
end.parse!

root = options[:root]
endpoint_arg = options[:endpoint] || ENV["DRIVE_HALF_VOCABULARY_ENDPOINT"] || "HEAD"
pin = options[:pin] || UPSTREAM_PIN
pin_source = options[:pin] ? "override" : "constant"

# Process output arrives tagged with the environment's default external
# encoding -- US-ASCII when the locale is cleared -- and a regex match against
# a non-ASCII added line then RAISES, exiting 1, which is the same status as a
# real hit: a crash would masquerade as a detection. Pin UTF-8 here, at the one
# place output enters, and scrub bytes that are not valid UTF-8 (a hunted word
# is ASCII, so scrubbing cannot hide one). Measured 2026-09-15: before this,
# a cleared-locale run over a non-ASCII added line died in the hunk parser.
def git(root, *args)
  out, err, status = Open3.capture3("git", *args, chdir: root)
  [out.force_encoding(Encoding::UTF_8).scrub, err.force_encoding(Encoding::UTF_8).scrub, status]
end

def git!(root, *args, on_fail:)
  out, err, status = git(root, *args)
  no_verdict("#{on_fail}: #{err.strip}") unless status.success?
  out
end

git!(root, "cat-file", "-e", "#{PHASE_BASE}^{commit}",
     on_fail: "base #{PHASE_BASE} is not a reachable commit in #{root}")

endpoint_out, endpoint_err, endpoint_status = git(root, "rev-parse", "--verify", "#{endpoint_arg}^{commit}")
no_verdict("endpoint #{endpoint_arg} does not resolve to a commit in #{root}: #{endpoint_err.strip}") unless endpoint_status.success?
endpoint = endpoint_out.strip

git!(root, "cat-file", "-e", "#{pin}^{commit}",
     on_fail: "pin #{pin} is not a reachable commit in #{root}")

population_out = git!(root, "diff", "--name-only", "--no-renames", "--diff-filter=AM", PHASE_BASE, endpoint,
                       on_fail: "git diff --name-only #{PHASE_BASE}..#{endpoint} failed")
population = population_out.split("\n").reject(&:empty?).sort
no_verdict("population is empty over #{PHASE_BASE}..#{endpoint} in #{root} -- nothing to sweep") if population.empty?

puts "drive_half_vocabulary_range=#{PHASE_BASE}..#{endpoint}"
population.each { |path| puts path }
puts "drive_half_vocabulary_population=#{population.length}"

identical = {}
population.each do |path|
  e_out, _e_err, e_status = git(root, "rev-parse", "#{endpoint}:#{path}")
  p_out, _p_err, p_status = git(root, "rev-parse", "#{pin}:#{path}")
  next unless e_status.success? && p_status.success?
  next unless e_out.strip == p_out.strip

  identical[path] = e_out.strip
end
identical.keys.sort.each { |path| puts "IDENTICAL #{path} blob=#{identical[path]}" }
puts "drive_half_vocabulary_upstream_identical=#{identical.length}"
puts "drive_half_vocabulary_pin=#{pin} pin_source=#{pin_source}"

# Parses `git diff -U0` hunks into [new_line_number, text] pairs for every `+`
# line INSIDE a hunk. The `+++ b/<path>` header is excluded only while no hunk
# has been seen yet; once inside a hunk, a line whose own text begins `++` is an
# added line, not a header, and is kept -- excluding `+++` by a blanket prefix
# test anywhere in the file would silently drop such a line.
def added_lines(root, base, endpoint, path)
  out = git!(root, "diff", "-U0", "--no-renames", "--no-color", "--no-ext-diff",
             "--diff-filter=AM", base, endpoint, "--", path,
             on_fail: "git diff -U0 #{base}..#{endpoint} -- #{path} failed")
  # A per-LINE, anchored check -- git's own binary-diff marker is a whole line
  # of exactly this shape. A substring-anywhere test would also match this
  # very sentence once this file is itself inside the swept population (it
  # was, and did: measured this session against a live plant).
  is_binary = out.each_line.any? { |line| line.start_with?("Binary files ") && line.rstrip.end_with?(" differ") }
  return { binary: true, lines: [] } if is_binary

  lines = []
  new_no = nil
  in_hunk = false
  out.each_line do |line|
    if line.start_with?("@@")
      match = line.match(/^@@ -\d+(?:,\d+)? \+(\d+)/)
      new_no = match ? match[1].to_i : 1
      in_hunk = true
      next
    end
    next unless in_hunk

    if line.start_with?("+")
      lines << [new_no, line[1..].to_s.chomp]
      new_no += 1
    elsif line.start_with?("-")
      # a removed line does not occupy a new-side line number
    end
  end
  { binary: false, lines: lines }
end

failures = 0
added_lines_total = 0
binary_paths = []

population.each do |path|
  info = added_lines(root, PHASE_BASE, endpoint, path)
  if info[:binary]
    binary_paths << path
    next
  end

  added_lines_total += info[:lines].length
  file_is_identical = identical.key?(path)

  info[:lines].each do |line_no, text|
    if file_is_identical
      if product_term?(text)
        failures += 1
        puts "FAIL vocabulary #{path}:#{line_no}: product name (upstream finding)"
      end
      next
    end

    GENERIC_TERMS.each do |term, label|
      next unless text =~ /\b#{Regexp.escape(term)}\b/i

      failures += 1
      puts "FAIL vocabulary #{path}:#{line_no}: #{label}"
    end
    if product_term?(text)
      failures += 1
      puts "FAIL vocabulary #{path}:#{line_no}: product-specific term"
    end
  end
end

binary_paths.sort.each { |path| puts "BINARY #{path}" }
puts "drive_half_vocabulary_binary_files=#{binary_paths.length}"
puts "drive_half_vocabulary_added_lines=#{added_lines_total}"
puts "drive_half_vocabulary_hits=#{failures}"

exit(failures.zero? ? 0 : 1)
