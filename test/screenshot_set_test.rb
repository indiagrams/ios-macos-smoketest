#!/usr/bin/env ruby
# frozen_string_literal: true

# screenshot_set_test.rb — META-02 / META-03, criterion 2's machine-checkable
# half: every delivered App Store screenshot is the EXACT pixel size Apple's
# Media Manager expects for its device class, and carries no alpha channel.
#
# WHY THIS FILE EXISTS
#
#   Nothing under test/ asserted this before now. The only size references in
#   the whole repository lived in the CAPTURE harness (AppStoreScreenshotTests,
#   the macOS ScreenshotDriver) -- which runs once, at capture time, and proves
#   nothing about what is sitting in fastlane/ afterwards -- and in template-
#   owned ci/extract-mac-screenshots.sh, whose own APPLE_SIZES list (:160)
#   ACCEPTS 2880x1800, 2560x1600, 1440x900 AND 1280x800. That list exists to
#   crop a capture DOWN to whichever Apple size it already fits inside, not to
#   guarantee it is the LARGEST one -- so a macOS capture that came up short at
#   1280x800 crops cleanly, uploads, and the extraction script's own run exits
#   0. That is WR-04 / UF-05 from this phase's own review and security audit:
#   a correct check pointed at the wrong population, one more time, in the
#   code that produces the assets a reviewer sees first. This file is the
#   STANDING gate that closes it: no capture step, no network, no simulator --
#   it reads whatever PNGs are sitting in the delivery directories today and
#   judges them.
#
# WHAT IS ASSERTED, AND OVER WHICH POPULATION
#
#   Two directories, three device families:
#
#     fastlane/Mac_screenshots/en-US/   "macos-*"                  2880x1800
#     fastlane/screenshots/en-US/       "iPhone 16 Pro Max-*"      1320x2868
#     fastlane/screenshots/en-US/       "iPad Pro 13-inch (M4)-*"  2064x2752
#
#   Every PNG found under either directory is matched against the known
#   family prefixes ABOVE (see FAMILIES). A file that matches none is a named
#   "population" failure in its own right -- see UNMATCHED FILES below -- so
#   the population is never narrower than what is actually sitting on disk.
#
#   Per matched file: EXACT pixel dimensions for its family (not "at least",
#   not "close to" -- Apple's Media Manager takes an exact size), and no alpha
#   channel. Per family: a FLOOR on how many tiles must be present (see THE
#   COUNT TENSION below). Both are printed as named facts so either moving is
#   visible without re-reading this file.
#
# THE COUNT TENSION, RESOLVED DELIBERATELY (08-VALIDATION.md, 08-UAT.md test 3)
#
#   iPhone 16 Pro Max ships SIX tiles today, not eight, and that is a
#   DECISION, not a defect. "-03-timestamps-light" and "-07-timestamps-dark"
#   are REFUSED by AppStoreScreenshotTests' own capture-time measurement -- the
#   surface needs 778.954pt against a 772.667pt content band, over by 6.29pt
#   even at scrollMargin=0, on a seeded single-card surface with no retraction
#   lever -- and the user chose, at plan 08-23's blocking checkpoint, to drop
#   them rather than ship a tile that does not fit. iPad never overflows (8/8
#   clean); macOS overflows only on the three-step chain, which was fixed in
#   plan 08-21 (8/8 clean today).
#
#   A gate that hardcodes "iPhone == 6" goes RED the moment a later phase
#   revisits that geometry and restores the two refused tiles -- a gate that
#   fails on a CORRECT future state, punishing the fix for the defect it
#   exists to catch. A gate that accepts ANY count, including zero, cannot
#   catch "a tile went missing", which is half of what this file is for.
#
#   The resolution is a FLOOR, not a frozen equality, on each named family:
#
#     * a count AT OR ABOVE the recorded floor passes -- restoring the two
#       refused iPhone tiles later raises the count to 8 and stays green;
#     * a count BELOW the floor fails BY NAME (which family, measured N,
#       floor F, and the provenance of why F is what it is) -- a silent drop
#       is caught the day it happens;
#     * a WHOLLY NEW device family (an iPhone SE set, say) matches no prefix
#       below at all, so its files fail the "known device family" clause by
#       name until a human adds an entry for it, with its own size and floor.
#       Teaching this gate a new shape is a deliberate edit, never something a
#       build should do to itself unnoticed.
#
#   Raising OR lowering a floor is therefore always a deliberate edit to this
#   file, carrying its own provenance comment -- exactly as iPhone's own 8 -> 6
#   is recorded on its entry below -- never a silent drift.
#
# TWO RULES CARRIED FROM THIS PROJECT'S OTHER GATES, BOTH LOAD-BEARING HERE
#
#   1. sips EXITS 0 ON A FILE THAT DOES NOT EXIST (icon_set_test.rb measured
#      this 2026-09-10 against the same tool): "sips -g hasAlpha /nope.png"
#      prints a warning to stderr and returns 0. So the RESULT is whichever
#      properties actually came back on stdout, and the exit code rides along
#      in the failure message rather than standing in for the answer -- see
#      sips_props. Nothing here trusts an exit code as a substitute for a
#      property that did not arrive.
#   2. A PNG is judged by PARSING it -- sips, exactly as icon_set_test.rb
#      reads pixel properties -- never by filename and never by trusting that
#      a file with a .png extension is one. The "format" property is asserted
#      too, so a renamed non-PNG fails as loudly as a wrong-sized one.
#
# REFUSAL, NOT A PASS, ON AN ABSENT OR EMPTY POPULATION
#
#   Every no_verdict condition is evaluated BEFORE the first `assert` call and
#   before this file prints anything but its own diagnostic on stderr --
#   test/store_copy_test.rb's discipline, adopted verbatim: "nobody looked"
#   must never read as "it is clean", so a run that cannot find a single PNG
#   under either directory prints NOTHING on stdout, says CANNOT RUN on
#   stderr, and exits 2. A caller MUST treat exit 2 as not a pass.
#
# DEPENDENCIES: zero `require` lines. Every property read goes through sips
# (an external tool, captured via an argv array, never a shell string) or
# Dir/File, both always available. There is nothing here for `bundler-cache:
# false` to trip over.
#
# Every file read that touches text output is pinned to UTF-8 at the point it
# is read: capture() opens the child's stdout as "r:UTF-8" so a repository
# checked out under a non-ASCII path does not raise Encoding::CompatibilityError
# on the first strip or regex over it (UL-048's class; test/icon_set_test.rb's
# capture() carries the identical comment and fix). This file performs no
# File.read of a text file at all, so that is the only encoding-sensitive read
# in it.
#
# NOT WIRED INTO ANY WORKFLOW BY THIS CHANGE. This is the gate only; CI wiring
# (.github/workflows/review-notes.yml) is a separate, explicit decision and is
# out of scope here, the same discipline built_plist_test.rb was landed under.
#
# Runnable from the repository root, under BOTH pinned interpreters, no
# network, no simulator, no build -- it reads files already on disk:
#   /opt/homebrew/opt/ruby@3.3/bin/ruby test/screenshot_set_test.rb
#   /opt/homebrew/opt/ruby@4.0/bin/ruby test/screenshot_set_test.rb
#
# Options:
#   --root DIR   inspect a different tree. Used by the red/green controls in
#                .planning/phases/08-submission-artifacts-store-metadata/
#                evidence/screenshot-set-controls.rb, the only reason a green
#                here is known to be reachable at all -- the same convention
#                test/icon_set_test.rb and test/store_copy_test.rb document
#                for their own --root.

