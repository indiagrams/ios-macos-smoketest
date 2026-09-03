# Contributing upstream to apple-shipkit

<!-- This fork's OUTBOUND path: how work done here reaches indiagrams/apple-shipkit.
     For the INBOUND direction — receiving upstream changes — see MAINTAINING-A-FORK.md.
     For apple-shipkit's own PR requirements see ../CONTRIBUTING.md. This document
     deliberately does not restate them; it adds only what is specific to this fork. -->

This fork exists to walk the shipping path for real and find out where the template
hurts. A finding that stays here helps nobody, and it does not survive
`bin/refork-smoketest.sh` either. This document is how a finding gets out.

## 0. Read this first

Upstream's PR requirements are already written down and they apply here unchanged:

- [CONTRIBUTING.md](../CONTRIBUTING.md) — the required CI checks, the Test plan in the
  PR body (required even for docs-only changes), squash-merge with linear history, the
  CHANGELOG entry in the same PR as the change, and the `ci/lib/` SHA-pin regeneration
  protocol.
- [docs/PRINCIPLES.md](PRINCIPLES.md) — the 24-rule operating manual `CONTRIBUTING.md`
  keeps citing.

Read those. Nothing in this file overrides them, and nothing in this file repeats them.

**Budget the cost before you split a change into PRs.** Branch protection on
apple-shipkit's `main` requires all eight checks with `enforce_admins` on, so even the
repo owner pays the full matrix, and six of the eight are macOS build cells. PRINCIPLES
#4 applies the same floor to docs-only PRs. Two consequences:

- Batch by **learning**, not by file. One PR per thing you learned.
- Land a docs change together with the code change it documents. `CONTRIBUTING.md`
  requires that anyway, so the cost argument and the rule point the same direction.

## 1. The SCOPE.md gate (UP-03)

Every proposal runs one test before anything else:

> Does this addition require modifying Swift source files in the app target to use it?

- **No** → it is *around* the project. In scope for upstream.
- **Yes** → it is *inside* the project. Deliberately out of scope.

Cite the sentence, never the path. This fork's [SCOPE.md](../SCOPE.md) names
`app/SmokeApp/`; upstream's current copy names `app/HelloApp/`. The stub directory gets
renamed across template versions, so a quote pinned to the path literal goes stale while
the test itself does not.

A **Yes** is not the end of the process. It still earns a row in
[UPSTREAM-LEDGER.md](UPSTREAM-LEDGER.md) carrying the reason it was ruled out. Recording
why something was deliberately *not* upstreamed is what makes this gate auditable rather
than a matter of memory.

## 2. Strip the fork concretion (UP-05)

Upstream gets the **slot and a placeholder**, never this fork's values. Before the patch
leaves, remove:

- bundle identifiers and any App Store display name belonging to this fork
- the Apple Team ID
- any contact address or phone number
- icon artwork, screenshots, and App Store listing copy
- anything else that would tell a stranger cloning the template whose app this was

The principle behind it: when Apple requires a value in order to ship, this fork supplies
the value and upstream supplies the slot, so apple-shipkit stays generic.

The eventual automated gate is Phase 4's `bin/check-identity.sh`. **It does not exist
yet.** Until it does, this step is a manual read of the diff — do it deliberately, on the
patch, before `git am`, not after you have opened the PR.

## 3. Why you cannot open the PR from this repo

The measured facts, not an assumption:

- This repository was materialised with `gh repo create --template`, **not** by forking.
- Both repositories report `isFork: false` with a null parent. They are not in the same
  fork network.
- They share **no commit ancestry**. `git merge-base HEAD upstream/main` returns nothing;
  the root commits are `e773cfc` here and `f9cd5a8` upstream, and the trees already
  differ by 61 files as of 2026-08-31 — a number that only grows.
- GitHub scopes cross-repository pull requests to repositories in the same network, and
  these two are not, so no cross-repo PR form is available between them.

Three operations are therefore prohibited, each with a specific consequence:

| Never run | What actually happens |
|---|---|
| `git merge upstream/main` | Fails with `fatal: refusing to merge unrelated histories`. Forcing it with `--allow-unrelated-histories` produces a conflict in essentially every file. |
| `git rebase upstream/main` | Same unrelated-history problem, replayed commit by commit. There is no common base to rebase onto. |
| `git push upstream <anything>` | Would upload this repository's entire independent history into apple-shipkit, producing an unreadable PR diff and polluting upstream's history with commits that have nothing to do with it. |

The third one is guarded mechanically rather than by discipline: the `upstream` remote's
push URL is set to the literal string `no-push`, so the operation dies immediately on an
unresolvable remote instead of reaching GitHub. If someone clears it — or after a fresh
clone, where remotes do not survive — restore the guard with:

