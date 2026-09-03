#!/usr/bin/env ruby
# frozen_string_literal: true

# tools/gitleaks.rb — the secret scan (D-62, IDENT-12). Downloads a
# version-pinned gitleaks release tarball, verifies its sha256 against the
# digest published in that release's own checksums file BEFORE executing it,
# refuses to run on a checkout that cannot answer the question, and scans the
# full git history reachable from HEAD.
#
# ─── WHY A PINNED BINARY AND NOT THE OFFICIAL GITHUB ACTION ──────────────────
# IDENT-12 asks for a pinned binary invocation rather than the Action published
# by the same project, and the reason is licensing, not taste: that Action
# requires a commercial licence for organisation-owned repositories, and this
# repository is organisation-owned. The gitleaks BINARY is MIT (the tarball
# ships its LICENSE; verified 2026-09-02). So the scan is the binary, fetched
# per run. The Action's literal name is deliberately not spelled here or in
# .github/workflows/review-notes.yml, so that a grep for it cannot be satisfied
# by a comment explaining its absence — the precaution that file already takes
# with the writable-token variant of the pull_request trigger.
#
# ─── WHY THE HISTORY AND NOT THE WORKING TREE ────────────────────────────────
# Measured, not assumed (04-RESEARCH §Q3): a high-entropy token committed in one
# commit and `git rm`'d in the next is reported by `gitleaks git` (exit 42) and
# MISSED ENTIRELY by `gitleaks dir` (exit 0). Deleting a leaked credential in a
# follow-up commit does not unpublish it; a working-tree scan says it does.
# There is a second reason `dir` is wrong here: it would scan the gitignored
# `.bootstrap.env`, which on a developer's machine holds a real issuer id.
#
# ─── WHY THIS SCRIPT ASSERTS THE CHECKOUT DEPTH ITSELF ───────────────────────
# `fetch-depth: 0` in the workflow is necessary and is NOT the gate. On a
# `--depth 1` clone of this repository, with a committed-then-deleted token in
# history, gitleaks reported `1 commits scanned … no leaks found` and exited 0
# (observed; re-observed in this plan's evidence). A shallow checkout does not
# make the scan fail, it makes it VACUOUS — and `fetch-depth: 0` is one config
# line that anybody can delete without a single check going red. The same class
# of silent pass exists for a target that is not a git repository at all
# (`scanned ~0 bytes … no leaks found`, exit 0). Both are refused here, in code,
# before the scanner is invoked, and a run that somehow produces no
# `commits scanned` line is refused after it.
#
# ─── EXIT-CODE CONTRACT ──────────────────────────────────────────────────────
#
#   Exit | Meaning
#   -----+---------------------------------------------------------------------
#   0    | scan completed and found nothing; the commits-scanned count is printed
#   42   | findings (redacted). `--exit-code 42` is what separates this from the
#        | case below: gitleaks' default exit for findings is 1, which is ALSO
#        | its exit for "unable to load config" and every other internal error,
#        | so with the default a broken config and a leaked key are the same
#        | number. Both must fail; they must not fail identically.
#   1    | the scanner ran and exited for a reason that is not findings — a
#        | malformed .gitleaks.toml, an unreadable object, a signal
#   2    | CANNOT RUN: no verdict was reached. Unsupported platform, not a git
#        | repository, shallow checkout, missing .gitleaks.toml, missing curl or
#        | tar or git, download failure, sha256 mismatch, version mismatch, or a
#        | scan that printed no commits-scanned line. This is the
#        | tools/asc-probe.rb:159-171 / ci/check-embedded-floors.sh idiom: a
#        | query that matched nothing and an assertion that therefore never ran
#        | is the classic vacuous-truth gate, and a distinct "I don't know" code
#        | makes "nothing was there" impossible to read as "everything checked out".
#
# Exit 2 is fail-closed by design. If GitHub Releases is unavailable, every
# pull request is blocked until it returns; that is the intended trade, and a
# re-run is the remedy.
#
# ─── WHAT THIS SCAN CANNOT SEE — read this before trusting a green run ───────
#   * `--log-opts=HEAD` scans the ancestry of the checked-out commit. Commits on
#     OTHER refs are out of scope: notably commit 33f8e08, which carries a real
#     given name in a fixture, is off `main` (squash-merged) and reachable only
#     by SHA. This scan does not cover it and no wording here should be read as
#     saying it does. It remains a separate, non-blocking human action.
#   * Stale remote branches, dangling objects and anything only in a reflog are
#     likewise unreachable from HEAD.
#   * A secret that was never committed — in a GitHub secret, a runner
#     environment variable, an artifact — is not in git and is not scanned.
#   * gitleaks is a regex-and-entropy engine. It does not detect a low-entropy
#     fake (measured: `ghp_` + 36 identical characters, and AWS's own
#     documented example key, are both reported as nothing), and it will not
#     detect a novel credential format the rule set has never seen.
#   * `.gitleaks.toml` can suppress findings. That file has its own gate,
#     test/gitleaks_config_test.rb, which runs in the same CI job.
#
# ─── RUN IT ──────────────────────────────────────────────────────────────────
#   ruby tools/gitleaks.rb                  # scan this repository
#   ruby tools/gitleaks.rb --root DIR       # scan another checkout (red controls)
#   GITLEAKS_CACHE_DIR=~/.cache/gitleaks ruby tools/gitleaks.rb
#
# The cache keeps the downloaded TARBALL between local runs; it never skips the
# digest check, which is recomputed on every run over whatever bytes are about
# to be unpacked. CI sets no cache and gets a fresh temporary directory.
#
# Ruby stdlib only (digest, open3, tmpdir, fileutils) — no gems, which is what
# keeps the `review notes` job's `bundler-cache: false` honest;
# test/gitleaks_config_test.rb asserts the require list so it cannot rot. Every
# shell-out is an explicit argv array, never a shell string.

