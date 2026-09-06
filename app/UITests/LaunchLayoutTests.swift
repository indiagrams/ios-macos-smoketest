import XCTest

// CRITERION 5 IS THE LOAD-BEARING ONE, AND THIS FILE IS THE THING THAT CAN FALSIFY IT.
// `docs/REVIEW-ARGUMENTS.md` asserts to Apple, in three places, that a tool screen IS the app's
// primary work surface. Criteria 1 and 2 prove the chaining capability EXISTS; this one proves it
// is PRIMARY. A false pass does not ship a bug, it ships an argument App Review will test against
// the running app — so every clause is measured cold, on every surface, and its number is recorded
// rather than summarised as "green". D-102'S THREE CLAUSES, AS ASSERTION SHAPES: (1) PRESENT —
// `Step.addStep` count > 0 on the surface at launch; (2) HIT-TESTABLE — the FIRST control
// `exists && isHittable`, taken BEFORE any scroll, plus the UI-SPEC's geometric wording, that its
// hit rect lies inside the window; and (3) REACHABLE — structural, nothing is tapped first.
//
// TRAP 1, THE ONE THAT WOULD FAIL A CORRECT APP: CLAUSE 2 IS ABOUT HITTABILITY AND NEVER ABOUT
// ENABLEMENT. At launch the input is empty, so the add-step control is legitimately
// `.disabled(true)` — you cannot chain a value that does not exist, and 06-UI-SPEC State Contract 1
// requires it PRESENT and disabled rather than hidden (`OutputAccessory.swift:140`, `:183`). In
// XCUITest `isHittable` and `isEnabled` are INDEPENDENT. No clause-2 assertion here reads
// `isEnabled`, and the reason is repeated in the assertion messages so a later reader does not
// "fix" the omission. That the control really IS disabled at launch is measured too, in its own
// method, where enablement is the subject rather than a confound.
//
// TRAP 2: CLAUSE 3 DOES NOT FORBID THE CONTROL FROM *PRESENTING* A MENU. The add-step control IS a
// `Menu`; that is shipped. Clause 3 forbids the control from being BEHIND something. TRAP 3: "no
// prior interaction" permits exactly ONE action, the navigation that selects the destination —
// and this suite spends even that on a launch PIN, so the clause methods perform ZERO taps and
// record the number (`criterion5_taps_before_assertion_<surface>=0`).
// `evidence/07-11-verify-twins.rb` enforces it structurally, refusing a driving call anywhere in
// the clause method or the helpers it reaches.
//
// THE SCOPE IS PART OF THE CRITERION AND IS SET, NOT INHERITED. Dynamic Type `.large` — the
// DEFAULT a launched simulator and a reviewer's device use — is pinned through
// `-UIPreferredContentSizeCategoryName`; portrait is set in `setUpWithError`; and the screen the
// clauses were measured at is RECORDED on every run. Nothing here clamps Dynamic Type, which
// Phase 6's contract forbids, and at accessibility sizes the layout is PERMITTED to scroll. The
// worst case is iPhone SE (3rd generation), 375 x 667, where the margin is ~77 pt against an 88 pt
// two-hit-target floor (`07-UI-SPEC.md` §"The margin, measured"). The size is RECORDED and not
// asserted on purpose: `pr.yml` picks whatever iPhone its runner has, and a device assertion would
// turn a required check red on every pull request. The worst-case requirement is enforced where it
// belongs — in `evidence/07-11-verify-scope.rb`, against the number this file records.
//
// D-107 ROUTE 1 THROUGHOUT: identifier-scoped, bounded, count-based queries; `exists` before any
// wait; no wait on an element that should be ABSENT. C-25 bounds what this proves: both UI-test
// targets are pinned to `SWIFT_VERSION: "5.9"` / `SWIFT_STRICT_CONCURRENCY: minimal`, so this is
// never evidence for APP-12, and everything below is Swift 5.9. And `print` from a UI-test bundle
// does not reach xcodebuild's pipe (06-16, both platforms), so every labelled line is emitted
// twice — `print`, and an `XCTContext` activity that lands in the `.xcresult`.

/// Criterion 5's three clauses measured cold on every surface, and criterion 3's real quit and
/// relaunch, including the one UI clause persistence imposes (D-102, D-95, D-98, APP-13).
@MainActor
final class LaunchLayoutTests: XCTestCase {
    /// The application under test. Not `private`: `LaunchLayoutSupport.swift` extends this class
    /// from another file, and `private` is file-scoped in Swift.
    var app: XCUIApplication!

