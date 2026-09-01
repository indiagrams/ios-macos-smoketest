# Product identity

## Why this exists

This is the durable, tracked record of what this app is called, what it ships, and
where each of its tools lives. The fuller reasoning — the alternatives weighed, the
proposals rejected — lives in this project's planning notes, which are gitignored and
do not survive a fresh clone, a new checkout, or a refork. This file does survive, and
it is what later work reads when it needs the actual strings: the App Store Connect
records, the identity replacement in the project manifests, and the App Store metadata
all resolve their values from here.

Nothing in this file is implemented yet. Recording the decision and changing the
identity strings in build files are separate steps, deliberately in separate phases.
This file is the record; the implementation lands later, in the identity work tracked
as `IDENT-01` onward.

## Identity

| Field | Value | Decision |
|---|---|---|
| App Store display name | Shipkit Pipes | D-01 |
| iOS bundle ID | `com.indiagram.shipkitpipes.ios` | D-04 |
| macOS bundle ID | `com.indiagram.shipkitpipes.macos` | D-04 |
| Bundle ID prefix | `com.indiagram.*` | D-06 |
| Universal Purchase | Declined — two independent app records, one per platform | D-05 |
| GitHub repository name | Unchanged: `indiagrams/ios-macos-smoketest` | D-02 |
| Xcode target and scheme names | Generic and fork-independent — decided, not yet implemented | D-03 |

**Three separate strings.** The repository name, the Xcode target name, and the App
Store display name are three different strings, and only the third one reaches App
Review. Collapsing them is the mistake this table exists to prevent: the repo can keep
a name that describes what the repo is for, the Xcode target can carry a generic
fork-independent name that needs no renaming, and the store-facing name can be the
product name. A reader who later finds `ios-macos-smoketest` in the URL bar and
`Shipkit Pipes` on the App Store listing has not found a mismatch — they have found
this separation working as designed.

**Why the display name matters.** Guideline 2.2 states that demos, betas, and trial
versions do not belong on the App Store. An app presenting itself as a smoke test
announces itself as exactly that, so "Smoke App" could not ship under any bundle ID.
The display name is the one string that has to carry a genuine product identity, and
it is the reason the identity work is a prerequisite for submission rather than a
parallel cleanup track.

**Accepted risk (D-07).** A reviewer who searches "shipkit" finds a
release-engineering template, which slightly weakens the framing that this is a
product rather than a vehicle for testing a pipeline; the risk is logged and accepted
rather than argued away, and the review arguments in
[REVIEW-ARGUMENTS.md](REVIEW-ARGUMENTS.md) carry that weight instead.

> [!IMPORTANT]
> **The display name is not confirmed.** App Store display names must be unique
> store-wide, and that cannot be checked from a build machine — only from App Store
> Connect at the moment a record is created. Phase 2 confirms availability when it
> creates the two ASC records. Until then, "Shipkit Pipes" is a first choice, not a
> settled fact, and anything downstream that hardcodes it inherits that caveat.

## What v1 ships

This is the feature list. Every tool v1 ships appears here with the surface it lives
on; anything absent from this table is not v1.

| Tool | Operations | Surface |
|---|---|---|
| Base64 | Encode, decode | Encode/decode |
| URL percent-encoding | Encode, decode | Encode/decode |
| HTML entities | Encode, decode | Encode/decode |
| MD5 | Hash | Hashing |
| SHA-1 | Hash | Hashing |
| SHA-256 | Hash | Hashing |
| SHA-512 | Hash | Hashing |
| Unix epoch → ISO 8601 | Convert | Timestamps |
| Unix epoch → local time | Convert | Timestamps |
| ISO 8601 → Unix epoch | Convert | Timestamps |
| Local time → Unix epoch | Convert | Timestamps |
| Timezone selection | Picker, defaulting to the device timezone | Timestamps |

## The five surfaces

1. **Encode/decode** — Base64, URL percent-encoding, and HTML entity conversion.
2. **Hashing** — MD5, SHA-1, SHA-256, and SHA-512 digests.
3. **Timestamps** — Unix epoch to ISO 8601 and to local time and back, with a timezone
   picker that defaults to the device timezone.
4. **Pipeline canvas** — the primary work surface. Steps chain, intermediate output is
   visible, and steps are removable and reorderable.
5. **History** — recent inputs and results for the current session.

**The app is pipeline-first (D-08).** The work surface is always a pipeline. The point
of chaining is that a reviewer meets it immediately rather than discovering it behind a
menu, so the pipeline canvas is the primary surface and not an advanced mode.

**A tool screen is a pipeline pre-seeded with one step (D-09), not a separate mode.**
Opening Hashing yields a one-step pipeline that can be extended in place. This is what
reconciles pipeline-first with having three named tool surfaces: they are entry points
into the same canvas, not a second implementation of it.

**Five surfaces, against a floor of three (D-10).** `APP-10` requires at least three
distinct screens; five clears guideline 4.2's not-a-single-view-utility bar with
margin. The margin is deliberate — a count that exactly meets the floor leaves nothing
to lose if a surface is cut during implementation.

**Navigation is platform-idiomatic (D-11).** iOS uses `TabView` with `NavigationStack`;
macOS uses `NavigationSplitView` with a sidebar. This is driven by review risk rather
than preference: guideline 2.4.5 judges Mac-nativeness, and an app that feels like a
ported iOS build is a known macOS rejection theme. The accepted cost is maintaining two
layouts over one.

## History and privacy

**History is in-memory only (D-12).** It is cleared on quit and never touches disk. No
input, no result, and no pipeline the user builds is persisted anywhere.

Three consequences follow from that, and downstream work depends on all three:

- **App Privacy nutrition labels become "Data Not Collected."** Not a goal that was
  worked toward — a consequence of there being nothing stored to declare.
- **`PrivacyInfo.xcprivacy` declares `UserDefaults` only**, for the `APP-13`
  last-used-tool setting, under `NSPrivacyAccessedAPICategoryUserDefaults` with reason
  code `CA92.1`. It never declares user content, because user content never reaches
  `UserDefaults`.
- **The "we stored your API key" failure mode is eliminated.** People paste secrets —
  tokens, keys, payloads — into tools like this one. Nothing persisted means nothing to
  leak, and it means that property is structural rather than a promise.

## Not in v1

Deliberately out of scope for the first release:

- JSON tools
- UUID and ULID generation
- JWT decoding
- Saved pipelines
- macOS menu-bar and Services integration

Pulling JSON tools forward to strengthen the guideline 4.3(b) position was considered
and declined. The differentiation argument this project makes is narrow and rests on
how the work surface is organized, not on how much the app does; adding tool families
would not strengthen it. See [REVIEW-ARGUMENTS.md](REVIEW-ARGUMENTS.md) for the
argument itself.
