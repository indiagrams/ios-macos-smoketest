# Apple account state

## Why this exists

This is the durable, tracked record of the Apple account facts this project's release
path depends on: how the team is enrolled, which agreements are in effect, what the App
Store Connect API key is, and which signing certificates the shared team is actually
carrying. The reasoning behind each measurement — the alternatives weighed, the sources
read — lives in this project's planning notes, which are gitignored and do not survive a
fresh clone, a new checkout, or a refork. This file does survive, and it is what the
pre-submission checklist in Phase 9 and Phase 10 reads before anything is sent to Apple.

**This file is account operations state, not product identity.** The trader-status
*evidence* lives in [PRODUCT-IDENTITY.md](PRODUCT-IDENTITY.md) per D-38, because it is a
fact about who ships the app and it appears on the public product page; what this file
carries is the account-level declaration as three dated fact rows, read off the same
Business page as the agreements beside it. Everything recorded here moves on a
different cadence (R-08): identity changes approximately never, while certificate
occupancy changes on every release run and is mutated weekly by the Saturday canary.
Splitting them keeps a fast-moving measurement out of a document whose whole value is
that it is stable.

**Nothing here is a prediction.** Every row is something that was looked at, on a date,
against a named team or key or record. Where a value has not been measured yet, the row
says so in the `Measured` column and names the plan that will fill it. A blank is not a
zero and a pending row is not a pass.

**No personal information is recorded here, and none may be added.** The App Store
Connect Business page displays postal and financial details for the organization, its
filing state with Apple, and an app-transfer record naming an individual. None of that is
needed by any requirement this file serves, and it is not written down. That is not left
to care: `test/docs_structure_test.rb` sweeps every fork-owned document, this one
included, for contact-address-shaped strings.

## How to read a row

Every fact table below carries the same six columns, in this order:

```
| Fact | Value | Measured (ISO-8601) | Against (team / key / record id) | Valid until | Re-check command |
```

**A bare value is a future defect.** The `Against` column exists because of a defect this
project already has: `.github/workflows/release.yml` carries certificate-capacity figures
that were measured against a completely different Apple team, and nothing in that file
says so. A reader has no way to tell a number that applies from a number that was copied
forward, so the number goes quietly wrong and stays wrong (C-05). A value, its
measurement date, and the thing it was measured against are one unit; recording two of
the three records nothing.

