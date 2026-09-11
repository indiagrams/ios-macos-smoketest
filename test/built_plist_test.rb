#!/usr/bin/env ruby
# frozen_string_literal: true

# built_plist_test.rb — the submission-critical Info.plist keys, asserted on the
# BUILT bundle rather than on the manifest that is supposed to produce it.
#
# WHY THIS FILE EXISTS AND WHY IT TAKES A PATH. Both `Generated-Info.plist`
# files are GENERATED and GITIGNORED (`git ls-files app/iOS/Generated-Info.plist`
# → empty), so there is no tracked plist to assert over, and the tracked thing
# that produces them — the two generator manifests — says `$(PRIVACY_POLICY_URL)`
# rather than a URL. Only the build resolves it. This repository has already
# paid twice for asserting the manifest instead of the artefact: XcodeGen bakes
# the host TARGET NAME into `TEST_HOST` at generation time while `PRODUCT_NAME`
# resolves at BUILD time (UL-043/UL-049), and `INFOPLIST_KEY_*` injection is
# INERT when a target does not generate its own plist — the setting resolved in
# `-showBuildSettings` while the built iOS plist had no key. Both were invisible
# to the manifests, to the file-level tests and to `tools/identity-parity.rb`.
# UL-063 adds the third edge: a built-artefact gate pointed at a DEBUG build is
# a claim about a build nobody ships, so callers must hand this gate a RELEASE
# bundle.
#
# WHAT IT ASSERTS, and the reason each one is the assertion rather than a
# cheaper neighbour:
#
#   1. `PrivacyPolicyURL` is present. Named with the key, the bundle path and
#      the platform, because "a key is missing" and "a bundle is missing" are
#      different defects.
#   2. Its scheme is exactly `https`, AND its authority is non-empty. The second
#      half is not redundant, and this is the sharpest thing in the file:
#      `//` opens a comment at ANY position in an xcconfig value, so a plainly
#      written `PRIVACY_POLICY_URL = https://host/privacy/` resolves — in Xcode,
#      measured 2026-09-11 on 26.1.1 — to the four characters `https:`. That
#      value is NON-EMPTY, so a presence check passes it, and it parses with
#      scheme `https` (`URI.parse("https:").scheme` is `"https"` and its `.host`
#      is nil), so a scheme check passes it too. An app shipping it opens
#      nothing. The host assertion is the only one of the three that fails.
#   3. It EQUALS `Xcconfig.value(app/Identity.xcconfig, PRIVACY_POLICY_URL)`.
#      Presence alone would pass on a hardcoded Swift or manifest literal, which
#      `PROJECT.md`'s parameterization constraint forbids; equality with the one
#      identity source is what proves the parameterization actually carried.
#   4. On macOS, `LSApplicationCategoryType` is the D-123 category. Apple
#      requires the key for Mac App Store distribution and requires it to match
#      the category selected in App Store Connect; ROADMAP criterion 3(c)
#      requires the bundle key to agree with it. On iOS the key is RECORDED AND
#      PRINTED but never asserted: `GENERATE_INFOPLIST_FILE = NO` makes the iOS
#      `INFOPLIST_KEY_*` form inert BY DESIGN, so failing there would be
#      asserting against a measured fact rather than against a defect.
#   5. On both platforms, `ITSAppUsesNonExemptEncryption` is present and
#      literally `false` — META-07's export-compliance half, asserted on the
#      artefact. Absent and false are checked separately: `nil` is falsy in Ruby
#      and would satisfy a `!value` test while Apple prompts on every upload.
#
# THE PLIST READ IS STRUCTURAL, WITH TWO ROUTES, AND THE ROUTE IS PRINTED. A
# built Info.plist is usually a BINARY plist, so route 1 (REXML, for an XML
# plist) returns nil and route 2 (`plutil -convert xml1 -o -` through an argv
# array, then REXML) answers. A route that fails FALLS THROUGH; it is never
# treated as a negative result, which is how "the parser could not read it"
# would otherwise wear the costume of "the key is not there". Nothing here
# greps a plist as text.
#
# REFUSAL, NOT A PASS. With no `--built-app`, or with a path that is not a
# bundle, this exits 2 with `CANNOT RUN:` — a plist scan over an unsupplied
# bundle asserts nothing and prints success. A CALLER MUST TREAT EXIT 2 AS NOT
# A PASS. Exit 0 means the artefact was read and every assertion held; exit 1
# means it was read and something failed; exit 2 means nothing was inspected.
#
# DEPENDENCY DISCIPLINE. Exactly ONE `require`, of `rexml/document`, matching
# `test/privacy_manifest_test.rb`. `bin/lib/xcconfig.rb` is `load`ed rather than
# required — the idiom `fastlane/Appfile` already uses — so the one-require
# promise holds and the gate can run in a job with `bundler-cache: false`. It is
# the ONE reader of the identity file (D-57/UL-035); this file contains no
# second xcconfig parser. There is deliberately no `require "uri"`: see
# assertion 2 above, where URI's own answer for the truncated value is the wrong
# one, and the component decomposition below is both the correct instrument and
# one fewer dependency.
#
# NOT WIRED INTO ANY WORKFLOW BY THE PLAN THAT CREATED IT. Plan 08-16 owns CI
# wiring and must land this as a NEW NON-REQUIRED job, run once on a real push
# before anything is made required. Adding it to the already-required
# `built app entitlements` job would make a never-executed gate a merge blocker
# on its first push, which is exactly how `locale-doctor-regression` left every
# pull request unmergeable.
#
# Runnable from the repository root or from test/, under BOTH pinned
# interpreters:
#   /opt/homebrew/opt/ruby@3.3/bin/ruby test/built_plist_test.rb --built-app <path>.app
#   /opt/homebrew/opt/ruby@4.0/bin/ruby test/built_plist_test.rb --built-app <path>.app
#
# Options:
#   --built-app PATH  a built .app bundle (iOS or macOS) whose Info.plist is read
#   --identity PATH   read a different xcconfig (used by the red controls only)

