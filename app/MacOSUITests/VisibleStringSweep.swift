import XCTest

// THE D-93 VISIBLE-STRING SWEEP, macOS HALF. ROADMAP Phase 6 criterion 6; PRIV-06.
//
// ROUTED BY PLAN 06-01's MEASURED VERDICT, NOT BY ASSUMPTION. That plan asked whether a macOS UI test
// executes at all on a headless GitHub Actions runner, wrote routing for all four possible answers
// before anything depended on one, and recorded `probe_verdict=viable` —
// `harvested_strings=114 harvested_distinct=109 probe_reached_subject=true runner_headless=true`,
// run 33925478706, job `app (macOS)`. The `viable` branch says: write the macOS twin exactly like the
// iOS one, on the template-owned `.github/workflows/pr.yml` unedited, and delete the probe. This file
// is that branch. `HarvestProbeTests.swift` is deleted in the same change: it has served its purpose,
// and a second launching UI test in this target doubles the runner cost and the flake surface.
//
// TWO CONSTRAINTS 06-01 MEASURED, WHICH SHAPE EVERYTHING BELOW:
//
//  1. A `print` FROM THIS BUNDLE NEVER REACHES THE CI LOG. The bundle is injected into
//     `AppMacOSUITests-Runner.app`, launched by `testmanagerd`, whose stdout is not connected to
//     xcodebuild's pipe; only XCTest's own IPC crosses back. So every number this sweep produces
//     rides an ASSERTION MESSAGE or an `XCTContext` activity in the `.xcresult`. The `print` calls
//     are kept for a local run and are evidence of nothing on a runner. A green
//     `XCTAssertGreaterThan(count, 20)` proves the predicate, not the number.
//  2. THE HARVEST IS MOSTLY NOT THE APP. `try app.snapshot()` on the application element returns the
//     whole menu bar. `SweepPopulation` is the counted exclusion that fixes it; see that file.
//
// THE DETECTION IDIOM IS COPIED FROM `AppStoreScreenshotTests.swift:52-54`; THE SKIP IS NOT, AND
// NEITHER IS THE FOREGROUND-ACTIVATION CALL. launchd scrubs `CI` and `GITHUB_ACTIONS` from the
// runner's environment, so the home directory is the only usable signal — and it is recorded here as
// an observable FACT rather than branched on. A sweep that skipped on a headless runner would be a
// gate that has never executed, which is the blocking row this phase inherited and the one 06-14's
// own macOS assertion fell into (`harness_macos=skipped`, run 33953867591). This one executes.
//
// C-25 BOUNDS WHAT THIS PROVES: this target is pinned to Swift 5.9 / minimal concurrency, so the file
// is criterion-6 evidence only and NEVER evidence for APP-12.
//
// NEVER QUERY BY VISIBLE TEXT. Every element is addressed by an `AccessibilityIdentifiers` constant.

/// Every string the app renders, on every surface, in both appearances — and no prose term among them.
@MainActor
final class VisibleStringSweep: XCTestCase {
    private typealias Ident = AccessibilityIdentifiers

    private var app: XCUIApplication!

    /// The application element's own `label`. EMPTY ON macOS, and that is a measurement rather than an
    /// expectation: run 33959451763, job `app (macOS)`, failed clause 3 with
    /// `XCTAssertGreaterThan failed: ("0") is not greater than ("3") - the application element carries
    /// no name`, after a full 82.8-second walk. The iOS twin reads the display name straight off this
    /// property; on macOS it is blank and the name has to come from the menu bar instead.
    private var applicationLabel = ""

    /// The menu bar's top-level item titles, in order. Index 1 is the application menu, which is what
    /// settles RESEARCH assumption A3 — whether AppKit resolves that title from `CFBundleDisplayName`
    /// or `CFBundleName` was deliberately left unmeasured, and this reads it off the running app.
    private var menuBarItems: [String] = []

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
    /// PROVISIONAL AND SAID TO BE. The iOS twin's floor is measured — 85 against a measured 105-106.
    /// This one cannot be, until CI has run the sweep once: no number this bundle produces reaches the
    /// workflow log (06-01), so the real distinct count arrives only in a run whose assertion message
    /// carries it. Set low enough not to hold the first run red on a guess, and tightened against the
    /// measurement rather than left as the guess.
    private static let distinctFloor = 50