USAGE = "Usage: ruby test/screenshot_set_test.rb [--root DIR]"

def no_verdict(message)
  warn "CANNOT RUN: #{message}"
  exit 2
end

root = nil
argv = ARGV.dup
until argv.empty?
  case (arg = argv.shift)
  when "--root"       then root = argv.shift or no_verdict("--root needs a directory. #{USAGE}")
  when "-h", "--help" then puts USAGE ; exit 0
  else no_verdict("unrecognised argument #{arg.inspect}. #{USAGE}")
  end
end

ROOT = File.expand_path(root || File.join(__dir__, ".."))
no_verdict("--root #{ROOT} is not a directory") unless File.directory?(ROOT)

MEASURED_ON = "2026-09-12"
LOCALE      = "en-US"

MACOS_DIR_REL = File.join("fastlane", "Mac_screenshots", LOCALE)
IOS_DIR_REL   = File.join("fastlane", "screenshots", LOCALE)
MACOS_PARENT_REL = File.join("fastlane", "Mac_screenshots")
IOS_PARENT_REL   = File.join("fastlane", "screenshots")

APPLE_ALPHA = "App Store Connect rejects a screenshot that carries an alpha channel"

# ─── the three named families -- see THE COUNT TENSION in the header ────────
# THE EIGHT TILES A FAMILY CAN CARRY, IN ORDINAL ORDER.
# ADDED 2026-09-14 BY THE PHASE 8 CLOSE-OUT (VG-02). The floors below bound HOW
# MANY tiles a family holds and say nothing about WHICH, and that gap was measured
# rather than reasoned: renaming `-01-chain-light` to `-03-timestamps-light` and
# `-05-chain-dark` to `-07-timestamps-dark` left the iPhone family at count=6 and
# the whole gate green at 76/76, with every printed fact byte-identical to a clean
# run -- while the shipped iPhone set carried NO CHAIN TILE IN EITHER APPEARANCE.
# The chain is the app's differentiator and the surface META-02 names in words.
#
# The ordinals are the reviewer's reading order, so a set that silently loses one
# surface and doubles another is exactly what this catalogue exists to refuse.
SLUGS = %w[
  01-chain-light 02-hashing-light 03-timestamps-light 04-encode-url-light
  05-chain-dark  06-hashing-dark  07-timestamps-dark  08-encode-url-dark
].freeze

