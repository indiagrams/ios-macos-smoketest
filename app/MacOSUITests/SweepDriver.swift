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
        if node.elementType == .menuBarItem {
            let name = node.title.isEmpty ? node.label : node.title
            if !name.isEmpty, !menuBarItems.contains(name) {
                menuBarItems.append(name)
            }
        }
        for child in node.children {
            harvest(child, inherited: subtree, into: &out)
        }
    }

    /// One harvest point: one round trip, four properties per node, the whole tree.
    func snap(into out: inout SweepHarvest) throws {
        let root = try app.snapshot()
        if !root.label.isEmpty {
            applicationLabel = root.label
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

    /// The first element carrying `identifier`, whatever kind of element it is. Deliberately not scoped
    /// to a query category: a sidebar row, a card and a menu item are different element types.
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
    /// call even when the element is already there, and this walk makes some forty of them.
    func press(_ target: XCUIElement, _ what: String) {
        if !target.exists {
            XCTAssertTrue(target.waitForExistence(timeout: 20), "the walk cannot reach \(what)")
        }
        target.click()
    }

    /// Replaces a field's contents. A FIXED, GENEROUS DELETE COUNT rather than one derived from
    /// `value`: an empty field reports its PROMPT as `value`, so a derived count is wrong in both
    /// directions, and over-deleting an empty field is a no-op.
    func replaceInput(_ identifier: String, with text: String) {
        let field = element(identifier)
        if !field.exists {
            XCTAssertTrue(field.waitForExistence(timeout: 20), "the walk cannot reach the input \(identifier)")
        }
        field.click()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40))
        if !text.isEmpty {
            field.typeText(text)
        }
    }

    /// Empties a field and CONFIRMS it, by the worked-value button that only exists while it is empty.
    /// Measured on the iOS twin: a clear that is not verified is a step that can silently not happen.
    func clearInput(_ identifier: String, revealing button: String) {
        for _ in 0 ..< 3 {
            replaceInput(identifier, with: "")
            if element(button).exists {
                return
            }
        }
        XCTFail("clearing \(identifier) never revealed \(button) — the field would not empty")
    }

    /// Moves to the destination carrying `identifier` and confirms it arrived.
    func visit(_ identifier: String) {
        let destination = element(identifier)
        if !destination.exists {
            XCTAssertTrue(destination.waitForExistence(timeout: 20), "cannot reach the destination \(identifier)")
        }
        destination.click()
    }

    /// Every string 07-UI-SPEC's copywriting delta adds, looked for BY NAME in the harvest.
    ///
    /// A FLOOR CANNOT DO THIS JOB. `distinctFloor` catches a surface disappearing; it cannot catch a
    /// phase adding eight strings that the walk never renders, because the count would go UP and the
    /// assertion would pass while the population had stopped covering its subject. That is the exact
    /// failure plan 07-12 exists to close, so the eight are named rather than counted.
    ///
    /// WHAT IT DOES NOT DO, measured on 2026-09-06 rather than assumed: it does not detect the loss
    /// of walk steps 11-14. All six harvestable strings still match under the ten-step walk, because
    /// 07-08 wired the footer into all three surfaces and that walk already appends a card on each —
    /// so the plan's premise that none of the eight was inside the ten-step walk holds for the two
    /// announcements and is FALSE for the other six. What steps 11-14 add is DEPTH inside those keys
    /// (`step.position` 2 -> 3 instances, `step.card.label` 13 -> 20) and thirteen distinct strings
    /// the shorter walk never renders. The aggregate loss is what `distinctFloor` catches.
    ///
    /// THE TWO UNREACHABLE ONES ARE PRINTED, NOT DROPPED. An exemption here is a labelled count, the
    /// same discipline `SweepPopulation`'s four buckets already follow, so the number moves the day a
    /// runtime starts surfacing announcements or somebody adds a ninth string.
    func assertPhase7StringsAreRendered(in distinct: Set<String>) {
        var exempted = 0
        for expected in SweepPopulation.phase7Strings {
            let found = SweepPopulation.matches(expected, in: distinct)
            if let exemption = expected.exemption {
                exempted += 1
                recordCounter("exempt_string key=\(expected.key) matches=\(found.count) reason=\(exemption)")
                continue
            }
            recordCounter("swept_string key=\(expected.key) matches=\(found.count)")
            XCTAssertGreaterThan(
                found.count,
                0,
                "nothing rendered matches \(expected.key) — the catalog holds \"\(expected.catalogValue)\" "
                    + "and the walk never brought it into the population"
            )
        }
        recordCounter("phase7_strings=\(SweepPopulation.phase7Strings.count) phase7_exempt=\(exempted)")
    }
}
