#!/usr/bin/env ruby
# frozen_string_literal: true

# APP-11 and APP-12 — the two halves of ROADMAP Phase 6 criterion 5 that are TRUE
# TODAY and would stop being true silently.
#
# WHY THIS EXISTS
#
#   Criterion 5 says the app "builds under `-swift-version 6
#   -strict-concurrency=complete` with no [either of the two concurrency escape
#   hatches] anywhere, and carries no network capability or entitlement on either
#   platform." Both clauses hold on this tree — measured, not assumed, below and in
#   evidence/06-17-offline-swift6.txt. Neither clause has anything watching it.
#
#   APP-11 holds because nobody changed the entitlements. That is not a property the
#   build enforces: adding one key to one file removes it, and every gate in this
#   repository would stay green. APP-12's build half IS enforced continuously — the
#   two unit-test targets and both app targets inherit the project base settings, so
#   a file that fails strict concurrency fails the required `app (…)` matrix. Its
#   second half is not enforced by anything: both escape hatches COMPILE CLEAN. That
#   is the point of them.
#
# THE TRAP THIS FILE IS BUILT AROUND (06-RESEARCH Pitfall 11)
#
#   `app/macOS/App.entitlements` carries, inside an XML COMMENT, the very key this
#   requirement forbids:
#
#       <!-- Add capabilities as needed:
#           <key>com.apple.security.…</key><true/>   -->
#
#   `app/iOS/App.entitlements` does the same for an iOS networking capability. A
#   `grep -q` of either file's TEXT goes RED ON A CORRECT TREE. So every assertion
#   here runs against PARSED STRUCTURE: XML comments are removed first, and where
#   `plutil` exists the stdlib parse is cross-checked against Apple's own parser and
#   the two key sets must be identical. There is no grep of entitlements text
#   anywhere in this file.
#
#   The same trap, one layer up, is why the Swift scan strips comments before it
#   counts: a file explaining WHY the two hatches are banned would otherwise be the
#   thing that makes the ban look violated. 06-09 met this in
#   `app/Shared/Engine/PercentCodec.swift`, 06-14 met it in a UI-test file, and
#   06-17 measured one surviving instance in `app/EngineTests/HTMLEntityTests.swift`
#   and fixed it AT SOURCE rather than around it.
#
#   And one layer up again: this file must NAME the two hatches to look for them.
#   It does not spell either one. Both are built from character arrays at run time
#   (D-92's shape, as `tools/check-contamination.rb` does for the prose terms), so
#   the file that configures the content gate is not swept green by its own source.
#   That route is recorded as `escape_tokens=assembled`.
#
# WHAT IS ASSERTED, AND OVER WHICH POPULATION
#
#   O1  both entitlements files exist, are non-empty, and parse            per file
#   O2  the parsed key set carries NONE of the frozen capability keys      per file
#   O3  the parsed key set IS EXACTLY the frozen dated allowlist           per file
#   O4  the file's sha256 still equals its frozen dated measurement        per file
#   O5  where plutil exists, Apple's parse and this one agree exactly      per file
#   O6  the tracked Swift population under app/ is non-empty and large     once
#   O7  neither hatch appears in comment-stripped Swift source             per file
#   O8  criterion 5's SCOPE: which targets "the app" ranges over           per manifest
#   O9  the built .app's EMBEDDED entitlements, when one is supplied       per app
#
#   O2 and O3 are asserted PER FILE, never as a union: a file that stopped being
#   read looks exactly like a file with nothing in it.
#
# ON O8, AND ON WHAT CRITERION 5 RANGES OVER
#
#   `app/project.yml` and `app/Project.swift` both set base SWIFT_VERSION 6.0 and
#   SWIFT_STRICT_CONCURRENCY complete, and both pin exactly two targets down to 5.9
#   / minimal: the two UI-TEST targets, because `SnapshotHelper.swift` is
#   fastlane-shipped and predates Swift 6, and because an XCTestCase subclass
#   overriding setUpWithError in a @MainActor class is a Swift 6 error. 06-13
#   DECLINED APP-12 on exactly this drift and left it open.
#
#   The decision recorded here: criterion 5's "the app" ranges over the FOUR targets
#   that ship or test app CODE — both application targets and both unit-test targets
#   — and NOT over the two XCUITest hosts, which contain no app code and whose only
#   Swift is test-driver scaffolding. That exclusion is not a silent subtraction. It
#   is a printed count, `swift6_excluded_uitest_targets`, frozen against a dated
#   measurement, so adding a seventh target moves a number and fails this gate until
#   somebody states which side of the line it is on. Every excluded target must also
#   BE a UI-test target by name, so a non-UI-test target cannot be quietly pinned to
#   5.9 and inherit the exemption.
#
#   Both manifests are parsed SEPARATELY and their excluded sets compared, because
#   `tools/identity-parity.rb` does not look at build settings and this exact drift
#   would be invisible to it.
#
# FAILURE-LINE CONTRACT — do not change the shape. Controls grep it.
# One line per failure, no leading whitespace:
#
#     FAIL offline <path>: <reason>
#
# Named reasons, never codes. Labelled counts printed even on success. A single
# combined exit at the bottom, never an early exit 1. A tree that could not be
# scanned exits 2 with CANNOT RUN on stderr and prints NO verdict — "nobody looked"
# must never read as "it is clean".
#
# Ruby stdlib only. ONE require (`digest`, a default gem shipped with the
# interpreter), which is what keeps the `review notes` job's `bundler-cache: false`
# honest: there is no gem to install. Every shell-out is an argv array. Every read
# of a text file pins its encoding on the call.
#
# Runnable from the repository root or from test/, under BOTH pinned interpreters:
#   /opt/homebrew/opt/ruby@3.3/bin/ruby test/app_offline_test.rb
#   /opt/homebrew/opt/ruby@4.0/bin/ruby test/app_offline_test.rb
#
# Options:
#   --root DIR        scan a different tree (used by the negative controls)
#   --built-app PATH  a built .app whose EMBEDDED entitlements are checked too

