import XCTest

// THE D-93 VISIBLE-STRING SWEEP, macOS HALF. ROADMAP Phase 6 criterion 6; PRIV-06.
//
// ROUTED BY PLAN 06-01's MEASURED VERDICT, NOT BY ASSUMPTION. That plan asked whether a macOS UI test
// executes at all on a headless GitHub Actions runner, wrote routing for all four possible answers
// before anything depended on one, and recorded `probe_verdict=viable` (harvested_strings=114,
// reached_subject=true, runner_headless=true; run 33925478706). The `viable` branch says: write the
// macOS twin exactly like the iOS one, on the template-owned `pr.yml` unedited, and delete the probe.
//
// TWO CONSTRAINTS 06-01 MEASURED, WHICH SHAPE EVERYTHING BELOW:
//
//  1. A `print` FROM THIS BUNDLE NEVER REACHES THE CI LOG. The bundle is injected into
//     `AppMacOSUITests-Runner.app`, launched by `testmanagerd`, whose stdout is not connected to
//     xcodebuild's pipe; only XCTest's own IPC crosses back. Every number therefore rides an
//     ASSERTION MESSAGE or an `XCTContext` activity. A green `XCTAssertGreaterThan(count, 20)`
//     proves the predicate, not the number.
//  2. THE HARVEST IS MOSTLY NOT THE APP. `try app.snapshot()` on the application element returns the
//     whole menu bar. `SweepPopulation` is the counted exclusion that fixes it; see that file.
//
// THE DETECTION IDIOM IS COPIED FROM `AppStoreScreenshotTests.swift:52-54`; THE SKIP IS NOT, AND
// NEITHER IS THE FOREGROUND-ACTIVATION CALL. launchd scrubs `CI` and `GITHUB_ACTIONS` from the
// runner's environment, so the home directory is the only usable signal — recorded here as an
// observable FACT rather than branched on. A sweep that skipped would be a gate that has never
// executed, the row this phase inherited and the one 06-14's macOS assertion fell into.
//
// C-25 BOUNDS WHAT THIS PROVES: this target is pinned to Swift 5.9 / minimal concurrency, so the file
// is criterion-6 evidence only and NEVER evidence for APP-12.
//
// NEVER QUERY BY VISIBLE TEXT. Every element is addressed by an `AccessibilityIdentifiers` constant.

/// Every string the app renders, on every surface, in both appearances — and no prose term among them.
@MainActor
final class VisibleStringSweep: XCTestCase {
    /// Internal, not private: `SweepDriver.swift` and `SweepSurfaces.swift` are cross-file
    /// extensions of this class and Swift `private` does not reach them.
    typealias Ident = AccessibilityIdentifiers

    /// Internal rather than private: `SweepDriver.swift` is a cross-file extension of this class
    /// and Swift `private` does not reach it. Nothing outside this target can see either.
    var app: XCUIApplication!

    /// The application element's own `label`. EMPTY ON macOS, and that is a measurement rather than an
    /// expectation: run 33959451763, job `app (macOS)`, failed clause 3 with
    /// `XCTAssertGreaterThan failed: ("0") is not greater than ("3") - the application element carries
    /// no name`, after a full 82.8-second walk. The iOS twin reads the display name straight off this
    /// property; on macOS it is blank and the name has to come from the menu bar instead.
    var applicationLabel = ""

    /// The menu bar's top-level item titles, in order. Index 1 is the application menu, which is what
    /// settles RESEARCH assumption A3 — whether AppKit resolves that title from `CFBundleDisplayName`
    /// or `CFBundleName` was deliberately left unmeasured, and this reads it off the running app.
    var menuBarItems: [String] = []

    /// The product name as the RUNNING APP presents it, with the source it came from.
    ///
    /// Never spelled here. Reading it from the app rather than from a plist is what lets clause 3 hold
    /// after a rename, and what keeps this file from naming an identity it exists to keep off screens.
    private var productName: (value: String, source: String) {
        if !applicationLabel.isEmpty {
            return (applicationLabel, "application-element-label")
        }
        if menuBarItems.count > 1 {
            return (menuBarItems[1], "menu-bar-application-item")
        }
        return ("", "none")
    }

