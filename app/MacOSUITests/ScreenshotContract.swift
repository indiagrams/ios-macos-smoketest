import XCTest

// THE macOS SCREENSHOT CONTRACT — what `AppStoreScreenshotTests.swift` is bound by, and the
// population type it asserts with.
//
// SPLIT OUT FOR ONE REASON, RECORDED SO IT IS NOT MISTAKEN FOR TASTE: that file is at
// `swiftlint --strict`'s 400-line file budget, and `--strict` promotes the 400-line WARNING to an
// error (UL-056). The alternative was deleting the measurements written in its comments, which are
// the part of it hardest to re-derive. `app/UITests/ScreenshotValues.swift` is the iOS twin of
// this move, made by plan 08-13 for the same reason.
//
// ─────────────────────────────────────────────────────────────────────────────────────────────
// THREE THINGS THAT ARE NOT THE SAME AS THE iOS TWIN
// ─────────────────────────────────────────────────────────────────────────────────────────────
//
// 1  THE WINDOW SIZE IS FORCED, FROM INSIDE THE APP (D-128). `crop_to_apple_size`
//    (`ci/extract-mac-screenshots.sh:160-182`) picks the LARGEST App-Store-accepted macOS size
//    that FITS the capture — the four accepted 16:10 sizes, tried largest first — so a window a
//    pixel short yields a perfectly valid next-size-down PNG and the run looks green. The sizes
//    are named in prose rather than spelled here for the same reason they are in the test file:
//    the gate on that file greps for the target pair, and this directory is one widening away
//    from being swept too.
//    `-UITestWindowSize` (`app/Shared/App.swift`) sets the window's FRAME, because XCUITest has no
//    window-resize API and the only process that can size the window is the one that owns it.
//    POINTS are requested in the test and PIXELS are measured in the evidence file, so a machine
//    with another backing scale fails legibly instead of cropping silently.
//
// 2  ASSERTION 4 CANNOT BE COUNTED IN THE WINDOW. On iOS the privacy control is a navigation-bar
//    item inside the shot; on macOS it is ONE app-menu item after About (D-117), and menus are
//    closed in a window capture. So the menu is opened POSITIONALLY, counted, and closed again
//    BEFORE the shot. Index 0 of the menu bar is the Apple menu, so the app's own menu is index 1
//    — an ordinal, not a query by visible text. The one by-visible-text `menuBarItems` subscript
//    in that file is a pre-existing window fallback and is NOT extended;
//    `evidence/08-11-controls.rb` counts them.
//
// 3  EVERY TEXT READ GOES THROUGH `renderedText`. macOS publishes a plain SwiftUI `Text`'s content
//    in AXValue ALONE and XCUITest's `.label` never reads AXValue, so `.label` is a CONSTANT EMPTY
//    STRING for the three commonest text shapes — for an element rendering the wrong string and
//    the right string alike (`app/UITestSupport/ElementText.swift`). An assertion on `.label`
//    would compare "" with "" and pass forever.
//
// ─────────────────────────────────────────────────────────────────────────────────────────────
// ORDERING, AND WHY THE ORDINAL IS IN THE ATTACHMENT NAME
// ─────────────────────────────────────────────────────────────────────────────────────────────
//
// `deliver` re-orders every set in App Store Connect by the NATURAL SORT OF THE FILE NAME, and
// `ci/extract-mac-screenshots.sh` names each output from `attachment.name` — so the ordinal IS the
// sort key, and D-125's "lead with the chained pipeline" is checkable on disk without uploading.
// LIGHT TAKES 01-04 AND DARK 05-08 DELIBERATELY: both appearances land in ONE set, so a
// `01-…-light` / `01-…-dark` pairing would sort the dark tile first and the lead tile would be
// alphabetical accident.
//
// ─────────────────────────────────────────────────────────────────────────────────────────────
// HOW THIS SUITE IS RUN, AND HOW IT MUST NOT BE
// ─────────────────────────────────────────────────────────────────────────────────────────────
//
// `ci/take-screenshots.sh --macos-only`, and NEVER a bare `xcodebuild test`. Under
// `CODE_SIGNING_ALLOWED=NO` the runner is Apple's stock XCTRunner.app with this fork's test bundle
// injected and never re-sealed; Gatekeeper's execution policy then refuses it, puts a "damaged and
// can't be opened" modal on the USER'S DESKTOP and exits 65 (08-11).
//
// **THE WHOLE RECIPE IS LOAD-BEARING AND THE RE-SIGN ALONE IS MEASURED TO FAIL.** An earlier
// version of this paragraph said `xattr -cr` was "a no-op there, because the bundle carries no
// extended attributes at all". THAT READING WAS TAKEN ON A NEVER-LAUNCHED RUNNER AND IS WRONG:
// four runs on one Mac, and the row that settles it is fresh-derived-data NO, `xattr -cr` NO,
// re-sign YES -> REFUSED, with a modal, while `codesign --verify --deep --strict` exited 0
// "valid on disk" on the very path the kernel named. What differed was `com.apple.macl`, which
// APPEARS ONCE A BUNDLE HAS BEEN REFUSED. So the four steps are one step: `rm -rf` the derived
// path, `build-for-testing`, BOTH `xattr -cr` AND `codesign --force --deep --sign -` on the
// runner, then `test-without-building`. Dropping any of them re-opens the modal.
//
// **IF A DIALOG APPEARS: Cancel. NEVER "Move to Trash"** — trashing deletes the runner from
// DerivedData and the next build silently rebuilds it, so the failure presents as intermittent.
//
// ─────────────────────────────────────────────────────────────────────────────────────────────
// THE HEADLESS-RUNNER SELF-SKIP, AND WHY HOME IS THE ONLY DETECTOR
// ─────────────────────────────────────────────────────────────────────────────────────────────
//
// `setUpWithError` skips the whole suite when HOME is `/Users/runner`, which covers both
// appearances rather than the one test body it used to guard. LOAD-BEARING: `app.activate()`
// needs a GUI session, and on a headless GH-Actions image the runner refuses focus — `activate()`
// sits ~60 s and XCTest records "Failed to activate application (current state: Running
// Background)". With `continueAfterFailure = false`, nothing below it ever runs.
//
// Detection BY HOME, and that is forced rather than chosen: macOS XCUITest spawns the runner via
// launchd, which scrubs the environment, so `CI` and `GITHUB_ACTIONS` are NOT visible inside the
// runner even when the workflow sets them. The home directory IS inherited from the launchd user
// session, and GH-Actions macos-* runners always log in as `runner` — a path no developer Mac can
// match. The screenshot suite exists for `make screenshots`, not for CI smoke validation: the
// `app (macOS)` matrix cells in pr.yml already compile this file and run `AppMacOSTests`.
//
// ─────────────────────────────────────────────────────────────────────────────────────────────
// THE MENU ITEM IS UNREADABLE ON THIS PLATFORM — MEASURED 2026-09-11, NOT PREDICTED
// ─────────────────────────────────────────────────────────────────────────────────────────────
//
// The first execution of this harness FAILED, by name, on both test methods:
//
//     BLIND READ: the add-step menu item at index 0 renders nothing this test can read
//
// The iOS twin asserts that the menu index it takes resolves to that operation's own catalog
// string, so a reordered `Operation.allCases` cannot silently build a different chain. On macOS
// that read is blind: the add-step menu presented its full population of TEN items, each carrying
// `Step.addStepMenu`, and item 0's text came back empty through BOTH `label` and `value`. This is
// the same class 06-13 measured for `Menu` containers, one level further in — MATCHING works,
// READING does not. `assertReadable` did exactly its job: it named a blind instrument instead of
// letting `"" == ""` pass, which is the shape `BlindReadGuards.swift` exists for.
//
// SO THE CLAIM MOVED TO WHERE IT CAN BE MEASURED, RATHER THAN BEING DELETED. The assertion is now
// on the card that LANDED: `Step.header` is `Text(title).accessibilityAddTraits(.isHeader)`
// (`StepCard.swift:182-185`), and the six-shape measurement in
// `evidence/07-UITESTSUPPORT-ax-shapes.swift` records that exact shape publishing its content in
// AXDescription — which `.label` DOES read. That is strictly stronger than the iOS check: it
// asserts the step that exists rather than the menu row that was clicked. The menu item's whole
// attribute set is still RECORDED on every run, so the finding is on the record rather than in
// this comment alone.
//
// THE SAME UNCERTAINTY REACHES ASSERTION 4, and it is handled the same way. `AppMacOSUITests/`'s
// `PrivacyLinkTests` had COMPILED BUT NEVER EXECUTED anywhere when this was written (08-11's own
// summary says so), so whether a `CommandGroup` button carries its accessibility identifier into
// the macOS menu bar is still open. The count is taken by IDENTIFIER first — matching is not the
// blind half — and only the fallback reads text, through renderedText UNIONED WITH `title`,
// because AXTitle is where AppKit publishes a menu item's text and the shared read layer does not
// ask for it. Every component is recorded, so a zero is a measurement and not an absence.
//
// NOT FIXED IN `app/UITestSupport/`: adding an AXTitle fallback to the shared read rule would
// change every read on both platforms, which is a decision for a plan that owns that file.
//
// ─────────────────────────────────────────────────────────────────────────────────────────────
// AND THEN THE RUN ANSWERED BOTH, 2026-09-11 — recorded here because they are expensive to
// re-derive and because one of them falsifies a live file
// ─────────────────────────────────────────────────────────────────────────────────────────────
//
//   addstep index=0 population=10 type=54 label="" value="" title="Base64 encode"
//   addstep index=8 population=10 type=54 label="" value="" title="SHA-256"
//   01-chain-light privacy_by_identifier=0 privacy_found=1 privacy_read="Privacy Policy"
//                  app_menu_items=19 menubar_items=7
//
// 1  A macOS MENU ITEM (elementType 54) PUBLISHES ITS TEXT IN **AXTitle** AND IN NEITHER OF THE
//    TWO ATTRIBUTES THE SHARED READ RULE ASKS FOR. `label` and `value` are both empty on an item
//    whose title is plainly "Base64 encode". `ElementText.swift`'s rule is `label` then `value`,
//    measured over six IN-WINDOW shapes; a menu item is a seventh shape it never covered, and on
//    that shape the rule is structurally blind. This is a finding ABOUT THE READ LAYER, not about
//    this app.
//
// 2  A SwiftUI `CommandGroup` BUTTON DOES **NOT** CARRY ITS ACCESSIBILITY IDENTIFIER INTO THE
//    macOS MENU BAR. `08-UI-SPEC.md`'s Open Item 2 resolves NEGATIVE — the same answer 06-13
//    measured for `Menu` containers. The item is reached by its ordinal instead, and its title
//    reads correctly through the union above.
//
//    **THIS FALSIFIES A LIVE FILE.** `app/MacOSUITests/PrivacyLinkTests.swift` takes exactly this
//    fallback and then calls `assertReadable` / `assertRendersText` on the item — reads that go
//    through `label` then `value`, both of which are empty here. That suite HAS NEVER EXECUTED
//    ANYWHERE (08-11's own summary says so), and on its first execution it will fail with a BLIND
//    READ on the branch it was written to take. Not fixed here: that file is outside this plan's
//    scope. It is recorded in `deferred-items.md` with the numbers.
//
// ─────────────────────────────────────────────────────────────────────────────────────────────
// ASSERTION 7 — THE HEAD OF THE PIPELINE IS IN THE PHOTOGRAPH, AND WHY ITS SECOND CLAUSE IS A
// macOS CLAUSE
// ─────────────────────────────────────────────────────────────────────────────────────────────
//
// Assertions 1-6 judged the OUTPUT VALUES and only those. Nothing required the INPUT of a surface
// or the "Step 1 <name>" header to be in the captured frame, so TWO OF EIGHT macOS tiles shipped
// without either — `macos-01-chain-light` and `macos-05-chain-dark` — with every assertion green.
// `macos-01-chain-light` is the LEAD TILE of the macOS set, the first thing a reviewer sees.
//
// THE HEAD POPULATION, top to bottom, and it has FOUR members rather than three:
//
//     <surface>.inputLabel , <surface>.input , Step.position , Step.header
//
// The label is in the set because leaving it out shipped the defect a SECOND time on the iOS twin:
// plan 08-20 widened the head from {output values} to {field, position, header}, re-captured, and
// two tiles came back with the navigation bar through the middle of the "Input" letterforms while
// the clause reported `outside=0`. It was not lying; it was answering a narrower question than the
// one that matters. `InputArea.swift` is SHARED between the two platforms, so the three per-surface
// `inputLabel` identifiers 08-20 minted are already attached here — this target only had to put
// them in its own head population. See ``SurfaceInput``.
//
// THE SECOND CLAUSE — the first `Step.card`'s minY may not sit ABOVE the band's top — IS THE
// BLURRED HALF-LINE IN ITS GENERAL FORM, and it is sharper on this platform than on iOS.
// `band.minY` is the LOCATED toolbar's maxY. iPhone's navigation bar is OPAQUE and cuts a clipped
// line off cleanly; **this platform's title bar is TRANSLUCENT and does not**, so a header pushed
// into that strip is composited THROUGH the bar and renders as a blurred half-line of text bleeding
// under the window title. It reads as a rendering bug rather than as a crop, which is how the UAT
// found it — by cropping the title band and comparing against a clean tile. Content continuing past
// the BOTTOM fold is normal and is not asserted against.
//
// ─────────────────────────────────────────────────────────────────────────────────────────────
// THE ARITHMETIC, AND WHY THE WINDOW CANNOT SIMPLY GROW
// ─────────────────────────────────────────────────────────────────────────────────────────────
//
//     band           = contentBounds()                    // window minus the LOCATED toolbar
//     headTop        = min(first Step.card's minY, and every head element's minY)
//     tailBottom     = max(maxY over values(sources))     // the SAME population assertion 2 judges
//     requiredDelta  = max(0, tailBottom - band.maxY)
//     availableDelta = max(0, headTop - (band.minY + scrollMargin))
//     fits           = (tailBottom - headTop) + scrollMargin <= band.height
//
// `fits` is stated as an EXTENT rather than as `requiredDelta <= availableDelta`. The two are the
// same predicate at the content origin, but both deltas clamp at zero, so the delta form reads
// `0 <= 0` — true — for a composition that does not fit once the surface has been scrolled. The
// iOS twin measured exactly that inside the loop whose job is to decide the composition
// (plan 08-20, commit 020d974). `tailBottom - headTop` is invariant under scrolling; the delta
// form is not.
//
// MEASURED ON THIS PLATFORM, 08-14's run, every chain shot: `window=(144,102,1440,900)`,
// `chrome=toolbar=top(144,102,1440,52)`, `band=(144,154,1440,848)`. Unscrolled, the three chain
// values sit at y=560.5 / 841.5 / 1122.5, each 18 pt tall. The shipped tile is that span scrolled
// up by 273 pt to CENTRE it, which is precisely what put the root card's header under the title
// bar. From the root card's top to the third value's bottom is ~980 pt in an 848 pt band: **a
// three-card chain and its own input cannot share one window of this size.**
//
// **AND THIS WINDOW CANNOT GROW.** D-128 locks the capture to an App-Store-accepted macOS size,
// and at this machine's 2.0 backing scale the requested POINT size is already the largest of the
// four accepted 16:10 sizes. There is no larger window to ask for, so the composition is the only
// lever: the chain RETRACTS its last appended step and re-measures, floored at one appended card.
// With the last step retracted the same span needs ~700 pt and `requiredDelta` falls to 0 — so
// nothing scrolls at all, which also takes this harness's least reliable mechanism off the
// critical path (08-14 measured `moved=0.0` on several attempts).
//
// WHEN THE FLOOR IS REACHED AND THE HEAD AND THE TAIL STILL CANNOT SHARE THE BAND, the gate FAILS
// with its numbers and `floor_and_fail=true` rather than filing a one-card "chain". It is NOT
// fixed by lowering `scrollMargin`, by loosening assertion 2, or by dropping a member of the head.

