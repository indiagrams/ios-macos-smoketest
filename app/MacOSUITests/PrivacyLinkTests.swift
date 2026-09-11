import XCTest

// THE PRIVACY CONTROL — macOS HALF (META-06, D-117, 08-UI-SPEC.md §Accessibility).
// `app/UITests/PrivacyLinkTests.swift` is the twin and declares the SAME three
// test names for the same three claims, exactly as the `ShellTests` pair already
// does across two different containers. The mechanisms differ because D-11 chose
// two containers: iOS answers 5.1.1(i) with a navigation-bar item on every
// surface, macOS with one app-menu item after About.
//
// THE `[OPEN]` THIS FILE EXISTS TO SETTLE. 08-UI-SPEC.md §Accessibility records,
// as a first-class `[OPEN]`, that nobody knows whether a SwiftUI `CommandGroup`
// button carries its `accessibilityIdentifier` into the macOS menu bar — no
// primary source says either way, and 06-13 measured the analogous NEGATIVE for
// `Menu` containers. So this suite MEASURES it and emits the number on every
// run, whatever its value, and then asserts in a way that holds either way:
// the identifier branch when the identifier survives, and a POSITIONAL fallback
// comparing the item's rendered text against the catalog value when it does not.
// A plan that turned that `[OPEN]` into a confident sentence without running it
// would have done the thing this project keeps paying for.
//
// THE MENU IS OPENED POSITIONALLY, NEVER BY ITS VISIBLE NAME. Index 0 of the
// menu bar is the Apple menu, so the application's own menu is index 1; that is
// an ordinal and not a query by visible text. SUBSCRIPTING the menu-bar query
// with the app's display name is forbidden here, and the forbidden shape is
// named in prose rather than written because `evidence/08-11-controls.rb` greps
// this file for it — a file that spells what a gate scans for sweeps that gate
// green by existing, which is the defect six Phase 5 plans hit in a row. The one
// such query in this target (`AppStoreScreenshotTests.swift:69-75`) is a
// headless-runner window fallback kept for its own reason and must not be
// extended.
//
// EVERY TEXT READ GOES THROUGH THE SHARED LAYER, AND ON THIS PLATFORM THAT IS
// NOT A FORMALITY. `app/UITestSupport/ElementText.swift:23-28`: macOS publishes
// a plain SwiftUI `Text`'s content in **AXValue alone**, and XCUITest's `.label`
// is built from AXDescription falling back to AXTitle and never reads AXValue —
// so `.label` is a CONSTANT EMPTY STRING here for the three commonest text
// shapes, for an element rendering the wrong string and the right string alike.
// An assertion on `.label` would compare "" with "" and pass forever. Every read
// below is `renderedText`, guarded by `assertReadable` before any comparison,
// and the expectation is guarded too — `assertRendersText` refuses a comparison
// whose expected side is itself empty.
//
// MATCHING IS A SEPARATE MECHANISM AND IS NOT BLIND. The same measurement
// records that `matching(identifier:)` COUNTS correctly on the very run where
// three `.label` reads came back empty, so the identifier query below is not
// weakened by any of the above. Reading is the blind half; finding is not.
//
// BOUNDED QUERIES ONLY (UL-064): one `count` read and a bounded loop, never a
// wait, and nothing here waits for an element expected to be ABSENT. The menu is
// closed again after every opening, so the next case does not inherit one.
//
// C-25 BOUNDS WHAT THIS PROVES: Swift 5.9 / `SWIFT_STRICT_CONCURRENCY: minimal`,
// like every file in this target, so this is META-06 evidence and never evidence
// for APP-12.

/// One privacy control reachable from every macOS surface — through the app
/// menu, read the only way this platform can be read (META-06, D-117).
@MainActor
final class PrivacyLinkTests: XCTestCase {
    private var app: XCUIApplication!

    /// The three surfaces, `LaunchLayoutTests.swift:59-63`'s rows reused rather
    /// than re-typed. The menu item is app-wide, so what this list varies is
    /// WHICH SURFACE IS SHOWING while the menu is asked — which is the macOS
    /// reading of D-118's reachability claim.
    private static let surfaces = [
        Surface(LaunchState.encodeDestination, "encode", AccessibilityIdentifiers.Encode.input),
        Surface(LaunchState.hashingDestination, "hashing", AccessibilityIdentifiers.Hashing.input),
        Surface(LaunchState.timestampsDestination, "timestamps", AccessibilityIdentifiers.Timestamps.input)
    ]

    /// The application's own menu, positionally: index 0 is the Apple menu.
    private static let appMenuIndex = 1

