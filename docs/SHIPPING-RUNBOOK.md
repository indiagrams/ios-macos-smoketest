# Shipping runbook — the App Store Connect steps this pipeline cannot automate

This document has one narrow subject: **the App Store Connect steps this repository's
release pipeline cannot perform, and what was actually done about each one.** It is not a
general release guide, and it deliberately does not duplicate the two documents that are:

| For | Read | Source of truth for |
|---|---|---|
| What you need from Apple before any of this applies | [APPLE-PREREQS.md](APPLE-PREREQS.md) | Account tiers, enrolment, certificate quotas |
| How to archive, export and upload without fastlane | [RELEASE-WITH-APPLE-NATIVE-TOOLS.md](RELEASE-WITH-APPLE-NATIVE-TOOLS.md) | The Apple-native command sequence |
| The live account and record facts, as dated rows | [APPLE-ACCOUNT-STATE.md](APPLE-ACCOUNT-STATE.md) | Key ids, certificate census, record state |

Where a step is documented in one of those, this file links to it and says so rather than
restating it. A second copy of a command is a second copy to keep correct.

## How to read an entry

Every entry carries four things, and an entry missing any of them is not finished:

1. **What the step is.**
2. **Why it has no automated path — with the measurement behind that claim.** "There is no
   API" is an assertion; a status code and a response body is a measurement. This project
   has been wrong before about what a tool can do, and the correction cost a criterion
   amendment (D-112), so claims about tool capability carry their evidence here.
3. **Exactly where it is performed.**
4. **The date it was performed — or, plainly, that it has not been.** A runbook that
   documents steps nobody ran is a plan. **A blank Performed cell is not a zero and an
   unperformed step is not a passing one.**

---

## 1. App Privacy nutrition labels — **PERFORMED 2026-09-11.**

**Performed:** 2026-09-11 — **Data Not Collected**, saved and Published in App Store Connect by
the account holder. This is an ATTESTATION, not a measurement: no tool can verify it, because the
App Privacy API does not exist (§10's row carries the two 404s and the 41-relationship
enumeration behind that claim).
**Where:** App Store Connect → Apps → *Shipkit Pipes* → **App Privacy** → Edit.

### Why there is no automated path — measured three ways on 2026-09-11

Not "we could not find an endpoint". There is no relationship of any name on the app
resource that could carry the answer:

```
GET /v1/apps/6807393045/appDataUsages          -> HTTP 404  PATH_ERROR
    "The relationship 'appDataUsages' does not exist"
GET /v1/apps/6807393045/dataUsagePublishState  -> HTTP 404  PATH_ERROR
    "The relationship 'dataUsagePublishState' does not exist"
GET /v1/apps/6807393045                        -> HTTP 200  (the control: the client works)
    41 relationships returned; zero match privacy, dataUsage or nutrition
```

Corroborated independently and earlier by the template's own tooling: `bin/lib/bootstrap.rb`
carries a `rescue Spaceship::UnexpectedResponse` clause whose comment records that Apple
removed both relationships in Apr–May 2026 and that the fastlane gem has not caught up.

Apple's own help page — *manage-app-information/manage-app-privacy* — describes an
**11-step web-UI flow ending in an explicit Publish**, and states that **"Responses are
provided at the app level and shared across platforms"**, which is why this is answered
**once** and is thereby in force for iOS and macOS both. It also states that once Data Not
Collected is selected, *"You don't need to answer any further questions."*

### The steps, in the order they must be done

1. Sign in to App Store Connect and open the app record.
2. Open **App Privacy** in the left-hand column of the app's page.
3. Under *Data Collection*, choose **Edit**.
4. Answer **No** to "Do you or your third-party partners collect data from this app?" —
   i.e. select **Data Not Collected**.
5. Save that answer.
6. **Publish it.** The flow ends with an explicit **Publish** button and a confirmation.
   **Saving is not publishing**, and an unpublished answer is the same as no answer.
7. Copy the confirmation text the UI shows, verbatim, and record it with the date below.

### Why those answers are correct — so they can be refused if you disagree

The shipped privacy manifest `app/Shared/PrivacyInfo.xcprivacy` declares an **empty**
`NSPrivacyCollectedDataTypes`, and `test/privacy_manifest_test.rb` asserts that
bidirectionally against Release `.xcarchive`s on both platforms under both generators. It
is a **required** status context on `main`, so every pull request carries it as a merge
gate. The app persists five interface settings in its own preferences and nothing else — no
text entered, no result and no chain of steps is written anywhere. The manifest declares
exactly one accessed-API category with reason **CA92.1**, *information only accessible to
the app itself*; **an accessed API is not a collected data type**, and nothing in the
labels should suggest otherwise.

