import XCTest

/// TEMPORARY DIAGNOSTIC — DELETE BEFORE MERGE. Not a gate: every method ends in a deliberate
/// `XCTFail` because an assertion message is the only channel that reaches the CI log (06-01).
///
/// THE QUESTION. `VisibleStringSweep` fails 3/3 on this branch at its DARK relaunch with the app
/// foreground, its menu bar built and `windows=0` (debug E14, E16), while the same loop passed 4/4 on
/// `main`. Its first launch works and its light walk completes. So something that now happens BEFORE
/// the relaunch breaks it. Each method below does the sweep's exact launch, ONE candidate action, the
/// sweep's exact terminate and relaunch, and reports what the relaunch presented:
///
///   A  nothing between the launches      fails => the branch's app + this relaunch shape, not the walk
///   B  step 15's two read-only queries   fails alone => step 15
///   C  one whole-app `snapshot()`        fails alone => harvesting the menu bar, new item and all
///   D  as A, plus `activate()` on relaunch — only meaningful if A fails
///
/// Named to sort AFTER `VisibleStringSweep`, so it cannot disturb the thirteen suites that serve as
/// controls in the same run.
@MainActor
final class WindowRelaunchProbe: XCTestCase {
    typealias Ident = AccessibilityIdentifiers
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func testAWalklessRelaunch() {
        probe("A") {}
    }

    func testBStepFifteenQueriesThenRelaunch() {
        probe("B") {
            _ = self.app.menuBarItems.count
            _ = self.app.descendants(matching: .any).matching(identifier: Ident.Shell.privacyPolicy).count
        }
    }

    func testCWholeAppSnapshotThenRelaunch() {
        probe("C") {
            _ = try? self.app.snapshot()
        }
    }

    func testDWalklessRelaunchWithActivate() {
        probe("D", activateOnRelaunch: true) {}
    }

    private func probe(_ name: String, activateOnRelaunch: Bool = false, between action: () -> Void) {
        launch("light")
        let first = reading()
        action()
        app.terminate()

        app = XCUIApplication()
        launch("dark")
        if activateOnRelaunch {
            app.activate()
        }
        let second = reading()
        XCTFail("PROBE \(name) first={\(first)} relaunch={\(second)}")
    }

    /// The sweep's launch, byte for byte: `VisibleStringSweep.swift:110-111`.
    private func launch(_ scheme: String) {
        if app == nil {
            app = XCUIApplication()
        }
        app.launchArguments = ["-UITestColorScheme", scheme]
        app.launchPinned(onlySurface: LaunchState.encodeDestination)
    }

    /// The sweep's first wait, then the same numbers `awaitFirstDestination()` reports.
    private func reading() -> String {
        let start = Date()
        let found = app.descendants(matching: .any).matching(identifier: Ident.Shell.sidebarEncode)
            .firstMatch.waitForExistence(timeout: 30)
        let waited = String(format: "%.1f", Date().timeIntervalSince(start))
        return "found=\(found) waited=\(waited)s app_state=\(app.state.rawValue) windows=\(app.windows.count) "
            + "menu_bar_items=\(app.menuBarItems.count)"
    }
}
