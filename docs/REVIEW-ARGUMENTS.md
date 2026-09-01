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

## Guideline 4.2 — lasting utility

> Your app should include features, content, and UI that elevate it beyond a repackaged website. If your app is not particularly useful, unique, or 'app-like,' it doesn't belong on the App Store. If your App doesn't provide some sort of lasting entertainment value or adequate utility, it may not be accepted.

*Apple, App Store Review Guidelines, section 4.2 Minimum Functionality. Fetched
verbatim from `developer.apple.com/app-store/review/guidelines/` on 2026-08-30.
That page carries no amendment or last-updated date of any kind, so none is
cited here; the fetch date is the only honest provenance available for it, and
inventing a version number for a living page would be worse than having none.*

Three things follow, and each of them is checkable against the shipped build
rather than asserted.

**There is nothing here to repackage.** Shipkit Pipes performs every operation
on-device. It has no network capability and no networking entitlement on either
platform — the macOS build is sandboxed without `com.apple.security.network.client`
and the iOS build makes no outbound request — so there is no website behind it
that a reviewer could find the app to be a wrapper around. The absence is
structural rather than a policy: with no network code path, an offline device
and an online one behave identically.

**It is not a single-view utility.** The app presents five distinct surfaces,
each recorded with its tool set in `docs/PRODUCT-IDENTITY.md`: **Encode/decode**
(Base64, URL percent-encoding, HTML entities), **Hashing** (MD5, SHA-1, SHA-256,
SHA-512), **Timestamps** (Unix epoch to ISO 8601 and to local time and back,
with a timezone picker), the **Pipeline canvas**, and **History**. The pipeline
canvas is the primary work surface, not an advanced mode reached from a menu.

**The utility is recurring, not novelty.** Decoding a Base64 payload, checking a
digest against one somebody else published, and reading a Unix timestamp out of
a log line are daily work for the audience this is built for, not a thing done
once and then uninstalled. The pipeline surface is what makes that work
accumulate instead of repeat: a multi-step conversion is assembled once, its
intermediate values stay visible, and steps can be removed and reordered rather
than the whole sequence being retyped through single-purpose screens.

## Guideline 4.3(b) — differentiation

> Don't submit apps that are indistinguishable from what's already widely available. Opportunistically creating variants of existing app categories or popular apps degrades App Store discovery, reduces overall app quality, and harms both users and developers. Certain kinds of apps, such as dating, flashlight, sound effects, wallpaper, simple timers, and fortune telling, are well established on the App Store and we will not accept new submissions unless they offer a meaningfully different or improved experience. We may remove these apps from the App Store going forward if they are not updated, improved, or do not attract customers.

*Apple, App Store Review Guidelines, section 4.3(b) Spam. Fetched verbatim from
`developer.apple.com/app-store/review/guidelines/` on 2026-08-30. As above, the
page carries no amendment or last-updated date and none is cited.*

### The asymmetry that matters

The refusal list in that text is complete as quoted. It names dating, flashlight,
sound effects, wallpaper, simple timers, and fortune telling — six categories,
and no others. It does **not** name converters, encoders, decoders, or hashing
tools. That distinction is load-bearing for this project's history: an earlier
concept for this fork was a focus timer, and "simple timers" is on that list by
name, which is a categorical bar rather than a judgement.

The exposure that remains is the general clause — "indistinguishable from what's
already widely available" — which is a judgement-based hook, applied per
submission by a reviewer, rather than a category the guideline has closed in
advance. That lowers the risk. It does not eliminate it, and nothing below
should be read as though it did: a judgement call can go against a submission
that has a good answer, and the pre-mortem further down assumes exactly that.

### The claim, stated once and narrowly

**The encode, hash, and timestamp tools already exist on both stores. The
chained pipeline — where one tool's output becomes the next tool's input, with
every intermediate step visible, removable, and reorderable — does not, and in
Shipkit Pipes it is the primary work surface rather than a secondary feature.**

Every clause in that sentence is checkable rather than rhetorical. "Already
exist" is the incumbents named in the scan below. "Output becomes the next
tool's input" is a thing a reviewer can do in the app in under a minute, using
the numbered walkthrough in the review notes. "Visible, removable, reorderable"
describes the pipeline canvas as built. "Primary work surface" is what D-08
decided and what D-09 implements: opening a tool screen yields a one-step
pipeline that extends in place, so there is no separate mode a reviewer has to
discover.

