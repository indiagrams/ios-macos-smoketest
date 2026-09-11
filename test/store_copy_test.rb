#!/usr/bin/env ruby
# frozen_string_literal: true

# D-124's store-copy gate. META-04 (iOS listing copy) and META-05 (macOS listing
# copy, which must DIVERGE from the iOS text -- D-121).
#
# WHY THIS FILE EXISTS
#
#   Twice now, text this fork sends to Apple has described screens the app does
#   not have. `fastlane/metadata/review_information/notes.txt` announced FIVE
#   screens, two of which never existed, and the worse of the two carried a
#   data-retention claim that contradicts `app/Shared/PrivacyInfo.xcprivacy` --
#   a submission arriving at App Review saying two different things about itself
#   (07-14-REVIEWNOTES-SUMMARY.md). The same two names then turned up in three
#   more passages, one of them the pre-drafted Resolution Center reply. Both
#   instances were caught by a HUMAN READING THE TEXT. Neither was caught by a
#   check, because no check existed. This is that check.
#
#   The population is deliberately WIDER than notes.txt: the listing copy itself
#   is text App Review reads, and a description naming a screen that does not
#   exist is the same defect in a field that is harder to correct after the fact.
#
# WHAT IT ASSERTS, BY CLAUSE
#
#   population   Three named sources, each contribution asserted and printed
#                SEPARATELY. A union that has stopped drawing from one source
#                looks identical to one that never did, which is this project's
#                "a correct check pointed at the wrong population" row.
#   placeholder  No listing value still carries the template's four-letter
#                placeholder prefix -- the one `fastlane/Fastfile:562` rejects
#                with `start_with?` and `bin/adopt.rb` filters on. It is NOT
#                spelled anywhere below; see THE ASSEMBLY RULE.
#   length       The keyword set fits App Store Connect's 100-character budget
#                and the subtitle fits 30, both asserted with the MEASURED
#                length in the message. `fastlane/metadata/en-US/subtitle.txt`
#                states the 30 in its own placeholder text.
#   divergence   Once both trees exist, the macOS description is not a byte copy
#                of the iOS one (D-121: the macOS listing leans on the 4.3(b)
#                case and cannot be the same paragraph). The shared fields --
#                `name` above all -- must NOT diverge: `appInfos` on record
#                6807393045 is total = 1, so name and subtitle are one object
#                (D-129, measured read-only 2026-09-10, 08-RESEARCH.md 3).
#   shared       AMENDED 2026-09-11 (plan 08-08). The shared set -- name,
#                subtitle, privacy_url -- is asserted PRESENT in the tree that
#                owns the one record and ABSENT from the other, two assertions
#                pointing in opposite directions. The original shape demanded all
#                three from BOTH trees, which the macOS tree cannot satisfy
#                without shipping a second copy of a one-record field; that made
#                the two halves of this gate's own reasoning contradict each
#                other, and the contradiction is resolved in favour of the
#                measurement. See the SPLIT BY SCOPE comment on the constants.
#   url         The three listing URLs are https and are not under the reserved
#                example domain. `precheck` reports that host as an advisory
#                HTTP-404 `warn` only, so an unreplaced URL still lands in App
#                Store Connect and is what a reviewer clicks.
#   surface      Every name presented as a NAVIGATION TARGET resolves through
#                `app/Shared/Localizable.xcstrings` -- the strings a user reads
#                -- not through Swift case names. `Destination.rawValue` IS the
#                catalog key (`app/Shared/Views/RootView.swift:68-77`), so the
#                Swift side cannot drift from the catalog; the copy can.
#
# EXIT CODES
#
#   0  every assertion passed, with the labelled counts printed.
#   1  at least one assertion failed, each naming what was expected and why.
#   2  NO VERDICT. The population could not be enumerated, or the catalog
#      yielded no allowed names at all. "Nobody looked" must never read as "it
#      is clean", so this path prints NOTHING on stdout -- not even a tick mark
#      -- and says CANNOT RUN on stderr. Every refusal below is evaluated
#      BEFORE the first assertion for exactly that reason.
#
#   The absent macOS tree is a NAMED FAILURE (exit 1), never an exception and
#   never a silent skip: an `Errno::ENOENT` with zero FAIL lines is read as
#   success by a `^FAIL`-grepping control. A macOS tree that EXISTS and is empty
#   is a refusal, because a scan over an empty population asserts nothing and
#   prints success.
#
# THE ASSEMBLY RULE -- why no token below is spelled
#
#   A file that configures a content gate is also swept by that gate. Six plans
#   in Phase 5 hit that by six different executors, and the sharpest instance
#   was an explanatory COMMENT that satisfied the very sweep it described. The
#   placeholder prefix, the reserved example domain and the two screen names
#   this clause exists to catch are therefore written SPACED and joined at run
#   time (`asm`, the shape of `test/privacy_manifest_test.rb:145-150`), so this
#   file cannot turn any sibling gate green -- or itself -- by existing.
#   `store_copy_name_tokens=assembled` records the route on stdout.
#   `app/Shared/Views/OutputAccessory.swift:34-36` is the same discipline from
#   the writing side.
#
#   The names are DESCRIBED here so a reader understands the file: they are the
#   two surfaces the pre-946bd4d notes invented -- one a canvas the notes called
#   the screen the app opens on, the other a session store whose description was
#   a retention claim. Neither ships. Neither is spelled.
#
# WHY TWO FAMILIES, NEVER A SCOPE GLOB
#
#   The allowed names come from two EXACT key prefixes, enumerated and asserted
#   apart, with their counts printed. A glob over the whole `shell`-scoped
#   namespace would silently accept any future scope-mate as a legitimate screen
#   name -- this repository's signature defect arriving through a naming choice.
#   That is also why a privacy-policy string belongs under the `app` scope and
#   not beside the destinations: the scope prefix below is DERIVED from the
#   family prefixes and is used for ONE thing only, counting the scope-mates
#   this gate deliberately leaves out, so that number moves when somebody adds
#   one.
#
# DEPENDENCIES: exactly one `require`, and it is a default gem shipped with the
# interpreter, which is what keeps `bundler-cache: false` honest in
# `.github/workflows/review-notes.yml:96`. There is deliberately no `digest`
# here: the divergence clause compares BYTES, which is what a digest comparison
# is minus the collision caveat, and prints byte lengths plus a documented
# non-cryptographic fingerprint instead.
#
# Every read of a text file pins its encoding ON THE CALL (UL-048). With LANG
# unset `Encoding.default_external` is US-ASCII and the first regex over a
# non-ASCII byte raises `invalid byte sequence in US-ASCII`, killing the run
# mid-way instead of producing a verdict. There is ONE reader below and every
# read goes through it.
#
# Runnable from the repository root, under BOTH pinned interpreters:
#   /opt/homebrew/opt/ruby@3.3/bin/ruby test/store_copy_test.rb
#   /opt/homebrew/opt/ruby@4.0/bin/ruby test/store_copy_test.rb
#
# Options:
#   --root DIR   scan a different tree. Used by the red/green controls in
#                .planning/.../evidence/08-03-store-copy-controls.txt, which is
#                the only reason a green is known to be reachable at all.

