import XCTest

// THE SWEEP'S HARVEST AND ITS DRIVING, SPLIT OUT OF `VisibleStringSweep.swift`. A second
// companion to that file, for the reason `SweepPopulation.swift:3..5` gives for the first: both
// files are `swiftlint --strict`, `file_length` is 400 lines, and under `--strict` that limit is
// an ERROR rather than a warning. MEASURED, not inferred: the unsplit file stood at 399 lines on
// iOS and at 400 on macOS, so plan 07-12's four walk steps did not fit in one line, let alone in
// ninety. The split is the same remedy 06-16 already applied once, applied a second time.
//
// NOTHING BELOW CHANGED WHEN IT MOVED. Every function is `VisibleStringSweep`'s, byte for byte,
// minus the `private` keyword that a same-file extension does not need and a cross-file one
// cannot have. THE WALK ITSELF STAYED WHERE IT WAS — the ten steps, their order, and the
// appearance loop around them — because that shape is PRIV-06's shipped evidence and moving it
// would make the diff unreadable at exactly the moment four steps are added to it.
//
// THE ONE ADDITION IS `count(_:)`, and it is D-107 route 1 stated as a function. The four steps
// plan 07-12 appends ask about POPULATIONS — how many cards carry a remove control, how many are
// blocked — rather than about presence, and a count is ONE query where `waitForExistence` is a
// poll that costs a second per call. This walk is the largest AX-tree consumer in the suite and
// `06-SIMULATOR-CRASH-FINDINGS.md` measured the crash mechanism to be RATE-based, so the cheaper
// shape is a safety property here rather than a performance one.
//
// C-25 BOUNDS WHAT THIS PROVES: Swift 5.9 / minimal concurrency, like every file in this target,
// so this is criterion-6 evidence only and NEVER evidence for APP-12.

extension VisibleStringSweep {
    // MARK: - The harvest

    /// Appends the non-empty `label`, `title`, `placeholderValue` and string `value` at `node`, then
    /// recurses over `node.children`. One `try app.snapshot()` feeds the whole walk of the tree.
    func harvest(_ node: XCUIElementSnapshot, inherited: SweepBucket, into out: inout SweepHarvest) {
        let subtree = SweepPopulation.subtreeBucket(node, inherited: inherited)
        let own = SweepPopulation.ownBucket(node, subtree: subtree)
        let candidates = [
            node.label,
            node.title,
            node.placeholderValue ?? "",
            (node.value as? String) ?? ""
        ]
        for value in candidates where !value.isEmpty {
            out.add(value, to: own)
        }
        for child in node.children {
            harvest(child, inherited: subtree, into: &out)
        }
    }

    /// One harvest point: one round trip, four properties per node, the whole tree.
    func snap(into out: inout SweepHarvest) throws {
        let root = try app.snapshot()
        if !root.label.isEmpty {
            productName = root.label
        }
        harvest(root, inherited: .rendered, into: &out)
    }

    /// How many elements carry `identifier` right now.
    ///
    /// A COUNT, and never a doomed wait: the four steps plan 07-12 appends assert ABSENCES — no
    /// blocked card after the failing step is removed, no remove control once the stack is empty —
    /// and no timeout can turn an absence into a presence. The same shape `StepEditTests` measured
    /// on three runtimes before this file borrowed it.
    func count(_ identifier: String) -> Int {
        app.descendants(matching: .any).matching(identifier: identifier).count
    }

    // MARK: - Driving, all of it by identifier