Nothing broader than that sentence is claimed anywhere in this repository, and
the drift is worth guarding against actively, because every broader version of
it is easier to write and none of them is defensible.

### The concession, stated in our own voice

**Shipkit Pipes ships strictly fewer tools than the free incumbent toolkits, and
tool count is not the claim.** A free 37-tool offline developer toolkit already
ships on the iOS App Store and a roughly 47-tool one on the Mac App Store, and
this app's v1 tool set is a strict subset of both. Anyone comparing catalogues
should conclude that the incumbents win that comparison, because they do. The
argument is about how the work surface is organised, not how much the app does —
which is also why pulling additional tool families forward into v1 was
considered during scoping and declined; see `docs/PRODUCT-IDENTITY.md`.

Writing the concession down, rather than leaving it as something everyone
happens to know, is what keeps the narrow framing from quietly widening in a
later phase when somebody writes marketing copy under deadline.

### The evidence

The claim rests on the **Competitive scan (run 2026-08-31)** section above, and
on nothing else. Five incumbent developer toolkits — `DevUtils: Dev Toolkit`,
`DevUtils.app`, `Developer Tools - Tooly`, `Hex: Dev Tools`, and `DevToys` —
were opened on a device on that date, and none offered a pipeline, recipe,
chain, workflow, or "send output to…" affordance. No CyberChef derivative or
port was found on either store.

The scan states its own limits and they carry into the claim: four search terms
across two stores is not a census, and App Store results are region-, device-,
and account-specific. The claim is therefore *supported* by a dated
observation, not proven, and it should be re-run before submission if the gap
is long. It is written to survive a reviewer who knows of an app the scan
missed — a counter-example would narrow the claim, and the honest response
would be to narrow it rather than to defend the wider version.

## macOS addendum — guideline 2.4.5

The 4.2 and 4.3(b) arguments above do not change by platform (D-15). The app,
the tools, and the pipeline are the same on both. What differs is that macOS
review additionally judges Mac-nativeness under guideline 2.4.5, and an app
that reads as a ported iOS build is a known rejection theme there, so that
question gets its own short section rather than being assumed to travel with
the shared argument.

**The macOS build is not the iOS layout recompiled.** Per D-11, iOS uses
`TabView` with `NavigationStack`, and macOS uses `NavigationSplitView` with a
sidebar listing the five surfaces. The accepted cost of that decision is
maintaining two navigation layouts instead of one; it was taken on review risk
rather than on preference.

**It is sandboxed, and it is offline.** The macOS target runs in the App
Sandbox with no networking entitlement — the same structural offline property
the 4.2 section describes, expressed in the entitlement file rather than in
prose.

**It embeds nothing that belongs outside the App Store distribution model.**
There is no Sparkle or other non-App-Store update mechanism, no login item, no
launch agent, no privileged helper tool, and no background daemon. The app is
launched by the user and does nothing when it is not running.

**Two later phases verify this rather than assuming it.** Phase 9 installs the
macOS build from TestFlight on a second Mac and checks it launches and behaves
correctly on a machine that never built it. Phase 11 submits macOS after iOS has
been approved, so a macOS-specific 2.4.5 finding cannot take the iOS submission
with it.

*Corrected 2026-09-01 at the Phase 2 close-out.* This paragraph used to say
Phase 11 submits macOS "as its own App Store record — the two records are
independent by D-05". There is one record, not two: D-44 reversed D-05 during
02-07 after Apple refused a second record on the grounds that app names are
unique within an account, and record `6807393045` now carries an `IOS` and a
`MAC_OS` `appStoreVersion` on the shared bundle ID. The **conclusion** survives
the correction — both versions were read back on 2026-09-01 in
`PREPARE_FOR_SUBMISSION`, and each is submitted independently — but it now rests
on independent *versions* rather than independent *records*, which is a different
fact. The paragraph was left stale for four plans because the change that
reversed the decision updated the two documents it touched and not this one.

## Hostile read (pre-mortem, run 2026-08-31)

The method here is Gary Klein's pre-mortem, and it is stated literally rather
than left implicit, because a later reader needs to know why the table reads the
way it does: **it is eight weeks from now. Shipkit Pipes was rejected under
4.3(b). The rejection letter said the app is indistinguishable from what is
already widely available. Why were they right?**

Assuming the failure already happened is the whole mechanism. Asked to list
risks, people list the ones they have answers for; asked to explain a failure
that has already occurred, they produce the reasons that actually bite. What
follows is the output of that question, not a list of counterarguments
brainstormed in the abstract.

