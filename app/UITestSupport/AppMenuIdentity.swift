import XCTest

// SELECT THE APP'S OWN MENU-BAR ITEM BY IDENTITY, NEVER BY POSITION.
//
// MEASURED DEFECT (run 34973317967, evidence/08.5-07-ci-readback.txt): `menuBarItems.element(boundBy:
// 1)`, clicked, and its opened contents enumerated, recorded "About This Mac", "System Information",
// "Force Quit…", "Force Quit ShipkitPipes", "Sleep" and their Apple-menu siblings — not the
// application's own menu. The ordinal "index 0 is the Apple menu, index 1 is the app's own menu"
// (`ScreenshotContract.swift`'s own documented addressing) does not hold on every runner. This file
// replaces the ordinal CLICK with an identity read at the two call sites that took it:
// `DriveHalfTests.swift` and `PrivacyLinkTests.swift`.
//
// THE PER-ITEM READ GOES THROUGH `ElementText.swift`'s `renderedText`, NEVER `.label` ALONE. A
// macOS menu-bar item is measured to carry its text the same way a menu item does
// (`ElementText.swift`'s seventh shape, type 54): AXTitle, which `.label` alone never reads.
//
// THE EXPECTED NAME COMES FROM THE APPLICATION ELEMENT'S OWN RENDERED TEXT, NEVER A LITERAL AND
// NEVER A MENU-BAR POSITION. `app/MacOSUITests/VisibleStringSweep.swift`'s `productName` (private
// to a different UI-test target's leaf test class, unreachable from here) still falls back to the
// SECOND distinct menu-bar-item title when the application element reads empty — that fallback IS
// the positional-identity defect this file exists to stop trusting for the CLICK, so this file does
// not reproduce it. RULED (ios-macos-smoketest-74, 2026-09-15): when the application element's own
// rendered text is empty, the resolved source is `none` and selection FAILS BY NAME — see
// `resolvedApplicationName` and `selectApplicationMenuBarItemByIdentity` below — rather than
// inferring the app's name from `entries[1]`.
//
// WHY THIS IS STILL AN IDENTITY FIX AND NOT A RENAMED ORDINAL. The EXPECTED name is resolved once
// from a single accessibility snapshot (the same rule `productName` already applies); the SELECTION
// this file performs is a NAME SEARCH over the LIVE menu bar for an item whose own rendered text
// equals that expectation — never an index into the live query. A runner where the live query's
// ordering disagrees with the snapshot's is exactly the case this guards: it fails BY NAME, naming
// the runner's actual titles, rather than clicking whatever sits at a fixed position.
//
// THE SAFETY ASSERTION. Once selected and clicked, the opened menu's own items are checked against
// the two Apple-menu entries run 34973317967 actually recorded at the old ordinal — "About This Mac"
// and "Force Quit…" — so a selection that is STILL wrong fails immediately, by name, rather than
// silently handing the wrong menu's contents to a caller.
//
// SWIFT 5.9 / `SWIFT_STRICT_CONCURRENCY: minimal`, matching both UI-test targets. macOS only — the
// menu bar this file addresses does not exist on iOS.

