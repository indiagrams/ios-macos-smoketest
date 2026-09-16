import XCTest

// SELECT THE APP'S OWN MENU-BAR ITEM BY IDENTITY, NEVER BY POSITION.
//
// WHY, CORRECTED (UL-095). Run 34973317967 clicked `menuBarItems.element(boundBy: 1)` and then
// enumerated "About This Mac", "Force Quit…", "Sleep" and the other Apple-menu items, which was read at
// the time as index 1 being the Apple menu. That reading is WITHDRAWN: the enumeration used the app-wide
// `descendants(matching: .menuItem)`, which lists the menu items of the whole menu bar, Apple menu first,
// rather than those of the menu just opened. On run 34978692666 the bar enumerated index 1 as the
// application's own menu. The ordinal
// was never measured wrong; it is still an assumption about bar order, and an identity read is not. This
// file is that identity read, at the two call sites that clicked by position: `DriveHalfTests.swift` and
// `PrivacyLinkTests.swift`.
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
// THE SAFETY ASSERTION. Once selected and clicked, the SELECTED ITEM'S OWN SUBMENU is checked
// against the two Apple-menu entries run 34973317967 recorded — "About This Mac" and "Force Quit…" —
// so a selection that is STILL wrong fails immediately, by name, rather than silently handing the
// wrong menu's contents to a caller.
//
// SCOPED TO THE SELECTED ITEM, NEVER THE APPLICATION (run 34978692666). The first version read
// `app.descendants(matching: .menuItem)`: every menu item across the WHOLE bar, Apple menu first,
// so it failed on a CORRECT selection (`resolved_name="ShipkitPipes"`) every time. The same
// whole-bar query is why run 34973317967 appeared to show index 1 opening the Apple menu; that run
// was never a red half. An EMPTY scoped read fails too, by its own message, so a query that reaches
// nothing cannot pass for "no Apple-menu content". The genuine red half is a standing control:
// `DriveHalfTests.testAppleMenuExclusionFiresOnTheAppleMenu` opens bar item 0 and expects exactly
// this assertion's message.
//
// SWIFT 5.9 / `SWIFT_STRICT_CONCURRENCY: minimal`, matching both UI-test targets. macOS only — the
// menu bar this file addresses does not exist on iOS.