```bash
git remote set-url --push upstream no-push
```

`upstream` is a **fetch-only comparison remote**. It exists so you can `fetch`, `diff`,
and `log` against the template. It is not a merge source, not a rebase target, and not a
push destination.

## 4. The flow that works

`format-patch` here, `git am` in a separate clone of apple-shipkit, PR opened inside that
repo. Three contexts, three blocks.

**(a) In this fork — set up the comparison remote and use it for comparison.**

```bash
git remote add upstream https://github.com/indiagrams/apple-shipkit.git
git remote set-url --push upstream no-push   # guard: see section 3
git fetch upstream

git diff upstream/main -- docs/    # what has this fork diverged on?
git diff upstream/main --stat      # how far apart are the trees?
git log upstream/main --oneline -20  # what landed upstream recently?
```

**(b) Produce an upstream-shaped patch from the commit that carried the learning.**

```bash
git format-patch -1 <sha> --output-directory /tmp/upstream-patch
```

**(c) In a SEPARATE clone of apple-shipkit — where the PR is actually opened.**

```bash
gh repo clone indiagrams/apple-shipkit ~/code/apple-shipkit
cd ~/code/apple-shipkit
git switch -c feat/short-description
git am /tmp/upstream-patch/*.patch        # or apply the change by hand

# Then, before committing:
#   - strip the fork concretion (section 2)
#   - relocate fork paths to upstream conventions:
#       tools/gen-review-notes.rb  ->  bin/gen-review-notes.rb
#       add a ci/check-<thing>.sh wrapper, matching ci/check-app-icon.sh
#   - update the docs and the CHANGELOG in the SAME commit

make check                                # the floor, per ../CONTRIBUTING.md
git push -u origin feat/short-description
gh pr create                              # a PR *within* apple-shipkit
```

Three things worth stating outright about block (c):

- The push target is **apple-shipkit's own `origin`** — the clone's origin, not this
  repo's. Nothing is ever pushed from this repository.
- **No fork of apple-shipkit is needed**, because the repo owner already has push access
  to it. That is why this flow is simpler than the fork-and-PR dance, not harder.
- **Branch protection still forces the PR and eight green checks**, even for an admin.
  `enforce_admins` is on. There is no direct-to-`main` shortcut for anyone.

## 5. Log it (UP-02, DOC-01)

A row goes into [UPSTREAM-LEDGER.md](UPSTREAM-LEDGER.md) **in the same change that
produced the learning** — not batched at the end of the phase, and not reconstructed
later. A row written three phases after the fact is a reconstruction, not a record, and
it is the reconstruction that quietly stops happening.

Documentation is updated in the same change too, on both sides: the fork-side doc here
and the upstream-side doc in the PR.

These two rules — **a ledger row in the same change** and **documentation in the same
change** — are standing exit criteria on *every* phase of this project, not just the
phase that created this file. The roadmap that declares them is untracked, so this
sentence is the durable statement of them.

When the upstream PR opens, come back and move the row's verdict from `Pending` to
`Submitted [#N]`. When it merges or is declined, move it to a terminal verdict. The
ledger's own header explains why that matters: closing this project out is defined as a
grep over that column.

## 6. Fork operations that `make setup-github` reverts

> **Fixed fork-side on 2026-09-02 (plan 04-11); read the rest of this section as a
> description of the TEMPLATE's behaviour.** `bin/setup-github.sh` in this repository
> no longer PUTs `/protection`. Where protection already exists it reads
> `…/required_status_checks/contexts`, appends only what is missing through the
> additive `POST …/contexts` endpoint, re-reads, and asserts the resulting array,
> printing `before`, `after` and `want` and exiting 1 on any disagreement. A context
> the script did not author therefore survives whether or not anybody remembered to
> name it; `SETUP_GITHUB_EXTRA_CHECKS='review notes'` exists to put the fork's own
> context back on a repository that has already lost it, not to keep one that is
> there. The full PUT survives only behind a 404 on `GET …/protection`, where there
> is no protection object to preserve, and `test/setup_github_test.rb` fails the
> build if that write ever escapes the 404 branch.
>
> **Observed live, once, on 2026-09-02, against this repository's real protection.**
> The fixed script was run twice with `SETUP_GITHUB_EXTRA_CHECKS="review notes"`.
> Both runs exited 0, printed `required contexts: 9 (expected 9)`, and sent no `POST`
> and no `PUT` — the union was already satisfied, which is the case that used to be
> destructive. The full `/protection` object was captured before and after and the
> `diff` was empty: the same nine contexts, and the same `app_id` binding of `null`
> on the two iOS-Simulator cells and `15368` on the other seven. **The binding is the
> assertion that matters, not the count** — a rebuilt array preserves the count 9
> while silently rebinding those two cells, so a count-only check would have passed
> on exactly the damage this change exists to prevent.
>
> **Three callers, and one of them is still exposed.** `make setup-github` and
> `make bootstrap-fork` — the latter through `bin/lib/bootstrap.rb`'s
> `BranchProtection` step, which passes no extra-checks list and does not need to —
> both run the script in this repository and are now safe.
> `bin/refork-smoketest.sh` is not: it deletes this repository and recreates it from
> the template with `gh repo create --template`, so the script that runs in step 7
> is the template's, which still PUTs. That path also takes
> `.github/workflows/review-notes.yml` with it, so what a refork leaves behind is a
> repository with eight required contexts and no ninth job to require — a different
> shape of the same loss. The runbook below is the recovery for that case, once the
> workflow file is back on the branch.