require "digest"

USAGE = "Usage: ruby test/app_offline_test.rb [--root DIR] [--built-app PATH]"

def no_verdict(message)
  warn "CANNOT RUN: #{message}"
  exit 2
end

root      = nil
built_app = ENV["APP_OFFLINE_BUILT_APP"]
argv      = ARGV.dup
until argv.empty?
  case (arg = argv.shift)
  when "--root"       then root      = argv.shift or no_verdict("--root needs a directory. #{USAGE}")
  when "--built-app"  then built_app = argv.shift or no_verdict("--built-app needs a path. #{USAGE}")
  when "-h", "--help" then puts USAGE ; exit 0
  else no_verdict("unrecognised argument #{arg.inspect}. #{USAGE}")
  end
end

ROOT = root.nil? ? File.expand_path("..", __dir__) : File.expand_path(root)

# ─── frozen, dated measurements ──────────────────────────────────────────────
# A value, its measurement date and the thing it was measured against are ONE
# UNIT (docs/APPLE-ACCOUNT-STATE.md:41-46). None of these is a number to bump: a
# phase that legitimately changes a capability RE-MEASURES the triple and writes
# the new date beside it.

MEASURED_ON = "2026-09-05"

IOS_ENTITLEMENTS   = "app/iOS/App.entitlements"
MACOS_ENTITLEMENTS = "app/macOS/App.entitlements"

# The capability keys that would give this app the network. Measured 2026-09-05
# against Apple's Entitlements reference; ZERO of them are present as a key in
# either file, and both files mention two of them INSIDE AN XML COMMENT, which is
# why nothing here greps text.
NETWORK_KEYS = [
  "com.apple.security.network.client",
  "com.apple.security.network.server",
  "com.apple.developer.networking.networkextension",
  "com.apple.developer.networking.multicast",
  "com.apple.developer.associated-domains"
].freeze

# Stronger than the denylist above and asserted alongside it: the COMPLETE parsed
# key set of each file, measured 2026-09-05. A denylist only catches capabilities
# somebody thought to name; this catches every one, network or not.
EXPECTED_KEYS = {
  IOS_ENTITLEMENTS   => [].freeze,
  MACOS_ENTITLEMENTS => ["com.apple.security.app-sandbox"].freeze
}.freeze

# "APP-11 is satisfied by NOT CHANGING these files", made mechanical.
# sha256, measured 2026-09-05 on this tree.
EXPECTED_SHA256 = {
  IOS_ENTITLEMENTS   => "1bcdffedc03803efd57aa50f58c32605fcd5040b168b604d938b1e02aa3796ce",
  MACOS_ENTITLEMENTS => "cb80efed2676a5566f0df2819912f8d2a686633b52c0d6f9d5838b7375212d8e"
}.freeze

