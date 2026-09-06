import XCTest

// APP-09'S EVIDENCE, ON A RUNNING APP. Nine plans built the capability to edit a chained
// pipeline; nothing had executed the claim. This file and its macOS twin are that execution.
//
// THE ONE THAT MATTERS IS THE DOWNSTREAM VALUE. ROADMAP criterion 2 says "downstream results
// updating to match". A reorder test that only checks ordinals proves RENUMBERING, not
// RECOMPUTATION — so every value assertion compares against a string this PROCESS computed, never
// against one the app also produced. A UI-test process cannot link the app module, which is a
// feature here: it forces the second computation to be independent. The source is asserted
// NON-EMPTY first, so no comparison can pass by comparing nothing with nothing
// (`ShellTests.swift:136..150` is the precedent).
//
// THE OFF-BY-ONE, WRITTEN INTO THE NAMING RATHER THAN INTO A COMMENT. `Step.remove` at
// `element(boundBy: 0)` is the FIRST APPENDED card, which the header numbers **Step 2** — the root
// step is synthesised at render time and is not in the array. Every accessor takes an
// `appendedIndex` and every message spells `Step \(appendedIndex + 2)`. The correction is NOT
// uniform across surfaces and `07-UI-SPEC.md`'s table was FALSE on Hashing until it was amended:
// the mapping lives in `StepStackPosition.modelOffset` (`app/Shared/Views/StepStack.swift:68`) and
// is `stepOffset: 1` on Hashing alone, because `model.hashing.steps.first` IS the chain root.
//
// D-107 ROUTE 1 IS MANDATORY AND THIS FILE IS ITS FIRST REAL STRESS. Every query is
// identifier-scoped, bounded and COUNT-based; there is no whole-tree walk and no wait on anything
// that should be ABSENT. D-100's "the root has no remove control" is asserted as
// `count(Step.remove) == count(Step.card) - 1`, never as a wait for an element that will never
// arrive: such a wait polls the whole tree for its entire timeout and was 4.5 % of the log volume
// in both 2026-09-05 simulator crashes (`06-SIMULATOR-CRASH-FINDINGS.md`). Every population is
// asserted before an index is taken into it, and every element is RE-QUERIED after every mutation.
//
// EVERY TEST PINS ITS LAUNCH STATE (07-07). `selection` persists since 07-05, so a case that left
// the app on Hashing decides the NEXT case's launch surface. `launch(_:)` builds a fresh
// `XCUIApplication` each time, so a test that visits three surfaces pins three launches.
//
// C-25 BOUNDS WHAT THIS PROVES. Both UI-test targets are pinned to `SWIFT_VERSION: "5.9"` /
// `SWIFT_STRICT_CONCURRENCY: minimal` because fastlane's `SnapshotHelper.swift` predates Swift 6.
// This suite is APP-09 evidence and never evidence for APP-12. Everything here is Swift 5.9.
//
// `print` FROM A UI-TEST BUNDLE DOES NOT REACH xcodebuild's PIPE — 06-16 measured that on both
// platforms. Every labelled evidence line is therefore emitted TWICE: with `print`, for a local
// run, and as an `XCTContext` activity, which lands in the `.xcresult` the transcript is read from.

/// Editing a chained pipeline on a running app: the six structural invariants, the ends rule, the
/// State-Contract-4 narrowing, the downstream values after a remove and after a move, the blocked
/// count going to zero, and rule AA's two frame clauses (APP-09, D-99, D-100, D-101).
@MainActor
final class StepEditTests: XCTestCase {
    private var app: XCUIApplication!

    /// `Operation.allCases.count`, asserted before any menu-item index is taken, and that
    /// enumeration's indexes for the two operations this suite chains with.
    private static let operationCount = 10
    private static let base64EncodeItem = 0
    private static let base64DecodeItem = 1

    /// AA-3's floor: two iOS hit targets, centre to centre, at Dynamic Type `.large`.
    private static let twoHitTargets: CGFloat = 88

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// D-99's complete cluster and D-100's pinned root, as counts, on all three surfaces with two
    /// appended cards on the stack — the two most load-bearing decisions in the phase, asserted
    /// directly rather than through a value.
    func testStructuralInvariantsHoldOnEverySurface() {
        assertInvariants(LaunchState.encodeDestination, "encode", AccessibilityIdentifiers.Encode.useExample)
        assertInvariants(LaunchState.hashingDestination, "hashing", AccessibilityIdentifiers.Hashing.useExample)
        assertInvariants(LaunchState.timestampsDestination, "timestamps", AccessibilityIdentifiers.Timestamps.useExample)
    }

