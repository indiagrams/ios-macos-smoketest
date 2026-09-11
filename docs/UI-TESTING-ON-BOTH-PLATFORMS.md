# UI testing on both platforms

<!-- Written for a forker who has just added a second platform to an XCUITest suite that
     was green on the first one. Every fact below was MEASURED by this fork while shipping,
     with the negative controls that make each measurement falsifiable, and every one carries
     the evidence that produced it. Nothing here is repeated from a blog post.

     Upstream-bound. The SCOPE.md question — "does this addition require modifying Swift
     source files in the app target to use it?" — answers NO for everything on this page:
     the support layer it describes lives in the UI-test targets and the app is
     byte-unchanged by all of it. See CONTRIBUTING-UPSTREAM.md for the route. -->

An XCUITest suite that passes on iOS and passes on macOS is not two green suites. It is
frequently one green suite and one that has never measured its subject, because the two
platforms publish a SwiftUI view's text in **different accessibility attributes** and
XCUITest reads only one of them. This page is what this fork measured, with the controls,
and the small app-agnostic support layer that falls out of it.

## 0. How to read this page

Every claim carries its epistemic status, because the single most expensive defect this
project has recorded is **a claim correct in form pointed at the wrong target**. The markers:

| Marker | What it means |
|---|---|
| **MEASURED HERE** | Reproduced on a developer Mac by a probe in this repository, with a negative control that can refuse the verdict. Date and OS build given. |
| **MEASURED ON A RUNNER** | Observed in a GitHub Actions run. Run id given. |
| **CITED** | Someone else's working code or Apple's own text. Path or link given. Not re-measured here. |
| **OPEN** | Not measured. Stated as a question, never as a fact. |

If you find a sentence here without one of those, treat it as OPEN and measure it.

## 1. The rule that is easiest to mis-state: **reading** is blind on macOS, **matching** is not

### 1.1 What each SwiftUI shape publishes — MEASURED HERE

macOS 26.5.2 (Build 25F84), 2026-09-10. An out-of-process accessibility client reading the
same API XCUITest reads, hosting six SwiftUI shapes, with two negative controls that must
read or the probe refuses to produce a verdict at all
(`evidence/07-UITESTSUPPORT-ax-shapes.swift`, checks 1–4):

| Shape you wrote | `AXRole` | `AXValue` | `AXDescription` | XCUITest `element.label` |
|---|---|---|---|---|
| a plain `Text` | `AXStaticText` | content | nil | **`""` — blind** |
| a `Text` in a `List` row | `AXStaticText` | content | nil | **`""` — blind** |
| `Label(_:systemImage:)` in a `List` | `AXStaticText` | content | nil | **`""` — blind** |
| a `Text` + `.accessibilityAddTraits(.isHeader)` | `AXHeading` | nil | content | reads |
| a container + `.accessibilityLabel` | `AXGroup` | nil | content | reads |
| a `NavigationLink`'s label | **`AXUnknown`** | nil | content | reads |

**macOS publishes a plain SwiftUI `Text`'s content in `AXValue` alone. XCUITest's `.label`
is built from `AXDescription`, falling back to `AXTitle`, and never reads `AXValue`.** So
`element.label` on macOS is a *constant empty string* for the three commonest text shapes a
SwiftUI author writes — the same answer for an element rendering the right string, an element
rendering the wrong string, and an element rendering nothing.

On iOS the same `Text` publishes its content **as** its label. That asymmetry is why a suite
can be green on iOS for a year while its macOS twin has never once looked at its subject.

Corroboration from a real runner, so this is not only a local finding: run `34050504430`
failed with `label=Format` read off an element whose `AXValue` held no string at all — so
`.label` answers from `AXDescription` on a runner too (**MEASURED ON A RUNNER**).

### 1.2 The read helper

Ask `label` **first**, then the element's own string `value`:

```swift
extension XCUIElement {
    var renderedText: String {
        let visible = label
        if !visible.isEmpty { return visible }
        return (value as? String) ?? ""
    }
}
```

The order is load-bearing and is not a detail:

- `label` first keeps **iOS byte-identical** — every element that answers today keeps giving
  the same answer.
- The fallback is consulted only when the first answer is empty, so this rule **can never
  change a read**; it can only turn a non-answer into an answer. The probe asserts exactly
  that over every captured element (check 4), which is what makes adopting it at an existing
  call site not a behaviour change.
- A future macOS that starts publishing an `AXDescription` for these shapes reads through the
  first branch rather than going stale.