FAMILIES = [
  {
    key:    "macos",
    dir:    MACOS_DIR_REL,
    prefix: "macos-",
    width:  2880,
    height: 1800,
    floor:  8,
    refused: [].freeze,
    provenance: "measured #{MEASURED_ON}: 8 of 8 macOS App Store tiles present, " \
                "2880x1800, no alpha (08-UAT.md test 2, re-verified after plan " \
                "08-21's chain-tile fix). No refusal has ever been recorded on " \
                "this family."
  }.freeze,
  {
    key:    "iphone_16_pro_max",
    dir:    IOS_DIR_REL,
    prefix: "iPhone 16 Pro Max-",
    width:  1320,
    height: 2868,
    floor:  6,
    # The two tiles UL-086 refuses. Listed as ALLOWED-ABSENT rather than removed
    # from SLUGS: a later phase that makes them fit restores them and must stay
    # green, which is the same reasoning the floor of 6 already carries.
    refused: %w[03-timestamps-light 07-timestamps-dark].freeze,
    provenance: "measured #{MEASURED_ON}: 6 of a possible 8 iPhone tiles present. " \
                "-03-timestamps-light and -07-timestamps-dark are REFUSED by " \
                "AppStoreScreenshotTests' own capture-time measurement (778.954pt " \
                "needed vs a 772.667pt content band, over by 6.29pt even at " \
                "scrollMargin=0) and DROPPED by the user's decision at plan " \
                "08-23's blocking checkpoint (08-UAT.md test 3). The floor is 6, " \
                "not 8, on purpose: a later phase restoring the two refused " \
                "tiles raises the count and must stay green; dropping BELOW 6 " \
                "is a regression this floor exists to catch."
  }.freeze,
  {
    key:    "ipad_pro_13_m4",
    dir:    IOS_DIR_REL,
    prefix: "iPad Pro 13-inch (M4)-",
    width:  2064,
    height: 2752,
    floor:  8,
    refused: [].freeze,
    provenance: "measured #{MEASURED_ON}: 8 of 8 iPad tiles present, 2064x2752, " \
                "no alpha (08-UAT.md test 3). iPad never overflowed the content " \
                "band on any surface, so no tile on this family has ever been " \
                "refused."
  }.freeze,
].freeze

# ─── assertion harness (test/icon_set_test.rb, test/store_copy_test.rb verbatim shape) ───

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
    puts "All #{@checks} screenshot-set assertions passed."
    exit 0
  else
    puts "#{@failures} of #{@checks} screenshot-set assertion(s) failed."
    exit 1
  end