    /// Where `CommandGroup(after: .appInfo)` puts the item: immediately after
    /// About, which is menu item index 0. Used ONLY by the fallback branch, and
    /// only after the menu's own population has been asserted to reach it.
    private static let privacyItemIndex = 1

    /// The catalog value of `app.privacyPolicy`, which is what the menu item's
    /// title renders (`app/Shared/Localizable.xcstrings`; the macOS branch of
    /// `PrivacyPolicyLink.swift` renders the key and overrides no label).
    ///
    /// **Spelled here because a UI-test process cannot reach the app's compiled
    /// catalog**, and because this is an EXPECTATION rather than a QUERY: nothing
    /// in this file FINDS an element by this string. An expectation has to come
    /// from outside the thing it judges or it judges nothing — that is the
    /// vacuous-comparison shape `assertRendersText` refuses by name.
    private static let privacyPolicyTitle = "Privacy Policy"

    /// The root card is ALONE on a surface at launch. Read from the assertion
    /// that already carries it: `app/MacOSUITests/VisibleStringSweep.swift:389`.
    private static let cardsAtLaunch = 1

    /// D-100 as a RELATION, not a literal: one remove control per APPENDED card
    /// (`app/MacOSUITests/StepEditTests.swift`, `VisibleStringSweep.swift:392`).
    private static let removesAtLaunch = cardsAtLaunch - 1

    /// The Hashing surface's four value cells, enumerated from the shipped enum.
    private static let hashingCells = [
        AccessibilityIdentifiers.Hashing.digestMD5,
        AccessibilityIdentifiers.Hashing.digestSHA1,
        AccessibilityIdentifiers.Hashing.digestSHA256,
        AccessibilityIdentifiers.Hashing.digestSHA512
    ]

