import XCTest

// `AccessibilityIdentifiers` (app/Shared/AccessibilityIdentifiers.swift)
// is compiled into BOTH the main app target (App-iOS) and this UI test
// target via xcodegen's / Tuist's `sources:` list — same file path, two
// targets. UI tests run as a separate process and can't link the main
// app's binary, so the usual `@testable import` pattern doesn't apply.
// Compiling the one shared file into both targets is the standard
// workaround; single source of truth preserved.

/// Drives App Store screenshot capture via fastlane snapshot.
///
/// **Per-appearance test functions, not one looping test.** Fastlane runs
/// each function as a separate test invocation and sets the simulator's
/// appearance BEFORE the app launches, so the app boots directly in light
/// or dark mode — no relaunch, no flicker. This also means:
///
///   - Parallel: light and dark can run on different simulators simultaneously.
///   - Independent failure: if dark breaks, light still captures.
///   - Independent re-run: `fastlane snapshot --only_testing
///     AppUITests/AppStoreScreenshotTests/testLightMode` when iterating.
///
/// **Selector contract.** Never query by visible text — see
/// `AccessibilityIdentifiers.swift`. The constants there are the
/// project-wide single source of truth, refactor-safe and locale-proof.
///
/// **Output.** `fastlane/screenshots/en-US/<device>-<NN>-<test>.png`.
/// Both light and dark captures land in the same `en-US/` directory;
/// deliver uploads everything. App Store Connect's 10-screenshot-per-class
/// limit applies — at 2 screens × 2 appearances × N languages, you have
/// (10 / appearances) screens of headroom per language.
@MainActor
final class AppStoreScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        setupSnapshot(app)

        // Force portrait — Simulator orientation persists across runs, and
        // App Store Connect requires specific portrait dimensions (e.g.
        // 1290×2796 for iPhone 16 Plus). A landscape capture produces the
        // same pixels in 2796×1290 — wrong dimensions, rejected upload.
        // Set BEFORE app.launch() so the app renders portrait from frame 0.
        XCUIDevice.shared.orientation = .portrait
    }

    private func launchAndCapture(appearance: XCUIDevice.Appearance, label: String) {
        // Use launch argument to communicate the target color scheme to the
        // app, rather than `XCUIDevice.shared.appearance = appearance` (which
        // has a known cold-simulator timeout flake on GHA macOS runners —
        // the setter waits for springboard confirmation, and on freshly-booted
        // simulators that handshake can timeout, failing the test with
        // "Failed to set appearance mode: Timed out while setting appearance
        // mode to Light"). AppMain reads `-UITestColorScheme` at App
        // init and applies `.preferredColorScheme(...)` to its WindowGroup,
        // bypassing the system appearance API entirely.
        let scheme = (appearance == .dark) ? "dark" : "light"
        app.launchArguments.append(contentsOf: ["-UITestColorScheme", scheme])
        // PINNED (07-07). This captures the PNG called "01-home" that is uploaded to the App Store,
        // and the wait below names the Encode destination's content. Once `selection` persists, an
        // unpinned launch would either time out here or — worse if the wait were ever loosened —
        // ship a screenshot of whichever surface the previous test happened to leave behind. The pin
        // appends, so the appearance argument set above survives.
        app.launchPinned(showing: LaunchState.encodeDestination)

        // Wait for the first destination by accessibility identifier. Never
        // query by visible text — that's fragile to localization and copy edits.
        //
        // REPOINTED BY PLAN 06-13 (C-22). This waited on a title identifier
        // that the template's placeholder root view carried; plan 06-13
        // repointed `app/Shared/App.swift` at `RootView`, so that identifier
        // stopped reaching a running app and this wait timed out in the
        // required `app (iOS Simulator)` job. C-22 names `Shell.tab.encode` as
        // the replacement and this is it. Plan 06-14 then deleted the
        // placeholder view and that identifier outright, in the same change as
        // the `test/identity_test.rb` G8 amendment that had asserted the view
        // existed.
        //
        // NOT `staticTexts`: `Shell.tab.encode` is attached to the destination's
        // CONTENT container, not to a `Text`, because SwiftUI does not put an
        // accessibility identifier on an iOS tab bar button on 18.6 or 26.1 —
        // measured on three runtimes by plan 06-13 and recorded in
        // `app/UITests/ShellTests.swift`. A type-agnostic query is what works on
        // all three.
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: AccessibilityIdentifiers.Shell.tabEncode)
                .firstMatch
                .waitForExistence(timeout: 10),
            "The first destination didn't appear within 10s — check app.launch() succeeded and the identifier is attached"
        )

        snapshot("01-home-\(label)")

        // Add more screens here as the app grows. Each snapshot() call
        // writes one PNG named <device>-NN-<test>-<image>.png into
        // fastlane/screenshots/en-US/.
    }

    func testLightMode() {
        launchAndCapture(appearance: .light, label: "light")
    }

    func testDarkMode() {
        launchAndCapture(appearance: .dark, label: "dark")
    }
}
