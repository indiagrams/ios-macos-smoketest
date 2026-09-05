import XCTest

// APP-10's EVIDENCE, AS A NAMED SUITE. 06-VALIDATION.md's APP-10 row names
// `-only-testing:AppUITests/ShellTests`, and this is exactly that file and that
// class name. Do not rename either: an artifact that can be selected by name
// cannot be quietly satisfied by something weaker. `app/MacOSUITests/ShellTests.swift`
// declares the SAME class name so the macOS twin resolves as
// `-only-testing:AppMacOSUITests/ShellTests`.
//
// `AccessibilityIdentifiers` (app/Shared/AccessibilityIdentifiers.swift) is
// compiled into BOTH the main app target (App-iOS) and this UI test target via
// an explicit `sources:` entry in app/project.yml and app/Project.swift — same
// file path, two targets. UI tests run as a separate process and cannot link
// the app's binary, so the usual `@testable import` pattern does not apply.
// Compiling the one shared file into both targets is the standard workaround
// and preserves the single-source-of-truth property.
//
// C-25 BOUNDS WHAT THIS SUITE PROVES, AND THIS SENTENCE IS THE BOUND. Both UI
// test targets are pinned to `SWIFT_VERSION: "5.9"` / `SWIFT_STRICT_CONCURRENCY:
// minimal`, because fastlane's `SnapshotHelper.swift` predates Swift 6. This
// suite is therefore **APP-10 evidence only and is never evidence for APP-12**,
// which is about the app targets and is carried by their build under Swift 6
// with complete checking plus plan 06-17's scan. A green run here says nothing
// whatsoever about concurrency safety. Everything below is Swift 5.9 syntax:
// `@MainActor final class`, `override func setUpWithError()`, no `async`, no
// Swift 6 isolation syntax.
//
// NEVER QUERY BY VISIBLE TEXT. Every destination below is reached through an
// `AccessibilityIdentifiers.Shell.*` constant. The three are asserted
// INDIVIDUALLY, each with a message naming which one is missing, BEFORE any
// total — because a count of three reached by two tabs and one stray element
// would pass a total-only assertion, and "a correct check pointed at the wrong
// population" is the failure class this phase exists to stop repeating.

/// The iOS navigation shell: three destinations, and work that survives a
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
        app.launch()

        let encode = element(AccessibilityIdentifiers.Shell.tabEncode)
        let hashing = element(AccessibilityIdentifiers.Shell.tabHashing)
        let timestamps = element(AccessibilityIdentifiers.Shell.tabTimestamps)

        XCTAssertTrue(
            encode.waitForExistence(timeout: 30),
            "the Encode/decode destination is missing — no element carries \(AccessibilityIdentifiers.Shell.tabEncode)"
        )
        XCTAssertTrue(
            hashing.exists,
            "the Hashing destination is missing — no element carries \(AccessibilityIdentifiers.Shell.tabHashing)"
        )
        XCTAssertTrue(
            timestamps.exists,
            "the Timestamps destination is missing — no element carries \(AccessibilityIdentifiers.Shell.tabTimestamps)"
        )

        // Only now a total, and it is computed from the three elements just
        // asserted rather than from a query that could match anything else.
        let found = [encode, hashing, timestamps].filter(\.exists).count
        XCTAssertEqual(found, 3, "destinations_ios=\(found), expected 3")

        print("destinations_ios=\(found)")
        print("destinations_source=ShellTests-ios")
    }

    // MARK: - D-82

    /// Work in progress survives switching destination and coming back.
    func testPipelineSurvivesDestinationSwitch() {
        app.launch()

        let useExample = element(AccessibilityIdentifiers.Encode.useExample)
        XCTAssertTrue(
            useExample.waitForExistence(timeout: 30),
            "the worked-value button is missing — no element carries \(AccessibilityIdentifiers.Encode.useExample)"
        )
        useExample.tap()

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

        switchTo(AccessibilityIdentifiers.Shell.tabHashing)
        switchTo(AccessibilityIdentifiers.Shell.tabEncode)

        let restored = inputValue()
        XCTAssertEqual(restored, populated, "the Encode input did not survive the destination change")
        XCTAssertEqual(
            cardCount(),
            cardsAfter,
            "the appended card did not survive the destination change"
        )

        print("d82_restored_ios=ok")
    }

    // MARK: - Queries, all of them by identifier

    /// The first element carrying `identifier`, whatever kind of element it is.
    ///
    /// Deliberately not scoped to a query category: a tab item, a sidebar row
    /// and a card resolve to different element types, and the point of the
    /// shared constant is that neither the sweep nor this suite has to know
    /// which.
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
        addStep.tap()

        let item = app.descendants(matching: .any)
            .matching(identifier: AccessibilityIdentifiers.Step.addStepMenu)
            .element(boundBy: 0)
        XCTAssertTrue(item.waitForExistence(timeout: 10), "the add-step menu presented no items")
        item.tap()
    }

    /// Move to the destination carrying `identifier`.
    private func switchTo(_ identifier: String) {
        let destination = element(identifier)
        XCTAssertTrue(destination.waitForExistence(timeout: 10), "cannot reach the destination \(identifier)")
        destination.tap()
    }
}