    /// The floor for `harvested_distinct`. A floor rather than an equality, so adding a string cannot
    /// break the gate but losing a surface must.
    ///
    /// MEASURED, not guessed, and it took a deliberately red run to measure it: no number this bundle
    /// produces reaches the workflow log (06-01), so the distinct count could only arrive in a run
    /// whose assertion message carried it. Run 33960685203, job `app (macOS)`, with every real
    /// assertion passing and only the temporary counters `XCTFail` failing:
    /// `harvested_strings=2192 harvested_distinct=94 system_chrome_strings=7644
    /// system_data_strings=22 platform_control_strings=152`. The floor is 85 — nine below the
    /// measurement, and low enough that adding strings cannot break it while losing the smallest
    /// surface (Hashing, about eleven distinct strings) still trips it.
    private static let distinctFloor = 85

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - The gate

    /// The fourteen-step walk, in both appearances, then the assertions in the order that matters.
    func testNoProseTermIsRenderedOnAnySurface() throws {
        var seen = SweepHarvest()
        let headless = NSHomeDirectory() == "/Users/runner"

        for scheme in ["light", "dark"] {
            app = XCUIApplication()
            app.launchArguments = ["-UITestColorScheme", scheme]
            app.launchPinned(onlySurface: LaunchState.encodeDestination) // 07-07, and only the surface
            try walk(into: &seen)
            app.terminate()
        }

        let rendered = seen.rendered
        let distinct = Set(rendered)
        let counters = "runner_headless=\(headless) harvested_strings=\(rendered.count) "
            + "harvested_distinct=\(distinct.count) system_chrome_strings=\(seen.chrome.count) "
            + "system_data_strings=\(seen.systemData.count) "
            + "platform_control_strings=\(seen.platformControl.count)"
        print(counters)
        // The one channel that crosses testmanagerd's boundary on a green run. A green that recorded
        // no number would be a green about nothing.
        XCTContext.runActivity(named: "SWEEP_COUNTERS \(counters)") { _ in }
        XCTContext.runActivity(named: "A3_MENU_BAR \(menuBarItems.prefix(8).joined(separator: " | "))") { _ in }
        XCTContext.runActivity(named: "A3_PRODUCT_NAME source=\(productName.source) value=\(productName.value)") { _ in }

        // 1 — DID IT REACH ITS SUBJECT? Asserted before, and separately from, anything about prose.
        // The counters ride the MESSAGE, because that is the only way a number leaves this process.
        XCTAssertGreaterThan(
            rendered.count,
            20,
            "the sweep saw almost nothing — it did not reach the app. \(counters)"
        )
        XCTAssertGreaterThanOrEqual(
            distinct.count,
            Self.distinctFloor,
            "the population shrank below the floor \(Self.distinctFloor). \(counters)"
        )

        // 2 — and only then, the prose condition, over the rendered bucket alone.
        for string in distinct.sorted() {
            let lowered = string.lowercased()
            if let term = SweepPopulation.proseTerms.first(where: { lowered.contains($0) }) {
                XCTFail("a prose term is rendered on a surface: '\(term)' appears in \"\(string)\"")
            }
        }

        // 3 — PRIV-06's own clause: the product name reaches the screen ONLY through system chrome.
        // Derived from the running app rather than spelled, so this file names no identity, follows a
        // rename, and covers both the display-name and product-name spellings 06-01 saw in the tree.
        let name = productName
        let squashed = SweepPopulation.squash(name.value)
        XCTAssertGreaterThan(
            squashed.count,
            3,
            "the running app names itself nowhere the sweep can read — clause 3 cannot run. "
                + "a3_menu_title_source=\(name.source) menu_bar=\(menuBarItems.prefix(4).joined(separator: " | "))"
        )
        for string in distinct.sorted() where SweepPopulation.squash(string).contains(squashed) {
            XCTFail("the product name is rendered outside system chrome: it appears in \"\(string)\"")
        }
    }

    // MARK: - The walk