The answers also have to agree with what the app already tells a reviewer. See
`fastlane/metadata/review_information/notes.txt` § "ANTICIPATED QUESTIONS", which answers
"does any data leave the device" and "is anything stored" in the app's own words.
**Publishing labels that contradict either is telling Apple two different stories.**

### What NOT to do in the same session

- **Do not submit for review**, and do not press anything that moves a version toward
  review. See §4.3 — this record's single open iOS review slot is permanently occupied.
- Do not touch the existing review submission.
- Do not change the release type, the price, or the version state while you are in there.

### What to record when you have done it

Append one line to this file's §7 log and fill the Performed cell above:

```
PERFORMED app-privacy published=yes date=<YYYY-MM-DD> selection=Data Not Collected
confirmation: "<paste the App Store Connect confirmation text verbatim>"
```

Then, and only then, `export ASC_APP_PRIVACY_ACK=true` in your shell profile or in the
gitignored `.bootstrap.env` to silence `make doctor` step 18. **Never put a value in the
tracked `.bootstrap.env.example`.**

**`make doctor` cannot confirm this for you.** Its App Privacy step hits the same removed
relationship and degrades to "the probe is broken", not to "unpublished" — so it is a
second witness that the API is gone, and **not** an independent check that you published.
Your own reading of the App Store Connect UI after Publish is the only confirmation that
exists.

---

## 2. Pricing and Availability — **NOT PERFORMED. Blocks App Store submission.**

**Performed:** not yet.
**Where:** App Store Connect → your app → **Pricing and Availability**. A free app must
still pick a price of **0**.

**Why there is no automated path, measured 2026-09-11:**

```
GET /v1/appPriceSchedules/6807393045                 -> HTTP 200 (exists for every app)
GET /v1/appPriceSchedules/6807393045/baseTerritory   -> HTTP 200, id USA
GET /v1/appPriceSchedules/6807393045/manualPrices    -> HTTP 404 NOT_FOUND
GET /v1/appPriceSchedules/6807393045/automaticPrices -> HTTP 404 NOT_FOUND
```

The schedule resource returns 200 with an id even for an app that has never been priced, so
**its existence proves nothing**; `manualPrices` 404s until a price is actually set. That
discriminator is not this document's invention — it is written down in `bin/lib/bootstrap.rb`
beside the check, verified there against a priced app (200, 1 entry) and an unpriced one.

No lane in this repository passes `price_tier`. `deliver` 2.238.0 does carry the option, but
its implementation goes through `app.prices` and `get_app_price` — the **legacy** price-tier
API, under a comment of its own dated 2020-09-14 — and `bin/lib/bootstrap.rb` records that
`fetch_app_prices` raises against the current API because Apple replaced app prices with
`appPriceSchedules`. The option exists; the road under it is the old one.

`make doctor` step 19 reports this, and reports **one** prerequisite missing rather than
three — which is also the independent confirmation that category and age rating are set.
Its own warning is worth repeating: **App Store Connect reports only the first unmet
prerequisite it hits, so finding them by submitting costs a review cycle each.**

---

## 3. App Review contact details — **NOT PERFORMED.**

**Performed:** not yet.
**Where:** the four files under `fastlane/metadata/review_information/`, which the metadata
lanes then deliver. `make doctor` step 16 lists them by path when they still hold
placeholders.

**Referenced by file path, never by value, on purpose.** This repository publishes no
contact details in `docs/`, and the gate that enforces that (`test/docs_structure_test.rb`)
sweeps a fixed list of five documents which **does not include this one** — see §6.1. So the
rule here is carried by hand: name the path, never the value.

Plan 08-17 deliberately did not send these to App Store Connect, and asserted afterwards
that `contactFirstName`, `contactLastName`, `contactEmail` and `contactPhone` are all still
null on both platforms' review details. Contact details belong on the submit path, at
Phase 9 or 10, not on the metadata path.

---

## 4. GitHub Pages for the support and privacy pages — **PERFORMED 2026-09-11.**

