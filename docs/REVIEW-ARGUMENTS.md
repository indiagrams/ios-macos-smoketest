# Review arguments

## Why this exists

This file is the **source of truth for the text App Review receives**. It holds
the reasoning behind the App Store submission arguments in full, and it holds —
in a clearly delimited block — the exact prose that reaches Apple.
`fastlane/metadata/review_information/notes.txt` is *generated* from that block
by `tools/gen-review-notes.rb`, and CI fails if the two drift. Hand-editing
`notes.txt` will therefore fail CI: edit this file and regenerate instead.

The point of the generator is not convenience. It is a guarantee that the
argument Apple reads is the argument that was actually reasoned about, rather
than a paraphrase somebody retyped into a metadata file at submit time.

> [!WARNING]
> **Leave `APP_REVIEW_NOTES` empty in `.bootstrap.env`.** `fastlane/Fastfile`'s
> `read_review_field` resolves the environment variable *ahead of*
> `notes.txt`. If that variable is set, `deliver` sends its value and silently
> ignores the generated file — meaning Apple receives text that nobody in this
> repo reviewed, while every drift check here still passes. `.bootstrap.env.example`
> actively recommends setting it; do not. The drift check asserts the variable is
> unset, not merely that the two files match.

The product name and both bundle IDs are recorded in `docs/PRODUCT-IDENTITY.md`;
that file, not this one, is the durable record of identity.

## Competitive scan (run 2026-08-31)

This scan exists because the differentiation claim this file will make is
checkable only against the actual App Store shelf. App Store search results are
region-, device-, and account-specific and cannot be reproduced from a build
machine, so desk research against vendor sites and listing pages is a starting
inventory, not evidence. A listing that does not advertise a feature is not
proof the feature is absent — the app has to be opened.

The table below was pre-filled from desk research assembled 2026-08-30 and
then filled in from an on-device sweep of both stores run by the repo owner on
**2026-08-31**, using the four search terms in the protocol below. Chaining
cells reflect what was observed on a device; the one row that could not be
exercised still says so.

| App | Store | Tool families | Chains tool output into another tool? | Evidence (what you saw) | Scanned |
|---|---|---|---|---|---|
| DevUtils: Dev Toolkit (`id6759389631`) | iOS App Store — iPhone, iPad, Mac; free | "37+ tools", offline-first | No | Opened during the 2026-08-31 sweep; no pipeline, recipe, chain, workflow, or "send output to…" affordance found — each tool takes its own input and returns its own output | 2026-08-31 |
| DevUtils.app (`id1533756032`, different seller) | Mac App Store | ~47 tools: JSON/HTML/SQL format, YAML↔JSON, Unix time, JWT, MD5/SHA-1/SHA-256/SHA-512, Base64, URL, HTML entity | No | Opened during the 2026-08-31 sweep; no pipeline, recipe, chain, workflow, or "send output to…" affordance found — each tool takes its own input and returns its own output | 2026-08-31 |
| Developer Tools - Tooly (`id6639614589`) | iOS + macOS | Base64, JSON↔XML, string case, Unix time; tools also exposed as Shortcuts actions | No | Opened during the 2026-08-31 sweep; no pipeline, recipe, chain, workflow, or "send output to…" affordance found — each tool takes its own input and returns its own output. Shortcuts-based chaining is out-of-app and unchanged by this scan | 2026-08-31 |
| Hex: Dev Tools (`id6760552804`) | iOS App Store | Base64, MD5/SHA-1/SHA-256/SHA-512, clipboard auto-detect | No | Opened during the 2026-08-31 sweep; no pipeline, recipe, chain, workflow, or "send output to…" affordance found — each tool takes its own input and returns its own output | 2026-08-31 |
| DevToys (macOS) | Mac App Store | Converters, encoders/decoders, formatters | No | Opened during the 2026-08-31 sweep; no pipeline, recipe, chain, workflow, or "send output to…" affordance found — each tool takes its own input and returns its own output | 2026-08-31 |
| CyberChef, or any derivative or port | Searched on both stores | ~300 operations chained as "recipes" in the web original | No | No CyberChef derivative or port found on either store. One name match surfaced — `CyberChef Pro` — and was checked and ruled out; see the row below | 2026-08-31 |
| CyberChef Pro (`id6743856931`) | iOS App Store — iPhone only; free + $9.99 IAP | **Not a CyberChef derivative.** A cooking app | No — not applicable | **Name collision, ruled out 2026-08-31.** Seller is Far Outpost LP. Its own listing reads: *"Transform your kitchen with CyberChef Pro, your ultimate culinary companion! Powered by neural networks, it crafts diverse, delicious recipes based on the ingredients you have on hand."* The "recipes" are food. This explains why the scanner found its search non-functional and no recipes to test — the app has no data operations to search for. Verified against the live App Store listing | 2026-08-31 |

Rules for filling this table in. A row is only marked `No` if somebody opened
the app and looked; a row nobody reached keeps its `UNVERIFIED` cell and gains
an explicit "not scanned" note in the evidence column. Silently converting an
unchecked row to `No` is the failure mode this table is shaped to prevent.
Unused spare rows are deleted rather than left blank.

Two notes on the fidelity of what is recorded above. First, the five `No` rows
carry a single aggregate observation: the scanner opened the multi-tool
utilities and found no chaining affordance in any of them. No app-by-app UI
detail beyond that was reported, and none has been invented here to make the
cells look fuller than the evidence is. Second, `CyberChef Pro` is deliberately
**not** recorded as `No`. It was found but not exercised, and it is the single
app on this shelf most likely to chain — recording it as `No` would be exactly
the failure mode the rule above exists to prevent.