    /// The Timestamps surface's representation cells, the same way.
    private static let timestampsCells = [
        AccessibilityIdentifiers.Timestamps.cellEpoch,
        AccessibilityIdentifiers.Timestamps.cellISO8601,
        AccessibilityIdentifiers.Timestamps.cellDateTime
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - D-117's macOS half, and the `[OPEN]` it depends on

    /// The app menu carries the privacy item while EACH surface is showing —
    /// asserted per surface, each failure naming its surface, before any total.
    ///
    /// **THIS ONE CASE CONTINUES AFTER A FAILURE, AND THE REASON IS THE CLAIM.**
    /// Every other case in this target stops at the first failure because it
    /// DRIVES something and a later step would measure wreckage. Nothing is
    /// driven here: each surface gets its own pinned launch, so the three
    /// measurements are independent, and stopping at the first would report one
    /// surface when three were available. "missing while Timestamps is showing"
    /// and "missing everywhere" are different defects with different causes, and
    /// a suite that can only ever name the first surface cannot tell them apart.
    func testOnePrivacyControlOnEverySurface() {
        continueAfterFailure = true
        var perSurface: [(name: String, found: Int)] = []

        for surface in Self.surfaces {
            launch(surface.destination)
            awaitSurface(surface.probe, surface.name)

            let menu = openTheApplicationMenu(on: surface.name)
            let found = assertThePrivacyItemIsInTheMenu(menu, on: surface.name)
            closeTheMenu()

            perSurface.append((surface.name, found))
        }

        // AND ONLY NOW A TOTAL, from the numbers already asserted.
        let total = perSurface.reduce(0) { $0 + $1.found }
        let breakdown = perSurface.map { "\($0.name)=\($0.found)" }.joined(separator: " ")
        record("privacy_controls_total=\(total) \(breakdown)")
        XCTAssertEqual(total, Self.surfaces.count, "privacy_controls_total=\(total), expected one per surface: \(breakdown)")
    }

    // MARK: - Present is not the same as usable

    /// The item a reviewer has to choose is hit-testable and enabled.
    func testThePrivacyControlIsHittableAndEnabled() {
        let surface = Self.surfaces[0]
        launch(surface.destination)
        awaitSurface(surface.probe, surface.name)

        let menu = openTheApplicationMenu(on: surface.name)
        let item = thePrivacyItem(in: menu, on: surface.name)
        record("privacy_hittable_\(surface.name)=\(item.isHittable) privacy_enabled_\(surface.name)=\(item.isEnabled)")
        XCTAssertTrue(item.isHittable, "the privacy item in the app menu is not hit-testable on \(surface.name)")
        XCTAssertTrue(item.isEnabled, "the privacy item in the app menu is disabled on \(surface.name)")
        closeTheMenu()
    }

    // MARK: - The control added chrome, not content

    /// Every Phase 7 structural count on every surface is where Phase 7 left it.
    ///
    /// The expectations are read from the assertions that already carry them, not
    /// typed from a plan — plan literals go stale by allocation.
    func testStructuralCountsAreUnchangedOnEverySurface() {
        for surface in Self.surfaces {
            launch(surface.destination)
            awaitSurface(surface.probe, surface.name)

            let cards = count(AccessibilityIdentifiers.Step.card)
            let adds = count(AccessibilityIdentifiers.Step.addStep)
            let removes = count(AccessibilityIdentifiers.Step.remove)
            record("structural_\(surface.name) cards=\(cards) addsteps=\(adds) removes=\(removes)")

            XCTAssertEqual(cards, Self.cardsAtLaunch, "\(surface.name): \(cards) cards at launch, expected the pinned root alone")
            XCTAssertEqual(removes, Self.removesAtLaunch, "\(surface.name): \(removes) remove controls beside \(cards) cards")
            // Per-output and therefore per-surface, so the Phase 7 assertion on
            // it is "greater than zero" and this one is the same assertion; the
            // number itself is recorded above.
            XCTAssertGreaterThan(adds, 0, "\(surface.name): no add-step control at launch at all")

            assertCellsAreIntact(on: surface)
        }
    }

    /// One element per declared value cell on the surface that owns them.
    ///
    /// **The worked value is clicked in first**, because `OutputBlock.swift:65-73`
    /// attaches the value identifier on the `.value` branch ALONE: a cell showing
    /// a placeholder carries no identifier at all. Measured on the iOS twin —
    /// all three `Timestamps.cell.*` count 0 at launch and 1 after one click,
    /// while the four Hashing digests count 1 either side because
    /// `DigestRow.swift:141` attaches unconditionally. Asserting at launch would
    /// have been an assertion about the EMPTY state wearing this name.
    private func assertCellsAreIntact(on surface: Surface) {
        let cells: [String]
        let example: String
        switch surface.name {
        case "hashing":
            cells = Self.hashingCells
            example = AccessibilityIdentifiers.Hashing.useExample
        case "timestamps":
            cells = Self.timestampsCells
            example = AccessibilityIdentifiers.Timestamps.useExample
        default:
            return
        }

        let button = element(example)
        XCTAssertTrue(button.waitForExistence(timeout: 20), "\(surface.name): no worked-value button carries \(example)")
        button.click()

        for cell in cells {
            let found = count(cell)
            record("structural_\(surface.name)_cell \(cell)=\(found)")
            XCTAssertEqual(found, 1, "\(surface.name): \(found) elements carry \(cell), expected exactly 1")
        }
    }

    // MARK: - The menu, opened positionally and closed again

    /// Opens the application's own menu and answers it, after asserting that the
    /// menu bar has enough items for the ordinal to mean anything.
    private func openTheApplicationMenu(on surface: String) -> XCUIElement {
        let bar = app.menuBarItems
        let items = bar.count
        // Titles, not identifiers: this is EVIDENCE about the running app's menu
        // bar, read the only way macOS allows, never a query.
        let titles = (0 ..< items).map { readable(bar.element(boundBy: $0)) }
        record("macos_menubar_items=\(items) titles=\(titles.joined(separator: " | "))")
        XCTAssertGreaterThan(
            items,
            Self.appMenuIndex,
            "\(surface): the menu bar carries \(items) items, so index \(Self.appMenuIndex) is not a safe read — \(titles)"
        )

        let menu = bar.element(boundBy: 1)
        menu.click()
        return menu
    }

    /// Puts the menu away so the next case does not inherit an open one.
    private func closeTheMenu() {
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
    }

    /// THE `[OPEN]` MEASUREMENT, EMITTED ON EVERY RUN WHATEVER ITS VALUE, then
    /// the assertion that holds either way. Answers 1 — one item, however it was
    /// resolved — so the caller can total the surfaces.
    private func assertThePrivacyItemIsInTheMenu(_ menu: XCUIElement, on surface: String) -> Int {
        let byIdentifier = app.menuItems.matching(identifier: AccessibilityIdentifiers.Shell.privacyPolicy).count
        record("macos_privacy_identifier_survives_\(surface)=\(byIdentifier > 0) macos_privacy_identifier_count_\(surface)=\(byIdentifier)")

        if byIdentifier > 0 {
            XCTAssertEqual(
                byIdentifier,
                1,
                "\(surface): \(byIdentifier) menu items carry \(AccessibilityIdentifiers.Shell.privacyPolicy), expected exactly 1"
            )
            let item = app.menuItems.matching(identifier: AccessibilityIdentifiers.Shell.privacyPolicy).element(boundBy: 0)
            assertReadable(item, "the app menu's privacy item on \(surface)")
            assertRendersText(item, Self.privacyPolicyTitle, "the app menu's privacy item on \(surface)")
            return 1
        }

        // THE FALLBACK, AND THE FINDING IT CARRIES. A zero here is not a failure
        // of this app — it is the `[OPEN]` resolving NEGATIVE, the same answer
        // 06-13 measured for `Menu` containers — so it is recorded as a named
        // fact rather than hidden behind a green, and the item is then resolved
        // by its ORDINAL inside the menu that was just opened.
        record("macos_privacy_identifier_survives=false reason=no-menu-item-carries-\(AccessibilityIdentifiers.Shell.privacyPolicy)")
        let entries = menu.descendants(matching: .menuItem)
        let population = entries.count
        let titles = (0 ..< population).map { readable(entries.element(boundBy: $0)) }
        record("macos_app_menu_items=\(population) titles=\(titles.joined(separator: " | "))")
        XCTAssertGreaterThan(
            population,
            Self.privacyItemIndex,
            "\(surface): the app menu holds \(population) items, so index \(Self.privacyItemIndex) is not a safe read — \(titles)"
        )

        let positional = entries.element(boundBy: Self.privacyItemIndex)
        assertReadable(positional, "the app menu's item at index \(Self.privacyItemIndex) on \(surface)")
        assertRendersText(
            positional,
            Self.privacyPolicyTitle,
            "the app menu's item at index \(Self.privacyItemIndex) on \(surface)"
        )
        return 1
    }

    /// The privacy item itself, by whichever route this platform allows.
    private func thePrivacyItem(in menu: XCUIElement, on surface: String) -> XCUIElement {
        let byIdentifier = app.menuItems.matching(identifier: AccessibilityIdentifiers.Shell.privacyPolicy)
        let found = byIdentifier.count
        record("macos_privacy_identifier_count_\(surface)=\(found)")
        if found > 0 {
            return byIdentifier.element(boundBy: 0)
        }
        let entries = menu.descendants(matching: .menuItem)
        XCTAssertGreaterThan(entries.count, Self.privacyItemIndex, "\(surface): the app menu holds \(entries.count) items")
        return entries.element(boundBy: Self.privacyItemIndex)
    }

    // MARK: - Launching, and queries, all of them by identifier

    /// A fresh application pinned to `destination`, because `selection` persists.
    private func launch(_ destination: String) {
        app = XCUIApplication()
        app.launchPinned(showing: destination)
    }

    /// The surface really rendered before anything is counted on it.
    private func awaitSurface(_ probe: String, _ name: String) {
        XCTAssertTrue(
            element(probe).waitForExistence(timeout: 30),
            "the app did not present the \(name) surface — no element carries \(probe)"
        )
    }

    /// How many elements carry `identifier` right now. One round trip.
    private func count(_ identifier: String) -> Int {
        all(identifier).count
    }

    /// Every element carrying `identifier`, whatever kind of element it is.
    private func all(_ identifier: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: identifier)
    }