    /// Every remove control is enabled while empty, while another card has failed and while it is
    /// itself blocked — the named narrowing of State Contract 4. If this fails, a failing step and
    /// everything beneath it are exactly the cards APP-09 cannot act on.
    func testRemoveStaysEnabledWhileEmptyFailedAndBlocked() {
        launch(LaunchState.encodeDestination)
        let source = populatedEncodeInput()
        XCTAssertFalse(source.isEmpty, "the worked-value button left the Encode input empty")
        buildFailingChain()
        let failed = count(AccessibilityIdentifiers.Step.blocked)
        XCTAssertGreaterThan(failed, 0, "the chain never blocked, so this run says nothing about a blocked card")
        assertEveryRemoveIsEnabled("failed-and-blocked")

        clearTheEncodeInput()
        XCTAssertEqual(count(AccessibilityIdentifiers.Step.card), 4, "clearing the input removed cards from the stack")
        XCTAssertEqual(count(AccessibilityIdentifiers.Step.output), 0, "a card still renders a value on an empty input")
        XCTAssertEqual(count(AccessibilityIdentifiers.Step.blocked), 0, "a card is still blocked on an empty input")
        assertEveryRemoveIsEnabled("empty")
    }

    /// A remove is a splice: the card below re-runs on the output of the card above, and the value
    /// it shows changes to one this process computed.
    func testARemoveChangesTheDownstreamValue() {
        launch(LaunchState.encodeDestination)
        let source = populatedEncodeInput()
        XCTAssertFalse(source.isEmpty, "the worked-value button left the Encode input empty")
        let once = base64(source)
        addStep(from: 0, choosing: Self.base64EncodeItem)
        addStep(from: 0, choosing: Self.base64EncodeItem)

        let before = appendedOutput(1, expecting: 2)
        XCTAssertEqual(before, base64(base64(once)), "Step 3 shows \(before), expected this process's triple base64")

        appendedControl(AccessibilityIdentifiers.Step.remove, 0).tap()
        XCTAssertEqual(count(AccessibilityIdentifiers.Step.card), 2, "the removal did not take exactly one card")
        let after = appendedOutput(0, expecting: 1)
        XCTAssertEqual(after, base64(once), "the surviving card shows \(after), expected this process's double base64")
        XCTAssertNotEqual(after, before, "the surviving card renumbered without recomputing: still \(before)")
    }

    /// A move is a swap: the card that took the moved step's place re-runs, and its value changes
    /// to one this process computed. Ordinals alone would prove renumbering, not recomputation.
    func testAMoveChangesTheDownstreamValue() {
        launch(LaunchState.encodeDestination)
        let source = populatedEncodeInput()
        XCTAssertFalse(source.isEmpty, "the worked-value button left the Encode input empty")
        let once = base64(source)
        addStep(from: 0, choosing: Self.base64EncodeItem)
        addStep(from: 0, choosing: Self.base64DecodeItem)

        let before = appendedOutput(0, expecting: 2)
        XCTAssertEqual(before, base64(once), "Step 2 shows \(before), expected this process's double base64")

        appendedControl(AccessibilityIdentifiers.Step.moveUp, 1).tap()
        let after = appendedOutput(0, expecting: 2)
        XCTAssertEqual(after, source, "after the swap Step 2 shows \(after), expected the input this process read back")
        XCTAssertEqual(appendedOutput(1, expecting: 2), once, "after the swap Step 3 is not this process's single base64")
        XCTAssertNotEqual(after, before, "the two cards traded ordinals without recomputing")
    }

    /// Removing the failing step takes the blocked count from greater than zero to exactly zero in
    /// one pass, and the card that was blocked shows the value this process computed. The
    /// greater-than-zero half comes FIRST, or the zero half is vacuous.
    func testBlockedClearsWhenTheFailingStepIsRemoved() {
        launch(LaunchState.encodeDestination)
        let source = populatedEncodeInput()
        XCTAssertFalse(source.isEmpty, "the worked-value button left the Encode input empty")
        buildFailingChain()

        let before = count(AccessibilityIdentifiers.Step.blocked)
        XCTAssertGreaterThan(before, 0, "step_blocked_before=\(before) — nothing blocked, so a zero after it proves nothing")
        print("step_blocked_before=\(before)")
        XCTContext.runActivity(named: "step_blocked_before=\(before)") { _ in }

        appendedControl(AccessibilityIdentifiers.Step.remove, 1).tap()
        let after = count(AccessibilityIdentifiers.Step.blocked)
        XCTAssertEqual(after, 0, "step_blocked_after=\(after) — a card is still blocked after the failing step was removed")
        print("step_blocked_after=\(after)")
        XCTContext.runActivity(named: "step_blocked_after=\(after)") { _ in }

        let recovered = appendedOutput(1, expecting: 2)
        XCTAssertEqual(recovered, base64(source), "the card that was blocked shows \(recovered), expected this process's base64")
    }