# Measured 2026-09-05: `git ls-files 'app/*.swift'` lists 68 files. The floor is
# deliberately well below that — its job is to refuse a VACUOUS pass, not to
# freeze the file count — and the exact number is printed on every run.
SWIFT_FLOOR = 40

# O8's scope decision, measured 2026-09-05 against both manifests.
MANIFEST_YML   = "app/project.yml"
MANIFEST_SWIFT = "app/Project.swift"
BASE_SWIFT_VERSION   = "6.0"
BASE_STRICT_CONCURRENCY = "complete"
PINNED_SWIFT_VERSION = "5.9"
PINNED_STRICT_CONCURRENCY = "minimal"
# The two targets criterion 5 does NOT range over, and why. Frozen: a seventh
# target, or a third exclusion, fails this gate rather than inheriting silence.
EXCLUDED_TARGETS   = ["AppUITests", "AppMacOSUITests"].freeze
TOTAL_TARGETS      = 6

# ─── the two hatches, ASSEMBLED — never spelled ──────────────────────────────
# `.continue-here.md`: "a file that configures a content gate is also swept by
# that gate" is a BLOCKING anti-pattern in this repository, and it has fired on
# six consecutive plans. This file is tracked; a whole-tree sweep for these two
# tokens would find its own configuration and read the tree as violating. So the
# tokens are built from character arrays at run time, exactly as
# tools/check-contamination.rb builds its prose terms (D-92). Nothing below spells
# either token, in code or in prose, and `escape_tokens=assembled` records it.
#
# Whitespace-tolerant on purpose: an attribute separated from its conformance by a
# newline, or an annotation written with a space before its parenthesis, is the
# same violation and must not slip past a fixed-string compare.
ATTR_SIGIL  = "@"
UNCHK_WORD  = %w[u n c h e c k e d].join
SENDABLE_W  = %w[S e n d a b l e].join
NONISO_WORD = %w[n o n i s o l a t e d].join
UNSAFE_WORD = %w[u n s a f e].join

HATCHES = [
  ["unchecked-conformance",
   Regexp.new("#{ATTR_SIGIL}\\s*#{UNCHK_WORD}\\s+#{SENDABLE_W}"),
   "an unchecked conformance to the concurrency-safety protocol"],
  ["unsafe-isolation",
   Regexp.new("#{NONISO_WORD}\\s*\\(\\s*#{UNSAFE_WORD}\\s*\\)"),
   "the unsafe-isolation annotation"]
].freeze

# ─── assertion harness (test/contamination_test.rb:81-103, verbatim) ─────────

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
  puts
  if @failures.zero?
    puts "All #{@checks} offline/Swift-6 assertions passed."
    exit 0
  else
    puts "#{@failures} of #{@checks} offline/Swift-6 assertion(s) failed."
    exit 1
  end
end

# ─── helpers ─────────────────────────────────────────────────────────────────

# argv array, never a shell string: quoting has silently changed a candidate set
# in this repository before.
def capture(*argv, chdir: ROOT)
  out = IO.popen(argv, chdir: chdir, err: File::NULL, &:read)
  [out.to_s, $?&.exitstatus]
rescue SystemCallError => e
  ["", "unavailable: #{e.message}"]
end

def tool?(name)
  _out, status = capture("/usr/bin/env", "which", name, chdir: ROOT)
  status == 0
end

# Every XML comment removed FIRST, then keys read off the remaining structure.
# BLOCK form on the gsub: a String replacement expands \0, \\ and a backquote, and
# one such replacement tripled a 277-line file in this phase while `ruby -c` stayed
# green.
def plist_keys(text)
  text.gsub(/<!--.*?-->/m) { "" }.scan(%r{<key>(.*?)</key>}m).flatten.map(&:strip)
end