end

# ─── helpers ─────────────────────────────────────────────────────────────────

# argv array, never a shell string. Output read with its encoding PINNED --
# see the header's encoding note.
def capture(*argv, chdir: ROOT)
  out = IO.popen(argv, "r:UTF-8", chdir: chdir, err: File::NULL, &:read)
  [out.to_s, $?&.exitstatus]
rescue SystemCallError => e
  ["", "unavailable: #{e.message}"]
end

def tool?(name)
  _out, status = capture("/usr/bin/env", "which", name)
  status == 0
end

# sips exits 0 on a file that does not exist (MEASURED, see header), so the
# RESULT is the set of properties that actually came back, and the exit code
# rides along in the message rather than standing in for the answer.
def sips_props(path, *props)
  args = ["/usr/bin/sips"]
  props.each { |p| args << "-g" << p }
  args << path
  out, status = capture(*args)
  found = {}
  out.to_s.split("\n").each do |line|
    m = line.match(/\A\s+([A-Za-z0-9_]+):\s*(.*?)\s*\z/)
    found[m[1]] = m[2] if m
  end
  [found, status]
end

def png_children(abs)
  return nil unless Dir.exist?(abs)
  Dir.children(abs).select { |f| f.downcase.end_with?(".png") }.sort
end

# ─── P0: the tool this gate depends on ───────────────────────────────────────

no_verdict("sips is not on PATH -- every dimension and alpha read here goes " \
           "through it, and a run that cannot read a pixel has not inspected " \
           "a screenshot") unless tool?("sips")

# ─── population, enumerated BEFORE anything prints or asserts ───────────────

MACOS_DIR_ABS = File.join(ROOT, MACOS_DIR_REL)
IOS_DIR_ABS   = File.join(ROOT, IOS_DIR_REL)

macos_dir_exists = Dir.exist?(MACOS_DIR_ABS)
ios_dir_exists   = Dir.exist?(IOS_DIR_ABS)
macos_files = png_children(MACOS_DIR_ABS) || []
ios_files   = png_children(IOS_DIR_ABS) || []

# REFUSE, DO NOT PASS. Evaluated before the first `assert` and before any
# stdout output -- test/store_copy_test.rb's discipline: "nobody looked" must
# never read as "it is clean".
no_verdict("neither #{MACOS_DIR_REL} nor #{IOS_DIR_REL} holds a single PNG " \
           "under #{ROOT} (macOS dir exists=#{macos_dir_exists} count=" \
           "#{macos_files.length}, iOS dir exists=#{ios_dir_exists} count=" \
           "#{ios_files.length}). A scan over an absent or empty population " \
           "asserts nothing and prints success -- there is nothing here to " \
           "measure a size or an alpha channel against") \
  if macos_files.empty? && ios_files.empty?

puts "==> Screenshot set (META-02 / META-03, criterion 2) -- population: " \
     "two directories, #{FAMILIES.length} device families"
puts

# ─── per-directory presence, each asserted and named apart ──────────────────

assert macos_dir_exists && !macos_files.empty?, "population", MACOS_DIR_REL,
       "the macOS screenshot directory exists and holds at least one PNG " \
       "(exists=#{macos_dir_exists}, count=#{macos_files.length}). Criterion " \
       "2's macOS half has nothing to measure a size or an alpha channel " \
       "against without it"
assert ios_dir_exists && !ios_files.empty?, "population", IOS_DIR_REL,
       "the iOS screenshot directory exists and holds at least one PNG " \
       "(exists=#{ios_dir_exists}, count=#{ios_files.length}). Criterion 2's " \
       "iOS half has nothing to measure a size or an alpha channel against " \
       "without it"

