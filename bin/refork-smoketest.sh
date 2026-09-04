#!/usr/bin/env bash
# Refork the public smoketest to validate the template end-to-end.
#
# Automates the destructive cycle the E2E refork test depends on (see
# docs/CONTINUOUS-VALIDATION.md). Run from the apple-shipkit repo root.
#
# What it does (in order):
#
#   1. Archive the smoketest's PRs + run logs to .planning/smoketest-history/
#   2. Revoke "Created via API" Apple certs (smoketest residue) to free quota
#   3. Delete the smoketest app repo + clear local clone
#   4. Reset (default) or nuke the certs repo
#         - reset: force-push empty branches, preserves the certs repo's
#           database id so the existing fine-grained PAT keeps working (G12)
#         - nuke: delete + recreate the certs repo (PAT scope must be
#           updated manually after; see G12 in CONTINUOUS-VALIDATION.md)
#   5. Re-fork the smoketest from indiagrams/ios-macos-smoketest
#   6. Run bin/rename.sh with the chosen --generator
#   7. Run make bootstrap (toolchain), commit, push, set branch protection
#   8. Materialize .bootstrap.env in the new clone, pre-filled with
#      smoketest identity + Apple credentials (sourced from
#      ~/.config/secrets.env) + the chosen RELEASE_MODE
#
# After this script exits cleanly, the smoketest is in a state equivalent
# to a fresh forker who has just run `make init` + filled .bootstrap.env.
# The next manual step is `make doctor && make bootstrap-fork` (or
# `make all`) from inside ../ios-macos-smoketest.
#
# Apple-side state NOT touched (Apple disallows API deletion):
#   - Bundle ID (--bundle-id; default com.indiagram.smoke-app) — idempotent
#     register_app_id covers it
#   - ASC App record (verify-mode bootstrap_asc covers it)
#
# Required env (read from ~/.config/secrets.env):
#   FASTLANE_TEAM_ID, ASC_API_KEY_ID, ASC_API_KEY_ISSUER_ID,
#   ASC_API_KEY_P8_BASE64, MATCH_PASSWORD, MATCH_GIT_BASIC_AUTHORIZATION,
#   KEYCHAIN_PASSWORD
#
# Required `gh auth` scopes: delete_repo + repo
#
# Usage:
#   bin/refork-smoketest.sh [OPTIONS]
#
# Options:
#   --keep-certs-repo               Reset certs repo (default; PAT scope retained)
#   --nuke-certs-repo               Delete + recreate certs repo (PAT update needed)
#   --generator=xcodegen|tuist      Project generator (default: xcodegen)
#   --release-mode=ci|local         Bootstrap mode written to .bootstrap.env (default: ci)
#   --bundle-id=ID                  App bundle id (default: com.indiagram.smoke-app)
#   --asc-app-name=NAME             App Store Connect record name. REQUIRED (no default;
#                                   ASC_APP_NAME in the environment also satisfies it)
#   --display-name=NAME             CFBundleDisplayName for the reforked app. REQUIRED
#                                   (no default; DISPLAY_NAME in the environment also
#                                   satisfies it)
#   --skip-cert-revoke              Skip revoking "Created via API" certs — REQUIRED
#                                   when the Apple team is shared with other apps
#                                   (a team-wide revoke kills co-tenant certs)
#   -h, --help                      Show this message

set -euo pipefail

# ─── Defaults + flag parsing ──────────────────────────────────────────────────

KEEP_CERTS=true
GENERATOR=xcodegen
RELEASE_MODE=ci
SKIP_CERT_REVOKE=false

usage() {
  awk '/^# Usage:/{flag=1} flag && /^[^#]/{exit} flag{sub(/^# ?/, ""); print}' "$0"
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --keep-certs-repo)        KEEP_CERTS=true ;;
    --nuke-certs-repo)        KEEP_CERTS=false ;;
    --generator=*)            GENERATOR="${1#*=}" ;;
    --release-mode=*)         RELEASE_MODE="${1#*=}" ;;
    --bundle-id=*)            BUNDLE_ID="${1#*=}" ;;
    --asc-app-name=*)         ASC_APP_NAME="${1#*=}" ;;
    --display-name=*)         DISPLAY_NAME="${1#*=}" ;;
    --skip-cert-revoke)       SKIP_CERT_REVOKE=true ;;
    -h|--help)                usage 0 ;;
    *)                        echo "unknown flag: $1" >&2; usage 64 ;;
  esac
  shift
