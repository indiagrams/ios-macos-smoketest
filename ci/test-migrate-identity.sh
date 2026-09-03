#!/usr/bin/env bash
# ci/test-migrate-identity.sh — fixture harness for the rename→config migration (IDENT-14).
#
# ── WHAT THIS SCRIPT PROVES ──────────────────────────────────────────────────
#
# That a *genuinely* structurally-renamed fork can be reconstructed on demand from an
# immutable git object, and that the reconstruction is what we believe it is BEFORE any
# migration runs against it. A migration test whose fixture silently stopped containing a
# structural rename would pass forever while exercising nothing. This file exists to make
# that failure mode loud.
#
# It is DELIBERATELY RED through phase 5 waves 1-4. It builds the fixture, asserts the
# fixture's shape, records the pre-migration identity-gate baseline, and then refuses BY NAME
# because the migration command it would drive does not exist yet. Plan 05-05 wires the green
# half and adds the workflow that calls this script. Nothing invokes it before then, precisely
# so a deliberately-red script never puts a false failure signal on the phase branch. Do not
# "fix" the exit code before 05-05.
#
# ── THE TWO FIXTURE BASES (FIXTURE_REF) ──────────────────────────────────────
#
#   e773cfc  default — this fork's pre-#281 initial commit. Ships app/Shared/HelloApp.swift,
#            `name: HelloApp` in app/project.yml, and NO app/Identity.xcconfig. Not yet
#            renamed to the fixture identity, so bin/rename.sh RUNS here and regenerates the
#            structural rename.
#   9589de1  ground-truth control — "Rename app stub + initial bootstrap": a real historical
#            rename performed by the real script, with five renames recorded in the commit
#            (R097 app/Shared, R100 x2 entitlements, R074 Tests, R072 MacOSTests). Already
#            renamed to `SmokeApp`, so bin/rename.sh must NOT run against it.
#
# A-04 (.planning/…/05-CONTEXT.md) replaced D-68's original recipe — clone upstream/main, run
# bin/rename.sh — because upstream's post-#281 script performs NO structural rename at all.
# Its own comment, verified at upstream/main d714006 line 722, reads: "There are no file-path
# renames. … (This script used to `git mv` five files here.)". That recipe structurally cannot
# produce this fixture.
#
# ── WHY THE BLOB SHA IS PINNED ───────────────────────────────────────────────
#
# f9b58ca07875619dbae60fe7f64c829d19721190 is the blob of bin/rename.sh at BOTH e773cfc and
# 9589de1 — the pre-#281 script that actually performs the five `git mv`s.
#
# Today the working-tree copy of bin/rename.sh happens to be byte-identical to that blob. Plan
# 05-10 trims the working copy and the equality ENDS. A fixture generator that resolved
# bin/rename.sh from the working tree, or from whatever the repository currently has checked
# out, would from 05-10 onward silently build a fixture with no structural rename in it — the
# self-invalidating-gate anti-pattern, one level up, at the plan level.
#
# So the assertion below pins the two FIXTURE COMMITS by name and deliberately never compares
# against the repository's current copy. That comparison is exactly what 05-10 breaks.
#
# ── EXIT-CODE CONTRACT OF THE GATE THIS HARNESS DRIVES RED ───────────────────
# (bin/preflight-identity.rb:32-48)
#
#   0  every required variable present and non-empty
#   1  unknown or malformed argv
#   2  Identity.xcconfig not found, or not a regular file, or unresolvable
#   3  one or more required variables missing or empty
#   4  --require-team given and the team is unresolvable
#
# The un-migrated fixture has no app/Identity.xcconfig at all, so the expected baseline is
# exit 2 — the RED half of phase 5 criterion 1's falsifiable pair. It is RECORDED as a
# greppable transcript line, not asserted away. Plan 05-05 adds the green half (exit 0 on the
# migrated fixture).
#
# ── PINNED INTERPRETERS ──────────────────────────────────────────────────────
#
#   /opt/homebrew/opt/ruby@3.3/bin/ruby   (3.3.12)  — first choice
#   /opt/homebrew/opt/ruby@4.0/bin/ruby   (4.0.6)   — second choice
#   NEVER /usr/bin/ruby (2.6.10) when a pinned interpreter is on the machine. All three were
#   measured to exit 2 on a missing --config path on 2026-09-02, but the project rule is to
#   pin rather than to rely on that coincidence continuing to hold. The resolved interpreter
#   is announced on every run.
#
# ── THIS SCRIPT'S OWN EXIT CODES ─────────────────────────────────────────────
#
#   0  not reachable in waves 1-4 — see the precondition refusal at the end
#   1  any assertion failed, or the named precondition refusal fired
#
# Usage:
#   bash ci/test-migrate-identity.sh                      # e773cfc regeneration (default)
#   FIXTURE_REF=9589de1 bash ci/test-migrate-identity.sh  # ground-truth control

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR=""