    /// On Hashing alone, `model.hashing.steps.first` IS the chain root, so `stepOffset` is 1. A
    /// remove wired to the appended index would delete that root — a different value under every
    /// header below it, with no confirmation and no undo.
    func testRemovingTheFirstAppendedHashingCardSparesTheChainRoot() {
        launch(LaunchState.hashingDestination)
        tapUseExample(AccessibilityIdentifiers.Hashing.useExample)
        addStep(from: 0, choosing: Self.base64EncodeItem)
        addStep(from: 0, choosing: Self.base64EncodeItem)

        let firstAppended = appendedOutput(0, expecting: 2)
        XCTAssertFalse(firstAppended.isEmpty, "Step 2 on Hashing renders nothing, so the comparison below would be vacuous")
        XCTAssertEqual(appendedOutput(1, expecting: 2), base64(firstAppended), "Step 3 is not this process's base64 of Step 2")

        appendedControl(AccessibilityIdentifiers.Step.remove, 0).tap()
        XCTAssertEqual(count(AccessibilityIdentifiers.Step.card), 2, "the removal did not take exactly one card")
        XCTAssertEqual(count(AccessibilityIdentifiers.Hashing.digestMD5), 1, "the chain root's digest row is no longer rendered")
        let surviving = appendedOutput(0, expecting: 1)
        XCTAssertEqual(surviving, firstAppended,
                       "removing Step 2 on Hashing deleted the CHAIN ROOT: the surviving card shows \(surviving), "
                           + "expected \(firstAppended), the value Step 2 was already showing")
    }

    /// AA-2 as a column comparison and AA-3 as a centre-to-centre distance, both from the frames a
    /// running app reports rather than computed from the tokens the code attaches.
    func testTheRemoveControlIsNeverAdjacentToAnAddStepControl() {
        launch(LaunchState.encodeDestination)
        tapUseExample(AccessibilityIdentifiers.Encode.useExample)
        addStep(from: 0, choosing: Self.base64EncodeItem)
        addStep(from: 0, choosing: Self.base64EncodeItem)

        let removes = frames(AccessibilityIdentifiers.Step.remove)
        let adds = frames(AccessibilityIdentifiers.Step.addStep)
        XCTAssertEqual(removes.count, 2, "\(removes.count) remove hit rects, expected one per appended card")
        XCTAssertEqual(adds.count, 3, "\(adds.count) add-step hit rects, expected one per output on the stack")

        var gap = CGFloat.greatestFiniteMagnitude
        var distance = CGFloat.greatestFiniteMagnitude
        for remove in removes {
            for add in adds {
                gap = min(gap, add.minX - remove.maxX)
                distance = min(distance, hypot(add.midX - remove.midX, add.midY - remove.midY))
            }
        }
        let seen = "removes=\(removes.map(describe)) addSteps=\(adds.map(describe))"
        XCTAssertGreaterThan(gap, 0, "AA-2: a remove hit rect overlaps an add-step's in x by \(-gap) pt. \(seen)")
        XCTAssertGreaterThanOrEqual(distance, Self.twoHitTargets,
                                    "AA-3: nearest centre-to-centre distance is \(distance) pt, below the "
                                        + "\(Self.twoHitTargets) pt two-hit-target floor. \(seen)")
        print("aa2_min_gap_pt=\(gap) aa3_min_distance_pt=\(distance)")
        XCTContext.runActivity(named: "aa2_min_gap_pt=\(gap) aa3_min_distance_pt=\(distance)") { _ in }
    }