This fork ships it as `app/UITestSupport/ElementText.swift`, compiled into **both** UI-test
targets, naming no view, no identifier and no type of the application under test. Spellings
for `XCUIElementSnapshot` (whole-tree walks read from snapshots, not from live elements) and
for `XCUIElementQuery` live in the same file, so a snapshot walk and a live read cannot
disagree about the same element.

It is a generalisation, not an invention: this fork already had the identical shape in
`LaunchLayoutSupport.isChosen(_:)`, where `isSelected` is asked first — the attribute iOS
answers — and the segment's own `AXValue` second, because macOS never sets `AXSelected` on a
segmented control.

### 1.3 What this rule does **NOT** say — read this before rewriting a query

> **Element MATCHING is a separate mechanism and it is not blind. Only READING TEXT OUT OF an
> element is.**

**MEASURED ON A RUNNER (run `34067745662`).** Three ordinal `Text`s on macOS: the assertion
counting `matching(identifier:)` hits **passed** — the query found all three — while the
`.label` read of those same three elements on the very next line returned `["", "", ""]`.
Same elements, same run. Finding them worked; reading them did not.

**CITED.** A sibling project's macOS end-to-end suite addresses elements with subscript
queries such as `app.staticTexts["System"]`
(`~/code/privateclaw/owner-app/UITests/TestRobot.swift`). Nothing on this page contradicts
that code or asks anyone to change it.

**OPEN, and stated as a question because it has not been measured here:** whether a
*label-shaped* subscript — `app.staticTexts["some visible text"]` — reaches a plain
`Text` on macOS whose `.label` reads empty. Identifier matching demonstrably does. If this
question matters to your suite, measure it in your own tree with a one-case UI test rather
than reasoning from this page; if it turns out label-shaped subscripts do not reach those
elements, the fix is an `.accessibilityIdentifier`, not a rewrite of the read layer.

If you take one sentence from this section: **do not rewrite a working query on the strength
of this page.** A page that says "you cannot find SwiftUI `Text` by label on macOS" would be
wrong, and it would send forkers to rewrite queries that work.

### 1.4 `NavigationLink` is a different trap with the opposite cause

**MEASURED HERE.** A `NavigationLink`'s label publishes its text in `AXDescription`, so
`.label` **reads it fine** — and its role is **`AXUnknown`**, so `app.staticTexts[…]` cannot
reach it *by element type* at all.

That is the mirror image of §1.1: there, the element is the right type and the read is blind;
here, the read is fine and the type query misses. A test failing on a `NavigationLink` is not
a blind-read problem, and applying §1.2's fix to it will change nothing. Query it with
`descendants(matching: .any).matching(identifier:)` — the form this fork uses everywhere for
exactly this reason — or give it an identifier and address that.

## 2. Assert that the instrument can see, before asserting what it sees

An empty read is not a failure signal. It is the *absence* of a signal, and an assertion
placed on top of it reports something — usually something confident and wrong. Two shapes of
that shipped in this repository:

**Loud and misleading.** `XCTAssertEqual(Set(ordinals).count, positions)` reported

```
XCTAssertEqual failed: ("1") is not equal to ("3") - two cards render the same ordinal: ["", "", ""]
```

Nothing rendered the same ordinal. Three reads came back EMPTY, and `Set(["", "", ""]).count`
is 1 as surely as `Set(["a", "a", "b"]).count` is 2. A duplicate is a defect in the
application; an empty sweep is a blind instrument. **Opposite findings, and the second was
reported in the first's words.** That cost a working session.

**Silent and green — the worse one.** `XCTAssertEqual(chained.label, Data(source.utf8).base64EncodedString())`
compared `"" == ""` and recorded a pass, **for two phases**, because both sides were read with
`.label` on macOS and `base64("")` **is** `""`. A gate asserting nothing, and saying so to
nobody. A loud failure announces itself on the next run; a vacuous pass does not.

The rule that stops both: **assert readability first, as its own assertion with its own
message, then assert the relation.** Two assertions where there was one. Nothing is weakened —
every original assertion survives verbatim as the second half — and the two opposite findings
can no longer wear each other's words. This fork ships four of them in
`app/UITestSupport/BlindReadGuards.swift`:

| Guard | What it refuses |
|---|---|
| `assertReadable(_:_:)` | An empty read feeding another assertion. Returns the text, so the comparison is only reached once the read is known to have happened. |
| `assertAllReadable(_:_:)` | A population read where *any* member is empty; the message counts them, because "one of nine" and "all nine" are different investigations. |
| `assertDistinctReadable(_:expected:_:)` | The loud case above: emptiness is checked first and names itself; the distinctness assertion survives underneath it. |
| `assertRendersText(_:_:_:)` | The silent case above. It guards the **expectation** as well as the actual — a relation whose expected side is itself computed from a read is satisfied by two blind reads whenever the transform maps `""` to `""`, which base64, trimming, joining and percent-encoding all do. |

Each takes `file`/`line` defaulted to `#filePath`/`#line`, so a failure points at the call
site a reader is looking for rather than at the helper.

**Proven by a planted RED, not by reading.** With the ordinal reads forced to `""`, the run
failed at `VisibleStringSweep.swift:294` — the walk's own line, proving the `file`/`line`
forwarding — with `BLIND READ: 3 of 3 reads of the step ordinals on screen came back EMPTY:
["", "", ""]`. The mutation's landing was confirmed by sha256 before the exit code was
trusted, and the file's sha256 was confirmed restored afterwards.

## 3. Gatekeeper blocks local macOS UI tests — and the cause is NOT what this section first said

> **AMENDED 2026-09-11 (UTC). The 2026-09-06 measurement below is preserved verbatim and is
> still accurate FOR THE CONFIGURATION IT MEASURED. What was wrong is the GENERALISATION and
> the PRESCRIPTION. Read §3.1 before acting on anything in §3.0.**

### 3.0 The original measurement, preserved

**MEASURED HERE**, attended, 2026-09-06. Running the macOS UI scheme on a developer Mac dies
with:

```
AppMacOSUITests-Runner (90456) encountered an error (Early unexpected exit, operation never
finished bootstrapping - no restart will be attempted. (Underlying Error: Test crashed with
signal kill before establishing connection.))
```

exit 65, with a *"damaged and can't be opened"* dialog on the developer's physical desktop.

**The two explanations everyone reaches for are both measurably wrong:**

| Probe | Answer |
|---|---|
| `codesign -dv` | `CodeDirectory v=20400 flags=0x0(none)`, `TeamIdentifier=…` — **the runner IS signed** |
| `xattr -l` | `com.apple.macl` only — **there is NO `com.apple.quarantine` to remove** |
| `spctl -a -vv -t exec` | `rejected`, `origin=Apple Development: Created via API` |

It is signed with an **Apple Development** certificate and refused by Gatekeeper's **execution
policy**, because a Development-signed bundle is neither Developer ID nor notarised. "damaged
/ downloaded on an unknown date" is macOS's *generic* execution-policy message; it is not a
claim about file integrity, and reading it literally sends you hunting a corrupt file that
does not exist. Note also that the build registers `builtin-RegisterExecutionPolicyException`
against the `.xctest` **plugin**, not against the **runner** that hosts it.

**Do not work around it.** Re-signing, an `spctl` exception, `xattr` removal (there is nothing
to remove) and disabling Gatekeeper were all considered and all rejected for one reason: each
turns the **local** run green while changing nothing about what CI measures, and CI is where
the verdict counts. Scope local runs to the unit bundle; `xcodebuild build` and
`build-for-testing` are fine on both platforms. Record the macOS UI result as
`PENDING-CI executed=none` — deliberately matching no success pattern — rather than guessing.

### 3.1 AMENDMENT — the runner has TWO states, and the one above is not the common one

**MEASURED 2026-09-11**, twice on the same Mac, hours apart, with one variable between them.

The section above assumes ONE runner state. There are two, and **which one you get depends on
the build configuration**, so a reader who checks `codesign` and sees something different has
not found a contradiction — they have found the other state.

| | §3.0's state (2026-09-06) | Under `CODE_SIGNING_ALLOWED=NO` (2026-09-11) |
|---|---|---|
| `codesign -dvvv` authority | Apple **Development** cert, this fork's Team ID | `Software Signing / Apple Code Signing CA / Apple Root CA`, `TeamIdentifier=59GAB85EFG` — **Apple's own**, `Identifier=com.apple.XCTRunner` |
| Sealed resources | present | **`Sealed Resources=none`**, no `Contents/_CodeSignature` |
| `xattr -lr` | `com.apple.macl` | **ZERO lines — not one extended attribute anywhere in the bundle** |
| `spctl -a -vv -t exec` | `rejected`, execution policy | fails **structurally**: *"code has no resources but signature indicates they must be present"* |
| kernel log | — | `(AppleSystemPolicy) ASP: Security policy would not allow process` |

