# Apple account state

## Why this exists

This is the durable, tracked record of the Apple account facts this project's release
path depends on: how the team is enrolled, which agreements are in effect, what the App
Store Connect API key is, and which signing certificates the shared team is actually
carrying. The reasoning behind each measurement — the alternatives weighed, the sources
read — lives in this project's planning notes, which are gitignored and do not survive a
fresh clone, a new checkout, or a refork. This file does survive, and it is what the
pre-submission checklist in Phase 9 and Phase 10 reads before anything is sent to Apple.

**This file is account operations state, not product identity.** Trader status lives in
[PRODUCT-IDENTITY.md](PRODUCT-IDENTITY.md) per D-38, because it is a fact about who ships
the app and it appears on the public product page. Everything recorded here moves on a
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

The six `pending 02-09` and `pending 02-10` rows still carry the short forms. They are
placeholders for measurements that have not been taken, and the plan that takes each one
writes its real re-check command then; correcting a command for a row whose value is an em
dash would be tidying a cell nobody can run yet. Named here rather than left to be
rediscovered.

## Apple Developer Program and account

| Fact | Value | Measured (ISO-8601) | Against (team / key / record id) | Valid until | Re-check command |
|---|---|---|---|---|---|
| Team id | `G5H628C6WR` | 2026-09-01 | team `G5H628C6WR` | per phase | `grep FASTLANE_TEAM_ID .bootstrap.env` |
| Enrollment type | `organization` — `Indiagram LLC` | 2026-09-01 | team `G5H628C6WR` | per phase | App Store Connect, Business, Account Information |
| Account holder access | `Account Holder + Admin` | 2026-09-01 | team `G5H628C6WR` | per phase | App Store Connect, Users and Access, People |
| Paid Apps Agreement | `Active` — `May 17, 2026 – May 16, 2027` | 2026-09-01 | team `G5H628C6WR` | 2027-05-16 | `ruby bin/verify-asc-agreements.rb` |
| Free Apps Agreement | `Active` — `Aug 26, 2026 – May 16, 2027` | 2026-09-01 | team `G5H628C6WR` | 2027-05-16 | `ruby bin/verify-asc-agreements.rb` |

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
| Submission path exercised | — | pending 02-09 | — | — | `ruby tools/asc-probe.rb submission-probe --app-id <id> --platform IOS --label primary` |

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
| `appStoreVersions` on the record | Two: `platform=IOS state=PREPARE_FOR_SUBMISSION version=1.0` and `platform=MAC_OS state=PREPARE_FOR_SUBMISSION version=1.0`. Both platforms live on the one record, and each can be submitted independently | 2026-09-01 | record `6807393045` | per phase | `/opt/homebrew/opt/ruby@3.3/bin/bundle exec ruby -e 'require "spaceship"; Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.create(key_id: ENV["ASC_API_KEY_ID"], issuer_id: ENV["ASC_API_KEY_ISSUER_ID"], key: Base64.decode64(ENV["ASC_API_KEY_P8_BASE64"])); Spaceship::ConnectAPI.get_app_store_versions(app_id: "6807393045").to_models.each { |v| puts "#{v.platform} #{v.app_store_state} #{v.version_string}" }'` |
| App records named `Shipkit Pipes` on this team | Exactly one. Enumerated all five app records on the team; no second `Shipkit Pipes` and no record against `com.indiagram.shipkitpipes.macos` | 2026-09-01 | team `G5H628C6WR` | per phase | `/opt/homebrew/opt/ruby@3.3/bin/bundle exec ruby -e 'require "spaceship"; Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.create(key_id: ENV["ASC_API_KEY_ID"], issuer_id: ENV["ASC_API_KEY_ISSUER_ID"], key: Base64.decode64(ENV["ASC_API_KEY_P8_BASE64"])); puts Spaceship::ConnectAPI::App.all.map { |a| "#{a.id} #{a.name}" }'` |
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
| `DEVELOPMENT` occupancy | — | pending 02-10 | — | — | `bundle exec ruby tools/asc-probe.rb census --out /tmp/census.json` |
| `DISTRIBUTION` occupancy | — | pending 02-10 | — | — | `bundle exec ruby tools/asc-probe.rb census --out /tmp/census.json` |
| `MAC_INSTALLER_DISTRIBUTION` occupancy | — | pending 02-10 | — | — | `bundle exec ruby tools/asc-probe.rb census --out /tmp/census.json` |

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
