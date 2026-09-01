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
| CyberChef, or any derivative or port | Searched on both stores | ~300 operations chained as "recipes" in the web original | **UNVERIFIED — a derivative WAS found; see the `CyberChef Pro` row** | The desk assumption that no CyberChef derivative ships natively is wrong: `CyberChef Pro` was found on the App Store on 2026-08-31 | 2026-08-31 |
| CyberChef Pro | App Store | Not established — see evidence | **UNVERIFIED — could not exercise** | Found on the App Store during the 2026-08-31 sweep. Reached and opened, but could not be exercised: its in-app search did not work and no recipes were available to test, so whether it implements CyberChef's recipe/chaining model is **unknown**. Not scanned in the sense this table means by "scanned" — the app was reached, not exercised | 2026-08-31 (found, not exercised) |

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

- `A3 — CyberChef or a derivative ships on the App Store: YES` — `CyberChef Pro`
  was found on the App Store on 2026-08-31. Its functionality could **not** be
  verified: in-app search was non-functional and no recipes were available to
  test, so whether it genuinely implements the recipe/chaining model is unknown.
  The desk-research assumption that no CyberChef derivative ships natively is
  nonetheless falsified — the app is on the shelf.
- `A4 — an incumbent developer toolkit chains one tool's output into another: UNRESOLVED` — **NO for every app actually exercised, UNRESOLVED overall.**
  Cleared by the sweep: `DevUtils: Dev Toolkit`, `DevUtils.app`, `Developer Tools - Tooly`,
  `Hex: Dev Tools`, and `DevToys`. Each was opened and none offered a pipeline,
  recipe, chain, or "send output to…" affordance. Not cleared: `CyberChef Pro`,
  which could not be exercised at all. Chaining is CyberChef's defining model,
  so the one app most likely to falsify A4 is precisely the one that could not
  be tested. A4 is therefore recorded as UNRESOLVED and **not** as NO; rounding
  it to NO would assert something the scan did not establish.

**A `YES` on either verdict falsifies the sole defensible 4.3(b) claim — that no
native App Store app makes the chain the primary work surface — and the phase
stops there.** No argument gets written on top of a falsified premise. This
app's v1 tool set (encode/decode, hashing, timestamps) is a strict *subset* of
what the free incumbents already ship, so tool count cannot be substituted as
the differentiator; a `YES` means the concept needs rethinking, not rewording.
That is why this scan runs before any argument text is written, and why the
checkpoint gating it is blocking rather than end-of-phase.

**A3 came back `YES`. That clause has fired.** See
[Assumption falsified — escalation required](#assumption-falsified--escalation-required)
at the end of this section for what it means and what stops.

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

### Assumption falsified — escalation required

**A3 is `YES`, and A4 is `UNRESOLVED` rather than `NO`. D-24's sole defensible
4.3(b) claim — *no native App Store app makes the chain the primary work
surface* — is therefore not established.** It has not been disproved either.
It is simply unsupported, and an unsupported claim is not one to put in front
of App Review.

The reasoning, stated plainly:

- A CyberChef derivative, `CyberChef Pro`, **is** on the App Store. The desk
  research assumed none was, and that assumption is wrong.
- The chained recipe is CyberChef's defining model. An app carrying that name
  is the single most likely thing on the shelf to make the chain its primary
  work surface.
- That app could not be exercised on 2026-08-31 — its in-app search was
  non-functional and no recipes were available to test — so nobody has looked
  at what it actually does.
- Every other app on the worksheet was opened and none chained. The claim is
  therefore intact against the incumbent toolkits and open against the one app
  that matters most to it.

**Consequence.** `01-05-PLAN.md` must **not** write the 4.3(b) differentiation
argument on this premise. Doing so would put a claim in front of Apple that
this repo's own evidence does not carry, in the exact place — a 4.3(b)
response — where being caught overstating is most expensive. The phase stops
here by the owner's decision rather than proceeding on a premise that has been
weakened but not resolved.

**The open question that settles it.** Does `CyberChef Pro` present a stacking
recipe / steps / pipeline pane, distinct from its input and its output, that a
user builds up and reorders?

- **If yes** — D-24's claim collapses outright. The chain is already the
  primary work surface of a native App Store app, and the differentiator has to
  be found somewhere else or the concept reconsidered.
- **If no** — the app borrowed the name without the model, A4 returns to `NO`,
  and D-24's claim is restored on evidence.

Answering it requires exercising the app, which the 2026-08-31 sweep could not
do. That is the next action, and it is a scan action, not a writing action.

**A possible alternative path, recorded and explicitly not adopted.** Guideline
4.3(b) asks for a "meaningfully different **or improved** experience" — the
disjunction is the guideline's own. If `CyberChef Pro` turns out to be a native
port that is broken in practice, an argument from improved execution rather
than from a different model may be available. That is a **different argument**
with a different evidence burden, and adopting it is a product decision
requiring replanning, not something this scan or this file may decide. It is
written down here only so the option is not lost. **It is not adopted.**

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
