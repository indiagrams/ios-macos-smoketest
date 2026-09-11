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
// can't be opened" modal on the USER'S DESKTOP and exits 65 (08-11). The script's
// `codesign --force --deep --sign -` between build-for-testing and test-without-building is the
// operative step — `xattr -cr` is a no-op there, because the bundle carries no extended attributes
// at all.
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
