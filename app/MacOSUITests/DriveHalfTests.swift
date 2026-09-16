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
    ///
    /// **THE ROUTE ASSERTED IS LAUNCH'S OWN, AND UNTIL 08.6-09 IT WAS NOT (R1-IN-10).** This case
    /// used to run the activation dance a SECOND time and quote that call's return value. (This
    /// sentence deliberately does not spell the method's name: the plan's own check counts call
    /// sites in this file by grep, and prose describing the removed shape must not satisfy it —
    /// the grep-gate hygiene the sibling gates in test/ already follow.) By then
    /// `launch` had already run the dance, so the app was `.runningForeground` with a window up and
    /// the second call returned `"present"` almost unconditionally — whatever launch had actually
    /// done. The failure message therefore named a route that no longer described how the window
    /// got there, and a `"new-window"` launch was indistinguishable from a `"present"` one. The
    /// route now comes from `robot.presentRoute`, which `launch` stores, and the dance runs once.
    func testRobotPresentsAWindowAndLeavesAFinalState() {
        let robot = TestRobot(app: XCUIApplication())
        robot.register(with: self)
        robot.launch(args: ["UI_TESTING"])

        let route = robot.presentRoute ?? "unrecorded"
        XCTAssertTrue(
            robot.app.windows.firstMatch.waitForExistence(timeout: 5),
            "no window present after the robot's activation dance, route=\(route)"
        )
        namedScreenshot("drive-half-launched")
    }

    /// W-02: the `File > New Window` fallback, forced rather than hoped for.
    ///
    /// **WHY THIS CASE EXISTS.** The fallback branch of `presentWindow` is currently exercised only
    /// because the hosted runner happens to be slow enough that no window has appeared by the time
    /// the first `waitForExistence` expires (run 34984109925). That is the runner's weather, not a
    /// property of this suite: a faster runner image would take the `"present"` route every time and
    /// the fallback would stop being covered WITH NO SIGNAL AT ALL — the branch would simply never
    /// run again and every cell would stay green. This case removes the dependency on timing by
    /// closing every window first, so `"new-window"` is the only route that can succeed.
    ///
    /// **THE PRECONDITIONS ARE ASSERTED, NOT ASSUMED.** The draft this follows assumed the app stays
    /// running with zero windows after the last one closes. That is a property of
    /// `applicationShouldTerminateAfterLastWindowClosed`, not a law — an app that quits on last close
    /// would make this case pass vacuously, because a relaunched app presents a window by the
    /// `"present"` route and the assertion below would be satisfied by the wrong mechanism. Both
    /// preconditions are therefore checked BEFORE the dance, and fail by name if they do not hold.
    ///
    /// **THE CLOSE LOOP IS BOUNDED.** A `while` over a live window count spins forever against a
    /// window that refuses to close (a modal, a sheet, a save prompt); the bound turns that into a
    /// named failure instead of a job timeout with no verdict.
    func testNewWindowFallbackRunsWhenNoWindowIsPresent() {
        let robot = TestRobot(app: XCUIApplication())
        robot.register(with: self)
        robot.launch(args: ["UI_TESTING"])

        XCTAssertTrue(
            robot.app.windows.firstMatch.waitForExistence(timeout: 5),
            "launch produced no window at all, so there is nothing to close and this case cannot "
                + "reach its subject (route=\(robot.presentRoute ?? "unrecorded"))"
        )

        // Bounded deliberately — see the doc comment. Twelve is well above any window count this
        // app produces and still terminates against one that will not close.
        let closeAttemptLimit = 12
        var attempts = 0
        while robot.app.windows.count > 0, attempts < closeAttemptLimit {
            robot.app.typeKey("w", modifierFlags: .command)
            attempts += 1
            _ = robot.app.windows.firstMatch.waitForNonExistence(timeout: 1)
        }
        driveHalfRecord("drive_half_fallback_close_attempts=\(attempts)")

        XCTAssertEqual(
            robot.app.windows.count, 0,
            "\(robot.app.windows.count) window(s) still open after \(attempts) close attempt(s); the "
                + "fallback route cannot be forced while a window remains, so this case would have "
                + "measured the \"present\" path instead"
        )
        XCTAssertEqual(
            robot.app.state, .runningForeground,
            "the app is \(robot.app.state.rawValue) rather than runningForeground after closing every "
                + "window, so it terminates on last close and this case would pass by relaunching "
                + "rather than by taking the fallback — assert the precondition, do not assume it"
        )

        let route = robot.app.presentWindow()
        driveHalfRecord("drive_half_forced_fallback_route=\(route)")
        XCTAssertEqual(
            route, "new-window",
            "with zero windows open the dance returned \"\(route)\", not \"new-window\"; the "
                + "File > New Window fallback did not run, so the branch this case exists to cover "
                + "was not exercised"
        )
        XCTAssertTrue(
            robot.app.windows.firstMatch.waitForExistence(timeout: 5),
            "the fallback ran but produced no window (route=\(route))"
        )
        namedScreenshot("drive-half-fallback")
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

    /// G-14's MEASUREMENT, AND DELIBERATELY NOT ITS ASSERTION.
    ///
    /// **WHAT IS UNKNOWN.** `08-REVIEW-FIX.md` § WR-08 records that nothing verifies the app menu
    /// has actually CLOSED before the macOS capture runs, and that no assertion was added there —
    /// because whether AppKit keeps `AXMenuItem` children in the accessibility tree once a menu is
    /// closed **has never been measured in this repository**. Both outcomes are plausible: the
    /// children may vanish with the menu, or the menu element may persist with its population
    /// intact and merely stop being displayed.
    ///
    /// **WHY AN ASSERTION HERE WOULD BE A MISTAKE RATHER THAN A RISK.** If the children persist,
    /// an assertion that the count drops to zero after Escape is PERMANENTLY RED — and this case
    /// runs in the macOS cell alongside the capture suite, so it would refuse every macOS tile for
    /// a property nobody had checked. Writing the assertion first is the exact mistake
    /// `08-REVIEW-FIX.md` declined to make at Phase 8's close-out, and this case exists to supply
    /// the number that decision was missing rather than to repeat it.
    ///
    /// **THIS CASE RECORDS AND ASSERTS NOTHING ABOUT THE COUNT.** It asserts only that it reached
    /// its own subject — an unpopulated menu would make the measurement meaningless, and a
    /// measurement that cannot tell "zero children after Escape" from "no menu was ever open" is
    /// not a measurement (the B-05 lesson, one plan old).
    ///
    /// **PLAN 08.6-11 CONVERTS THIS INTO AN ASSERTION**, against the number this case records. Naming
    /// that plan here is not decoration: an assertion-free case with no named successor is how
    /// `testUnconditionalActivateCost` became a permanent resident of the required cells, removed
    /// directly below this one. This case has a named successor and an expiry.
    ///
    /// **IT DOES NOT NEED THE CAPTURE WINDOW SIZE.** The measurement runs on the 1024x768 hosted
    /// runner, which is the whole reason it lives here and not in the capture suite — that suite
    /// refuses on exactly that display (D-154, D-155), so a measurement placed there would never
    /// run on the machine that has to produce it.
    func testMenuItemsAfterEscapeMeasurement() {
        let robot = TestRobot(app: XCUIApplication())
        robot.register(with: self)
        robot.launch(args: ["UI_TESTING"])

        let appMenu = selectApplicationMenuBarItemByIdentity(on: robot.app)
        let itemsBefore = openedMenuItems(of: appMenu).count

        robot.app.typeKey(.escape, modifierFlags: [])
        // A bounded settle, not a verdict: Escape is asynchronous and this measurement must not
        // read the tree mid-dismissal. Nothing here waits FOR a particular outcome, because the
        // outcome is what is being measured.
        _ = openedMenuItems(of: appMenu).firstMatch.waitForNonExistence(timeout: 2)

        let itemsAfter = openedMenuItems(of: appMenu).count
        let menuExistsAfter = appMenu.exists
        driveHalfRecord(
            "menu_items_after_escape=\(itemsAfter) menu_items_before_escape=\(itemsBefore) "
                + "menu_exists_after_escape=\(menuExistsAfter)"
        )

        let attachment = XCTAttachment(
            string: "menu_items_before_escape=\(itemsBefore)\n"
                + "menu_items_after_escape=\(itemsAfter)\n"
                + "menu_exists_after_escape=\(menuExistsAfter)\n"
        )
        attachment.name = "g14-menu-after-escape"
        attachment.lifetime = .keepAlways
        add(attachment)

        // THE ONLY ASSERTION, AND IT IS ABOUT THIS CASE AND NOT ABOUT G-14: the menu was open
        // before Escape. Without it, a run where the menu never opened would record
        // `menu_items_after_escape=0` and look exactly like the outcome G-14 hopes for.
        XCTAssertGreaterThan(
            itemsBefore, 0,
            "the application menu presented no items BEFORE Escape, so this run measured nothing: "
                + "a zero after-count here would be indistinguishable from a menu that closed, "
                + "which is the one thing this measurement must be able to tell apart"
        )
    }

    // REMOVED 2026-09-16 BY PLAN 08.6-09: `testUnconditionalActivateCost` (R1-IN-07, R1-RISK-4).
    //
    // A DELETION THAT ERASES THE REASON THE CODE EXISTED IS HOW THE NEXT READER RE-ADDS IT, so the
    // record stays here rather than only in a commit message nobody greps.
    //
    // WHAT IT MEASURED: the wall-clock cost of an UNCONDITIONAL `app.activate()` (T-08.5-11),
    // recorded as `drive_half_unconditional_activate_seconds`.
    //
    // WHAT IT RECORDED: 0.008880972862243652 seconds.
    //
    // THE DECISION IT FED, AND WHERE THAT DECISION LIVES: whether `ScreenshotDriver`'s own
    // unconditional activate had to be routed through `presentWindow(within:)` before the D-137
    // capture skip could be lifted. Taken in Phase 8.5 plan 08 and recorded as
    // `RESULT decision=screenshotdriver-reroute taken=no evidence=…` in
    // `.planning/phases/08.5-ui-automation-drive-half/evidence/08.5-08-skip-measurement.txt`.
    // Eight milliseconds is three orders of magnitude below the 30-second threshold that would
    // have forced the reroute, so the question is settled and the probe has no remaining consumer.
    //
    // WHY IT HAD TO GO RATHER THAN STAY: it carried NO ASSERTION AT ALL, and its
    // `XCTExpectFailure` was declared NON-STRICT — an expected failure that does not require the
    // failure to occur. (Spelled in prose, because the plan's own check counts the strict-waiver
    // option's literal name in this file and this description of the removed shape must not
    // satisfy it; the same grep-gate hygiene the gates in test/ follow.) Such a case cannot go red
    // for any reason: not if activate() breaks, not if
    // the app never launches, not if the measurement is absurd. And it ran in the REQUIRED
    // `app (macOS)` cells on every pull request (R1-RISK-4), because pr.yml's macOS step runs the
    // FULL App-macOS scheme with no `-only-testing` (pr.yml:315) and the scheme's Test action
    // includes AppMacOSUITests (app/project.yml:377-381, app/Project.swift:326-331) — so every
    // contributor paid its launch on every PR for a number that was already decided.
    //
    // A green that cannot become a red is the exact shape this phase exists to remove. Keeping it
    // behind a flag was the alternative the review offered; it was declined because a flag would
    // preserve a case whose verdict is meaningless rather than retire a question that is answered.
}
