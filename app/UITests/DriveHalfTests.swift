import XCTest

// DRIVE-HALF SELF-TEST, iOS TWIN. TESTS THE ROBOT, NOT ANY SCREEN THIS APP OWNS (D-142a).
//
// The macOS twin (`app/MacOSUITests/DriveHalfTests.swift`) carries the window-activation dance and
// the menu-item measurement, both macOS-only concepts. On iOS the robot's only job is to launch
// and leave a `final-state` attachment, so this file has one test. Asserts nothing about this
// app's own encode/hash/timestamp/pipeline surfaces — no accessibility-identifier constant and
// no view name appears below.
//
// SWIFT 5.9 / `SWIFT_STRICT_CONCURRENCY: minimal`, matching both UI-test targets.

@MainActor
final class DriveHalfTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Criterion 1: the robot launches the app to the foreground, and `register(with:)` leaves a
    /// `final-state` attachment at teardown.
    func testRobotLaunchesForegroundAndLeavesAFinalState() {
        let robot = TestRobot(app: XCUIApplication())
        robot.register(with: self)
        robot.launch(args: ["UI_TESTING"])

        XCTAssertTrue(
            robot.app.wait(for: .runningForeground, timeout: 10),
            "app never reached the foreground state"
        )
        namedScreenshot("drive-half-launched")
    }
}
