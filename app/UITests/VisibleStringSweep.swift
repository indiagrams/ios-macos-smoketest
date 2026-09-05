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
// `SWIFT_STRICT_CONCURRENCY: minimal` because fastlane's `SnapshotHelper.swift` predates Swift 6. This
// file is criterion-6 evidence only and is NEVER evidence for APP-12. Everything below is Swift 5.9
// syntax: `@MainActor final class`, `override func setUpWithError()`, no `async`.
//
// FOUR PROPERTIES, NOT ONE. `label` alone misses every `TextField` prompt — this app has three — which
// lands in `placeholderValue`, and every field's current text, which lands in `value`. A correct check
// pointed at an incomplete population is the failure class this phase exists to stop repeating.
//
// ONE IPC ROUND TRIP PER HARVEST POINT. `try app.snapshot()` returns the whole tree in one call and
// `harvest` walks `.children` in this process. The per-element alternative costs one round trip per
// element, which on a populated three-surface app is the difference between a fast test and a flaky
// one.
//
// REACHED ITS SUBJECT FIRST, SEPARATELY. `harvested_strings=` is printed and asserted BEFORE any
// property of what was harvested, so a skip, a crash or an empty tree reads as a failure to reach the
// app rather than as a statement about what the app renders.

/// Every string the app renders, on every surface, in both appearances — and no prose term among them.
@MainActor
final class VisibleStringSweep: XCTestCase {
    private typealias Ident = AccessibilityIdentifiers

    private var app: XCUIApplication!

    /// The application element's own name, read from the running app rather than from a plist.
    private var productName = ""

    /// The measured floor for `harvested_distinct`, recorded in 06-16-sweep.txt. A floor rather than an
    /// equality: adding a string must not break the gate, but LOSING a surface must.
    private static let distinctFloor = 85

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - The gate

    /// The ten-step walk, in both appearances, then the assertions in the order that matters.
    func testNoProseTermIsRenderedOnAnySurface() throws {
        var seen = SweepHarvest()

        // Step 10 is the outer loop: the whole walk again, in the other appearance. It should add no
        // new string; it is here to confirm that neither appearance HIDES one. The launch-argument
        // mechanism is `app/Shared/App.swift`'s, reused rather than `XCUIDevice.shared.appearance`,
        // whose cold-simulator handshake flakes on GHA runners.
        for scheme in ["light", "dark"] {
            app = XCUIApplication()
            app.launchArguments = ["-UITestColorScheme", scheme]
            app.launch()
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

    // MARK: - The harvest

    /// Appends the non-empty `label`, `title`, `placeholderValue` and string `value` at `node`, then
    /// recurses over `node.children`. One `try app.snapshot()` feeds the whole walk of the tree.
    private func harvest(_ node: XCUIElementSnapshot, inherited: SweepBucket, into out: inout SweepHarvest) {
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
    private func snap(into out: inout SweepHarvest) throws {
        let root = try app.snapshot()
        if !root.label.isEmpty {
            productName = root.label
        }
        harvest(root, inherited: .rendered, into: &out)
    }

    // MARK: - The walk

    /// Steps 1 and 9: launch, then each surface in turn, harvesting after every step.
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
    }

    /// Steps 2-8 on the encode/decode surface, the only one with an input-validation failure.
    private func encodeSurface(into out: inout SweepHarvest) throws {
        press(element(Ident.Encode.useExample), "the Encode worked-value button")
        try snap(into: &out)

        for index in 0 ..< 3 { // step 3: three headers
            press(segment(Ident.Encode.format, index), "the format picker's segment \(index)")
            try snap(into: &out)
        }
        press(segment(Ident.Encode.direction, 1), "the direction picker's decode segment")
        for index in 0 ..< 3 { // step 4: the other three
            press(segment(Ident.Encode.format, index), "the format picker's segment \(index)")
            try snap(into: &out)
        }

        for fixture in SweepPopulation.encodeFixtures { // step 5: the error strings
            replaceInput(Ident.Encode.input, with: fixture.text)
            for format in fixture.formats {
                press(segment(Ident.Encode.format, format), "the format picker's segment \(format)")
                try snap(into: &out)
            }
        }

        clearInput(Ident.Encode.input, revealing: Ident.Encode.useExample)
        press(segment(Ident.Encode.direction, 0), "the direction picker's encode segment")
        press(segment(Ident.Encode.format, 0), "the format picker's first segment")
        press(element(Ident.Encode.useExample), "the Encode worked-value button")

        try chainAndBlock(into: &out)
    }

    /// Steps 6-8: copy, open the menu, choose an operation, then drive the appended card to blocked.
    ///
    /// Menu items are in the accessibility tree ONLY WHILE THE MENU IS OPEN, which is why step 7 opens
    /// it and harvests before step 8 chooses. The order inside step 8 is deliberate and is not the one
    /// the walk table reads at first glance: a step whose output is an error has its add-step control
    /// `.disabled(true)` by the State Contract, so the card is appended while the pipeline is VALID and
    /// the error fixture is installed afterwards. That is what puts the blocked sentence on screen.
    private func chainAndBlock(into out: inout SweepHarvest) throws {
        press(control(Ident.Step.copy, 0), "the first copy control")
        try snap(into: &out)

        press(control(Ident.Step.addStep, 0), "the first add-step control")
        try snap(into: &out)

        // The SEEDED card's value carries the surface's own constant (`Encode.output`); only APPENDED
        // cards use the shared `Step.output`. Measured from the running tree, not assumed.
        let source = element(Ident.Encode.output).label
        press(control(Ident.Step.addStepMenu, 0), "the add-step menu's first item")
        try snap(into: &out)

        // ROADMAP criterion 8 / APP-08, asserted as its CONJUNCTION rather than as the existence of a
        // view type: the control is on screen, it was used, and the appended card renders the chained
        // result. The first menu item is `Operation.allCases.first`, whose expected value this process
        // computes for itself — no app code is linked to produce it.
        let chained = control(Ident.Step.output, 0)
        XCTAssertTrue(chained.waitForExistence(timeout: 15), "the add-step menu appended no card")
        XCTAssertEqual(
            chained.label,
            Data(source.utf8).base64EncodedString(),
            "the appended step did not render the chained result of \"\(source)\""
        )
        print("app08_chained_ios=ok")

        press(segment(Ident.Encode.direction, 1), "the direction picker's decode segment")
        let blocked = element(Ident.Step.blocked)
        XCTAssertTrue(blocked.waitForExistence(timeout: 15), "an appended step below a failing one is not blocked")
        try snap(into: &out)
        press(segment(Ident.Encode.direction, 0), "the direction picker's encode segment")
    }

    /// Step 9 on hashing. **Hashing has no input-validation failure** — any `String` has a UTF-8
    /// encoding and every encoding has a digest — so there is no error fixture here and a later reader
    /// should not go looking for a hashing error string. Its only non-output state is *blocked*, which
    /// is reachable on an appended card and is therefore harvested on the encode surface above.
    private func hashingSurface(into out: inout SweepHarvest) throws {
        press(element(Ident.Hashing.useExample), "the Hashing worked-value button")
        try snap(into: &out)

        press(control(Ident.Step.copy, 0), "the first digest's copy control")
        try snap(into: &out)

        press(control(Ident.Step.addStep, 0), "the first digest's add-step control")
        try snap(into: &out)
        press(control(Ident.Step.addStepMenu, 0), "the add-step menu's first item")
        try snap(into: &out)
    }

    /// Step 9 on timestamps: the picker's three options, the caption, the Detect title and the cells.
    private func timestampsSurface(into out: inout SweepHarvest) throws {
        press(element(Ident.Timestamps.useExample), "the Timestamps worked-value button")
        try snap(into: &out)

        for index in 0 ..< 3 {
            press(segment(Ident.Timestamps.readAs, index), "the read-as picker's segment \(index)")
            try snap(into: &out)
        }
        press(element(Ident.Timestamps.detect), "the detect control")
        try snap(into: &out)

        for fixture in SweepPopulation.timestampFixtures {
            replaceInput(Ident.Timestamps.input, with: fixture)
            try snap(into: &out)
        }
        clearInput(Ident.Timestamps.input, revealing: Ident.Timestamps.useExample)
        press(element(Ident.Timestamps.useExample), "the Timestamps worked-value button")

        press(control(Ident.Step.copy, 0), "the first representation's copy control")
        try snap(into: &out)
        press(control(Ident.Step.addStep, 0), "the first representation's add-step control")
        try snap(into: &out)
        press(control(Ident.Step.addStepMenu, 0), "the add-step menu's first item")
        try snap(into: &out)
    }

    // MARK: - Driving, all of it by identifier

    /// The first element carrying `identifier`, whatever kind of element it is.
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The `index`th element carrying `identifier` — the shape the `Step.*` constants are designed for.
    private func control(_ identifier: String, _ index: Int) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).element(boundBy: index)
    }

