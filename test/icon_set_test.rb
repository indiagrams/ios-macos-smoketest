#!/usr/bin/env ruby
# frozen_string_literal: true

# META-01 / criterion 1 — the app icon set is complete and carries no alpha, over
# a population that contains EVERY slot on BOTH platforms, including the one that
# actually ships.
#
# WHY THIS FILE EXISTS, AND WHY IT IS NOT AN EDIT TO ci/check-app-icon.sh
#
#   The template gate ci/check-app-icon.sh is CORRECT. It is also pointed at two
#   files: the iOS 1024 it resolves from Contents.json (:135-153) and the literal
#   app/macOS/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png (:152-153).
#   Criterion 1 says "every other slot". The nine other macOS slots, the generator's
#   1024 source, and app/macOS/Resources/AppIcon.icns are outside its population.
#
#   The .icns is not a spare copy. app/project.yml:152-169 runs a
#   postCompileScripts step that copies it OVER actool's four-size output before
#   Code Sign, and ASSETCATALOG_COMPILER_APPICON_NAME: "" suppresses
#   CFBundleIconName so macOS reads CFBundleIconFile → that .icns. THE .icns
#   IS THE ICON THAT SHIPS, and until this file existed nothing had ever opened it.
#
#   This is the project's signature defect — a correct check pointed at the wrong
#   POPULATION — so the answer is a WIDER population, not a different check.
#   ci/ is template-owned (AGENTS.md), so this is a new fork-owned file and
#   ci/check-app-icon.sh is invoked read-only as one of the sources of truth.
#
# WHAT IS ASSERTED, AND OVER WHICH POPULATION
#
#   A  app/iOS/Assets.xcassets/AppIcon.appiconset      every images[].filename
#   B  app/macOS/Assets.xcassets/AppIcon.appiconset    every images[].filename
#   C1 app/macOS/Resources/AppIcon.icns                every member iconutil extracts
#   C2 app/macOS/Resources/AppIcon-source-1024.png     the generator's input
#   D  a built .app, only with --built-app             the .icns its Info.plist names
#
#   Each source's contribution is asserted and printed SEPARATELY. A union that has
#   stopped drawing from one source looks identical to one that never did.
#   icon_unenumerated= prints the icon-shaped artefacts deliberately left out, as
#   a NUMBER, so it moves when somebody adds one.
#
#   Members come out of Contents.json by PARSE, never out of a directory listing.
#   A slot declared and absent and a slot present and undeclared are different
#   defects and get different messages.
#
# TWO MEASUREMENTS THIS FILE IS BUILT AROUND (both made 2026-09-10, on this tree)
#
#   1. iconutil -c icns ALWAYS stores the 16pt and 32pt @1x entries as the raw
#      ARGB container types ic04/ic05. An iconset whose ten PNGs ALL report
#      hasAlpha: no round-trips through iconutil -c icns → -c iconset with
#      hasAlpha: yes on exactly those two members. The alpha channel there is a
#      property of the CONTAINER FORMAT, not of the artwork, so a flat
#      "hasAlpha must be no" over .icns members is unsatisfiable by construction
#      — no .icns any Apple tool can produce would pass it.
#      This gate therefore reads those two entries HARDER rather than skipping
#      them: it decodes the ARGB payload with the icns run-length coding and
#      asserts EVERY alpha byte is 0xFF. Real transparency fails; a mandatory
#      channel that is fully opaque does not. icon_alpha_via_argb_decode= counts
#      how many members took that route, so it cannot quietly become zero.
#      An .icns image chunk that is neither PNG-stored nor a raw type this gate
#      can decode is a THIRD STATE and fails as one.
#
#   2. sips EXITS 0 ON A FILE THAT DOES NOT EXIST — sips -g hasAlpha /tmp/nope.png
#      prints "Warning: … not a valid file - skipping" to stderr and returns 0.
#      Any alpha check that trusts sips's exit code is green on an absent icon.
#      So every property read here fails unless the PROPERTY ITSELF came back on
#      stdout, and the tool's exit code is carried in the message beside it.
#
# THE ASSEMBLY RULE
#
#   The one environment-variable name this gate reacts to is written SPACED and
#   joined at run time, never spelled. A file that configures a content gate is
#   also swept by that gate, and six plans in Phase 5 were hit by exactly that.
#   icon_override_token=assembled records the route on stdout.
#
# Every shell-out is an argv array — quoting has silently changed a candidate set
# in this repository before. Every exit code is captured on the statement after the
# call and nothing is ever piped before its status is read (08-RESEARCH Pitfall 4:
# bash ci/check-app-icon.sh 2>&1 | tail -40; echo "EXIT=$?" prints EXIT=0).
#
# Runnable from the repository root, under BOTH pinned interpreters:
#   /opt/homebrew/opt/ruby@3.3/bin/ruby test/icon_set_test.rb
#   /opt/homebrew/opt/ruby@4.0/bin/ruby test/icon_set_test.rb
#
# Options:
#   --root DIR        inspect a different tree (used by the negative controls)
#   --icns PATH       inspect a different .icns as source C1 (controls only; the
#                     path in use is always printed as icon_icns_source=)
#   --built-app PATH  a built .app whose EMBEDDED icon is inspected as source D,
#                     the shape test/app_offline_test.rb already takes

require "json"

USAGE = "Usage: ruby test/icon_set_test.rb [--root DIR] [--icns PATH] [--built-app PATH]"