**Performed:** 2026-09-11, 06:04–06:09 UTC.
**Where:** `github.com/indiagrams/ios-macos-smoketest` — repository Pages settings.

**And the honest version of what happened, because it is not what the plan expected.** No
`POST /repos/{owner}/{repo}/pages` was ever issued. GitHub **auto-enabled** a legacy
branch-source Pages site the moment the `gh-pages` orphan branch was pushed, and the
read-before-write found the resource already in the desired state:

```
source.branch = gh-pages      source.path = /      build_type = legacy      status = built
html_url      = https://indiagrams.github.io/ios-macos-smoketest/
```

So the manual step is **push the `gh-pages` orphan branch**; the settings write is not one a
person has to make. No file under `.github/workflows/` is involved — branch-source Pages
needs none. Re-checked 2026-09-11: both published pages return `http_code=200` with
`redirects=0`.

---

## 5. Steps a tool refused, or performed wrongly while reporting success

### 5.1 The screenshot lanes upload duplicates and exit 0 — `UL-076`

**This is the single most important screenshot instruction in this document.**

Measured three times on 2026-09-11 — twice on iOS, once on macOS, deterministic every time,
always the `-01-` and `-02-` of each device: **24 files uploaded, 30 assets held by Apple**,
`exit=0`, `Successfully uploaded all screenshots`, every asset `state=COMPLETE` with
`errors=[]`. **Apple refused nothing**; the defect is entirely client-side.

Mechanism, read in `deliver/lib/deliver/upload_screenshots.rb` of fastlane 2.238.0:
`verify_local_screenshots_are_uploaded` (`:216-241`) compares each local MD5 against
`source_file_checksum` and judges a file whose checksum has **not yet surfaced** to be
missing; `retry_upload_screenshots_if_needed` (`:194-216`) re-uploads it as a second copy;
the per-set counter then refuses the remaining files at the ten-image ceiling (`:129-140`) —
files that were already correct. The verdict was wrong when it was taken and right seconds
later.

**Therefore: never verify a screenshot upload by the lane's exit code.** Verify by
**counting what Apple holds**, per display type, and asserting the **distinct
`sourceFileChecksum` count equals the number of local files**:

```
GET /v1/appStoreVersions/{id}/appStoreVersionLocalizations
GET /v1/appStoreVersionLocalizations/{id}/appScreenshotSets
GET /v1/appScreenshotSets/{id}/appScreenshots?limit=50
```

Removing extra copies needs one `DELETE /v1/appScreenshots/{id}` per surplus asset, behind
an explicit allowlist and a live "never delete the last copy" precheck.

### 5.2 Re-running a screenshot lane **deletes the whole set first**

`overwrite_screenshots: true` is set in **both** lanes — the template's iOS lane and the
fork's macOS override in `fastlane/Fastfile.local`. `upload_screenshots.rb:32-34` calls
`delete_screenshots` **before** uploading anything, and it deletes whole **sets**.

That was harmless the first time, because the sets were empty. **It is not harmless now.**
Anyone re-running a lane to fix ONE image replaces all of them — observed directly on the
second run: `Deleted 'en-US APP_IPHONE_67'`, `Deleted 'en-US APP_IPAD_PRO_3GEN_129'`, and
the set ids changed. That is fastlane's normal replace idiom and is probably what you want;
it must not be something you discover.

### 5.3 `fastlane ios upload_screenshots` could never run — `UL-075`

The template's iOS screenshot lane passes `platform: :ios` — a Symbol — where `deliver`'s
option is declared without a type and so defaults to requiring a String. The lane dies in
**1.1 seconds**, at config-parse time, before any network call:

```
[!] 'platform' value must be a String! Found Symbol instead.
```

Every other `deliver` call site in the same file passes a String, including the lane's own
macOS twin forty-eight lines later. **`upstream/main` carries the identical pair**, so no
fork's iOS screenshot lane has ever worked. It is fixed here by an `override_lane` in
fork-owned `fastlane/Fastfile.local` changing exactly one token — but **upstream still
carries it**, and `ci/take-screenshots.sh`, `ci/bump-asc-version.sh` and `docs/SCREENSHOTS.md`
all still tell a reader to run the template lane.

### 5.4 `notes.txt` is **generated**. Never hand-edit it.

`fastlane/metadata/review_information/notes.txt` is produced by `tools/gen-review-notes.rb`
from the block delimited `id=core` in [REVIEW-ARGUMENTS.md](REVIEW-ARGUMENTS.md). Edit the
block, then regenerate:

```sh
ruby tools/gen-review-notes.rb
ruby tools/gen-review-notes.rb --check    # fails loudly if the two have drifted
```

A hand-edit is silently overwritten on the next generation, and `AGENTS.md` carries this as
a standing rule.

### 5.5 Running the macOS UI suite locally

Run `ci/take-screenshots.sh`, or reproduce **all** of what it does: a fresh derived-data
path, then `xattr -cr` **and** `codesign --force --deep --sign -` on the built runner, then
`xcodebuild test-without-building`. **The re-sign alone is measured to fail.**

Getting it wrong puts a *"damaged and can't be opened"* modal on a person's physical desktop.
**Cancel it. Never click "Move to Trash"** — that deletes the runner out of DerivedData, the
next build silently rebuilds it, and the failure then presents as intermittent.

---

## 6. BLOCKING BEFORE SUBMISSION

**These are not advisory. Each one is something this project measured honestly and
deliberately did not claim.**

### 6.1 The app icon is generated, not designed — **replace before submission**

**D-126. Guideline 2.3.8 (Accurate Metadata) cost upstream one full review cycle (`C-29`).**

The current 1024 artwork was drawn programmatically so the icon gates would stop being
dishonest, and they now pass: `ci/check-app-icon.sh` reports `spread 370` against a floor of
40, and `test/icon_set_test.rb` is 96 of 96. **A green gate is not a 2.3.8 verdict.** Spread
is a structural proxy that answers "is there more than one thing on this canvas"; it cannot
answer "does this look like a real product".

**The set is worse than the artwork, and this is the part that makes it blocking.**
`ci/gen-macos-icons.swift` marks every slot at or below 64 px `useHandDrawn: true` and, for
those, does not downsample the source at all — it draws the **template's** gauge motif from
scratch. Re-measured today by reading the pixels, not by trusting a log line:

| Slot | Pixels | Distinct colours | Greyscale | Verdict |
|---|---|---|---|---|
| `icon_32x32` at 2x | 64 | 89 | 89 | **monochrome — the template's gauge** |
| `icon_512x512` | 512 | 1888 | 3 | colour — this fork's pipeline mark |

**Two different marks for one app**, and the same split is inside the `AppIcon.icns` that
ships. Nothing in this repository can see it: the spread floor excludes everything under
128 px by design, and no check compares one slot's artwork to another's.

**What replacing it means:** regenerate with `make icons` — never hand-edit a slot, because a
hand-repaired slot regresses on the next regeneration — and the replacement must also resolve
the sub-128 mismatch, which needs an upstream change to `ci/gen-macos-icons.swift` (it should
downsample the source at small sizes too, or take the small mark as an input) or a deliberate
fork-owned override.

**The forcing point is PHASE 9, not Phase 10** — user decision, 2026-09-11. TestFlight shows
the icon to testers, and real artwork has human lead time.

Note also that `ci/check-app-icon.sh` is invoked on the **release** path only, so a
regression between now and submission is invisible to pull-request CI unless
`test/icon_set_test.rb` is running there.

### 6.2 PRIV-01 half (b) — one clean upload validation, still owed

**Amended into its current form by D-112; owed at Phase 9 or 10. Phase 8 does not claim it.**

Half (b) is exactly **one App Store Connect upload validation with no ITMS-91053 /
ITMS-91055 / ITMS-9105x privacy-manifest error**, taken before submission.

Four builds were uploaded on 2026-09-05 and are all `VALID`, and they **do not close it**.
Plan 08-02 measured that rather than reasoning about it, and its verdict is quoted here so
nobody re-derives it:

```
RESULT priv01-halfb builds=4 uploads_date=2026-09-05
       manifest_commit=cb8e6361362dd37b15f123aa6ff68ef3a30efa24
       manifest_date=2026-09-05T23:17:04-07:00
       carried_current_manifest=no closes_halfb=no
```

The commit that authored the `CA92.1` entry is dated **22 h 53 m after** the first upload, and
the phase that wrote it had not started. So the four builds validated cleanly against an
**empty** accessed-API array, which cannot produce the declaration-versus-binary disagreement
ITMS-9105x exists to catch. **PRIV-01 stays `Pending`.**

### 6.3 The single open iOS review slot is permanently occupied — `UL-018`