step() { printf '\n==> %s\n' "$*"; }
ok()   { printf '    ✓ %s\n' "$*"; }
fail() { printf '    ✗ %s\n' "$*" >&2; exit 1; }

cleanup() {
  if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
    rm -rf "$WORK_DIR"
  fi
}
trap 'cleanup' EXIT INT TERM

# The pin. See "WHY THE BLOB SHA IS PINNED" above.
RENAME_SH_BLOB="f9b58ca07875619dbae60fe7f64c829d19721190"

# The identity the fixture is renamed TO when regenerating from e773cfc. Fixed, non-secret,
# and .invalid / example.com by construction — no operator-supplied value reaches sed here.
FIXTURE_APP_NAME="MigrateFixture"
FIXTURE_BUNDLE_ID="com.example.migratefixture"
FIXTURE_DISPLAY_NAME="Migrate Fixture"
FIXTURE_EMAIL="fixture@example.invalid"
FIXTURE_SLUG="example/fixture"

# ── Fixture selection ────────────────────────────────────────────────────────
#
# Announced on EVERY run, the way ci/local-release-check.sh:165-177 announces IDENTITY_XCCONFIG:
# a ground-truth run must never be mistakable for a regeneration run in a log.
if [ -n "${FIXTURE_REF+x}" ]; then
  FIXTURE_REF_OVERRIDDEN=true
else
  FIXTURE_REF_OVERRIDDEN=false
fi
FIXTURE_REF="${FIXTURE_REF:-e773cfc}"

case "$FIXTURE_REF" in
  e773cfc)
    FIXTURE_TOKEN="HelloApp"          # the token present in the base, BEFORE rename.sh runs
    RENAMED_TOKEN="$FIXTURE_APP_NAME" # the token the fixture must carry AFTER rename.sh runs
    RUN_RENAME=true
    EXPECT_XCODEPROJ=true
    FIXTURE_MODE="regeneration — bin/rename.sh runs and performs the structural rename"
    ;;
  9589de1)
    FIXTURE_TOKEN="SmokeApp"
    RENAMED_TOKEN="SmokeApp"          # already renamed at this ref; re-renaming would be a lie
    RUN_RENAME=false
    EXPECT_XCODEPROJ=false            # this ref predates xcodeproj generation in CI
    FIXTURE_MODE="ground-truth control — already renamed at this ref, bin/rename.sh does NOT run"
    ;;
  *)
    fail "FIXTURE_REF='${FIXTURE_REF}' rejected — the only accepted values are 'e773cfc' (regeneration) and '9589de1' (ground-truth control). Anything else would build a fixture whose shape this script cannot assert."
    ;;
esac

step "0/10 Fixture selection"
printf '    fixture base: %s (%s)\n' "$FIXTURE_REF" "$FIXTURE_MODE"
printf '    pre-rename token: %s   post-rename token: %s\n' "$FIXTURE_TOKEN" "$RENAMED_TOKEN"
if [ "$FIXTURE_REF_OVERRIDDEN" = true ]; then
  printf '    FIXTURE_REF override in effect — this is NOT the default regeneration run\n'
fi

# Pin the interpreter. Never /usr/bin/ruby (2.6.10) when a pinned one is installed.
RUBY_BIN=""
for candidate in /opt/homebrew/opt/ruby@3.3/bin/ruby /opt/homebrew/opt/ruby@4.0/bin/ruby; do
  if [ -x "$candidate" ]; then
    RUBY_BIN="$candidate"
    break
  fi