require "json"

USAGE = "Usage: ruby test/store_copy_test.rb [--root DIR]"

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

ROOT = root.nil? ? File.expand_path("..", __dir__) : File.expand_path(root)

# --- the tokens, ASSEMBLED -- never spelled ---------------------------------
# Written SPACED and joined at run time. See THE ASSEMBLY RULE above.

def asm(spaced)
  spaced.split(" ").join
end

PLACEHOLDER    = asm("T O D O")
EXAMPLE_DOMAIN = asm("e x a m p l e . c o m")
DRIFTED        = [asm("P i p e l i n e"), asm("H i s t o r y")].freeze

# --- the population, named before anything iterates -------------------------

IOS_METADATA_DIR   = "fastlane/metadata/en-US"
MACOS_METADATA_DIR = "fastlane/metadata-macos/en-US"
REVIEW_NOTES       = "fastlane/metadata/review_information/notes.txt"
CATALOG            = "app/Shared/Localizable.xcstrings"
METADATA_ROOTS     = ["fastlane/metadata", "fastlane/metadata-macos"].freeze

# The stems this gate reads by name, SPLIT BY SCOPE rather than by file kind.
#
# AMENDED 2026-09-11 by plan 08-08, and it is a CORRECTION, not a relaxation. The
# original split carried an unstated premise -- that both trees hold the same file
# set -- and measurement falsifies it. The macOS tree carries ONLY the per-platform
# fields (D-122), so the original shape demanded `subtitle.txt`, `privacy_url.txt`
# and `name.txt` from a tree that must not have them: three assertions satisfiable
# only by shipping a second copy of a one-record field, which is the very drift the
# shared clause exists to refuse. The deliverable count goes UP rather than down --
# the ABSENCE of each shared stem from the macOS tree is now asserted POSITIVELY,
# so this gate refuses a missing per-platform field AND a duplicated shared one.
#
#   PER PLATFORM -- description, keywords, release_notes, support_url,
#     marketing_url. TWO records, one per platform: two
#     `appStoreVersionLocalizations` on record 6807393045, deliver's
#     LOCALISED_VERSION_VALUES, and `GET /v1/apps/6807393045/searchKeywords`
#     REFUSING to answer without `filter[platform]` (HTTP 400, measured
#     read-only). These live in BOTH trees.
#   SHARED -- name, subtitle, privacy_url. ONE record, app-wide:
#     `appInfoLocalizations` is total = 1 (D-129), deliver's LOCALISED_APP_VALUES.
#     These live in the SHARED tree only.
#
# `support_url` sits in the same directory as `privacy_url` and looks like the same
# family. MEASURED, IT IS NOT -- LOCALISED_VERSION_VALUES against
# LOCALISED_APP_VALUES. That surprise is why the split below is written from the
# measurement rather than inferred from where a file happens to sit.
#
# The count of files present in a tree but swept by no copy clause there is printed
# as `store_copy_excluded` so it moves the day somebody adds a file to either tree.
COPY_STEMS        = %w[description keywords release_notes].freeze
URL_STEMS         = %w[support_url marketing_url].freeze
SHARED_COPY_STEMS = %w[subtitle].freeze
SHARED_URL_STEMS  = %w[privacy_url].freeze
SHARED_STEM       = "name"
SHARED_STEMS      = (SHARED_COPY_STEMS + SHARED_URL_STEMS + [SHARED_STEM]).freeze
# Which platform tree owns the one shared record. Named ONCE and never inferred
# from a path, so a second tree cannot become the shared one by being listed first.
SHARED_TREE       = "ios"