require "rexml/document"

USAGE = "Usage: ruby test/built_plist_test.rb --built-app PATH [--identity PATH]"

# The five named facts, printed on EVERY run including a refusal, so a log can
# never be ambiguous about whether the gate reached its subject. `unread` is a
# value, not an absence — a run that printed nothing and a run that read nothing
# look identical otherwise.
@facts = {
  "built_plist_platform"    => "unread",
  "built_plist_privacy_url" => "unread",
  "built_plist_category"    => "unread",
  "built_plist_encryption"  => "unread",
  "built_plist_parse_route" => "unread",
}

def print_facts
  @facts.each { |k, v| puts "#{k}=#{v}" }
end

def no_verdict(message)
  print_facts
  warn "CANNOT RUN: #{message}"
  exit 2
end

built_app = ENV["BUILT_PLIST_APP"]
identity  = nil
argv      = ARGV.dup
until argv.empty?
  case (arg = argv.shift)
  when "--built-app"  then built_app = argv.shift or no_verdict("--built-app needs a path. #{USAGE}")
  when "--identity"   then identity  = argv.shift or no_verdict("--identity needs a path. #{USAGE}")
  when "-h", "--help" then puts USAGE ; exit 0
  else no_verdict("unrecognised argument #{arg.inspect}. #{USAGE}")
  end
end

ROOT     = File.expand_path("..", __dir__)
IDENTITY = identity.nil? ? File.join(ROOT, "app", "Identity.xcconfig") : File.expand_path(identity)

# `load`, not `require_relative`: see the dependency-discipline note above.
load File.expand_path("bin/lib/xcconfig.rb", ROOT)

# ─── frozen, dated measurements ──────────────────────────────────────────────
# A value, its measurement date and the thing it was measured against are ONE
# UNIT (docs/APPLE-ACCOUNT-STATE.md:41-46). The category is spelled here rather
# than read out of the manifests on purpose: a gate that derived its expectation
# from its own subject would accept whatever the subject happened to say — the
# rule bin/preflight-identity.rb:84-86 states for REQUIRED_VARS.

