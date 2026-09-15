import XCTest

// DRIVE-HALF SELF-TESTS, macOS TWIN. TESTS THE ROBOT, NOT ANY SCREEN THIS APP OWNS (D-142a).
//
// ROADMAP criterion 1 asks for the pieces to exist AND execute. Every assertion in this file is
// about `TestRobot` and `XCUIApplication.presentWindow(within:)` — this app's own encode/hash/
// timestamp/pipeline surfaces are explicitly out of scope here (D-142a is a boundary, not an
// oversight; app-screen robots are separate, future work). No accessibility-identifier constant
// and no view name appears below.
//
// `testMenuItemAttributeReadback` IS A MEASUREMENT, NOT A VERDICT. `08-GAPS.md`'s review-closeout
// `IN-04` and `Open decision 5` name a live contradiction in `app/UITestSupport/ElementText.swift`:
// one paragraph says a macOS menu item's text lands in `AXTitle` alone (measured, `renderedText`'s
// third fallback), another says `.label` is built from AXDescription falling back to AXTitle. Only
// a macOS run settles which is live for a real running menu — this job is the first one that can
// (criterion 6 cross-reference). The probe's only ASSERTION is that the population it read is
// non-empty; it records every attribute for every item and leaves the reading to plan 08.5-11.
//
// SWIFT 5.9 / `SWIFT_STRICT_CONCURRENCY: minimal`, matching both UI-test targets.

@MainActor
final class DriveHalfTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Criterion 1: the robot presents a window, and `register(with:)` leaves a `final-state`
    /// attachment at teardown. Asserts only that a window exists — nothing about what is in it.
    func testRobotPresentsAWindowAndLeavesAFinalState() {
        let robot = TestRobot(app: XCUIApplication())
        robot.register(with: self)
        robot.launch(args: ["UI_TESTING"])

        let route = robot.app.presentWindow()
        XCTAssertTrue(
            robot.app.windows.firstMatch.waitForExistence(timeout: 5),
            "no window present after the robot's activation dance, route=\(route)"
        )
        namedScreenshot("drive-half-launched")
    }

    /// See the file header's "IS A MEASUREMENT, NOT A VERDICT" paragraph. Bounded to the first 12
    /// items so a future menu with a long population cannot make this probe slow rather than wide.
    func testMenuItemAttributeReadback() {
        let robot = TestRobot(app: XCUIApplication())
        robot.register(with: self)
        robot.launch(args: ["UI_TESTING"])

        // SELECTED BY IDENTITY, NOT POSITION — `menuBarItems.element(boundBy: 1)` recorded the
        // Apple menu's own contents on run 34973317967 (evidence/08.5-07-ci-readback.txt, and
        // this very probe's own prior measurement of that run). See
        // `app/UITestSupport/AppMenuIdentity.swift`, the one shared helper this file and
        // `PrivacyLinkTests.swift` both call.
        selectApplicationMenuBarItemByIdentity(on: robot.app)

        let items = robot.app.descendants(matching: .menuItem)
        let population = min(items.count, 12)
        var lines: [String] = []
        for index in 0 ..< population {
            let item = items.element(boundBy: index)
            let line = "menu_item index=\(index) type=\(item.elementType.rawValue) "
                + "label=\"\(item.label)\" value=\"\((item.value as? String) ?? "")\" "
                + "title=\"\(item.title)\" rendered=\"\(item.renderedText)\""
            driveHalfRecord(line)
            lines.append(line)
        }
        robot.app.typeKey(.escape, modifierFlags: [])

        let attachment = XCTAttachment(string: lines.joined(separator: "\n"))
        attachment.name = "menu-item-attributes"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertGreaterThan(population, 0, "the application menu presented no items to measure")
    }

    /// Bounded probe (T-08.5-11): the wall-clock cost of an UNCONDITIONAL `app.activate()`,
    /// wrapped in a non-strict `XCTExpectFailure` since `ScreenshotContract.swift:80-90` records a
    /// failure for exactly this call on a headless runner. Plan 08.5-08 reads the measured seconds
    /// back to decide whether `ScreenshotDriver`'s own unconditional activate must be routed
    /// through `presentWindow(within:)` before its capture skip (D-137) is lifted.
    func testUnconditionalActivateCost() {
        let robot = TestRobot(app: XCUIApplication())
        robot.register(with: self)
        robot.launch(args: ["UI_TESTING"])

        let start = Date()
        XCTExpectFailure(
            "unconditional activate() may record \"Failed to activate application\" on a "
                + "headless runner (ScreenshotContract.swift:80-90) — this probe measures cost, "
                + "not correctness",
            options: .nonStrict()
        ) {
            robot.app.activate()
        }
        let elapsed = Date().timeIntervalSince(start)
        driveHalfRecord("drive_half_unconditional_activate_seconds=\(elapsed)")
    }
}