# No second locale directory this gate has never heard of -- a sibling of
# en-US would ship screenshots that nothing here measures.
[[MACOS_PARENT_REL, MACOS_DIR_REL], [IOS_PARENT_REL, IOS_DIR_REL]].each do |parent_rel, expected_rel|
  parent_abs = File.join(ROOT, parent_rel)
  next unless Dir.exist?(parent_abs)
  siblings = Dir.children(parent_abs).select { |c| File.directory?(File.join(parent_abs, c)) }.sort
  expected = File.basename(expected_rel)
  extra    = siblings - [expected]
  assert extra.empty?, "population", parent_rel,
         "#{parent_rel} holds no locale directory besides #{expected.inspect} " \
         "(found: #{siblings.inspect}). A second locale this gate has never " \
         "heard of would ship screenshots that nothing here measures for size " \
         "or alpha (extra: #{extra.inspect})"
end

# ─── every file matched to exactly one known device family, or named as unmatched ───

Member = Struct.new(:rel, :abs, :family, keyword_init: true)

population = []
unmatched  = []

[[MACOS_DIR_REL, MACOS_DIR_ABS, macos_files], [IOS_DIR_REL, IOS_DIR_ABS, ios_files]].each do |dir_rel, dir_abs, files|
  files.each do |fname|
    rel     = File.join(dir_rel, fname)
    abs     = File.join(dir_abs, fname)
    matches = FAMILIES.select { |f| f[:dir] == dir_rel && fname.start_with?(f[:prefix]) }
    case matches.length
    when 1
      population << Member.new(rel: rel, abs: abs, family: matches.first)
    when 0
      unmatched << rel
    else
      # Two family prefixes matching the same filename is a defect in THIS
      # FILE's own family table, never in the artefact -- named apart from
      # "unmatched" so the two cannot be confused.
      assert false, "population", rel,
             "the filename matches exactly one known device family. It " \
             "matches #{matches.length} (#{matches.map { |f| f[:key] }.join(', ')}) " \
             "-- the family prefixes below are not mutually exclusive, which " \
             "is a defect in this gate's own table, not in the artefact"
    end
  end
end

unmatched.sort.each do |rel|
  assert false, "population", rel,
         "the file is a PNG under a known screenshot directory, so it must " \
         "match one of the known device-family prefixes " \
         "(#{FAMILIES.map { |f| f[:prefix].inspect }.join(', ')}). It matches " \
         "none -- either an unrecognised export landed here, or a genuinely " \
         "new device family shipped without this gate being taught its size " \
         "-- and either way nothing has checked this file's dimensions or its " \
         "alpha channel"
end

# ─── per-family floor -- see THE COUNT TENSION in the header ────────────────

FAMILIES.each do |fam|
  count = population.count { |m| m.family == fam }
  assert count >= fam[:floor], "population", fam[:dir],
         "the #{fam[:key]} family (prefix #{fam[:prefix].inspect}) holds at " \
         "least #{fam[:floor]} tile(s); measured #{count}. #{fam[:provenance]}"
end

# ─── per-family IDENTITY -- which tiles, not just how many (VG-02) ──────────
#
# The floor above is a COUNT. These two clauses are the SET, and between them a
# renamed, duplicated or substituted tile is named rather than averaged away.

FAMILIES.each do |fam|
  present = population.select { |m| m.family == fam }
            .map { |m| File.basename(m.rel, ".png").delete_prefix(fam[:prefix]) }

  unknown = (present - SLUGS).sort
  assert unknown.empty?, "identity", fam[:dir],
         "every #{fam[:key]} tile carries one of the #{SLUGS.length} known ordinal " \
         "slugs; #{unknown.length} do(es) not (#{unknown.join(', ')}). A slug outside " \
         "the catalogue is a tile nobody ordered -- a rename, a stale export, or a " \
         "surface that shipped without this gate being taught it"

  duplicated = present.tally.select { |_, n| n > 1 }.keys.sort
  assert duplicated.empty?, "identity", fam[:dir],
         "no #{fam[:key]} slug appears twice; duplicated: #{duplicated.join(', ')}"

  required = SLUGS - fam[:refused]
  missing  = (required - present).sort
  assert missing.empty?, "identity", fam[:dir],
         "every REQUIRED #{fam[:key]} tile is present. Missing: #{missing.join(', ')}. " \
         "Required is the #{SLUGS.length}-slug catalogue minus this family's recorded " \
         "refusals (#{fam[:refused].empty? ? 'none' : fam[:refused].join(', ')}), so a " \
         "tile that vanishes or is renamed into another surface's slot fails here even " \
         "when the count still clears the floor"