// ─────────────────────────────────────────────────────────────────────────────────────────────
// WHAT THIS HARNESS DELIBERATELY DOES NOT CARRY
// ─────────────────────────────────────────────────────────────────────────────────────────────
//
// The iOS twin's SECOND OPINION — `SecondOpinion.base64` / `sha256Hex` / `htmlEncoded` /
// `percentEncoded`, `app/UITests/ScreenshotValues.swift` — lives in the iOS target only. Plan
// 08-14's assertion set is the six preconditions, and the values here are asserted present, inside
// the frame, readable and pairwise distinct, NOT recomputed from their definitions. Stated here
// rather than left to be discovered: a macOS chain producing three distinct WRONG values would
// pass this gate and fail the iOS one.
//
// C-25: Swift 5.9 / `SWIFT_STRICT_CONCURRENCY: minimal`, like every file in this target.

/// One identifier and how many elements must carry it, so a population assembled from two
/// identifiers asserts each contribution before either is unioned.
///
/// The shape exists because a correct check pointed at the wrong population is this project's
/// most expensive recurring defect: a three-card chain publishes ONE `Encode.output` and TWO
/// `Step.output`, so a gate counting three of either is right about everything except its subject.
struct ValueSource {
    let identifier: String
    let expected: Int

    init(_ identifier: String, _ expected: Int) {
        (self.identifier, self.expected) = (identifier, expected)
    }
}