done

case "$GENERATOR" in
  xcodegen|tuist) ;;
  *) echo "--generator must be xcodegen or tuist (got: $GENERATOR)" >&2; exit 64 ;;
esac

case "$RELEASE_MODE" in
  ci|local) ;;
  *) echo "--release-mode must be ci or local (got: $RELEASE_MODE)" >&2; exit 64 ;;
esac

# ─── Constants ────────────────────────────────────────────────────────────────

ORG=indiagrams
TEMPLATE_REPO="$ORG/apple-shipkit"
APP_REPO="$ORG/ios-macos-smoketest"
CERTS_REPO="$ORG/ios-macos-smoketest-certs"
APP_NAME=SmokeApp
BUNDLE_ID="${BUNDLE_ID:-com.indiagram.smoke-app}"
APP_EMAIL=maintainers@indiagram.com
ASC_APP_SKU=indiagram-smoke-001

# DISPLAY_NAME and ASC_APP_NAME carry NO default, deliberately (A-08 / D-75).
#
# Both used to default to one specific product's prose name. ASC_APP_NAME is
# written into the generated .bootstrap.env below and becomes the App Store
# Connect record name bin/lib/bootstrap.rb creates or renames, and it is also
# what fastlane/metadata/en-US/name.txt — the App Store listing name deliver
# uploads — is generated from. A silent default there names a NEW store record
# after a DIFFERENT shipping product, which is App Store Review guideline 2.2's
# exact prohibition, inside an Apple team shared with other apps.
#
# Neither value is derivable here: this script runs from the apple-shipkit repo
# root, and the fork it creates does not exist yet, so there is no
# app/Identity.xcconfig to read them from. The only two options are "ask" and
# "guess", and this project refuses the second everywhere else. So: refuse BY
# NAME, and do it here — above the preflight, far above step 3, which DELETES
# the app repo.
#
# Indirect expansion is bash's ${!name}, matching the secrets loop below in this
# same file. The flag spelling is written out rather than derived from the
# variable name: bash 3.2 (macOS /bin/bash) has no ${var,,}, and a derivation
# that silently produced the wrong flag would send the operator hunting a typo.
for identity_pair in DISPLAY_NAME:--display-name ASC_APP_NAME:--asc-app-name; do
  identity_key="${identity_pair%%:*}"
  identity_flag="${identity_pair#*:}"
  [ -n "${!identity_key:-}" ] || {
    echo "$identity_key is required and has no default." >&2
    echo "  pass $identity_flag=NAME, or set $identity_key in the environment." >&2
    exit 64
  }
done

CLONE_PARENT="$(cd .. && pwd)"
CLONE_DIR="$CLONE_PARENT/ios-macos-smoketest"

# ─── Preflight ────────────────────────────────────────────────────────────────

echo "Refork smoketest — generator=$GENERATOR release_mode=$RELEASE_MODE certs=$([ "$KEEP_CERTS" = true ] && echo keep || echo nuke)"
echo

[ -f "$HOME/.config/secrets.env" ] || { echo "missing ~/.config/secrets.env" >&2; exit 1; }
set -a
# shellcheck disable=SC1091
source "$HOME/.config/secrets.env"
set +a

# Validate required secrets vars are populated
for k in FASTLANE_TEAM_ID ASC_API_KEY_ID ASC_API_KEY_ISSUER_ID ASC_API_KEY_P8_BASE64 \
         MATCH_PASSWORD MATCH_GIT_BASIC_AUTHORIZATION KEYCHAIN_PASSWORD; do
  v="${!k:-}"
  [ -n "$v" ] || { echo "~/.config/secrets.env missing $k" >&2; exit 1; }
done

gh auth status 2>&1 | grep -qE "delete_repo" \
  || { echo "gh auth missing delete_repo scope; run: gh auth refresh -s delete_repo" >&2; exit 1; }

# ─── 1. Archive ───────────────────────────────────────────────────────────────

echo "=== 1/8: archive PRs + key runs ==="
ARCHIVE_DIR=".planning/smoketest-history/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$ARCHIVE_DIR"
gh pr list --repo "$APP_REPO" --state all --limit 100 --json number,title,state,mergedAt,body,url \
  > "$ARCHIVE_DIR/pr-list.json" 2>/dev/null || echo "  (no PRs to archive)"