# App Store Connect's budgets. The 30 is stated by the tracked subtitle
# placeholder itself; the 100 is the keyword-field limit named in META-04.
KEYWORDS_LIMIT = 100
SUBTITLE_LIMIT = 30

# --- the catalog, two families, no glob -------------------------------------

DESTINATION_PREFIX = "shell.destination."
TAB_PREFIX         = "shell.tab."
APP_PREFIX         = "app."

# DERIVED, not spelled, and used only for the deliberately-excluded count.
SCOPE_PREFIX = DESTINATION_PREFIX[/\A[^.]+\./]

# Floors, not frozen equality. A floor refuses a VACUOUS pass without going red
# the day a fourth destination or a second tab label legitimately lands. The
# exact numbers are printed on every run.
MEASURED_ON       = "2026-09-10"
DESTINATION_FLOOR = 3
TAB_FLOOR         = 1

# --- assertion harness (test/privacy_manifest_test.rb:262-281, verbatim) -----

@failures = 0
@checks   = 0

def assert(condition, group, path, label)
  @checks += 1
  if condition
    puts "  #{'%-11s' % group} #{path}: #{label.to_s.gsub(/\s*\n\s*/) { ' ' }}"
  else
    puts "FAIL #{group} #{path}: #{label.to_s.gsub(/\s*\n\s*/) { ' ' }}"
    @failures += 1
  end
end

def verdict!
  puts
  if @failures.zero?
    puts "All #{@checks} store-copy assertions passed."
    exit 0
  else
    puts "#{@failures} of #{@checks} store-copy assertion(s) failed."
    exit 1
  end
end

# --- the one reader ---------------------------------------------------------

def read_text(rel)
  File.read(File.join(ROOT, rel), encoding: "UTF-8")
end

# A deterministic, dependency-free 64-bit fingerprint (FNV-1a). NOT a
# cryptographic digest and never described as one: the divergence clause
# asserts BYTE INEQUALITY and this number is printed beside it so two runs can
# be compared by eye without reproducing the text.
def fingerprint(value)
  hash = 0xcbf29ce484222325
  value.to_s.each_byte do |byte|
    hash = ((hash ^ byte) * 0x100000001b3) & 0xffffffffffffffff
  end
  format("%016x", hash)
end

# --- enumeration ------------------------------------------------------------

def txt_basenames(dir)
  abs = File.join(ROOT, dir)
  return nil unless Dir.exist?(abs)

  Dir.glob(File.join(abs, "*.txt")).sort.map { |path| File.basename(path) }
end

ios_files   = txt_basenames(IOS_METADATA_DIR)
macos_files = txt_basenames(MACOS_METADATA_DIR)
notes_abs   = File.join(ROOT, REVIEW_NOTES)

# --- refusals, ALL of them, before the first assertion ----------------------

no_verdict("#{IOS_METADATA_DIR} does not exist under #{ROOT} -- the iOS listing tree is " \
           "this gate's anchor population and there is nothing to scan") if ios_files.nil?
no_verdict("#{IOS_METADATA_DIR} holds no .txt file under #{ROOT} -- a scan over an empty " \
           "population asserts nothing and prints success") if ios_files.empty?
no_verdict("#{MACOS_METADATA_DIR} exists under #{ROOT} and holds no .txt file -- an empty " \
           "tree is not the same fact as an absent one, and a scan over it asserts " \
           "nothing and prints success") if !macos_files.nil? && macos_files.empty?