# Swift comments removed while LINE STRUCTURE IS PRESERVED, so a hit still reports
# its line. String literals are deliberately NOT stripped: a hatch spelled inside a
# string is not a comment and this gate errs toward reporting it.
def strip_swift_comments(src)
  out   = +""
  i     = 0
  n     = src.length
  state = :code
  depth = 0
  while i < n
    ch = src[i]
    nx = src[i + 1]
    case state
    when :code
      if ch == "/" && nx == "/"
        state = :line ; out << "  " ; i += 2
      elsif ch == "/" && nx == "*"
        state = :block ; depth = 1 ; out << "  " ; i += 2
      elsif ch == "#" && nx == "\""
        state = :raw ; out << ch << nx ; i += 2
      elsif src[i, 3] == '"""'
        state = :mstring ; out << '"""' ; i += 3
      elsif ch == "\""
        state = :string ; out << ch ; i += 1
      else
        out << ch ; i += 1
      end
    when :line
      if ch == "\n" then state = :code ; out << ch else out << " " end
      i += 1
    when :block
      if ch == "/" && nx == "*"
        depth += 1 ; out << "  " ; i += 2
      elsif ch == "*" && nx == "/"
        depth -= 1 ; out << "  " ; i += 2 ; state = :code if depth.zero?
      else
        out << (ch == "\n" ? ch : " ") ; i += 1
      end
    when :string
      if ch == "\\"       then out << ch << (nx || "") ; i += 2
      elsif ch == "\"" || ch == "\n" then state = :code ; out << ch ; i += 1
      else out << ch ; i += 1
      end
    when :mstring
      if ch == "\\"          then out << ch << (nx || "") ; i += 2
      elsif src[i, 3] == '"""' then state = :code ; out << '"""' ; i += 3
      else out << ch ; i += 1
      end
    when :raw
      if src[i, 2] == "\"#" then state = :code ; out << "\"#" ; i += 2
      else out << ch ; i += 1
      end
    end
  end
  out
end

def hits(text)
  found = []
  HATCHES.each do |slug, re, described|
    offset = 0
    while (m = re.match(text, offset))
      found << [slug, text[0, m.begin(0)].count("\n") + 1, described]
      offset = m.end(0)
    end
  end
  found
end

# ─── O6 first: the population, before anything iterates over it ──────────────
# `git ls-files`, as an argv array. A non-zero exit or an empty list is a reason
# to REFUSE A VERDICT, never to report a clean tree — an `.each` over an empty
# collection asserts nothing and prints success.

listing, ls_status = capture("git", "ls-files", "-z", "app")
no_verdict("git ls-files could not run in #{ROOT} (#{ls_status})") unless ls_status == 0
tracked = listing.split("\0").reject(&:empty?).sort
no_verdict("git ls-files listed no tracked files under app/ in #{ROOT}") if tracked.empty?

swift_files = tracked.select { |rel| rel.end_with?(".swift") }
no_verdict("git ls-files listed no tracked .swift files under app/ in #{ROOT}") if swift_files.empty?

assert swift_files.length >= SWIFT_FLOOR, "offline", "app/",
       "the tracked Swift population under app/ holds #{swift_files.length} files " \
       "(floor #{SWIFT_FLOOR}, measured #{TOTAL_TARGETS}-target tree on #{MEASURED_ON}: 68). " \
       "A population below the floor would make every scan below vacuous"

# ─── O1–O4: the entitlements, parsed, per file ───────────────────────────────

key_counts    = {}
parse_route   = tool?("plutil") ? "stdlib+plutil" : "stdlib"

