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
// THREE FUNCTIONS HAVE BEEN ADDED SINCE, and the count is kept honest here rather than left at
// "the one addition", which is what this paragraph said until 2026-09-06.
//
// THE FIRST ADDITION WAS `count(_:)`, and it is D-107 route 1 stated as a function. The four steps
// plan 07-12 appends ask about POPULATIONS — how many cards carry a remove control, how many are
// blocked — rather than about presence, and a count is ONE query where `waitForExistence` is a
// poll that costs a second per call. This walk is the largest AX-tree consumer in the suite and
// `06-SIMULATOR-CRASH-FINDINGS.md` measured the crash mechanism to be RATE-based, so the cheaper
// shape is a safety property here rather than a performance one.
//
// THE OTHER TWO ARE `readable(_:)` AND `assertOrdinalsAreDistinct(_:of:)`, added by the 07-12
// ORDINAL gap closure. Both are about the same measured fact and both are byte-identical twins of
// the other platform's: XCUITest's `.label` does not read `AXValue`, and a plain SwiftUI `Text` on
// macOS publishes its content nowhere else. Their doc comments carry the measurement.
//
// AMENDED 2026-09-10: THOSE TWO ARE NOW ONE-LINE DELEGATIONS, AND THE MEASUREMENT NO LONGER LIVES
// HERE. The sentence above is preserved because it was true and because it is what the two
// functions still DO; what changed is where the rule is implemented. Both now call
// `app/UITestSupport/` — ONE app-agnostic file per concern, compiled into BOTH UI-test targets
// through both generator manifests, naming no view, no identifier and no type of this application.
// The rule and the behaviour are unchanged; the twins stay byte-identical; and the measurement
// widened from 07-12's one shape to six shapes with two negative controls
// (`evidence/07-UITESTSUPPORT-ax-shapes.swift`, `docs/UI-TESTING-ON-BOTH-PLATFORMS.md`).
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

    /// STEP 0 — the walk's first wait, and, when it fails, the measurements that say WHY.
    ///
    /// **THE WAIT AND THE MESSAGE ARE UNCHANGED IN SUBSTANCE; ONLY THE FAILURE PATH GREW.** The
    /// same element, the same 30-second timeout, the same sentence. Nothing here can turn a red
    /// into a green: the early `return` is taken only when the row really exists, and every line
    /// below it runs after the wait has already answered false.
    ///
    /// WHY IT EXISTS. On 2026-09-12 this assertion failed on BOTH macOS jobs of run 34717633775
    /// and the message could not distinguish four different defects: which appearance pass was
    /// running (the loop launches twice and `continueAfterFailure` is false, so a failure in the
    /// second pass and a failure in the first read identically); whether the app had a window at
    /// all; whether it had one whose SIDEBAR was collapsed, which removes exactly these rows from
    /// the tree while the detail area still renders; and whether the process was even in the
    /// foreground. Each number below separates one of those from the others, and `detail_encode_input`
    /// is the discriminator that matters most — a positive count there with `sidebar_encode=0` means
    /// the window is present and the split view collapsed its sidebar, which is a different bug from
    /// "the app presented nothing".
    ///
    /// THE CHANNEL IS PROVEN, NOT ASSUMED. A `print` from this bundle never reaches the workflow
    /// log (06-01), so the numbers ride the ASSERTION MESSAGE — and that channel is measured, not
    /// hoped for: the old message reached the CI log verbatim in the run cited above. The activity
    /// is recorded as well, for the `.xcresult` when one is kept.
    func awaitFirstDestination() {
        if element(Ident.Shell.sidebarEncode).waitForExistence(timeout: 30) {
            return
        }

        let args = app.launchArguments
        let appearance = args.firstIndex(of: "-UITestColorScheme")
            .flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } ?? "unset"
        let windows = app.windows.count
        let frame = windows > 0 ? "\(app.windows.firstMatch.frame)" : "none"
        let diagnosis = "appearance=\(appearance) app_state=\(app.state.rawValue) windows=\(windows) "
            + "window_frame=\(frame) menu_bar_items=\(app.menuBarItems.count) "
            + "tree_elements=\(app.descendants(matching: .any).count) "
            + "sidebar_encode=\(count(Ident.Shell.sidebarEncode)) "
            + "sidebar_hashing=\(count(Ident.Shell.sidebarHashing)) "
            + "sidebar_timestamps=\(count(Ident.Shell.sidebarTimestamps)) "
            + "detail_encode_input=\(count(Ident.Encode.input))"
        recordCounter("step0_first_destination \(diagnosis)")
        XCTFail("the app did not present its first destination — no element carries "
            + "\(Ident.Shell.sidebarEncode). \(diagnosis)")
    }

    /// What an element is RENDERING, in whichever attribute the platform publishes it in.
    ///
    /// **DELEGATES TO ``XCUIElement/renderedText`` SINCE 2026-09-10**, and the measurement that
    /// justifies the rule moved with it, verbatim and widened, into
    /// `app/UITestSupport/ElementText.swift` — ONE file, compiled into BOTH UI-test targets, naming
    /// nothing about this application. The rule is unchanged and the behaviour is unchanged:
    /// `label` FIRST — iOS's idiom, and the branch every already-answering element keeps taking —
    /// then the element's own string `value`.
    ///
    /// THE NAME SURVIVES ON PURPOSE. The walk already calls it at every read site, so adopting the
    /// shared layer is ONE line here rather than a sweep over thirteen call sites, and the diff a
    /// later reader has to judge is the delegation rather than the churn around it.
    ///
    /// The measurement itself, now made over SIX shapes with TWO negative controls rather than the
    /// one shape 07-12 measured, is in `evidence/07-UITESTSUPPORT-ax-shapes.swift` and in
    /// `docs/UI-TESTING-ON-BOTH-PLATFORMS.md`. Short version, unchanged: a plain SwiftUI `Text` on
    /// macOS carries its content in `AXValue` alone, and XCUITest's `.label` reads `AXDescription`
    /// falling back to `AXTitle` — never `AXValue`.
    func readable(_ target: XCUIElement) -> String {
        target.renderedText
    }

    /// The ordinals on screen are one per card and no two alike — asserted as TWO failures, not one.
    ///
    /// **DELEGATES TO ``assertDistinctReadable(_:expected:_:file:line:)`` SINCE 2026-09-10**, in
    /// `app/UITestSupport/BlindReadGuards.swift`. Both assertions survive, in the same order, with
    /// the same meaning: emptiness FIRST and naming itself, then the distinctness check verbatim.
    ///
    /// THE MESSAGE THIS REPLACED COST A WHOLE SESSION, WHICH IS WHY IT IS SPLIT.
    /// `XCTAssertEqual(Set(ordinals).count, positions)` answers "two cards render the same ordinal"
    /// for a genuine duplicate AND for a read that came back empty on every card, because
    /// `Set(["", "", ""]).count` is 1 as surely as `Set(["Step 1", "Step 1", "Step 2"]).count` is 2.
    /// Those are OPPOSITE findings — a duplicate is an APP defect that `StepStackPosition` exists to
    /// prevent, an empty sweep is a BLIND INSTRUMENT — and CI run 34067745662 reported the second
    /// wearing the first's words.
    ///
    /// `file` and `line` are forwarded so a failure still points at the walk step that made the
    /// read rather than at this file. `continueAfterFailure` is false in this suite, so the first
    /// of the two failures is the one reported, which is the right order.
    func assertOrdinalsAreDistinct(
        _ ordinals: [String],
        of positions: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertDistinctReadable(ordinals, expected: positions, "the step ordinals on screen", file: file, line: line)
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
        privacyControlOnThisSurface(identifier)
    }

    /// STEP 15 — the privacy control, as this platform can see it from the surface just arrived at.
    ///
    /// APPENDED TO THE INHERITED WALK RATHER THAN RESTRUCTURING IT, and appended HERE because
    /// ``visit(_:)`` is the one expression every surface arrival goes through — so the step covers
    /// all three surfaces without a fourth copy of the surface list and without touching
    /// `VisibleStringSweep.swift`, where the FLOOR lives.
    ///
    /// **IT DOES NOT OPEN THE MENU, AND THAT IS A DELIBERATE RISK ALLOCATION RATHER THAN AN
    /// OMISSION.** On macOS the control is an app-menu item, so seeing it means CLICKING the menu
    /// bar — and nothing has ever measured whether a menu-bar click works on the headless runner
    /// this sweep executes on. `AppStoreScreenshotTests` is the only file in this target that
    /// clicks a menu, and it SKIPS on headless, so it is not evidence. Putting an unproven
    /// interaction inside a SHIPPED criterion-6 gate risks turning a green gate red for a reason
    /// that has nothing to do with its subject; the click therefore lives in `PrivacyLinkTests`,
    /// which is new, whose arbiter is CI, and where a red is a finding rather than a regression.
    ///
    /// WHAT IS ASSERTED HERE IS THE PRECONDITION THAT FILE DEPENDS ON: the menu bar carries more
    /// than one item, so the application's own menu at index 1 is addressable at all. That is
    /// falsifiable — a run where the menu bar did not populate fails it — and it is the fact
    /// `productName` already leans on when it falls back to `menuBarItems[1]`. The identifier's
    /// presence in the tree is RECORDED beside it rather than asserted, because whether a
    /// `CommandGroup` button reaches a CLOSED menu's tree is exactly the `[OPEN]` this phase is
    /// measuring and not something to bake into a gate before it has an answer.
    func privacyControlOnThisSurface(_ surface: String) {
        let items = app.menuBarItems.count
        let inTree = count(Ident.Shell.privacyPolicy)
        recordCounter("step15_privacy_surface=\(surface) step15_menubar_items=\(items) "
            + "step15_privacy_in_tree=\(inTree)")
        XCTAssertGreaterThan(
            items,
            1,
            "step 15: the menu bar carries \(items) item(s), so the application's own menu — index 1, "
                + "the Apple menu being index 0 — is not addressable and the privacy item cannot be reached"
        )
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
