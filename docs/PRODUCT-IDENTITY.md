# Product identity

## Why this exists

This is the durable, tracked record of what this app is called, what it ships, and
where each of its tools lives. The fuller reasoning — the alternatives weighed, the
proposals rejected — lives in this project's planning notes, which are gitignored and
do not survive a fresh clone, a new checkout, or a refork. This file does survive, and
it is what later work reads when it needs the actual strings: the App Store Connect
records, the identity replacement in the project manifests, and the App Store metadata
all resolve their values from here.

**The App Store Connect side of this identity is live; the build-file side is not.**
As of 2026-09-01 the record, the store name, the bundle ID and the SKU exist at Apple
and are recorded below. Changing the identity strings inside the project manifests is a
separate step in a separate phase, tracked as `IDENT-01` onward. A reader who finds the
old placeholder identity in `app/` has not found a contradiction — they have found the
half that has not landed yet.

## Identity

| Field | Value | Decision |
|---|---|---|
| App Store display name | Shipkit Pipes | D-01 |
| Universal Purchase | **Adopted** — one app record serving both iOS and macOS | D-44, reversing D-05 |
| App Store Connect record | `6807393045` — one record, two platform versions | D-44 |
| Shared bundle ID, iOS and macOS | `com.indiagram.shipkitpipes.ios` | D-44, superseding D-04 |
| SKU — permanent, never reissuable | `shipkitpipes-ios-001` | D-31 |
| Registered but unused App ID | `com.indiagram.shipkitpipes.macos` (`KPNQ2D3B8A`) | D-44 |
| Bundle ID prefix | `com.indiagram.*` | D-06 |
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

**The display name is confirmed.** App Store Connect accepted "Shipkit Pipes" on
2026-09-01 for record `6807393045`, and reservation is a side effect of that creation
because Apple exposes no availability-query endpoint to ask in advance (D-01, D-30).
Anything downstream may hardcode the name without inheriting a caveat. The name was read
back from Apple rather than trusted from the form: `GET /v1/apps` reports `name` as
`Shipkit Pipes`, `sku` as `shipkitpipes-ios-001`, and `primaryLocale` as `en-US`.

## Build-system identity, measured

**The build-file side is now measured, not claimed.** Every row in this section was read
from a generated project or from a built `.app` on the date shown, against the tool versions
shown, and each row says what it was measured against — the same value, date, scope triple
that [APPLE-ACCOUNT-STATE.md](APPLE-ACCOUNT-STATE.md) uses for facts that live at Apple.
The paragraph at the top of this file that describes the build-file side as not yet landed is
dated to 2026-09-01; the rows below are what landed, and the phase's final audit closes that
paragraph rather than this section.

**Why this is a dated record and not a badge.** There is no fork-owned macOS CI surface in
this repository. The one fork-owned required status context, `review notes`, runs on
`ubuntu-latest` with no Xcode, and all three `macos-15` jobs live in the template-owned
`.github/workflows/pr.yml`, which this fork does not edit. The check that both generators
report the same identity needs `xcodebuild`, so it is a local command whose output is recorded
here, and re-running the command at the end of this section is how the record is refreshed.

### Generator parity

Both generators attach `app/Identity.xcconfig` and neither manifest carries an identity
literal; `tools/identity-parity.rb` regenerates with each, reads `xcodebuild
-showBuildSettings` for every scheme and configuration, and diffs the identity keys.