    /// Launch, then each surface in turn, harvesting after every step. Then steps 11-14, which
    /// plan 07-12 appended and which run inside this function for the same reason the other steps
    /// do — so the appearance loop above carries them too.
    private func walk(into out: inout SweepHarvest) throws {
        XCTAssertTrue(
            element(Ident.Shell.sidebarEncode).waitForExistence(timeout: 30),
            "the app did not present its first destination — no element carries \(Ident.Shell.sidebarEncode)"
        )
        try snap(into: &out)

        try encodeSurface(into: &out)

        visit(Ident.Shell.sidebarHashing)
        try snap(into: &out)
        try hashingSurface(into: &out)

        visit(Ident.Shell.sidebarTimestamps)
        try snap(into: &out)
        try timestampsSurface(into: &out)

        try footerEditsAndTheRoot(into: &out)
    }

    /// One measured number out of the walk. A `print` from this bundle never reaches the workflow
    /// log (06-01), so every number also rides an `XCTContext` activity — the one channel that
    /// crosses testmanagerd. Kept as a function so the four steps below are byte-identical twins
    /// of the iOS ones.
    private func record(_ line: String) {
        print(line)
        XCTContext.runActivity(named: line) { _ in }
    }

    // MARK: - Steps 11-14: the footers, a move, a removal, and the root alone

    /// The four steps 07-UI-SPEC §"Harvest Population — delta" appends to the ten above. Inside
    /// `walk(into:)`, so they run in BOTH appearances like every other step.
    ///
    /// ON THE ENCODE SURFACE, AND THAT IS FORCED RATHER THAN CHOSEN. Step 13 needs a step that
    /// FAILS with another step below it, and encode/decode is the only surface whose root output
    /// can be turned into invalid input for the operation beneath it: hashing cannot fail (any
    /// `String` has a UTF-8 encoding and every encoding has a digest) and the timestamps
    /// conversions are not chainable at all, which `Operation`'s own header states.
    ///
    /// WHAT THIS BRINGS INTO THE POPULATION, which is the entire point of appending it:
    /// `Step.position` on every card at four stack lengths, `Step.rootNote` on the root, the three
    /// footer control labels, the container label at those same lengths, and the values a reorder
    /// and a splice recompute. The two ANNOUNCEMENTS are not here and cannot be — the measured
    /// reason and their alternative coverage site are in `SweepPopulation.phase7Strings`.
    private func footerEditsAndTheRoot(into out: inout SweepHarvest) throws {
        visit(Ident.Shell.sidebarEncode)
        try twoAppendedCards(into: &out)
        try readEveryFooter(into: &out)
        try moveTheFirstAppendedCardDown(into: &out)
        try removeTheFailingStep(into: &out)
        try emptyTheStackToTheRoot(into: &out)
    }

    /// Step 11's precondition: the app's declared defaults, a worked value, and exactly two
    /// appended cards carrying DIFFERENT operations.
    ///
    /// NORMALISED FROM WHATEVER THE TEN STEPS LEFT, and that is a correctness requirement rather
    /// than tidiness. The macOS walk arrives here with the card `chainAndBlock` appended still on
    /// the stack, so appending two more would leave the first two cards holding the SAME
    /// operation — and step 12's move would then swap two identical steps, changing nothing any
    /// assertion could see. The iOS twin happens to arrive with an empty stack, but only because
    /// `dismissKeyboard` relaunches; that is an accident of another mechanism, not a guarantee,
    /// and a population that depends on one is the wrong population.
    private func twoAppendedCards(into out: inout SweepHarvest) throws {
        clearAppendedCards()
        press(segment(Ident.Encode.direction, 0), "the direction picker's encode segment")
        press(segment(Ident.Encode.format, 0), "the format picker's Base64 segment")
        if element(Ident.Encode.useExample).exists {
            press(element(Ident.Encode.useExample), "the Encode worked-value button")
        }
        try appendStep(choosing: 0, into: &out)
        try appendStep(choosing: 1, into: &out)
    }

    /// Opens the ROOT card's add-step control and chooses `menuItem` in `Operation.allCases`
    /// order — 0 is Base64 encode and 1 is Base64 decode, the two the steps below rely on being
    /// different. The menu's population is asserted before the index is taken, and the card count
    /// before and after is what proves the choice landed.
    private func appendStep(choosing menuItem: Int, into out: inout SweepHarvest) throws {
        let before = count(Ident.Step.card)
        press(control(Ident.Step.addStep, 0), "the root card's add-step control")
        let items = count(Ident.Step.addStepMenu)
        XCTAssertGreaterThan(items, menuItem, "the add-step menu presents \(items) items, so item \(menuItem) is outside it")
        press(control(Ident.Step.addStepMenu, menuItem), "the add-step menu's item \(menuItem)")
        XCTAssertTrue(
            control(Ident.Step.card, before).waitForExistence(timeout: 15),
            "the add-step menu appended no card: the stack stayed at \(before)"
        )
        try snap(into: &out)
    }