def no_verdict(message)
  warn "CANNOT RUN: #{message}"
  exit 2
end

root      = nil
icns_arg  = nil
built_app = nil
argv      = ARGV.dup
until argv.empty?
  case (arg = argv.shift)
  when "--root"       then root      = argv.shift or no_verdict("--root needs a directory. #{USAGE}")
  when "--icns"       then icns_arg  = argv.shift or no_verdict("--icns needs a path. #{USAGE}")
  when "--built-app"  then built_app = argv.shift or no_verdict("--built-app needs a path. #{USAGE}")
  when "-h", "--help" then puts USAGE ; exit 0
  else no_verdict("unrecognised argument #{arg.inspect}. #{USAGE}")
  end
end

ROOT = File.expand_path(root || File.join(__dir__, ".."))
no_verdict("--root #{ROOT} is not a directory") unless File.directory?(ROOT)

MEASURED_ON = "2026-09-10"

# ─── the tokens, ASSEMBLED — never spelled ───────────────────────────────────
def asm(spaced)
  spaced.split(" ").join
end

# ─── paths, relative to ROOT ─────────────────────────────────────────────────

IOS_SET_REL    = "app/iOS/Assets.xcassets/AppIcon.appiconset"
MACOS_SET_REL  = "app/macOS/Assets.xcassets/AppIcon.appiconset"
ICNS_REL       = "app/macOS/Resources/AppIcon.icns"
ICNS_SRC_REL   = "app/macOS/Resources/AppIcon-source-1024.png"
TEMPLATE_GATE_REL = "ci/check-app-icon.sh"

ICNS_PATH = icns_arg ? File.expand_path(icns_arg) : File.join(ROOT, ICNS_REL)

# Apple's own wording, carried into every alpha failure so the message says what
# the reviewer will say. App Store Connect rejects a marketing icon outright for
# this; on macOS it is also what turns a Dock icon into a ghost.
APPLE_ALPHA = "images can't include alpha channels or transparencies"

# icns container types that store RAW ARGB rather than a PNG, with the pixel side
# each one carries. This is the FILE FORMAT, not a population list: the population
# is whatever chunks the artefact turns out to contain. The side is VERIFIED at run
# time — the decode must yield exactly side*side*4 bytes or the entry fails as a
# third state rather than being trusted.
ICNS_ARGB_SIDES = { "ic04" => 16, "ic05" => 32 }.freeze

# THE 2.3.8 PROXY. This threshold MIRRORS ci/check-app-icon.sh:85 and the four
# sampling constants mirror its icon_spread() at :101-130. It is NOT imported:
# that script is template-owned (AGENTS.md), a fork gate that sourced it would
# break the moment upstream moved a line, and a silent duplicate is worse than a
# labelled one. If upstream changes its threshold, this constant and that line
# are ONE UNIT and both get re-measured.
#
# What it measures: quantise the icon to 8 levels per channel, keep the colour
# clusters covering at least 3% of the canvas, and take the largest distance
# between any two of them. Artwork puts distant clusters on the canvas; a flat
# fill or a bare gradient does not. Measured upstream: placeholder 0, real icon
# 282. The gap is wide enough that 40 is not a knife edge.
#
# This is Guideline 2.3.8, and upstream learned it from Apple the expensive way:
# a placeholder icon came back as a rejection, one full review cycle spent
# (ci/check-app-icon.sh:4-13, C-29).
SPREAD_FLOOR      = 40
SPREAD_SAMPLE     = 64
SPREAD_QUANTISE   = 32
SPREAD_MIN_SHARE  = 0.03

# Below this size an icon legitimately carries no detail to measure -- the
# 16/32/64 slots are redrawn as a simplified mark by ci/gen-macos-icons.swift
# precisely because the 1024 artwork turns to mush there. Printed as
# icon_spread_min_pixels= so the exclusion is a number rather than a silence.
SPREAD_MIN_PIXELS = 128

# The escape-hatch environment variable, SPACED and joined at run time so this
# file never spells it. A file that configures a content gate is also swept by
# that gate.
OVERRIDE_VAR = asm("A L L O W _ P L A C E H O L D E R _ I C O N")

PNG_MAGIC  = "\x89PNG\r\n\x1a\n".b
ARGB_MAGIC = "ARGB".b

# ─── assertion harness (test/privacy_manifest_test.rb:262-281, verbatim) ─────

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
    puts "All #{@checks} icon-set assertions passed."
    exit 0
  else
    puts "#{@failures} of #{@checks} icon-set assertion(s) failed."
    exit 1
  end
end

# ─── helpers ─────────────────────────────────────────────────────────────────

# argv array, never a shell string.
#
# The child's output is read with its encoding PINNED. A subprocess read inherits
# Encoding.default_external, so with LANG and LC_ALL unset the String comes back
# tagged US-ASCII and the first strip, concatenation or regex over non-ASCII bytes
# raises Encoding::CompatibilityError -- UL-048's class, arriving on the
# subprocess side rather than the file side. sips echoes the PATH it was given
# back on its first line, so a repository checked out under a non-ASCII path is
# all it takes. test/encoding_test.rb caught this on its first run against this
# file.
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

# sips exits 0 on a file that does not exist (MEASURED #{MEASURED_ON}), so the
# RESULT is the set of properties that actually came back, and the exit code rides
# along in the message rather than standing in for the answer.
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

