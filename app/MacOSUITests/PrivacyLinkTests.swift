import XCTest

// THE PRIVACY CONTROL — macOS HALF (META-06, D-117, 08-UI-SPEC.md §Accessibility).
// `app/UITests/PrivacyLinkTests.swift` is the twin and declares the SAME three
// test names for the same three claims, exactly as the `ShellTests` pair already
// does across two different containers. The mechanisms differ because D-11 chose
// two containers: iOS answers 5.1.1(i) with a navigation-bar item on every
// surface, macOS with one app-menu item after About.
//
// THE `[OPEN]` THIS FILE WAS WRITTEN TO SETTLE — AND IT IS NOW SETTLED, NEGATIVE.
// 08-UI-SPEC.md §Accessibility recorded as a first-class `[OPEN]` whether a
// SwiftUI `CommandGroup` button carries its `accessibilityIdentifier` into the
// macOS menu bar. **Plan 08-14 measured it on a running macOS app: it does not.**
// `privacy_by_identifier=0` on all eight screenshot shots, the same answer 06-13
// measured for `Menu` containers. So the branch this suite actually takes is the
// POSITIONAL fallback, and that is now the expected path rather than a contingency.
//
// BOTH BRANCHES SURVIVE ANYWAY, and that is deliberate: the identifier count is
// still emitted on every run, so the day a SwiftUI release starts propagating it
// the number moves and somebody sees it, instead of the fallback quietly covering
// a changed platform forever.
//
// READING THE ITEM NEEDED A THIRD ATTRIBUTE, ADDED TO THE SHARED LAYER RATHER
// THAN WORKED AROUND HERE. A macOS menu item publishes its text in **AXTitle** —
// `type=54 label="" value="" title=<text>`, measured by 08-14 — which is in
// neither of the two attributes `renderedText` asked for when this file was
// written. On its first execution this suite would have failed with a BLIND READ,
// and it would have been RIGHT to: the guard was correctly detecting a read that
// could not see its subject. The fix belongs in `app/UITestSupport/ElementText.swift`,
// which now asks `label`, then `value`, then `title`, as three NAMED attributes
// each measured against a named shape — not as "try everything until something is
// non-empty". An element publishing in none of the three still reads "" and still
// trips the guard.
//
// THE MENU IS OPENED BY IDENTITY, NOT BY POSITION — CHANGED 2026-09-15 AFTER A MEASURED
// FAILURE. The prior rule here — "index 0 of the menu bar is the Apple menu, so the
// application's own menu is index 1" — does NOT hold on every runner: run 34973317967 clicked
// exactly that ordinal and recorded the Apple menu's own contents (About This Mac, Force
// Quit…, Sleep), not the application's own menu (evidence/08.5-07-ci-readback.txt). The menu
// is now opened by `app/UITestSupport/AppMenuIdentity.swift`'s
// `selectApplicationMenuBarItemByIdentity(on:)`, the one shared helper this file and
// `DriveHalfTests.swift` both call — it compares every top-level item's AXTitle against the
// app's own name (never a hardcoded literal) and fails BY NAME if none matches. SUBSCRIPTING
// the menu-bar query with the app's display name directly is still forbidden here, and the
// forbidden shape is named in prose rather than written because `evidence/08-11-controls.rb`
// greps this file for it — a file that spells what a gate scans for sweeps that gate green by
// existing, which is the defect six Phase 5 plans hit in a row. The one such query in this
// target (`AppStoreScreenshotTests.swift:69-75`) is a headless-runner window fallback kept for
// its own reason and must not be extended.
//
// EVERY TEXT READ GOES THROUGH THE SHARED LAYER, AND ON THIS PLATFORM THAT IS
// NOT A FORMALITY. `app/UITestSupport/ElementText.swift:23-28`: macOS publishes
// a plain SwiftUI `Text`'s content in **AXValue alone**, and XCUITest's `.label`
// is built from AXDescription falling back to AXTitle and never reads AXValue —
// so `.label` is a CONSTANT EMPTY STRING here for the three commonest text
// shapes, for an element rendering the wrong string and the right string alike.
// An assertion on `.label` would compare "" with "" and pass forever. Every read
// below is `renderedText`, guarded by `assertReadable` before any comparison,
// and the expectation is guarded too — `assertRendersText` refuses a comparison
// whose expected side is itself empty.
//
// MATCHING IS A SEPARATE MECHANISM AND IS NOT BLIND. The same measurement
// records that `matching(identifier:)` COUNTS correctly on the very run where
// three `.label` reads came back empty, so the identifier query below is not
// weakened by any of the above. Reading is the blind half; finding is not.
//
// BOUNDED QUERIES ONLY (UL-064): one `count` read and a bounded loop, never a
// wait, and nothing here waits for an element expected to be ABSENT. The menu is
// closed again after every opening, so the next case does not inherit one.
//
// C-25 BOUNDS WHAT THIS PROVES: Swift 5.9 / `SWIFT_STRICT_CONCURRENCY: minimal`,
// like every file in this target, so this is META-06 evidence and never evidence
// for APP-12.