gh run list --repo "$APP_REPO" --limit 50 --json databaseId,displayTitle,conclusion,createdAt,workflowName,event \
  > "$ARCHIVE_DIR/run-list.json" 2>/dev/null || true
echo "  archive → $ARCHIVE_DIR"

# ─── 2. Revoke residue Apple certs ────────────────────────────────────────────

if [ "$SKIP_CERT_REVOKE" = true ]; then
  echo "=== 2/8: SKIPPING 'Created via API' cert revocation (--skip-cert-revoke) ==="
  echo "  The Apple team is shared with other apps; a team-wide revoke would kill"
  echo "  co-tenant certs. The canary mints + revokes its own certs each run."
else
  echo "=== 2/8: revoke 'Created via API' Apple certs (smoketest residue) ==="
  unset APP_STORE_CONNECT_API_KEY_KEY APP_STORE_CONNECT_API_KEY_KEY_FILEPATH \
        APP_STORE_CONNECT_API_KEY_KEY_ID APP_STORE_CONNECT_API_KEY_ISSUER_ID

  if [ -d "$CLONE_DIR/fastlane" ]; then
    pushd "$CLONE_DIR" >/dev/null
    bundle exec fastlane list_certs 2>&1 \
      | awk '/Created via API/ { for (i=1;i<=NF;i++) if ($i ~ /^[A-Z0-9]{10}$/) { print $i; break } }' \
      | while read -r cert_id; do
          echo "  revoking $cert_id"
          bundle exec fastlane revoke_cert "id:$cert_id" 2>&1 | grep -E "Revoked|error" | head -1
        done
    popd >/dev/null
  else
    echo "  no local smoketest clone at $CLONE_DIR; skipping cert revocation"
  fi
fi

# ─── 3. Delete app repo + clear local clone ───────────────────────────────────

echo "=== 3/8: delete app repo + clear local clone ==="
if gh repo view "$APP_REPO" --json name >/dev/null 2>&1; then
  gh repo delete "$APP_REPO" --yes
  echo "  deleted $APP_REPO"
else
  echo "  $APP_REPO doesn't exist; skipping"
fi
rm -rf "$CLONE_DIR"

# ─── 4. Reset or nuke certs repo ──────────────────────────────────────────────

if [ "$KEEP_CERTS" = false ]; then
  echo "=== 4/8: NUKE certs repo ==="
  echo "  WARNING: PAT will need scope update on github.com/settings/tokens"
  if gh repo view "$CERTS_REPO" --json name >/dev/null 2>&1; then
    gh repo delete "$CERTS_REPO" --yes
  fi
else
  echo "=== 4/8: RESET certs repo (force-push empty branches) ==="
  if gh repo view "$CERTS_REPO" --json name >/dev/null 2>&1; then
    TMPDIR_CERTS=$(mktemp -d)
    gh repo clone "$CERTS_REPO" "$TMPDIR_CERTS" -- --quiet 2>&1 | tail -1 || true
    pushd "$TMPDIR_CERTS" >/dev/null
    git checkout --orphan reset-tmp >/dev/null 2>&1
    git reset --hard >/dev/null 2>&1
    git -c user.email=refork@local.invalid -c user.name=refork commit --allow-empty -m "reset for E2E" -q
    for branch in $(git branch -r | grep -v HEAD | sed 's|origin/||'); do
      git push origin --delete "$branch" 2>&1 | tail -1 || true
    done
    popd >/dev/null
    rm -rf "$TMPDIR_CERTS"
    echo "  certs repo reset; PAT scope retained"
  else
    echo "  $CERTS_REPO doesn't exist — creating"
    gh repo create "$CERTS_REPO" --private --description "Encrypted certs + profiles for $APP_REPO"
  fi
fi

# ─── 5. Re-fork from template ─────────────────────────────────────────────────

echo "=== 5/8: re-fork smoketest from $TEMPLATE_REPO ==="
( cd "$CLONE_PARENT" && \
    gh repo create "$APP_REPO" --template "$TEMPLATE_REPO" --public --clone -- --quiet 2>&1 | tail -1 )
[ -d "$CLONE_DIR" ] || { echo "expected clone at $CLONE_DIR but it's missing" >&2; exit 1; }
echo "  fresh fork at $CLONE_DIR"