**THE MECHANISM, in the second state:** the runner is not Development-signed at all. It is
Apple's **stock `XCTRunner.app`** with the fork's test bundle injected and **never re-sealed** —
so it carries an Apple-authority signature that *structurally cannot validate*. The refusal is
about a broken seal, not about Developer ID or notarisation.

**CONSEQUENCE — two things this page previously told you are wrong:**

1. **`xattr -cr` is a NO-OP here.** There is no quarantine bit, and §3.0 is right that there is
   nothing to remove — but it is then wrong to treat clearing it as the thing that would help.
2. **The ad-hoc re-sign is the OPERATIVE step.** `codesign --force --deep --sign - <runner>`
   replaces the broken seal with a valid one, and the runner then launches. Controlled
   comparison, same machine:

   | run | `xattr -cr` | ad-hoc re-sign | outcome |
   |---|---|---|---|
   | with the template's script | yes | **yes** | launched, exit 0, real window capture on disk, **no dialog** |
   | without either | no | **no** | kernel refusal, *"damaged"* modal on the desktop, exit 65 |

**WHAT "DO NOT WORK AROUND IT" STILL MEANS, AND WHAT IT NO LONGER MEANS.**

- **For a TEST VERDICT it stands, unchanged.** A locally-green macOS UI run still says nothing
  about what CI measures. Scope local runs to the unit bundle and record `PENDING-CI
  executed=none`. That advice in §3.0 was right and is not weakened here.
- **For SCREENSHOT CAPTURE it does not apply.** There the artefact on disk *is* the deliverable,
  not a pass/fail claim — and the template's own `ci/take-screenshots.sh` performs the
  `xattr -cr` + ad-hoc re-sign itself, between `build-for-testing` and `test-without-building`.
  Running it is therefore not a workaround at all; it is the supported path.

**IF YOU DO NEED A LOCAL macOS UI RUN**, reproduce that same split —
`build-for-testing` → `codesign --force --deep --sign - <runner>` → `test-without-building`,
scoped with `-only-testing:` — and make sure **nothing relinks the runner between the re-sign
and the test**, or you execute a binary you did not sign. Never run a bare full-scheme
`xcodebuild test`: it puts a modal on a human's physical desktop, and if they click
*Move to Trash* the runner is deleted from DerivedData and the next build silently rebuilds
it, so the failure then presents as intermittent. **Cancel, never Move to Trash.**

**If the dialog appears, click Cancel. Never "Move to Trash."** Trashing deletes the runner
out of DerivedData, the next build silently rebuilds it, and the failure then presents as
intermittent.

## 4. Log volume can crash the app under test

**CITED** — this fork's `06-SIMULATOR-CRASH-FINDINGS.md`, and ledger row **UL-064**, which
carries the full four-route decision. In one sentence: `XCTAutomationSupport` logs roughly
**2,900 msg/s** during a whole-tree accessibility walk, that trips a libtrace client
quarantine, and XCTest's own fault handler dereferences a NULL subsystem on the quarantine
notice. **It is an Apple bug, not an app bug** — the SIGSEGV is in the test infrastructure.

Mitigation, per simulator:

```bash
xcrun simctl spawn <udid> log config --mode "level:off" --subsystem com.apple.dt.xctest
```

**`persist:off` survives reboots, so it MUST be restored**, or the machine is left with XCTest
logging silently suppressed for every future session:

```bash
xcrun simctl spawn <udid> log config --mode "level:info,persist:default" --subsystem com.apple.dt.xctest
```

Reduce the volume at source as well: prefer identifier-scoped **counts** to `waitForExistence`
polls, and never wait on an element that is supposed to be **absent** — a doomed wait was 4.5 %
of the log volume in both measured crashes. `XCUIElementQuery.renderedTexts` in §1.2 takes one
`count` and a bounded loop for this reason.

## 5. `NSArgumentDomain` pins a launch — and therefore cannot prove persistence

**CITED**, measured by this fork in `07-RESEARCH §7.4` and re-measured in
`evidence/07-11-launch-layout.txt`. `UserDefaults` reads the process's own launch arguments
automatically, with no shipped code to enable it, and that domain **outranks** the persistent
one:

```swift
app.launchArguments += ["-your.settings.key", "the-value-you-want"]
```

A binary that had just written a different value to disk answered the pinned value from the
same store. So a pinned test needs neither the app deleted between cases nor a reset control
added to shipped code. Excellent for pinning a launch.