MEASURED_ON = "2026-09-11"

# D-123, and ROADMAP criterion 3(c) as amended 2026-09-11 under D-129.
EXPECTED_CATEGORY = "public.app-category.developer-tools"

# The xcconfig key and the Info.plist key it feeds. Names locked by 08-06.
URL_XCCONFIG_KEY = "PRIVACY_POLICY_URL"
URL_PLIST_KEY    = "PrivacyPolicyURL"
CATEGORY_KEY     = "LSApplicationCategoryType"
ENCRYPTION_KEY   = "ITSAppUsesNonExemptEncryption"

REQUIRED_SCHEME = "https"

# ─── assertion harness (test/privacy_manifest_test.rb:258-281, verbatim) ─────

@failures = 0
@checks   = 0

def assert(condition, group, path, label)
  @checks += 1
  if condition
    puts "  ✓ #{group} #{path}: #{label}"
  else
    puts "FAIL #{group} #{path}: #{label.to_s.gsub(/\s*\n\s*/, ' ')}"
    @failures += 1
  end
end

def verdict!
  print_facts
  puts
  if @failures.zero?
    puts "All #{@checks} built-plist assertions passed."
    exit 0
  else
    puts "#{@failures} of #{@checks} built-plist assertion(s) failed."
    exit 1
  end
end

# argv array, never a shell string: quoting has silently changed a candidate set
# in this repository before.
def capture(*argv)
  out = IO.popen(argv, err: File::NULL, &:read)
  [out.to_s, $?&.exitstatus]
rescue SystemCallError => e
  ["", "unavailable: #{e.message}"]
end

# ─── the structural plist parse ──────────────────────────────────────────────
# Elements, not text. REXML walks elements, so an XML comment is structurally
# invisible to it — which is the whole reason this is a parse and not a regex
# that happens to work today.

def plist_value(el)
  case el.name
  when "dict"    then el.elements.to_a.each_slice(2).to_h { |k, v| [k.text.to_s.strip, plist_value(v)] }
  when "array"   then el.elements.map { |e| plist_value(e) }
  when "string"  then el.text.to_s
  when "true"    then true
  when "false"   then false
  when "integer" then el.text.to_i
  when "real"    then el.text.to_f
  else "<#{el.name}>"
  end
end

def parse_plist_text(text)
  doc  = REXML::Document.new(text)
  root = doc.elements["plist"]
  return nil if root.nil?
  first = root.elements[1]
  return nil if first.nil?
  plist_value(first)
rescue REXML::ParseException, RuntimeError
  nil
end

# Route 1 REXML (an XML plist), route 2 plutil -> REXML (a binary one). A route
# that fails falls THROUGH to the next; only both failing is an answer, and it
# is a refusal rather than a negative result.
def read_plist(path)
  raw = begin
    File.read(path, encoding: "UTF-8")
  rescue ArgumentError, Errno::ENOENT, Errno::EACCES
    nil
  end

  if raw
    direct = parse_plist_text(raw)
    return [direct, "rexml"] if direct.is_a?(Hash)
  end

  converted, status = capture("/usr/bin/plutil", "-convert", "xml1", "-o", "-", path)
  if status == 0
    via_plutil = parse_plist_text(converted)
    return [via_plutil, "plutil"] if via_plutil.is_a?(Hash)
  end

  [nil, "none"]
end

# ─── URL decomposition, by components rather than by prefix ──────────────────
# Returns { scheme:, authority:, path: } or nil. Deliberately NOT `URI.parse`:
# for the truncated value this gate exists to catch, `URI.parse("https:")`
# answers scheme `"https"` with a nil host, so the component this cares most
# about is the one URI reports as absent WITHOUT raising. Decomposing here keeps
# the authority a first-class answer and keeps the require count at one.
def decompose_url(value)
  str = value.to_s
  scheme, rest = str.split(":", 2)
  return nil if scheme.nil? || scheme.empty? || rest.nil?
  return nil unless scheme.match?(/\A[A-Za-z][A-Za-z0-9+.-]*\z/)
  return nil unless rest.start_with?("//")

  after_slashes    = rest[2..].to_s
  cut              = after_slashes.index("/")
  authority        = cut.nil? ? after_slashes : after_slashes[0, cut]
  path             = cut.nil? ? "" : after_slashes[cut..]
  { scheme: scheme, authority: authority, path: path }