# ─── 6. Identity config (replaces the retired rename step) ───────────────────

# WHAT REPLACED THE RENAME STEP.
#
# This step used to run `bin/rename.sh <app> <bundle-id> <display-name>` followed
# by the rename self-check script. Phase 5 retired both: app/Identity.xcconfig is
# now the single tracked source of truth for identity (A-01 / D-45), bin/rename.sh
# no longer substitutes any identity value, and the self-check was deleted with the
# substitution it checked. The forker path is "edit four values in one tracked
# file" — see docs/MIGRATING-FROM-RENAME.md.
#
# Nothing is automated in its place, and that is deliberate rather than an
# oversight. A fresh clone of the template legitimately ships placeholder
# identity, so any check written here would pass on both a correct and an
# incorrect tree — a pass condition satisfied regardless of what it claims to
# detect is the one shape this project refuses by name. The gap is NAMED instead,
# by gates that already exist and already run in the operator's documented next
# step: `make doctor` reports IdentityAdopted blocked at tier 2 while the four
# values are still the template's, and `make bootstrap-fork` refuses to go past
# it. Both are printed at the end of this run.
#
# bin/rename.sh survives as prose personalization only (contact address and
# GitHub slug across README.md and CONTRIBUTING.md). It is NOT run here: it is
# cosmetic for a throwaway smoketest fork.
echo "=== 6/8: identity config (generator=$GENERATOR) ==="
pushd "$CLONE_DIR" >/dev/null
echo "  app/Identity.xcconfig still carries the template's placeholder identity."
echo "  Edit its four values before 'make bootstrap-fork'."
echo "  See docs/MIGRATING-FROM-RENAME.md."

# ─── 7. Toolchain + initial push + branch protection ──────────────────────────

echo "=== 7/8: bootstrap toolchain + initial push + branch protection ==="
unset TMPDIR # local-check.sh hates a stale TMPDIR
make bootstrap 2>&1 | tail -3
git add -A
git -c user.email="$APP_EMAIL" -c user.name="$APP_NAME bootstrap" \
  commit -m "Rename app stub + initial bootstrap" 2>&1 | tail -1
git push -u origin main 2>&1 | tail -1
bin/setup-github.sh 2>&1 | tail -3

# ─── 8. Materialize .bootstrap.env with chosen mode + smoketest identity ──────

echo "=== 8/8: write .bootstrap.env (release_mode=$RELEASE_MODE) ==="
cat > .bootstrap.env <<EOF
APP_NAME=$APP_NAME
BUNDLE_ID=$BUNDLE_ID
DISPLAY_NAME='$DISPLAY_NAME'
APP_EMAIL=$APP_EMAIL
GENERATOR=$GENERATOR
RELEASE_MODE=$RELEASE_MODE
FASTLANE_TEAM_ID=$FASTLANE_TEAM_ID
ASC_API_KEY_ID=$ASC_API_KEY_ID
ASC_API_KEY_ISSUER_ID=$ASC_API_KEY_ISSUER_ID
ASC_API_KEY_P8_PATH=~/.config/secrets/AuthKey_$ASC_API_KEY_ID.p8
GH_ORG=$ORG
GH_APP_REPO=ios-macos-smoketest
GH_CERTS_REPO=ios-macos-smoketest-certs
GH_PAT_FILE=~/.config/secrets/smoketest-pat
MATCH_PASSWORD_FILE=~/.config/secrets/match-password
KEYCHAIN_PASSWORD_FILE=~/.config/secrets/keychain-password
ICON_1024_PATH=
ASC_APP_SKU=$ASC_APP_SKU
ASC_APP_NAME='$ASC_APP_NAME'
EOF
echo "  wrote .bootstrap.env"
popd >/dev/null

# ─── Done ─────────────────────────────────────────────────────────────────────

cat <<EOF

===============================================================================
Refork complete. Smoketest is in fresh-forked + bootstrapped-toolchain state.
generator=$GENERATOR release_mode=$RELEASE_MODE certs=$([ "$KEEP_CERTS" = true ] && echo reset || echo nuked)

Next:
  cd $CLONE_DIR
  make doctor          # validate state — should be ✗-pending in many places
  make bootstrap-fork  # mints certs (ci) or probes keychain (local)
  # or:
  make all             # one-shot: doctor → bootstrap-fork → ship → verify
===============================================================================
EOF