    /// The scope these assertions are taken at, in the amended criterion's own terms.
    private static let scope = "dynamic-type-large,iphone-se-portrait,macos-720x480"

    /// Dynamic Type `.large`, pinned as the DEFAULT rather than clamped. `UICTContentSizeCategoryL`
    /// is UIKit's own name for `.large`, and the argument domain fixes it with no shipped code.
    static let environmentPinning = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]

    /// The worst case the margin was measured on: iPhone SE (3rd generation), 375 x 667 pt.
    static let worstCase = CGSize(width: 375, height: 667)

    /// The three surfaces, in shell order.
    static let surfaces = [
        Surface(LaunchState.encodeDestination, "encode", AccessibilityIdentifiers.Encode.input),
        Surface(LaunchState.hashingDestination, "hashing", AccessibilityIdentifiers.Hashing.input),
        Surface(LaunchState.timestampsDestination, "timestamps", AccessibilityIdentifiers.Timestamps.input)
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Criterion 5, then criterion 3

    /// The three clauses, on all three surfaces, with nothing tapped first.
    func testCriterion5ThreeClausesHoldOnEverySurfaceWithNoPriorInteraction() {
        record("criterion5_scope=\(Self.scope)")
        for surface in Self.surfaces {
            assertTheThreeClauses(surface.destination, surface.name, surface.probe)
        }
        record("criterion5_surfaces_covered=\(Self.surfaces.count)")
    }

    /// One surface, measured cold. **NOTHING IS DRIVEN IN HERE AND THAT IS THE ASSERTION:** the
    /// destination is chosen by the launch pin, so clause 3 is a property of this method's SHAPE
    /// and not of a comment claiming it. The pin is also what makes the measurement about a
    /// specific surface seen COLD: once `selection` persists, an unpinned launch measures whatever
    /// the previous case left, and the evidence would be about test ordering.
    private func assertTheThreeClauses(_ destination: String, _ surface: String, _ probe: String) {
        launch(destination)
        awaitSurface(probe, surface)
        let window = assertTheMeasuredEnvironment(surface)

        // Clause 1 — present.
        let present = count(AccessibilityIdentifiers.Step.addStep)
        record("criterion5_present_\(surface)=\(present)")
        XCTAssertGreaterThan(present, 0, "clause 1: \(surface) renders no add-step control at launch at all")

        // Clause 2 — hit-testable without scrolling, taken BEFORE any scroll, and in the UI-SPEC's
        // own geometric wording as well. EVERY rect on the surface is RECORDED FIRST, so a failure
        // carries the geometry that caused it instead of only the verdict.
        let rects = (0 ..< present).map { all(AccessibilityIdentifiers.Step.addStep).element(boundBy: $0).frame }
        let first = all(AccessibilityIdentifiers.Step.addStep).element(boundBy: 0)
        let hittable = first.exists && first.isHittable
        let inside = !rects[0].isEmpty && window.contains(rects[0])
        record("criterion5_hittable_\(surface)=\(hittable)")
        record("criterion5_within_window_\(surface)=\(inside) window=\(describeRect(window)) "
            + "rects=\(rects.map(describeRect).joined(separator: " "))")
        XCTAssertTrue(
            hittable,
            "clause 2: the first add-step control on \(surface) is not hit-testable at launch without scrolling, "
                + "at \(describeRect(rects[0])) inside \(describeRect(window)). This assertion is deliberately about "
                + "HITTABILITY and never about isEnabled: the input is empty at launch so the control is "
                + "legitimately disabled, and in XCUITest the two are independent — an isEnabled assertion here "
                + "would fail a correct app."
        )
        XCTAssertTrue(inside, "clause 2: \(surface)'s add-step rect \(describeRect(rects[0])) is not inside \(describeRect(window))")

        // Clause 3 — structural, and recorded as the number it actually is.
        record("criterion5_priorinteraction_\(surface)=navigation-only")
        record("criterion5_taps_before_assertion_\(surface)=0")
    }

    /// The additive assertion the UI contract recommends, in its OWN method so the tap it performs
    /// cannot contaminate the no-prior-interaction ones. It also PAYS FOR TRAP 1: the control
    /// really is disabled on an empty input.
    func testTheAddStepControlBecomesEnabledAfterOneTapOnTheWorkedValue() {
        launch(LaunchState.encodeDestination)
        awaitSurface(AccessibilityIdentifiers.Encode.input, "encode")

        let atLaunch = all(AccessibilityIdentifiers.Step.addStep).element(boundBy: 0)
        XCTAssertTrue(atLaunch.exists, "no add-step control on the Encode surface at launch")
        let disabled = !atLaunch.isEnabled
        record("criterion5_disabled_at_launch=\(disabled)")
        XCTAssertTrue(disabled, "the add-step control is already enabled on an empty input, so the change below is vacuous")

        tapUseExample(AccessibilityIdentifiers.Encode.useExample)

        let afterOneTap = all(AccessibilityIdentifiers.Step.addStep).element(boundBy: 0)
        XCTAssertTrue(afterOneTap.exists, "the add-step control disappeared when the input was filled")
        record("criterion5_enabled_after_one_tap=\(afterOneTap.isEnabled)")
        XCTAssertTrue(afterOneTap.isEnabled, "a working chain is not one tap away: the control is still disabled")
    }

    /// A real quit and relaunch: the last-used surface and its setting survive; the pipeline, the
    /// input and the outputs do not.
    func testCriterion3TheAppReopensOnTheLastUsedSurfaceWithSettingsIntact() {
        // NEITHER LAUNCH PINS A `SettingsKey`, AND THE FIRST ONE'S ABSTENTION WAS FORCED BY A
        // MEASUREMENT RATHER THAN CHOSEN. Pinning the second launch would assert `NSArgumentDomain`
        // instead of the on-disk store — the correct check pointed at the wrong population, in its
        // purest form. Pinning the FIRST one is worse and less obvious: `AppModel.hydrate()` runs
        // inside `init`, and `@State private var model = AppModel()` re-evaluates that initialiser
        // on every render pass, so a throwaway model is built, reads the HIGHEST-RANKING domain and
        // writes what it read straight back through `didSet`. With a pin in place that domain is
        // the argument domain, so each re-render re-writes the PINNED value over whatever the user
        // has since chosen. Measured on iOS 17.5, both directions: after a pinned launch a tab tap
        // leaves `settings.selection` at the pinned value 8 s later, and the identical tap after an
        // unpinned launch persists correctly. A pinned first launch cannot prove a relaunch claim.
        // The order-independence a pin would have bought is bought by DRIVING instead — this method
        // navigates to its own surface and changes its own setting, which ``LaunchState``'s
        // `onlySurface(_:)` already names as the stronger of the two guarantees.
        app = XCUIApplication()
        app.launchArguments = Self.environmentPinning
        app.launch()
        record("criterion3_opened_on=\(surfaceShowing())")

        // ENCODE FIRST, THEN TIMESTAMPS, so the run always contains a real change of surface even
        // when the previous case happened to leave the app on the target. And the target is chosen
        // to make the assertion NON-VACUOUS: `Destination`'s declared default is `.encode`, so an
        // app that persisted nothing at all would reopen there and fail the restore assertion
        // rather than pass it by coincidence.
        navigateToEncode()
        navigateToTimestamps()
        record("criterion3_navigated=encode->timestamps")
        let before = selectionShown(AccessibilityIdentifiers.Timestamps.readAs)
        XCTAssertFalse(before.isEmpty, "the Read as picker shows no selection at all, so the comparison below is vacuous")

        // THE PIPELINE IS BUILT BEFORE THE SETTING IS CHANGED, AND THE ORDER IS MEASURED RATHER
        // THAN STYLISTIC: moving "Read as" off the detected format makes the worked example
        // unparseable, every cell renders a failure, and `OutputAccessory`'s `isEnabled` goes false
        // — so an add-step tap after the change finds a disabled control and the menu never opens.
        tapUseExample(AccessibilityIdentifiers.Timestamps.useExample)
        addOneStep()
        XCTAssertEqual(count(AccessibilityIdentifiers.Step.card), 2, "the add-step control appended nothing to carry across")

        let changed = changeTheReadAsSegment()
        XCTAssertNotEqual(changed, before, "the Read as segment did not change, so nothing was persisted to survive")

        app.terminate()
        relaunchWithNothingPinned()

        // EVERYTHING IS READ AND RECORDED BEFORE ANY OF IT IS ASSERTED, so one failing half cannot
        // hide the other three: "which surface" and "which setting" are separate claims about the
        // same store, and a run that only ever reports the first tells a reader nothing about it.
        let surface = surfaceShowing()
        navigateToTimestamps()
        let restored = selectionShown(AccessibilityIdentifiers.Timestamps.readAs)
        let cards = count(AccessibilityIdentifiers.Step.card)
        let emptied = element(AccessibilityIdentifiers.Timestamps.useExample).waitForExistence(timeout: 20)
        record("criterion3_surface_restored=\(surface)")
        record("criterion3_settings_restored=\(restored == changed) shown=\(restored) expected=\(changed)")
        record("criterion3_cards_restored=\(cards > 1)")
        record("criterion3_input_restored=\(!emptied)")

        XCTAssertEqual(surface, "timestamps", "the app reopened on \(surface), not on the surface it was left on")
        XCTAssertEqual(restored, changed, "the Read as setting reopened as \(restored), not as the \(changed) it was left on")

        // AND WHAT D-95 DOES **NOT** RESTORE. A test asserting only what survives would pass on an
        // app that had begun persisting the user's pasted text — the AR-03 clause this phase keeps.
        XCTAssertEqual(cards, 1, "\(cards) cards after the relaunch — the appended pipeline survived the quit")
        XCTAssertTrue(emptied, "no worked-value button, which renders only on an EMPTY input: the text survived the quit")
    }

    /// D-98 on the RENDERED app rather than in the model: an unresolvable persisted value never
    /// leaves a control without a selection. **No case asserts a nil read** — `string(forKey:)`
    /// COERCES `42` to `"42"` [measured, 07-RESEARCH §7.4], so a nil-expecting assertion passes for
    /// the wrong reason and keeps passing on a broken app.
    func testCorruptPersistedValuesNeverRenderAControlWithoutASelection() {
        assertEveryControlShowsASelection(LaunchState.destinationThatDoesNotResolve, "unresolvable-destination")
        assertEveryControlShowsASelection(LaunchState.integerWhereAStringBelongs, "integer-where-a-string-belongs")
        assertEveryControlShowsASelection(LaunchState.plistArrayWhereAStringBelongs, "array-where-a-string-belongs")
        assertEveryControlShowsASelection(
            LaunchState.onlySurface(LaunchState.timestampsDestination) + LaunchState.timeZoneTheSystemRejects,
            "rejected-time-zone"
        )
    }

    /// One corruption case, injected and read off the screen. The time-zone case pins the surface
    /// too, with the reason ``LaunchState``'s `onlySurface(_:)` asks for: its assertion is about
    /// Timestamps' controls, so which surface opens must not be left to what ran before.
    private func assertEveryControlShowsASelection(_ pinning: [String], _ caseName: String) {
        app = XCUIApplication()
        app.launchArguments += Self.environmentPinning + pinning
        app.launch()

        let surface = surfaceShowing()
        record("criterion3_corrupt_\(caseName)_surface=\(surface)")
        XCTAssertFalse(surface.isEmpty, "\(caseName): no surface rendered at all")

        navigateToEncode()
        assertShowsASelection(AccessibilityIdentifiers.Encode.format, "encode format", caseName)
        assertShowsASelection(AccessibilityIdentifiers.Encode.direction, "encode direction", caseName)

        navigateToTimestamps()
        assertShowsASelection(AccessibilityIdentifiers.Timestamps.readAs, "read as", caseName)
        assertShowsASelection(AccessibilityIdentifiers.Timestamps.timeZone, "time zone", caseName)
        record("criterion3_corrupt_\(caseName)=ok")
    }

    /// A control renders, and renders WITH a selection. A blank control is a UI failure and not
    /// just a model one (D-98, CR-02's class).
    private func assertShowsASelection(_ identifier: String, _ named: String, _ caseName: String) {
        let control = element(identifier)
        XCTAssertTrue(control.waitForExistence(timeout: 20), "\(caseName): the \(named) control is not rendered at all")
        let shown = selectionShown(identifier)
        XCTAssertFalse(shown.isEmpty, "\(caseName): the \(named) control renders with NO selection — D-98's exact "
            + "failure. value=\(String(describing: control.value)) label=\(control.label) "
            + "segments=\(segments(of: control).count)")
    }
}
