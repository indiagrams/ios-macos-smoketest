import XCTest

// THE GENERIC ROBOT BASE: ONE ROBOT PER APPLICATION, EVERY METHOD RETURNS SELF, NO SCREEN NAMED.
//
// This file and `ElementText.swift` / `BlindReadGuards.swift` beside it are compiled into BOTH
// UI-test targets and contain no identifier, no view name, no string and no type belonging to the
// application under test. Drop the directory into any SwiftUI project, list it in the two UI-test
// targets, and it works — that property is deliberate and is asserted by a grep
// (`test/drive_half_vocabulary_test.rb`), not by intention.
//
// PORTED FROM A PRIVATE REPOSITORY'S GENERIC HALF, AND ONLY THE GENERIC HALF (D-133).
// [UP-05-sensitive: derived from a private repository, generic content only] The private source
// splits into a generic half — one robot base, launch/register/terminate/waitForElement, a
// file-level named-screenshot helper — and a domain half: two methods binding a specific product's
// launch environment and a specific product's connection-liveness check. Neither domain method,
// nor any of the six domain robots built on top of this base in that repository, is reproduced
// here — not even as a comment, since a commented-out reference is still tracked-tree text a grep
// would find. What is here is the shape ROADMAP criterion 1 names: a base, an activation dance,
// and a teardown capture.
//
// THE macOS WINDOW-ACTIVATION DANCE GENERALISES SOMETHING THIS REPOSITORY ALREADY DOES, NOT A
// FOREIGN IMPORT. `app/MacOSUITests/ScreenshotDriver.swift:32-58` already activates, waits 8 s for
// a window, and falls back to File > New Window with 3 s waits; `ScreenshotContract.swift:79-90`
// records `activate()` as LOAD-BEARING on a real Mac (a window can launch behind other GUI apps).
// `presentWindow(within:)` below is that dance, generalised onto `XCUIApplication` so any robot —
// here or in a future app-screen robot D-142(a) leaves for later work — can call it once.
// D-151(a): `activate()` is called only when the app is not already frontmost
// (`state != .runningForeground`) — the unconditional form costs roughly 60 s and a recorded
// XCTest failure on a headless runner (`ScreenshotContract.swift:80-90`), and reading the state
// first turns "was activation needed" into a MEASUREMENT the caller can read back rather than an
// assumption baked into the call. `ScreenshotDriver.swift` itself is NOT edited here — it keeps
// its own, pre-existing, unconditional dance unchanged.
//
// EVIDENCE CHANNEL: `docs/UI-TESTING-ON-BOTH-PLATFORMS.md` §7 — `print` reaches `xcodebuild`'s
// pipe on the iOS Simulator job and does NOT on the macOS job. Every value this file records goes
// through `driveHalfRecord(_:)` below, which is both a `print` and an `XCTContext.runActivity`, so
// the macOS run keeps the value in its `.xcresult` even though the log swallows it.
//
// SWIFT 5.9 / `SWIFT_STRICT_CONCURRENCY: minimal`, matching both UI-test targets. No concurrency
// of any kind is used here and no Swift 6 isolation syntax appears.

/// One line, recorded twice — see the file header's "EVIDENCE CHANNEL" paragraph. `print` alone is
/// silent on the macOS job; `XCTContext.runActivity` alone leaves the iOS Simulator log with
/// nothing to `grep` through. A free function, not a method, so the robot, the macOS-only
/// extension below, and any future call site can all reach it without an `XCTestCase` instance.
func driveHalfRecord(_ line: String) {
    print(line)
    XCTContext.runActivity(named: line) { _ in }
}