[IOS_ENTITLEMENTS, MACOS_ENTITLEMENTS].each do |rel|
  abs = File.join(ROOT, rel)

  # O1. A DELETED entitlements file satisfies a key-absence check completely, so
  # existence and non-emptiness are asserted before absence means anything.
  exists = File.file?(abs)
  assert exists, "offline", rel,
         "the entitlements file exists; a missing file would satisfy every " \
         "key-absence assertion below while proving nothing about the app"
  next unless exists

  raw = File.read(abs, encoding: "UTF-8")
  assert !raw.strip.empty?, "offline", rel, "the entitlements file is non-empty"
  assert raw.include?("<plist") && raw.include?("<dict"), "offline", rel,
         "the file is a property list with a dictionary root, so its keys can be read " \
         "structurally rather than grepped"

  keys = plist_keys(raw)
  key_counts[rel] = keys

  # O2. The named requirement: no network capability. Asserted on the PARSED key
  # set. Both files carry a forbidden key inside an XML comment, and the comment
  # is gone before this runs.
  present = NETWORK_KEYS & keys
  assert present.empty?, "offline", rel,
         "carries none of the #{NETWORK_KEYS.length} network-capability keys APP-11 " \
         "forbids; found #{present.join(', ')}"

  # O3. The complete key set, frozen and dated. Catches a capability nobody thought
  # to put on the denylist.
  expected = EXPECTED_KEYS.fetch(rel)
  assert keys.sort == expected.sort, "offline", rel,
         "the parsed key set is exactly the set measured on #{MEASURED_ON} " \
         "[#{expected.join(', ')}]; found [#{keys.join(', ')}]. A capability was added " \
         "or removed — re-measure the triple with today's date, do not bump it"

  # O4. Unchanged since the measurement.
  digest = Digest::SHA256.hexdigest(File.binread(abs))
  assert digest == EXPECTED_SHA256.fetch(rel), "offline", rel,
         "sha256 still equals the value measured on #{MEASURED_ON} " \
         "(#{EXPECTED_SHA256.fetch(rel)}); found #{digest}"

  # O5. Apple's own parser, where it exists, must produce the same key set. This is
  # what makes the stdlib route above a PARSE rather than a hopeful regex — and it
  # is the assertion that would catch a comment-stripping bug in this file.
  if parse_route == "stdlib+plutil"
    lint_out, lint_status = capture("plutil", "-lint", abs)
    assert lint_status == 0, "offline", rel,
           "plutil -lint accepts the file (#{lint_out.strip})"
    xml, xml_status = capture("plutil", "-convert", "xml1", "-o", "-", abs)
    assert xml_status == 0, "offline", rel, "plutil -convert xml1 re-emits the file"
    apple_keys = plist_keys(xml)
    assert apple_keys.sort == keys.sort, "offline", rel,
           "Apple's parser and this file's parser agree on the key set exactly " \
           "(plutil: [#{apple_keys.join(', ')}] / here: [#{keys.join(', ')}]). A " \
           "disagreement means the comment-stripping in this gate is wrong, which is " \
           "the failure mode Pitfall 11 describes"
  end
end

# ─── O7: the two hatches, over comment-stripped Swift ────────────────────────

stripped_hits = []
comment_hits  = []
scanned_bytes = 0

swift_files.each do |rel|
  abs = File.join(ROOT, rel)
  next unless File.file?(abs)

  raw = File.read(abs, encoding: "UTF-8")
  scanned_bytes += raw.bytesize
  stripped = strip_swift_comments(raw)

  found = hits(stripped)
  found.each { |slug, line, described| stripped_hits << [rel, line, slug, described] }

  # Not an assertion — a printed count. A COMMENT naming a hatch is legitimate
  # prose (three files in this tree explain why the hatches are banned) and must
  # not turn this gate red; that is precisely what control 4 proves. But the count
  # is printed so a comment that appears is visible rather than invisible.
  (hits(raw).length - found.length).then do |extra|
    comment_hits << [rel, extra] if extra.positive?
  end

  assert found.empty?, "offline", rel,
         found.empty? ? "carries neither concurrency escape hatch outside comments" :
         "line #{found.first[1]} uses #{found.first[2]} — #{found.first[3]} — which " \
         "APP-12 and ROADMAP criterion 5 forbid outright. It compiles clean under " \
         "-strict-concurrency=complete, which is why a scan and not the build is what " \
         "catches it"
end

# ─── O8: criterion 5's scope, from BOTH manifests, compared ──────────────────
# Read structurally: the base block, then every per-target override attributed to
# the target that encloses it. `tools/identity-parity.rb` does not look at build
# settings, so a manifest pair that disagreed here would be invisible to it.

def yml_overrides(text)
  section = false
  target  = nil
  found   = {}
  text.lines.each_with_index do |line, idx|
    section = true  if line.start_with?("targets:")
    section = false if section && line.match?(/\A[a-z]/) && !line.start_with?("targets:")
    next unless section

    if (m = line.match(/\A  ([A-Za-z][A-Za-z0-9_-]*):\s*\z/))
      target = m[1]
    elsif (m = line.match(/\A\s{4,}SWIFT_VERSION:\s*"([^"]+)"/))
      found[target] = [m[1], idx + 1]
    end
  end
  found
end

def yml_targets(text)
  section = false
  names   = []
  text.lines.each do |line|
    section = true  if line.start_with?("targets:")
    section = false if section && line.match?(/\A[a-z]/) && !line.start_with?("targets:")
    next unless section

    names << Regexp.last_match(1) if line.match(/\A  ([A-Za-z][A-Za-z0-9_-]*):\s*\z/)
  end
  names
