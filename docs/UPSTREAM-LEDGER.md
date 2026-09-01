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

Rows UL-007 through UL-011 were added in the phase close-out rather than in the change that produced each learning, which is late by this project's own rule ([CONTRIBUTING-UPSTREAM.md](CONTRIBUTING-UPSTREAM.md) section 5). Each of them says so in its Notes cell and names the commit that carried the learning, rather than being back-dated to look timely. A late row that admits it is late is still a record; a back-dated one is not. From Phase 2 on, the row goes in the same change.

| ID | Date | Phase | Learning | SCOPE test | Verdict | PR | Notes |
|----|------|-------|----------|------------|---------|----|-------|
| UL-001 | 2026-08-31 | 1 | Review-notes generator plus its drift gate — `tools/gen-review-notes.rb`, `test/gen_review_notes_test.rb`, `test/docs_structure_test.rb`, `.github/workflows/review-notes.yml` | No - in scope | Pending | — | D-14. Tooling around the project, not app code. All four files now exist and the workflow's job name, `review notes`, is a required status check on `main`. The generator is dependency-free — zero `require` statements — so the upstream port needs no Gemfile change. Upstream shape: rename to `bin/gen-review-notes.rb`, add a `ci/check-review-notes.sh` wrapper matching the existing `ci/check-app-icon.sh` convention, and add a job to upstream's `pr.yml`. |
| UL-002 | 2026-08-31 | 1 | An upstream-learning-ledger template — this file's structure, vocabulary, and close-out contract | No - in scope | Pending | — | D-20. Upstream gets the structure; this fork's entries stay here. The schema is a generic capability, the rows are fork concretions. |
| UL-003 | 2026-08-31 | 1 | `bin/setup-github.sh` recomputes and PUTs the required-status-checks array from scratch, silently destroying any fork-added required check on the next run | No - in scope | Pending | — | It should preserve unknown checks, or read an extra-checks list from config, rather than assuming it is the only writer. Affects Phase 4's IDENT-11 gate as much as this phase's drift check. Now load-bearing rather than theoretical: 01-06 made `review notes` the ninth required check, so any `make setup-github` run silently returns protection to eight and the gate stops gating while still reporting. Recovery runbook, verified idempotent, is `CONTRIBUTING-UPSTREAM.md` section 6; verify by context count, not by looking at the Actions tab. |
| UL-004 | 2026-08-31 | 1 | `SCOPE.md`'s governing test hardcodes an app directory path that moves across template versions — `app/SmokeApp/` here, `app/HelloApp/` upstream — so the quoted test goes stale while the test itself has not changed | No - in scope | Pending | — | Would be durable phrased against "the app target". Interacts with DOC-03 in Phase 5. |
| UL-005 | 2026-08-31 | 1 | `AGENTS.md` documents a `git merge upstream/main` sync path that cannot work for a repository materialised by `gh repo create --template`, and its opening line links the words apple-shipkit to the smoketest URL | No - in scope | Pending | — | **The fork-side correction landed in this phase**, commit `c56bde9`: the opening paragraph now states the `gh repo create --template` relationship, and the sync section is a prohibition table with consequences plus the four fetch-and-compare uses of the remote. **Upstream still needs the same fix to its own copy** — upstream repaired the link but not the merge path, and a template that tells every forker to merge `upstream/main` is wrong for every template-materialised repo, not just this one. Interacts with DOC-03. |
| UL-006 | 2026-08-31 | 1 | The Shipkit Pipes product identity — App Store display name and both platform bundle IDs | No - in scope | Fork-only [fork concretion; upstream gets the slot, never the value] | — | Recorded in `docs/PRODUCT-IDENTITY.md`, which 01-04 created — the link was dangling when this row was written and now resolves. Upstream keeps its placeholders. This row exists to demonstrate the Fork-only verdict: the learning passes the SCOPE test, and is still deliberately not upstreamed. |
| UL-007 | 2026-08-31 | 1 | The template ships a single `fastlane/metadata/` tree while documenting dual-platform support, and one `review_information/` directory cannot hold two app records' metadata | No - in scope | Pending | — | Surfaced in 01-05, when the generated `id=macos` notes block turned out to have nowhere to be written. Blocks a per-platform notes generator, so splitting the tree is a prerequisite inside Phase 8 rather than optional cleanup; the generator already takes `--id` and `--dest`, only the directories are missing. **Late row** — the learning landed in commit `ac851da` and this row in the phase close-out. |
| UL-008 | 2026-08-31 | 1 | `read_review_field` resolves `ENV[APP_REVIEW_NOTES]` ahead of `notes.txt`, and `.bootstrap.env.example` actively recommends setting that variable — so the recommended path silently defeats any generated review-notes file | No - in scope | Pending | — | D-25. Upstream could invert the precedence, or warn at the recommendation that the variable overrides the tracked file that CI checks. Worked around fork-side by making `tools/gen-review-notes.rb --check` assert the variable is unset in both the process environment and `.bootstrap.env`, rather than merely diffing two files: a file-only comparison goes green while Apple receives text nobody reviewed. **Late row** — the learning landed in commit `ee3a86f` and this row in the phase close-out. |
| UL-009 | 2026-08-31 | 1 | GitHub replaces the entire `checks` array when `required_status_checks` is PATCHed with one, so the obvious command for adding a required check destroys every check already there | No - in scope | Pending | — | Caught in 01-06 before it ran; the shape as planned would have left `main` protected by a single context. The safe form reads the live array, appends the new entry, and PATCHes the result — additive by construction and idempotent. Distinct from UL-003: that row is `bin/setup-github.sh` dropping a fork-added check, this one is the naive repair doing worse damage in the other direction. Runbook in `CONTRIBUTING-UPSTREAM.md` section 6, including why the parent `/protection` object must never be PUT. **Late row** — the learning landed in commit `7286037` and this row in the phase close-out. |
| UL-010 | 2026-08-31 | 1 | A grep-based gate run over a repository that documents its own literals matches the prose explaining the gate; three separate near-misses in this phase alone | No - in scope | Pending | — | Occurrences: this file's close-out grep would have matched its own verdict vocabulary had that vocabulary been formatted as a table (01-03); a workflow comment naming the trigger it forbids defeated a grep for that trigger (01-06); and a note explaining a banned phrase would have tripped the ban on it (01-06). Upstream carries the same shape in `bin/verify-rename.sh`, which greps five literals repo-wide and maintains a hand-written seven-path exclusion list that has to grow every time a doc discusses one. Generic fix: extract the specific section or table, or strip comment regions, instead of growing an allowlist. **Late row** — the learnings landed in commits `48ee116`, `c31a7a7` and `2ca986e`, and this row in the phase close-out. |
| UL-011 | 2026-08-31 | 1 | A competitive-scan verdict was recorded from a store search result's name alone, and the wrong verdict stopped the phase before the listing was read | No - in scope | Fork-only [product-research learning about this fork's own App Review argument; the template has no slot for it] | — | 01-02 recorded `CyberChef Pro` as a CyberChef derivative on presence alone and escalated a blocker against D-24; commit `db936de` corrected both assumption verdicts to NO after the App Store listing showed an unrelated cooking app. The original error is preserved in `docs/REVIEW-ARGUMENTS.md`'s audit trail rather than rewritten away, because it is exactly the reasoning failure that document exists to guard against. Recorded here because D-19 requires a row for every learning, including the ones that will never go upstream. |
| UL-012 | 2026-08-31 | 1 | A tool that reads project files without pinning an encoding dies with a stack trace instead of a verdict whenever the locale is unset | No - in scope | Pending | — | `tools/gen-review-notes.rb` read `docs/REVIEW-ARGUMENTS.md`, `notes.txt`, and `.bootstrap.env` with `File.read`/`File.foreach`, inheriting `Encoding.default_external`. With `LANG` unset - cron, launchd, a bare container, `env -i` - that is US-ASCII, and any non-ASCII byte raises `ArgumentError` from `String#match?` (line 211) or `Encoding::CompatibilityError` from `String#rstrip` (line 132). Reachable input, not exotic: an App Review contact with a diacritic, or a curly apostrophe anywhere in the notes prose. CI never caught it because `.bootstrap.env` is gitignored and absent there, so the guard short-circuits. A drift gate that crashes cannot be distinguished by its caller from one that passed. Fixed fork-side by pinning UTF-8 at every read and write site plus a regression test that clears `LC_ALL`/`LANG`/`LC_CTYPE`; upstream needs the same once the generator lands there. |
| UL-013 | 2026-09-01 | 2 | `register_app_id` hardcodes `BundleIdPlatform::IOS`, and the comment above it defers macOS registration to a `match` code path that v1.6 deleted, so the lane cannot register a macOS bundle ID at all and nothing says so | No - in scope | Merged [#279] | [#279](https://github.com/indiagrams/apple-shipkit/pull/279) | D-33. The defect has four surfaces, and changing only the hardcoded constant would have left three of them teaching the wrong model: the comment deferred to match's per-platform profile path, which v1.6 removed along with match-based CI signing (apple-shipkit#158); it cited fastlane 2.230 against a 2.238.0 lockfile; and the success line interpolated a literal iOS platform regardless of what was sent, so the log would have become the next stale comment. The lane now takes a `platform:` option (`ios` default, `macos`), validated before authenticating so a typo costs no round trip. `BundleIdPlatform` exposes exactly `IOS` and `MAC_OS` - re-read 2026-09-01 in the locked 2.238.0 gem at `spaceship/lib/spaceship/connect_api.rb:126-130` - so `UNIVERSAL` is unreachable through spaceship even though Apple's own API defines it, and `BundleIdCreateRequest` requires the field, so a value must always be supplied. Delivered by `git format-patch` into a separate clone per D-34; nothing was pushed from this repository and the `upstream` remote's push URL is still the literal `no-push`. `docs/BOOTSTRAP.md`'s claim that the lane is idempotent because `BundleId.create` rescues `ALREADY_EXISTS` was corrected in the same pull request - no code does that, and the `BundleId.all(filter:)` lookup preceding it is what actually makes a re-run safe. Merged upstream 2026-09-01 as `4dbdaa8` with all eight required contexts green (`enforce_admins` is on, so none were bypassed); the verdict moved to its terminal form in the change that observed the merge rather than at close-out. D-35 gated every bundle ID registration in this phase on this row reaching a terminal verdict, and that gate is now open. |
| UL-014 | 2026-09-01 | 2 | The template documents `fastlane match` with a separate certs repo, where v1.6 replaced it with per-run mint-and-revoke, so a forker following the documented model supplies a `GH_CERTS_REPO` that no longer drives anything | No - in scope | Pending | — | C-01. `fastlane/Fastfile` records that match-based CI signing was dropped in v1.6 (apple-shipkit#158) because match needed a separate certs repo, two extra secrets, and broke for legacy WWDR-G3-issued certificates on macos-15-arm64; `.github/workflows/release.yml` states outright that there is no certs repo dependency. The configuration surface did not follow the code: `.bootstrap.env.example` and `bin/init-bootstrap-env.sh` still prompt for `GH_CERTS_REPO` and `MATCH_PASSWORD_FILE`, and `bin/refork-smoketest.sh` still reads them. That is the worst shape a dead config key can take - a forker supplies a value, nothing raises, and nothing happens - and it is how this project's own planning notes came to carry a signing model the code had already abandoned. Found by reading the signing path while preparing UL-013 rather than by being bitten, so it is recorded before it costs anyone a session. Upstream shape: either remove the dead keys, or annotate them at the point of prompting with the version that stopped reading them. |