**And that is exactly why it cannot prove a persistence claim.** The caveat is as important as
the technique, and a template that ships the helper without it creates a new trap. Measured on
iOS 17.5 by reading the app's own plist: with a pin in place, the highest-ranking domain is
`NSArgumentDomain`, so an app that hydrates from defaults and writes back what it read will
write the **pinned** value into its own persistent store over whatever the user has since
chosen. A persistence test built on a pin therefore silently reverts the very change it is
about, and reports the pin as the app. Prove persistence by **pinning nothing on either
launch** and driving the app instead.

## 6. A deliberate RED must never be a Swift runtime trap in a host-based bundle

**MEASURED HERE.** A unit-test bundle with a `TEST_HOST` loads **into the application**. So a
Swift runtime trap in a test — a force-unwrap, an array index, a precondition — kills the
host, posts a crash-reporter dialog on the developer's **physical desktop** (one per
parameterized case; six were observed from six offsets of a single test), and ends the
transcript at the trap. A trapping red is also not a usable red: nothing after it runs, so it
proves *less* than an assertion would.

The pattern that works, and it is two artefacts rather than one:

- **Prove the trap** in a standalone CLI binary compiled with the project's own Swift flags
  (`-swift-version 6 -strict-concurrency=complete` here). Exit 133 is the evidence.
- **Prove the behaviour** in-bundle with `#expect` / `XCTFail`. Exit 65, each case naming its
  own input.

## 7. macOS UI-test output does not reach `xcodebuild`'s pipe — an open template gap

**MEASURED** by this fork across several runs: `print` from a UI-test bundle reaches
`xcodebuild`'s pipe on the **simulator** and **does not** on the **macOS** job. Every labelled
value must therefore also be an `XCTContext` activity or an `XCTAttachment` in the `.xcresult`:

```swift
func record(_ line: String) {
    print(line)                                  // iOS reads this
    XCTContext.runActivity(named: line) { _ in }  // macOS reads this, out of the xcresult
}
```

Read them back with `xcrun xcresulttool get test-results activities`.

**And that only helps if the `.xcresult` survives the job.** **MEASURED HERE, 2026-09-10:**
this template's `pr.yml` contains no `upload-artifact` step, no `resultBundlePath`, and no
mention of `xcresult` at all. Combined with a log formatter that renders no activity, the
consequence is that **every fork's macOS UI evidence is a pass/fail verdict with no numbers in
it.** This is not hypothetical here: two of this fork's macOS measurements are blocked on
exactly it — 07-10's `aa2_min_gap_pt` / `aa3_min_distance_pt`, and 07-11's three
`criterion5_hittable_*_macos` rows, all recorded as UNRETRIEVABLE rather than inferred from
their iOS twins.

**Named as an open template gap rather than fixed here**, because `.github/workflows/` is
template-owned in this fork and an edit to it would be deleted wholesale by the next refork.
The upstream shape is small: give the macOS test step a `resultBundlePath`, then either upload
that bundle as an artifact or extract the activities on the runner and echo them into the log.
Either one turns a verdict into a measurement.

## 8. What a v2 of this support layer should contribute, and from where

Everything on this page is the **read** half, because that is what this repository measured.
The **drive** half — the parts that make a macOS suite reliable rather than merely honest —
is already built and battle-tested in a sibling project, and it should be contributed **from
there**, by someone with that repository's runs behind them. Re-implementing it here untested
would be worse than the gap.

The prior art, by path, so the next contributor can find it (**CITED**, read-only; measured
2026-09-10 at 29 Swift files / 7,429 lines, 11 of them Robot classes):

| Piece | Where it lives | What it already solves |
|---|---|---|
| Robot Pattern base | `~/code/privateclaw/owner-app/UITests/TestRobot.swift` | One robot per behaviour cluster, every method returning `Self`; test bodies contain no raw `XCUIApplication` queries. Hand-rolled, no external library. |
| macOS window-activation dance | the same file, `launch(args:env:)` | `app.activate()` after launch, then a `File ▸ New Window` menu fallback when no window appears within 8 s — because on CI runners and some local machines the app launches in the background and every query then misses. |
| `XCTAttachment` screenshot capture | the same file, `e2eScreenshot(_:)` and `register(with:)` | Named screenshots into the xcresult, plus an automatic `final-state` teardown capture registered once in `setUp` so every case in a class is covered pass or fail. |
| xcresult failure-screenshot extraction | `~/code/privateclaw/ci/dump_failure_screenshots.sh` | Works around `xcresulttool export attachments --only-failures`, which searches *inside* assertion records and therefore returns nothing for test-scope attachments; and filters the hundreds of auto-generated "Debug description" and "UI Snapshot" junk attachments a long `waitForExistence` produces. |
| Naming convention | `~/code/privateclaw/owner-app/UITests/TEST-CONVENTION.md` | Files named after user-observable behaviour clusters rather than after SwiftUI views. |

