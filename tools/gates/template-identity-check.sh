#!/usr/bin/env bash
# B-02: the canonical template-identity gate for phase 08.6.
#
# Replaces `git diff --stat upstream/main -- ci/ Makefile fastlane/Fastfile fastlane/Snapfile`
# asserted EMPTY, which CANNOT PASS: this fork shares no merge-base with `upstream/main`, so that
# diff reports the fork's entire deliberate divergence (19 files, 2311 deletions) as drift.
#
# Two halves, per 74's ruling 2026-09-15:
#   1. PHASE SCOPE (authoritative) — this phase changed none of the template-owned paths.
#      Compared BASE-to-WORKING-TREE, not BASE..HEAD: a `BASE..HEAD` range compares two
#      COMMITS and is blind to an uncommitted edit. Found by the planted-red control,
#      which passed against a modified Makefile until this was fixed.
#   2. UPSTREAM PARITY (narrow)    — the two capture scripts still match upstream, and a red
#                                    says WHOSE change it is.
set -uo pipefail

BRANCH_POINT_FILE=".planning/phases/08.6-screenshot-capture-path-witnessed/08.6-BRANCH-POINT.md"
BROAD_PATHS=(ci/ Makefile fastlane/Fastfile fastlane/Snapfile)
CAPTURE_SCRIPTS=(ci/take-screenshots.sh ci/extract-mac-screenshots.sh)
rc=0

# --- base: computed, then cross-checked against the recorded sha (ruling point 2) -------------
BASE="$(git merge-base HEAD origin/main 2>/dev/null || true)"
if [ -z "$BASE" ]; then
  echo "FAIL base: no merge-base between HEAD and origin/main"; exit 1
fi
RECORDED="$(grep -oE '[0-9a-f]{40}' "$BRANCH_POINT_FILE" | head -1)"
if [ "$BASE" != "$RECORDED" ]; then
  echo "FAIL base-moved: merge-base HEAD origin/main is $BASE but $BRANCH_POINT_FILE records $RECORDED."
  echo "     The gate's question silently changed. Reconcile the branch point before trusting any result below."
  rc=1
else
  echo "OK   base=$BASE (matches the recorded branch point)"
fi

# --- half 1: phase scope ----------------------------------------------------------------------
if git diff --quiet "$BASE" -- "${BROAD_PATHS[@]}"; then
  echo "OK   phase-scope: this phase changed none of ${BROAD_PATHS[*]}"
else
  echo "FAIL phase-scope: THIS PHASE changed a template-owned path (D-131). Files:"
  git diff --name-only "$BASE" -- "${BROAD_PATHS[@]}" | sed 's/^/       /'
  rc=1
fi

# --- half 2: upstream parity, and WHOSE change it is (ruling point 3) --------------------------
if git rev-parse --verify --quiet upstream/main >/dev/null; then
  if git diff --quiet upstream/main -- "${CAPTURE_SCRIPTS[@]}"; then
    echo "OK   upstream-parity: ${CAPTURE_SCRIPTS[*]} match upstream/main"
  else
    echo "FAIL upstream-parity: the capture scripts differ from upstream/main. Attributing:"
    for f in "${CAPTURE_SCRIPTS[@]}"; do
      ours=no; theirs=no
      git diff --quiet "$BASE" -- "$f" || ours=yes
      git diff --quiet "$BASE" upstream/main -- "$f" || theirs=yes
      echo "       $f: changed_by_us=$ours changed_upstream_since_branch_point=$theirs"
    done
    echo "       changed_by_us=yes -> WE moved a template-owned file; revert it (D-131)."
    echo "       changed_upstream_since_branch_point=yes -> UPSTREAM moved; this is a re-pin decision, not fork drift."
    rc=1
  fi
else
  echo "SKIP upstream-parity: no upstream/main ref in this clone"
fi

exit $rc
