import XCTest

// THE macOS TWIN OF `app/UITests/ShellTests.swift`, DELIBERATELY THE SAME CLASS
// NAME so it is selectable as `-only-testing:AppMacOSUITests/ShellTests` beside
// the iOS suite's `-only-testing:AppUITests/ShellTests`, which is the artifact
// 06-VALIDATION.md's APP-10 row names. Two files rather than one shared one,
// because the two platforms have two different containers by D-11 and the
// destinations are therefore two different sets of elements.
//
// `AccessibilityIdentifiers` (app/Shared/AccessibilityIdentifiers.swift) is
// compiled into BOTH the macOS app target and this UI test target via an
// explicit `sources:` entry in app/project.yml and app/Project.swift — same
// file path, two targets. UI tests run as a separate process and cannot link
// the app's binary, so the usual `@testable import` pattern does not apply.
// This is the first file in `app/MacOSUITests/` to reference the shared enum;
// C-22 recorded that the directory had zero references before this plan.
//
// C-25 BOUNDS WHAT THIS SUITE PROVES, AND THIS SENTENCE IS THE BOUND. Both UI
// test targets are pinned to `SWIFT_VERSION: "5.9"` / `SWIFT_STRICT_CONCURRENCY:
// minimal`, because fastlane's `SnapshotHelper.swift` predates Swift 6. This
// suite is therefore **APP-10 evidence only and is never evidence for APP-12**,
// which is about the app targets and is carried by their build under Swift 6
// with complete checking plus plan 06-17's scan. A green run here says nothing
// whatsoever about concurrency safety.
//
// WHERE THIS RUNS, AND WHY NOT HERE. C-24: a full-scheme `App-macOS` test
// launches an unsigned `AppMacOSUITests-Runner` and puts a Gatekeeper
// "damaged, move to Trash" dialog on the developer's own desktop. This suite is
// therefore never run locally; its result comes from the `app (macOS)` job on
// the phase's pull request. Plan 06-01 measured that this is a real route and
// not a hope: `probe_verdict=viable`, `harvested_strings=114`,
// `reached_subject=true` on a headless GitHub Actions runner.
//
// THE DETECTION IDIOM IS COPIED FROM `AppStoreScreenshotTests.swift:52-54`; THE
// SKIP IS NOT, AND NEITHER IS THE FOREGROUND-ACTIVATION CALL. macOS XCUITest
// spawns the runner through launchd, which scrubs `CI` and `GITHUB_ACTIONS`
// from the environment, so the home directory is the only usable signal — and
// it is recorded here as an observable FACT rather than branched on. A suite
// that raised XCTest's skip on a headless runner would answer APP-10 with
// silence, which is the "gate that has never executed" this phase exists to
// stop shipping. The two calls the older test's skip exists to avoid — the one
// that brings the app to the foreground and the window query that needs it —
// are described here and appear nowhere below; 06-01 proved the accessibility
// tree is populated without either.
//
// NEVER QUERY BY VISIBLE TEXT. Every destination below is reached through an
// `AccessibilityIdentifiers.Shell.*` constant, and the three are asserted
// INDIVIDUALLY, each with a message naming which one is missing, BEFORE any
// total — because a count of three reached by two sidebar rows and one stray
// element would pass a total-only assertion.