Four rules govern the table, and they are what make it worth having written.
Each objection is stated in the reviewer's voice, at its strongest, with no
hedging. Every rebuttal cites a dated checkable fact — the competitive scan by
its date, the quoted guideline text, or a named property of the shipped app —
rather than an assertion. Every row carries a residual risk, and "accepted" is a
legitimate value there. And at least one row is not fully rebutted, because a
pre-mortem in which every objection is answered has been run wrong.

| # | Objection (stated at its strongest) | Force | Rebuttal | Evidence | Residual risk |
|---|---|---|---|---|---|
| H1 | A free 37-tool offline developer toolkit already ships on the iOS App Store, and a roughly 47-tool one on the Mac App Store. You ship three tool families and every one of them is already in those apps. This is a smaller version of something that is on the shelf for free. | High | Conceded on tool count, which is not the claim. The claim is that the chain is the primary work surface: one tool's output becomes the next tool's input in-app, with every intermediate value visible and every step removable and reorderable. The 2026-08-31 scan opened all five incumbent toolkits and found no pipeline, recipe, chain, or "send output to…" affordance in any of them. | Competitive scan run 2026-08-31, five toolkits opened on-device; the concession is stated in the app's own voice in §Guideline 4.3(b). | A reviewer who evaluates on catalogue size rather than on work surface finds for the incumbents, and nothing in the app changes that. Partly mitigated by D-08 putting the pipeline on the first screen and by the numbered walkthrough in the review notes; not eliminated. |
| H2 | iOS and macOS already chain arbitrary tools. Shortcuts does it system-wide, and Developer Tools - Tooly already exposes its own tools as Shortcuts actions, so a user who wants to chain Base64 into SHA-256 can do it today without your app. | High | True, and not disputed. That chaining lives in Apple's Shortcuts app: it has to be built and maintained outside the tool, and it shows no intermediate value while it runs. The claim is about the chain being this app's own primary work surface, which is a different property from being reachable through a system automation layer. The 2026-08-31 scan recorded Tooly's Shortcuts actions explicitly rather than quietly treating them as absent. | Competitive scan run 2026-08-31, the `Developer Tools - Tooly` row and the A4 verdict note, both of which name the Shortcuts route. | Real and only partly answered. A reviewer who uses Shortcuts daily may judge the in-app version an incremental convenience, and the honest reply is that this is a difference of surface rather than of capability. |
| H3 | CyberChef has chained roughly 300 operations as "recipes" for a decade. This is a small reimplementation of a well-known free tool, which is the definition of a variant of something already widely available. | Medium | The prior art is granted; the claim was never that chaining is a new idea, and saying so would be false. The claim is scoped to the native App Store shelf. CyberChef is a web app, and the 2026-08-31 scan searched both stores for it and for any derivative or port and found none. The single name match, `CyberChef Pro`, was opened and ruled out as an unrelated cooking app. | Competitive scan run 2026-08-31, the A3 verdict and the `CyberChef Pro` row with its listing text quoted. | A reviewer can point at the website and ask why this needs an app at all. The answer is the 4.2 one — no network path exists, so a pasted secret cannot leave the device — and that is an argument about the app rather than a fact about the shelf. |
| H4 | "Shipkit" reads as release-engineering scaffolding. Searching the name finds a template repository for shipping apps, not a product, so this looks like a vehicle for exercising a release pipeline rather than an app anyone wants to use. | Low | No rebuttal is offered, deliberately. The framing weakness is real and was recorded as an accepted risk at scoping time rather than argued away. What was done instead is structural: the repository name, the Xcode target name, and the App Store display name are kept as three separate strings, and only the display name reaches review. | D-07, recorded at scoping; `docs/PRODUCT-IDENTITY.md` §"Three separate strings" and its accepted-risk note. | Accepted. This risk is accepted and logged rather than mitigated. If it costs a review cycle, the correct response is a different display name, not a better argument. |
| H5 | Your evidence is four search terms run on a single day, by one person, on one account. App Store results are region-, device-, and account-specific. An app that does exactly this already exists and your scan simply did not surface it. | Medium | Granted as a limit, and stated as one in the scan section itself rather than left for a reviewer to discover. The claim is deliberately written as supported by a dated observation rather than proven, and the scan records its own protocol so the gap is visible. A counter-example would narrow the claim rather than collapse it, and the correct response would be to narrow it. | Competitive scan run 2026-08-31, §"Strength of the claim" and the scan protocol, both of which state the limit before any argument is built on the result. | Not mitigated, and this is the genuinely open row. One counter-example changes the argument. The standing action is to re-run the scan before submission if the gap since 2026-08-31 has grown long. |