no_verdict("#{REVIEW_NOTES} not found under #{ROOT} -- the text App Review reads before " \
           "it opens the app is one of the three named sources") unless File.file?(notes_abs)

notes_text = read_text(REVIEW_NOTES)
no_verdict("#{REVIEW_NOTES} is empty under #{ROOT}") if notes_text.strip.empty?

no_verdict("#{CATALOG} not found under #{ROOT} -- every allowed screen name is resolved " \
           "through it, so without it this gate can neither pass nor fail a name") \
  unless File.file?(File.join(ROOT, CATALOG))

catalog = begin
  JSON.parse(read_text(CATALOG))
rescue JSON::ParserError => e
  no_verdict("#{CATALOG} is not parseable JSON (#{e.message.lines.first.to_s.strip}) -- " \
             "a hopeful regex over it would be a second opinion about what the app says")
end

strings = catalog["strings"]
no_verdict("#{CATALOG} carries no `strings` object under #{ROOT}") unless strings.is_a?(Hash)
no_verdict("#{CATALOG} carries an EMPTY `strings` object under #{ROOT}") if strings.empty?

def english(entry)
  entry.is_a?(Hash) ? entry.dig("localizations", "en", "stringUnit", "value") : nil
end

destination_keys = strings.keys.select { |key| key.start_with?(DESTINATION_PREFIX) }.sort
tab_keys         = strings.keys.select { |key| key.start_with?(TAB_PREFIX) }.sort
scope_keys       = strings.keys.select { |key| key.start_with?(SCOPE_PREFIX) }.sort
app_keys         = strings.keys.select { |key| key.start_with?(APP_PREFIX) }.sort

destination_names = destination_keys.map { |key| english(strings[key]) }.compact
tab_names         = tab_keys.map { |key| english(strings[key]) }.compact
app_names         = app_keys.map { |key| english(strings[key]) }.compact

allowed    = (destination_names + tab_names).map { |value| value.to_s.strip }.reject(&:empty?).uniq.sort
allowed_ci = allowed.map(&:downcase)

no_verdict("the two navigation-target key families in #{CATALOG} under #{ROOT} resolved " \
           "NO English values (#{destination_keys.length} `#{DESTINATION_PREFIX}` key(s), " \
           "#{tab_keys.length} `#{TAB_PREFIX}` key(s)) -- an allowed set of zero either " \
           "passes every name or fails every name, and neither is a measurement") if allowed.empty?

# --- P1: the population, each source's contribution asserted separately -----

assert !macos_files.nil?, "population", MACOS_METADATA_DIR,
       "the macOS metadata tree is absent, so META-05's population is empty and every " \
       "macOS assertion below it would be about nothing. Plan 08-08 creates this tree; " \
       "until it does, the divergence clause is UNRUNNABLE rather than passing"
IOS_NAMED_STEMS   = (COPY_STEMS + URL_STEMS + SHARED_STEMS).sort.freeze
MACOS_NAMED_STEMS = (COPY_STEMS + URL_STEMS).sort.freeze

assert ios_files.length >= IOS_NAMED_STEMS.length, "population", IOS_METADATA_DIR,
       "the iOS listing tree holds #{ios_files.length} .txt file(s), at or above the " \
       "#{IOS_NAMED_STEMS.length} this gate reads by name (#{IOS_NAMED_STEMS.join(', ')}); " \
       "a shorter list means a clause below is asking about a file that is not there"
unless macos_files.nil?
  assert macos_files.length >= MACOS_NAMED_STEMS.length, "population", MACOS_METADATA_DIR,
         "the macOS listing tree holds #{macos_files.length} .txt file(s), at or above the " \
         "#{MACOS_NAMED_STEMS.length} this gate reads by name " \
         "(#{MACOS_NAMED_STEMS.join(', ')}). Asserted APART from the iOS floor, because the " \
         "two trees do not hold the same file set and one shared floor would hide a short one"
end
assert notes_text.length > 500, "population", REVIEW_NOTES,
       "the review notes hold #{notes_text.length} characters; a stub file would make the " \
       "surface-name clause vacuous while looking like a source"

trees = [["ios", IOS_METADATA_DIR, ios_files], ["macos", MACOS_METADATA_DIR, macos_files]]
present_trees = trees.reject { |(_platform, _dir, files)| files.nil? }
assert !present_trees.empty?, "population", "-",
       "at least one metadata tree is present (#{present_trees.map(&:first).join(', ')}); " \
       "an `each` over an empty collection asserts nothing and reports success"

# --- P2-P4: placeholder copy, lengths, URLs, shared fields ------------------

values   = {}
excluded = []

