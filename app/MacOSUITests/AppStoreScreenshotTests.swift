import AppKit
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
// NOTHING IS FILED UNTIL SEVEN PRECONDITIONS HOLD, and ``file(_:)`` is what enforces that. The
// seventh is the one this gate went without: assertion 2 judged the OUTPUT VALUES and only those,
// so TWO OF EIGHT tiles shipped with the input and the "Step 1 HTML encode" header scrolled under
// the TRANSLUCENT title bar — `macos-01-chain-light`, the LEAD TILE of the set, and
// `macos-05-chain-dark` — with every assertion green. `ScreenshotDriver.swift` carries the head
// population and the arithmetic that makes ASSERTION 7 satisfiable. Criterion 2 forbids "a launch
// or title screen", and a test that captures whatever is on screen is how one ships.

/// Four states, two appearances — per-appearance test functions, so light and dark can fail or be
/// re-run independently.
@MainActor
final class AppStoreScreenshotTests: XCTestCase {
    var app: XCUIApplication!

    /// The POINT size `-UITestWindowSize` is asked for. **The target PIXEL pair is named in prose
    /// and never spelled here, because the gate on this file greps for it and a comment stating
    /// it would turn that gate red by existing** (`.continue-here.md`, blocking). The rule under
    /// that: pixels are the MEASUREMENT, taken from the produced PNG in the evidence file, and a
    /// test hardcoding them would pass on a machine whose backing scale makes them wrong.
    static let captureWindowSize = "1440x900"

    /// `Operation.allCases.count`, asserted before any menu index is taken, and this chain's two
    /// indices — each proven at capture time against that operation's own catalog string.
    static let operationCount = 10
    static let base64EncodeItem = 0
    static let sha256Item = 8
    static let base64EncodeTitle = "Base64 encode"
    static let sha256Title = "SHA-256"

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

    /// Attempts ``scrollValuesIntoFrame(_:head:)`` may take, and the slack it settles for.
    /// `scrollMargin` is the room ASSERTION 7 refuses to spend: NOT a tolerance, and not lowered.
    static let scrollAttempts = 6
    static let scrollMargin: CGFloat = 12

    /// Wheel events ``wheel(_:)`` may spend discovering the sign and the target, the two asks
    /// ``measureScrollResponse(_:)`` probes this platform's response with, and how many steps the
    /// chain appends before it measures whether they fit. The small ask is the magnitude UL-079
    /// measured an iOS DRAG swallowing whole; whether a macOS WHEEL does the same is a measurement
    /// taken on every chain shot, never inherited.
    static let discoveryAttempts = 3
    static let largeAsk: CGFloat = 200
    static let smallAsk: CGFloat = 2.5
    static let chainAppends = 2

    /// What the last ``contentBounds()`` call found, and `appended=N retracted=M` for the shot
    /// being captured — both on the evidence line of EVERY shot, so a tile's composition is a
    /// measurement rather than an inference from its file name.
    var chrome = "none"
    var composition = "appended=0 retracted=0"

    /// The failure count when the current shot began, for ``file(_:)``; and the wheel convention,
    /// discovered per launch rather than taken from a doc comment. `scrollCalibrated` records that
    /// ONE correctly-signed delivery has been observed, after which a zero answer means "at the
    /// limit" rather than "wrong sign".
    var failuresBefore = 0
    var scrollSign: CGFloat = 1
    var scrollTargetIndex = 0
    var scrollCalibrated = false

    /// How many wheel targets ``scrollTarget()`` last built, PUBLISHED BY THE FUNCTION THAT BUILDS
    /// THE LIST so the bound that walks it cannot disagree with it. It replaced a `scrollTargets`
    /// constant whose only consumer was an assertion comparing it with the two-element array
    /// literal on the line above — a comparison of two compile-time values, which is to say an
    /// assertion with no input on which it fails, inside the harness whose subject is those.
    var scrollTargetCount = 0