Note how directly the third and fourth rows answer §7: attachments are the channel macOS
leaves you, and extracting them is the step a template has to make routine.

**UP-05 obligation, stated here rather than left to a reviewer to catch.** Those five paths are
**this maintainer's local checkout of a PRIVATE repository**. They are legitimate in a fork-side
document — the whole point of the section is that the next contributor can find the code — and
they are **fork concretion** the moment this page travels upstream: a stranger cloning the
template cannot resolve them, and a path that resolves for nobody is worse than a description.
Before `git am`, replace this table's `Where it lives` column with the *shape* of each piece
(what it does, why it exists, what it works around), keeping the "contribute it from the repo
where it is proven" instruction and dropping the paths. See CONTRIBUTING-UPSTREAM.md §2.

## 9. Evidence index

| § | Claim | Status | Evidence |
|---|---|---|---|
| 1.1 | six SwiftUI shapes' published attributes | MEASURED HERE 2026-09-10, macOS 26.5.2 (25F84) | `evidence/07-UITESTSUPPORT-ax-shapes.swift` (6 shapes, 2 negative controls) |
| 1.1 | `.label` answers from `AXDescription` on a runner | MEASURED ON A RUNNER | run `34050504430`; `evidence/07-11-D98-macos.txt:13,75` |
| 1.1 | a plain `Text` reads empty through `.label` | MEASURED ON A RUNNER | run `34067745662`; `evidence/07-12-ORDINAL-read.txt` §0 |
| 1.2 | the label-first rule disturbs no existing read | MEASURED HERE | `evidence/07-UITESTSUPPORT-ax-shapes.swift` check 4 |
| 1.2 | the same shape already existed for selection state | in-tree | `app/MacOSUITests/LaunchLayoutSupport.swift`, `isChosen(_:)` |
| 1.3 | identifier matching reaches an `AXValue`-only element | MEASURED ON A RUNNER | run `34067745662` — the count passed, the read beside it did not |
| 1.3 | label-shaped subscript matching on macOS | **OPEN** | not measured here |
| 1.4 | a `NavigationLink` label is `AXUnknown` and reads | MEASURED HERE 2026-09-10 | `evidence/07-UITESTSUPPORT-ax-shapes.swift` check 3 |
| 2 | the loud failure | MEASURED ON A RUNNER | run `34067745662` |
| 2 | the vacuous `"" == ""` pass | MEASURED HERE | `evidence/07-12-ORDINAL-ax-shape.swift`, `APP08_VACUITY` line |
| 2 | the guards fire and point at the call site | MEASURED HERE 2026-09-10 | planted RED, sha256 confirmed before and after |
| 3 | Gatekeeper execution-policy rejection | MEASURED HERE, attended 2026-09-06 | `evidence/07-07-selection-launchstate.txt:215-234` |
| 4 | log volume crashes the app under test | CITED | `06-SIMULATOR-CRASH-FINDINGS.md`; ledger `UL-064` |
| 5 | `NSArgumentDomain` outranks the store | MEASURED | `07-RESEARCH §7.4`; `evidence/07-11-launch-layout.txt` |
| 5 | a pinned launch cannot prove persistence | MEASURED, iOS 17.5 | `evidence/07-11-launch-layout.txt`; `app/UITests/LaunchState.swift` header |
| 6 | a host-based trap kills the host | MEASURED | plan 07-02's two-artefact control |
| 7 | `print` is lost on the macOS job | MEASURED | `evidence/07-10-step-edit.txt:148` |
| 7 | `pr.yml` uploads no xcresult | MEASURED HERE 2026-09-10 | `grep -c 'upload-artifact\|resultBundlePath\|xcresult' .github/workflows/pr.yml` → 0 |
| 8 | the v2 prior art | CITED, read-only | paths in §8's table |

Evidence paths above are this fork's planning tree, which is untracked by design; the tables
on this page are the durable record of what they say. Anything marked OPEN has not been
measured — do not promote it by quoting it.