```
id 7972166e-3e8f-477a-bad4-2706898c4357   state READY_FOR_REVIEW   platform IOS
submittedDate null
```

Created by a Phase 2 probe and **irretirable**. Phases 9 and 10 meet it as a 409 and submit
**through** it. **Do not attempt to clear it.**

**Every App Store Connect session must hash `reviewSubmissions` by id before and after**, and
must assert that the **returned count equals `meta.paging.total` BEFORE hashing**, so a
silently truncated page cannot hash stable-and-wrong. The expected digest over the sorted
id list is:

```
2a715e9c3bf01c88ceb56487986e1a6a0965c826c8393fc55c01af7ea121596c
```

**One id of movement means stop.** Never create a review submission, never submit, and never
set `FORK_ALLOW_ASC_SUBMIT`.

### 6.4 The 4.3(b) premise has a live challenge — open `Blissum` before Phase 9

`Blissum` (`id6464085978`, Mac App Store, Developer Tools, free, v3.1.2 released
**2026-05-27**) advertises a named feature, verbatim: *"Chain Transformations: Process your
text, copy the output, and push it into another tool for further transformations—all through
intuitive keyboard commands."*

It shipped **three months before** this project's 2026-08-31 competitive sweep, **and the
sweep did not find it** — surfacing under that protocol's own search term. That is a
demonstrated false negative in the evidence behind a claim this project asserts to Apple.

[REVIEW-ARGUMENTS.md](REVIEW-ARGUMENTS.md) states that if a native App Store app makes the
chain the **primary work surface**, then *"the concept needs rethinking, not rewording"*. So
this is a blocking pre-submission gate, not a note:

1. **Open Blissum on a real Mac.** The protocol's own step 3 forbids treating listing copy as
   evidence, and the paragraph currently distinguishing Blissum is a listing read.
2. Answer one question: do intermediate values persist on screen, can a step be removed, can
   steps be reordered? Those three properties are the claim.
3. If yes — **narrow or withdraw the claim** before any build goes to testers.
4. Either way, give the `DevToys (macOS)` row an app id so it can be re-checked by id.

**User decision, 2026-09-11: this is a blocking input on Phase 9**, recorded there in the
roadmap, because settling it after TestFlight and after the listing is submitted means
rewriting a premise under submission pressure.

### 6.5 Pricing

See §2. It blocks App Store submission and it is not set.

---

## 7. What is automated — **do not do these by hand**

| Step | Done by | Notes |
|---|---|---|
| Listing copy, keywords, support and marketing URLs, per platform | `fastlane ios upload_metadata` and `fastlane mac upload_metadata` | Two trees: `fastlane/metadata/en-US/` and `fastlane/metadata-macos/en-US/` |
| App name, subtitle, privacy policy URL | the same lanes | **Shared** — one object, written once |
| Primary category | the same lanes | **Shared.** One primary, no secondary |
| The macOS divergence | `fastlane/Fastfile.local` | Four `override_lane`s on `platform :mac` plus one on `platform :ios`; the macOS ones pass an **absolute** path at the fork-owned macOS tree |
| Age rating questionnaire | `DELIVER_APP_RATING_CONFIG_PATH` pointing at `fastlane/age_rating.json` | Signed off 2026-09-11 as `route=approve`; 28 answers. **One shared object — run it once, for one platform only.** Pass the path **absolute** |
| Export compliance | already answered on three surfaces | Genuinely per-build; all four existing builds carry `usesNonExemptEncryption: false` |
| Screenshots | `fastlane ios upload_screenshots` / `fastlane mac upload_screenshots` | **But verify by counting what Apple holds — see §5.1** |
| `notes.txt` | `ruby tools/gen-review-notes.rb` | See §5.4 |

**`releaseType` is `MANUAL` on both versions**, re-read 2026-09-11. Both screenshot and
metadata lanes pass `automatic_release: false`, which `deliver` maps to `MANUAL` and sends on
every version PATCH. **Somebody must click release. An approved version will not go live by
itself.**

---

## 8. What IS done — re-read 2026-09-11, not inherited

Every value below was read back from the live record on the date above with a GET-only
client, not copied out of a planning document.