    /// Build a two-appended-card stack on `destination` and assert all six invariants over it.
    private func assertInvariants(_ destination: String, _ surface: String, _ identifier: String) {
        launch(destination)
        tapUseExample(identifier)
        addStep(from: 0, choosing: Self.base64EncodeItem)
        addStep(from: 0, choosing: Self.base64EncodeItem)

        let cards = count(AccessibilityIdentifiers.Step.card)
        let positions = count(AccessibilityIdentifiers.Step.position)
        let notes = count(AccessibilityIdentifiers.Step.rootNote)
        let removes = count(AccessibilityIdentifiers.Step.remove)
        let ups = count(AccessibilityIdentifiers.Step.moveUp)
        let downs = count(AccessibilityIdentifiers.Step.moveDown)
        XCTAssertEqual(cards, 3, "\(surface): \(cards) cards, expected the pinned root plus two appended")
        XCTAssertEqual(positions, cards, "\(surface): \(cards) cards carry \(positions) ordinals — a card is unnumbered")
        XCTAssertEqual(notes, 1, "\(surface): \(notes) root notes, expected exactly 1")
        XCTAssertEqual(removes, cards - 1,
                       "\(surface): \(removes) remove controls against \(cards) cards — D-100 pins the root")
        XCTAssertEqual(ups, cards - 1, "\(surface): \(ups) move-up controls against \(cards) cards")
        XCTAssertEqual(downs, ups, "\(surface): \(ups) move-up controls against \(downs) move-down")
        assertEndsRule(surface)
        assertEveryRemoveIsEnabled(surface)
        print("step_card_count=\(cards) step_remove_count=\(removes) step_surface=\(surface)")
        XCTContext.runActivity(named: "stepedit_surface=\(surface) step_card_count=\(cards) step_remove_count=\(removes) "
            + "position=\(positions) rootNote=\(notes) moveUp=\(ups) moveDown=\(downs)") { _ in }
    }

    /// First move-up dimmed, last move-down dimmed, every other move enabled. `isEnabled` is
    /// correct and deliberate here: this is a POSITIONAL fact.
    private func assertEndsRule(_ surface: String) {
        let ups = all(AccessibilityIdentifiers.Step.moveUp)
        let downs = all(AccessibilityIdentifiers.Step.moveDown)
        let population = ups.count
        XCTAssertEqual(downs.count, population, "\(surface): \(population) move-up against \(downs.count) move-down")
        for appendedIndex in 0 ..< population {
            let up = ups.element(boundBy: appendedIndex).isEnabled
            let down = downs.element(boundBy: appendedIndex).isEnabled
            XCTAssertEqual(up, appendedIndex > 0,
                           "\(surface): move-up on Step \(appendedIndex + 2) is enabled=\(up), expected \(appendedIndex > 0)")
            XCTAssertEqual(down, appendedIndex < population - 1,
                           "\(surface): move-down on Step \(appendedIndex + 2) is enabled=\(down), not positional")
        }
    }

    /// Every remove control on the surface is enabled, whatever its card is rendering.
    private func assertEveryRemoveIsEnabled(_ situation: String) {
        let controls = all(AccessibilityIdentifiers.Step.remove)
        let population = controls.count
        XCTAssertGreaterThan(population, 0, "\(situation): no remove control on the surface at all")
        for appendedIndex in 0 ..< population {
            XCTAssertTrue(controls.element(boundBy: appendedIndex).isEnabled,
                          "\(situation): remove on Step \(appendedIndex + 2) is not enabled")
        }
    }

    // MARK: - Driving, all of it by identifier

    /// A fresh application with all five settings pinned, then launched.
    private func launch(_ destination: String) {
        app = XCUIApplication()
        app.launchPinned(showing: destination)
    }

