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

        // SELECTED BY IDENTITY, NOT POSITION — bar order is an assumption, and an identity read is
        // not. (Run 34973317967's "index 1 is the Apple menu" reading came from an app-wide menu-item
        // query and is withdrawn, UL-095; run 34978692666 enumerated index 1 as the application's menu.) See
        // `app/UITestSupport/AppMenuIdentity.swift`, the one shared helper this file and
        // `PrivacyLinkTests.swift` both call.
        let appMenu = selectApplicationMenuBarItemByIdentity(on: robot.app)

        // THE SELECTED MENU'S OWN ITEMS, NOT THE APPLICATION'S: `robot.app.descendants(matching:
        // .menuItem)` read the whole bar, Apple menu first, and produced plan 07's "wrong menu"
        // reading (run 34978692666). Plan 08.5-11's IN-04 uses only this scoped population.
        let items = openedMenuItems(of: appMenu)
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

    /// THE STANDING RED HALF of `AppMenuIdentity.swift`'s safety assertion. Opens bar item 0 — the
    /// Apple menu, its title recorded rather than assumed — and aims the assertion at it. STRICT, and
    /// matched on the exclusion's own wording: the case passes only if that exact message fires, so
    /// an empty read, a click failure or anything else inside the block stays a real failure.
    func testAppleMenuExclusionFiresOnTheAppleMenu() {
        let robot = TestRobot(app: XCUIApplication())
        robot.register(with: self)
        robot.launch(args: ["UI_TESTING"])

        let wrong = robot.app.menuBarItems.element(boundBy: 0)
        let title = wrong.renderedText
        let attachment = XCTAttachment(string: "wrong_selection index=0 title=\"\(title)\"")
        attachment.name = "apple-menu-control-selection"
        attachment.lifetime = .keepAlways
        add(attachment)
        driveHalfRecord("apple_menu_control index=0 title=\"\(title)\"")

        wrong.click()
        let options = XCTExpectedFailure.Options()
        options.issueMatcher = { issue in
            issue.compactDescription.contains(Self.appleMenuExclusionWording)
        }
        XCTExpectFailure("bar item 0 is the Apple menu, so the exclusion must fire", options: options) {
            assertOpenedMenuIsNotTheAppleMenu(wrong, selectedName: "menu bar index 0 (\(title))")
        }
        robot.app.typeKey(.escape, modifierFlags: [])
    }

    /// R1-IN-04'S CONTROL, REPAIRED. THE PREVIOUS VERSION WAS VACUOUS FOR TWO INDEPENDENT
    /// REASONS, BOTH READ OUT OF AN XCRESULT RATHER THAN ARGUED (B-05).
    ///
    /// 1. IT NEVER REACHED ITS OWN ASSERTIONS. `continueAfterFailure` is false in this suite, and
    ///    a failure raised inside an `XCTExpectFailure` block unwinds the test method AT the
    ///    failure — so the record and both `XCTAssert`s that followed the block were dead code.
    ///    `menu_selector_failure_return=` is absent from BOTH the phase-branch bundle (run
    ///    35061521778) and the planted-defect bundle (run 35061527283); the case's whole verdict
    ///    was "the expected failure fired", which is decided by the selector's `XCTFail` — a line
    ///    the R1-IN-04 revert does not touch. Measured in BOTH directions on the iOS Simulator by
    ///    `evidence/08.6-07-expectfailure-unwind-harness.swift`: with the flag false the activity
    ///    after the block is ABSENT, with it true it is PRESENT.
    /// 2. AND THE TARGET APPLICATION LEFT THE ASSERTION UNDISCRIMINATING EVEN IF REACHED. It drove
    ///    the failure against an `LSUIElement` with no menu bar at all — its own
    ///    `menu-bar-enumeration` attachment reads `resolved_name="Dock"` with ZERO enumerated
    ///    rows. With no menu-bar items the pre-fix `menuBarItems.firstMatch` and the fix's
    ///    sentinel are BOTH non-existent, so `exists` is false in either world. The old doc
    ///    comment's "the reverted code returns the bar's own first live item (the Apple menu)" was
    ///    reasoning about THIS app's bar while the code queried a different application's.
    ///
    /// WHAT DISCRIMINATES NOW, NAMED EXACTLY: `returned.exists`, taken against the APP UNDER TEST,
    /// whose live bar CI measured at 7 items (`Apple | ShipkitPipes | File | Edit | View | Window
    /// | Help`). The fixed code returns an element matching an identifier no item carries, so
    /// `exists == false`. The reverted code returns `menuBarItems.firstMatch`, which on this bar
    /// IS the Apple menu, so `exists == true`. One boolean over a non-empty population — and no
    /// attribute read on a possibly-absent element, whose behaviour this phase has not measured.
    ///
    /// AND NON-ARRIVAL IS ITSELF A FAILURE (L-10). A control that cannot separate "the defect is
    /// present" from "the test stopped before the assertion" carries the old weakness in a new
    /// shape. The teardown block below fails the case when the assertions were never reached, and
    /// the live count is recorded beside the verdict so an empty bar — the state that made the
    /// previous version vacuous — shows up as a value instead of as a pass.
    func testFailedMenuSelectionReturnsAnElementThatCannotExist() {
        // POINT 1 ABOVE, UNDONE DELIBERATELY. The suite default is false; this case needs the
        // lines after the expected-failure block to execute, because they ARE the case.
        continueAfterFailure = true

        var reachedTheAssertions = false
        addTeardownBlock {
            XCTAssertTrue(
                reachedTheAssertions,
                "this case never reached its assertions — the expected failure unwound the test "
                    + "first, so it measured nothing at all about what the failure path returned"
            )
        }

        let robot = TestRobot(app: XCUIApplication())
        robot.register(with: self)
        robot.launch(args: ["UI_TESTING"])

        // A name the live bar cannot carry, supplied to the selector rather than planted in the
        // app: the subject here is the failure path's RETURN VALUE, not name resolution.
        let unmatchableName = "no-menu-bar-item-carries-this-name-\(UUID().uuidString)"

        let options = XCTExpectedFailure.Options()
        options.issueMatcher = { issue in
            issue.compactDescription.contains("no menu-bar item's title matches")
        }
        var returned: XCUIElement?
        XCTExpectFailure(
            "the expected name is unmatchable by construction, so the identity search must fail by name",
            options: options
        ) {
            returned = selectApplicationMenuBarItemByIdentity(on: robot.app, matchingName: unmatchableName)
        }

        let live = robot.app.menuBarItems.count
        let sentinels = robot.app.menuBarItems
            .matching(identifier: XCTestCase.noSelectionSentinelIdentifier).count
        let returnedExists = returned?.exists
        let existsText = returnedExists.map { $0 ? "true" : "false" } ?? "no-return"
        reachedTheAssertions = true
        driveHalfRecord(
            "menu_selector_failure_return exists=\(existsText) live_menu_bar_items=\(live) "
                + "sentinel_matching_items=\(sentinels) reached=yes"
        )

        XCTAssertGreaterThan(
            live, 0,
            "this case needs a POPULATED menu bar to discriminate: with zero live items the fix's "
                + "sentinel and the defect's firstMatch are both non-existent and `exists` proves "
                + "nothing — that is exactly how this control was vacuous before"
        )
        guard let returnedExists else {
            XCTFail("the selector returned nothing to inspect, so the failure path was not observed")
            return
        }
        XCTAssertFalse(
            returnedExists,
            "a failed selection returned an element that EXISTS — with \(live) live menu-bar "
                + "item(s) present, the failure path handed back a real one (the bar's own first "
                + "item, which is the Apple menu) instead of an element that cannot exist"
        )
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