/// One surface's input block as the capture gate addresses it: the FIELD and the LABEL above it.
///
/// **THE LABEL IS HERE BECAUSE LEAVING IT OUT SHIPPED THE DEFECT TWICE ON THE iOS TWIN.** Both
/// identifiers are minted per surface rather than shared — there are three `InputArea`s and three
/// labels, exactly as there are three fields, and a shared constant would make this gate's
/// population depend on which surface's view a container happens to keep alive.
///
/// A value rather than two parameters at every call site, so a shot cannot name Hashing's label
/// beside Encode's field — and so `gate` stays inside `function_parameter_count`'s five.
struct SurfaceInput {
    /// The text field.
    let field: String

    /// The "Input" label above it. `InputArea.swift` attaches it on the leaf `Text`, and that file
    /// is SHARED, so this platform inherited the identifier without changing app code.
    let label: String

    static let encode = SurfaceInput(field: AccessibilityIdentifiers.Encode.input,
                                     label: AccessibilityIdentifiers.Encode.inputLabel)
    static let hashing = SurfaceInput(field: AccessibilityIdentifiers.Hashing.input,
                                      label: AccessibilityIdentifiers.Hashing.inputLabel)
    static let timestamps = SurfaceInput(field: AccessibilityIdentifiers.Timestamps.input,
                                         label: AccessibilityIdentifiers.Timestamps.inputLabel)
}