done
if [ -z "$RUBY_BIN" ]; then
  # CI runners use setup-ruby / the runner image's ruby; neither pinned path exists there.
  RUBY_BIN="$(command -v ruby || true)"
  [ -n "$RUBY_BIN" ] || fail "no ruby on PATH and neither pinned interpreter is installed"
fi
printf '    ruby: %s (%s)\n' "$RUBY_BIN" "$("$RUBY_BIN" -e 'print RUBY_VERSION')"

# ── 1/10 Non-shallow self-assertion ──────────────────────────────────────────
#
# Asserted HERE, in the test, and not left to `fetch-depth: 0` in the workflow. That YAML line
# is a config line anybody can delete with nothing going red — deleting it would blind this
# test rather than break it. Same discipline as tools/gitleaks.rb, recorded in place at
# .github/workflows/review-notes.yml:92. actions/checkout defaults to depth 1 and structurally
# cannot see e773cfc.
step "1/10 Non-shallow self-assertion"
cd "$REPO_ROOT"

SHALLOW="$(git rev-parse --is-shallow-repository)"
[ "$SHALLOW" = "false" ] || \
  fail "shallow clone (git rev-parse --is-shallow-repository = '$SHALLOW') — the fixture commits are unreachable. The workflow needs 'fetch-depth: 0'; actions/checkout defaults to depth 1."
ok "repository is not a shallow clone"

git rev-parse --verify --quiet "${FIXTURE_REF}^{commit}" >/dev/null || \
  fail "fixture commit ${FIXTURE_REF} does not resolve in this repository"
ok "fixture commit ${FIXTURE_REF} resolves"

# ── 2/10 Pre-flight ──────────────────────────────────────────────────────────
step "2/10 Pre-flight"
test -x bin/rename.sh          || fail "bin/rename.sh not executable in $REPO_ROOT"
command -v git      >/dev/null || fail "git not on PATH"
command -v xcodegen >/dev/null || fail "xcodegen not on PATH — run 'make bootstrap' first"
test -f bin/preflight-identity.rb || fail "bin/preflight-identity.rb missing in $REPO_ROOT"
ok "tools present"

if git rev-parse --verify --quiet origin/main >/dev/null; then
  ANCESTOR_REF="origin/main"
else
  ANCESTOR_REF="HEAD"
  ok "origin/main is not a local ref here — asserting ancestry against HEAD instead"
fi
git merge-base --is-ancestor "$FIXTURE_REF" "$ANCESTOR_REF" || \
  fail "${FIXTURE_REF} is not an ancestor of ${ANCESTOR_REF} — this is not the history the fixture was pinned against"
ok "${FIXTURE_REF} is an ancestor of ${ANCESTOR_REF}"

# ── 3/10 Blob pin ────────────────────────────────────────────────────────────
#
# Both fixture commits, by name. Never the repository's current copy — that equality is what
# plan 05-10 ends, and depending on it is how this fixture would go quietly vacuous.
step "3/10 Blob pin on bin/rename.sh"
for pinned_ref in e773cfc 9589de1; do
  actual_blob="$(git rev-parse "${pinned_ref}:bin/rename.sh")"
  [ "$actual_blob" = "$RENAME_SH_BLOB" ] || \
    fail "rename.sh blob drifted at ${pinned_ref} — the fixture generator is no longer the pre-#281 script; refusing to build a fixture that cannot contain the defect this test exists to prove (expected ${RENAME_SH_BLOB}, got ${actual_blob})"
  ok "${pinned_ref}:bin/rename.sh == ${RENAME_SH_BLOB}"
done

# ── 4/10 Clone to tmpdir ─────────────────────────────────────────────────────
step "4/10 Clone to tmpdir"
WORK_DIR="$(mktemp -d -t test-migrate-identity-XXXXXX)"
ok "tmpdir: $WORK_DIR"

git clone --no-hardlinks --quiet "$REPO_ROOT" "$WORK_DIR"
ok "cloned $REPO_ROOT -> $WORK_DIR"

