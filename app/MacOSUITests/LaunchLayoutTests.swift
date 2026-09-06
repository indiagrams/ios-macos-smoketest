import XCTest

// THE macOS TWIN OF `app/UITests/LaunchLayoutTests.swift`, DELIBERATELY THE SAME CLASS NAME so it
// is selectable as `-only-testing:AppMacOSUITests/LaunchLayoutTests` beside the iOS suite's
// `-only-testing:AppUITests/LaunchLayoutTests` — the shape the shipped `ShellTests` and
// `StepEditTests` pairs follow. `evidence/07-11-verify-twins.rb` keeps the two honest against the
// app's OWN identifier declaration and not merely against each other: a comparison whose
// population is "the two copies" exits 0 on an identical omission in both, which 07-07 and 07-10
// each measured on their own twin gates.
//
// CRITERION 5 IS THE LOAD-BEARING ONE: `docs/REVIEW-ARGUMENTS.md` asserts to Apple, in three
// places, that a tool screen IS the app's primary work surface. D-102'S THREE CLAUSES: (1) PRESENT
// — `Step.addStep` count > 0 at launch; (2) HIT-TESTABLE — the FIRST control
// `exists && isHittable` taken BEFORE any scroll, plus the UI-SPEC's geometric wording that its
// hit rect lies inside the window; (3) REACHABLE — structural, nothing is clicked first.
//
// THE THREE TRAPS, HONOURED HERE AS ON iOS. Clause 2 is about HITTABILITY and NEVER about
// enablement: the input is empty at launch so the control is legitimately `.disabled(true)`
// (`OutputAccessory.swift:140`, `:183`), and in XCUITest the two are INDEPENDENT — an `isEnabled`
// assertion would fail a correct app, so none appears in a clause-2 message and the reason is
// written into the message itself. Clause 3 forbids the control being BEHIND a menu, not
// PRESENTING one. And "no prior interaction" permits one action, the navigation that selects the
// destination — spent here on a launch PIN, so the clause methods perform ZERO clicks.
//
// THE SCOPE CLAUSE THIS PLATFORM CARRIES IS THE WINDOW, NOT THE TEXT SIZE: criterion 5 names the
// macOS minimum 720 x 480, which `RootView.swift:222` declares through
// `Spacing.macOSMinWindowWidth` / `Spacing.macOSMinWindowHeight`. macOS has no Dynamic Type
// argument to pin. `assertTheMeasuredEnvironment(_:)` states the one gap this leaves.
//
// WHERE THIS RUNS, AND WHY NOT HERE. Measured 2026-09-06, attended: the runner IS signed and
// carries no quarantine attribute, and `spctl -a -t exec` still answers `rejected,
// origin=Apple Development` — Gatekeeper's EXECUTION POLICY refuses a Development-signed bundle
// that is neither Developer ID nor notarised. CI is the arbiter, and a measured one: `pr.yml`'s
// `test macOS (unsigned)` runs a full-scheme `xcodebuild test` and `AppMacOSUITests.xctest` has
// passed there. `xcbeautify` renders no `XCTContext` activity and the run uploads no artifacts, so
// a CI transcript carries each case's VERDICT and not its numbers — every assertion below is
// written to be meaningful from its case name alone. D-107 route 1 throughout; C-25 pins this to
// Swift 5.9, so this is never evidence for APP-12.

/// Criterion 5's three clauses measured cold on every surface, and criterion 3's real quit and
/// relaunch, including the one UI clause persistence imposes (D-102, D-95, D-98, APP-13).
@MainActor
final class LaunchLayoutTests: XCTestCase {
    /// The application under test. Not `private`: `LaunchLayoutSupport.swift` extends this class
    /// from another file, and `private` is file-scoped in Swift.
    var app: XCUIApplication!

    /// The scope these assertions are taken at, in the amended criterion's own terms.
    private static let scope = "dynamic-type-large,iphone-se-portrait,macos-720x480"

    /// macOS has no Dynamic Type argument to pin — the scope clause it carries is the WINDOW, not
    /// the text size. Declared anyway so both twins launch through one shape rather than two.
    static let environmentPinning: [String] = []

    /// The declared minimum window, which criterion 5 names in its own words as 720 x 480.
    static let minimumWindow = CGSize(width: 720, height: 480)

    /// The three surfaces, in shell order.
    static let surfaces = [
        Surface(LaunchState.encodeDestination, "encode", AccessibilityIdentifiers.Encode.input),
        Surface(LaunchState.hashingDestination, "hashing", AccessibilityIdentifiers.Hashing.input),
        Surface(LaunchState.timestampsDestination, "timestamps", AccessibilityIdentifiers.Timestamps.input)
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
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

    /// The additive assertion the UI contract recommends, in its OWN method so the click it
    /// performs cannot contaminate the no-prior-interaction ones. It also PAYS FOR TRAP 1: the
    /// control really is disabled on an empty input.
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