| Fact | Value |
|---|---|
| `appInfos` total | 1 — `2b0a2b50-1b4a-46d3-b888-03be64184aad` |
| `primaryCategory` | `DEVELOPER_TOOLS` · `secondaryCategory` `null` |
| `appStoreAgeRating` | **`FOUR_PLUS`** — Apple's **computed** value, read back rather than predicted |
| Brazil | `brazilAgeRating` `L`, `brazilAgeRatingV2` `SELF_RATED_L` |
| Shared listing | `name` "Shipkit Pipes", `subtitle` "Offline text tools that chain", privacy policy URL set |
| `appStoreVersions` | 2 — IOS and MAC_OS, both `1.0`, both `PREPARE_FOR_SUBMISSION`, both `releaseType` `MANUAL` |
| iOS localization | description 1413 chars, keywords 93 chars, support URL set |
| macOS localization | description 1755 chars, keywords 88 chars, support URL set — **a different description from iOS**, which is D-121 |
| Screenshots | **24 assets in 3 sets, 8 + 8 + 8, every checksum distinct**, all `COMPLETE`, `errors=[]` |
| Display types | `APP_IPHONE_67`, `APP_IPAD_PRO_3GEN_129`, `APP_DESKTOP` |
| Published pages | privacy and support both `200`, `redirects=0` |
| `whatsNew` | `null` on both, correctly — `deliver` refuses release notes on a platform's first version |

**A caution on re-checking the age rating.** `appStoreAgeRating` is published on the
**`appInfo`** resource. Reading `/v1/appInfos/{id}/ageRatingDeclaration` on its own returns
`null` for it, which looks exactly like "unanswered" and is not. Re-check with:

```sh
# reads the computed band from the resource that actually carries it
GET /v1/apps/6807393045/appInfos?limit=10        -> data[0].attributes.appStoreAgeRating
```

---

## 9. Known gaps in the checks that guard this document

**Recorded rather than closed, because a known hole is cheaper than a false sense of one
being covered.**

1. **The contact-address sweep does not cover this file.** `test/docs_structure_test.rb`
   sweeps `ALL_DOCS` — exactly five fork-owned documents — and a new document is not in that
   population (D-115). This is *a correct check pointed at the wrong population*, which is
   this project's recurring failure shape. Until the population is widened from more than one
   source, **sweep any edit to this file by hand** and keep referring to the App Review
   contact by file path. The tree-wide address rule in `tools/check-contamination.rb` does
   reach this file and is the backstop, not the primary.
2. **`AppMacOSUITests/PrivacyLinkTests` does not execute.** It ends in
   `throw XCTSkip("macOS launch-pinning does not present the surface …")` because macOS uses
   `NavigationSplitView` where iOS uses `TabView`, so the launch pin does not select the
   destination — 5/5 at `awaitSurface`, 2026-09-11. Status: **`PENDING-CI executed=none`**.
   **Owner: Phase 8.5.** The in-app privacy route is proven on iOS and unproven on macOS.

---

## 10. Performed log

| Date | Step | Outcome |
|---|---|---|
| 2026-09-11 | GitHub Pages site for the privacy and support pages | Live — branch source `gh-pages`, path `/`, `build_type` legacy, both pages `200` |
| 2026-09-11 | Age-rating sign-off | `route=approve`, band 4+; delivered by lane, confirmed by Apple's computed `FOUR_PLUS` |
| 2026-09-11 | Shared and per-platform listing metadata, category | Written by the two `upload_metadata` lanes and read back field by field |
| 2026-09-11 | Screenshots, both platforms | 24 assets in 3 sets; six surplus copies from `UL-076` removed and the sets re-counted |
| 2026-09-11 | App Privacy API surface re-confirmed absent | Two 404s and a 41-relationship enumeration; `app_privacy_api=absent` |
| 2026-09-11 | **App Privacy answers published** | **DONE.** Data Not Collected, saved and **Published** by the account holder in App Store Connect. Confirmation read back verbatim: *"Published a few seconds ago by [account holder]"* — the name is replaced by a role here deliberately; this file carries no personal information (§9.1's sweep would fail on it, and it is a public repository). **This row is an ATTESTATION, not a measurement:** no tool can verify it. The App Privacy API does not exist — two 404s plus an enumeration of all 41 relationships the app resource publishes, none matching privacy, dataUsage or nutrition — and `make doctor` step 18 hits the same removed relationship, so it reports a broken probe rather than an unpublished state. It is a second witness to the absence, never an independent check. |
| — | **Price schedule** | **NOT PERFORMED — see §2** |
| — | **App Review contact details** | **NOT PERFORMED — see §3** |