# The pixel side a catalog declaration implies: size x scale. Derived from the
# parsed declaration, never from the filename, so a slot whose name and
# declaration disagree is measured against what actool will actually build.
def nominal_side(img)
  size = img.is_a?(Hash) ? img["size"].to_s : ""
  m = size.match(/\A(\d+)(?:\.\d+)?x/)
  return nil unless m
  scale = (img["scale"].to_s[/\A(\d+)/, 1] || "1").to_i
  scale = 1 if scale.zero?
  m[1].to_i * scale
end

# The pixel side an ICONSET MEMBER NAME implies. iconutil names what it extracts,
# so here the name IS the artefact's own statement about itself.
def nominal_side_from_name(name)
  m = name.match(/\Aicon_(\d+)x\d+(?:@(\d+)x)?\.png\z/)
  return nil unless m
  m[1].to_i * (m[2] ? m[2].to_i : 1)
end

def read_json(abs)
  JSON.parse(File.read(abs, encoding: "UTF-8"))
rescue StandardError => e
  { "__error__" => "#{e.class}: #{e.message}" }
end

# Walk the icns container: 8-byte header, then type/length/payload triples.
def icns_chunks(abs)
  d = File.binread(abs)
  return [nil, "shorter than an icns header (#{d.bytesize} bytes)"] if d.bytesize < 8
  return [nil, "no icns magic (starts #{d.byteslice(0, 4).inspect})"] unless d.byteslice(0, 4) == "icns".b

  out = []
  o = 8
  while o + 8 <= d.bytesize
    type = d.byteslice(o, 4)
    len  = d.byteslice(o + 4, 4).unpack1("N")
    return [nil, "chunk #{type.inspect} declares length #{len}, which cannot hold its own header"] if len < 8
    return [nil, "chunk #{type.inspect} runs past the end of the file"] if o + len > d.bytesize
    out << [type.b, d.byteslice(o + 8, len - 8)]
    o += len
  end
  [out, nil]
end

# icns run-length coding: a byte >= 0x80 is a run of (n - 0x80 + 3) copies of the
# next byte; otherwise it is a literal run of (n + 1) bytes.
def icns_rle(data, want)
  out = +"".b
  i = 0
  while i < data.bytesize && out.bytesize < want
    n = data.getbyte(i)
    i += 1
    if n >= 0x80
      b = data.getbyte(i)
      break if b.nil?
      i += 1
      out << (b.chr * (n - 0x80 + 3))
    else
      slice = data.byteslice(i, n + 1)
      break if slice.nil?
      out << slice
      i += n + 1
    end
  end
  out
end

# Pixel reads go through sips -s format bmp and a stdlib parse, NEVER Pillow.
# ci/check-app-icon.sh:37-40 records why, and the reason is not stylistic: icons
# inside a built .ipa are CgBI PNGs (Apple crushed variant) and Pillow refuses
# them with a broken-data-stream error, which would make this check SILENTLY SKIP
# exactly the artefact that matters most. sips reads them.
def bmp_spread(bmp_path)
  d = File.binread(bmp_path)
  return [nil, "BMP is #{d.bytesize} bytes, shorter than a header"] if d.bytesize < 54
  return [nil, "no BM magic (starts #{d.byteslice(0, 2).inspect})"] unless d.byteslice(0, 2) == "BM".b

  off = d.byteslice(10, 4).unpack1("V")
  w   = d.byteslice(18, 4).unpack1("l<")
  h   = d.byteslice(22, 4).unpack1("l<").abs
  bpp = d.byteslice(28, 2).unpack1("v")
  return [nil, "#{w}x#{h} at #{bpp}bpp is not a shape this parser reads"] unless [24, 32].include?(bpp) && w > 0 && h > 0

  step   = bpp / 8
  stride = ((bpp * w + 31) / 32) * 4
  counts = Hash.new(0)
  total  = 0
  h.times do |y|
    base = off + y * stride
    w.times do |x|
      i = base + x * step
      b = d.getbyte(i)
      g = d.getbyte(i + 1)
      r = d.getbyte(i + 2)
      return [nil, "pixel data runs past the end of the BMP"] if b.nil? || g.nil? || r.nil?
      counts[[r / SPREAD_QUANTISE * SPREAD_QUANTISE,
              g / SPREAD_QUANTISE * SPREAD_QUANTISE,
              b / SPREAD_QUANTISE * SPREAD_QUANTISE]] += 1
      total += 1
    end
  end
  return [nil, "the BMP carried no pixels"] if total.zero?

  big = counts.select { |_c, n| n.to_f / total >= SPREAD_MIN_SHARE }.keys
  return [0, nil] if big.length < 2

  best = 0.0
  big.combination(2).each do |a, c|
    dist = Math.sqrt(((a[0] - c[0])**2) + ((a[1] - c[1])**2) + ((a[2] - c[2])**2))
    best = dist if dist > best
  end
  [best.to_i, nil]
end

SPREAD_TMP = []
def spread_of(abs)
  SPREAD_TMP << mktmp("icon-set-bmp") if SPREAD_TMP.empty?
  bmp = File.join(SPREAD_TMP.first, "probe-#{rand(1 << 32).to_s(16)}.bmp")
  _out, status = capture("/usr/bin/sips", "-s", "format", "bmp",
                         "--resampleHeightWidth", SPREAD_SAMPLE.to_s, SPREAD_SAMPLE.to_s,
                         abs, "--out", bmp)
  # sips exits 0 on input it could not read, so the ARTEFACT is the signal.
  return [nil, "sips wrote no BMP (exit #{status.inspect})"] unless File.file?(bmp)
  bmp_spread(bmp)
