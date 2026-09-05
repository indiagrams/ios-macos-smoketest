import XCTest

// GAP-06-01 — THE KEYBOARD CAN BE PUT AWAY. Found by the user at Phase 6's end-of-phase human
// verification and by nothing else, which is the whole reason that checkpoint exists.
//
// The defect: `app/Shared/Views/InputArea.swift` builds its field as
// `TextField(prompt, text:, axis: .vertical)`. The vertical axis makes the field MULTILINE, so
// Return inserts a newline instead of resigning first responder — and a sweep of all of
// `app/Shared/` found zero dismissal affordances of any other kind. Once the keyboard was up it
// stayed up, over the outputs and over the tab bar.
//
// THE SWEEP RAN WITH THE KEYBOARD UP AND WORKED AROUND IT WITHOUT NOTICING. `VisibleStringSweep`
// relaunches the app to get the keyboard out of the way (`dismissKeyboard`, "keyboard_dismissed_by=
// relaunch") and exempts the keyboard window's typing-prediction strings from its population. Both
// of those are right for what that gate measures and neither says anything about whether a USER can
// put the keyboard away. This file is the assertion nobody had written.
//
// iOS ONLY, BY LOCATION. `app/UITests/` compiles into `AppUITests` (platform: iOS) alone. macOS has
// no software keyboard, the toolbar that carries the control is compiled out there, and there is
// deliberately no macOS twin of this file — a twin would be a suite that can only ever pass.
//
// C-25 BOUNDS WHAT THIS PROVES. Both UI-test targets are pinned to `SWIFT_VERSION: "5.9"` /
// `SWIFT_STRICT_CONCURRENCY: minimal` because fastlane's `SnapshotHelper.swift` predates Swift 6, so
// this file is GAP-06-01 evidence only and NEVER evidence for APP-12. Everything below is Swift 5.9.
//
// NEVER QUERY BY VISIBLE TEXT. The control is addressed by `AccessibilityIdentifiers.Input.done`,
// the constant the view attaches, and never by the word on it. `AccessibilityIdentifiers` is
// compiled into BOTH the app target and this UI-test target via an explicit `sources:` entry in
// app/project.yml and app/Project.swift — UI tests run in a separate process and cannot
// `@testable import` the app binary.
//
// `print` FROM A UI-TEST BUNDLE NEVER REACHES THE CI LOG — the bundle runs inside a runner app
// launched by `testmanagerd` and its stdout is not connected to xcodebuild's pipe, and xcbeautify
// swallows it on the iOS job as well (measured by 06-16 on both platforms). Every counter below
// therefore rides an ASSERTION MESSAGE or an `XCTContext` activity, which lands in the `.xcresult`.
//
// REACHED ITS SUBJECT FIRST, SEPARATELY. `keyboard_present=` is asserted BEFORE anything about
// dismissal, so a run that never got the keyboard up reads as a failure to reach the subject rather
// than as a statement about whether the subject works. A skip reads as a skip.

/// The user can put the software keyboard away again (GAP-06-01).
@MainActor
final class KeyboardDismissTests: XCTestCase {
    private typealias Ident = AccessibilityIdentifiers

    private var app: XCUIApplication!

    /// Typed into the field so the keyboard is up over real work, and compared again after the
    /// dismissal: putting the keyboard away must not discard what was typed.
    private static let typed = "gap0601"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - The gate