end

# ─── resolve the bundle and its platform ─────────────────────────────────────

no_verdict("no built .app supplied. A plist scan over an unsupplied bundle " \
           "asserts nothing and prints success, so this refuses instead. " \
           "#{USAGE}") if built_app.nil? || built_app.to_s.empty?

BUNDLE = File.expand_path(built_app.to_s)

no_verdict("#{BUNDLE} is not a directory — a built .app is a directory. " \
           "Nothing was produced here, so NOTHING WAS INSPECTED") unless File.directory?(BUNDLE)

# Platform by bundle SHAPE, never by name or by a flag the caller could get
# wrong: a macOS bundle nests its Info.plist under Contents/. Same predicate
# test/app_offline_test.rb and test/privacy_manifest_test.rb already use.
MAC_PLIST = File.join(BUNDLE, "Contents", "Info.plist")
IOS_PLIST = File.join(BUNDLE, "Info.plist")

PLATFORM, PLIST_PATH =
  if File.file?(MAC_PLIST)   then ["macos", MAC_PLIST]
  elsif File.file?(IOS_PLIST) then ["ios", IOS_PLIST]
  else [nil, nil]
  end

no_verdict("#{BUNDLE} has an Info.plist at neither #{File.join('Contents', 'Info.plist')} " \
           "(macOS shape) nor Info.plist (iOS shape), so it is not a built app " \
           "bundle. NOTHING WAS INSPECTED") if PLATFORM.nil?

@facts["built_plist_platform"] = PLATFORM

REL = File.join(File.basename(BUNDLE), PLIST_PATH.sub("#{BUNDLE}/", ""))

plist, route = read_plist(PLIST_PATH)
@facts["built_plist_parse_route"] = route

no_verdict("#{PLIST_PATH} could not be parsed structurally by either route " \
           "(rexml, then plutil -convert xml1). A plist this gate cannot read " \
           "is not a plist whose keys are absent — NOTHING WAS INSPECTED") if plist.nil?

# ─── the population, enumerated and counted BEFORE anything indexes into it ──
# A vacuous plist — parsed, but empty — would satisfy every "is this key wrong"
# assertion below by having no keys at all. The count is printed so it moves.

keys = plist.keys.sort
puts "built_plist_keys=#{keys.length}"
puts "built_plist_bundle=#{BUNDLE}"
puts "built_plist_measured_on=#{MEASURED_ON}"
puts

puts "built-plist — #{PLATFORM} bundle #{File.basename(BUNDLE)}, read via #{route}:"

assert keys.length >= 5, "builtplist", REL,
       "the parsed plist carries at least 5 keys (found #{keys.length}). An empty " \
       "dictionary would pass every absence-shaped assertion below by having " \
       "nothing in it"

# ─── 1 + 2 + 3: the privacy policy URL ───────────────────────────────────────

bundle_url = plist[URL_PLIST_KEY]
@facts["built_plist_privacy_url"] = bundle_url.nil? ? "ABSENT" : bundle_url.to_s

assert plist.key?(URL_PLIST_KEY) && !bundle_url.to_s.empty?, "builtplist", REL,
       "the #{PLATFORM} bundle declares #{URL_PLIST_KEY}. It is #{bundle_url.inspect} in " \
       "#{PLIST_PATH}. The in-app privacy control reads this key out of the app's own " \
       "bundle (D-120); without it the control has nothing to open"

parts = decompose_url(bundle_url)

assert !parts.nil?, "builtplist", REL,
       "#{URL_PLIST_KEY} decomposes into scheme + authority + path. It is " \
       "#{bundle_url.inspect}, which has no `scheme://authority` shape at all"