The `Measured` cell is either an ISO-8601 date or the literal `pending NN-NN` naming the
plan that will measure it. The `Valid until` cell is either an ISO-8601 date or one of the
window tokens defined in [Staleness contract](#staleness-contract). Both forms are
asserted structurally by `test/docs_structure_test.rb`; a row added without a date and
without a target fails CI rather than sitting here looking plausible.

**Commands in this file are written to be pasted.** Any `gh` invocation carries
`--repo indiagrams/ios-macos-smoketest` explicitly, because this working copy has an
`upstream` remote and no default repository set, so a bare invocation resolves against
`indiagrams/apple-shipkit` instead — a different repository, whose answers would be
wrong in a way that looks like an answer.

**Any `tools/asc-probe.rb` row carries the pinned bundle in full.** `ruby tools/asc-probe.rb`
cannot make a live call at all: spaceship is not loadable outside the bundle, and the probe
refuses with a message naming the correct command rather than failing quietly. A bare
`bundle exec` is the worse of the two — brew's unversioned Ruby is 4.0.x and resolves a
`vendor/bundle/ruby/4.0.0` that does not exist, so it dies in `Bundler::GemNotFound` with
nothing to say about why. Both were hit on 2026-09-01 while re-checking the App ID rows
below, which is why those rows now spell out
`/opt/homebrew/opt/ruby@3.3/bin/bundle exec ruby tools/asc-probe.rb ...`.

The remaining `pending 02-09` rows still carry the short forms. They are placeholders for
measurements that have not been taken, and the plan that takes each one writes its real
re-check command then; correcting a command for a row whose value is an em dash would be
tidying a cell nobody can run yet. Named here rather than left to be rediscovered. The
certificate-census rows were placeholders of the same kind until 02-10 measured them, and
they now carry the pinned form.

**A `|` inside a cell is written `\|`, and that is not cosmetic.** GitHub breaks a table
cell on a bare pipe even inside a code span, so a re-check command containing a Ruby block
parameter renders with its command chopped across three columns and the parameter eaten —
the command in the rendered page is then not the command anyone can run. Two rows in the
app-record table were in exactly that state until 2026-09-01. The structural guard did not
catch them because it split rows on every pipe, which made its own parser agree with the
defect: the rows parsed as eight cells, only cells 0..3 were ever asserted on, and the
header assertion vouched for the header rather than for the rows beneath it. The guard now
splits on unescaped pipes and asserts every fact row is exactly six cells wide; it was
watched failing on both rows before they were fixed. **Copying a command out of the raw
source needs the `\` dropped**; copying it out of the rendered page does not, and the
rendered page is what these rows are for.

## Apple Developer Program and account

| Fact | Value | Measured (ISO-8601) | Against (team / key / record id) | Valid until | Re-check command |
|---|---|---|---|---|---|
| Team id | `G5H628C6WR` | 2026-09-01 | team `G5H628C6WR` | per phase | `grep FASTLANE_TEAM_ID .bootstrap.env` |
| Enrollment type | `organization` — `Indiagram LLC` | 2026-09-01 | team `G5H628C6WR` | per phase | App Store Connect, Business, Account Information |
| Account holder access | `Account Holder + Admin` | 2026-09-01 | team `G5H628C6WR` | per phase | App Store Connect, Users and Access, People |
| Paid Apps Agreement | `Active` — `May 17, 2026 – May 16, 2027` | 2026-09-01 | team `G5H628C6WR` | 2027-05-16 | `ruby bin/verify-asc-agreements.rb` |
| Free Apps Agreement | `Active` — `Aug 26, 2026 – May 16, 2027` | 2026-09-01 | team `G5H628C6WR` | 2027-05-16 | `ruby bin/verify-asc-agreements.rb` |
| EU DSA trader declaration, account level | `Active` — displayed with `Digital Services Act`, `27 Countries or Regions`, a `View` link, and `May 17, 2026`. The literal status string is `Active`; neither of the two state labels the inherited guidance predicted was on screen, and neither has a first-party source (R-06) | 2026-09-01 | team `G5H628C6WR` | per submission | App Store Connect, Business, Agreements, Compliance, Digital Services Act |
| EU DSA trader dialog options | Both read verbatim off the `Digital Services Act Compliance` dialog: `I'm a trader under the DSA`, radio filled, and `I'm not a trader under the DSA or I don't plan to distribute in the EU`. Apple's documented wording for this choice matches neither. Read only — `Next` was not clicked and no selection was changed | 2026-09-01 | team `G5H628C6WR` | per submission | App Store Connect, Business, Agreements, Compliance, Digital Services Act, Edit |
| EU DSA trader contact publication | Declaring as a trader publishes an address, a phone number and an email address on the App Store product page, display-only and without altering any Apple account's own contact details — stated by the selected option's sub-text. **No such value is recorded in this repository**, and this row records only that the publication happens | 2026-09-01 | team `G5H628C6WR` | per submission | App Store Connect, Business, Agreements, Compliance, Digital Services Act, Edit |

**Three trader-status rows live here, and the rest lives in PRODUCT-IDENTITY.md.** D-38
puts the trader-status evidence — the per-app declaration on record `6807393045`, the
Universal Purchase seam, and the D-37 exit condition — in
[PRODUCT-IDENTITY.md](PRODUCT-IDENTITY.md), because it is a fact about who ships the app.
What belongs *here* is the account-level half: it is read off the same Business, Agreements,
Compliance page as the two agreement rows above it, on the same visit, and it is what the
pre-submission checklist needs in the file it already opens. The [Staleness
contract](#staleness-contract) has named `per submission` as trader status's window since
this file was created, and until now that window governed no row in it. It governs these
three.

**Both agreements end on the same day: `May 16, 2027`.** ACCT-04 as amended (R-09, D-41)
asks for the expiries that genuinely exist rather than an invented one for the API key,
and these are they. Apple gates the entire App Store Connect API behind an in-effect
agreement, so an agreement that lapses does not degrade the release path, it stops it
account-wide — which is why the re-check is a preflight script rather than a calendar
reminder.

**The enrollment type is load-bearing for trader status.** An organization enrollment has
its trader details auto-populated from the organization record, so the individual-
enrollment document-upload path does not apply here (A3). Recording the enrollment type is
what lets a later reader tell that the shorter path was correct rather than merely
convenient.

## ASC API key

| Fact | Value | Measured (ISO-8601) | Against (team / key / record id) | Valid until | Re-check command |
|---|---|---|---|---|---|
| Key id | `SCH57C86HT` | 2026-09-01 | team `G5H628C6WR` | per phase | `grep ASC_API_KEY_ID .bootstrap.env` |
| Key kind | `Team key` | 2026-09-01 | key `SCH57C86HT` | per phase | App Store Connect, Users and Access, Integrations, Team Keys |
| Key expiry | `no expiry` — `Active until revoked` | 2026-09-01 | key `SCH57C86HT` | per phase | Apple key-management documentation, re-read per phase |
| `POST /v1/bundleIds`, as exercised | `App Manager` key `SCH57C86HT` sufficient for `POST /v1/bundleIds` — observed 2026-09-01 against team `G5H628C6WR`. The justification is Apple's own response: both creates returned a record with an Apple-assigned id and no refusal text. The role string is metadata and is never the proof (D-40). Claims nothing about certificates (02-10) or submission (02-09) | 2026-09-01 | key `SCH57C86HT` against team `G5H628C6WR` | per phase | `/opt/homebrew/opt/ruby@3.3/bin/bundle exec fastlane register_app_id platform:ios` with `BUNDLE_ID` overridden |
| Access role, as exercised | — | pending 02-09 | — | — | `ruby tools/asc-probe.rb probe-compare --primary <f> --control <f>` |
| Upload path exercised | — | pending 02-09 | — | — | `ruby tools/asc-probe.rb read-back app --bundle-id <id> --expect-platform <p>` |
| Submission path exercised | `POST /v1/reviewSubmissions` accepted: `201 Created`, creating container `7972166e-3e8f-477a-bad4-2706898c4357` on app `6807393045`. **This is an observation, not proof that the key's role permits submission.** The Developer-role control was never run — see the `Access role, as exercised` row, still pending — so one uncontrolled `201` cannot separate a key that may submit from an endpoint that accepts the create regardless of role, which is what D-40 forbids treating as evidence. **The write must not be re-run.** It is irreversible by every API route (UL-018): the container allows no `DELETE`, and a cancel is refused while it is unsubmitted, so each run permanently consumes one of the one-open-submission-per-app-and-platform slots. The container above is still open and no sanctioned route retires it. | 2026-09-01 | app `6807393045`, key `SCH57C86HT`, team `G5H628C6WR` | per phase | read-only: `GET /v1/apps/6807393045/reviewSubmissions` and confirm the container's `state`. Never re-run `submission-probe` against a record whose submission slot is free (UL-018) |

**The key has no expiry, and that is a verified negative claim rather than an omission.**
Apple's key-creation page, its key-revocation reference, and the App Store Connect help
page all describe a key as active until it is revoked, and none of the three mentions an
expiration date for the key itself. All three were fetched and read in full on
2026-09-01 (K-4). ACCT-04's original wording asked for a key expiry to be recorded;
writing a plausible date there would have been the worse failure, so the requirement was
amended rather than silently reinterpreted (R-09, D-41).

**A key's access level cannot be edited after it is generated.** Remediation is not a
settings change: it means generating a new key and rotating three values in two places —
`ASC_API_KEY_ID`, `ASC_API_KEY_ISSUER_ID`, and the `.p8` itself, in both `.bootstrap.env`
and the repository's Actions secrets (K-3). The old key stays valid during the switch, and
revocation is irreversible, so the replacement is proven working before anything is
revoked. That is why an insufficient key is a one-way door and belongs to this phase.

**The role rows stay pending on purpose.** A role string was displayed for this key in the
App Store Connect interface during Phase 2 planning on 2026-09-01, and it is recorded in
the phase's planning notes as metadata. It is deliberately not a fact row here, and it is
never proof: D-40 and D-42 both turn on establishing sufficiency by exercising the upload
path and the submission path and observing what Apple actually returns. Reading a role
label and concluding sufficiency is the inference-from-a-name pattern that cost Phase 1
twice. 02-09 exercises both paths and fills these rows with what it saw.

## App IDs

| Fact | Value | Measured (ISO-8601) | Against (team / key / record id) | Valid until | Re-check command |
|---|---|---|---|---|---|
| `com.indiagram.shipkitpipes.ios` App ID | Registered — `id=9ZZGBGJBRQ`, name `Shipkit Pipes iOS`. Requested `platform: IOS`; **Apple stores `UNIVERSAL`** | 2026-09-01 | team `G5H628C6WR` | per phase | `/opt/homebrew/opt/ruby@3.3/bin/bundle exec ruby tools/asc-probe.rb read-back bundle-id --identifier com.indiagram.shipkitpipes.ios --expect-platform IOS` |
| `com.indiagram.shipkitpipes.macos` App ID | Registered — `id=KPNQ2D3B8A`, name `Shipkit Pipes macOS`. Requested `platform: MAC_OS`; **Apple stores `UNIVERSAL`** | 2026-09-01 | team `G5H628C6WR` | per phase | `/opt/homebrew/opt/ruby@3.3/bin/bundle exec ruby tools/asc-probe.rb read-back bundle-id --identifier com.indiagram.shipkitpipes.macos --expect-platform MAC_OS` |
| `com.indiagram.smokeapp` App ID (pre-existing) | Present, `id=TP38APY79P`, platform `UNIVERSAL`. Deliberately not deleted — Apple does not allow deleting an App ID that has ever been used | 2026-09-01 | team `G5H628C6WR` | per phase | `/opt/homebrew/opt/ruby@3.3/bin/bundle exec ruby tools/asc-probe.rb read-back bundle-id --identifier com.indiagram.smokeapp --expect-platform IOS` |
| Both App IDs confirmed in the Developer portal | Seen by the account holder in Certificates, Identifiers and Profiles, Identifiers: `com.indiagram.shipkitpipes.ios` and `com.indiagram.shipkitpipes.macos` both present. Exactly the two intended identifiers were created by these runs — no third. `com.indiagram.smokeapp` still present and untouched | 2026-09-01 | team `G5H628C6WR` | per phase | Apple Developer portal, Certificates, Identifiers and Profiles, Identifiers |
| Universal Purchase | **Adopted** — one app record (`6807393045`) serves both platforms from the single bundle ID `com.indiagram.shipkitpipes.ios` (D-44, reversing D-05). The earlier value of this row read "Declined and executed — two App IDs registered as two independent records"; that was true of the App IDs and never became true of the app records, because the second record could not be created. `com.indiagram.shipkitpipes.macos` remains a registered App ID with no app record against it | 2026-09-01 | team `G5H628C6WR` | per phase | `grep -n 'Universal Purchase' docs/PRODUCT-IDENTITY.md` |

### Apple stores `UNIVERSAL` for every App ID in this team, whatever platform was requested

Both App IDs above were created on 2026-09-01 through `fastlane register_app_id`, one with
`platform: ios` and one with `platform: macos`, which reach
`Spaceship::ConnectAPI::BundleIdPlatform::IOS` and `::MAC_OS` respectively. Both create calls
succeeded. **Both then read back from `GET /v1/bundleIds` with `platform` = `UNIVERSAL`**, and so
does the pre-existing `com.indiagram.smokeapp`, which was registered long before this phase.

This is a fact about Apple, not about the instrument, and it was checked as such before being
written down. Two independent code paths agree: `tools/asc-probe.rb`, which parses the raw
`GET /v1/bundleIds` JSON, and a direct `Spaceship::ConnectAPI::BundleId.all` call, which goes
through fastlane's own object mapping. In the probe run, the `identifier` comparison passed while
the `platform` comparison failed on the same record — so the right record was fetched and the
comparator does discriminate between fields.

Consequences, stated no more strongly than the observation supports:

- **The read-back assertions in this table exit 1, by design, and have been left that way.** There
  is no `--expect-platform UNIVERSAL`: `tools/asc-probe.rb` rejects it at argument validation
  (C-02), because spaceship's enum exposes only `IOS` and `MAC_OS`. Widening that enum to make the
  command exit 0 would be rewriting a correct assertion to match a surprising result, which
  destroys the only evidence the assertion was ever carrying. Paste the command and read the
  `got "UNIVERSAL"` line; that line is the measurement.
- **`platform` is not a usable discriminator between these two App IDs.** What distinguishes them
  is the identifier, which is what every downstream lane passes as `app_identifier` anyway.
- This is consistent with F-10 — since Xcode 11.4 a single App ID can build iOS, macOS, tvOS and
  watchOS apps — but F-10 is a statement about capability, and this is a statement about a stored
  field. They are recorded as two separate things.
- **Open question, deliberately not resolved by guessing:** whether Apple ignored the requested
  `platform` at create time, or accepted it and normalised the record to `UNIVERSAL` afterwards,
  cannot be told apart from a read-back. `register_app_id`'s success message interpolates the
  *requested* value rather than the response, so it is not evidence either way. Settling it would
  mean creating a third App ID purely to watch the create response, and an App ID that has ever
  been used cannot be reclaimed (T-02-32), so it was not done.

## App Store Connect app record

| Fact | Value | Measured (ISO-8601) | Against (team / key / record id) | Valid until | Re-check command |
|---|---|---|---|---|---|
| App record id | `6807393045` — the only app record this project owns | 2026-09-01 | record `6807393045` on team `G5H628C6WR` | per phase | `/opt/homebrew/opt/ruby@3.3/bin/bundle exec ruby tools/asc-probe.rb read-back app --bundle-id com.indiagram.shipkitpipes.ios --expect-sku shipkitpipes-ios-001 --expect-locale en-US --expect-name 'Shipkit Pipes'` |
| App record `name` | `Shipkit Pipes` — accepted by App Store Connect at creation | 2026-09-01 | record `6807393045` | per phase | `/opt/homebrew/opt/ruby@3.3/bin/bundle exec ruby tools/asc-probe.rb read-back app --bundle-id com.indiagram.shipkitpipes.ios --expect-sku shipkitpipes-ios-001 --expect-locale en-US --expect-name 'Shipkit Pipes'` |
| App record `sku` | `shipkitpipes-ios-001` — matches D-31 character for character. **Permanent**: cannot be changed, and cannot be reused in this organization even if the record is removed | 2026-09-01 | record `6807393045` | per phase | `/opt/homebrew/opt/ruby@3.3/bin/bundle exec ruby tools/asc-probe.rb read-back app --bundle-id com.indiagram.shipkitpipes.ios --expect-sku shipkitpipes-ios-001 --expect-locale en-US --expect-name 'Shipkit Pipes'` |
| App record `primaryLocale` | `en-US` — set explicitly per D-32 rather than relying on the documented default | 2026-09-01 | record `6807393045` | per phase | `/opt/homebrew/opt/ruby@3.3/bin/bundle exec ruby tools/asc-probe.rb read-back app --bundle-id com.indiagram.shipkitpipes.ios --expect-sku shipkitpipes-ios-001 --expect-locale en-US --expect-name 'Shipkit Pipes'` |
| App record `bundleId` | `com.indiagram.shipkitpipes.ios` — shared by both platforms under Universal Purchase | 2026-09-01 | record `6807393045` | per phase | `/opt/homebrew/opt/ruby@3.3/bin/bundle exec ruby tools/asc-probe.rb read-back app --bundle-id com.indiagram.shipkitpipes.ios --expect-sku shipkitpipes-ios-001 --expect-locale en-US --expect-name 'Shipkit Pipes'` |
| `appStoreVersions` on the record | Two: `platform=IOS state=PREPARE_FOR_SUBMISSION version=1.0` and `platform=MAC_OS state=PREPARE_FOR_SUBMISSION version=1.0`. Both platforms live on the one record, and each can be submitted independently | 2026-09-01 | record `6807393045` | per phase | `/opt/homebrew/opt/ruby@3.3/bin/bundle exec ruby -e 'require "spaceship"; Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.create(key_id: ENV["ASC_API_KEY_ID"], issuer_id: ENV["ASC_API_KEY_ISSUER_ID"], key: Base64.decode64(ENV["ASC_API_KEY_P8_BASE64"])); Spaceship::ConnectAPI.get_app_store_versions(app_id: "6807393045").to_models.each { \|v\| puts "#{v.platform} #{v.app_store_state} #{v.version_string}" }'` |
| App records named `Shipkit Pipes` on this team | Exactly one. Enumerated all five app records on the team; no second `Shipkit Pipes` and no record against `com.indiagram.shipkitpipes.macos` | 2026-09-01 | team `G5H628C6WR` | per phase | `/opt/homebrew/opt/ruby@3.3/bin/bundle exec ruby -e 'require "spaceship"; Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.create(key_id: ENV["ASC_API_KEY_ID"], issuer_id: ENV["ASC_API_KEY_ISSUER_ID"], key: Base64.decode64(ENV["ASC_API_KEY_P8_BASE64"])); puts Spaceship::ConnectAPI::App.all.map { \|a\| "#{a.id} #{a.name}" }'` |
| `com.indiagram.shipkitpipes.macos` app record | **None, permanently and by design.** The App ID `KPNQ2D3B8A` stays registered; no app record was ever created against it and none will be. A `read-back app` for this identifier exits `2` — that is the correct result under Universal Purchase, not a defect | 2026-09-01 | team `G5H628C6WR` | per phase | `/opt/homebrew/opt/ruby@3.3/bin/bundle exec ruby tools/asc-probe.rb read-back app --bundle-id com.indiagram.shipkitpipes.macos --expect-sku shipkitpipes-macos-001` |
| SKU `shipkitpipes-macos-001` | Never consumed. D-31 reserved it for the second record that was never created; it is not attached to anything at Apple | 2026-09-01 | team `G5H628C6WR` | per phase | Absent from the `App.all` enumeration above |
| App Store name uniqueness scope | **Account-scoped, not merely store-wide.** Two app records in one account cannot carry the same name. Observed by Apple refusing the second record, not read from documentation | 2026-09-01 | team `G5H628C6WR` | per phase | Apple returns the refusal only at record creation; there is no query endpoint |
| Field mutability at record creation | `sku` **permanent** — "You can't change the SKU after you add the app to your account". `bundleId` frozen at **first upload**, not at creation — "You can't change this property after you upload a build". `name` editable **until the app is submitted to App Review**. `primaryLocale` editable **at any time** — "You can change the primary language at any time" | 2026-09-01 | record `6807393045` | per phase | [Apple: add an app to your account](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app) |

### Only two moments here are irreversible, and record creation is not one of them

Creating the record feels like the one-way door, and mostly it is not. Of the four fields
set at creation, three have a correction path: the name can be changed until the app is
submitted for review, the primary language can be changed at any time, and the bundle ID
is not frozen until the first build is uploaded. What genuinely cannot be undone is the
**SKU string**, which is permanent and whose value cannot be reissued in this organization
even if the record is deleted, and the **first upload**, which is what freezes the bundle
ID. Phases 8, 9 and 10 should place their caution accordingly: the risk is not in having
created the record, it is in the SKU that was typed and in the first binary that is sent.

### The read-back is a working instrument, which is newly demonstrable

Before this record existed, every identifier returned exit `2`, so a not-found control
proved nothing — it could not be distinguished from a probe that returned `2`
unconditionally. Now that one real record exists, the same instrument was observed
producing all three of its documented outcomes against live data on 2026-09-01:

```
exit 0  read-back app --bundle-id com.indiagram.shipkitpipes.ios \
          --expect-sku shipkitpipes-ios-001 --expect-locale en-US \
          --expect-name 'Shipkit Pipes'
        the record is found and every assertion holds

exit 2  read-back app --bundle-id com.indiagram.definitely-not-a-real-app-zzz9 \
          --expect-sku shipkitpipes-ios-001
        absence is detected rather than passed over

exit 1  read-back app --bundle-id com.indiagram.shipkitpipes.ios \
          --expect-sku shipkitpipes-ios-999
        the SKU assertion actually executes, and says so:
        asc-probe: expected sku="shipkitpipes-ios-999", got "shipkitpipes-ios-001"
```

That block is deliberately fenced rather than tabulated. `test/docs_structure_test.rb`
parses every markdown table inside a fact section and requires each row to carry a
measurement date and a target, so a three-column illustration in this section is read as
a malformed fact row and fails the suite. It did, while this section was being written.
The same shape is UL-010's, and the fix is the one this file already uses for the example
header row in [How to read a row](#how-to-read-a-row): put prose tables in a fence, and
leave the pipes to the facts.

**The bogus identifier is deliberately not `com.indiagram.shipkitpipes.macos`.** That one
also returns `2`, but it returns `2` for a reason that changed during this phase — it is
now correctly absent under Universal Purchase. A control that passes for a changed reason
is not a control, so a string that has never existed and never will is used instead.

## Certificate census

| Fact | Value | Measured (ISO-8601) | Against (team / key / record id) | Valid until | Re-check command |
|---|---|---|---|---|---|
| `DEVELOPMENT` occupancy | One certificate. `id=2VJC2RHG62`, display name `Created via API`, expires `2027-05-24T05:30:41Z` | 2026-09-01 | team `G5H628C6WR` | 2026-09-08 | `/opt/homebrew/opt/ruby@3.3/bin/bundle exec ruby tools/asc-probe.rb census --out /tmp/census.json` |
| `DISTRIBUTION` occupancy | One certificate. `id=6B8BWZ4B4X`, display name `Indiagram LLC`, expires `2027-05-24T05:14:35Z` | 2026-09-01 | team `G5H628C6WR` | 2026-09-08 | `/opt/homebrew/opt/ruby@3.3/bin/bundle exec ruby tools/asc-probe.rb census --out /tmp/census.json` |
| `MAC_INSTALLER_DISTRIBUTION` occupancy | One certificate. `id=BRDTBXL68H`, display name `Indiagram LLC`, expires `2027-08-27T16:21:36Z` | 2026-09-01 | team `G5H628C6WR` | 2026-09-08 | `/opt/homebrew/opt/ruby@3.3/bin/bundle exec ruby tools/asc-probe.rb census --out /tmp/census.json` |
| Certificate types beyond those three | **None.** The census enumerates every certificate on the team, not only the release types, and nothing outside `DEVELOPMENT`, `DISTRIBUTION` and `MAC_INSTALLER_DISTRIBUTION` came back. Total occupancy across all types therefore equals the sum of the rows above | 2026-09-01 | team `G5H628C6WR` | 2026-09-08 | `/opt/homebrew/opt/ruby@3.3/bin/bundle exec ruby tools/asc-probe.rb census --out /tmp/census.json` |
| `DISTRIBUTION` mint attempted | One, on the safe default. Command: `/opt/homebrew/opt/ruby@3.3/bin/bundle exec fastlane mint_local_certs types:apple_distribution`. No `--force`; the action's own summary table printed its `force` value as `false`, and `CERT_FORCE` was unset in the environment | 2026-09-01 | team `G5H628C6WR` | 2026-09-08 | Re-running mints again — do not re-run to re-check; read the census rows instead |
| Outcome of that mint | **`REUSED`, not `CREATED`.** The lane exited `0`, but the before and after censuses carry an identical id set, so no `POST /v1/certificates` was made. fastlane said, verbatim: *"Found the certificate 6B8BWZ4B4X (Indiagram LLC) which is installed on the local machine. Using this one."* | 2026-09-01 | team `G5H628C6WR` | 2026-09-08 | `/opt/homebrew/opt/ruby@3.3/bin/bundle exec ruby tools/asc-probe.rb census --out /tmp/census.json` before and after, then `census-diff` |
| ACCT-04b — key sufficiency on the **distribution** path | **UNPROVEN.** The mint reused a local certificate and never reached Apple's create endpoint, so the key's authority to create a distribution certificate was not exercised and remains unknown. Not a failure and not a pass — an untaken measurement | 2026-09-01 | key `SCH57C86HT` against team `G5H628C6WR` | per phase | Only a mint that actually creates can settle this; see the reuse trap below |
| Nothing was revoked (ACCT-05b) | Asserted, not assumed. `census-diff` over the before and after censuses exited `0`: three certificates before, three after, no id absent from the second | 2026-09-01 | team `G5H628C6WR` | 2026-09-08 | `/opt/homebrew/opt/ruby@3.3/bin/bundle exec ruby tools/asc-probe.rb census-diff --before <before> --after <after>` |
| Post-mint occupancy | Unchanged from the rows above, re-measured rather than predicted: one certificate of each of the three release types, same three ids | 2026-09-01 | team `G5H628C6WR` | 2026-09-08 | `/opt/homebrew/opt/ruby@3.3/bin/bundle exec ruby tools/asc-probe.rb census --out /tmp/census.json` |
| Decision taken on that result (02-10 Task 3) | **`record-only`.** Nothing was minted, revoked, forced or removed. All three routes that would have compelled a real create were declined: passing `--force`, deleting the local identity so the reuse check finds nothing, and minting the two types not yet attempted. It is recorded as a decision with its reasoning, not as an omission — see [Why no mint still available can settle ACCT-04b](#why-no-mint-still-available-can-settle-acct-04b) | 2026-09-01 | team `G5H628C6WR` | per phase | Not a measurement and not re-runnable; the occupancy row below is what re-checks |
| Whether any mint still available could settle ACCT-04b | **No.** For team `G5H628C6WR` the login keychain already holds a valid `Apple Distribution` identity and a `3rd Party Mac Developer Installer` certificate, so a mint of either distribution-family type reuses and never reaches Apple. It holds no `Apple Development` identity for this team, so that one type would genuinely create — but `DEVELOPMENT` is not the permission ACCT-04b asks about. Read-only reading; nothing was added to or removed from the keychain | 2026-09-01 | login keychain against team `G5H628C6WR` | 2026-09-08 | `security find-identity -v \| grep G5H628C6WR` and the same with `-p codesigning`; the two lists differ, and both matter |
| Capacity, per type | **Unobserved for all three types**, `DISTRIBUTION` included — its mint reused rather than created, so no create attempt has ever been made against this team by this project. Nothing numeric is recorded here because nothing numeric was measured; the rows above carry occupancy, which is a different quantity | 2026-09-01 | team `G5H628C6WR` | 2026-09-08 | Only an attempted create can observe it, and attempting one consumes a slot on a team shared with another shipping product — a human decision, not a re-check |
| Post-decision occupancy, re-measured rather than predicted | Unchanged: one certificate of each of the three release types, the same three ids. Taken at `2026-09-01T18:11:07Z`, after the decision rather than before it, and `census-diff` against the pre-mint baseline exited `0` — no id absent, none added | 2026-09-01 | team `G5H628C6WR` | 2026-09-08 | `/opt/homebrew/opt/ruby@3.3/bin/bundle exec ruby tools/asc-probe.rb census --out /tmp/census.json`, then `census-diff` against the previous census |
| ACCT-05 — the certificate criterion as a whole | **Not met in full, and deliberately not marked complete.** Occupancy is measured and dated, nothing was revoked, and every unproven type is stated as such — but the criterion also asks for a mint attempted for the types the release lane needs, and only `DISTRIBUTION` was attempted. `DEVELOPMENT` and `MAC_INSTALLER_DISTRIBUTION` were never attempted at all | 2026-09-01 | team `G5H628C6WR` | per phase | Closing it means attempting those two mints, each of which consumes a slot on a shared team |
| ACCT-04 — both halves | **OPEN.** The submission half was abandoned during 02-09 with no sufficiency verdict reached (ledger row UL-018), and the distribution half is unproven above. Neither half is closed, and neither may be read across to the other | 2026-09-01 | key `SCH57C86HT` against team `G5H628C6WR` | per phase | Each half has its own verdict row; read both, and do not treat one as evidence about the other |

**This section records occupancy, never a quota.** Apple publishes no numeric per-team
certificate figure at all: the only quantitative sentence on its certificates overview
concerns which roles may create distribution certificates, and searching the full page for
quota language returns nothing else (C-A). There is therefore no authority to defer to,
only measurement — so what lands here is how many certificates of each type the team is
carrying on a given date, and "at capacity" is an empirical outcome of an attempted mint,
never a prediction from a stored constant. Any number in the `Value` column is an
occupancy count for `G5H628C6WR` on the date beside it and means nothing about any other
team or any other day.

**Three certificate types, because those are the three the release lane mints:**
`DEVELOPMENT`, `DISTRIBUTION`, and `MAC_INSTALLER_DISTRIBUTION` (C-06). They are listed
even at zero occupancy, so a missing type is visibly zero rather than silently absent.

**`Certificate` carries no creation date in App Store Connect API 4.4.1.** The schema
exposes name, type, display name, serial number, platform, expiration date, content and
activation state, and nothing else (C-E). `expirationDate` is the only ordering proxy
available. This is written down to pre-empt the reintroduction of the claim that an
at-capacity mint revokes the oldest certificate by creation date: that claim appears in
two places in this repository, no such code path exists in the pinned fastlane, and the
API could not support the ordering even if it did (R-04). The operational rule is
unchanged and independent of the reasoning behind it — nothing is revoked without a human
looking at the list first (D-39), and team `G5H628C6WR` is shared with another shipping
app, so a wrong revocation destroys someone else's production certificate.

**The census instrument was checked in both directions before its output was believed.**
A measurement is only as good as the instrument's ability to fail, so on 2026-09-01 the
`census-diff` comparator was run against three inputs. A byte-identical copy of the real
census exited `0` — the pass direction, which proves the failures below are not a constant.
A copy differing only in its `team` field, carrying the team that
`.github/workflows/release.yml` measured against, exited `2` and named the mismatch; that
is the C-05 failure mode being caught rather than diffed. And a copy derived from the real
census with one genuinely-present certificate id removed exited `1` and named that id. The
removal fixture was built from the real file rather than hand-written, so the id it deletes
was actually in the before set — a fixture whose removed id was never present would exit
`1` for the wrong reason and assert nothing.

**Per-certificate expiry is part of what this project has to track, and it is the only
expiry on this page that moves.** The App Store Connect API key carries no expiry at all
(see the ASC API key section above), so the dates that genuinely exist are the Developer
Program agreement dates recorded further up and the three certificate `expirationDate`
values in the table above. The earliest of them is 2027-05-24. Those dates come from Apple
in each census run, so re-running the re-check command is what refreshes them; nothing here
is computed from a stored assumption about certificate lifetime.

### A green mint is not evidence the key may create certificates

This is the finding worth carrying forward, and it is recorded because the lane looked like
a pass. `fastlane cert` with its default `force: false` first asks Apple for the
certificates of the type requested and then checks whether any of them is already installed
in the local login keychain. If one is, it **uses that certificate and never calls the
create endpoint at all**. The run still exits `0`, still prints a success banner, still sets
`CER_CERTIFICATE_ID`, and still ends with *"Local-mode signing identities ready in login
keychain"* — and a key with no authority to create a distribution certificate whatsoever
would produce that same output, character for character. Every surface-level signal is
identical between "the key is sufficient" and "the question was never asked".

That is what happened here on 2026-09-01. A valid `Apple Distribution` identity for this
team was already in the login keychain before the mint, the mint found it, and the
authorization layer was never touched. **The only thing that distinguishes the two cases is
the certificate census taken before and after:** a real create adds an id, a reuse does not.
The id set was identical, so the outcome is `REUSED` and ACCT-04b is **unproven**.

Unproven is recorded as unproven. It is not rounded up to a pass because the lane was
green, and it is not recorded as a failure either — nothing failed; a measurement simply was
not taken. The reason this matters beyond bookkeeping is that the question ACCT-04b asks is
whether this key can create a distribution certificate at the moment a release actually
needs one, on a machine where no such certificate is sitting in the keychain — which is
precisely the situation in which the reuse path is unavailable and the answer starts to
matter. Anyone re-running the mint locally to "confirm" it will get the same reuse and the
same green log.

**This says nothing about the submission path, and the submission path says nothing about
this.** Creating distribution certificates and submitting an app for review are separate
permissions in Apple's roles matrix, granted to different sets of roles. Two separate
verdicts are kept for that reason, and neither may be read across to the other.

### Why no mint still available can settle ACCT-04b

**Forcing the question is a decision, not a fix**, and on 2026-09-01 it was decided not to
force it. The decision was `record-only`: nothing minted, nothing revoked, no `--force`, no
local identity removed. What follows is the reasoning, recorded because without it the close
reads as giving up rather than as a measurement that could not be taken at an acceptable price.

**Which types would reuse and which would create is knowable in advance, from the keychain.**
Read on 2026-09-01, scoped to team `G5H628C6WR`:

```
Apple Distribution                        present locally  -> a mint REUSES
3rd Party Mac Developer Installer         present locally  -> a mint REUSES
Apple Development                         absent           -> a mint would CREATE
```

So both distribution-family types are already local and will reuse without reaching Apple.
The only type that would produce a real `POST /v1/certificates` is `DEVELOPMENT` — and
**`DEVELOPMENT` tests the wrong permission.** Apple gates *"Create and revoke distribution
certificates"* as the conditional row on its roles matrix, which is what makes ACCT-04b a
live question for an `App Manager` key at all. Development certificates are not on that row
and are routinely creatable by Developer-role users. A successful `DEVELOPMENT` create would
prove only that the key can write to the certificates endpoint at all; it would say nothing
about the distribution permission actually in question, while consuming a slot on a shared
team to say it. Recording it as evidence for ACCT-04b would be the same substitution one
seam further along: a real observation of the wrong thing.

**Read the two keychain listings, not one.** `find_existing_cert` decides reuse through
`FastlaneCore::CertChecker.installed?`, which is the union of two different queries —
`security find-identity -v -p codesigning` for signing identities, and
`security find-certificate -c "3rd Party Mac Developer Installer"` (plus the `Developer ID
Installer` equivalent) for installer certificates. Installer certificates do not appear under
the code-signing policy, so anyone predicting a `mac_installer_distribution` mint from
`find-identity -p codesigning` alone will see nothing, predict `CREATED`, and be wrong. Read
from the pinned fastlane source rather than observed here, since that mint was not attempted.

**There is a second reuse path that the keychain does not show at all.** If no matching
identity is installed, `find_existing_cert` still reuses when a cached `<id>.p12` is sitting
in the `cert` output directory — it imports the cached key and certificate and returns. So
deleting the local identity does not reliably compel a create either, which is one more
reason the option was not worth its cost. Also read from source, not observed.

**The cost of the two routes that would have produced a real create.** Both `--force` and
deleting the local identity consume a certificate slot on a team shared with another shipping
product. Deleting the local identity is the worse of the two: it discards the private key,
which leaves `6B8BWZ4B4X` registered at Apple but permanently unusable — a slot spent on
nothing, on a team where slots are shared and capacity is unknown. That is trading a working
production signing identity for a checkmark, and it was declined.

**What that leaves, stated plainly.** ACCT-04b is unproven and stays unproven. Capacity is
unobserved for all three types. Neither is a failure, and neither is rounded up.

## Staleness contract

Each fact carries a window, and a row past its window is stale rather than wrong. The
three windows:

| Fact class | Window | Why |
|---|---|---|
| Certificate census | 7 days | Changes on every release run, and the Saturday canary mutates it weekly |
| ASC key role | per phase | Cannot drift silently — a key's access level cannot be edited after generation, only replaced |
| Trader status | per submission | Enforcement is applied at submission time, so the check belongs to the submission |

**Close-out check.** One command, machine-checkable, reporting how many fact rows are past
their `Valid until` date:

```bash
ruby -e 'require "date"
t = File.read("docs/APPLE-ACCOUNT-STATE.md", encoding: "UTF-8")
lines = t.lines
stale = ["## Apple Developer Program and account", "## ASC API key", "## Certificate census"].flat_map { |h|
  i = lines.index { |l| l.start_with?(h) } or next []
  j = lines[(i + 1)..].index { |l| l.start_with?("## ") }
  lines[(i + 1)...(j ? i + 1 + j : lines.length)]
}.map(&:strip).select { |l| l.start_with?("|") }.reject { |l| l =~ /\A\|[\s:|-]+\|\z/ }.filter_map { |r|
  c = r.split("|")[1..].to_a.map(&:strip)
  next if c[0] == "Fact"
  next unless c[4].to_s =~ /\A\d{4}-\d{2}-\d{2}\z/
  "#{c[0]} (valid until #{c[4]})" if Date.parse(c[4]) < Date.today
}
puts "#{stale.length} stale row(s)"
stale.each { |s| puts "  #{s}" }'
```

It must read `0 stale row(s)` before a submission. If it does not, every row it names is
re-measured — not re-dated.

**Why that check parses a section instead of grepping the file.** This document prints its
own column names, spells out its own conventions, and shows an example header row a few
sections up. A count-based grep over the whole file would match the prose describing the
check and report a number that means nothing, and it would keep reporting it after the
table it was supposed to watch had rotted away. The check above extracts the three named
fact sections first and parses their table rows; `test/docs_structure_test.rb` asserts
against this file the same way, for the same reason. Ledger row UL-010 records three
separate near-misses of exactly this shape in Phase 1.

## What guards this file

`test/docs_structure_test.rb` treats this document as the fifth fork-owned document under
structural guarantee, and runs on every pull request inside the `review notes` job. It
asserts the six-column header in order, that every data row carries either a real
measurement date or an explicit `pending NN-NN` marker, that every measured row names what
it was measured against, that the team id is present, that no `Value` cell states a
numeric certificate quota, and — via the sweep that covers all five documents — that no
contact-address-shaped string has appeared.

Confirm the guard actually ran, rather than assuming it:

```bash
gh run list --repo indiagrams/ios-macos-smoketest --workflow review-notes.yml --limit 1
```

Note that the `review notes` job going red only blocks a merge while `review notes` is a
required status check on `main`, which is live GitHub state rather than anything in this
repository. `docs/CONTRIBUTING-UPSTREAM.md` section 6 carries the hazard, the restore
command, and the expected required-context count of nine. Verify by count; a de-required
check looks exactly like a required one.