    /// The first element carrying `identifier`, whatever kind of element it is.
    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The `index`th element carrying `identifier` — the shape the `Step.*` constants are designed for.
    func control(_ identifier: String, _ index: Int) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).element(boundBy: index)
    }

    /// One segment of a segmented picker, by index. A picker surfaces as buttons on iOS and as radio
    /// buttons on macOS, so both are tried rather than assumed.
    func segment(_ identifier: String, _ index: Int) -> XCUIElement {
        let picker = element(identifier)
        let buttons = picker.buttons
        return buttons.count > index ? buttons.element(boundBy: index) : picker.radioButtons.element(boundBy: index)
    }

    /// `exists` first, `waitForExistence` only if it does not: the waiting form costs a full second per
    /// call even when the element is already there, and this walk makes some sixty of them.
    func press(_ target: XCUIElement, _ what: String) {
        if !target.exists {
            XCTAssertTrue(target.waitForExistence(timeout: 20), "the walk cannot reach \(what)")
        }
        target.tap()
    }

    /// Replaces a field's contents. Deletes first: an empty `TextField` reports its prompt as `value`,
    /// so the delete count is an upper bound and over-deleting an empty field is a no-op.
    func replaceInput(_ identifier: String, with text: String) {
        let field = element(identifier)
        if !field.exists {
            XCTAssertTrue(field.waitForExistence(timeout: 20), "the walk cannot reach the input \(identifier)")
        }
        focus(field, identifier)
        // A FIXED, GENEROUS DELETE COUNT rather than one derived from `value`. An empty `TextField`
        // reports its PROMPT as `value`, so a derived count is wrong in both directions; over-deleting
        // an empty field is a no-op, and the whole run is one `typeText` call whatever the length.
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40))
        if !text.isEmpty {
            field.typeText(text)
        }
    }

    /// Empties a field and CONFIRMS it, by the worked-value button that only exists while it is empty.
    ///
    /// Measured: a single delete pass left the Timestamps field non-empty on one run of two, and the
    /// walk then waited twenty seconds for a button the app was right not to be showing.
    func clearInput(_ identifier: String, revealing button: String) {
        for _ in 0 ..< 3 {
            replaceInput(identifier, with: "")
            if element(button).exists {
                return
            }
        }
        XCTFail("clearing \(identifier) never revealed \(button) — the field would not empty")
    }

    /// Taps a field until the software keyboard is up. A tap that lands before SwiftUI has installed
    /// the responder leaves `typeText` with nowhere to send its events ("Neither element nor any
    /// descendant has keyboard focus"), which is a flake, not a defect in the app — so it is waited
    /// out here rather than slept through.
    func focus(_ field: XCUIElement, _ identifier: String) {
        for attempt in 0 ..< 3 {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            if app.keyboards.element.exists || app.keyboards.element.waitForExistence(timeout: 3) {
                return
            }
            print("focus_attempt=\(attempt) identifier=\(identifier) keyboards=\(app.keyboards.count)")
        }
    }

    /// Puts the software keyboard away before anything below it is driven.
    ///
    /// The tab bar sits UNDER the keyboard, and XCUITest refuses to tap a covered element — so this is
    /// a precondition of step 9, not a nicety.
    ///
    /// A relaunch rather than a gesture, and that is a MEASURED choice: the interactive
    /// scroll-to-dismiss this used first worked on 17.5 and 18.6 and failed on 26.1, where
    /// `scrollViews.firstMatch` resolves to an offscreen scroll view ("visible frame is empty").
    /// Nothing in the walk depends on state surviving this — but the wait below has always required the
    /// relaunch to come back on Encode, which stopped being free once `selection` persisted (07-07).
    func dismissKeyboard() {
        guard app.keyboards.element.exists else { return }
        print("keyboard_dismissed_by=relaunch")
        app.terminate()
        app.launchPinned(onlySurface: LaunchState.encodeDestination) // 07-07: must land on Encode
        XCTAssertTrue(
            element(Ident.Shell.tabEncode).waitForExistence(timeout: 30),
            "the relaunch that puts the keyboard away did not bring the app back"
        )
    }

    /// Taps the tab item at `index` and confirms it showed the destination carrying `identifier`. The
    /// index addresses `app.tabBars.buttons`, whose population is asserted to be exactly 3 first.
    func visit(_ index: Int, expecting identifier: String) {
        dismissKeyboard()
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 20), "the app presents no tab bar at all")
        XCTAssertEqual(bar.buttons.count, 3, "the tab bar carries \(bar.buttons.count) items, expected 3")
        bar.buttons.element(boundBy: index).tap()
        XCTAssertTrue(
            element(identifier).waitForExistence(timeout: 20),
            "tab item \(index) does not show \(identifier)"
        )
    }
}