end

# Indent 6 or deeper is what distinguishes a PER-TARGET override from the base
# settings block at indent 4; without that floor the base itself is read as an
# override attributed to no target, which is a nil key and a crash rather than a
# verdict. The enclosing target is the nearest preceding `name:` line.
def swift_overrides(text)
  target = nil
  found  = {}
  text.lines.each_with_index do |line, idx|
    if (m = line.match(/\A\s*name:\s*"([^"]+)"/))
      target = m[1]
    elsif (m = line.match(/\A\s{6,}"SWIFT_VERSION":\s*"([^"]+)"/)) && !target.nil?
      found[target] = [m[1], idx + 1]
    end
  end
  found
end

yml_text   = File.read(File.join(ROOT, MANIFEST_YML), encoding: "UTF-8")
swift_text = File.read(File.join(ROOT, MANIFEST_SWIFT), encoding: "UTF-8")

[[MANIFEST_YML, yml_text, /^\s{4}SWIFT_VERSION:\s*"([^"]+)"/, /^\s{4}SWIFT_STRICT_CONCURRENCY:\s*(\S+)/],
 [MANIFEST_SWIFT, swift_text, /^\s{4}"SWIFT_VERSION":\s*"([^"]+)"/, /^\s{4}"SWIFT_STRICT_CONCURRENCY":\s*"([^"]+)"/]].each do |rel, text, ver_re, str_re|
  ver = text[ver_re, 1]
  str = text[str_re, 1].to_s.delete(",\"")
  assert ver == BASE_SWIFT_VERSION, "offline", rel,
         "the project BASE settings declare SWIFT_VERSION #{BASE_SWIFT_VERSION} " \
         "(found #{ver.inspect}) — this is what makes criterion 5's build clause true " \
         "for every target that does not override it"
  assert str == BASE_STRICT_CONCURRENCY, "offline", rel,
         "the project BASE settings declare strict concurrency #{BASE_STRICT_CONCURRENCY} " \
         "(found #{str.inspect})"
end

yml_over   = yml_overrides(yml_text)
swift_over = swift_overrides(swift_text)
all_targets = yml_targets(yml_text)

assert all_targets.length == TOTAL_TARGETS, "offline", MANIFEST_YML,
       "the manifest declares #{TOTAL_TARGETS} targets as measured on #{MEASURED_ON} " \
       "(found #{all_targets.length}: #{all_targets.join(', ')}). A new target is a new " \
       "answer to 'what does criterion 5 range over' and must be stated, not inherited"

[[MANIFEST_YML, yml_over], [MANIFEST_SWIFT, swift_over]].each do |rel, over|
  assert over.keys.sort == EXCLUDED_TARGETS.sort, "offline", rel,
         "exactly the #{EXCLUDED_TARGETS.length} targets measured on #{MEASURED_ON} " \
         "override the base Swift version [#{EXCLUDED_TARGETS.join(', ')}]; found " \
         "[#{over.keys.join(', ')}]. Every other target inherits " \
         "-swift-version #{BASE_SWIFT_VERSION} -strict-concurrency=#{BASE_STRICT_CONCURRENCY}"
  over.each do |target, (value, line)|
    assert value == PINNED_SWIFT_VERSION, "offline", "#{rel}:#{line}",
           "#{target} is pinned to #{PINNED_SWIFT_VERSION} (found #{value})"
    assert target.to_s.end_with?("UITests"), "offline", "#{rel}:#{line}",
           "#{target} is a UI-TEST target, which is the only reason criterion 5 does not " \
           "range over it: it contains no app code, only XCUITest scaffolding. A " \
           "non-UI-test target pinned below Swift #{BASE_SWIFT_VERSION} does NOT inherit " \
           "this exemption"
  end
end

assert yml_over.keys.sort == swift_over.keys.sort, "offline", "#{MANIFEST_YML} / #{MANIFEST_SWIFT}",
       "both manifests exclude the SAME targets ([#{yml_over.keys.join(', ')}] vs " \
       "[#{swift_over.keys.join(', ')}]). tools/identity-parity.rb does not read build " \
       "settings, so this drift would otherwise be invisible to every gate in the repo"

