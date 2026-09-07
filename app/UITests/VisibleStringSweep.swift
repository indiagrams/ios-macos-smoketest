import XCTest

// THE D-93 VISIBLE-STRING SWEEP, iOS HALF. ROADMAP Phase 6 criterion 6; PRIV-06.
//
// D-94 replaced criterion 6's human "visual pass" with this: a UI test that walks every surface,
// harvests every visible string and fails on any prose term. Criterion 6 runs over the strings a
// running app RENDERS; criterion 7's `tools/check-contamination.rb` runs over the strings TRACKED
// FILES CONTAIN. Two populations on purpose — a string can be rendered and untracked, or tracked and
// never rendered, and UL-044 is what conflating them cost. The buckets, the exemptions and the frozen
// term list are in `SweepPopulation.swift`, which states in code what is in the swept set.
//
// `AccessibilityIdentifiers` (app/Shared/AccessibilityIdentifiers.swift) is compiled into BOTH the app
// target and this UI-test target via an explicit `sources:` entry in app/project.yml and
// app/Project.swift — same file path, two targets. UI tests run as a separate process and cannot link
// the app's binary, so `@testable import` does not apply. This sweep depends on that same mechanism:
// every element it drives is addressed by a shared constant and NEVER by visible text, because a sweep
// that queried by text would assert on the very strings it is testing.
//
// C-25 BOUNDS WHAT THIS PROVES. Both UI-test targets are pinned to `SWIFT_VERSION: "5.9"` /
// `SWIFT_STRICT_CONCURRENCY: minimal` because fastlane's `SnapshotHelper.swift` predates Swift 6, so
// this file is criterion-6 evidence only and NEVER evidence for APP-12. Everything below is Swift 5.9.
//
// FOUR PROPERTIES, NOT ONE. `label` alone misses every `TextField` prompt — this app has three — which
// lands in `placeholderValue`, and every field's current text, which lands in `value`. A correct check
// pointed at an incomplete population is the failure class this phase exists to stop repeating.
//
// ONE IPC ROUND TRIP PER HARVEST POINT. `try app.snapshot()` returns the whole tree in one call and
// `harvest` walks `.children` in this process; the per-element alternative costs one round trip per
// element. REACHED ITS SUBJECT FIRST, SEPARATELY: `harvested_strings=` is printed and asserted BEFORE
// any property of what was harvested, so a skip, a crash or an empty tree reads as a failure to reach
// the app rather than as a statement about what the app renders.

/// Every string the app renders, on every surface, in both appearances — and no prose term among them.
@MainActor
final class VisibleStringSweep: XCTestCase {
    /// Internal, not private: `SweepDriver.swift` and `SweepSurfaces.swift` are cross-file
    /// extensions of this class and Swift `private` does not reach them.
    typealias Ident = AccessibilityIdentifiers

    /// Internal rather than private: `SweepDriver.swift` is a cross-file extension of this class
    /// and Swift `private` does not reach it. Nothing outside this target can see either.
    var app: XCUIApplication!

    /// The application element's own name, read from the running app rather than from a plist.
    var productName = ""

    /// The measured floor for `harvested_distinct`. A floor rather than an equality: adding a string
    /// must not break the gate, but LOSING a surface must.
    ///
    /// RE-MEASURED 2026-09-06 by plan 07-12, after walk steps 11-14 were appended — measured, not
    /// bumped. 06-16 set 85 against a measured 106; the fourteen-step walk was run on two runtimes
    /// off one build on 2026-09-06:
    ///
    ///     iOS 17.5, iPhone SE (3rd generation)   harvested_distinct=142   harvested_strings=3066
    ///     iOS 18.6, iPhone 16 Pro                harvested_distinct=140   harvested_strings=3402
    ///
    /// 136 = 140, the SMALLER measurement, minus 4. The margin is twice the largest inter-runtime
    /// spread ever observed here (2 today, 1 at 06-16), so a runtime difference cannot trip the gate.
    /// It is also tight enough to keep the property 06-16's floor CLAIMED and did not have:
    /// Hashing contributes about 11 distinct strings and Timestamps about 20, and 140 - 11 = 129 and
    /// 140 - 20 = 120 both fall below 136 — where the old 85 would have let the loss of Hashing pass
    /// unnoticed, since 106 - 11 = 95 is still above it.
    ///
    /// WHAT THIS NUMBER GUARDS, AND WHAT IT DOES NOT — measured on 2026-09-06, not reasoned:
    ///
    ///     the ten-step walk on this same build        harvested_distinct=129   -> RED, 129 < 136
    ///     the fourteen-step walk minus step 13 alone  harvested_distinct=137   -> green, 137 >= 136
    ///     the fourteen-step walk minus Timestamps     harvested_distinct=128   -> RED, 128 < 136
    ///
    /// So this floor catches losing a SURFACE and it catches losing all four appended steps. It does
    /// NOT catch losing ONE of them: a single step is worth about five distinct strings, which is
    /// inside any margin wide enough to survive the runtime spread. Stated as a residual rather than
    /// closed, because closing it would mean a floor tight enough to flake — the same defect wearing
    /// the opposite sign. ``assertPhase7StringsAreRendered(in:)`` does not close it either: measured,
    /// all six harvestable strings still match under the ten-step walk, because 07-08 wired the
    /// footer into all three surfaces and that walk already appends a card on each.
    ///
    /// iOS 26.1 is absent from that table BY MEASUREMENT and not by omission: the walk does not reach
    /// its assertions on that runtime, and a pristine-tree control at 1e08537 fails identically, so
    /// the defect predates these four steps. `evidence/07-12-sweep.txt` and the phase's
    /// `deferred-items.md` carry it.
    private static let distinctFloor = 136

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

