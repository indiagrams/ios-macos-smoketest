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
