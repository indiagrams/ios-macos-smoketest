import XCTest

// macOS App Store screenshot capture — the twin of `app/UITests/AppStoreScreenshotTests.swift`,
// the same eight states in the same order.
//
// **`ScreenshotContract.swift` beside this file carries the contract and the measurements**: why
// the window size is forced and what silently happens when it is a pixel short, why assertion 4
// cannot be counted inside the window on this platform, why every text read goes through
// `renderedText`, why the ordinal lives in the attachment name, how this suite must be run, and
// what it deliberately does not carry. Read it before changing anything here.
//
// NOTHING IS FILED UNTIL SIX PRECONDITIONS HOLD, and the capture takes the RESULT of the function
// that drove and gated the shot, so they cannot be skipped while leaving a tile behind. Criterion
// 2 forbids "a launch or title screen", and a test that captures whatever is on screen is how one
// ships.

/// Four states, two appearances — per-appearance test functions, so light and dark can fail or be
/// re-run independently.
@MainActor
final class AppStoreScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    /// The POINT size `-UITestWindowSize` is asked for. **The target PIXEL pair is named in prose
    /// and never spelled here, because the gate on this file greps for it and a comment stating
    /// it would turn that gate red by existing** (`.continue-here.md`, blocking). The rule under
    /// that: pixels are the MEASUREMENT, taken from the produced PNG in the evidence file, and a
    /// test hardcoding them would pass on a machine whose backing scale makes them wrong.
    private static let captureWindowSize = "1440x900"

    /// `Operation.allCases.count`, asserted before any menu index is taken, and this chain's two
    /// indices — each proven at capture time against that operation's own catalog string.
    private static let operationCount = 10
    private static let base64EncodeItem = 0
    private static let sha256Item = 8
    private static let base64EncodeTitle = "Base64 encode"
    private static let sha256Title = "SHA-256"

    /// The two `EncodeFormat` raw values `LaunchState` does not spell.
    private static let htmlFormat = "encode.format.html"
    private static let urlFormat = "encode.format.url"

    private static let light = "light", dark = "dark"

    /// The application's own menu, positionally: index 0 is the Apple menu. And where
    /// `CommandGroup(after: .appInfo)` puts the item — immediately after About, index 0.
    private static let appMenuIndex = 1
    private static let privacyItemIndex = 1

    /// The catalog value of `app.privacyPolicy`. An EXPECTATION, never a query: nothing here
    /// finds an element by this string (`PrivacyLinkTests.swift:80-89`).
    private static let privacyPolicyTitle = "Privacy Policy"

    /// What the last ``contentBounds()`` call found, for the evidence line.
    private var chrome = "none"

    /// Hashing's four cells and Timestamps' three, from the shipped identifier enum.
    private static let hashingCells = [
        AccessibilityIdentifiers.Hashing.digestMD5,
        AccessibilityIdentifiers.Hashing.digestSHA1,
        AccessibilityIdentifiers.Hashing.digestSHA256,
        AccessibilityIdentifiers.Hashing.digestSHA512
    ]

    private static let timestampsCells = [
        AccessibilityIdentifiers.Timestamps.cellEpoch,
        AccessibilityIdentifiers.Timestamps.cellISO8601,
        AccessibilityIdentifiers.Timestamps.cellDateTime
    ]

    /// **THE `/Users/runner` SELF-SKIP, MOVED HERE FROM THE ONE TEST BODY IT USED TO GUARD** so it
    /// covers both appearances rather than one. Unchanged in substance and still LOAD-BEARING —
    /// `ScreenshotContract.swift` §"The headless-runner self-skip" carries why, and why HOME is
    /// the only detector available inside the runner.
    override func setUpWithError() throws {
        continueAfterFailure = false
        if NSHomeDirectory() == "/Users/runner" {
            throw XCTSkip("Skipped on headless GitHub Actions runner; runs in full locally via `make screenshots`.")
        }
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - The two sets, and the ordinals that decide what a reviewer sees first

    func testLightMode() {
        attachScreenshot(chainShot("01-chain-light", Self.light))
        attachScreenshot(hashingShot("02-hashing-light", Self.light))
        attachScreenshot(timestampsShot("03-timestamps-light", Self.light))
        attachScreenshot(encodeURLShot("04-encode-url-light", Self.light))
    }

    func testDarkMode() {
        attachScreenshot(chainShot("05-chain-dark", Self.dark))
        attachScreenshot(hashingShot("06-hashing-dark", Self.dark))
        attachScreenshot(timestampsShot("07-timestamps-dark", Self.dark))
        attachScreenshot(encodeURLShot("08-encode-url-dark", Self.dark))
    }

    // MARK: - The four states, each returning its own name once it has earned it

    /// THE CHAIN — HTML encode, then Base64 encode, then SHA-256, over the worked example.
    private func chainShot(_ named: String, _ appearance: String) -> String {
        launch(Self.pinning(LaunchState.encodeDestination, format: Self.htmlFormat), appearance)
        fillFromExample(AccessibilityIdentifiers.Encode.useExample, reading: AccessibilityIdentifiers.Encode.input)
        addStep(Self.base64EncodeItem, Self.base64EncodeTitle)
        addStep(Self.sha256Item, Self.sha256Title)
        // THE ROOT CARD'S OUTPUT CARRIES `Encode.output`, NOT `Step.output` — `EncodeSurface.swift:169`
        // passes `valueIdentifier: Encode.output` into the seeded card and only the APPENDED cards
        // keep the default. A gate counting three `Step.output` would be a correct check pointed at
        // the wrong population (08-13 measured `[1, 2]`), so each contribution is asserted alone.
        gate(named, cards: 3, sources: [
            ValueSource(AccessibilityIdentifiers.Encode.output, 1),
            ValueSource(AccessibilityIdentifiers.Step.output, 2)
        ], surface: AccessibilityIdentifiers.Encode.output)
        return named
    }

    /// Hashing at its seeded root: one input, four digests at once.
    private func hashingShot(_ named: String, _ appearance: String) -> String {
        launch(Self.pinning(LaunchState.hashingDestination, format: Self.htmlFormat), appearance)
        fillFromExample(AccessibilityIdentifiers.Hashing.useExample, reading: AccessibilityIdentifiers.Hashing.input)
        gate(named, cards: 1, sources: Self.hashingCells.map { ValueSource($0, 1) },
             surface: AccessibilityIdentifiers.Hashing.digestSHA512)
        return named
    }

    /// Timestamps at its seeded root in the pinned `UTC` zone: one instant, three representations.
    /// `Timestamps.cell.*` carry NO identifier while empty (`OutputBlock.swift:65-73` attaches on
    /// the `.value` branch alone), so all three count 0 at launch and 1 after the click.
    private func timestampsShot(_ named: String, _ appearance: String) -> String {
        launch(Self.pinning(LaunchState.timestampsDestination, format: Self.htmlFormat), appearance)
        fillFromExample(AccessibilityIdentifiers.Timestamps.useExample, reading: AccessibilityIdentifiers.Timestamps.input)
        gate(named, cards: 1, sources: Self.timestampsCells.map { ValueSource($0, 1) },
             surface: AccessibilityIdentifiers.Timestamps.cellISO8601)
        return named
    }

    /// Encode/decode at its seeded single step with **format = URL** — a third conversion family
    /// beside shot 01's HTML (01 is this surface mid-work, not this state).
    private func encodeURLShot(_ named: String, _ appearance: String) -> String {
        launch(Self.pinning(LaunchState.encodeDestination, format: Self.urlFormat), appearance)
        fillFromExample(AccessibilityIdentifiers.Encode.useExample, reading: AccessibilityIdentifiers.Encode.input)
        gate(named, cards: 1, sources: [ValueSource(AccessibilityIdentifiers.Encode.output, 1)],
             surface: AccessibilityIdentifiers.Encode.output)
        return named
    }

    // MARK: - The six capture-time preconditions

    /// Assertions 1-6, all of them, before any tile is filed.
    ///
    /// **EVERYTHING IS MEASURED AND RECORDED BEFORE ANYTHING IS JUDGED.** `continueAfterFailure`
    /// is false, so an assertion placed above the evidence line takes the evidence line with it —
    /// and the numbers that would explain the failure are exactly the ones lost.
    @discardableResult
    private func gate(_ shot: String, cards: Int, sources: [ValueSource], surface: String) -> [String] {
        let rendered = count(surface)
        let found = count(AccessibilityIdentifiers.Step.card)
        let matched = sources.map { count($0.identifier) }
        let blocked = count(AccessibilityIdentifiers.Step.blocked)
        // The menu is opened, counted and closed FIRST, so every geometry read below is taken with
        // the window back in the state it will be photographed in.
        let controls = privacyItemsInTheAppMenu(shot)
        let visible = contentBounds()
        let seen = values(sources)
        let texts = seen.map(\.text)
        let outside = seen.filter { $0.frame.isEmpty || !visible.contains($0.frame) }
        record("shot=\(shot) cards=\(found) surface=\(rendered) population=\(matched) values=\(texts.count) "
            + "lengths=\(texts.map(\.count)) outside=\(outside.count) blocked=\(blocked) privacy=\(controls) "
            + "frames=\(seen.map { describeRect($0.frame) }.joined(separator: ",")) "
            + "visible=\(describeRect(visible)) \(chrome)")

        // 5 — THE SURFACE ITSELF RENDERED. First: every read above is about nothing if the window
        // exists and SwiftUI has not yet drawn into it.
        XCTAssertGreaterThan(rendered, 0, "\(shot) ASSERTION 5 (surface): no element carries \(surface), so this "
            + "capture would be of a window the app has not drawn into yet")

        // 1 — THE DRIVE LANDED. This is 1 at launch on every surface, so a chain shot whose clicks
        // silently did nothing is refused here rather than filed.
        XCTAssertEqual(found, cards, "\(shot) ASSERTION 1 (cards): \(found) step cards on the surface, expected "
            + "\(cards) — the drive did nothing and this is the launch state")

        // 2 — THE POPULATION, EACH IDENTIFIER'S CONTRIBUTION ON ITS OWN, and only then the union.
        for (index, source) in sources.enumerated() {
            XCTAssertEqual(matched[index], source.expected, "\(shot) ASSERTION 2 (population): \(matched[index]) "
                + "elements carry \(source.identifier), expected \(source.expected)")
        }
        // AND EVERY VALUE INSIDE THE BAND THE CAPTURE CAN SHOW. The photograph here is the WINDOW
        // (`attachScreenshot` captures `app.windows.firstMatch`), so the window's own rect is the
        // right frame — unlike iOS, where the photograph is the screen and the bars OVERLAY it.
        // The title-bar band is still LOCATED and subtracted rather than assumed. An EMPTY frame
        // counts as outside: `CGRect.contains` answers false for one, and so does this message.
        XCTAssertTrue(outside.isEmpty, "\(shot) ASSERTION 2 (inside the frame): \(outside.count) of \(seen.count) "
            + "values are outside \(describeRect(visible)): "
            + "\(outside.map { describeRect($0.frame) }.joined(separator: " ")) — this tile shows fewer values "
            + "than it claims to")

        // 3 — AND READABLE AND PAIRWISE DISTINCT. Three empty reads are distinct from nothing and
        // identical to each other; `assertDistinctReadable` reports those as two different failures.
        assertDistinctReadable(texts, expected: texts.count, "\(shot): the values this tile is about")

        // 4 — THE PRIVACY CONTROL EXISTS, ONCE, WHILE THIS SURFACE IS SHOWING. Counted in the app
        // MENU, which is where D-117 put it on this platform.
        XCTAssertEqual(controls, 1, "\(shot) ASSERTION 4 (privacy): \(controls) privacy items in the app menu, "
            + "expected exactly 1 (-1 means the menu bar was too short for the ordinal to be safe)")

        // 6 — AND NOTHING ON SCREEN IS AN ERROR CARD.
        XCTAssertEqual(blocked, 0, "\(shot) ASSERTION 6 (blocked): \(blocked) cards are blocked — this tile is a "
            + "screenshot of a broken pipeline")

        return texts
    }

    /// Assertion 4's macOS half: open the app menu positionally, count the privacy item by
    /// whichever route this platform allows, then CLOSE the menu again and bring the window back
    /// to front — so the capture that follows is of a window with a live title bar and no menu.
    ///
    /// Answers -1 when the menu bar is too short for the ordinal to mean anything, so that case
    /// fails assertion 4 with its number on the record instead of being silently absorbed.
    private func privacyItemsInTheAppMenu(_ shot: String) -> Int {
        let bar = app.menuBarItems
        let items = bar.count
        guard items > Self.appMenuIndex else {
            record("\(shot) privacy_menubar_items=\(items) ordinal_unsafe=true")
            return -1
        }
        let menu = bar.element(boundBy: Self.appMenuIndex)
        menu.click()

        // THE 08-11 `[OPEN]`, RE-EMITTED ON EVERY SHOT WHATEVER ITS VALUE: does a SwiftUI
        // `CommandGroup` button carry its accessibility identifier into the macOS menu bar?
        let byIdentifier = app.menuItems.matching(identifier: AccessibilityIdentifiers.Shell.privacyPolicy).count
        var found = byIdentifier
        var title = ""
        if byIdentifier == 0 {
            let entries = menu.descendants(matching: .menuItem)
            let population = entries.count
            if population > Self.privacyItemIndex {
                title = entries.element(boundBy: Self.privacyItemIndex).renderedText
                found = title == Self.privacyPolicyTitle ? 1 : 0
            }
        }
        record("\(shot) privacy_by_identifier=\(byIdentifier) privacy_found=\(found) "
            + "privacy_positional_title=\"\(title)\" menubar_items=\(items)")

        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        app.activate()
        return found
    }

    /// The band a capture can actually show: the window minus any chrome LOCATED at its top.
    /// Measured rather than assumed — on this platform the title bar does not overlay content, so
    /// subtracting it is conservative, and what was found lands in ``chrome`` and comes out of the
    /// run rather than out of this sentence.
    private func contentBounds() -> CGRect {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 30),
                      "no window resolved, so 'inside the frame' would be a comparison against nothing")
        let bounds = window.frame
        var top = bounds.minY
        var bars: [String] = []
        for bar in [("toolbar", app.toolbars.firstMatch)] where bar.1.exists && !bar.1.frame.isEmpty {
            let rect = bar.1.frame
            guard rect.midY < bounds.midY else { continue }
            top = max(top, rect.maxY)
            bars.append("\(bar.0)=top\(describeRect(rect))")
        }
        chrome = "window=\(describeRect(bounds)) chrome=\(bars.isEmpty ? "none" : bars.joined(separator: ","))"
        return CGRect(x: bounds.minX, y: top, width: bounds.width, height: bounds.maxY - top)
    }

    /// Every value in `sources`, in source order, with the frame and the text read in ONE pass.
    private func values(_ sources: [ValueSource]) -> [(frame: CGRect, text: String)] {
        var found: [(frame: CGRect, text: String)] = []
        for source in sources {
            let query = all(source.identifier)
            for index in 0 ..< query.count {
                let value = query.element(boundBy: index)
                found.append((value.frame, value.renderedText))
            }
        }
        return found
    }

    // MARK: - Driving, all of it by identifier and never by visible text

    /// All five settings keys; surface and encode format chosen by the caller.
    private static func pinning(_ surface: String, format: String) -> [String] {
        [
            LaunchState.selectionKey, surface,
            LaunchState.encodeFormatKey, format,
            LaunchState.encodeDirectionKey, LaunchState.forwardDirection,
            LaunchState.timestampsReadAsKey, LaunchState.epochReadAs,
            LaunchState.timestampsTimeZoneKey, LaunchState.fixedTimeZone
        ]
    }

    /// A fresh application, pinned, in the requested appearance, at the requested POINT size.
    ///
    /// `activate()` so the window comes to front: without it the window may launch behind others
    /// and XCUITest's window queries return nothing on a real Mac with other GUI apps running.
    private func launch(_ pinning: [String], _ appearance: String) {
        app = XCUIApplication()
        app.launchArguments += ["UI_TESTING"]
        app.launchArguments += ["-UITestColorScheme", appearance]
        app.launchArguments += ["-UITestWindowSize", Self.captureWindowSize]
        app.launchArguments += pinning
        app.launch()
        app.activate()

        // The pre-existing File → New Window fallback, KEPT UNCHANGED AND NOT EXTENDED: it is the
        // one by-visible-text menu query in this target and `evidence/08-11-controls.rb` counts them.
        if !app.windows.firstMatch.waitForExistence(timeout: 8) {
            let fileMenu = app.menuBarItems["File"]
            if fileMenu.waitForExistence(timeout: 3) {
                fileMenu.click()
                let newWindow = app.menuItems["New Window"]
                if newWindow.waitForExistence(timeout: 3) {
                    newWindow.click()
                }
            }
        }
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5), "App window must be visible")
    }

    /// Fill a surface's input from its worked-value control and hand back what the field holds.
    ///
    /// **This is also the per-shot RENDER GUARD**, using THAT surface's own identifier rather than
    /// shot 01's: a window can exist before SwiftUI has drawn into it, which is how a screenshot
    /// of an empty frame gets captured and uploaded.
    @discardableResult
    private func fillFromExample(_ control: String, reading field: String) -> String {
        let button = element(control)
        XCTAssertTrue(button.waitForExistence(timeout: 30), "no worked-value control carries \(control)")
        XCTAssertTrue(element(field).waitForExistence(timeout: 30),
                      "the window appeared but nothing carries \(field) — SwiftUI has not drawn this surface")
        button.click()
        let text = (element(field).value as? String) ?? ""
        XCTAssertFalse(text.isEmpty, "the worked-value control left \(field) empty, so every value below this "
            + "would be about the empty string")
        return text
    }

    /// Open an add-step control and choose the item at `menuIndex` — having first proven the
    /// menu's population is `Operation.allCases.count` AND that the index resolves to `title`.
    private func addStep(_ menuIndex: Int, _ title: String) {
        let controls = all(AccessibilityIdentifiers.Step.addStep)
        XCTAssertTrue(controls.element(boundBy: 0).waitForExistence(timeout: 20), "no add-step control on the surface")
        controls.element(boundBy: 0).click()

        let items = all(AccessibilityIdentifiers.Step.addStepMenu)
        XCTAssertTrue(items.element(boundBy: menuIndex).waitForExistence(timeout: 20),
                      "the add-step menu presented no item at index \(menuIndex)")
        let population = items.count
        XCTAssertEqual(population, Self.operationCount,
                       "the menu presented \(population) items, expected Operation.allCases.count "
                           + "= \(Self.operationCount)")
        let item = items.element(boundBy: menuIndex)
        XCTAssertEqual(assertReadable(item, "the add-step menu item at index \(menuIndex)"), title,
                       "menu index \(menuIndex) resolves to something other than \(title) — `Operation.allCases` "
                           + "has been reordered and this chain is not the chain it says it is")
        item.click()
    }

    // MARK: - Queries, the capture, and the evidence channel

    /// Every element carrying `identifier`, whatever kind of element it is.
    private func all(_ identifier: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: identifier)
    }

    /// How many elements carry `identifier` right now — one round trip, never a doomed wait.
    private func count(_ identifier: String) -> Int {
        all(identifier).count
    }

    private func element(_ identifier: String) -> XCUIElement {
        all(identifier).firstMatch
    }

    /// Captures the foreground window. `attachment.name` BECOMES THE EXTRACTED FILE NAME
    /// (`ci/extract-mac-screenshots.sh:140-150`), which is `deliver`'s sort key.
    private func attachScreenshot(_ name: String) {
        let screenshot = app.windows.firstMatch.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "macos-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// One measured line, emitted twice. A `print` from this bundle does NOT reach xcodebuild's
    /// pipe on macOS (06-01) — the runner is launched by `testmanagerd`, whose stdout is not
    /// connected to it — so every number also rides an `XCTContext` activity, which does cross.
    private func record(_ line: String) {
        print(line)
        XCTContext.runActivity(named: line) { _ in }
    }
}