cd "$WORK_DIR"
# Every destructive command below runs relative to CWD. A failed `cd` would aim them at the
# operator's real tree, where `-fdx` would delete gitignored .bootstrap.env, app/Local.xcconfig
# (the Team ID) and the un-versioned .planning/. Assert, do not assume (T-05-01).
[ "$PWD" = "$WORK_DIR" ] || \
  fail "cd to the tmpdir did not take: PWD='$PWD' but WORK_DIR='$WORK_DIR' — refusing to run anything destructive"
ok "CWD is the tmpdir"

# ── 5/10 Fixture base ────────────────────────────────────────────────────────
step "5/10 Fixture base ${FIXTURE_REF}"
# The branch MUST be named 'main': bin/rename.sh's gate_on_main reads it, and a detached
# worktree reports 'HEAD' and fails the gate.
git checkout -q -B main "$FIXTURE_REF" || \
  fail "failed to set main to ${FIXTURE_REF} in the clone"
ok "on branch main at ${FIXTURE_REF} (gate_on_main will pass)"

# -x is permitted ONLY on this line, ONLY inside the verified tmpdir, because rename.sh's
# gate_clean_tree counts untracked files and a fresh checkout leaves generated ones behind.
# The PWD assertion immediately above this line is the guard (T-05-01); do not separate them.
[ "$PWD" = "$WORK_DIR" ] || fail "refusing a destructive clean outside the tmpdir: PWD='$PWD'"
git clean -qffdx
ok "tmpdir tree clean (gate_clean_tree will pass)"

# ── 6/10 Base assertions, BEFORE use ─────────────────────────────────────────
#
# Driven red in 05-01 Task 2 as control=fixture-base-shape by pointing the checkout at the
# repository's current commit, which has app/Shared/App.swift, `name: App` and DOES ship
# app/Identity.xcconfig. Without that control these three lines could be vacuous.
step "6/10 Base assertions"
[ -f "app/Shared/${FIXTURE_TOKEN}.swift" ] || \
  fail "fixture base wrong: app/Shared/${FIXTURE_TOKEN}.swift is missing at ${FIXTURE_REF}"
ok "app/Shared/${FIXTURE_TOKEN}.swift present"

grep -q "^name: ${FIXTURE_TOKEN}$" app/project.yml || \
  fail "fixture base wrong: app/project.yml has no '^name: ${FIXTURE_TOKEN}$' at ${FIXTURE_REF}"
ok "app/project.yml carries 'name: ${FIXTURE_TOKEN}'"

[ ! -f app/Identity.xcconfig ] || \
  fail "fixture base wrong: app/Identity.xcconfig EXISTS at ${FIXTURE_REF} — a pre-#281 fork has no identity config, and its presence would make the exit-2 red baseline unreachable"
ok "app/Identity.xcconfig absent, as a pre-#281 fork must be"

# ── 7/10 Rename (regeneration bases only) ────────────────────────────────────
step "7/10 Structural rename"
if [ "$RUN_RENAME" = true ]; then
  # Exit code captured under `set +e`/`set -e`. Never piped through sed or grep first — $? would
  # become the pipeline's last exit code (05-RESEARCH.md Pitfall 9).
  set +e
  RENAME_OUT="$(bash bin/rename.sh "$FIXTURE_APP_NAME" "$FIXTURE_BUNDLE_ID" "$FIXTURE_DISPLAY_NAME" \
    --email="$FIXTURE_EMAIL" --slug="$FIXTURE_SLUG" 2>&1)"
  RENAME_EXIT=$?
  set -e
  [ "$RENAME_EXIT" -eq 0 ] || \
    fail "bin/rename.sh exited ${RENAME_EXIT} (expected 0) in the fixture tmpdir; output:
${RENAME_OUT}"
  # The "TEAM_ID_PLACEHOLDER still in app/project.yml + app/Project.swift" warning is EXPECTED
  # here — no --team-id is passed, deliberately, because the fixture must carry no real team.
  ok "bin/rename.sh exit 0 (TEAM_ID_PLACEHOLDER warning is expected, not a failure)"