#if os(macOS)
    extension XCUIApplication {
        /// One top-level menu-bar item, read from a single accessibility snapshot: its own rendered
        /// text and its own submenu's first entry's rendered text. AppKit publishes a menu's
        /// structure via accessibility whether or not it is open, so reading this needs no click.
        ///
        /// `firstChildTitle` READS THE GRANDCHILD, NOT THE CHILD (R1-IN-03, fixed 08.6-04). A
        /// menu-bar item's DIRECT child is its own `menu` node, which renders no text of its own —
        /// the phase evidence recorded `first_child_title=""` for all 7 items while the walk read
        /// only that far. The field carries the submenu's first entry, one level further in, which
        /// is what every reader of the `menu-bar-enumeration` attachment already assumed it meant.
        struct MenuBarSnapshotEntry {
            let title: String
            let firstChildTitle: String
        }

        /// The single recursive walk both menu-bar readers below share: visits every
        /// `.menuBarItem` node reachable from `node`, in document order, over an already-taken
        /// `snapshot()`. Neither reader re-derives what a menu-bar item is; they differ only in
        /// what `visit` collects, so a future change cannot make them disagree about the
        /// population.
        private func walkMenuBarItems(_ node: XCUIElementSnapshot, visit: (XCUIElementSnapshot) -> Void) {
            if node.elementType == .menuBarItem {
                visit(node)
            }
            for child in node.children {
                walkMenuBarItems(child, visit: visit)
            }
        }

        /// EVERY top-level menu-bar item, in document order, walked over a root ALREADY TAKEN by
        /// the caller — never a click-per-item loop, matching this codebase's bounded-read
        /// discipline (`SweepDriver.swift`'s `count(_:)` doc comment; `BlindReadGuards.swift`'s
        /// file header). Deduplicates by title, the same rule `SweepDriver.swift`'s
        /// `harvest(_:inherited:into:)` already applies when it builds the array `productName`
        /// reads from. THIS DEDUP IS FOR READERS THAT WANT A DISPLAY LIST — a reader that needs to
        /// COUNT the population, so a uniqueness bound can fail on a duplicate title, must use
        /// `menuBarSnapshotTitles(from:)` below instead (R1-IN-02).
        ///
        /// TAKES NO SNAPSHOT ITSELF (R1-IN-01, fixed 08.6-04). Before this fix, every caller that
        /// already held a root from its own `try app.snapshot()` still called the throwing,
        /// no-argument form below, which took a SECOND, independent `snapshot()` — two reads that
        /// were never the atomic view the file header claimed. `selectApplicationMenuBarItemByIdentity`
        /// and `SweepDriver.privacyControlOnThisSurface` now both pass their own root here instead.
        func menuBarSnapshotEntries(from root: XCUIElementSnapshot) -> [MenuBarSnapshotEntry] {
            var entries: [MenuBarSnapshotEntry] = []
            walkMenuBarItems(root) { node in
                let title = node.renderedText
                if !title.isEmpty, !entries.contains(where: { $0.title == title }) {
                    let firstChild = node.children.first?.children.first?.renderedText ?? ""
                    entries.append(MenuBarSnapshotEntry(title: title, firstChildTitle: firstChild))
                }
            }
            return entries
        }

        /// The one-line convenience for a caller that has not already taken a snapshot: takes the
        /// ONE `snapshot()` this file's header claims, then forwards to `menuBarSnapshotEntries(from:)`
        /// above. A caller that already holds a root — every call site in this codebase, today —
        /// must call the `from:` overload directly instead; calling this one AS WELL would be the
        /// second, independent snapshot R1-IN-01 existed to stop.
        func menuBarSnapshotEntries() throws -> [MenuBarSnapshotEntry] {
            menuBarSnapshotEntries(from: try snapshot())
        }

        /// EVERY top-level menu-bar item's title, in document order, walked over a root ALREADY
        /// TAKEN by the caller — the same walk `menuBarSnapshotEntries(from:)` above uses, but with
        /// NO deduplication.
        ///
        /// IT EXISTS BECAUSE A UNIQUENESS ASSERTION CANNOT BE MADE OVER A POPULATION THAT WAS
        /// ALREADY MADE UNIQUE (R1-IN-02, unreachable until 08.6-02). `SweepDriver.swift`'s step
        /// 15 asserts a live menu-bar title appears EXACTLY once; counting over
        /// `menuBarSnapshotEntries(from:)`'s deduped titles means the count can only ever be 0 or
        /// 1 — the `> 1` half of "exactly 1" was structurally unreachable, because the dedup guard
        /// above collapses two same-titled items into one before the count ever runs. This reader
        /// keeps every title, duplicates included, so that half can fail. Display-list readers
        /// keep using `menuBarSnapshotEntries(from:)`; this one is for readers that count.
        ///
        /// TAKES NO SNAPSHOT ITSELF, AND HAS NO THROWING NO-ARGUMENT TWIN (R1-IN-01). Every caller
        /// of this reader already holds a root taken for another read on the same invocation
        /// (`SweepDriver.privacyControlOnThisSurface` reads `expected`, `raw` and `deduped` from
        /// one snapshot); a second convenience that took its own would reintroduce the defect this
        /// function's sibling above was just fixed to stop.
        func menuBarSnapshotTitles(from root: XCUIElementSnapshot) -> [String] {
            var titles: [String] = []
            walkMenuBarItems(root) { node in
                let title = node.renderedText
                if !title.isEmpty {
                    titles.append(title)
                }
            }
            return titles
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

    /// The direct items of a top-level menu-bar item's OWN submenu — never the application's whole
    /// menu tree. Shared by the safety assertion and `DriveHalfTests`' attribute probe so the two
    /// cannot read different scopes again.
    func openedMenuItems(of selected: XCUIElement) -> XCUIElementQuery {
        selected.menus.firstMatch.children(matching: .menuItem)
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

        /// The exclusion message's fixed wording. `DriveHalfTests`' control matches on it, so an
        /// unrelated failure inside that control's expected-failure block stays a real failure.
        static let appleMenuExclusionWording = "opened Apple-menu content"

        /// THE SAFETY ASSERTION — see the file header. Reads only `selected`'s own submenu: its first
        /// `menu` descendant's direct `menuItem` children, bounded to 12. Internal so the standing
        /// control can aim it at a deliberately wrong selection.
        func assertOpenedMenuIsNotTheAppleMenu(
            _ selected: XCUIElement,
            selectedName: String,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            let opened = openedMenuItems(of: selected)
            let openedCount = min(opened.count, 12)
            guard openedCount > 0 else {
                XCTFail(
                    "the menu selected as \"\(selectedName)\" presented no items of its own to check — an "
                        + "empty scoped read cannot stand for \"no Apple-menu content\"",
                    file: file, line: line
                )
                return
            }
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
                "the menu selected as \"\(selectedName)\" \(Self.appleMenuExclusionWording) (About This Mac / "
                    + "Force Quit) in its own submenu",
                file: file, line: line
            )
        }

        /// A menu-bar item guaranteed to have ZERO matches, by construction: no real menu-bar
        /// item is ever given this identifier. Returned by every failure path of
        /// `selectApplicationMenuBarItemByIdentity` below instead of the bar's own first live
        /// item — which, measured (R1-IN-04), IS the application's own Apple menu, so a caller that
        /// proceeds past a failure under `continueAfterFailure = true` (as
        /// `PrivacyLinkTests.testOnePrivacyControlOnEverySurface` does, deliberately) previously
        /// went on to read the Apple menu's own contents, and every follow-on failure message
        /// named the wrong menu. The identifier is a generic literal, naming no view and no type
        /// of this application (standing rule 16).
        private func noSelectionSentinel(on app: XCUIApplication) -> XCUIElement {
            app.menuBarItems.matching(identifier: "__no_selection__").firstMatch
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
        /// returns the sentinel defined above — an element that structurally cannot exist, a
        /// mechanical necessity of the non-optional return type, not a second selection route; the
        /// failure above has already named the defect. It previously returned the bar's own first
        /// live item, which IS the Apple menu (R1-IN-04); that made every follow-on failure under
        /// `continueAfterFailure = true` misdescribe the Apple menu as the selection. The sentinel
        /// makes that misattribution structurally impossible.
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
                entries = app.menuBarSnapshotEntries(from: root)
            } catch {
                XCTFail("could not read the menu bar's accessibility snapshot: \(error)", file: file, line: line)
                return noSelectionSentinel(on: app)
            }

            let expected = resolvedApplicationName(applicationRenderedText: applicationRenderedText)
            recordMenuBarEnumeration(entries, expected: expected)

            guard !expected.value.isEmpty else {
                XCTFail(
                    "app element rendered no name; refusing to infer it from menu position — enumerated: "
                        + "\(entries.map(\.title).joined(separator: " | "))",
                    file: file, line: line
                )
                return noSelectionSentinel(on: app)
            }

            let live = app.menuBarItems
            let liveCount = live.count
            for index in 0 ..< liveCount {
                let candidate = live.element(boundBy: index)
                if candidate.renderedText == expected.value {
                    candidate.click()
                    assertOpenedMenuIsNotTheAppleMenu(
                        candidate, selectedName: expected.value, file: file, line: line
                    )
                    return candidate
                }
            }

            XCTFail(
                "no menu-bar item's title matches the resolved app name \"\(expected.value)\" (source: "
                    + "\(expected.source)) — enumerated: \(entries.map(\.title).joined(separator: " | "))",
                file: file, line: line
            )
            return noSelectionSentinel(on: app)
        }
    }
#endif