end

# The exit code is captured on the statement AFTER the call, and the output goes
# to a FILE rather than a pipe. 08-RESEARCH Pitfall 4, measured: piping the
# template gate and then reading the status yields the PIPE's status -- EXIT=0
# printed for a gate that exited 1. A cross-check read that way cannot fail.
def run_to_file(env, argv, out_path, chdir: ROOT)
  pid = Process.spawn(env, *argv, out: [out_path, "w"], err: [:child, :out], chdir: chdir)
  _pid, status = Process.wait2(pid)
  [status.exitstatus, File.read(out_path, encoding: "UTF-8")]
rescue SystemCallError => e
  [nil, "could not run #{argv.inspect}: #{e.message}"]
end

def mktmp(prefix)
  base = ENV["TMPDIR"] || "/tmp"
  dir  = File.join(base, "#{prefix}-#{Process.pid}-#{rand(1 << 32).to_s(16)}")
  Dir.mkdir(dir)
  dir
end

TMP_DIRS = []
at_exit do
  TMP_DIRS.each do |d|
    Dir.glob(File.join(d, "**", "*"), File::FNM_DOTMATCH).sort.reverse_each do |p|
      next if File.basename(p) == "." || File.basename(p) == ".."
      File.directory?(p) ? Dir.rmdir(p) : File.unlink(p)
    rescue SystemCallError
      nil
    end
    Dir.rmdir(d) rescue nil
  end
end

# ─── P0: the tools this gate depends on ──────────────────────────────────────

no_verdict("sips is not on PATH — every alpha and dimension read here goes through it, " \
           "and a run that cannot read a pixel has not inspected an icon") unless tool?("sips")
no_verdict("iconutil is not on PATH — the .icns that actually ships could not be opened, " \
           "so every assertion about the icon users see would be about nothing") unless tool?("iconutil")

puts "==> Icon set (META-01, criterion 1) — population: four named sources"
puts

# A member of the population. path is what a FAIL line names.
Member = Struct.new(:source, :path, :abs, :nominal, :kind, :chunk, :measured,
                    keyword_init: true)

population = []

# ─── SOURCE A: the iOS asset catalog, by PARSE ───────────────────────────────

ios_contents_rel = File.join(IOS_SET_REL, "Contents.json")
ios_contents_abs = File.join(ROOT, ios_contents_rel)
ios_declared = []
ios_json_ok  = File.file?(ios_contents_abs)
assert ios_json_ok, "population", ios_contents_rel,
       "source A's catalog manifest exists. The iOS marketing icon is resolved from it rather " \
       "than hardcoded, the way ci/check-app-icon.sh:135-153 does"