require "digest"
require "open3"
require "tmpdir"
require "fileutils"

# ─── frozen constants ────────────────────────────────────────────────────────
# The pin. It is stated in two places on purpose: here, which is what executes,
# and in the workflow step's `name:`, which is what a reader sees in the Actions
# log. test/gitleaks_config_test.rb compares them, because two statements of one
# fact that nothing compares are a defect waiting to happen.
VERSION = "8.30.1"

# sha256 of each release tarball, copied from the release's OWN checksums file
# (gitleaks_8.30.1_checksums.txt, 999 bytes, fetched 2026-09-02; release
# published 2026-03-21T02:17:58Z). Not computed from a downloaded file — that
# would verify the download against itself.
DIGESTS = {
  "linux_x64"    => "551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb",
  "darwin_arm64" => "b40ab0ae55c505963e365f271a8d3846efbc170aa17f2607f13df610a9aeb6a5"
}.freeze

BASE_URL        = "https://github.com/gitleaks/gitleaks/releases/download"
CONFIG_BASENAME = ".gitleaks.toml"
EXIT_FINDINGS   = 42
ROOT_DEFAULT    = File.expand_path("..", __dir__)
USAGE           = "Usage: ruby tools/gitleaks.rb [--root DIR]"

# Unbuffered, so this script's own lines and the scanner's interleave in the
# order they happened. A CI log in which the refusal prints before the line
# explaining what was being attempted is a log that reads backwards.
$stdout.sync = true
$stderr.sync = true

def no_verdict(message)
  warn "CANNOT RUN: #{message}"
  exit 2
end

# Pin UTF-8 explicitly rather than inheriting the locale (the fork's idiom since
# commit 3b1efb9): with LANG unset Ruby's default external encoding is US-ASCII
# and a regex over output containing a non-ASCII byte raises instead of matching.
def utf8(text)
  text = text.dup.force_encoding(Encoding::UTF_8)
  text.valid_encoding? ? text : text.scrub("?")
end

# The command is passed as [cmd, argv0] rather than splatted: Process.spawn with
# a single string argument is the STRING form, which Ruby hands to /bin/sh
# whenever the string carries a metacharacter (tools/identity-parity.rb:210-218,
# demonstrated there). The two-element array form is never shell-interpreted,
# whatever argv holds.
def capture(argv, chdir: nil)
  opts = { in: File::NULL }
  opts[:chdir] = chdir if chdir
  out, err, status = Open3.capture3([argv[0], argv[0]], *argv[1..], **opts)
  [utf8(out), utf8(err), status.exitstatus || (128 + status.termsig.to_i)]
rescue Errno::ENOENT
  [nil, nil, nil]
end

