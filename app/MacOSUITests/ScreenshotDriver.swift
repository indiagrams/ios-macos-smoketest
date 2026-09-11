import XCTest

// THE DRIVING HALF of `AppStoreScreenshotTests` — launching, filling, appending a step, and the
// framing scroll. All of it by IDENTIFIER and never by visible text.
//
// AN EXTENSION IN A SECOND FILE, the shape `app/MacOSUITests/SweepDriver.swift` already uses for
// `VisibleStringSweep` and for the same reason: `swiftlint --strict` promotes the 400-line file
// WARNING to an error (UL-056), and the alternative was deleting measurements. `ScreenshotContract.swift`
// carries the contract; this file carries what drives it; the class file carries the shots and the gate.
//
// C-25: Swift 5.9 / `SWIFT_STRICT_CONCURRENCY: minimal`, like every file in this target.

extension AppStoreScreenshotTests {
    /// All five settings keys; surface and encode format chosen by the caller.
    static func pinning(_ surface: String, format: String) -> [String] {
        [
            LaunchState.selectionKey, surface,
            LaunchState.encodeFormatKey, format,
            LaunchState.encodeDirectionKey, LaunchState.forwardDirection,
            LaunchState.timestampsReadAsKey, LaunchState.epochReadAs,
            LaunchState.timestampsTimeZoneKey, LaunchState.fixedTimeZone
        ]
    }