[[MANIFEST_YML, yml_text, PINNED_STRICT_CONCURRENCY],
 [MANIFEST_SWIFT, swift_text, PINNED_STRICT_CONCURRENCY]].each do |rel, text, pinned|
  count = text.lines.count { |l| l.match?(/SWIFT_STRICT_CONCURRENCY"?:\s*"?#{pinned}/) }
  assert count == EXCLUDED_TARGETS.length, "offline", rel,
         "#{EXCLUDED_TARGETS.length} strict-concurrency downgrades to #{pinned}, one per " \
         "excluded UI-test target (found #{count})"
end

# ─── O9: the BUILT artefact, when one is supplied ────────────────────────────
# A file-level gate that never exercises the artefact is a recorded defect class
# here: XcodeGen bakes TEST_HOST at generation time, and iOS INFOPLIST_KEY_*
# injection is inert when the target does not generate its plist — both invisible
# to the manifests, the tests and the parity tool. So when a built .app is
# available its EMBEDDED entitlements are read and asserted against the same keys.
#
# The `review notes` job runs on ubuntu-latest with no Xcode and no codesign, so
# this half is conditional — and WHICH PATH RAN is printed rather than implied.

builtapp_checked = false
builtapp_reason  = nil

if built_app.nil? || built_app.to_s.empty?
  builtapp_reason = "no built .app supplied (pass --built-app PATH or set " \
                    "APP_OFFLINE_BUILT_APP); the required review-notes job runs on " \
                    "ubuntu-latest with no Xcode, so this is the CI path"
elsif !File.directory?(built_app)
  assert false, "offline", built_app.to_s,
         "the supplied --built-app path is a directory containing a built bundle"
  builtapp_reason = "supplied path is not a directory"
elsif !tool?("codesign")
  builtapp_reason = "codesign is not on PATH on this host"
else
  out, status = capture("codesign", "-d", "--entitlements", ":-", "--xml", built_app.to_s)
  out, status = capture("codesign", "-d", "--entitlements", ":-", built_app.to_s) if status != 0
  assert status == 0, "offline", built_app.to_s,
         "codesign -d --entitlements read the bundle's embedded entitlements " \
         "(exit #{status.inspect})"
  if status == 0
    embedded = plist_keys(out)
    present  = NETWORK_KEYS & embedded
    assert present.empty?, "offline", built_app.to_s,
           "the BUILT bundle's embedded entitlements carry none of the " \
           "#{NETWORK_KEYS.length} network-capability keys APP-11 forbids; found " \
           "#{present.join(', ')}. This is the artefact, not the input"
    builtapp_checked = true
    builtapp_reason  = "embedded entitlements read from #{File.basename(built_app)}, " \
                       "#{embedded.length} key(s)"
  end
end

# ─── labelled counts, printed on success as well as on failure ───────────────

puts
puts "swift_files_scanned=#{swift_files.length}"
puts "swift_bytes_scanned=#{scanned_bytes}"
puts "escape_tokens=assembled"
puts "escape_hits_stripped=#{stripped_hits.length}"
puts "escape_hits_in_comments=#{comment_hits.sum { |(_rel, n)| n }}"
comment_hits.each { |rel, n| puts "escape_comment_mention #{rel}=#{n}" }
stripped_hits.each { |rel, line, slug, _d| puts "escape_hit #{rel}:#{line}=#{slug}" }
puts "entitlements_parse_route=#{parse_route}"
puts "entitlements_ios_keys=#{key_counts.fetch(IOS_ENTITLEMENTS, []).length}"
key_counts.fetch(IOS_ENTITLEMENTS, []).each { |k| puts "entitlements_ios_key #{k}" }
puts "entitlements_macos_keys=#{key_counts.fetch(MACOS_ENTITLEMENTS, []).length}"
key_counts.fetch(MACOS_ENTITLEMENTS, []).each { |k| puts "entitlements_macos_key #{k}" }
puts "swift6_targets=#{all_targets.length - EXCLUDED_TARGETS.length}"
puts "swift6_excluded_uitest_targets=#{EXCLUDED_TARGETS.length}"
EXCLUDED_TARGETS.each { |t| puts "swift6_excluded #{t}" }
puts "swift6_manifests_agree=#{yml_over.keys.sort == swift_over.keys.sort}"
puts "builtapp_checked=#{builtapp_checked}"
puts "builtapp_reason=#{builtapp_reason}"

verdict!
