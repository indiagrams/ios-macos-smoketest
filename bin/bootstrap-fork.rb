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
# Usage: bundle exec ruby bin/bootstrap-fork.rb

require_relative "lib/bootstrap"

config = Bootstrap::Config.load!
Bootstrap::Runner.new(config).bootstrap