#if os(macOS)
    extension XCUIApplication {
        /// One top-level menu-bar item, read from a single accessibility snapshot: its own rendered
        /// text and its first submenu entry's rendered text. AppKit publishes a menu's structure via
        /// accessibility whether or not it is open, so reading this needs no click.
        struct MenuBarSnapshotEntry {
            let title: String
            let firstChildTitle: String
        }

        /// EVERY top-level menu-bar item, in document order, from ONE `snapshot()` call — never a
        /// click-per-item loop, matching this codebase's bounded-read discipline
        /// (`SweepDriver.swift`'s `count(_:)` doc comment; `BlindReadGuards.swift`'s file header).
        /// Deduplicates by title, the same rule `SweepDriver.swift`'s `harvest(_:inherited:into:)`
        /// already applies when it builds the array `productName` reads from.
        func menuBarSnapshotEntries() throws -> [MenuBarSnapshotEntry] {
            var entries: [MenuBarSnapshotEntry] = []
            func walk(_ node: XCUIElementSnapshot) {
                if node.elementType == .menuBarItem {
                    let title = node.renderedText
                    if !title.isEmpty, !entries.contains(where: { $0.title == title }) {
                        let firstChild = node.children.first?.renderedText ?? ""
                        entries.append(MenuBarSnapshotEntry(title: title, firstChildTitle: firstChild))
                    }
                }
                for child in node.children {
                    walk(child)
                }
            }
            try walk(snapshot())
            return entries
        }
    }

    /// The app's own name, read from the application element's own rendered text alone — see the
    /// file header. Never falls back to a menu-bar position: an empty rendered text resolves to
    /// `("", "none")` and the caller fails by name rather than guessing. Not a member of
    /// `XCTestCase` or `XCUIApplication`: it takes only what it needs, so it stays testable and
    /// short on its own.
    private func resolvedApplicationName(
        applicationRenderedText: String
    ) -> (value: String, source: String) {
        if !applicationRenderedText.isEmpty {
            return (applicationRenderedText, "application-element-rendered-text")
        }
        return ("", "none")
    }

    extension XCTestCase {
        /// The `.keepAlways` `menu-bar-enumeration` attachment — every top-level item's index,
        /// title and first submenu entry, plus the resolved expectation, so a reader can see what
        /// was compared against what without re-deriving it from the assertions below.
        private func recordMenuBarEnumeration(
            _ entries: [XCUIApplication.MenuBarSnapshotEntry],
            expected: (value: String, source: String)
        ) {
            let enumerationLines = entries.enumerated().map { index, entry in
                "menu_bar index=\(index) title=\"\(entry.title)\" first_child_title=\"\(entry.firstChildTitle)\""
            }
            let attachment = XCTAttachment(
                string: (["resolved_name=\"\(expected.value)\" source=\(expected.source)"] + enumerationLines)
                    .joined(separator: "\n")
            )
            attachment.name = "menu-bar-enumeration"
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        /// THE SAFETY ASSERTION — see the file header. Run 34973317967's Apple-menu items at the
        /// old ordinal are this assertion's runner red half (evidence/08.5-07-ci-readback.txt):
        /// "About This Mac", "Force Quit…", "Force Quit ShipkitPipes", "Sleep" — an Apple-menu
        /// content set, not this app's own. If a selection made by identity still opens that
        /// content, this fails immediately rather than letting a caller search it downstream.
        private func assertOpenedMenuIsNotTheAppleMenu(
            _ app: XCUIApplication,
            selectedName: String,
            file: StaticString,
            line: UInt
        ) {
            let opened = app.descendants(matching: .menuItem)
            let openedCount = min(opened.count, 12)
            var sawAboutThisMac = false
            var sawForceQuit = false
            for itemIndex in 0 ..< openedCount {
                let text = opened.element(boundBy: itemIndex).renderedText
                if text == "About This Mac" {
                    sawAboutThisMac = true
                }
                if text.hasPrefix("Force Quit") {
                    sawForceQuit = true
                }
            }
            XCTAssertFalse(
                sawAboutThisMac || sawForceQuit,
                "the menu selected by identity (\"\(selectedName)\") opened Apple-menu content (About "
                    + "This Mac / Force Quit) — the same shape run 34973317967 measured at the old "
                    + "ordinal click (evidence/08.5-07-ci-readback.txt)",
                file: file, line: line
            )
        }

        /// Selects, opens and safety-checks the application's OWN top-level menu-bar item BY
        /// IDENTITY — see the file header. Records the `.keepAlways` `menu-bar-enumeration`
        /// attachment, clicks the matched item, asserts the opened menu excludes the Apple menu's own
        /// entries, and returns the clicked top-level element — the shape both call sites already
        /// held before this fix (`DriveHalfTests.swift`'s local `appMenu`,
        /// `PrivacyLinkTests.swift`'s `openTheApplicationMenu`'s `menu`).
        ///
        /// XCTFails BY NAME — the expected name and the enumerated titles — if nothing matches; it
        /// never falls back to an index. If `continueAfterFailure` is true at the call site (as
        /// `PrivacyLinkTests.testOnePrivacyControlOnEverySurface` sets it, deliberately, to measure
        /// every surface even after one fails), execution continues past the failure and this
        /// returns an UNCLICKED placeholder — a mechanical necessity of the non-optional return
        /// type, not a second selection route; the failure above has already named the defect.
        @discardableResult
        func selectApplicationMenuBarItemByIdentity(
            on app: XCUIApplication,
            file: StaticString = #filePath,
            line: UInt = #line
        ) -> XCUIElement {
            let entries: [XCUIApplication.MenuBarSnapshotEntry]
            let applicationRenderedText: String
            do {
                let root = try app.snapshot()
                applicationRenderedText = root.renderedText
                entries = try app.menuBarSnapshotEntries()
            } catch {
                XCTFail("could not read the menu bar's accessibility snapshot: \(error)", file: file, line: line)
                return app.menuBarItems.firstMatch
            }

            let expected = resolvedApplicationName(applicationRenderedText: applicationRenderedText)
            recordMenuBarEnumeration(entries, expected: expected)

            guard !expected.value.isEmpty else {
                XCTFail(
                    "app element rendered no name; refusing to infer it from menu position — enumerated: "
                        + "\(entries.map(\.title).joined(separator: " | "))",
                    file: file, line: line
                )
                return app.menuBarItems.firstMatch
            }

            let live = app.menuBarItems
            let liveCount = live.count
            for index in 0 ..< liveCount {
                let candidate = live.element(boundBy: index)
                if candidate.renderedText == expected.value {
                    candidate.click()
                    assertOpenedMenuIsNotTheAppleMenu(
                        app, selectedName: expected.value, file: file, line: line
                    )
                    return candidate
                }
            }

            XCTFail(
                "no menu-bar item's title matches the resolved app name \"\(expected.value)\" (source: "
                    + "\(expected.source)) — enumerated: \(entries.map(\.title).joined(separator: " | "))",
                file: file, line: line
            )
            return app.menuBarItems.firstMatch
        }
    }
#endif