One fork-owned guarantee lives in GitHub state rather than in a file, and one
template-owned script destroys it without saying so. This section exists so that
recovery is a paste rather than an investigation.

### The hazard

`.github/workflows/review-notes.yml` defines a job named **`review notes`**, and
that string is a required status check on `main`. Requiring it is what makes a
red drift check block a merge; without the requirement the workflow still runs
and still goes red, and the merge button still works.

`bin/setup-github.sh` recomputes that requirement from scratch every time it
runs. It builds a `CHECKS` array from the platform matrix — one `app (...)` cell
per platform and generator — then unconditionally appends `swiftlint` and
`swiftformat`, and **PUTs the whole array** as `required_status_checks`. It has
no notion of a fork-added check and no way to learn about one. It is
template-owned, so this fork cannot patch it.

Consequently, running any of these silently drops the `review notes`
requirement:

- `make setup-github`
- `bin/setup-github.sh` directly
- `bin/refork-smoketest.sh`, which recreates the repository from the template

The symptom is quiet by design: nothing fails, no warning is printed, and the
workflow keeps running and reporting. Protection simply lists **eight** contexts
where nine were expected, and a pull request with a red drift check becomes
mergeable again. **The check that stops gating looks exactly like the check that
is gating.** Verify by count, not by looking at the Actions tab.

### Restore it

Additive by construction: it writes back the eight checks it just read, and
appends the ninth. It cannot drop a required build check, and it is idempotent —
running it when the check is already required leaves the array unchanged.

```bash
REPO=indiagrams/ios-macos-smoketest

gh api "repos/$REPO/branches/main/protection/required_status_checks" \
  | jq '{strict: .strict,
         checks: ((.checks | map(select(.context != "review notes")))
                  + [{context: "review notes"}])}' \
  | gh api -X PATCH "repos/$REPO/branches/main/protection/required_status_checks" --input -
```

**PATCH the `required_status_checks` sub-resource. Never PUT `/protection`.**
This is a security property, not a style preference: a PUT rebuilds the entire
protection object from whatever the caller supplies, so a caller who omits
`enforce_admins`, `required_linear_history`, or the approving-review count
silently weakens the branch while appearing to add a check. Never weaken
protection in order to make a check land. That is precisely the bug this section
documents, and reproducing it by hand would be worse than leaving the gate off.

### Verify it

```bash
REPO=indiagrams/ios-macos-smoketest

gh api "repos/$REPO/branches/main/protection/required_status_checks" \
  --jq '.checks[].context' | sort

gh api "repos/$REPO/branches/main/protection" \
  --jq '{enforce_admins: .enforce_admins.enabled,
         strict: .required_status_checks.strict}'
```

**The expected count is nine.** The first command must print exactly nine lines:
the eight template checks — `app (iOS device)`, `app (iOS Simulator)`,
`app (Tuist iOS device)`, `app (Tuist iOS Simulator)`, `app (macOS)`,
`app (Tuist macOS)`, `swiftlint`, `swiftformat` — plus `review notes`. Eight
lines means the requirement was dropped and the gate is off. The second command
must report `true` for both; if either has become `false`, something PUT the
whole protection object and more than this check was lost.

The job name in the workflow and the required context here are the same string,
spaces included. Renaming the job breaks the link in the more dangerous
direction: protection keeps requiring a context that no longer reports, and
every pull request hangs unmergeable rather than merging unchecked.

### The real fix

This section is a workaround, and workarounds that are not linked to their fix
become permanent. The fix belongs upstream:
[UPSTREAM-LEDGER.md](UPSTREAM-LEDGER.md) row **UL-003** proposes that
`bin/setup-github.sh` preserve unknown checks, or read an extra-checks list from
configuration, rather than assuming it is the only writer of that array. When
that row reaches a terminal verdict, revisit this section. Until then, treat
"re-add the required check" as a standing step after any `setup-github` run.