    /// Type, confirm the keyboard is PRESENT, use the Done control, confirm it is ABSENT.
    func testTheDoneControlPutsTheKeyboardAway() {
        app.launch()

        // 1 — DID IT REACH ITS SUBJECT? A run that never raised the keyboard can say nothing about
        // dismissing one, and must not be allowed to read as a pass.
        XCTAssertTrue(
            raiseKeyboard(on: Ident.Encode.input),
            "keyboard_present=no — the walk never got the software keyboard up on the Encode input, "
                + "so this run says nothing about whether it can be put away"
        )
        XCTContext.runActivity(named: "keyboard_present=yes") { _ in }

        // 2 — the control exists, and it is addressed by its constant rather than by its word.
        let done = element(Ident.Input.done)
        XCTAssertTrue(
            done.waitForExistence(timeout: 15),
            "keyboard_dismissed=unreachable — no element carries \(Ident.Input.done); the keyboard "
                + "is up and there is no control on it to put it away"
        )

        // THE OBSTRUCTION, RECORDED AND DELIBERATELY NOT ASSERTED — and the reason is a measurement
        // that cost this file an assertion. The first version of this test asserted `bar.isHittable`
        // AFTER the dismissal, on the reasoning that the covered tab bar is the user-visible harm
        // GAP-06-01 names. It was then measured on all three runtimes and `isHittable` reported
        // **true while the keyboard was still up** on 17.5, 18.6 and 26.1 alike — so that assertion
        // was true before the fix and after it, and would have passed against an app with no
        // dismissal at all. That is "a control that cannot fire", the shape this phase has now met
        // seven times, and it was deleted rather than kept for the look of it.
        //
        // What is left is the GEOMETRY, which is a fact about the platform's layout rather than
        // about this app, so it is carried out as a number on every run and asserted nowhere. Both
        // readings are emitted, the frame overlap and the hittability, so a later reader can see
        // that the two disagree and does not have to rediscover it.
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 15), "the app presents no tab bar at all")
        let overlap = app.keyboards.element.frame.intersects(bar.frame)
        XCTContext.runActivity(named: "tab_bar_covered_while_keyboard_up=\(overlap) hittable=\(bar.isHittable)") { _ in }

        // 3 — and using it puts the keyboard away. NO SCROLL GESTURE IS MADE ANYWHERE IN THIS TEST:
        // whatever dismisses the keyboard here, it is not the scroll route.
        done.tap()
        XCTAssertTrue(
            app.keyboards.element.waitForNonExistence(timeout: 15),
            "keyboard_dismissed=no — the software keyboard is still on screen after \(Ident.Input.done) was used"
        )
        XCTContext.runActivity(named: "keyboard_dismissed=yes") { _ in }

        // 4 — the dismissal did not throw the work away. Phase 6 has no destructive action at all
        // (UI-SPEC §"Copywriting Contract"), and a Done control that cleared the field would be one.
        XCTAssertEqual(
            inputValue(),
            Self.typed,
            "keyboard_dismissed=lossy — the Encode input no longer holds what was typed into it"
        )

        // 5 — and the shell still works afterwards. Not a restatement of step 3: this drives the tab
        // bar that was under the keyboard and requires the tap to actually ARRIVE somewhere, so a
        // dismissal that left the app with a stale responder or an invisible overlay fails here
        // rather than passing on the keyboard's absence alone.
        bar.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(
            element(Ident.Shell.tabHashing).waitForExistence(timeout: 15),
            "keyboard_dismissed=stuck — the keyboard is gone but tab item 1 no longer reaches "
                + Ident.Shell.tabHashing
        )
        XCTContext.runActivity(named: "shell_usable_after_dismiss=yes") { _ in }
    }

    // MARK: - Driving, all of it by identifier

    /// The first element carrying `identifier`, whatever kind of element it is.
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The Encode surface's input, as the accessibility tree reports it.
    private func inputValue() -> String {
        (element(Ident.Encode.input).value as? String) ?? ""
    }

    /// Taps the field until the software keyboard is up, then types. Returns whether the keyboard is
    /// up AFTER typing — which is the state this suite is about.
    ///
    /// The retry loop is 06-16's, and it is there for a measured reason: a tap that lands before
    /// SwiftUI has installed the responder leaves `typeText` with nowhere to send its events
    /// ("Neither element nor any descendant has keyboard focus"). That is a flake, not a defect, so
    /// it is waited out rather than slept through.
    private func raiseKeyboard(on identifier: String) -> Bool {
        let field = element(identifier)
        XCTAssertTrue(
            field.waitForExistence(timeout: 30),
            "the app did not present its input field — no element carries \(identifier)"
        )
        for _ in 0 ..< 3 {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            if app.keyboards.element.exists || app.keyboards.element.waitForExistence(timeout: 5) {
                break
            }
        }
        guard app.keyboards.element.exists else {
            return false
        }
        field.typeText(Self.typed)
        return app.keyboards.element.exists
    }
}