    /// One segment of a segmented picker, by index. A picker surfaces as buttons on iOS and as radio
    /// buttons on macOS, so both are tried rather than assumed.
    private func segment(_ identifier: String, _ index: Int) -> XCUIElement {
        let picker = element(identifier)
        let buttons = picker.buttons
        return buttons.count > index ? buttons.element(boundBy: index) : picker.radioButtons.element(boundBy: index)
    }

    /// `exists` first, `waitForExistence` only if it does not: the waiting form costs a full second per
    /// call even when the element is already there, and this walk makes some sixty of them.
    private func press(_ target: XCUIElement, _ what: String) {
        if !target.exists {
            XCTAssertTrue(target.waitForExistence(timeout: 20), "the walk cannot reach \(what)")
        }
        target.tap()
    }

    /// Replaces a field's contents. Deletes first: an empty `TextField` reports its prompt as `value`,
    /// so the delete count is an upper bound and over-deleting an empty field is a no-op.
    private func replaceInput(_ identifier: String, with text: String) {
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
    /// Measured, not assumed: a single delete pass left the Timestamps field non-empty on one run of
    /// two, and the walk then waited twenty seconds for a button the app was right not to be showing.
    /// A clear that is not verified is a step that can silently not happen.
    private func clearInput(_ identifier: String, revealing button: String) {
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
    private func focus(_ field: XCUIElement, _ identifier: String) {
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
    /// scroll-to-dismiss this used first worked on iOS 17.5 and 18.6 and failed on 26.1, where
    /// `scrollViews.firstMatch` resolves to an offscreen scroll view and XCUITest refuses the swipe
    /// ("visible frame is empty"). A gate that must hold on four runtimes cannot depend on which view
    /// a gesture happens to land in. Nothing in the walk depends on state surviving this: the appended
    /// card and the blocked sentence are harvested on the surface that created them, before it is
    /// ever called.
    private func dismissKeyboard() {
        guard app.keyboards.element.exists else { return }
        print("keyboard_dismissed_by=relaunch")
        app.terminate()
        app.launch()
        XCTAssertTrue(
            element(Ident.Shell.tabEncode).waitForExistence(timeout: 30),
            "the relaunch that puts the keyboard away did not bring the app back"
        )
    }

    /// Taps the tab item at `index` and confirms it showed the destination carrying `identifier`. The
    /// index addresses `app.tabBars.buttons`, whose population is asserted to be exactly 3 first.
    private func visit(_ index: Int, expecting identifier: String) {
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