else
  ok "skipped — ${FIXTURE_REF} is already renamed; re-renaming it would destroy the ground truth"
fi

# ── 8/10 Renamed-shape assertions — the property the migration must undo ─────
step "8/10 Renamed-shape assertions"
if [ "$EXPECT_XCODEPROJ" = true ]; then
  [ -d "app/${RENAMED_TOKEN}.xcodeproj" ] || \
    fail "renamed shape wrong: app/${RENAMED_TOKEN}.xcodeproj is not a directory"
  ok "app/${RENAMED_TOKEN}.xcodeproj present"
else
  ok "xcodeproj not required at ${FIXTURE_REF} (that ref predates generation in CI)"
fi

[ -f "app/Shared/${RENAMED_TOKEN}.swift" ] || \
  fail "renamed shape wrong: app/Shared/${RENAMED_TOKEN}.swift is missing"
ok "app/Shared/${RENAMED_TOKEN}.swift present"

[ -f "app/iOS/${RENAMED_TOKEN}.entitlements" ] || \
  fail "renamed shape wrong: app/iOS/${RENAMED_TOKEN}.entitlements is missing — the structural rename did not move the entitlements"
ok "app/iOS/${RENAMED_TOKEN}.entitlements present"

grep -q "^struct ${RENAMED_TOKEN}Main: App {$" "app/Shared/${RENAMED_TOKEN}.swift" || \
  fail "renamed shape wrong: 'struct ${RENAMED_TOKEN}Main: App {' not found in app/Shared/${RENAMED_TOKEN}.swift"
ok "@main struct is ${RENAMED_TOKEN}Main"

grep -q "^name: ${RENAMED_TOKEN}$" app/project.yml || \
  fail "renamed shape wrong: app/project.yml has no '^name: ${RENAMED_TOKEN}$'"
ok "app/project.yml carries 'name: ${RENAMED_TOKEN}'"

[ ! -f app/Identity.xcconfig ] || \
  fail "renamed shape wrong: app/Identity.xcconfig exists post-rename — rename.sh does not write it, so something else did"
ok "app/Identity.xcconfig still absent — the fixture is un-migrated"

# ── 9/10 Red baseline — recorded, not asserted away ──────────────────────────
step "9/10 Red baseline: the identity gate against the un-migrated fixture"
set +e
PREFLIGHT_OUT="$("$RUBY_BIN" "$REPO_ROOT/bin/preflight-identity.rb" --config "$PWD/app/Identity.xcconfig" 2>&1)"
PREFLIGHT_EXIT=$?
set -e
printf 'RESULT baseline=preflight-unmigrated-fixture exit=%s expected=2\n' "$PREFLIGHT_EXIT"
[ "$PREFLIGHT_EXIT" -eq 2 ] || \
  fail "identity gate exited ${PREFLIGHT_EXIT} against the un-migrated fixture (expected 2 = 'not found'); output:
${PREFLIGHT_OUT}"
ok "exit 2 — the RED half of criterion 1's falsifiable pair (plan 05-05 adds the green half)"

# ── 10/10 Precondition refusal ───────────────────────────────────────────────
#
# TWO named refusals, not one, and both exit 1. Plan 05-02 shares wave 1 with this plan and
# creates tools/migrate-identity.rb; with parallelization on and worktrees off, that file may or
# may not exist when this script runs. A single `[ -x ]` assertion here would make this script's
# exit code a race against 05-02's scheduling — and an acceptance criterion that passes or fails
# on scheduling order is not a criterion.
#
# The shape is test/doctor_identity_test.rb:100-114's RED precondition block: a NAMED condition,
# never a backtrace, and never a silent pass.
step "10/10 Precondition: the migration command"
MIGRATE_CMD="$REPO_ROOT/tools/migrate-identity.rb"
if [ ! -e "$MIGRATE_CMD" ]; then
  fail "migration command not present at tools/migrate-identity.rb — plan 05-02 has not landed yet"
else
  fail "migration command present but this script cannot invoke it until plan 05-05 wires the green half — deliberately red through waves 1-4"
fi
