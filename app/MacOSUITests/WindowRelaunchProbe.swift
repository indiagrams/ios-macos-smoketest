import XCTest

// TEMPORARY DIAGNOSTIC, ROUND 2 — DELETE BEFORE MERGE. Not a gate: every method ends in a deliberate
// `XCTFail`, because an assertion message is the only channel that reaches the CI log (06-01).
//
// ROUND 1 (run 34731024041) showed the relaunch is a VICTIM: after the sweep's light pass, EVERY later
// launch in the runner session presents `windows=0`, first launches included, `activate()` or not. So
// the light pass leaves something behind that outlives the process. This round reads that state and
// tests the leading candidate, AppKit's default window restoration:
//
//   UIStateBeforeSweep  sorts after StepEditTests and before VisibleStringSweep — the state while healthy
//   A  dump, no launch — the same state right after the sweep poisoned the session
//   B  the PASSING suites' launch shape    fails => the poison does not depend on how the app is launched
//   C  the sweep's shape + ApplePersistenceIgnoreState   presents a window => restored window state
//
// B runs before C on purpose: a launch that presents a window rewrites the saved state on exit.

private let bundleID = "com.indiagram.shipkitpipes.ios"

/// Both places the app's state can live: CI builds unsigned, so the sandbox entitlement may not apply.
private func persistedStateDump() -> String {
    let home = NSHomeDirectory()
    let container = "\(home)/Library/Containers/\(bundleID)/Data/Library"
    let script = """
    {
    for d in "\(home)/Library/Saved Application State" "\(container)/Saved Application State"; do
      echo "[savedState $d]"; ls -la "$d" 2>&1 | grep -iE "shipkit|denied|No such"
    done
    echo "[windows.plist]"
    for d in "\(home)/Library/Saved Application State" "\(container)/Saved Application State"; do
      find "$d" -path "*\(bundleID)*" -name windows.plist -exec plutil -p {} + 2>&1 | head -c 900
    done
    echo "[defaults keys]"
    defaults read \(bundleID) 2>&1 | grep -E '^    "|Domain|does not exist' \
      | sed -E 's/SwiftUI[.]ModifiedContent<[^=]*AppWindow/~AppWindow/' | cut -c1-120 | head -c 1600
    echo "[prefs files]"
    ls -la "\(home)/Library/Preferences/\(bundleID).plist" "\(container)/Preferences/\(bundleID).plist" 2>&1
    } 2>&1 | head -c 3500
    """
    return shell(script)
}

private func shell(_ script: String) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", script]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
        try process.run()
    } catch {
        return "run_error=\(error)"
    }
    let deadline = Date().addingTimeInterval(20)
    while process.isRunning, Date() < deadline {
        Thread.sleep(forTimeInterval: 0.1)
    }
    if process.isRunning {
        process.terminate()
        return "TIMED_OUT " + (String(data: pipe.fileHandleForReading.availableData, encoding: .utf8) ?? "")
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return (String(data: data, encoding: .utf8) ?? "undecodable").replacingOccurrences(of: "\n", with: " ¶ ")
}

@MainActor
final class UIStateBeforeSweep: XCTestCase {
    func testDumpWhileHealthy() {
        XCTFail("PROBE BEFORE state={\(persistedStateDump())}")
    }
}

@MainActor
final class WindowRelaunchProbe: XCTestCase {
    typealias Ident = AccessibilityIdentifiers
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func testADumpAfterSweep() {
        XCTFail("PROBE AFTER state={\(persistedStateDump())}")
    }

    func testBPassingSuitesLaunchShape() {
        app = XCUIApplication()
        app.launchPinned(showing: LaunchState.encodeDestination) // ShellTests.swift:136
        XCTFail("PROBE B launch={\(reading())}")
    }

    func testCIgnorePersistedState() {
        app = XCUIApplication()
        app.launchArguments = ["-UITestColorScheme", "dark", "-ApplePersistenceIgnoreState", "YES"]
        app.launchPinned(onlySurface: LaunchState.encodeDestination)
        XCTFail("PROBE C launch={\(reading())} then_state={\(persistedStateDump())}")
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