    /// **THE SKIP IS CONDITIONAL ON THE MEASURED CAUSE, NOT ON WHO THE RUNNER IS (D-137, retained
    /// 2026-09-15).** The `/Users/runner` self-skip was lifted for a runner measurement, and run
    /// 34978692666 named why these captures cannot run there. The runner display is 1024x768 (its
    /// failure recording), so the window this suite forces overflows the screen:
    /// `ScreenshotDriver.swift:72: Not hittable: Button, {{1101.0, 254.0}, {96.0, 16.0}},
    /// identifier: 'Encode.useExample'`, and `AppStoreScreenshotTests.swift:248: … 1 of 2 values are
    /// outside (0.0,77.0,1024.0,632.0)`. So the suite skips when, and only when, the screen's visible
    /// frame cannot contain ``captureWindowSize``, and it prints both sizes. Any display large enough
    /// runs it. Nothing keys on HOME. `ScreenshotContract.swift` §"The headless-runner self-skip"
    /// carries the history.
    ///
    /// **AND AS OF 08.6-03 THE SKIP IS ITSELF CONDITIONAL — ON A DECLARATION (D-154, D-155).**
    /// A short display no longer skips by default; it REFUSES. The skip above is not free on the
    /// one path that matters: `ci/take-screenshots.sh:187` goes on to
    /// `ci/extract-mac-screenshots.sh`, whose `rm` at `:53` deletes the existing
    /// `fastlane/Mac_screenshots/en-US/macos-*.png` tiles BEFORE discovering at `:156` that the
    /// run produced no attachment — and they are untracked and gitignored, so a skip there
    /// destroys the previous set and exits 0. Default-strict is the safe polarity because the
    /// delete is one-way and a red is not: an invocation path nobody has thought about goes loudly
    /// red instead of quietly reaching it. **The only path permitted to declare is a FORK-OWNED
    /// CI cell that provably cannot reach that `rm`** — one invoking `xcodebuild` directly and
    /// never `ci/take-screenshots.sh`. The decision itself is `CaptureFit.captureDeclaration`
    /// (`CaptureFit.swift`), pure and unit-exercisable, because none of the interesting inputs
    /// exist on the machine this suite is developed on.
    override func setUpWithError() throws {
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame.size
        let visibleText = visible.map { "\($0.width)x\($0.height)" } ?? "none"
        print("capture_fit requested=\(Self.captureWindowSize) visibleFrame=\(visibleText)")
        switch CaptureFit.captureDeclaration(visible: visible,
                                             requested: Self.captureWindowSize,
                                             environment: ProcessInfo.processInfo.environment) {
        case .proceed:
            break
        case .skip(let reason):
            throw XCTSkip(reason)
        case .refuse(let reason):
            XCTFail(reason)
            throw CaptureFitRefusal.displayCannotHoldCaptureWindow(reason)
        }

        // TRUE, AND IT IS THE STRICTER SETTING RATHER THAN THE LOOSER ONE — the iOS twin's
        // finding, carried across because the twins must not diverge on it. With `false` a refused
        // shot wrote no tile only because the method ABORTED — a side effect of XCTest unwinding
        // rather than a verdict — and that abort also cost every LATER shot its tile. The refusal
        // is now ``file(_:)``'s explicit decision. The gate still RECORDS before it judges.
        continueAfterFailure = true
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - The two sets, and the ordinals that decide what a reviewer sees first

    func testLightMode() {
        file(chainShot("01-chain-light", Self.light))
        file(hashingShot("02-hashing-light", Self.light))
        file(timestampsShot("03-timestamps-light", Self.light))
        file(encodeURLShot("04-encode-url-light", Self.light))
    }

    /// The capture for a shot that EARNED it — counted over the failures THIS shot recorded, which
    /// ``launch(_:_:)`` baselines. This is the whole reason `continueAfterFailure` can be true: the
    /// refusal is a VERDICT rather than a consequence of the method dying, so a refused shot no
    /// longer takes the tiles after it down with it. `totalFailureCount`, so an exception counts.
    private func file(_ named: String) {
        let recorded = (testRun?.totalFailureCount ?? 0) - failuresBefore
        guard recorded == 0 else {
            return record("refused shot=\(named) failures=\(recorded) — no tile written")
        }
        attachScreenshot(named)
    }

    func testDarkMode() {
        file(chainShot("05-chain-dark", Self.dark))
        file(hashingShot("06-hashing-dark", Self.dark))
        file(timestampsShot("07-timestamps-dark", Self.dark))
        file(encodeURLShot("08-encode-url-dark", Self.dark))
    }

    // MARK: - The four states, each returning its own name once it has earned it

    /// THE CHAIN — HTML encode, then Base64 encode, then SHA-256, over the worked example.
    private func chainShot(_ named: String, _ appearance: String) -> String {
        launch(Self.pinning(LaunchState.encodeDestination, format: Self.htmlFormat), appearance)
        fillFromExample(AccessibilityIdentifiers.Encode.useExample, reading: AccessibilityIdentifiers.Encode.input)
        addStep(Self.base64EncodeItem, Self.base64EncodeTitle)
        addStep(Self.sha256Item, Self.sha256Title)
        // **THE COMPOSITION IS MEASURED RATHER THAN HARDCODED.** Both appends are made; the surface
        // then RETRACTS its last appended step while the head and the tail cannot share the band.
        // The root card's output carries `Encode.output`, NOT `Step.output`, so each contribution
        // is still asserted alone — `ScreenshotContract.swift` §"population".
        let surviving = retractChainToFit(named, head: Self.headIdentifiers(.encode),
                                          appended: Self.chainAppends)
        gate(named, cards: 1 + surviving, sources: Self.chainSources(surviving),
             surface: AccessibilityIdentifiers.Encode.output, input: .encode)
        // STILL A CHAIN — counted from the TREE and not from the loop's own counter, which floors
        // at 1 by construction and so could not fail. `Step.remove`'s population IS the appended
        // cards (D-100), read off the surface that is being filed.
        let appended = count(AccessibilityIdentifiers.Step.remove)
        XCTAssertGreaterThan(appended, 0, "\(named): \(appended) appended cards survive the retraction — a "
            + "root-only surface is not a chain and this tile makes no chaining argument")
        return named
    }

    /// Hashing at its seeded root: one input, four digests at once.
    private func hashingShot(_ named: String, _ appearance: String) -> String {
        launch(Self.pinning(LaunchState.hashingDestination, format: Self.htmlFormat), appearance)
        fillFromExample(AccessibilityIdentifiers.Hashing.useExample, reading: AccessibilityIdentifiers.Hashing.input)
        gate(named, cards: 1, sources: Self.hashingCells.map { ValueSource($0, 1) },
             surface: AccessibilityIdentifiers.Hashing.digestSHA512, input: .hashing)
        return named
    }

    /// Timestamps at its seeded root in the pinned `UTC` zone: one instant, three representations.
    /// `Timestamps.cell.*` carry NO identifier while empty (`OutputBlock.swift:65-73` attaches on
    /// the `.value` branch alone), so all three count 0 at launch and 1 after the click.
    private func timestampsShot(_ named: String, _ appearance: String) -> String {
        launch(Self.pinning(LaunchState.timestampsDestination, format: Self.htmlFormat), appearance)
        fillFromExample(AccessibilityIdentifiers.Timestamps.useExample, reading: AccessibilityIdentifiers.Timestamps.input)
        gate(named, cards: 1, sources: Self.timestampsCells.map { ValueSource($0, 1) },
             surface: AccessibilityIdentifiers.Timestamps.cellISO8601, input: .timestamps)
        return named
    }

    /// Encode/decode at its seeded single step with **format = URL** — a third conversion family
    /// beside shot 01's HTML (01 is this surface mid-work, not this state).
    private func encodeURLShot(_ named: String, _ appearance: String) -> String {
        launch(Self.pinning(LaunchState.encodeDestination, format: Self.urlFormat), appearance)
        fillFromExample(AccessibilityIdentifiers.Encode.useExample, reading: AccessibilityIdentifiers.Encode.input)
        gate(named, cards: 1, sources: [ValueSource(AccessibilityIdentifiers.Encode.output, 1)],
             surface: AccessibilityIdentifiers.Encode.output, input: .encode)
        return named
    }

    // MARK: - The six capture-time preconditions

    /// Assertions 1-7, all of them, before any tile is filed — everything measured and RECORDED
    /// before anything is judged (`ScreenshotContract.swift` §"measured before judged").
    ///
    /// `input` is the SURFACE'S OWN input block, named by each shot the way `surface:` already is:
    /// the head of the pipeline, which until ASSERTION 7 nothing required to be in the photograph.
    @discardableResult
    private func gate(_ shot: String, cards: Int, sources: [ValueSource], surface: String, input: SurfaceInput) -> [String] {
        let rendered = count(surface)
        let found = count(AccessibilityIdentifiers.Step.card)
        let matched = sources.map { count($0.identifier) }
        let blocked = count(AccessibilityIdentifiers.Step.blocked)
        // The menu is opened, counted and closed FIRST, so every geometry read below is taken with
        // the window back in the state it will be photographed in.
        let controls = privacyItemsInTheAppMenu(shot)
        let measure = frameShot(shot, sources: sources, input: input)
        let visible = measure.band
        let seen = values(sources)
        let texts = seen.map(\.text)
        let outside = seen.filter { $0.frame.isEmpty || !visible.contains($0.frame) }
        record("shot=\(shot) cards=\(found) surface=\(rendered) population=\(matched) values=\(texts.count) "
            + "lengths=\(texts.map(\.count)) outside=\(outside.count) blocked=\(blocked) privacy=\(controls) "
            + "headTop=\(measure.headTop) headTop_by=\(measure.headTopBy) tailBottom=\(measure.tailBottom) "
            + "requiredDelta=\(measure.requiredDelta) availableDelta=\(measure.availableDelta) "
            + "fits=\(measure.fits) scrollBy=\(measure.scrollBy) \(composition) head=\(measure.describedHead) "
            + "frames=\(seen.map { describeRect($0.frame) }.joined(separator: ",")) "
            + "cardframes=\(frames(AccessibilityIdentifiers.Step.card).map(describeRect).joined(separator: ",")) "
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

        // 7 — AND THE HEAD OF THE PIPELINE IS IN THE PHOTOGRAPH. The clause assertion 2 could not
        // state: the lead tile shipped with its input and its "Step 1 HTML encode" header under the
        // title bar while every VALUE was inside the band. ASSERTION 2 IS UNTOUCHED ABOVE — the
        // population is WIDENED, and a widening paid for by a loosening re-creates the defect.
        assertHeadInFrame(shot, measure)

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
        var read = "", at = "", entries = 0
        if byIdentifier == 0 {
            // MEASURED: the `[OPEN]` resolves NEGATIVE, so fall back and read each item through
            // renderedText UNIONED WITH `title` — AXTitle is where AppKit publishes a menu item's
            // text and the shared read layer does not ask for it. Every component is recorded, so a
            // zero here is a named measurement rather than a silent absence.
            //
            // **THE POPULATION IS COUNTED, NOT ONE ORDINAL PROBED.** A probe of a single index can
            // answer at most 1, so assertion 4's "expected exactly 1" was structurally unable to
            // fail on the route this platform actually takes — driven red on two privacy items in
            // the app menu (a second `CommandGroup(after: .appInfo)`, or one emitted twice by a
            // `Commands` builder): the probe read index 1, matched, answered 1, and the assertion
            // was GREEN with two. Counted, it answers 2 and the assertion names the number.
            //
            // Counting is also a REPAIR: the probe answered 0 for a menu carrying exactly one item
            // at any other ordinal, which is a false refusal, and the ordinal is not the subject —
            // "exactly 1 privacy item in the app menu" is. `entries` is already bounded and already
            // recorded, so this adds no unbounded walk; `privacy_at=` keeps the positions on the
            // record, so a `CommandGroup` placement that moves is still visible as a measurement.
            let all = menu.descendants(matching: .menuItem)
            entries = all.count
            var matched: [String] = []
            for index in 0 ..< entries {
                let entry = all.element(boundBy: index)
                let text = entry.renderedText.isEmpty ? entry.title : entry.renderedText
                if index == Self.privacyItemIndex {
                    read = text
                }
                if text == Self.privacyPolicyTitle {
                    matched.append("#\(index)")
                }
            }
            found = matched.count
            at = matched.joined(separator: ",")
        }
        record("\(shot) privacy_by_identifier=\(byIdentifier) privacy_found=\(found) "
            + "privacy_read=\"\(read)\" privacy_at=\(at.isEmpty ? "none" : at) "
            + "app_menu_items=\(entries) menubar_items=\(items)")

        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        app.activate()
        return found
    }

    // MARK: - Queries, the capture, and the evidence channel

    /// Captures the foreground window. `attachment.name` BECOMES THE EXTRACTED FILE NAME
    /// (`ci/extract-mac-screenshots.sh:140-150`), which is `deliver`'s sort key.
    private func attachScreenshot(_ name: String) {
        let screenshot = app.windows.firstMatch.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "macos-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
