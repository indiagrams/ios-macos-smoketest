# Upstream learning ledger

The record of what this fork learned by shipping for real, what happened to each
learning, and — for the ones that will never go upstream — why not.

## Why this exists

This fork exists to walk the shipping path and find out where the template hurts. Every
generic shipping learning is proposed upstream to
[apple-shipkit](https://github.com/indiagrams/apple-shipkit) **when it is hit**, not
batched into a cleanup pass at the end of the project. Batching is how ledgers die: a row
written three phases after the fact is a reconstruction, not a record.

Every learning gets a row — **including the ones that will never go upstream**. A
learning that fails the [SCOPE.md](../SCOPE.md) test, or that is a fork concretion rather
than a generic capability, is still recorded, with the reason it was ruled out. That is
what makes the scope gate auditable instead of a matter of memory, and it is what makes
this project's close-out a mechanical check rather than an archaeology project.

**A row is added in the same change as the learning that produced it.** That rule, plus
the rule that documentation is updated in the same change, are standing exit criteria on
*every* phase of this project — not just the phase that created this file.

How a learning gets from here to upstream is [CONTRIBUTING-UPSTREAM.md](CONTRIBUTING-UPSTREAM.md).
Short version: there is no fork relationship and no cross-repo PR, so it travels by
`git format-patch` into a separate clone of apple-shipkit.

## Verdict vocabulary

Six values, closed set. Three are terminal. Adapted from the Yocto Project's
`Upstream-Status:` patch tag, which exists to answer exactly the question D-19 asks:
*why was this deliberately not sent upstream?*

- `Pending` — identified, not yet proposed. **Non-terminal.**
- `Submitted [#N]` — PR open upstream. **Non-terminal.** The PR number is required.
- `Merged [#N]` — landed in apple-shipkit. **Terminal.** The PR number is required.
- `Denied [reason]` — proposed, upstream declined. **Terminal.** Reason required in brackets.
- `Out-of-scope [reason]` — fails the SCOPE.md test. **Terminal.** Reason required in brackets.
- `Fork-only [reason]` — passes the SCOPE.md test but is a fork concretion; upstream gets
  the slot, never the value. **Terminal.** Reason required in brackets.

Do not invent a seventh value. A vocabulary that grows mid-project stops being greppable,
which is the only property this column has.

## Close-out contract

Closing this project out is defined as: **no row is left non-terminal.** That is one
command, not a review meeting:

```bash
grep -cE '^\| UL-[0-9]{3} \|.*\| (Pending|Submitted)' docs/UPSTREAM-LEDGER.md
```

It must read `0` at close-out. If it does not, every remaining non-terminal row must be
listed explicitly with the reason it is still open — an accepted, stated exception, never
a silent one.

## Row conventions

- **IDs are `UL-NNN`, monotonically increasing, and never reused.** A retired or mistaken
  row keeps its ID and gets a terminal verdict explaining what happened. Stable IDs mean a
  row can be cited from a commit message or an upstream PR body and still resolve later.
- **`SCOPE test`** holds the literal answer to SCOPE.md's question — `No - in scope` or
  `Yes - out of scope`. Cite the test's sentence, not its path literal; the path moves
  across template versions.
- **`PR`** is an em dash until a PR exists.
- **No fork concretion in any cell** — no Team ID, no contact address, no secrets. Values
  that belong to this fork live in this fork's own docs and are referenced from here.

## Hazard: this file can be deleted wholesale

`bin/refork-smoketest.sh` runs `gh repo delete` followed by `gh repo create --template`.
Running it **destroys this repository and recreates it from the template**, taking this
ledger with it — along with every other fork-owned file this project produced. Nothing in
this file survives that, because remotes, untracked state, and fork-owned docs alike are
all recreated from the template rather than preserved.

This is recorded as a risk, not fixed here; fixing it is outside this phase's scope. Two
consequences worth carrying forward:

- It is the real argument for upstreaming promptly. A fork-side tool that has been
  upstreamed survives a refork. One that has not, does not.
- "This ledger's content has been upstreamed or archived" is a close-out item, not an
  afterthought.

## Ledger

| ID | Date | Phase | Learning | SCOPE test | Verdict | PR | Notes |
|----|------|-------|----------|------------|---------|----|-------|
| UL-001 | 2026-08-31 | 1 | Review-notes generator plus its drift gate — `tools/gen-review-notes.rb`, `test/gen_review_notes_test.rb`, `.github/workflows/review-notes.yml` | No - in scope | Pending | — | D-14. Tooling around the project, not app code. Upstream shape: rename to `bin/gen-review-notes.rb`, add a `ci/check-review-notes.sh` wrapper matching the existing `ci/check-app-icon.sh` convention, and add a job to upstream's `pr.yml`. |
| UL-002 | 2026-08-31 | 1 | An upstream-learning-ledger template — this file's structure, vocabulary, and close-out contract | No - in scope | Pending | — | D-20. Upstream gets the structure; this fork's entries stay here. The schema is a generic capability, the rows are fork concretions. |
| UL-003 | 2026-08-31 | 1 | `bin/setup-github.sh` recomputes and PUTs the required-status-checks array from scratch, silently destroying any fork-added required check on the next run | No - in scope | Pending | — | It should preserve unknown checks, or read an extra-checks list from config, rather than assuming it is the only writer. Affects Phase 4's IDENT-11 gate as much as this phase's drift check. |
| UL-004 | 2026-08-31 | 1 | `SCOPE.md`'s governing test hardcodes an app directory path that moves across template versions — `app/SmokeApp/` here, `app/HelloApp/` upstream — so the quoted test goes stale while the test itself has not changed | No - in scope | Pending | — | Would be durable phrased against "the app target". Interacts with DOC-03 in Phase 5. |
| UL-005 | 2026-08-31 | 1 | `AGENTS.md` documents a `git merge upstream/main` sync path that cannot work for a repository materialised by `gh repo create --template`, and its opening line links the words apple-shipkit to the smoketest URL | No - in scope | Pending | — | Corrected fork-side in Phase 1; upstream needs the same correction to its own copy. Interacts with DOC-03. |
| UL-006 | 2026-08-31 | 1 | The Shipkit Pipes product identity — App Store display name and both platform bundle IDs | No - in scope | Fork-only [fork concretion; upstream gets the slot, never the value] | — | Recorded in `docs/PRODUCT-IDENTITY.md`. Upstream keeps its placeholders. This row exists to demonstrate the Fork-only verdict: the learning passes the SCOPE test, and is still deliberately not upstreamed. |
