#!/usr/bin/env ruby
# frozen_string_literal: true

# Idempotent driver for forking the template. Reads `.bootstrap.env` for
# credentials and `app/Identity.xcconfig` for the app's identity, then runs
# every programmatic step (identity verification, store-metadata generation,
# push, branch protection, GH secrets, signing identities, optional icon swap).
# Halts on first blocker (typically: ASC App record not yet created — Apple
# disallows POST). It VERIFIES identity and never writes it: there is no rename
# step and no certs repo, and `fastlane match` is not used.
#
# Each step is no-op if its desired state is already reached, so re-running
# after a partial failure picks up where you left off.
#
# Exit-code contract, in bin/preflight-identity.rb's shape. It is documented
# because this driver's steps write to GitHub and to Apple, and a caller has to
# be able to tell "I do not understand you" apart from "a step is blocked":
#
#   Exit | Meaning                                        | Message must name
#   -----+------------------------------------------------+---------------------------------
#   0    | -h / --help printed usage; or every step is    | — (usage; or the per-step
#        | done or was completed                          |     transcript)
#   1    | a step is BLOCKED and needs a human            | the step and what to fix
#   2    | an argument this script does not understand    | the argument, verbatim
#
# THERE IS NO --dry-run HERE, AND THAT IS DELIBERATE. This repository already
# has one and it is spelled `make doctor`: Bootstrap::Runner#doctor walks the
# SAME @steps this driver walks and asks each one only for its `check` half,
# never its acting half. Adding a second flag that did something subtly
# different from that would be the dishonest-dry-run shape plan 05-20 measured
# in bin/ship.rb, where `--dry-run` dispatches a real workflow run with the
# upload skipped. The usage below points at `make doctor` instead of shipping a
# flag that lies. test/driver_argv_test.rb asserts both halves of this: that
# `--dry-run` is REFUSED here, and that Runner#doctor calls no step's acting
# half while Runner#bootstrap does.
#
# Usage: bundle exec ruby bin/bootstrap-fork.rb  (see --help)

# The usage text, printed by -h / --help and quoted back on a refusal. It names
# what the command DOES before it lists anything else, because the reader most
# likely to type --help is the one who does not yet know this creates
# repositories and writes secrets.
USAGE = <<~TEXT
  bin/bootstrap-fork.rb — run every programmatic fork-bootstrap step.

  Acts on GitHub and on Apple. Depending on what is not yet done, this WILL:

      push commits straight to main (no pull request is opened)
      write repository secrets to the GitHub repo named in .bootstrap.env
      apply branch protection to main
      create the certs/profiles this fork's release mode needs

  Every step is a no-op when its desired state is already reached, so
  re-running after a partial failure picks up where it stopped. It VERIFIES
  the app identity and never rewrites it.

  Usage:
    bundle exec ruby bin/bootstrap-fork.rb          run the steps that are pending
    bundle exec ruby bin/bootstrap-fork.rb --help   print this usage (-h is an alias)

  There is no --dry-run. The read-only preview is `make doctor`: it walks the
  same steps and only reports on each, rather than running it. Run that first
  if you want to see what this command would do.

  Configuration comes from .bootstrap.env; app identity from
  app/Identity.xcconfig.

  Exit codes: 0 usage, or every step done; 1 a step is blocked and needs you;
  2 an argument this script does not understand.
TEXT

# Parsed BEFORE the library is even loaded, and so before anything reads
# credentials or opens a connection. An unrecognised argument — flag-shaped or
# not — is refused by name and never ignored, because ignoring one is exactly
# how a `--help` typed as a usage probe became a live production call on
# 2026-09-03 (gap GAP-05-02, ledger row UL-051).
ARGV.each do |arg|
  case arg
  when "-h", "--help"
    puts USAGE
    exit 0
  else
    warn "[bootstrap-fork] Unrecognised argument: #{arg}"
    warn "[bootstrap-fork] Nothing was contacted and nothing was written."
    warn ""
    warn USAGE
    exit 2
  end
end

require_relative "lib/bootstrap"

config = Bootstrap::Config.load!
Bootstrap::Runner.new(config).bootstrap