# PATH lookup in Ruby, so a missing binary is reported by name before any
# subprocess is attempted.
def which(name)
  ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |dir|
    candidate = File.join(dir, name)
    return candidate if File.executable?(candidate) && !File.directory?(candidate)
  end
  nil
end

# ─── arguments ───────────────────────────────────────────────────────────────
root = nil
argv = ARGV.dup
until argv.empty?
  arg = argv.shift
  case arg
  when "--root" then root = argv.shift or no_verdict("--root needs a directory")
  when "-h", "--help"
    puts USAGE
    exit 0
  else no_verdict("unknown argument #{arg.inspect}. #{USAGE}")
  end
end
root = File.expand_path(root || ROOT_DEFAULT)

# ─── preconditions: every one of them a silent-pass this scan would otherwise
# ─── report as green ─────────────────────────────────────────────────────────
%w[git curl tar].each { |tool| no_verdict("#{tool} is not on PATH") unless which(tool) }

no_verdict("not a directory: #{root}") unless File.directory?(root)

_out, _err, status = capture(%W[git -C #{root} rev-parse --git-dir])
no_verdict("not a git repository: #{root} — a directory that is not a repository " \
           "scans ~0 bytes and reports no leaks found, exit 0") unless status&.zero?

shallow, _err, status = capture(%W[git -C #{root} rev-parse --is-shallow-repository])
no_verdict("git rev-parse --is-shallow-repository failed in #{root}") unless status&.zero?
if shallow.to_s.strip != "false"
  no_verdict("shallow checkout: #{root} (is-shallow-repository = #{shallow.to_s.strip}). " \
             "A depth-1 checkout scans 1 commit and reports no leaks found, exit 0, with a " \
             "committed-then-deleted credential sitting in history. Check out with " \
             "fetch-depth: 0.")
end

config = File.join(root, CONFIG_BASENAME)
no_verdict("#{CONFIG_BASENAME} not found at #{config}. Without it the built-in rules " \
           "report this repository's documented placeholders as findings.") unless File.file?(config)

# ─── platform → the asset whose digest is pinned ─────────────────────────────
kernel, _err, kstatus  = capture(%w[uname -s])
machine, _err, mstatus = capture(%w[uname -m])
no_verdict("uname failed") unless kstatus&.zero? && mstatus&.zero?
kernel  = kernel.to_s.strip
machine = machine.to_s.strip
platform =
  if kernel == "Linux" && machine == "x86_64" then "linux_x64"
  elsif kernel == "Darwin" && machine == "arm64" then "darwin_arm64"
  end
unless platform && DIGESTS.key?(platform)
  no_verdict("unsupported platform #{kernel}/#{machine}. A digest is pinned for " \
             "#{DIGESTS.keys.join(' and ')} only; scanning with an unverified binary " \
             "would defeat the point of pinning one.")
end

asset = "gitleaks_#{VERSION}_#{platform}.tar.gz"
url   = "#{BASE_URL}/v#{VERSION}/#{asset}"

# ─── fetch, verify, unpack ───────────────────────────────────────────────────
# The cache holds the TARBALL, never a trusted verdict about it: the digest is
# recomputed below over whatever bytes are about to be unpacked, on every run.
cache_dir = ENV["GITLEAKS_CACHE_DIR"].to_s.strip
cache_dir = nil if cache_dir.empty?
FileUtils.mkdir_p(cache_dir) if cache_dir

Dir.mktmpdir("gitleaks-#{VERSION}-") do |work|
  tarball = cache_dir ? File.join(cache_dir, asset) : File.join(work, asset)

  if File.file?(tarball) && cache_dir
    puts "gitleaks #{VERSION} #{platform}: using cached tarball #{tarball} (digest re-verified below)"
  else
    puts "gitleaks #{VERSION} #{platform}: downloading #{url}"
    _out, err, status = capture(%W[curl -sSfL --retry 2 --max-time 120 -o #{tarball} #{url}])
    no_verdict("download failed (curl exit #{status.inspect}): #{err.to_s.strip}") unless status&.zero?
  end

  expected = DIGESTS.fetch(platform)
  actual   = Digest::SHA256.file(tarball).hexdigest
  if actual != expected
    warn "  expected sha256: #{expected}"
    warn "  actual   sha256: #{actual}"
    warn "  tarball: #{tarball}"
    no_verdict("sha256 mismatch for #{asset}. The bytes about to be executed are not the " \
               "bytes the release published. Do NOT run them. If a cache is in use, delete " \
               "the file above and re-run; otherwise treat this as a supply-chain event.")
  end
  puts "  sha256 OK: #{actual} (#{asset}, from gitleaks_#{VERSION}_checksums.txt)"

  _out, err, status = capture(%W[tar -xzf #{tarball} -C #{work} gitleaks])
  no_verdict("could not unpack #{asset}: #{err.to_s.strip}") unless status&.zero?

  binary = File.join(work, "gitleaks")
  no_verdict("#{asset} contained no gitleaks binary") unless File.file?(binary)
  File.chmod(0o755, binary)

  reported, _err, status = capture([binary, "version"])
  no_verdict("`gitleaks version` failed (exit #{status.inspect})") unless status&.zero?
  reported = reported.to_s.strip
  unless reported == VERSION
    no_verdict("version mismatch: the verified tarball reports #{reported.inspect}, " \
               "this script pins #{VERSION.inspect}")
  end
  puts "  gitleaks version: #{reported}"

  # ─── the scan ──────────────────────────────────────────────────────────────
  # --log-opts=HEAD: the ancestry of the checked-out commit, which under
  # actions/checkout with fetch-depth: 0 on a pull_request event is the PR merge
  # ref — base branch plus the PR's commits. The default (every fetched ref) is
  # broader and slower and, in a clone that has an unrelated `upstream` remote,
  # scans a different project's history.
  #
  # -v with --redact: without --verbose, a finding prints as the single line
  # `leaks found: 1` — a red gate that tells the person who has to fix it
  # nothing about what or where. With it, each finding prints its rule, file,
  # line, commit and fingerprint, with the secret itself replaced by REDACTED
  # (observed, both forms). An actionable failure and a disclosed one are not
  # the same thing, and this is the pair of flags that separates them.
  scan = [binary, "git", root,
          "--no-banner", "--redact", "-v",
          "--exit-code", EXIT_FINDINGS.to_s,
          "--log-opts=HEAD",
          "--config", config]
  puts "  scanning: #{scan.join(' ')}"
  puts

  # Stream the scanner's own output rather than swallowing it and paraphrasing:
  # the redacted report is the evidence a reviewer reads. stdout and stderr share
  # one pipe so their interleaving survives.
  transcript = +""
  reader, writer = IO.pipe
  pid = Process.spawn([scan[0], scan[0]], *scan[1..],
                      in: File::NULL, out: writer, err: writer)
  writer.close
  reader.each_line do |line|
    line = utf8(line)
    transcript << line
    print line
    $stdout.flush
  end
  reader.close
  Process.wait(pid)
  code = $?.exitstatus || (128 + $?.termsig.to_i)
  puts

  # A run that printed no commits-scanned line did not scan anything, whatever
  # it exited: the same vacuous shape the shallow and not-a-repository guards
  # above refuse in advance, caught here from the other side.
  commits = transcript[/(\d+) commits scanned/, 1]
  if commits.nil?
    no_verdict("the scanner printed no `commits scanned` line (exit #{code}); " \
               "there is no evidence any history was read")
  end

  case code
  when 0
    puts "SECRET SCAN CLEAN: #{commits} commits scanned, no findings " \
         "(gitleaks #{VERSION}, #{CONFIG_BASENAME})."
    exit 0
  when EXIT_FINDINGS
    found = transcript[/leaks found:\s*(\d+)/, 1] || "?"
    warn "SECRET SCAN FAILED: #{found} leak(s) — see the redacted report above. " \
         "#{commits} commits scanned. Rotate the credential FIRST; removing the commit " \
         "does not unpublish it. If the finding is documentation rather than a secret, " \
         "add a dated, scoped entry to #{CONFIG_BASENAME} (its rules are enforced by " \
         "test/gitleaks_config_test.rb)."
    exit EXIT_FINDINGS
  else
    warn "SECRET SCAN ERROR: gitleaks exited #{code}, which is neither clean (0) nor " \
         "findings (#{EXIT_FINDINGS}) — a malformed #{CONFIG_BASENAME} or an internal " \
         "failure. #{commits} commits scanned. Output above."
    exit 1
  end
end