extension XCTestCase {
    /// Attach a named screenshot to the current xcresult, `.keepAlways` so it survives a passing
    /// run. Use this for a labelled moment a reader will want without hunting the automatic
    /// `final-state` capture ``TestRobot/register(with:)`` installs at teardown.
    func namedScreenshot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

#if os(macOS)
    extension XCUIApplication {
        /// The macOS window-activation dance, generalised from `ScreenshotDriver.swift` (see the file
        /// header). Returns which route produced a window — `"present"` (one was already there, or
        /// `activate()` alone surfaced it), `"new-window"` (the `File > New Window` fallback ran to
        /// completion), or `"none"` (neither did) — so a caller can put the route in its own failure
        /// message instead of a bare timeout, and so `drive_half_state_before_activate` and the route
        /// are both a MEASUREMENT a later run can read back rather than an assumption.
        @discardableResult
        func presentWindow(within timeout: TimeInterval = 8) -> String {
            let stateBefore = state
            driveHalfRecord("drive_half_state_before_activate=\(stateBefore.rawValue)")
            if stateBefore != .runningForeground {
                activate()
            }
            if windows.firstMatch.waitForExistence(timeout: timeout) {
                driveHalfRecord("drive_half_present_route=present")
                return "present"
            }
            // "File" and "New Window" are AppKit's own standard menu, not this app's (standing
            // rule 16 allows platform vocabulary) — but they are LOCALE-dependent, which is the
            // actual defect R1-IN-06 names: on a non-English runner these matches never fire and
            // this route falls through to "none" silently. `TestRobot.launch` below pins
            // `-AppleLanguages (en)` so that stays true rather than merely declared. Each "none"
            // now RECORDS WHICH LOOKUP FAILED, so a locale break is distinguishable from an app
            // that genuinely has no File menu — the half R1-IN-06 called silent.
            let fileMenu = menuBarItems["File"]
            guard fileMenu.waitForExistence(timeout: 3) else {
                driveHalfRecord("drive_half_present_route=none reason=file-menu-absent")
                return "none"
            }
            fileMenu.click()
            let newWindowItem = menuItems["New Window"]
            guard newWindowItem.waitForExistence(timeout: 3) else {
                driveHalfRecord("drive_half_present_route=none reason=new-window-item-absent")
                return "none"
            }
            newWindowItem.click()
            driveHalfRecord("drive_half_present_route=new-window")
            return "new-window"
        }
    }
#endif

/// One robot per application under test: every method returns `Self`, so a test body reads as a
/// chain of actions rather than a sequence of raw `XCUIApplication` queries. This is the GENERIC
/// base only (D-133) — a domain robot for this app's own screens is a future, separate file, not
/// an addition to this one.
class TestRobot {
    let app: XCUIApplication

    /// The route `launch(args:env:)`'s own `presentWindow()` call took — `"present"`,
    /// `"new-window"` or `"none"` — or `nil` where no dance ran.
    ///
    /// **WHY THIS EXISTS (R1-IN-10).** `launch` called `presentWindow()` and DISCARDED the result,
    /// so the only way a test could name a route was to call `presentWindow()` a SECOND time — by
    /// which point the app is already `.runningForeground` with a window up, so the second call
    /// returns `"present"` almost unconditionally and reports on itself rather than on launch. A
    /// case asserting that value was asserting that calling the dance twice works. The route launch
    /// actually took is the one worth quoting in a failure message, so `launch` keeps it here.
    ///
    /// `nil` on iOS, where `launch` runs no dance at all: an empty string would be indistinguishable
    /// from a dance that returned nothing, and this is a fact about which platform ran, not a value.
    private(set) var presentRoute: String?

    required init(app: XCUIApplication) {
        self.app = app
    }

    /// `-AppleLanguages (en)`, pinned so `presentWindow`'s macOS fallback route — which matches
    /// AppKit's own "File" and "New Window" menu items BY ENGLISH TITLE — has a runner where that
    /// match is guaranteed rather than merely assumed (R1-IN-06). A caller that passes its OWN
    /// `-AppleLanguages` argument is left alone: this only ADDS the pin when the caller has not
    /// already made its own locale choice, so a future test of a non-English locale still can.
    private static let englishLanguagePin = ["-AppleLanguages", "(en)"]