Two things about that table are worth stating outright. H1's objection is a hard
fact, not a framing to be managed — the free incumbents really do ship more
tool families, and the row reads that way on purpose. And H5 is the row that
should worry a reader most, precisely because it is the one with no answer: the
whole argument is one undiscovered app away from needing to be rewritten.

## Pre-drafted Resolution Center reply (use only if rejected)

Drafted in advance so it can be edited under time pressure rather than composed
under it. It applies only after a rejection lands: pasted into App Store
Connect's Resolution Center, edited to answer the specific letter received, and
never sent proactively.

Thank you for reviewing Shipkit Pipes, and for the specific note about guideline
4.3(b). I would like to explain how the app differs from other developer
utilities, because the difference is in how the work is organised rather than in
the size of the tool list.

Shipkit Pipes is built around a pipeline. One tool's output becomes the next
tool's input inside the app, every intermediate value stays on screen, and steps
can be reordered or removed without retyping the sequence. That pipeline is the
screen the app opens on, not a feature behind a menu.

It takes about a minute to see. Open the Pipeline tab, enter the text `hello`,
and add a Base64 encode step, which produces `aGVsbG8=`. Add a SHA-256 step
after it and the digest of that intermediate value appears beneath it. Both
steps stay visible, and removing the first one updates the second.

We are aware that other developer utilities on the App Store ship larger tool
catalogues than ours, several of them free, and we are not claiming otherwise.
Everything in our app runs offline, with no network access on either platform.

I would be glad to answer any further questions.

## Why the notes do not contain this argument

Everything above stays in this file. None of it goes into
`fastlane/metadata/review_information/notes.txt`. That is a decision (D-27), not
an oversight, and it is recorded here because the natural instinct on reading a
thin set of review notes next to a long argument is to "improve" the notes by
pasting the argument in.

Three reasons, in descending order of how well evidenced they are.

**Guideline 2.3.1(a) asks for specificity about what the app does, not for a
defence of it.** Its text — *"All new features, functionality, and product
changes must be described with specificity in the Notes for Review section of
App Store Connect (generic descriptions will be rejected) and accessible for
review"* — is about making functionality legible and reachable. A guideline
argument does not make anything more legible or more reachable.

**Apple's own guidance on review notes asks for something else entirely.** It
asks for the app's concept, its features, how to enable them, the audience it
was designed for, and the questions a person using it might have. Guidelines are
not among the things it asks for.

**There is no reliable public evidence that a well-argued note reverses a 4.3(b)
call.** The forum threads asking precisely that question are unanswered, and
that absence is itself the finding rather than a gap to be filled with optimism.

The reverse direction *is* evidenced, and that asymmetry is the whole decision:
2.3.1(a) states plainly that generic descriptions will be rejected. A vague or
absent note loses. A well-argued one is not known to win. So the notes carry a
plain, specific description and a walkthrough that demonstrates chaining, and
the guideline argument waits here for the one place a guideline citation is
actually responsive — a Resolution Center reply to a rejection that raised it.

## Verbatim notes block

> [!CAUTION]
> Everything between the `id=core` sentinels below is copied byte-for-byte into
> `fastlane/metadata/review_information/notes.txt` by `tools/gen-review-notes.rb`.
> Editing `notes.txt` directly will fail CI. The fix is always to edit the block
> here and run `ruby tools/gen-review-notes.rb` to regenerate.

The block below deliberately contains no rule numbers, no argument, and no
marketing language — see §"Why the notes do not contain this argument". It
describes the app and shows a reviewer how to exercise chaining in about a
minute. The literal values in the walkthrough were computed and checked before
being written down; a wrong expected value in the notes is worse than having no
walkthrough at all.

<!-- BEGIN:REVIEW-NOTES id=core -->
Shipkit Pipes is an offline developer utility for converting and inspecting
text: encoding and decoding, hashing, and timestamp conversion.

It is built for developers who do this work on the machine or device in front
of them, and who would rather not paste data - tokens, payloads, log lines -
into a website in order to convert it.

THE FIVE SCREENS

1. Pipeline - the "Pipeline" tab in the tab bar on iOS; the "Pipeline" item in
   the sidebar on macOS. This is the main screen and the one the app opens on.