end

# ─── dimension + alpha, member by member, over the WHOLE matched population ─

assert !population.empty?, "dimension", "(population)",
       "the population is non-empty before anything iterates it"

dimension_checked = 0
alpha_checked     = 0

population.sort_by(&:rel).each do |m|
  fam = m.family
  props, status = sips_props(m.abs, "pixelWidth", "pixelHeight", "hasAlpha", "format")
  w     = props["pixelWidth"]
  h     = props["pixelHeight"]
  alpha = props["hasAlpha"]
  fmt   = props["format"]

  if w.nil? || h.nil? || alpha.nil? || fmt.nil?
    assert false, "dimension", m.rel,
           "sips returned the pixel properties for this file. It did not " \
           "(exit #{status.inspect}, got #{props.keys.sort.inspect}) -- and " \
           "sips exits 0 on a file it could not read, so this is a third " \
           "state and is failed as one rather than read as compliant"
    next
  end

  dimension_checked += 1
  assert fmt == "png", "dimension", m.rel,
         "sips reads this file's format as png; it is #{fmt.inspect}. A file " \
         "under a screenshot delivery directory that is not actually a PNG " \
         "has not shipped what its extension claims"
  assert w == fam[:width].to_s && h == fam[:height].to_s, "dimension", m.rel,
         "the #{fam[:key]} tile measures exactly #{fam[:width]}x#{fam[:height]}; " \
         "it is #{w}x#{h}. Apple's Media Manager accepts an exact size only -- " \
         "ci/extract-mac-screenshots.sh's own APPLE_SIZES list ACCEPTS " \
         "2880x1800, 2560x1600, 1440x900 AND 1280x800, so a window that came " \
         "up short crops cleanly into a smaller accepted size and that " \
         "script's own run exits 0 (WR-04 / UF-05); this gate is the one " \
         "place a short capture is refused by name rather than silently " \
         "downgraded"

  alpha_checked += 1
  assert alpha == "no", "alpha", m.rel,
         "no alpha channel (sips hasAlpha=#{alpha.inspect}). #{APPLE_ALPHA}, " \
         "and ci/extract-mac-screenshots.sh's own flatten_alpha() exists " \
         "because XCUITest's window capture carries a transparent drop-shadow " \
         "margin by default -- this is the standing check that the flatten " \
         "step ran and held"
end

assert dimension_checked.positive?, "dimension", "(population)",
       "at least one member's dimensions were actually measured. A dimension " \
       "clause that measured nothing reports compliance it never looked for"
assert alpha_checked.positive?, "alpha", "(population)",
       "at least one member's alpha channel was actually measured. An alpha " \
       "clause that measured nothing reports compliance it never looked for"

# ─── named facts, printed on success as well as on failure ──────────────────

puts
puts "screenshot_root=#{ROOT}"
puts "screenshot_macos_dir=#{MACOS_DIR_REL}"
puts "screenshot_macos_dir_exists=#{macos_dir_exists}"
puts "screenshot_macos_count=#{macos_files.length}"
puts "screenshot_ios_dir=#{IOS_DIR_REL}"
puts "screenshot_ios_dir_exists=#{ios_dir_exists}"
puts "screenshot_ios_count=#{ios_files.length}"
puts "screenshot_total=#{macos_files.length + ios_files.length}"
puts "screenshot_matched=#{population.length}"
puts "screenshot_unmatched=#{unmatched.length}"
puts "screenshot_unmatched_paths=#{unmatched.join(',')}"
FAMILIES.each do |fam|
  count = population.count { |m| m.family == fam }
  puts "screenshot_family_#{fam[:key]}_count=#{count}"
  puts "screenshot_family_#{fam[:key]}_floor=#{fam[:floor]}"
  puts "screenshot_family_#{fam[:key]}_size=#{fam[:width]}x#{fam[:height]}"
end
puts "screenshot_dimension_checked=#{dimension_checked}"
puts "screenshot_alpha_checked=#{alpha_checked}"
puts "screenshot_measured_on=#{MEASURED_ON}"

verdict!