    /// The first element carrying `identifier`.
    private func element(_ identifier: String) -> XCUIElement {
        all(identifier).firstMatch
    }

    /// What an element is RENDERING, in whichever attribute this platform
    /// publishes it in.
    ///
    /// **DELEGATES TO ``XCUIElement/renderedText``**, the convention
    /// `app/MacOSUITests/SweepDriver.swift:92-135` established on 2026-09-10 and
    /// the reason `app/UITestSupport/` exists. This file was born delegating on
    /// 2026-09-11, so there is no local implementation it replaced — the line is
    /// here so a reader looking for the rule finds the same pointer at every
    /// site. The rule: `label` FIRST, then the element's own string `value`,
    /// because macOS carries a plain `Text`'s content in `AXValue` alone and
    /// `.label` never reads it.
    private func readable(_ target: XCUIElement) -> String {
        target.renderedText
    }

    /// One measured number, emitted twice. A `print` from this bundle does NOT
    /// reach xcodebuild's pipe on macOS (06-01) — the runner is launched by
    /// `testmanagerd`, whose stdout is not connected to it — so every number also
    /// rides an `XCTContext` activity, which is the one channel that crosses.
    private func record(_ line: String) {
        print(line)
        XCTContext.runActivity(named: line) { _ in }
    }
}