/// The macOS navigation shell: three destinations, and work that survives a
/// destination change (APP-10, D-82).
@MainActor
final class ShellTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - APP-10

    /// The three destinations exist, each asserted by its own constant.
    func testThreeDestinationsExist() {
        let headless = NSHomeDirectory() == "/Users/runner"
        print("runner_headless=\(headless)")

        app.launch()

        let encode = element(AccessibilityIdentifiers.Shell.sidebarEncode)
        let hashing = element(AccessibilityIdentifiers.Shell.sidebarHashing)
        let timestamps = element(AccessibilityIdentifiers.Shell.sidebarTimestamps)

        XCTAssertTrue(
            encode.waitForExistence(timeout: 30),
            "the Encode/decode destination is missing — no element carries "
                + AccessibilityIdentifiers.Shell.sidebarEncode
                + " (headless=\(headless))"
        )
        XCTAssertTrue(
            hashing.exists,
            "the Hashing destination is missing — no element carries "
                + AccessibilityIdentifiers.Shell.sidebarHashing
        )
        XCTAssertTrue(
            timestamps.exists,
            "the Timestamps destination is missing — no element carries "
                + AccessibilityIdentifiers.Shell.sidebarTimestamps
        )

        // Only now a total, and it is computed from the three elements just
        // asserted rather than from a query that could match anything else.
        let found = [encode, hashing, timestamps].filter(\.exists).count
        XCTAssertEqual(found, 3, "destinations_macos=\(found), expected 3")

        // A `print` from this bundle does NOT reach the xcodebuild log — 06-01
        // measured that, because the runner app is launched by testmanagerd and
        // its stdout is not connected to xcodebuild's pipe. The counts are
        // therefore carried in the assertion messages above and in the
        // `.xcresult`; these calls are kept for the local case only.
        print("destinations_macos=\(found)")
        print("destinations_source=ShellTests-macos")

        // Deliberately failing nothing, and deliberately not silent: a green run
        // that recorded no number would be a green about nothing. This puts the
        // count in the run's activity log, which crosses the IPC boundary that
        // `print` does not.
        XCTContext.runActivity(named: "destinations_macos=\(found)") { _ in }
    }

    // MARK: - D-82

    /// Work in progress survives switching destination and coming back.
    ///
    /// **This is the platform the trap belongs to.** A `NavigationSplitView`
    /// swaps its detail view when the sidebar selection changes, so state held
    /// inside a surface would be discarded here and only here. A check that ran
    /// on iOS alone would prove the wrong thing.
    func testPipelineSurvivesDestinationSwitch() {
        app.launch()

        let useExample = element(AccessibilityIdentifiers.Encode.useExample)
        XCTAssertTrue(
            useExample.waitForExistence(timeout: 30),
            "the worked-value button is missing — no element carries "
                + AccessibilityIdentifiers.Encode.useExample
        )
        useExample.click()

        // Captured rather than compared against a literal: the worked value
        // lives in `InputExample`, which is app-target code this process cannot
        // link. Asserted non-empty FIRST, so the comparison after the round trip
        // cannot pass by comparing nothing with nothing.
        let populated = inputValue()
        XCTAssertFalse(populated.isEmpty, "the worked-value button left the Encode input empty")

        let cardsBefore = cardCount()
        addOneStep()
        let cardsAfter = cardCount()
        XCTAssertGreaterThan(
            cardsAfter,
            cardsBefore,
            "the add-step control appended nothing: \(cardsBefore) cards before, \(cardsAfter) after"
        )

        switchTo(AccessibilityIdentifiers.Shell.sidebarHashing)
        switchTo(AccessibilityIdentifiers.Shell.sidebarEncode)

        let restored = inputValue()
        XCTAssertEqual(restored, populated, "the Encode input did not survive the destination change")
        XCTAssertEqual(
            cardCount(),
            cardsAfter,
            "the appended card did not survive the destination change"
        )

        print("d82_restored_macos=ok")
        XCTContext.runActivity(named: "d82_restored_macos=ok") { _ in }
    }

    // MARK: - Queries, all of them by identifier

    /// The first element carrying `identifier`, whatever kind of element it is.
    ///
    /// Deliberately not scoped to a query category: a sidebar row, a card and a
    /// menu item resolve to different element types, and the point of the shared
    /// constant is that neither the sweep nor this suite has to know which.
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// How many step cards are on the current destination.
    private func cardCount() -> Int {
        app.descendants(matching: .any).matching(identifier: AccessibilityIdentifiers.Step.card).count
    }

    /// The Encode surface's input, as the accessibility tree reports it.
    private func inputValue() -> String {
        (element(AccessibilityIdentifiers.Encode.input).value as? String) ?? ""
    }

    /// Open the first add-step menu on screen and choose its first operation.
    private func addOneStep() {
        let addStep = app.descendants(matching: .any)
            .matching(identifier: AccessibilityIdentifiers.Step.addStep)
            .element(boundBy: 0)
        XCTAssertTrue(addStep.waitForExistence(timeout: 10), "no add-step control on the Encode surface")
        addStep.click()

        let item = app.descendants(matching: .any)
            .matching(identifier: AccessibilityIdentifiers.Step.addStepMenu)
            .element(boundBy: 0)
        XCTAssertTrue(item.waitForExistence(timeout: 10), "the add-step menu presented no items")
        item.click()
    }

    /// Move to the destination carrying `identifier`.
    private func switchTo(_ identifier: String) {
        let destination = element(identifier)
        XCTAssertTrue(destination.waitForExistence(timeout: 10), "cannot reach the destination \(identifier)")
        destination.click()
    }
}