assert !parts.nil? && parts[:scheme] == REQUIRED_SCHEME, "builtplist", REL,
       "#{URL_PLIST_KEY}'s scheme is exactly #{REQUIRED_SCHEME.inspect} — found " \
       "#{parts.nil? ? 'no scheme' : parts[:scheme].inspect} in #{bundle_url.inspect}. " \
       "A non-https privacy URL is a broken link shipped to App Review"

assert !parts.nil? && !parts[:authority].to_s.empty?, "builtplist", REL,
       "#{URL_PLIST_KEY} has a non-empty AUTHORITY — found " \
       "#{parts.nil? ? 'none' : parts[:authority].inspect} in #{bundle_url.inspect}. " \
       "This is the assertion that catches the xcconfig `//` truncation: `https:` is " \
       "non-empty AND carries scheme https, so presence and scheme checks both pass it " \
       "while the app opens nothing (measured on Xcode 26.1.1, #{MEASURED_ON})"

xcconfig_url = Xcconfig.value(IDENTITY, URL_XCCONFIG_KEY)

assert !xcconfig_url.nil? && !xcconfig_url.empty?, "builtplist", REL,
       "#{IDENTITY} assigns #{URL_XCCONFIG_KEY} a non-empty value — it is " \
       "#{xcconfig_url.inspect}. There is nothing to compare the bundle against otherwise"

assert bundle_url.to_s == xcconfig_url.to_s, "builtplist", REL,
       "the bundle's #{URL_PLIST_KEY} EQUALS #{URL_XCCONFIG_KEY} in the tracked identity " \
       "file. bundle=#{bundle_url.inspect} xcconfig=#{xcconfig_url.inspect} " \
       "(#{IDENTITY}). Presence alone would pass on a hardcoded literal, which PROJECT.md's " \
       "parameterization constraint forbids; equality is what proves the value travelled " \
       "from the one identity source into the shipped artefact"

# ─── 4: the App Store category ───────────────────────────────────────────────

category = plist[CATEGORY_KEY]
@facts["built_plist_category"] = category.nil? ? "ABSENT" : category.to_s

if PLATFORM == "macos"
  assert category.to_s == EXPECTED_CATEGORY, "builtplist", REL,
         "the macOS bundle declares #{CATEGORY_KEY} = #{EXPECTED_CATEGORY.inspect}; found " \
         "#{category.nil? ? 'NO SUCH KEY' : category.inspect}. Apple requires this key for " \
         "Mac App Store distribution and requires it to match the category selected in App " \
         "Store Connect; D-123 locks the category and ROADMAP criterion 3(c) requires the " \
         "bundle key to agree with it. A disagreement is a submission-time mismatch"
else
  # RECORDED, NOT ASSERTED. `GENERATE_INFOPLIST_FILE = NO` makes the iOS
  # `INFOPLIST_KEY_LSApplicationCategoryType` form inert by design — the setting
  # resolves in -showBuildSettings and never reaches the bundle. A failure here
  # would be an assertion against a measured fact, not against a defect. The
  # value is printed above so a future change of that mechanism is visible.
  puts "  · builtplist #{REL}: #{CATEGORY_KEY} on iOS is " \
       "#{category.nil? ? 'absent, as expected under GENERATE_INFOPLIST_FILE = NO' : category.inspect} " \
       "— recorded, never asserted"
end

# ─── 5: export compliance ────────────────────────────────────────────────────

encryption = plist[ENCRYPTION_KEY]
@facts["built_plist_encryption"] = plist.key?(ENCRYPTION_KEY) ? encryption.inspect : "ABSENT"

assert plist.key?(ENCRYPTION_KEY), "builtplist", REL,
       "the #{PLATFORM} bundle declares #{ENCRYPTION_KEY}. Without it Apple prompts the " \
       "export-compliance question on every upload (META-07)"

assert encryption == false, "builtplist", REL,
       "#{ENCRYPTION_KEY} is literally false — found " \
       "#{plist.key?(ENCRYPTION_KEY) ? encryption.inspect : 'NO SUCH KEY'}. Absent and false " \
       "are asserted separately on purpose: nil is falsy in Ruby and would satisfy a `!value` " \
       "test while the key is missing from the shipped bundle"

verdict!
