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

## Competitive scan (run YYYY-MM-DD)

This scan exists because the differentiation claim this file will make is
checkable only against the actual App Store shelf. App Store search results are
region-, device-, and account-specific and cannot be reproduced from a build
machine, so desk research against vendor sites and listing pages is a starting
inventory, not evidence. A listing that does not advertise a feature is not
proof the feature is absent — the app has to be opened.

The table below is pre-filled from desk research assembled 2026-08-30. Every
chaining cell starts as `UNVERIFIED` and may only be changed by what a human
observed on a device.

| App | Store | Tool families | Chains tool output into another tool? | Evidence (what you saw) | Scanned |
|---|---|---|---|---|---|
| DevUtils: Dev Toolkit (`id6759389631`) | iOS App Store — iPhone, iPad, Mac; free | "37+ tools", offline-first | UNVERIFIED — pending on-device scan |  |  |
| DevUtils.app (`id1533756032`, different seller) | Mac App Store | ~47 tools: JSON/HTML/SQL format, YAML↔JSON, Unix time, JWT, MD5/SHA-1/SHA-256/SHA-512, Base64, URL, HTML entity | UNVERIFIED — pending on-device scan |  |  |
| Developer Tools - Tooly (`id6639614589`) | iOS + macOS | Base64, JSON↔XML, string case, Unix time; tools also exposed as Shortcuts actions | UNVERIFIED — pending on-device scan |  |  |
| Hex: Dev Tools (`id6760552804`) | iOS App Store | Base64, MD5/SHA-1/SHA-256/SHA-512, clipboard auto-detect | UNVERIFIED — pending on-device scan |  |  |
| DevToys (macOS) | Mac App Store | Converters, encoders/decoders, formatters | UNVERIFIED — pending on-device scan |  |  |
| CyberChef, or any derivative or port | Searched on both stores | ~300 operations chained as "recipes" in the web original | UNVERIFIED — pending on-device scan |  |  |
| _(spare row — add any app found in a top-ten list that is not above)_ |  |  |  |  |  |
| _(spare row — add any app found in a top-ten list that is not above)_ |  |  |  |  |  |

Rules for filling this table in. A row is only marked `No` if somebody opened
the app and looked; a row nobody reached keeps its `UNVERIFIED` cell and gains
an explicit "not scanned" note in the evidence column. Silently converting an
unchecked row to `No` is the failure mode this table is shaped to prevent.
Unused spare rows are deleted rather than left blank.

### Assumption verdicts

- `A3 — CyberChef or a derivative ships on the App Store: UNVERIFIED`
- `A4 — an incumbent developer toolkit chains one tool's output into another: UNVERIFIED`

**A `YES` on either verdict falsifies the sole defensible 4.3(b) claim — that no
native App Store app makes the chain the primary work surface — and the phase
stops there.** No argument gets written on top of a falsified premise. This
app's v1 tool set (encode/decode, hashing, timestamps) is a strict *subset* of
what the free incumbents already ship, so tool count cannot be substituted as
the differentiator; a `YES` means the concept needs rethinking, not rewording.
That is why this scan runs before any argument text is written, and why the
checkpoint gating it is blocking rather than end-of-phase.

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

---

<!--
  This file is intentionally incomplete. This plan writes only the top matter
  and the competitive scan. Still to be appended, by a later plan in this phase:
  the 4.2 lasting-utility argument, the 4.3(b) differentiation argument, the
  macOS 2.4.5 addendum, the hostile-read pre-mortem, the pre-drafted Resolution
  Center reply, and the delimited verbatim block that the notes generator reads.
  Do not treat the absence of those sections as a bug.
-->