    /// Every element carrying `identifier`, whatever kind of element it is.
    private func all(_ identifier: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: identifier)
    }

    /// How many elements carry `identifier` right now — a count, never a doomed wait: the absence
    /// this suite asserts is one no timeout can turn into a presence.
    private func count(_ identifier: String) -> Int {
        all(identifier).count
    }

    /// The first element carrying `identifier`.
    private func element(_ identifier: String) -> XCUIElement {
        all(identifier).firstMatch
    }

    /// One footer control of the APPENDED card at `appendedIndex`. Index 0 is the FIRST APPENDED
    /// card, which the header numbers **Step 2** — the mapping is in this function's name and in
    /// its message. The population is asserted before the index is taken.
    private func appendedControl(_ identifier: String, _ appendedIndex: Int) -> XCUIElement {
        let query = all(identifier)
        let population = query.count
        XCTAssertGreaterThan(population, appendedIndex,
                             "\(identifier) has \(population) elements; appended index \(appendedIndex) "
                                 + "(Step \(appendedIndex + 2)) is outside it")
        return query.element(boundBy: appendedIndex)
    }

    /// What the APPENDED card at `appendedIndex` is rendering. `expected` is the `Step.output`
    /// population, asserted BEFORE the index: a blocked card carries no output at all, so this
    /// query's size moves with the render state.
    private func appendedOutput(_ appendedIndex: Int, expecting expected: Int) -> String {
        let outputs = all(AccessibilityIdentifiers.Step.output)
        let population = outputs.count
        XCTAssertEqual(population, expected, "\(population) cards carry an output, expected \(expected)")
        let rendered = outputs.element(boundBy: appendedIndex)
        XCTAssertTrue(rendered.exists, "Step \(appendedIndex + 2) renders no output")
        let reported = (rendered.value as? String) ?? ""
        return reported.isEmpty ? rendered.label : reported
    }

    /// Fill a surface's input from its worked-value button, shown only while the input is empty.
    private func tapUseExample(_ identifier: String) {
        let button = element(identifier)
        XCTAssertTrue(button.waitForExistence(timeout: 30),
                      "the worked-value button is missing — no element carries \(identifier)")
        button.tap()
    }

    /// Fill the Encode input and hand back what it holds, read from the tree rather than spelled
    /// as a literal: `InputExample` is app-target code this process cannot link.
    private func populatedEncodeInput() -> String {
        tapUseExample(AccessibilityIdentifiers.Encode.useExample)
        return (element(AccessibilityIdentifiers.Encode.input).value as? String) ?? ""
    }

    /// Open the add-step control at `accessoryIndex` and choose the item at `menuIndex` in
    /// `Operation.allCases` order. The menu's population is asserted before the index.
    private func addStep(from accessoryIndex: Int, choosing menuIndex: Int) {
        let accessories = all(AccessibilityIdentifiers.Step.addStep)
        let control = accessories.element(boundBy: accessoryIndex)
        XCTAssertTrue(control.waitForExistence(timeout: 20), "no add-step control at index \(accessoryIndex)")
        control.tap()
        let items = all(AccessibilityIdentifiers.Step.addStepMenu)
        XCTAssertTrue(items.element(boundBy: menuIndex).waitForExistence(timeout: 20),
                      "the add-step menu presented no item at index \(menuIndex)")
        let population = items.count
        XCTAssertEqual(population, Self.operationCount, "the menu presented \(population) items, expected \(Self.operationCount)")
        items.element(boundBy: menuIndex).tap()
    }

    /// Base64 decode, decode, encode — Step 2 holds a value, Step 3 fails on text that is not
    /// Base64, Step 4 is blocked beneath it (D-84's halt rule).
    private func buildFailingChain() {
        addStep(from: 0, choosing: Self.base64DecodeItem)
        addStep(from: 0, choosing: Self.base64DecodeItem)
        addStep(from: 0, choosing: Self.base64EncodeItem)
    }

    /// Empty the Encode input, then put the keyboard away. Emptiness is asserted through the
    /// worked-value button, rendered only on an empty input — the field's own `value` reports its
    /// PLACEHOLDER when empty and would answer the wrong question.
    private func clearTheEncodeInput() {
        let field = element(AccessibilityIdentifiers.Encode.input)
        let existing = (field.value as? String) ?? ""
        XCTAssertFalse(existing.isEmpty, "there is nothing to clear — the Encode input is already empty")
        for _ in 0 ..< 3 {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            if app.keyboards.element.exists || app.keyboards.element.waitForExistence(timeout: 5) {
                break
            }
        }
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count + 2))
        element(AccessibilityIdentifiers.Input.done).tap()
        XCTAssertTrue(element(AccessibilityIdentifiers.Encode.useExample).waitForExistence(timeout: 15),
                      "the Encode input still holds text after \(existing.count + 2) deletions")
    }

    /// Every frame carrying `identifier`. An empty rect is an element the runner could not place,
    /// and treating it as one at the origin would answer rule AA about something not on screen —
    /// so it fails here, named, rather than being skipped.
    private func frames(_ identifier: String) -> [CGRect] {
        let query = all(identifier)
        let population = query.count
        var found: [CGRect] = []
        for appendedIndex in 0 ..< population {
            let rect = query.element(boundBy: appendedIndex).frame
            XCTAssertFalse(rect.isEmpty, "\(identifier) at index \(appendedIndex) reports an empty frame")
            found.append(rect)
        }
        return found
    }
}

/// One frame as `(x,y,w,h)`, for a failure message that carries what was measured.
private func describe(_ frame: CGRect) -> String {
    "(\(frame.minX),\(frame.minY),\(frame.width),\(frame.height))"
}

/// This process's own Base64 — `Base64Codec.encode`'s definition arrived at independently, because
/// the app target is not linkable from here. That is what makes the comparison evidence rather
/// than a tautology.
private func base64(_ text: String) -> String {
    Data(text.utf8).base64EncodedString()
}