        // Step 10 is the outer loop: the whole walk again, in the other appearance. It should add no
        // new string; it is here to confirm that neither appearance HIDES one. The launch-argument
        // mechanism is `app/Shared/App.swift`'s, reused rather than `XCUIDevice.shared.appearance`,
        // whose cold-simulator handshake flakes on GHA runners.
        for scheme in ["light", "dark"] {
            app = XCUIApplication()
            app.launchArguments = ["-UITestColorScheme", scheme]
            app.launchPinned(onlySurface: LaunchState.encodeDestination) // 07-07, and only the surface
            try walk(into: &seen)
            app.terminate()
        }

        let rendered = seen.rendered
        let distinct = Set(rendered)
        print("harvested_strings=\(rendered.count)")
        print("harvested_distinct=\(distinct.count)")
        print("system_chrome_strings=\(seen.chrome.count)")
        print("system_data_strings=\(seen.systemData.count)")
        print("platform_control_strings=\(seen.platformControl.count)")
        for string in Set(seen.chrome).sorted() {
            print("system_chrome_string: \(string)")
        }
        for string in distinct.sorted() {
            print("harvested: \(string)")
        }

        // 1 — DID IT REACH ITS SUBJECT? Asserted before, and separately from, anything about prose.
        XCTAssertGreaterThan(rendered.count, 20, "the sweep saw almost nothing — it did not reach the app")
        XCTAssertGreaterThanOrEqual(
            distinct.count,
            Self.distinctFloor,
            "the population shrank: harvested_distinct=\(distinct.count), floor \(Self.distinctFloor)"
        )

        // 1b — IS IT STILL COMPLETE? A floor cannot answer that: eight new strings the walk
        // never renders would raise the count and pass. The eight are looked for BY NAME.
        assertPhase7StringsAreRendered(in: distinct)

        // 2 — and only then, the prose condition, over the rendered bucket alone.
        for string in distinct.sorted() {
            let lowered = string.lowercased()
            if let term = SweepPopulation.proseTerms.first(where: { lowered.contains($0) }) {
                XCTFail("a prose term is rendered on a surface: '\(term)' appears in \"\(string)\"")
            }
        }

        // 3 — PRIV-06's own clause: the product name reaches the screen ONLY through system chrome.
        // Derived from the running app (the application element's label) rather than spelled, so this
        // file names no identity and the check follows a rename.
        let squashed = SweepPopulation.squash(productName)
        XCTAssertGreaterThan(squashed.count, 3, "the application element carries no name — clause 3 cannot run")
        for string in distinct.sorted() where SweepPopulation.squash(string).contains(squashed) {
            XCTFail("the product name is rendered outside system chrome: it appears in \"\(string)\"")
        }
        print("product_name_outside_chrome_ios=0")
    }

    // MARK: - The walk

    /// Steps 1 and 9: launch, then each surface in turn, harvesting after every step. Then steps
    /// 11-14, which plan 07-12 appended and which run inside this function for the same reason the
    /// other steps do — so the appearance loop above carries them too.
    private func walk(into out: inout SweepHarvest) throws {
        XCTAssertTrue(
            element(Ident.Shell.tabEncode).waitForExistence(timeout: 30),
            "the app did not present its first destination — no element carries \(Ident.Shell.tabEncode)"
        )
        try snap(into: &out)

        try encodeSurface(into: &out)

        visit(1, expecting: Ident.Shell.tabHashing)
        try snap(into: &out)
        try hashingSurface(into: &out)

        visit(2, expecting: Ident.Shell.tabTimestamps)
        try snap(into: &out)
        try timestampsSurface(into: &out)

        try footerEditsAndTheRoot(into: &out)
    }

    /// One measured number out of the walk. `print` from this bundle DOES reach the log on iOS;
    /// the macOS twin adds the `XCTContext` channel, which is the only one that crosses
    /// testmanagerd (06-01). Kept as a function so the four steps below are byte-identical twins.
    func recordCounter(_ line: String) {
        print(line)
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
        visit(0, expecting: Ident.Shell.tabEncode)
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
        let ordinals = (0 ..< positions).map { readable(control(Ident.Step.position, $0)) }
        assertOrdinalsAreDistinct(ordinals, of: positions)
        recordCounter("step11_cards=\(cards) step11_positions=\(positions) step11_rootnotes=\(notes) "
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
        let ordinalsBefore = (0 ..< cards).map { readable(control(Ident.Step.position, $0)) }
        let outputBefore = readable(control(Ident.Step.output, 0))
        press(control(Ident.Step.moveDown, 0), "the first appended card's move-down control")
        try snap(into: &out)
        XCTAssertEqual(count(Ident.Step.card), cards, "the move changed the stack length")
        let labelsAfter = (1 ..< cards).map { control(Ident.Step.card, $0).label }
        let ordinalsAfter = (0 ..< cards).map { readable(control(Ident.Step.position, $0)) }
        let outputAfter = readable(control(Ident.Step.output, 0))
        XCTAssertEqual(ordinalsAfter, ordinalsBefore, "the ordinals travelled with the steps; they belong to the slots")
        XCTAssertNotEqual(labelsAfter, labelsBefore, "the move renamed nothing: still \(labelsBefore)")
        XCTAssertNotEqual(outputAfter, outputBefore, "the first appended card traded places without recomputing")
        recordCounter("step12_cards=\(cards) step12_labels_moved=true step12_ordinals_held=true")
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
        recordCounter("step13_blocked_before=\(blockedBefore) step13_blocked_after=\(blockedAfter)")
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
        recordCounter("step14_passes=\(passes) step14_cards=\(cards) step14_removes=0 step14_rootnotes=1")
        try snap(into: &out)
    }
}
