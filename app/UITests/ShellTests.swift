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
// NEVER QUERY BY VISIBLE TEXT. Every destination below is identified by an
// `AccessibilityIdentifiers.Shell.*` constant, asserted INDIVIDUALLY, each with
// a message naming which one is missing, BEFORE any total — because a count of
// three reached by two tabs and one stray element would pass a total-only
// assertion, and "a correct check pointed at the wrong population" is the
// failure class this phase exists to stop repeating.
//
// MEASURED, AND IT DECIDES THE SHAPE OF THIS FILE: **SwiftUI DOES NOT PUT AN
// ACCESSIBILITY IDENTIFIER ON AN iOS TAB BAR BUTTON.** Dumped from the running
// app on three runtimes, with the identifier tried in four placements — on the
// `Label` inside `.tabItem`, on the view carrying `.tabItem`, on a `Text` inside
// a composed `Label`, and on iOS 18's `Tab` — the tab bar's buttons carry a
// label and no identifier on iOS 18.6 and 26.1 in every one of them. (On 17.5
// the Label placement alone does reach the button, which is exactly how a
// 17.5-only check would have shipped a suite that fails on the other two.) An
// `.accessibilityLabel` DOES propagate; an `.accessibilityIdentifier` does not.
//
// So the identifier is attached to each tab's CONTENT, which works identically
// on all three runtimes, and this suite VISITS each destination rather than
// looking for three buttons. That is a stronger statement than the one it
// replaces — it says the Nth tab item leads to the destination whose content
// carries the Nth constant, and that it leads to no other — and the only
// non-identifier addressing it uses is an INDEX into `app.tabBars.buttons`,
// whose population is asserted to be exactly 3 before any index is taken. No
// query anywhere in this file matches on a word the user can read.

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

    /// The three destinations exist, each asserted by its own constant, and each
    /// one reached by its own tab item.
    func testThreeDestinationsExist() {
        // PINNED (07-07). The walk below indexes the tab bar from 0 and asserts that tab item N
        // shows destination N AND NO OTHER. That second clause is about which tab content is in the
        // tree, so it depends on where the app opened: a launch restored onto Timestamps would have
        // that destination's content already built when tab 0 is tapped.
        app.launchPinned(showing: LaunchState.encodeDestination)

        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 30), "the app presents no tab bar at all")

        // The population, asserted BEFORE any index is taken into it. Three
        // destinations means three tab items and nothing else; an index into a
        // collection of unknown size is the wrong-population shape.
        XCTAssertEqual(bar.buttons.count, 3, "the tab bar carries \(bar.buttons.count) items, expected 3")

        var found = 0
        for (index, expected) in Self.destinations.enumerated() {
            bar.buttons.element(boundBy: index).tap()

            let reached = element(expected.identifier).waitForExistence(timeout: 15)
            XCTAssertTrue(
                reached,
                "the \(expected.name) destination is missing — tab item \(index) does not show "
                    + expected.identifier
            )
            if reached {
                found += 1
            }

            // And it leads to that destination ONLY. This is what ties the index
            // to the constant one-to-one: three tab items that all showed the
            // same surface would satisfy the assertion above three times over.
            for other in Self.destinations where other.identifier != expected.identifier {
                XCTAssertFalse(
                    element(other.identifier).exists,
                    "tab item \(index) shows \(other.identifier) as well as \(expected.identifier)"
                )
            }
        }

        XCTAssertEqual(found, 3, "destinations_ios=\(found), expected 3")

        print("destinations_ios=\(found)")
        print("destinations_source=ShellTests-ios")
    }

    /// The three destinations in tab order, each with the constant its content
    /// carries and a human name for the failure message.
    private static let destinations: [(identifier: String, name: String)] = [
        (AccessibilityIdentifiers.Shell.tabEncode, "Encode/decode"),
        (AccessibilityIdentifiers.Shell.tabHashing, "Hashing"),
        (AccessibilityIdentifiers.Shell.tabTimestamps, "Timestamps")
    ]

    // MARK: - D-82

    /// Work in progress survives switching destination and coming back.
    func testPipelineSurvivesDestinationSwitch() {
        // PINNED (07-07). This queries the Encode worked-value button with no navigation first, so
        // an unpinned launch onto Hashing would spend 30 s waiting for an element that is not in the
        // tree and then fail — as a statement about test ORDER, not about D-82.
        app.launchPinned(showing: LaunchState.encodeDestination)

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

        visit(1, expecting: AccessibilityIdentifiers.Shell.tabHashing, named: "Hashing")
        visit(0, expecting: AccessibilityIdentifiers.Shell.tabEncode, named: "Encode/decode")

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

    /// Tap the tab item at `index` and confirm it showed the destination whose
    /// content carries `identifier`.
    ///
    /// The index addresses `app.tabBars.buttons`, whose count is asserted to be
    /// exactly 3 in `testThreeDestinationsExist`; what the index LEADS TO is
    /// then checked by constant, so a reordering of the tabs fails here rather
    /// than silently testing the wrong surface.
    private func visit(_ index: Int, expecting identifier: String, named name: String) {
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 15), "the app presents no tab bar at all")
        bar.buttons.element(boundBy: index).tap()
        XCTAssertTrue(
            element(identifier).waitForExistence(timeout: 15),
            "cannot reach the \(name) destination — tab item \(index) does not show \(identifier)"
        )
    }
}