    /// Launch with the given arguments/environment, then — on macOS only — run the
    /// window-activation dance so the app has a window before the caller's first query.
    ///
    /// PINS THE ENGLISH LOCALE (R1-IN-06) UNLESS `args` ALREADY NAMES ITS OWN `-AppleLanguages`.
    /// `presentWindow`'s fallback route (below) matches AppKit's standard menu by its English
    /// title; on a non-English runner it fell through to `"none"` silently. Making the runner's
    /// language a measurement this robot controls, rather than an assumption about whoever runs
    /// it, is preferred here over merely declaring the assumption — the drive half's whole point
    /// is that the fallback route executes.
    @discardableResult
    func launch(args: [String] = [], env: [String: String] = [:]) -> Self {
        let callerPinnedItsOwnLanguage = args.contains(Self.englishLanguagePin[0])
        app.launchArguments = (callerPinnedItsOwnLanguage ? [] : Self.englishLanguagePin) + args
        app.launchEnvironment = env
        app.launch()
        #if os(macOS)
            presentRoute = app.presentWindow()
        #endif
        return self
    }

    /// Register an automatic `final-state` teardown screenshot for `testCase`. Call this BEFORE
    /// `launch(args:env:)` — the teardown block is what still runs when the test fails midway
    /// through launching, and a block added only after a failing launch never gets a chance to run.
    ///
    /// **THE APP IS CAPTURED STRONGLY, NOT WEAKLY.** Run 34973317967 measured zero `final-state`
    /// attachments across all three `DriveHalfTests` macOS cases despite every one of them calling
    /// `register(with:)` before `launch(...)` (`evidence/08.5-07-ci-readback.txt`,
    /// `evidence/08.5-07-final-state-diagnosis.txt`). Every call site holds its `TestRobot` only in
    /// a local `let robot` inside the test method, so the robot — and the `weak self` this block
    /// used to capture — is deallocated before teardown runs; the old `guard let app = self?.app`
    /// then resolved `self` to `nil` and returned silently, producing no attachment and no signal
    /// that anything had gone missing. `app` is captured BEFORE the block, by value, so the block
    /// no longer depends on the robot outliving the test method — only `testCase` stays weak, since
    /// an `XCTestCase` teardown block capturing its own test case strongly is the classic retain
    /// cycle this pattern exists to avoid.
    @discardableResult
    func register(with testCase: XCTestCase) -> Self {
        let app = app
        testCase.addTeardownBlock { [weak testCase] in
            guard let tc = testCase else { return }
            guard app.state != .notRunning else {
                // ABSENCE MADE OBSERVABLE, NOT SILENT. The old guard's bare `return` here was the
                // second defect run 34973317967 measured: "absence is indistinguishable from 'app
                // not running'" (`evidence/08.5-07-final-state-diagnosis.txt`). A named attachment
                // records which branch was taken instead of leaving a reader to guess.
                let unavailable = XCTAttachment(string: "final-state-unavailable: app state=\(app.state.rawValue)")
                unavailable.name = "final-state-unavailable"
                unavailable.lifetime = .keepAlways
                tc.add(unavailable)
                return
            }
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "final-state"
            attachment.lifetime = .keepAlways
            tc.add(attachment)
        }
        return self
    }

    /// Terminate the application under test.
    @discardableResult
    func terminate() -> Self {
        app.terminate()
        return self
    }

    /// Wait up to `timeout` for `identifier` to exist anywhere in the tree, failing the current
    /// test — at the CALL SITE, via `file`/`line` — if it never does. `BlindReadGuards.swift`'s
    /// discipline for where a failure should point: a reader looking for the assertion finds it in
    /// their own test body, not in this file.
    @discardableResult
    func waitForElement(
        _ identifier: String,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(
            element.waitForExistence(timeout: timeout),
            "Element '\(identifier)' must exist within \(timeout)s",
            file: file,
            line: line
        )
        return self
    }
}