/// One privacy control reachable from every macOS surface — through the app
/// menu, read the only way this platform can be read (META-06, D-117).
///
/// SPLIT ACROSS TWO FILES FOR ONE REASON, THE SAME ONE `ScreenshotContract.swift`'s header
/// records for its own split: this file sat at `swiftlint --strict`'s 400-line file budget, and
/// `--strict` promotes that WARNING to an error (UL-056). `PrivacyLinkTestsSupport.swift` beside
/// this file carries the menu-opening, item-selection and query helpers — a cross-file
/// extension of this class, the same shape `SweepDriver.swift` already is of
/// `VisibleStringSweep.swift`. Properties and methods it needs are `internal`, NOT `private` —
/// Swift `private` does not reach a different file's extension.
@MainActor
final class PrivacyLinkTests: XCTestCase {
    /// Internal, not private: `PrivacyLinkTestsSupport.swift` is a cross-file extension of this
    /// class and Swift `private` does not reach it.
    var app: XCUIApplication!

    /// The three surfaces, `LaunchLayoutTests.swift:59-63`'s rows reused rather
    /// than re-typed. The menu item is app-wide, so what this list varies is
    /// WHICH SURFACE IS SHOWING while the menu is asked — which is the macOS
    /// reading of D-118's reachability claim.
    private static let surfaces = [
        Surface(LaunchState.encodeDestination, "encode", AccessibilityIdentifiers.Encode.input),
        Surface(LaunchState.hashingDestination, "hashing", AccessibilityIdentifiers.Hashing.input),
        Surface(LaunchState.timestampsDestination, "timestamps", AccessibilityIdentifiers.Timestamps.input)
    ]

    /// Where `CommandGroup(after: .appInfo)` puts the item: immediately after
    /// About, which is menu item index 0. Used ONLY by the fallback branch, and
    /// only after the menu's own population has been asserted to reach it.
    ///
    /// Internal, not private: read from `PrivacyLinkTestsSupport.swift`.
    static let privacyItemIndex = 1

    /// The catalog value of `app.privacyPolicy`, which is what the menu item's
    /// title renders (`app/Shared/Localizable.xcstrings`; the macOS branch of
    /// `PrivacyPolicyLink.swift` renders the key and overrides no label).
    ///
    /// **Spelled here because a UI-test process cannot reach the app's compiled
    /// catalog**, and because this is an EXPECTATION rather than a QUERY: nothing
    /// in this file FINDS an element by this string. An expectation has to come
    /// from outside the thing it judges or it judges nothing — that is the
    /// vacuous-comparison shape `assertRendersText` refuses by name.
    ///
    /// Internal, not private: read from `PrivacyLinkTestsSupport.swift`.
    static let privacyPolicyTitle = "Privacy Policy"