2. Encode / Decode - the "Encode" tab on iOS; the "Encode / Decode" sidebar
   item on macOS. Base64, URL percent-encoding, and HTML entities.
3. Hashing - the "Hashing" tab on iOS; the "Hashing" sidebar item on macOS.
   MD5, SHA-1, SHA-256, and SHA-512.
4. Timestamps - the "Timestamps" tab on iOS; the "Timestamps" sidebar item on
   macOS. Unix epoch to ISO 8601 and to local time, and back, with a time zone
   picker that defaults to the device time zone.
5. History - the "History" tab on iOS; the "History" sidebar item on macOS.
   Inputs and results from the current session.

Screens 2 to 4 open as a pipeline pre-seeded with one step, so they are entry
points into the same canvas rather than separate modes.

CHAINING: A ONE-MINUTE WALKTHROUGH

The app is built around chaining one tool's output into the next tool's input.
To see it, with exact values to check against:

1. Open the "Pipeline" tab (iOS) or the "Pipeline" sidebar item (macOS).
2. Type this into the input field, with no trailing newline or space:
   hello
3. Add a step and choose Encode / Decode, then Base64 encode. The step shows:
   aGVsbG8=
4. Add a second step and choose Hashing, then SHA-256. It takes step 3's output
   as its input, not the original text, and shows:
   333d6b3a3c1f5db6c9bdda5939b136986d170f4649172a68368d54ecb44c2ff2
5. Both steps stay on screen with their intermediate values visible. Delete the
   Base64 step and the SHA-256 step recomputes over "hello" directly, changing
   to:
   2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
6. Steps can also be reordered, and the values update in place.

WHY THERE IS NO DEMO ACCOUNT

There is nothing to sign in to. The app has no accounts, no sign-in, and no
server, and it is fully offline: it has no network code path and no networking
entitlement on either platform. There are no credentials to supply.

ANTICIPATED QUESTIONS

Does any data the user enters leave the device?
No. Every operation runs locally. The app makes no network requests and has no
networking entitlement, so there is nothing to intercept or opt out of.

Is anything stored?
History is held in memory only and is cleared when the app quits. No input,
result, or pipeline is written to disk. The only persisted setting is which
tool screen was open last.

What does the app do with no network connection?
Everything. There is no online mode and no reduced offline mode; the app
behaves identically in airplane mode.
<!-- END:REVIEW-NOTES id=core -->

<!--
  NOTE FOR A LATER READER: the id=macos block below has NO generation
  destination in Phase 1, and that is deliberate rather than an oversight.
  fastlane/metadata/ currently holds exactly one review_information/ directory,
  while iOS and macOS each need their own review notes. Phase 8 adds a second
  generator invocation - `ruby tools/gen-review-notes.rb --id macos --dest
  fastlane/metadata/<macos-tree>/review_information/notes.txt` - at which point
  this block becomes live. Until then it is intentionally unwired. Do not delete
  it as dead text; the generator's block-isolation behaviour is already pinned by
  test/gen_review_notes_test.rb case 3 precisely so that this block can be wired
  later without changing the tool.

  CORRECTED 2026-09-01 at the Phase 2 close-out. This note used to say "D-04 and
  D-05 create two independent App Store records that each need their own review
  notes". D-44 reversed D-05 during 02-07: there is one record, 6807393045, with
  an IOS and a MAC_OS appStoreVersion. The premise was wrong and is removed. The
  consequence - that a second notes destination is still needed - is retained but
  is NOT yet evidenced: whether App Store Connect keeps review notes per platform
  version under Universal Purchase has not been measured by this project, and
  Phase 8 must measure it rather than inherit it from here. Stated as unverified
  on purpose; substituting a plausible answer for an unmeasured one is the exact
  failure Phase 2 spent ten plans catching.
-->

<!-- BEGIN:REVIEW-NOTES id=macos -->
Shipkit Pipes for Mac is a native Mac app rather than a port of the iOS build.
The five screens are reached from a sidebar rather than a tab bar, and the app
uses standard Mac window resizing, keyboard focus, and copy and paste.

It runs in the App Sandbox with no networking entitlement. It installs no login
item, no launch agent, and no privileged helper tool, and it embeds no update
mechanism of its own - it is distributed through the Mac App Store only, and it
does nothing while it is not running.

The tool set, the five screens, and the chaining walkthrough are the same as on
iOS.
<!-- END:REVIEW-NOTES id=macos -->