| Pair | Resolved identity settings, identical across XcodeGen and Tuist | Measured (ISO-8601) | Against |
|---|---|---|---|
| `App-iOS`, `Release` | `PRODUCT_BUNDLE_IDENTIFIER = com.indiagram.shipkitpipes.ios`, `PRODUCT_NAME = ShipkitPipes`, `FULL_PRODUCT_NAME = ShipkitPipes.app`, `INFOPLIST_KEY_NSHumanReadableCopyright = Copyright © 2026 Indiagram LLC. All rights reserved.`, plus `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, `SWIFT_VERSION` — 7 keys | 2026-09-02 | XcodeGen 2.46.0, Tuist 4.205.0, Xcode 26.1.1 (17B100) |
| `App-iOS`, `Debug` | the same 7 keys, identical | 2026-09-02 | same |
| `App-macOS`, `Release` | `PRODUCT_BUNDLE_IDENTIFIER = com.indiagram.shipkitpipes.ios`, `PRODUCT_NAME = ShipkitPipes`, `FULL_PRODUCT_NAME = ShipkitPipes.app`, plus the three version keys — 6 keys. The copyright is a plist-dictionary key on macOS rather than a build setting, so it is absent from both sides symmetrically | 2026-09-02 | same |
| `App-macOS`, `Debug` | the same 6 keys, identical | 2026-09-02 | same |
| `DEVELOPMENT_TEAM`, all four pairs | With the gitignored `app/Local.xcconfig` set aside: **no `DEVELOPMENT_TEAM` line on either side** and the verdict is still `PARITY OK`. With the file present: one identical line on both sides, and one more key per pair | 2026-09-02 | both states measured in the same session; the file restored byte-identically afterwards |

### Built apps

The values below were read with `PlistBuddy` from the `.app` bundles that `xcodebuild`
produced, located through `BUILT_PRODUCTS_DIR` from `-showBuildSettings`. They are the
arbiter for the identity: a generated `Info.plist` under `app/` is untracked and carries the
unresolved `$(COPYRIGHT)` reference, so it is not evidence of anything.

| Platform and key | Value read from the built app | Measured (ISO-8601) | Against |
|---|---|---|---|
| macOS `CFBundleDisplayName` | `Shipkit Pipes` | 2026-09-02 | `App-macOS`, `Release`, `platform=macOS`, unsigned, XcodeGen project, Xcode 26.1.1 |
| macOS `CFBundleName` | `ShipkitPipes` | 2026-09-02 | same |
| macOS `CFBundleIdentifier` | `com.indiagram.shipkitpipes.ios` | 2026-09-02 | same |
| macOS `NSHumanReadableCopyright` | `Copyright © 2026 Indiagram LLC. All rights reserved.` — the `©` present as UTF-8 bytes `c2 a9` in the built plist, checked with `xxd`, not by how it renders | 2026-09-02 | same; this is the string the About box shows |
| iOS `CFBundleDisplayName` | `Shipkit Pipes` | 2026-09-02 | `App-iOS`, `Release`, `iphonesimulator`, unsigned, XcodeGen project, Xcode 26.1.1 |
| iOS `CFBundleName` | `ShipkitPipes` | 2026-09-02 | same |
| iOS `CFBundleIdentifier` | `com.indiagram.shipkitpipes.ios` | 2026-09-02 | same |
| iOS `NSHumanReadableCopyright` | **Absent from the built iOS plist** — `PlistBuddy` reports `Does Not Exist`. The build setting `INFOPLIST_KEY_NSHumanReadableCopyright` resolves to the full string in `-showBuildSettings`, but `INFOPLIST_KEY_*` values are written into the plist only under `GENERATE_INFOPLIST_FILE = YES`, and the app targets use an explicit `INFOPLIST_FILE` with that setting `NO`. No iOS surface displays this key; the store-facing copyright is `fastlane/metadata/copyright.txt` | 2026-09-02 | same; recorded as observed, not rounded up |
| Both platforms, the edit control | `DISPLAY_NAME` in `app/Identity.xcconfig` set to `Negative Control`: the rebuilt macOS and iOS apps both read `Negative Control`; reverted, both read `Shipkit Pipes` again. Six unsigned builds, six `PlistBuddy` reads | 2026-09-02 | the claim "editing the one tracked file changes the built app on both platforms", demonstrated in both directions |

### What is not gated, and what covers it

With a required key removed from `app/Identity.xcconfig`, `xcodegen generate` exits 3 naming
the key and writes no project, because `options.preGenCommand` runs
`tools/preflight-identity.rb` first. On the same input `tuist generate` exits 0 and writes a
project whose `PRODUCT_BUNDLE_IDENTIFIER` resolves to nothing — the line is absent from
`-showBuildSettings` altogether. That is a known, documented coverage gap, not a passing
control: Tuist has no pre-generation hook, and a guard embedded in `app/Project.swift` is
skipped whenever only the xcconfig changes, because Tuist's manifest cache keys on the
manifest's own content. Tuist's coverage is the `review notes` job, which runs the same
preflight as plain text on every pull request whichever generator produced anything.
Measured 2026-09-02 against Tuist 4.205.0 and XcodeGen 2.46.0.

### Re-measuring

The command below was executed on 2026-09-02, before it was published here, and produced the
values in the tables above; a re-check command that nobody has run is a convention, not a
mechanism. It regenerates the gitignored project with both generators, builds both platforms
unsigned, and prints the parity verdict followed by the built-plist values. Expect
`identity-parity: PARITY OK — 4 scheme x configuration pair(s) identical across XcodeGen and
Tuist`, then the macOS bundle path and four values, then the iOS bundle path and three.

```bash
export PATH="/opt/homebrew/opt/ruby@3.3/bin:$PATH"
ruby tools/identity-parity.rb
( cd app && xcodegen generate )
D=$(xcodebuild -project app/App.xcodeproj -scheme App-macOS -configuration Release -showBuildSettings 2>/dev/null | sed 's/^ *//' | awk -F' = ' '/^BUILT_PRODUCTS_DIR = /{print $2}')
xcodebuild build -quiet -project app/App.xcodeproj -scheme App-macOS -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
APP=$(ls -d "$D"/*.app | head -1); echo "$APP"
for k in CFBundleDisplayName CFBundleName CFBundleIdentifier NSHumanReadableCopyright; do /usr/libexec/PlistBuddy -c "Print :$k" "$APP/Contents/Info.plist"; done
D=$(xcodebuild -project app/App.xcodeproj -scheme App-iOS -configuration Release -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -showBuildSettings 2>/dev/null | sed 's/^ *//' | awk -F' = ' '/^BUILT_PRODUCTS_DIR = /{print $2}')
xcodebuild build -quiet -project app/App.xcodeproj -scheme App-iOS -configuration Release -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
APP=$(ls -d "$D"/*.app | head -1); echo "$APP"
for k in CFBundleDisplayName CFBundleName CFBundleIdentifier; do /usr/libexec/PlistBuddy -c "Print :$k" "$APP/Info.plist"; done
```

### Tool versions these measurements were made against

`.tool-versions` is the template's pin file; `make bootstrap` installs through `Brewfile`
instead, so nothing reports when the two diverge. Five of its six pins differ from what is
installed on the machine that made every measurement above.

| Tool | `.tool-versions` pin | Installed when measured (2026-09-02) |
|---|---|---|
| ruby | 3.3.11 | 3.3.12 at `/opt/homebrew/opt/ruby@3.3/bin/ruby`; the suites are also run under 4.0.6 |
| xcodegen | 2.45.4 | 2.46.0 |
| lefthook | 2.1.6 | 2.1.12 |
| swiftlint | 0.63.2 | 0.65.1 |
| swiftformat | 0.61.1 | 0.62.1 |
| xcbeautify | 3.2.1 | 3.2.1 — the one pin that matches |
| tuist | not pinned (`Brewfile` cask) | 4.205.0 |
| Xcode | `xcodeVersion: "26.0"` in `app/project.yml` | 26.1.1 (17B100) |

## One record, two platforms

**Universal Purchase was adopted on 2026-09-01, reversing the decision to decline it
(D-44, reversing D-05).** This is the one place a fresh clone can read why, so it is
recorded here rather than only in the gitignored planning notes.

The reversal was forced by a fact no source consulted in this project had surfaced:
**App Store names must be unique within an account, not merely store-wide.** Creating a
second record for macOS under the same name failed, and Apple's rejection said so
verbatim:

> "The app name you entered is already being used for another app in your account. If
> you would like to use the name for this app you will need to submit an update to your
> other app to change the name, or remove it from App Store Connect."

The collision was not with a third party. It was with this project's own iOS record,
created minutes earlier. Two records in one account cannot share a name, so the
two-record shape and the single store name in this table could not both hold — the plan
was unsatisfiable by construction rather than by mistake, and one of the two had to go.
The name is load-bearing for the guideline 4.3(b) argument the whole submission rests on
(D-08, D-24), so the record shape gave way instead (D-30 forbids substituting a name).

**What it costs, recorded rather than argued away.** D-05 declined Universal Purchase to
keep the two platforms' App Review rejection blast radius independent. That property is
now given up: one record, one name, one metadata tree. iOS and macOS remain separate
`AppStoreVersion`s and can still be submitted independently, so the two submissions stay
separate — but a name or metadata rejection now lands on both. This was chosen with the
trade stated, which is what the roadmap's criterion asks of this decision.

**The `.ios` suffix on a cross-platform bundle ID is deliberate, not a leftover.**
`com.indiagram.shipkitpipes.ios` now identifies both platforms. Renaming it would have
meant deleting the record, and a removed app's SKU cannot be reused in the same
organization — so `shipkitpipes-ios-001` would have been burned permanently to fix a
string no user ever sees. The cosmetic oddity was the cheaper of the two.

**`com.indiagram.shipkitpipes.macos` (`KPNQ2D3B8A`) is registered and now permanently
unused.** It is left in place deliberately: deleting App IDs is not obviously reversible
and keeping it costs nothing. Its SKU, `shipkitpipes-macos-001`, was never consumed. A
read-back for that identifier correctly returns not-found, because no app record was ever
created against it — that is the expected result under Universal Purchase and not a
defect to be repaired.

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

## European Union trader status

**This app ships as a declared trader in the European Union, and that is recorded here
at both of the surfaces Apple keeps it on (D-38).** Under the Digital Services Act an app
whose developer has not made the declaration is withdrawn from the EU App Store, so this
is availability state rather than paperwork. It lives in this tracked file rather than
only in this project's planning notes because those notes are gitignored and do not
survive a fresh clone — the same reasoning that produced D-23.

**There are two surfaces, and the second one is the one that goes unchecked.** A shipping-
guidance file this project inherited states that trader status is an account-level setting
only. It is not: Apple carries an account-level declaration under Business and a separate
per-app declaration under App Information, and a check that reads only the first would
report green while an individual app sat undeclared (R-05, C-08). Both were read on the
same day by the account holder, and both are below. Every string is quoted as it appeared
on screen; nothing here is a normalised or expected value.

| Surface | Observed string | Observed (ISO-8601) | Against |
|---|---|---|---|
| Business, Agreements, Compliance, Digital Services Act — the status | `Active`, shown alongside `Digital Services Act`, `27 Countries or Regions`, a `View` link, and `May 17, 2026` | 2026-09-01 | account, team `G5H628C6WR` |
| The `Digital Services Act Compliance` dialog — the selected option | `I'm a trader under the DSA`, its radio filled | 2026-09-01 | account, team `G5H628C6WR` |
| The `Digital Services Act Compliance` dialog — the unselected option | `I'm not a trader under the DSA or I don't plan to distribute in the EU` | 2026-09-01 | account, team `G5H628C6WR` |
| App Information, App Store Regulations and Permits, Digital Services Act | `This developer has identified itself as a trader for this app` | 2026-09-01 | record `6807393045`, bundle ID `com.indiagram.shipkitpipes.ios` |
| App Information, App Store Regulations and Permits — the platform selector | `There is no platform selector.` One Digital Services Act block serves the whole record | 2026-09-01 | record `6807393045`, covering both its `IOS` and `MAC_OS` versions |

**The account-level declaration was read, never touched.** The dialog was opened, both of
its options were read, and it was dismissed. `Next` was not clicked, no selection was
changed, and nothing was submitted. Changing that selection removes published apps from
the EU App Store until re-verified, and team `G5H628C6WR` is shared with another shipping
product, so the blast radius of a stray click there is not this project's alone.

**Declaring as a trader publishes contact details on the public product page.** The
selected option's own sub-text says so: a trader provides an address, a phone number and
an email address "for the purpose of posting on your App Store product page in accordance
with the DSA", and the same sentence adds that this is display-only and does not change
the contact details on any Apple account or membership. The unselected option's sub-text
is the complement — no contact information to be displayed. This is recorded because it is
a consequence of trader status that nothing in this project had written down, and because
it sits next to a standing rule without contradicting it: **Apple publishes those details
by regulation, and this repository still does not commit them.** No address, phone number
or email value appears anywhere in this file, and `test/docs_structure_test.rb` sweeps for
the shapes of them.

**Under Universal Purchase the per-app declaration is one surface, not two, and that was
observed rather than assumed.** Record `6807393045` carries two `appStoreVersions`, `IOS`
and `MAC_OS` (D-44). The obvious hazard was that App Store Regulations and Permits might
expose the declaration per platform, in which case reading the iOS half would say nothing
about the macOS half — the same substitution R-05 forbids, one seam further in. The
surface was checked for a platform selector and has none, so the single block above covers
both versions. That is a row in the table, and it is a measurement, not a note.

**Apple publishes no verification state labels and no turnaround commitment.** That is a
verified negative claim, not an omission: the help page, the four dated developer news
posts, and the App Store Connect API specification were all read on 2026-09-01 and none
of the five names a state vocabulary or a service-level target (T-10). There is therefore
no such thing as waiting for a particular word to appear. What exists is the status string
above, on the date above.

**No label in the table above was predicted, and every prediction about these strings has
now failed.** The pair this project was told to check the account-level status for —
`Verified` and `Pending` — appears in no first-party Apple source, and neither is what the
screen says; the screen says `Active` (R-06). Apple's own documentation describes the
dialog's choice as being between "This is a trader account" and "This is not a trader
account"; **both** real labels differ from both documented ones, and the real first option
is a contraction, `I'm`, which is the kind of difference a paraphrase erases without
anybody noticing. That makes three documented-strings-versus-reality failures inside one
phase: the status vocabulary, the dialog's option labels, and `UNIVERSAL` being stored for
every App ID whatever platform was requested (R-10). The rule that survives all three is
the one this section is built on — a string is recorded because someone read it, or it is
not recorded.

> [!IMPORTANT]
> Trader status is enforced by Apple **at submission time**. This section is evidence that
> the declaration was in place on 2026-09-01 against the record named — not a standing
> guarantee. The staleness window for it in
> [APPLE-ACCOUNT-STATE.md](APPLE-ACCOUNT-STATE.md) is `per submission`, and Phases 10 and
> 11 re-read both surfaces rather than trusting this file's date.

**The D-37 exit condition, written from what was read.** D-37 requires Apple to have
confirmed trader status before Phase 2 exits, and R-06 forbids naming the confirming string
in advance — so the condition could only be written afterwards, from the terminal state
that actually exists. It is this: the account-level Digital Services Act row reads `Active`
on a recorded date against team `G5H628C6WR`, **and** the Digital Services Act block on
record `6807393045`'s own App Information page states that this developer has identified
itself as a trader for this app, on a recorded date, read at the app's surface rather than
inferred from the account. Both halves held on 2026-09-01 and both are rows in the table
above, so the condition is met. An account-level reading on its own does not meet it —
that substitution is precisely what R-05 exists to prevent — and there is nothing stronger
available to ask Apple for.

**What could not be checked, stated rather than papered over.** The strongest evidence a
state is real is watching it change: a per-app surface read before and after a declaration
is made shows two different strings, where one string read once shows only that something
was displayed. That control could not run here. Record `6807393045` was already declared
when it was first looked at, there was no action to take, and no before-and-after pair
exists. What stands in its place, labelled as a substitute and not as a control, is the
pair of option labels in the dialog: the surface demonstrably expresses both a trader and
a non-trader state, and the one selected is the trader state. A fabricated pair would have
been worse than this admission.

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