/// THE POPULATIONS THIS GATE ASSERTS OVER, gathered where ``ValueSource`` and ``SurfaceInput``
/// already are. Definitions rather than driving, which is why they are not in `ScreenshotDriver`;
/// and gathered here rather than in the class file because that file is at the 400-line budget
/// `swiftlint --strict` enforces (UL-056) and measurements are not deleted to make room.
extension AppStoreScreenshotTests {
    /// Hashing's four cells and Timestamps' three, from the shipped identifier enum.
    static let hashingCells = [
        AccessibilityIdentifiers.Hashing.digestMD5,
        AccessibilityIdentifiers.Hashing.digestSHA1,
        AccessibilityIdentifiers.Hashing.digestSHA256,
        AccessibilityIdentifiers.Hashing.digestSHA512
    ]

    static let timestampsCells = [
        AccessibilityIdentifiers.Timestamps.cellEpoch,
        AccessibilityIdentifiers.Timestamps.cellISO8601,
        AccessibilityIdentifiers.Timestamps.cellDateTime
    ]

    /// The chain's value population for `appended` appended cards: ONE `Encode.output` from the
    /// seeded root and one `Step.output` per appended card. MEASURED, not assumed — only the
    /// APPENDED cards keep `Step.output`, so a gate counting three of either is right about
    /// everything except its subject.
    static func chainSources(_ appended: Int) -> [ValueSource] {
        [
            ValueSource(AccessibilityIdentifiers.Encode.output, 1),
            ValueSource(AccessibilityIdentifiers.Step.output, appended)
        ]
    }
}