if ios_json_ok
  doc = read_json(ios_contents_abs)
  assert !doc.key?("__error__"), "population", ios_contents_rel,
         "source A's catalog manifest parses as JSON#{doc["__error__"] ? " (#{doc["__error__"]})" : ""}"
  images = doc.is_a?(Hash) ? doc["images"] : nil
  images = [] unless images.is_a?(Array)
  ios_declared = images.map { |i| i.is_a?(Hash) ? i["filename"] : nil }.compact
  images.each do |img|
    next unless img.is_a?(Hash) && img["filename"]
    rel = File.join(IOS_SET_REL, img["filename"])
    population << Member.new(source: "ios_appiconset", path: rel, abs: File.join(ROOT, rel),
                             nominal: nominal_side(img), kind: "png", chunk: nil)
  end
end
from_ios = population.count { |m| m.source == "ios_appiconset" }
assert from_ios >= 1, "population", IOS_SET_REL,
       "source A contributes at least 1 declared slot (got #{from_ios}). The floor refuses a " \
       "vacuous pass; it is not a frozen count"

# ─── SOURCE B: the macOS asset catalog, by PARSE ─────────────────────────────

mac_contents_rel = File.join(MACOS_SET_REL, "Contents.json")
mac_contents_abs = File.join(ROOT, mac_contents_rel)
mac_declared = []
mac_json_ok  = File.file?(mac_contents_abs)
assert mac_json_ok, "population", mac_contents_rel, "source B's catalog manifest exists"
if mac_json_ok
  doc = read_json(mac_contents_abs)
  assert !doc.key?("__error__"), "population", mac_contents_rel,
         "source B's catalog manifest parses as JSON#{doc["__error__"] ? " (#{doc["__error__"]})" : ""}"
  images = doc.is_a?(Hash) ? doc["images"] : nil
  images = [] unless images.is_a?(Array)
  mac_declared = images.map { |i| i.is_a?(Hash) ? i["filename"] : nil }.compact
  images.each do |img|
    next unless img.is_a?(Hash) && img["filename"]
    rel = File.join(MACOS_SET_REL, img["filename"])
    population << Member.new(source: "macos_appiconset", path: rel, abs: File.join(ROOT, rel),
                             nominal: nominal_side(img), kind: "png", chunk: nil)
  end
end
from_macos = population.count { |m| m.source == "macos_appiconset" }
assert from_macos >= 10, "population", MACOS_SET_REL,
       "source B contributes at least 10 declared slots (got #{from_macos}). macOS declares ten " \
       "sizes and a catalog that has quietly lost one is a slot nothing would ever look at"

# ─── SOURCE C1: the .icns that actually ships ────────────────────────────────

icns_rel_for_msg = icns_arg ? ICNS_PATH : ICNS_REL
unless File.file?(ICNS_PATH)
  no_verdict("#{ICNS_PATH} is not a readable file. app/project.yml:152-169 copies this .icns over " \
             "actool's output before Code Sign, so it IS the icon that ships — a run that cannot " \
             "open it must not report on a smaller population as though it had")
end

chunks, chunk_err = icns_chunks(ICNS_PATH)
no_verdict("#{icns_rel_for_msg} could not be walked as an icns container: #{chunk_err}") if chunks.nil?

png_chunks   = chunks.select { |_t, p| p.start_with?(PNG_MAGIC) }
argb_chunks  = chunks.select { |_t, p| p.byteslice(0, 4) == ARGB_MAGIC }
other_chunks = chunks.reject { |c| png_chunks.include?(c) || argb_chunks.include?(c) }

icns_dir = mktmp("icon-set-icns")
TMP_DIRS << icns_dir
iconset_out = File.join(icns_dir, "AppIcon.iconset")
_out, iconutil_status = capture("/usr/bin/iconutil", "-c", "iconset", ICNS_PATH, "-o", iconset_out)
icns_route = "none"
icns_members = []
if iconutil_status == 0 && File.directory?(iconset_out)
  icns_route = "iconset"
  # Directory listing is legitimate HERE: iconutil just created this directory and
  # its contents ARE the extraction result. The catalog populations above are
  # parsed, never listed.
  icns_members = Dir.children(iconset_out).select { |f| f.end_with?(".png") }.sort
end

if icns_members.empty?
  no_verdict("#{icns_rel_for_msg} yielded no members (iconutil -c iconset exit " \
             "#{iconutil_status.inspect}), so every assertion about the icon that actually ships " \
             "would be about nothing. A zero-member extraction is not a smaller population, it is " \
             "no population at all")
end

icns_members.each do |name|
  abs = File.join(iconset_out, name)
  population << Member.new(source: "icns", path: "#{icns_rel_for_msg}!#{name}", abs: abs,
                           nominal: nominal_side_from_name(name), kind: "icns_member", chunk: nil)
end
from_icns = population.count { |m| m.source == "icns" }
assert from_icns >= 1, "population", icns_rel_for_msg,
       "source C1 contributes at least 1 extracted member (got #{from_icns}) via " \
       "iconutil -c iconset. iconutil -l is NOT a route on this Xcode: it prints " \
       "'invalid option -- l' at exit 1 (measured #{MEASURED_ON}), which is why " \
       "icon_icns_route= is printed rather than assumed"

# The container walk and the extraction are two independent readings of the same
# artefact. If they disagree, one of them is not seeing the whole file.
assert (png_chunks.length + argb_chunks.length) == icns_members.length,
       "population", icns_rel_for_msg,
       "the container walk and iconutil agree on how many image entries this .icns holds " \
       "(#{png_chunks.length} PNG + #{argb_chunks.length} ARGB = " \
       "#{png_chunks.length + argb_chunks.length} vs #{icns_members.length} extracted). " \
       "A disagreement means one reading is blind to part of the icon that ships"

other_chunks.each do |type, payload|
  # info is a binary plist iconutil writes; it is not an icon entry. Anything
  # else that is neither PNG nor ARGB is an image this gate cannot read, and that
  # is evidence for neither side.
  next if type == "info".b
  assert false, "alpha", "#{icns_rel_for_msg}##{type}",
         "icns entry #{type.inspect} (#{payload.bytesize} bytes) is stored in neither a PNG nor a " \
         "raw ARGB container, so its transparency could not be read at all. That is evidence for " \
         "neither side and is reported as its own failure rather than folded into a pass"
end

# ─── SOURCE C2: the 1024 source the ten slots are generated FROM ─────────────

icns_src_abs = File.join(ROOT, ICNS_SRC_REL)
src_present  = File.file?(icns_src_abs)
assert src_present, "population", ICNS_SRC_REL,
       "source C2 exists — ci/gen-macos-icons.swift derives all ten macOS slots and the .icns " \
       "from this one file, so a defect here is a defect in every slot at once"
if src_present
  population << Member.new(source: "macos_resources", path: ICNS_SRC_REL, abs: icns_src_abs,
                           nominal: 1024, kind: "png", chunk: nil)
end
from_resources = population.count { |m| m.source == "macos_resources" }

# ─── SOURCE D: the built .app, only when supplied ────────────────────────────

built_route  = "not-supplied"
built_reason = "source D was NOT supplied. Pass --built-app <path>.app to inspect the icon inside " \
               "a built bundle; this run inspected the four repository sources only, and says so " \
               "rather than omitting the source silently"
built_icns   = nil

if built_app
  bundle = File.expand_path(built_app)
  assert File.directory?(bundle), "built-app", built_app,
         "the --built-app path is a bundle directory. A build step that produced nothing leaves a " \
         "path exactly like this behind, and a gate that shrugs at it exits 0 having never looked"
  if File.directory?(bundle)
    plist = [File.join(bundle, "Contents", "Info.plist"), File.join(bundle, "Info.plist")]
            .find { |p| File.file?(p) }
    assert !plist.nil?, "built-app", built_app,
           "the bundle carries an Info.plist at either bundle shape's location"
    icon_key = nil
    if plist
      out, status = capture("/usr/libexec/PlistBuddy", "-c", "Print :CFBundleIconFile", plist)
      if status == 0 && !out.strip.empty?
        icon_key = out.strip
        built_route = "plistbuddy"
      else
        out2, status2 = capture("/usr/bin/plutil", "-extract", "CFBundleIconFile", "raw", "-o", "-", plist)
        if status2 == 0 && !out2.strip.empty?
          icon_key = out2.strip
          built_route = "plutil"
        else
          built_route = "none"
        end
      end
    end
    assert !icon_key.nil?, "built-app", built_app,
           "the built bundle's own Info.plist names an icon file (CFBundleIconFile). " \
           "app/project.yml sets ASSETCATALOG_COMPILER_APPICON_NAME to empty precisely so macOS " \
           "reads this key and not the catalog, so an absent key means the shipped bundle has no " \
           "icon route at all (PlistBuddy/plutil route: #{built_route})"
    if icon_key
      name = icon_key.end_with?(".icns") ? icon_key : "#{icon_key}.icns"
      cand = [File.join(bundle, "Contents", "Resources", name), File.join(bundle, name)]
             .find { |p| File.file?(p) }
      assert !cand.nil?, "built-app", built_app,
             "the icon file the bundle's Info.plist names (#{name}) is present inside the bundle. " \
             "The name resolving to nothing is the defect this source exists to catch"
      if cand
        built_icns = cand
        bdir = mktmp("icon-set-built")
        TMP_DIRS << bdir
        bout = File.join(bdir, "Built.iconset")
        _o, bstatus = capture("/usr/bin/iconutil", "-c", "iconset", cand, "-o", bout)
        bmembers = (bstatus == 0 && File.directory?(bout)) ? Dir.children(bout).select { |f| f.end_with?(".png") }.sort : []
        assert !bmembers.empty?, "built-app", cand,
               "the .icns inside the built bundle yielded members (iconutil exit #{bstatus.inspect}). " \
               "Zero members is not a smaller population, it is no population at all"
        bmembers.each do |m|
          population << Member.new(source: "built_app", path: "#{cand}!#{m}",
                                   abs: File.join(bout, m), nominal: nominal_side_from_name(m),
                                   kind: "icns_member", chunk: nil)
        end
        built_reason = "source D inspected #{cand} (#{bmembers.length} members), resolved from " \
                       "CFBundleIconFile=#{icon_key.inspect} via #{built_route}"
      end
    end
  end
end
from_built = population.count { |m| m.source == "built_app" }

# ─── declared-vs-present, both directions, separate messages ─────────────────

[[IOS_SET_REL, ios_declared, ios_json_ok], [MACOS_SET_REL, mac_declared, mac_json_ok]].each do |set_rel, declared, ok|
  next unless ok
  assert !declared.empty?, "declared", set_rel,
         "the catalog declares at least one filename. An each over an empty collection asserts " \
         "nothing and prints success"
  declared.each do |fn|
    assert File.file?(File.join(ROOT, set_rel, fn)), "declared", File.join(set_rel, fn),
           "a slot DECLARED in Contents.json is present on disk. actool resolves the catalog by " \
           "declaration, so a declared-and-missing slot is a build-time hole, not a cosmetic one"
  end
  # Files on disk that nobody declared. Dir.children here enumerates the DISK
  # side of a comparison whose other side is the parse; it is not how the
  # population was built.
  on_disk = Dir.children(File.join(ROOT, set_rel)).select { |f| f.downcase.end_with?(".png") }.sort
  on_disk.each do |fn|
    assert declared.include?(fn), "undeclared", File.join(set_rel, fn),
           "a PNG present in the .appiconset is DECLARED in Contents.json. An undeclared slot is " \
           "shipped to nobody and is a different defect from a declared slot that is missing: it " \
           "looks like coverage in a directory listing and is invisible to actool"
  end
end

# ─── ALPHA, member by member, over the WHOLE population ──────────────────────

assert !population.empty?, "alpha", "(population)",
       "the population is non-empty before anything iterates it"

alpha_via_hasalpha  = 0
alpha_via_argb      = 0
argb_sides_by_side  = {}
argb_chunks.each do |type, payload|
  side = ICNS_ARGB_SIDES[type]
  if side.nil?
    assert false, "alpha", "#{icns_rel_for_msg}##{type}",
           "icns raw entry #{type.inspect} is an ARGB container type this gate has no decoded pixel " \
           "side for, so its transparency could not be read. Third state, failed as one"
    next
  end
  want    = side * side * 4
  decoded = icns_rle(payload.byteslice(4, payload.bytesize - 4), want)
  if decoded.bytesize != want
    assert false, "alpha", "#{icns_rel_for_msg}##{type}",
           "icns raw entry #{type.inspect} decodes to #{decoded.bytesize} bytes, not the " \
           "#{want} an #{side}x#{side} ARGB image must hold. The assumed pixel side is VERIFIED " \
           "here rather than trusted, and it did not hold"
    next
  end
  argb_sides_by_side[side] = [type, decoded.byteslice(0, side * side)]
end

population.each do |m|
  props, status = sips_props(m.abs, "pixelWidth", "pixelHeight", "hasAlpha", "format")
  w     = props["pixelWidth"]
  h     = props["pixelHeight"]
  alpha = props["hasAlpha"]

  # sips exits 0 on a file it could not read (MEASURED 2026-09-10), so the missing
  # PROPERTY is the failure signal and the exit code rides along in the message.
  if w.nil? || h.nil? || alpha.nil?
    assert false, "alpha", m.path,
           "sips returned the pixel properties for this member. It did not " \
           "(exit #{status.inspect}, got #{props.keys.sort.inspect}) — and sips exits 0 on a file " \
           "that does not exist, so this is a third state and is failed as one rather than read " \
           "as an absence of alpha"
    next
  end

  m.measured = w.to_i

  if m.nominal
    assert w == m.nominal.to_s && h == m.nominal.to_s, "dimension", m.path,
           "the member measures #{m.nominal}x#{m.nominal} as its declaration implies; it is #{w}x#{h}"
  end

  if alpha == "yes" && m.source == "icns" && argb_sides_by_side.key?(w.to_i)
    # The container mandates the channel for this entry. Read it HARDER: every
    # alpha byte must be 0xFF. Real transparency still fails.
    type, achan = argb_sides_by_side[w.to_i]
    worst = achan.bytes.min
    alpha_via_argb += 1
    assert worst == 255, "alpha", m.path,
           "the #{w}x#{w} entry the icns container stores as raw #{type} is FULLY OPAQUE " \
           "(lowest alpha byte #{worst} of 255). #{APPLE_ALPHA}. iconutil writes this entry as ARGB " \
           "whatever the artwork is (measured #{MEASURED_ON}: an all-opaque iconset round-trips " \
           "with hasAlpha yes on exactly the 16pt and 32pt @1x members), so the channel's PRESENCE " \
           "proves nothing and its CONTENTS are what is asserted"
  else
    alpha_via_hasalpha += 1
    assert alpha == "no", "alpha", m.path,
           "no alpha channel (sips hasAlpha=#{alpha.inspect}). #{APPLE_ALPHA} — App Store Connect " \
           "rejects a marketing icon for it outright, and on macOS a transparent slot renders as a " \
           "ghost in the Dock"
  end
end

# ─── SPREAD: the Guideline 2.3.8 proxy, over every member big enough ─────────

spread_checked = 0
spread_values  = {}
population.each do |m|
  side = m.measured.to_i
  next if side < SPREAD_MIN_PIXELS

  value, why = spread_of(m.abs)
  spread_checked += 1
  if value.nil?
    # Could not read the pixels. Evidence for NEITHER side, failed as its own
    # thing rather than folded into either -- an unreadable icon is not an icon
    # that passed.
    assert false, "spread", m.path,
           "the pixels could be read at all: #{why}. A member whose pixels never arrived has not " \
           "been shown to be artwork and has not been shown to be a placeholder"
    next
  end

  spread_values[m.path] = value
  assert value >= SPREAD_FLOOR, "spread", m.path,
         "spread #{value}, need >= #{SPREAD_FLOOR} -- this measures as a flat colour or a bare " \
         "gradient, which is Guideline 2.3.8 (Accurate Metadata). Upstream learned this one from " \
         "Apple rather than from a check: a placeholder icon came back as a rejection and cost a " \
         "full review cycle (C-29, ci/check-app-icon.sh:4-13). Nothing objects on the way out -- " \
         "the asset is a valid PNG, CI is green and App Store Connect accepts the upload"
end

assert spread_checked.positive?, "spread", "(population)",
       "at least one member was large enough (>= #{SPREAD_MIN_PIXELS}px) to measure for detail. " \
       "A spread clause that measured nothing reports compliance it never looked for"

# ─── THE TEMPLATE GATE, as a separate source of truth ────────────────────────
#
# This gate's population is strictly WIDER than ci/check-app-icon.sh's two files.
# Wider must not mean "instead of": the template gate keeps its own verdict here,
# visible and separately asserted, so a fork-side mistake cannot quietly replace
# upstream's answer with its own.

template_gate_abs  = File.join(ROOT, TEMPLATE_GATE_REL)
template_gate_exit = "absent"
template_gate_env  = "not-run"
if !File.file?(template_gate_abs)
  assert false, "template-gate", TEMPLATE_GATE_REL,
         "the template gate exists and can be cross-checked. It does not, so upstream's own verdict " \
         "on the two files it owns was not obtained and this run is narrower than it claims"
else
  gate_dir = mktmp("icon-set-tmplgate")
  TMP_DIRS << gate_dir
  gate_out_path = File.join(gate_dir, "check-app-icon.out")
  # The override is REMOVED from the child environment. An escape hatch that can
  # talk the template gate into exit 0 would launder this cross-check into
  # agreement with nothing, so the verdict obtained here is always the honest one
  # and the route is printed as icon_template_gate_env=.
  template_gate_env = "sanitised"
  # ci/check-app-icon.sh, invoked as an ARGV ARRAY with its output redirected to a
  # FILE and its status read on the statement after the call. Never piped.
  template_gate_exit, gate_output = run_to_file({ OVERRIDE_VAR => nil },
                                                ["/bin/bash", template_gate_abs],
                                                gate_out_path)
  quoted = gate_output.to_s.lines.map(&:chomp).reject(&:empty?).join(" | ")

  case template_gate_exit
  when 0
    assert true, "template-gate", TEMPLATE_GATE_REL,
           "the template gate passes on the two files it owns (exit 0), read from a file with the " \
           "status captured before anything touched the output"
  when 1
    assert false, "template-gate", TEMPLATE_GATE_REL,
           "the template gate passes on the two files it owns. It exited 1, and its own words are: " \
           "#{quoted}"
  else
    assert false, "template-gate", TEMPLATE_GATE_REL,
           "the template gate returned #{template_gate_exit.inspect}, which is neither its pass (0) " \
           "nor its documented failure (1). That is evidence for NEITHER side and is reported as " \
           "its own failure rather than folded into the pass -- output: #{quoted}"
  end
end

# ─── THE OVERRIDE THAT CANNOT HIDE ───────────────────────────────────────────
#
# ci/check-app-icon.sh:86-93 honours an escape hatch that downgrades the 2.3.8
# failure to a warning. That is a reasonable option for a design that really is
# one flat colour. It is NOT a state in which this gate may report icon
# compliance: a green that depends on a variable suppressing the check it rests
# on is a green about the environment, not about the icon. So the variable is
# read, printed either way, and its presence is a failure in itself.

override_raw = ENV[OVERRIDE_VAR]
override_set = !override_raw.nil? && !override_raw.to_s.strip.empty?
assert !override_set, "override", "(environment)",
       "no placeholder escape hatch is suppressing the 2.3.8 proxy this verdict rests on. " \
       "It is set to #{override_raw.inspect}. Any non-empty value fails here, not just the one " \
       "value the template gate acts on -- setting it at all states an intent to suppress, and a " \
       "compliance verdict rendered in that environment would mean nothing. Unset it and re-run, " \
       "or accept that this gate has no opinion while it is set"

# ─── what is deliberately OUTSIDE the population, as a number ────────────────
#
# Icon-shaped artefacts on the tree that this gate does not check. Printed so the
# number MOVES when somebody adds one, which is the whole lesson of UL-052's
# unenumerated_bin=9. The two members today are the README screenshots under
# docs/ — they are documentation images, never shipped as an icon, and Guideline
# 2.3.8 does not reach them.
tracked_out, tracked_status = capture("git", "-C", ROOT, "ls-files")
if tracked_status == 0 && !tracked_out.strip.empty?
  unenum_route = "git"
  candidates = tracked_out.lines.map(&:chomp)
else
  unenum_route = "walk"
  # Not the population — the population is parsed. This glob is the OTHER side of
  # the exclusion arithmetic.
  candidates = Dir.glob(File.join(ROOT, "**", "*"), File::FNM_CASEFOLD)
                  .map { |p| p.sub(/\A#{Regexp.escape(ROOT)}\/?/, "") }
end
images = candidates.select { |p| p.downcase.end_with?(".png", ".icns") }
enumerated_files = population.map { |m| m.path.split("!").first }.uniq
enumerated_files << (icns_arg ? ICNS_PATH : ICNS_REL)
unenumerated = images.reject { |p| enumerated_files.include?(p) }.sort

# A second .appiconset nobody told this gate about is a population hole, not a
# stylistic matter: it would be compiled by actool and never inspected here.
appiconsets = candidates.map { |p| p[/\A.*\.appiconset(?=\/)/] }.compact.uniq.sort
known_sets  = [IOS_SET_REL, MACOS_SET_REL]
assert (appiconsets - known_sets).empty?, "population", "(tree)",
       "every .appiconset on the tree is one of the two this gate enumerates. Found " \
       "#{appiconsets.inspect}; a set outside #{known_sets.inspect} is compiled by actool and " \
       "inspected by nothing"

# ─── named facts, printed on success as well as on failure ───────────────────

puts
puts "icon_root=#{ROOT}"
puts "icon_slots_from_ios_appiconset=#{from_ios}"
puts "icon_slots_from_macos_appiconset=#{from_macos}"
puts "icon_members_from_icns=#{from_icns}"
puts "icon_slots_from_macos_resources=#{from_resources}"
puts "icon_slots_from_built_app=#{from_built}"
puts "icon_total=#{population.length}"
puts "icon_unenumerated=#{unenumerated.length}"
puts "icon_unenumerated_route=#{unenum_route}"
puts "icon_unenumerated_paths=#{unenumerated.join(',')}"
puts "icon_appiconsets_found=#{appiconsets.length}"
puts "icon_icns_route=#{icns_route}"
puts "icon_icns_source=#{icns_rel_for_msg}"
puts "icon_icns_chunks_png=#{png_chunks.length}"
puts "icon_icns_chunks_argb=#{argb_chunks.length}"
puts "icon_icns_chunks_other=#{other_chunks.length}"
puts "icon_alpha_checked=#{alpha_via_hasalpha + alpha_via_argb}"
puts "icon_alpha_via_hasalpha=#{alpha_via_hasalpha}"
puts "icon_alpha_via_argb_decode=#{alpha_via_argb}"
puts "icon_spread_checked=#{spread_checked}"
puts "icon_spread_floor=#{SPREAD_FLOOR}"
puts "icon_spread_min_pixels=#{SPREAD_MIN_PIXELS}"
puts "icon_spread_worst=#{spread_values.empty? ? 'none' : spread_values.values.min}"
spread_values.keys.sort.each { |k| puts "icon_spread #{k}=#{spread_values[k]}" }
puts "icon_template_gate_exit=#{template_gate_exit}"
puts "icon_template_gate_env=#{template_gate_env}"
puts "icon_placeholder_override=#{override_set ? 'set' : 'unset'}"
puts "icon_override_token=assembled"
puts "icon_built_app_route=#{built_route}"
puts "icon_built_app_reason=#{built_reason}"
puts "icon_measured_on=#{MEASURED_ON}"

verdict!