    /// The root card is ALONE on a surface at launch. Read from the assertion
    /// that already carries it: `app/MacOSUITests/VisibleStringSweep.swift:389`.
    private static let cardsAtLaunch = 1

    /// D-100 as a RELATION, not a literal: one remove control per APPENDED card
    /// (`app/MacOSUITests/StepEditTests.swift`, `VisibleStringSweep.swift:392`).
    private static let removesAtLaunch = cardsAtLaunch - 1

    /// The Hashing surface's four value cells, enumerated from the shipped enum.
    private static let hashingCells = [
        AccessibilityIdentifiers.Hashing.digestMD5,
        AccessibilityIdentifiers.Hashing.digestSHA1,
        AccessibilityIdentifiers.Hashing.digestSHA256,
        AccessibilityIdentifiers.Hashing.digestSHA512
    ]

    /// The Timestamps surface's representation cells, the same way.
    private static let timestampsCells = [
        AccessibilityIdentifiers.Timestamps.cellEpoch,
        AccessibilityIdentifiers.Timestamps.cellISO8601,
        AccessibilityIdentifiers.Timestamps.cellDateTime
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false

        // SKIP LIFTED 2026-09-15 FOR MEASUREMENT (D-137, G-10) — never assumed removed
        // permanently; the CI run this lift produces decides whether it stays gone or is
        // restored with THAT run's own reason (plan 08.5-08 Task 3), recorded in
        // `evidence/08.5-08-skip-measurement.txt`, not assumed here.
        //
        // PRIOR HISTORY, KEPT FOR THE READER: MEASURED 2026-09-11, this class's first ever
        // execution: the runner LAUNCHED cleanly (3 tests, 170.9 s, no Gatekeeper refusal) and
        // failed 5/5 on one assertion — `awaitSurface`, all three surfaces. `launchPinned`'s
        // destination did not take effect on macOS (`NavigationSplitView` where iOS is
        // `TabView`, `RootView.swift:157` vs `:179`), so every read below was of a window the
        // app never navigated. NOT the `AXTitle` fix, which is real and exercised on iOS.
        //
        // STILL OWED, UNCHANGED BY THIS LIFT: WR-01's identity fix below is UNVERIFIED BY
        // EXECUTION. Drive it red first — delete the privacy `CommandGroup`, expect a FAIL here
        // (plan 08.5-09).
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - D-117's macOS half, and the `[OPEN]` it depends on

    /// The app menu carries the privacy item while EACH surface is showing —
    /// asserted per surface, each failure naming its surface, before any total.
    ///
    /// **THIS ONE CASE CONTINUES AFTER A FAILURE, AND THE REASON IS THE CLAIM.**
    /// Every other case in this target stops at the first failure because it
    /// DRIVES something and a later step would measure wreckage. Nothing is
    /// driven here: each surface gets its own pinned launch, so the three
    /// measurements are independent, and stopping at the first would report one
    /// surface when three were available. "missing while Timestamps is showing"
    /// and "missing everywhere" are different defects with different causes, and
    /// a suite that can only ever name the first surface cannot tell them apart.
    func testOnePrivacyControlOnEverySurface() {
        continueAfterFailure = true
        var perSurface: [(name: String, found: Int)] = []

        for surface in Self.surfaces {
            launch(surface.destination)
            awaitSurface(surface.probe, surface.name)

            let menu = openTheApplicationMenu(on: surface.name)
            let found = assertThePrivacyItemIsInTheMenu(menu, on: surface.name)
            closeTheMenu()

            perSurface.append((surface.name, found))
        }

        // AND ONLY NOW A TOTAL, from the numbers already asserted.
        let total = perSurface.reduce(0) { $0 + $1.found }
        let breakdown = perSurface.map { "\($0.name)=\($0.found)" }.joined(separator: " ")
        record("privacy_controls_total=\(total) \(breakdown)")
        XCTAssertEqual(total, Self.surfaces.count, "privacy_controls_total=\(total), expected one per surface: \(breakdown)")
    }

    // MARK: - Present is not the same as usable

    /// The item a reviewer has to choose is hit-testable and enabled.
    func testThePrivacyControlIsHittableAndEnabled() throws {
        let surface = Self.surfaces[0]
        launch(surface.destination)
        awaitSurface(surface.probe, surface.name)

        let menu = openTheApplicationMenu(on: surface.name)
        let item = try thePrivacyItem(in: menu, on: surface.name)
        record("privacy_hittable_\(surface.name)=\(item.isHittable) privacy_enabled_\(surface.name)=\(item.isEnabled)")
        XCTAssertTrue(item.isHittable, "the privacy item in the app menu is not hit-testable on \(surface.name)")
        XCTAssertTrue(item.isEnabled, "the privacy item in the app menu is disabled on \(surface.name)")
        closeTheMenu()
    }

    // MARK: - The control added chrome, not content

    /// Every Phase 7 structural count on every surface is where Phase 7 left it.
    ///
    /// The expectations are read from the assertions that already carry them, not
    /// typed from a plan — plan literals go stale by allocation.
    func testStructuralCountsAreUnchangedOnEverySurface() {
        for surface in Self.surfaces {
            launch(surface.destination, probingPersistence: true)
            awaitSurface(surface.probe, surface.name)
            recordWindowPersistence(on: surface.name)

            let cards = count(AccessibilityIdentifiers.Step.card)
            let adds = count(AccessibilityIdentifiers.Step.addStep)
            let removes = count(AccessibilityIdentifiers.Step.remove)
            record("structural_\(surface.name) cards=\(cards) addsteps=\(adds) removes=\(removes)")

            XCTAssertEqual(cards, Self.cardsAtLaunch, "\(surface.name): \(cards) cards at launch, expected the pinned root alone")
            XCTAssertEqual(removes, Self.removesAtLaunch, "\(surface.name): \(removes) remove controls beside \(cards) cards")
            // Per-output and therefore per-surface, so the Phase 7 assertion on
            // it is "greater than zero" and this one is the same assertion; the
            // number itself is recorded above.
            XCTAssertGreaterThan(adds, 0, "\(surface.name): no add-step control at launch at all")

            assertCellsAreIntact(on: surface)
        }
    }

    /// One element per declared value cell on the surface that owns them.
    ///
    /// **The worked value is clicked in first**, because `OutputBlock.swift:65-73`
    /// attaches the value identifier on the `.value` branch ALONE: a cell showing
    /// a placeholder carries no identifier at all. Measured on the iOS twin —
    /// all three `Timestamps.cell.*` count 0 at launch and 1 after one click,
    /// while the four Hashing digests count 1 either side because
    /// `DigestRow.swift:141` attaches unconditionally. Asserting at launch would
    /// have been an assertion about the EMPTY state wearing this name.
    private func assertCellsAreIntact(on surface: Surface) {
        let cells: [String]
        let example: String
        switch surface.name {
        case "hashing":
            cells = Self.hashingCells
            example = AccessibilityIdentifiers.Hashing.useExample
        case "timestamps":
            cells = Self.timestampsCells
            example = AccessibilityIdentifiers.Timestamps.useExample
        default:
            return
        }

        let button = element(example)
        XCTAssertTrue(button.waitForExistence(timeout: 20), "\(surface.name): no worked-value button carries \(example)")
        button.click()

        for cell in cells {
            let found = count(cell)
            record("structural_\(surface.name)_cell \(cell)=\(found)")
            XCTAssertEqual(found, 1, "\(surface.name): \(found) elements carry \(cell), expected exactly 1")
        }
    }

    // The menu-opening, item-selection, launch and query helpers below moved to
    // `PrivacyLinkTestsSupport.swift` — see this class's own header comment.
}