    /// Removes appended cards until none is left, and answers how many passes that took.
    ///
    /// Bounded twice over: by the remove population, which must shrink by one each pass, and by a
    /// hard trip count, so a control that stops responding ends the loop with a named failure
    /// instead of spinning against the accessibility tree — the volume D-107 is about.
    @discardableResult
    private func clearAppendedCards() -> Int {
        var remaining = count(Ident.Step.remove)
        var passes = 0
        while remaining > 0, passes < 12 {
            press(control(Ident.Step.remove, 0), "the topmost appended card's remove control")
            XCTAssertTrue(
                control(Ident.Step.remove, remaining - 1).waitForNonExistence(timeout: 15),
                "a card was dropped and its footer control is still in the tree"
            )
            remaining = count(Ident.Step.remove)
            passes += 1
        }
        XCTAssertEqual(remaining, 0, "the stack would not empty: \(remaining) footer controls left after \(passes) passes")
        return passes
    }

    /// STEP 11 — read the footer of every card on a surface with two appended cards.
    ///
    /// READ, never press. Every string a footer renders has to be in the population whether or not
    /// a control is ever activated, so this step activates nothing.
    ///
    /// The six structural invariants are asserted HERE, before anything indexes into the stack.
    /// That is this walk's house rule — assert a population before indexing into it — and they are
    /// also criterion 2's evidence, which is why the UI contract lists this step under both.
    private func readEveryFooter(into out: inout SweepHarvest) throws {
        let cards = count(Ident.Step.card)
        let positions = count(Ident.Step.position)
        let notes = count(Ident.Step.rootNote)
        let ups = count(Ident.Step.moveUp)
        let downs = count(Ident.Step.moveDown)
        let removes = count(Ident.Step.remove)
        XCTAssertGreaterThanOrEqual(cards, 3, "step 11 needs a root and two appended cards; the stack holds \(cards)")
        XCTAssertEqual(positions, cards, "\(positions) of \(cards) cards carry an ordinal")
        XCTAssertEqual(notes, 1, "\(notes) cards show the root note, expected exactly one")
        XCTAssertEqual(ups, cards - 1, "\(ups) move-up controls for \(cards) cards")
        XCTAssertEqual(downs, cards - 1, "\(downs) move-down controls for \(cards) cards")
        XCTAssertEqual(removes, cards - 1, "\(removes) remove controls for \(cards) cards — D-100 says one per APPENDED card")
        let ordinals = (0 ..< positions).map { control(Ident.Step.position, $0).label }
        XCTAssertEqual(Set(ordinals).count, positions, "two cards render the same ordinal: \(ordinals)")
        record("step11_cards=\(cards) step11_positions=\(positions) step11_rootnotes=\(notes) "
            + "step11_moveups=\(ups) step11_movedowns=\(downs) step11_removes=\(removes)")
        try snap(into: &out)
    }

    /// STEP 12 — move down on the FIRST appended card.
    ///
    /// The two cards carry different operations, so the swap is observable three ways: the
    /// ORDINALS belong to slots and must NOT move, the container labels — "Step %lld of %lld, %@"
    /// — swap their operation halves, and the value under the first appended ordinal is
    /// recomputed. Asserting the ordinals alone would prove renumbering and not recomputation,
    /// which is the distinction `StepEditTests` was written around.
    ///
    /// The MOVE ANNOUNCEMENT is posted by this press and is NOT in the tree; see
    /// `SweepPopulation.phase7Strings` for the measurement and where the string is covered.
    private func moveTheFirstAppendedCardDown(into out: inout SweepHarvest) throws {
        let cards = count(Ident.Step.card)
        let labelsBefore = (1 ..< cards).map { control(Ident.Step.card, $0).label }
        let ordinalsBefore = (0 ..< cards).map { control(Ident.Step.position, $0).label }
        let outputBefore = control(Ident.Step.output, 0).label
        press(control(Ident.Step.moveDown, 0), "the first appended card's move-down control")
        try snap(into: &out)
        XCTAssertEqual(count(Ident.Step.card), cards, "the move changed the stack length")
        let labelsAfter = (1 ..< cards).map { control(Ident.Step.card, $0).label }
        let ordinalsAfter = (0 ..< cards).map { control(Ident.Step.position, $0).label }
        let outputAfter = control(Ident.Step.output, 0).label
        XCTAssertEqual(ordinalsAfter, ordinalsBefore, "the ordinals travelled with the steps; they belong to the slots")
        XCTAssertNotEqual(labelsAfter, labelsBefore, "the move renamed nothing: still \(labelsBefore)")
        XCTAssertNotEqual(outputAfter, outputBefore, "the first appended card traded places without recomputing")
        record("step12_cards=\(cards) step12_labels_moved=true step12_ordinals_held=true")
    }

