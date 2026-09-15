import XCTest

// THE MENU-OPENING, ITEM-SELECTION, LAUNCH AND QUERY HELPERS, SPLIT OUT OF
// `PrivacyLinkTests.swift`. A cross-file extension of that class, the same shape
// `SweepDriver.swift` already is of `VisibleStringSweep.swift`, and for the same reason: the
// file it split from is `swiftlint --strict`, `file_length` is 400 lines, and under `--strict`
// that limit is an ERROR rather than a warning.
//
// NOTHING BELOW CHANGED WHEN IT MOVED, beyond `private` becoming internal where a cross-file
// extension needs it — Swift `private` does not reach an extension in a different file.
//
// SWIFT 5.9 / `SWIFT_STRICT_CONCURRENCY: minimal`, matching both UI-test targets.

extension PrivacyLinkTests {
    // MARK: - The menu, opened by identity and closed again

    /// Opens the application's own menu and answers it.
    func openTheApplicationMenu(on surface: String) -> XCUIElement {
        let bar = app.menuBarItems
        let items = bar.count
        // Titles, not identifiers: this is EVIDENCE about the running app's menu
        // bar, read the only way macOS allows, never a query.
        let titles = (0 ..< items).map { readable(bar.element(boundBy: $0)) }
        record("macos_menubar_items_\(surface)=\(items) titles=\(titles.joined(separator: " | "))")

        // SELECTED BY IDENTITY, NOT POSITION — bar order is an assumption, and an identity read is
        // not. (Run 34973317967's "index 1 is the Apple menu" reading is withdrawn, UL-095.) See
        // `app/UITestSupport/AppMenuIdentity.swift`, the one shared helper this file and
        // `DriveHalfTests.swift` both call.
        return selectApplicationMenuBarItemByIdentity(on: app)
    }

    /// Puts the menu away so the next case does not inherit an open one.
    func closeTheMenu() {
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
    }

    /// THE `[OPEN]` MEASUREMENT, EMITTED ON EVERY RUN WHATEVER ITS VALUE, then
    /// the assertion that holds either way. Answers a MEASURED count — `-1` the
    /// ordinal was never safe, `byIdentifier` that route's count, `1`/`0` from the
    /// positional read. Both exits returned the literal `1` until 2026-09-11, so
    /// the caller's total compared 3 with 3 on every input (WR-01).
    func assertThePrivacyItemIsInTheMenu(_ menu: XCUIElement, on surface: String) -> Int {
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
            assertRendersText(item, PrivacyLinkTests.privacyPolicyTitle, "the app menu's privacy item on \(surface)")
            return byIdentifier
        }

        // THE FALLBACK, THE EXPECTED PATH: a zero IDENTIFIER count is the `[OPEN]`
        // resolved NEGATIVE (08-14 running, 06-13 `Menu` before it), not a defect.
        record("macos_privacy_identifier_survives=false reason=no-menu-item-carries-\(AccessibilityIdentifiers.Shell.privacyPolicy)")
        let entries = menu.descendants(matching: .menuItem)
        let population = entries.count
        let titles = (0 ..< population).map { readable(entries.element(boundBy: $0)) }
        record("macos_app_menu_items=\(population) titles=\(titles.joined(separator: " | "))")
        guard population > PrivacyLinkTests.privacyItemIndex else {
            XCTFail("\(surface): the app menu holds \(population) items, so \(PrivacyLinkTests.privacyItemIndex) is not a safe read")
            return -1
        }

        let positional = entries.element(boundBy: PrivacyLinkTests.privacyItemIndex)
        assertReadable(positional, "the app menu's item at index \(PrivacyLinkTests.privacyItemIndex) on \(surface)")
        assertRendersText(
            positional,
            PrivacyLinkTests.privacyPolicyTitle,
            "the app menu's item at index \(PrivacyLinkTests.privacyItemIndex) on \(surface)"
        )
        let read = positional.renderedText
        record("macos_privacy_read_\(surface)=\"\(read)\"")
        return read == PrivacyLinkTests.privacyPolicyTitle ? 1 : 0
    }

    /// The privacy item itself, by whichever route this platform allows. Throws (via
    /// `XCTUnwrap`) rather than guessing a position when the identity scan below does not find
    /// exactly one match — the same rule `AppMenuIdentity.swift`'s `resolvedApplicationName`
    /// applies, for the same reason: a silent `?? 0` would be a positional assumption wearing
    /// an identity's name (run 34973317967's "index 1 is the Apple menu" reading is withdrawn, UL-095).
    func thePrivacyItem(in menu: XCUIElement, on surface: String) throws -> XCUIElement {
        let byIdentifier = app.menuItems.matching(identifier: AccessibilityIdentifiers.Shell.privacyPolicy)
        let found = byIdentifier.count
        record("macos_privacy_identifier_count_\(surface)=\(found)")
        if found > 0 {
            return byIdentifier.element(boundBy: 0)
        }
        // IDENTITY, NOT POSITION (the AppStoreScreenshotTests.swift:350 shape): scan every
        // entry's text — renderedText, falling back to title when empty. AXTitle is where AppKit
        // publishes a menu item's text; the shared read rule reads `title` third, and `.label` never
        // falls back to it (run 34984109925) — and select the one that equals `privacyPolicyTitle`,
        // rather than trusting a fixed ordinal (adversarial #14 / C-19e).
        let entries = menu.descendants(matching: .menuItem)
        let population = entries.count
        var titles: [String] = []
        var matches: [Int] = []
        for index in 0 ..< population {
            let entry = entries.element(boundBy: index)
            let text = entry.renderedText.isEmpty ? entry.title : entry.renderedText
            titles.append(text)
            if text == PrivacyLinkTests.privacyPolicyTitle {
                matches.append(index)
            }
        }
        XCTAssertEqual(
            matches.count, 1,
            "\(surface): \(matches.count) app-menu items render \"\(PrivacyLinkTests.privacyPolicyTitle)\", "
                + "expected exactly 1 — \(titles)"
        )
        let matchIndex = try XCTUnwrap(
            matches.first,
            "\(surface): no app-menu item renders \"\(PrivacyLinkTests.privacyPolicyTitle)\" to select — \(titles)"
        )
        return entries.element(boundBy: matchIndex)
    }

    // MARK: - Launching, and queries, all of them by identifier

    /// A fresh application pinned to `destination`, because `selection` persists.
    func launch(_ destination: String) {
        app = XCUIApplication()
        app.launchPinned(showing: destination)
    }

    /// The surface really rendered before anything is counted on it.
    func awaitSurface(_ probe: String, _ name: String) {
        XCTAssertTrue(
            element(probe).waitForExistence(timeout: 30),
            "the app did not present the \(name) surface — no element carries \(probe)"
        )
    }

    /// How many elements carry `identifier` right now. One round trip.
    func count(_ identifier: String) -> Int {
        all(identifier).count
    }

    /// Every element carrying `identifier`, whatever kind of element it is.
    func all(_ identifier: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: identifier)
    }

    /// The first element carrying `identifier`.
    func element(_ identifier: String) -> XCUIElement {
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
    func readable(_ target: XCUIElement) -> String {
        target.renderedText
    }

    /// One measured number, emitted twice. A `print` from this bundle does NOT
    /// reach xcodebuild's pipe on macOS (06-01) — the runner is launched by
    /// `testmanagerd`, whose stdout is not connected to it — so every number also
    /// rides an `XCTContext` activity, which is the one channel that crosses.
    func record(_ line: String) {
        print(line)
        XCTContext.runActivity(named: line) { _ in }
    }
}