    /// A fresh application, pinned, in the requested appearance, at the requested POINT size.
    /// `activate()` so the window comes to front: without it the window may launch behind others
    /// and XCUITest's window queries return nothing on a real Mac with other GUI apps running.
    func launch(_ pinning: [String], _ appearance: String) {
        app = XCUIApplication()
        app.launchArguments += ["UI_TESTING"]
        app.launchArguments += ["-UITestColorScheme", appearance]
        app.launchArguments += ["-UITestWindowSize", Self.captureWindowSize]
        app.launchArguments += pinning
        app.launch()
        app.activate()

        // The pre-existing File → New Window fallback, KEPT UNCHANGED AND NOT EXTENDED: it is the
        // one by-visible-text menu query in this target and `evidence/08-11-controls.rb` counts them.
        if !app.windows.firstMatch.waitForExistence(timeout: 8) {
            let fileMenu = app.menuBarItems["File"]
            if fileMenu.waitForExistence(timeout: 3) {
                fileMenu.click()
                let newWindow = app.menuItems["New Window"]
                if newWindow.waitForExistence(timeout: 3) {
                    newWindow.click()
                }
            }
        }
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5), "App window must be visible")
    }

    /// Fill a surface's input from its worked-value control and hand back what the field holds.
    /// **Also the per-shot RENDER GUARD**, on THAT surface's own identifier rather than shot 01's:
    /// a window can exist before SwiftUI has drawn into it, which is how a screenshot of an empty
    /// frame gets captured and uploaded.
    @discardableResult
    func fillFromExample(_ control: String, reading field: String) -> String {
        let button = element(control)
        XCTAssertTrue(button.waitForExistence(timeout: 30), "no worked-value control carries \(control)")
        XCTAssertTrue(element(field).waitForExistence(timeout: 30),
                      "the window appeared but nothing carries \(field) — SwiftUI has not drawn this surface")
        button.click()
        let text = (element(field).value as? String) ?? ""
        XCTAssertFalse(text.isEmpty, "the worked-value control left \(field) empty, so every value below this "
            + "would be about the empty string")
        return text
    }

    /// Open an add-step control, choose the item at `menuIndex`, and prove the step that LANDED is
    /// the one that was asked for — see `ScreenshotContract.swift` §"the menu item is unreadable".
    func addStep(_ menuIndex: Int, _ title: String, landingAt cardIndex: Int) {
        let controls = all(AccessibilityIdentifiers.Step.addStep)
        XCTAssertTrue(controls.element(boundBy: 0).waitForExistence(timeout: 20), "no add-step control on the surface")
        controls.element(boundBy: 0).click()

        let items = all(AccessibilityIdentifiers.Step.addStepMenu)
        XCTAssertTrue(items.element(boundBy: menuIndex).waitForExistence(timeout: 20),
                      "the add-step menu presented no item at index \(menuIndex)")
        let population = items.count
        let item = items.element(boundBy: menuIndex)
        // A MEASUREMENT AND NOT AN ASSERTION, emitted whatever its value: every attribute an
        // out-of-process client can ask a macOS menu item for, so the next reader has the answer.
        record("addstep index=\(menuIndex) population=\(population) type=\(item.elementType.rawValue) "
            + "label=\"\(item.label)\" value=\"\((item.value as? String) ?? "")\" title=\"\(item.title)\"")
        XCTAssertEqual(population, Self.operationCount,
                       "the menu presented \(population) items, expected Operation.allCases.count "
                           + "= \(Self.operationCount)")
        item.click()

        let headers = all(AccessibilityIdentifiers.Step.header)
        XCTAssertTrue(headers.element(boundBy: cardIndex).waitForExistence(timeout: 20),
                      "nothing carries \(AccessibilityIdentifiers.Step.header) at card index \(cardIndex)")
        assertRendersText(headers.element(boundBy: cardIndex), title,
                          "the header of the card menu index \(menuIndex) appended — if this is another "
                              + "operation, `Operation.allCases` has been reordered and this chain is not "
                              + "the chain it says it is")
    }

    /// Brings the value span into the band the capture can show — choosing BOTH the element to
    /// scroll and the sign convention by MEASUREMENT, because guessing either produced a silent
    /// no-op that looked exactly like a scroll view with nothing to scroll.
    ///
    /// **Measured 2026-09-11, three runs, and every number here came out of one of them.**
    /// Unscrolled, in a 1440 x 900 pt window whose content band is 848 pt, the chain's three
    /// values sit at y=560.5 / 841.5 / 1122.5 — a span of 580 pt that FITS the band, offset
    /// 272.5 pt too low, with the third value 120 pt below the fold. Assertion 2 refused the shot.
    ///
    /// **`app.scrollViews` answers 2 here and `firstMatch` is the WRONG ONE.** A
    /// `NavigationSplitView` publishes the SIDEBAR's scroll view as well as the detail pane's, and
    /// a sidebar holding three rows has nothing to scroll — so `scroll(byDeltaX:deltaY:)` on it is
    /// a no-op that reports success. Four attempts across both signs moved the content by exactly
    /// 0.0 pt. The target is therefore chosen by CONTAINMENT of a value the shot is about, with
    /// every candidate's frame recorded, and the value element itself is the fallback target
    /// because a scroll-wheel event delivered inside a scroll view reaches it either way.
    ///
    /// NOTHING IS LOOSENED: a span taller than the band returns immediately and assertion 2
    /// reports it with the frames that prove it.
    func scrollValuesIntoFrame(_ sources: [ValueSource]) {
        // AN EMPTY POPULATION RETURNS, AND THE RED CONTROL IS WHY. Taking `element(boundBy: 0)`
        // of a query that matched nothing throws XCUITest's own "No matches found for Elements
        // matching predicate" — which is a failure, but an OPAQUE one, and it happens BEFORE
        // assertion 5 can say "this capture would be of a window the app has not drawn into yet".
        // The launch-state case is exactly the case assertion 5 exists for, so letting this frame
        // it would leave criterion 2's own clause unable to speak in its own words.
        guard let first = sources.first, count(first.identifier) > 0 else { return }
        let anchor = all(first.identifier).element(boundBy: 0)
        let query = app.scrollViews
        let frames = (0 ..< query.count).map { query.element(boundBy: $0).frame }
        let point = CGPoint(x: anchor.frame.midX, y: anchor.frame.midY)
        let chosen = frames.firstIndex { $0.contains(point) }
        record("scroll_target scrollviews=\(frames.count) chosen=\(chosen.map { "\($0)" } ?? "none") "
            + "frames=\(frames.map(describeRect).joined(separator: ",")) anchor=\(describeRect(anchor.frame))")

        // In order: the scroll view that CONTAINS the value, then the value itself. A wheel event
        // delivered on a descendant reaches the nearest enclosing scroll view, so the second is a
        // real alternative rather than a repeat of the first.
        let targets = [chosen.map { query.element(boundBy: $0) } ?? anchor, anchor]
        var index = 0
        var sign: CGFloat = 1

        for attempt in 0 ..< Self.scrollAttempts {
            let visible = contentBounds()
            let rects = values(sources).map(\.frame)
            guard let top = rects.map(\.minY).min(), let bottom = rects.map(\.maxY).max() else { return }
            let span = bottom - top
            guard span <= visible.height else { return }
            let delta = top - (visible.minY + (visible.height - span) / 2)
            guard abs(delta) > Self.scrollMargin else { return }

            targets[index].scroll(byDeltaX: 0, deltaY: sign * delta)
            let moved = (values(sources).map(\.frame).map(\.minY).min() ?? top) - top
            record("scroll attempt=\(attempt) target=\(index) sign=\(sign) span=\(span) delta=\(delta) "
                + "moved=\(moved) band=\(describeRect(visible))")

            // `top` was asked to FALL by `delta`. Moving the same way as the correction, or not at
            // all, means the convention or the target is the other one — try the sign first,
            // because it is the cheaper of the two to be wrong about.
            if moved == 0 || (delta > 0 && moved > 0) || (delta < 0 && moved < 0) {
                if sign > 0 {
                    sign = -1
                } else {
                    sign = 1
                    index = min(index + 1, targets.count - 1)
                }
            }
        }
    }
}