### Assumption verdicts

- `A3 — CyberChef or a derivative ships on the App Store: NO` — no CyberChef
  derivative or port was found on either store. One name match surfaced,
  `CyberChef Pro` (`id6743856931`), and was ruled out on inspection: it is an
  unrelated iPhone-only cooking app by Far Outpost LP whose "recipes" are food.
  **Audit trail:** this verdict was first recorded as `YES` on the strength of
  the name alone, before the listing was read, and corrected the same day once
  it was. The correction is kept visible rather than rewritten away, because the
  original error — inferring a product from its name — is exactly the kind of
  reasoning this document exists to guard against.
- `A4 — an incumbent developer toolkit chains one tool's output into another: NO` —
  cleared by the sweep: `DevUtils: Dev Toolkit`, `DevUtils.app`,
  `Developer Tools - Tooly`, `Hex: Dev Tools`, and `DevToys`. Each was opened and
  none offered a pipeline, recipe, chain, or "send output to…" affordance. The
  one app that could not be exercised, `CyberChef Pro`, is not a developer tool
  at all and is therefore not a counter-example. No app remains unaccounted for.
  Note that `Developer Tools - Tooly` exposes its tools as Shortcuts actions —
  that chaining lives in Apple's Shortcuts app, not in-app, and is a hostile-read
  objection the argument must answer rather than a falsification of A4.

**A `YES` on either verdict falsifies the sole defensible 4.3(b) claim — that no
native App Store app makes the chain the primary work surface — and the phase
stops there.** No argument gets written on top of a falsified premise. This
app's v1 tool set (encode/decode, hashing, timestamps) is a strict *subset* of
what the free incumbents already ship, so tool count cannot be substituted as
the differentiator; a `YES` means the concept needs rethinking, not rewording.
That is why this scan runs before any argument text is written, and why the
checkpoint gating it is blocking rather than end-of-phase.

**Both verdicts came back `NO`. The clause did not fire.** The claim that no
native App Store app makes the chain the primary work surface is supported by
this scan, dated 2026-08-31. It is supported, not proven — App Store search is
region-, device-, and account-specific, and absence of evidence across four
search terms is weaker than a census. Re-run before submission if the gap is
long.

### Scan protocol

Run on a real device signed into a real App Store account — an iPhone or iPad
for the iOS App Store, and a Mac for the Mac App Store. Do both stores.

1. Search each of these four terms, in each store: `base64`, `hash`,
   `developer tools`, `unix timestamp`.
2. For each search, record roughly the top ten results — app name, seller,
   price — together with the date the search was run.
3. Open every result that looks like a multi-tool developer utility. Do not
   trust the listing copy. Look specifically for a **pipeline, recipe, chain,
   workflow, or "send output to…" affordance**: a way for one tool's output to
   become another tool's input inside the app. Screenshots and the in-app UI
   are the evidence; marketing text is not.
4. Search both stores for `cyberchef`, and for `recipe` alongside `encode` and
   `decode`, to settle whether a CyberChef-equivalent ships natively.
5. Record the date the scan was actually run in the section heading above. It
   is the scan date that matters, not the date the desk inventory was compiled.

### Assumption resolved — claim supported

**Both A3 and A4 came back `NO`. D-24's claim — *no native App Store app makes
the chain the primary work surface* — is supported by the 2026-08-31 scan.**
`01-05` may write the 4.3(b) differentiation argument on this premise.

How it resolved, kept in full because the path matters more than the answer:

- The scan cleared five incumbent developer toolkits. Each was opened; none
  offered a pipeline, recipe, chain, or "send output to…" affordance.
- One app could not be exercised — `CyberChef Pro` — and on the name alone it
  looked like the single most likely thing on the shelf to falsify the claim.
  A3 was recorded `YES` and the phase was stopped.
- Reading the actual listing settled it: `CyberChef Pro` (`id6743856931`,
  Far Outpost LP, iPhone-only, free + $9.99 IAP) is a **cooking app**. Its
  description begins *"Transform your kitchen with CyberChef Pro, your ultimate
  culinary companion!"* and its "recipes" are food. It shares a name with
  GCHQ's CyberChef and nothing else.
- That also explains the scan obstacle rather than leaving it as an anomaly:
  the in-app search returned nothing useful and no recipes were available to
  test **because there are no data operations in a recipe app**.

**The error worth remembering.** A3 was set to `YES` from the name before the
listing was read — a product inferred from its title. The scanner reported the
obstacle honestly instead of rounding an untested app to `NO`, which is what
made the mistake findable. Both halves of that are the process working.

**What is still true.** `Developer Tools - Tooly` exposes its tools as Shortcuts
actions. That chaining is real but lives in Apple's Shortcuts app, not in-app.
It does not falsify A4, and the 4.3(b) argument must answer it directly rather
than ignore it — a reviewer who knows Shortcuts will raise it.

**Strength of the claim.** Supported, not proven. Four search terms across two
stores is not a census, and App Store results are region-, device-, and
account-specific. The argument should be phrased to survive a reviewer knowing
of an app this scan missed.

**Shelf life.** All of the above is a 2026-08-31 observation of a store that
changes weekly. Whatever is decided must be re-verified before the review notes
are finalised in Phase 8.

---

<!--
  This file is intentionally incomplete. This plan writes only the top matter
  and the competitive scan. Still to be appended, by a later plan in this phase:
  the 4.2 lasting-utility argument, the 4.3(b) differentiation argument, the
  macOS 2.4.5 addendum, the hostile-read pre-mortem, the pre-drafted Resolution
  Center reply, and the delimited verbatim block that the notes generator reads.
  Do not treat the absence of those sections as a bug.
-->
