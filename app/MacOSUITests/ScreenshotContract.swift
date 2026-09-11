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