    /// STEP 13 — drive the chain into a failure, then remove the FAILING step.
    ///
    /// ONE PRESS INSTALLS THE FAILURE, and it is the root's FORMAT rather than a typed fixture.
    /// After step 12 the first appended card is a Base64 decode; switching the root to HTML makes
    /// its output — the worked value with `&`, `<` and `>` escaped — invalid Base64 at the first
    /// comma, so that card fails and the Base64 encode below it is blocked. The failing card is
    /// APPENDED, which is what makes it removable; the pinned root could not be (D-100).
    ///
    /// GREATER THAN ZERO COMES FIRST. A zero-after with no positive-before is vacuous, and this
    /// pair is criterion 2's evidence as well as this sweep's.
    private func removeTheFailingStep(into out: inout SweepHarvest) throws {
        press(segment(Ident.Encode.format, 2), "the format picker's HTML segment")
        let stalled = element(Ident.Step.blocked)
        if !stalled.exists {
            XCTAssertTrue(stalled.waitForExistence(timeout: 15), "no card is blocked, so a zero after this would prove nothing")
        }
        let blockedBefore = count(Ident.Step.blocked)
        XCTAssertGreaterThan(blockedBefore, 0, "step13_blocked_before=\(blockedBefore) — nothing is blocked")
        try snap(into: &out)

        let cardsBefore = count(Ident.Step.card)
        press(control(Ident.Step.remove, 0), "the failing card's own footer control")
        XCTAssertTrue(
            control(Ident.Step.card, cardsBefore - 1).waitForNonExistence(timeout: 15),
            "the press took no card: the stack stayed at \(cardsBefore)"
        )
        let blockedAfter = count(Ident.Step.blocked)
        XCTAssertEqual(
            blockedAfter,
            0,
            "step13_blocked_before=\(blockedBefore) step13_blocked_after=\(blockedAfter) — a card is still blocked"
        )
        record("step13_blocked_before=\(blockedBefore) step13_blocked_after=\(blockedAfter)")
        try snap(into: &out)
    }

    /// STEP 14 — take appended cards away until none remains.
    ///
    /// What is left is the pinned root ALONE: one card, one ordinal, its footer showing the root
    /// note, and not one of the three footer controls anywhere on the surface. That is the one
    /// state the ten-step walk never reaches once it has built a pipeline — and the root note is
    /// the string 06-16's population could not have contained, because 06-16 predates it.
    private func emptyTheStackToTheRoot(into out: inout SweepHarvest) throws {
        let passes = clearAppendedCards()
        let cards = count(Ident.Step.card)
        XCTAssertEqual(cards, 1, "the root card is not alone: \(cards) cards remain")
        XCTAssertEqual(count(Ident.Step.position), 1, "the root card alone carries no ordinal")
        XCTAssertEqual(count(Ident.Step.rootNote), 1, "the root card alone does not show its note")
        XCTAssertEqual(count(Ident.Step.remove), 0, "a footer control survived the last removal")
        XCTAssertEqual(count(Ident.Step.moveUp), 0, "a move-up control survived the last removal")
        XCTAssertEqual(count(Ident.Step.moveDown), 0, "a move-down control survived the last removal")
        record("step14_passes=\(passes) step14_cards=\(cards) step14_removes=0 step14_rootnotes=1")
        try snap(into: &out)
    }
}