present_trees.each do |platform, dir, files|
  values[platform] = {}
  shared_here      = platform == SHARED_TREE
  copy_stems_here  = COPY_STEMS + (shared_here ? SHARED_COPY_STEMS : [])
  url_stems_here   = URL_STEMS  + (shared_here ? SHARED_URL_STEMS  : [])

  copy_stems_here.each do |stem|
    scope   = SHARED_STEMS.include?(stem) ? "shared" : "per-platform"
    rel     = "#{dir}/#{stem}.txt"
    present = files.include?("#{stem}.txt")
    assert present, "copy", rel,
           "the #{platform} listing #{stem} (#{scope}) exists on disk. deliver's " \
           "`load_from_filesystem` reads these fields off disk only -- there is no env " \
           "route for them (08-RESEARCH 372) -- so a missing file is a field nobody set"
    next unless present

    value = read_text(rel)
    values[platform][stem] = value

    assert !value.strip.empty?, "copy", rel,
           "the #{platform} listing #{stem} is non-empty"
    assert !value.include?(PLACEHOLDER), "placeholder", rel,
           "the #{platform} listing #{stem} carries no placeholder copy. The template ships " \
           "a four-letter placeholder prefix in every listing .txt -- the one " \
           "`fastlane/Fastfile:562` rejects with `start_with?` -- and a value still carrying " \
           "it is text that would ship to App Review as this fork's #{stem}"
  end

  if values[platform].key?("keywords")
    measured = values[platform]["keywords"].strip.length
    assert measured <= KEYWORDS_LIMIT, "length", "#{dir}/keywords.txt",
           "the #{platform} keyword set is #{measured} character(s) against App Store " \
           "Connect's limit of #{KEYWORDS_LIMIT}; the field is truncated or rejected at " \
           "upload, not at review, so the shortfall is invisible in the tracked file"
  end

  if values[platform].key?("subtitle")
    measured = values[platform]["subtitle"].strip.length
    assert measured <= SUBTITLE_LIMIT, "length", "#{dir}/subtitle.txt",
           "the #{platform} subtitle is #{measured} character(s) against the limit of " \
           "#{SUBTITLE_LIMIT} the tracked placeholder itself states. Counted with " \
           "String#length on a UTF-8 read, so an accented letter or a dash is ONE character " \
           "here and one character to App Store Connect"
  end

  url_stems_here.each do |stem|
    scope   = SHARED_STEMS.include?(stem) ? "shared" : "per-platform"
    rel     = "#{dir}/#{stem}.txt"
    present = files.include?("#{stem}.txt")
    assert present, "url", rel, "the #{platform} #{stem} (#{scope}) exists on disk"
    next unless present

    value = read_text(rel).strip
    values[platform][stem] = value

    assert value.start_with?("https://"), "url", rel,
           "the #{platform} #{stem} is https (measured #{value.inspect})"
    host = value[%r{\Ahttps?://([^/?#]+)}, 1].to_s.downcase
    under_example = host == EXAMPLE_DOMAIN || host.end_with?(".#{EXAMPLE_DOMAIN}")
    assert !under_example, "url", rel,
           "the #{platform} #{stem} is not under the reserved example domain (measured host " \
           "#{host.inspect}). `precheck` reports that host at advisory `warn` level as an " \
           "HTTP 404 only, so the unreplaced URL still lands in App Store Connect and is " \
           "what App Review clicks"
  end

  # The app name. Asserted PRESENT in the tree that owns the one shared record, and
  # asserted ABSENT from every other tree by the second-copy clause in P5 -- two
  # assertions pointing in OPPOSITE directions, so neither a missing name nor a
  # duplicated one can pass.
  if shared_here
    rel     = "#{dir}/#{SHARED_STEM}.txt"
    present = files.include?("#{SHARED_STEM}.txt")
    assert present, "shared", rel,
           "the #{platform} app #{SHARED_STEM} exists on disk, in the tree that owns the one " \
           "shared record (SHARED_TREE = #{SHARED_TREE.inspect})"
    if present
      value = read_text(rel).strip
      values[platform][SHARED_STEM] = value
      assert !value.include?(PLACEHOLDER), "placeholder", rel,
             "the app #{SHARED_STEM} carries no placeholder copy; it is the first string App " \
             "Review reads"
    end
  elsif files.include?("#{SHARED_STEM}.txt")
    # Read it even though it should not be here, so the cross-tree equality clause in
    # P5 still has both values and a wrong tree reports TWICE: once as a second copy,
    # and once as a value that disagrees, if it does.
    values[platform][SHARED_STEM] = read_text("#{dir}/#{SHARED_STEM}.txt").strip
  end

  # Swept-by-no-copy-clause, computed PER TREE against that tree's OWN stems. The two
  # trees do not sweep the same set, and one global reject would report the shared
  # stems as excluded in the very tree that sweeps them.
  excluded.concat(files.reject { |file| copy_stems_here.include?(File.basename(file, ".txt")) }
                       .map { |file| "#{dir}/#{file}" })
end

# Files that live in a metadata tree but OUTSIDE the locale directory this gate
# enumerates -- `copyright.txt` today. Printed as a number so it moves.
outside_locale = METADATA_ROOTS.flat_map do |tree|
  abs = File.join(ROOT, tree)
  Dir.exist?(abs) ? Dir.glob(File.join(abs, "*.txt")).sort : []
end

# --- P5: divergence, and the fields that must NOT diverge -------------------

ios_description   = values.dig("ios", "description")
macos_description = values.dig("macos", "description")

if ios_description && macos_description
  assert ios_description.strip != macos_description.strip, "divergence",
         "#{IOS_METADATA_DIR}/description.txt + #{MACOS_METADATA_DIR}/description.txt",
         "the macOS description is not a byte copy of the iOS one (iOS " \
         "#{ios_description.strip.length} bytes / #{fingerprint(ios_description.strip)}, macOS " \
         "#{macos_description.strip.length} bytes / #{fingerprint(macos_description.strip)}). " \
         "D-121 requires the macOS listing to lean on the 4.3(b) case, which the iOS " \
         "paragraph does not make"
end

# The shared record has exactly ONE home on disk, and this is the clause that says
# so. It is the MIRROR of the presence clause above: that one refuses a missing
# shared field in the tree that owns it, this one refuses a SECOND copy anywhere
# else. A gate that only checked presence would be satisfied by duplicating the
# record into both trees, which is the drift it exists to catch.
unless macos_files.nil?
  second_copies = SHARED_STEMS.select { |stem| macos_files.include?("#{stem}.txt") }
  assert second_copies.empty?, "shared", MACOS_METADATA_DIR,
         "the macOS tree carries NO second copy of a shared record (shared set: " \
         "#{SHARED_STEMS.sort.join(', ')}; found: " \
         "#{second_copies.empty? ? 'none' : second_copies.sort.join(', ')}). " \
         "`appInfoLocalizations` is total = 1 on record 6807393045 (D-129, measured " \
         "read-only #{MEASURED_ON}), so app name, subtitle and the privacy policy URL are " \
         "ONE object each. A file per tree is two values behind one label, and deliver " \
         "writes whichever lane ran last -- a divergence nobody chose and no run reports"
end

ios_name   = values.dig("ios", SHARED_STEM)
macos_name = values.dig("macos", SHARED_STEM)
if ios_name && macos_name
  assert ios_name == macos_name, "shared",
         "#{IOS_METADATA_DIR}/#{SHARED_STEM}.txt + #{MACOS_METADATA_DIR}/#{SHARED_STEM}.txt",
         "the app #{SHARED_STEM} is IDENTICAL across the two trees (#{ios_name.inspect} / " \
         "#{macos_name.inspect}). Under Universal Purchase `appInfos` is total = 1 on record " \
         "6807393045 (D-129, measured read-only #{MEASURED_ON}), so name and subtitle are one " \
         "shared object -- writing two different values delivers whichever lane ran last"
end

# --- P6: the catalog, two families, counted and asserted APART --------------

assert destination_keys.length >= DESTINATION_FLOOR, "catalog", CATALOG,
       "the `#{DESTINATION_PREFIX}` family holds #{destination_keys.length} key(s) " \
       "(#{destination_keys.join(', ')}), at or above the floor of #{DESTINATION_FLOOR} " \
       "measured #{MEASURED_ON}. The floor refuses a vacuous allowed set; it is not a " \
       "number to freeze, and a fourth destination is not a failure"
assert destination_names.length == destination_keys.length, "catalog", CATALOG,
       "every `#{DESTINATION_PREFIX}` key resolves to an English value " \
       "(#{destination_names.length} of #{destination_keys.length}); a key with no " \
       "`stringUnit` would silently shrink the allowed set"
assert tab_keys.length >= TAB_FLOOR, "catalog", CATALOG,
       "the `#{TAB_PREFIX}` family holds #{tab_keys.length} key(s) (#{tab_keys.join(', ')}), " \
       "at or above the floor of #{TAB_FLOOR} measured #{MEASURED_ON}. It is asserted apart " \
       "from the destination family on purpose: one family silently emptying is invisible " \
       "in a union"
assert tab_names.length == tab_keys.length, "catalog", CATALOG,
       "every `#{TAB_PREFIX}` key resolves to an English value (#{tab_names.length} of " \
       "#{tab_keys.length})"
assert (allowed_ci & DRIFTED.map(&:downcase)).empty?, "catalog", CATALOG,
       "neither of the two names this clause exists to catch resolves through the catalog. " \
       "Both are DESCRIBED in this file's header and neither is spelled in its source; if " \
       "one ever became a real string, this gate would start accepting the very text it was " \
       "written to refuse"
assert (allowed & app_names).empty?, "catalog", CATALOG,
       "no `#{APP_PREFIX}`-scoped string is in the allowed navigation-target set " \
       "(#{app_keys.length} such key(s) today). The allowed set is built from two EXACT " \
       "family prefixes and never from a scope glob, so a string added for something that " \
       "is not a screen -- a privacy-policy link, say -- cannot become a legitimate screen " \
       "name by sitting in the same namespace"

# --- P7: the surface-name clause --------------------------------------------
#
# Section extraction, never a whole-file grep: these documents DISCUSS screen
# names in prose, and a whole-file grep would match the sentence describing the
# rule (`test/docs_structure_test.rb:214-227` states the same rule for the same
# reason). notes.txt carries ALL-CAPS heading lines rather than Markdown
# headings, so the helper below is that shape adapted to this document.

SCREEN_LIST_HEADING = /\bSCREENS\b/
WALKTHROUGH_HEADING = /\bWALKTHROUGH\b/
ALL_CAPS_HEADING    = /\A[A-Z][A-Z0-9 ,.:;'()\/-]*\z/

def heading?(line)
  text = line.chomp
  return false if text.empty? || text.start_with?(" ", "\t") || text.length > 60

  text.match?(ALL_CAPS_HEADING)
end

def plain_section(text, heading_re)
  lines = text.lines
  start = lines.index { |line| heading?(line) && line.chomp.match?(heading_re) }
  return nil if start.nil?

  stop = lines.each_with_index.find { |line, index| index > start && heading?(line) }
  lines[start...(stop ? stop[1] : lines.length)].join
end

# A token is a CANDIDATE when the text presents it as a navigation target: a
# quoted or capitalised name immediately followed by a navigation noun. That
# construction is what keeps the tracked notes' own sentence about the app's
# MODEL -- the one in the enumerated-screen section that uses, in lower case and
# as a common noun, the same word as one of the two drifted names -- out of the
# candidate set, while "the X tab" and "the X sidebar item" are in it. Longest
# noun first so the alternation cannot match a shorter prefix of a longer
# phrase.
NAV_NOUNS = ["item in the sidebar", "sidebar item", "tab", "screen", "pane", "sidebar"].freeze
# MEASURED, not assumed: an earlier draft interpolated these nouns into an /x
# pattern with their spaces intact, and /x DISCARDS literal whitespace -- so
# "item in the sidebar" became one unbroken word, matched nothing, and the
# extractor quietly returned 10 candidates instead of 11 while every assertion
# stayed green. Each noun's internal spaces are therefore compiled to `\s+`,
# which also lets a noun wrap across a line break.
NAV_NOUN_RE = NAV_NOUNS.map { |noun| noun.split(" ").map { |word| Regexp.escape(word) }.join('\s+') }
                       .join("|").freeze
NAV_RE      = /
  (?:"(?<quoted>[^"]{1,40})" | (?<bare>[A-Z][A-Za-z0-9\/]*(?:\s[A-Z][A-Za-z0-9\/]*){0,2}))
  \s+(?:#{NAV_NOUN_RE})\b
/x
# The leading name of an entry in an enumerated screen list: `1. Name - prose`.
ENUM_RE = /\A\s*\d+[.)]\s+(?<name>\S[^\n]*?)\s+[-–—]\s/

def nav_names(text, where)
  # Collapsed to single spaces first: the quoted name and its navigation noun
  # are wrapped across a line break in the tracked notes, and a line-at-a-time
  # scan would silently drop those candidates.
  flat    = text.gsub(/\s+/) { " " }
  matches = []
  flat.scan(NAV_RE) { matches << Regexp.last_match }
  matches.map { |match| [(match[:quoted] || match[:bare]).to_s.strip, where] }
end

def enumerated_names(text, where)
  text.lines.filter_map do |line|
    match = line.match(ENUM_RE)
    match ? [match[:name].strip, where] : nil
  end
end

screens_section     = plain_section(notes_text, SCREEN_LIST_HEADING)
walkthrough_section = plain_section(notes_text, WALKTHROUGH_HEADING)

assert !screens_section.nil?, "surface", REVIEW_NOTES,
       "the enumerated-screen section is present (an ALL-CAPS heading matching " \
       "#{SCREEN_LIST_HEADING.inspect}). An extractor that cannot find its section reports " \
       "zero offending names on every tree, which is a pass that has not looked"
assert !walkthrough_section.nil?, "surface", REVIEW_NOTES,
       "the walkthrough section is present (an ALL-CAPS heading matching " \
       "#{WALKTHROUGH_HEADING.inspect}); it names screens too, and the pre-946bd4d notes " \
       "opened it by telling a reviewer to open a screen that does not exist"

# THREE ROUTES, counted apart for the same reason the population is: a route
# that has silently stopped matching is invisible inside a total.
from_list = screens_section ? enumerated_names(screens_section, REVIEW_NOTES) : []
from_nav  = (screens_section ? nav_names(screens_section, REVIEW_NOTES) : []) +
            (walkthrough_section ? nav_names(walkthrough_section, REVIEW_NOTES) : [])
from_copy = present_trees.flat_map do |platform, dir, _files|
  description = values.dig(platform, "description")
  description ? nav_names(description, "#{dir}/description.txt") : []
end

candidates        = from_list + from_nav + from_copy
unique_candidates = candidates.uniq

assert !candidates.empty?, "surface", "-",
       "the extractor found #{candidates.length} name(s) presented as navigation targets " \
       "across the named sources. An extractor that matches nothing passes on ANY tree, " \
       "which is D-124's stated non-vacuity hazard and the reason this count is printed as " \
       "`store_copy_name_candidates` on every run"
assert !from_list.empty?, "surface", REVIEW_NOTES,
       "the enumerated-screen route contributed #{from_list.length} name(s). Zero means the " \
       "list stopped being a numbered list and this route now checks nothing, which is " \
       "invisible in the total beside the other routes"
assert !from_nav.empty?, "surface", REVIEW_NOTES,
       "the navigation-noun route contributed #{from_nav.length} name(s) across the two " \
       "extracted sections. Zero means the phrasing moved and the route matches nothing"

unique_candidates.each do |name, where|
  drifted = DRIFTED.any? { |token| token.casecmp?(name) }
  assert allowed_ci.include?(name.downcase), "surface", where,
         "#{name.inspect} is presented as a navigation target and resolves through " \
         "#{CATALOG} (allowed: #{allowed.join(' | ')})" \
         "#{drifted ? '. This is one of the two names a corrected notes.txt no longer ' \
                      'carries -- the drift this gate exists to catch, arriving again' : ''}"
end

# --- labelled counts, printed on success as well as on failure --------------

puts
puts "store_copy_from_ios=#{ios_files.length}"
puts "store_copy_from_macos=#{macos_files.nil? ? 0 : macos_files.length}"
puts "store_copy_from_notes=#{File.file?(notes_abs) ? 1 : 0}"
puts "store_copy_total=#{ios_files.length + (macos_files.nil? ? 0 : macos_files.length) + 1}"
puts "store_copy_excluded=#{excluded.length}"
puts "store_copy_excluded_names=#{excluded.map { |rel| File.basename(rel) }.uniq.sort.join(',')}"
puts "store_copy_outside_locale=#{outside_locale.length}"
puts "store_copy_macos_tree=#{macos_files.nil? ? 'absent' : 'present'}"
puts "store_copy_per_platform_stems=#{(COPY_STEMS + URL_STEMS).sort.join(',')}"
puts "store_copy_shared_stems=#{SHARED_STEMS.sort.join(',')}"
puts "store_copy_shared_tree=#{SHARED_TREE}"
puts "store_copy_shared_second_copies=#{macos_files.nil? ? 'unrunnable' : SHARED_STEMS.count { |s| macos_files.include?("#{s}.txt") }}"
puts "store_copy_ios_description_bytes=#{ios_description.to_s.strip.length}"
puts "store_copy_ios_description_fnv1a64=#{ios_description ? fingerprint(ios_description.strip) : 'none'}"
puts "store_copy_macos_description_bytes=#{macos_description.to_s.strip.length}"
puts "store_copy_macos_description_fnv1a64=#{macos_description ? fingerprint(macos_description.strip) : 'none'}"
puts "store_copy_catalog_keys=#{strings.length}"
puts "store_copy_catalog_destinations=#{destination_keys.length}"
puts "store_copy_catalog_tabs=#{tab_keys.length}"
puts "store_copy_catalog_allowed=#{allowed.length}"
puts "store_copy_catalog_scope=#{scope_keys.length}"
puts "store_copy_catalog_excluded=#{(scope_keys - destination_keys - tab_keys).length}"
puts "store_copy_catalog_app_scoped=#{app_keys.length}"
puts "store_copy_catalog_allowed_names=#{allowed.join('|')}"
puts "store_copy_name_candidates=#{candidates.length}"
puts "store_copy_name_from_list=#{from_list.length}"
puts "store_copy_name_from_nav=#{from_nav.length}"
puts "store_copy_name_from_copy=#{from_copy.length}"
puts "store_copy_name_unique=#{unique_candidates.length}"
puts "store_copy_name_resolved=#{unique_candidates.map(&:first).uniq.sort.join('|')}"
puts "store_copy_name_tokens=assembled"
puts "store_copy_sections_found=#{[screens_section, walkthrough_section].compact.length}"
puts "store_copy_measured_on=#{MEASURED_ON}"

verdict!