    override func setUpWithError() throws {
        continueAfterFailure = true // CONTROL RUN ONLY
    }

    /// CONTROL MUTATION sweep-reached-subject-macos: the walk points at a surface that does not exist.
    func testControlNearEmptyHarvest() {
        let seen = SweepHarvest()
        app = XCUIApplication()
        app.launch()
        _ = element("Shell.sidebar.doesNotExist").waitForExistence(timeout: 2)
        XCTAssertGreaterThan(
            seen.rendered.count,
            20,
            "the sweep saw almost nothing — it did not reach the app. harvested_strings=\(seen.rendered.count)"
        )
        app.terminate()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - The gate

    /// The walk, in both appearances, then the assertions in the order that matters.
    func testNoProseTermIsRenderedOnAnySurface() throws {
        var seen = SweepHarvest()
        let headless = NSHomeDirectory() == "/Users/runner"

        for scheme in ["light", "dark"] {
            app = XCUIApplication()
            app.launchArguments = ["-UITestColorScheme", scheme]
            app.launch()
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

        // CONTROL RUN ONLY — carries the counters out over XCTest's IPC, which is the only channel a
        // number can leave this bundle by (06-01). Placed last on purpose: reaching it proves every
        // assertion above it ran.
        XCTFail("SWEEP_COUNTERS \(counters) a3_menu_title_source=\(name.source) "
            + "a3_menu_title_value=\(name.value) menu_bar=\(menuBarItems.prefix(9).joined(separator: " | ")) "
            + "chrome_distinct=\(Set(seen.chrome).sorted().joined(separator: " | "))")

        // CONTROL RUN ONLY — is typing viable on a headless runner at all? Unmeasured until now.
        app = XCUIApplication()
        app.launch()
        let field = element(Ident.Encode.input)
        XCTAssertTrue(field.waitForExistence(timeout: 30), "TYPING_PROBE could not reach the input")
        field.click()
        field.typeText("zz")
        XCTFail("TYPING_PROBE typed=zz observed=\((field.value as? String) ?? "<nil>")")
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
    private func snap(into out: inout SweepHarvest) throws {
        let root = try app.snapshot()
        if !root.label.isEmpty {
            applicationLabel = root.label
        }
        harvest(root, inherited: .rendered, into: &out)
    }

    // MARK: - The walk

    /// Launch, then each surface in turn, harvesting after every step.
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
    }

    /// The encode/decode surface — the only one with an input-validation failure, and the only one
    /// whose error states this walk can reach, because it reaches them by CLICKING the direction
    /// picker rather than by typing. The worked value is not valid Base64 and its `&` opens an HTML
    /// entity that is never closed, so decode gives two of the app's error sentences for free.
    private func encodeSurface(into out: inout SweepHarvest) throws {
        press(element(Ident.Encode.useExample), "the Encode worked-value button")
        try snap(into: &out)

        for index in 0 ..< 3 {
            press(segment(Ident.Encode.format, index), "the format picker's segment \(index)")
            try snap(into: &out)
        }
        press(segment(Ident.Encode.direction, 1), "the direction picker's decode segment")
        for index in 0 ..< 3 {
            press(segment(Ident.Encode.format, index), "the format picker's segment \(index)")
            try snap(into: &out)
        }
        press(segment(Ident.Encode.direction, 0), "the direction picker's encode segment")
        press(segment(Ident.Encode.format, 0), "the format picker's first segment")

        try chainAndBlock(into: &out)
    }

    /// Copy, open the menu, choose an operation, then drive the appended card to blocked.
    ///
    /// Menu items are in the accessibility tree ONLY WHILE THE MENU IS OPEN, which is why the menu is
    /// opened and harvested before an item is chosen. The order after that is deliberate and is not
    /// the one the walk table reads at first glance: a step whose output is an error has its add-step
    /// control `.disabled(true)` by the State Contract, so the card is appended while the pipeline is
    /// VALID and the failure is installed afterwards. That is what puts the blocked sentence on screen.
    private func chainAndBlock(into out: inout SweepHarvest) throws {
        press(control(Ident.Step.copy, 0), "the first copy control")
        try snap(into: &out)

        press(control(Ident.Step.addStep, 0), "the first add-step control")
        try snap(into: &out)

        // The SEEDED card's value carries the surface's own constant; only APPENDED cards use the
        // shared `Step.output`. Measured from the running tree, not assumed.
        let source = element(Ident.Encode.output).label
        press(control(Ident.Step.addStepMenu, 0), "the add-step menu's first item")

        // ROADMAP criterion 8 / APP-08, asserted as its CONJUNCTION rather than as the existence of a
        // view type: the control is on screen, it was used, and the appended card renders the CHAINED
        // result. The first menu item is `Operation.allCases.first`, whose expected value this process
        // computes for itself — no app code is linked to produce it.
        let chained = control(Ident.Step.output, 0)
        XCTAssertTrue(chained.waitForExistence(timeout: 15), "the add-step menu appended no card")
        XCTAssertEqual(
            chained.label,
            Data(source.utf8).base64EncodedString(),
            "app08_chained_macos=failed — the appended step did not render the chained result of \"\(source)\""
        )
        try snap(into: &out)
        XCTContext.runActivity(named: "app08_chained_macos=ok") { _ in }

        press(segment(Ident.Encode.direction, 1), "the direction picker's decode segment")
        XCTAssertTrue(
            element(Ident.Step.blocked).waitForExistence(timeout: 15),
            "an appended step below a failing one is not blocked"
        )
        try snap(into: &out)
        press(segment(Ident.Encode.direction, 0), "the direction picker's encode segment")
    }

    /// Hashing. **It has no input-validation failure** — any `String` has a UTF-8 encoding and every
    /// encoding has a digest — so there is no error fixture here and a later reader should not go
    /// looking for a hashing error string. Its only non-output state is *blocked*, which is reachable
    /// on an appended card and is harvested on the encode surface above.
    private func hashingSurface(into out: inout SweepHarvest) throws {
        press(element(Ident.Hashing.useExample), "the Hashing worked-value button")
        try snap(into: &out)

        press(control(Ident.Step.copy, 0), "the first digest's copy control")
        try snap(into: &out)

        press(control(Ident.Step.addStep, 0), "the first digest's add-step control")
        try snap(into: &out)
        press(control(Ident.Step.addStepMenu, 0), "the add-step menu's first item")
        try appendedCard(into: &out)
    }

    /// Timestamps: the picker's three options, the caption, the Detect title and the cell titles.
    private func timestampsSurface(into out: inout SweepHarvest) throws {
        press(element(Ident.Timestamps.useExample), "the Timestamps worked-value button")
        try snap(into: &out)

        for index in 0 ..< 3 {
            press(segment(Ident.Timestamps.readAs, index), "the read-as picker's segment \(index)")
            try snap(into: &out)
        }
        press(element(Ident.Timestamps.detect), "the detect control")
        try snap(into: &out)

        press(control(Ident.Step.copy, 0), "the first representation's copy control")
        try snap(into: &out)
        press(control(Ident.Step.addStep, 0), "the first representation's add-step control")
        try snap(into: &out)
        press(control(Ident.Step.addStepMenu, 0), "the add-step menu's first item")
        try appendedCard(into: &out)
    }

    /// Waits for the card the add-step menu appended, THEN harvests it. Measured on the iOS twin: the
    /// snapshot taken straight after the menu tap caught the card unrendered on one runtime and
    /// rendered on another, and a population that depends on a race is the wrong population.
    private func appendedCard(into out: inout SweepHarvest) throws {
        XCTAssertTrue(control(Ident.Step.output, 0).waitForExistence(timeout: 15), "the menu appended no card")
        try snap(into: &out)
    }

    // MARK: - Driving, all of it by identifier

    /// The first element carrying `identifier`, whatever kind of element it is. Deliberately not scoped
    /// to a query category: a sidebar row, a card and a menu item are different element types.
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
    /// call even when the element is already there, and this walk makes some forty of them.
    private func press(_ target: XCUIElement, _ what: String) {
        if !target.exists {
            XCTAssertTrue(target.waitForExistence(timeout: 20), "the walk cannot reach \(what)")
        }
        target.click()
    }

    /// Moves to the destination carrying `identifier` and confirms it arrived.
    private func visit(_ identifier: String) {
        let destination = element(identifier)
        if !destination.exists {
            XCTAssertTrue(destination.waitForExistence(timeout: 20), "cannot reach the destination \(identifier)")
        }
        destination.click()
    }
}
