import XCTest

// EIGHT ORDERED SHOTS PER DEVICE, AND THE ORDER IS A FILE-NAME CONSTRAINT RATHER THAN AN INTENTION.
//
// `deliver` re-orders every set in App Store Connect by the NATURAL SORT OF THE FILE NAME
// (`deliver/lib/deliver/upload_screenshots.rb:242-260`), and an iOS file name is
// `"\(simulator)-\(name).png"` (`SnapshotHelper.swift:185`). The ordinal below IS the sort key, so
// D-125's "lead with the chained pipeline" is checkable on disk without uploading. LIGHT TAKES 01-04
// AND DARK 05-08 DELIBERATELY: both appearances land in ONE set, so a `01-…-light` / `01-…-dark`
// pairing would sort the dark tile first and the lead tile would be alphabetical accident. That lead
// tile is the 4.3(b) argument made visual — three values in three alphabets at three lengths.
//
// NOTHING IS FILED UNTIL SEVEN PRECONDITIONS HOLD. The capture takes the RESULT of the function that
// drove and gated the shot, so those seven assertions are the capture's own argument expression and
// cannot be skipped while leaving a tile behind. Criterion 2 forbids "a launch or title screen", and
// a test that captures whatever is on screen is how one ships. THE SEVENTH IS THE ONE THIS GATE WENT
// WITHOUT: assertion 2 judged the OUTPUT VALUES and only those, so four of eight iPhone tiles shipped
// with the input field and the "Step 1 <name>" header scrolled off the top and every check green.
// `ScreenshotFraming.swift` carries ASSERTION 7 and the arithmetic that makes it satisfiable.
//
// THE THREE VALUES OF SHOT 01 ARE THE SURFACE'S OWN. The root card is compared against an HTML
// encoding THIS PROCESS computes — which is what proves the `encodeFormat` pin took, since a raw
// value the app cannot resolve falls back to Base64 in silence — and the third card against a
// SHA-256 THIS PROCESS computes from the SECOND card's value, so a card that renumbers without
// recomputing fails. No digest literal appears in this file (the 07-10 house rule).
//
// THE ROOT CARD'S OUTPUT ON ENCODE CARRIES `Encode.output`, NOT `Step.output` — measured:
// `EncodeSurface.swift:169` passes `valueIdentifier: Encode.output` into the seeded card's
// `OutputBlock` and only the APPENDED cards keep the default. A three-card chain publishes ONE
// `Encode.output` and TWO `Step.output`; a gate counting three `Step.output` would be a correct
// check pointed at the wrong population. Each contribution is asserted before either is unioned.
//
// EVERY LAUNCH PINS ALL FIVE SETTINGS KEYS (07-07) and appends with `+=`, so the appearance argument
// and the pinning coexist — `selection` persists since 07-05. SECURITY: every input is a synthetic
// constant already in the tree, reached by TAPPING the worked-value control rather than by typing,
// and the status bar is pinned to 9:41 by `override_status_bar(true)`. A screenshot is published.
//
// C-25: Swift 5.9 / `SWIFT_STRICT_CONCURRENCY: minimal`, like every file in this target.

/// Four states, two appearances. **Per-appearance test functions, not one looping test:** fastlane
/// runs each as its own invocation, so light and dark can run on different simulators and fail or be
/// re-run independently (`--only_testing AppUITests/AppStoreScreenshotTests/testLightMode`).
@MainActor
final class AppStoreScreenshotTests: XCTestCase {
    /// The application under test.
    ///
    /// INTERNAL RATHER THAN PRIVATE, and not an oversight: `ScreenshotFraming.swift` is an extension in
    /// another file and an extension cannot see a `private` member. The macOS twin declares this and
    /// `chrome` internal for exactly the same reason.
    var app: XCUIApplication!

    /// `Operation.allCases.count`, asserted before any menu index is taken, and this chain's two
    /// indices — each proven at capture time against that operation's own catalog string.
    private static let operationCount = 10
    private static let base64EncodeItem = 0
    private static let sha256Item = 8
    private static let base64EncodeTitle = "Base64 encode"
    private static let sha256Title = "SHA-256"

    /// The two `EncodeFormat` raw values `LaunchState` does not spell. Neither is trusted: the root
    /// card is compared against this process's own encoding, so an unresolvable one fails here.
    private static let htmlFormat = "encode.format.html"
    private static let urlFormat = "encode.format.url"

    private static let light = "light", dark = "dark"

    /// Drags ``scrollValuesIntoFrame(_:head:)`` may take, and the room it keeps above the head.
    ///
    /// SIX RATHER THAN FOUR, and not a loosening of anything: the framing is BIDIRECTIONAL since the
    /// chain began retracting, so one shot can need a descent to un-clip the head AND a rise to bring
    /// the tail in. Four was the bound the one-way version needed; the macOS twin has been at six
    /// since it was written. `scrollMargin` is the room ASSERTION 7 refuses to spend.
    static let scrollAttempts = 6
    static let scrollMargin: CGFloat = 12

    /// What a drag spends before the scroll view moves at all — see ``drag(_:within:)``.
    static let dragHysteresis: CGFloat = 12

    /// How many steps the chain shot appends before it measures whether they fit.
    private static let chainAppends = 2

    /// `appended=N retracted=M` for the shot being captured — set by ``retractChainToFit(_:head:appended:)``,
    /// reset by ``launch(_:_:)``, and on the evidence line of EVERY shot, so the composition of a tile
    /// is a measurement rather than an inference from its file name.
    var composition = "appended=0 retracted=0"

    /// What the last ``contentBounds()`` call found at the window's edges, for the evidence line.
    var chrome = "none"
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

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Force portrait — orientation persists across runs and ASC accepts an exact list of sizes.
        // A landscape capture is the same pixels transposed: rejected. Set BEFORE any launch.
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - The two sets, and the ordinals that decide what a reviewer sees first

    func testLightMode() {
        snapshot(chainShot("01-chain-light", Self.light))
        snapshot(hashingShot("02-hashing-light", Self.light))
        snapshot(timestampsShot("03-timestamps-light", Self.light))
        snapshot(encodeURLShot("04-encode-url-light", Self.light))
    }

    func testDarkMode() {
        snapshot(chainShot("05-chain-dark", Self.dark))
        snapshot(hashingShot("06-hashing-dark", Self.dark))
        snapshot(timestampsShot("07-timestamps-dark", Self.dark))
        snapshot(encodeURLShot("08-encode-url-dark", Self.dark))
    }

    // MARK: - The four states, each returning its own name once it has earned it

    /// THE CHAIN — HTML encode, then Base64 encode, then SHA-256, over the worked example.
    ///
    /// **THE COMPOSITION IS MEASURED PER DEVICE RATHER THAN HARDCODED.** Both appends are made
    /// everywhere; the surface then RETRACTS its last appended step while the head of the pipeline
    /// and the tail of it cannot share the band. On iPad they always can — the band is 1288 pt and
    /// the three cards span 287…1333 with every value inside — so the iPad tile keeps three values
    /// and nothing scrolls. Degrading that tile to simplify the phone's harness would be a
    /// regression caused by the fix, and is refused.
    private func chainShot(_ named: String, _ appearance: String) -> String {
        launch(Self.pinning(LaunchState.encodeDestination, format: Self.htmlFormat), appearance)
        let source = fillFromExample(AccessibilityIdentifiers.Encode.useExample,
                                     reading: AccessibilityIdentifiers.Encode.input)
        assertRendersText(element(AccessibilityIdentifiers.Encode.output), SecondOpinion.htmlEncoded(source),
                          "\(named): the pinned root card, which is what proves encodeFormat really is HTML")
        addStep(Self.base64EncodeItem, Self.base64EncodeTitle)
        addStep(Self.sha256Item, Self.sha256Title)
        let head = Self.headIdentifiers(.encode)
        let surviving = retractChainToFit(named, head: head, appended: Self.chainAppends)
        let values = gate(named, cards: 1 + surviving, sources: Self.chainSources(surviving),
                          surface: AccessibilityIdentifiers.Encode.output, input: .encode)
        // STILL A CHAIN — counted from the TREE and not from the loop's own counter. `surviving`
        // floors at 1 by construction, so an assertion on it could not fail; `Step.remove`'s
        // population IS the appended cards (D-100), read off the surface that is being filed.
        let appended = count(AccessibilityIdentifiers.Step.remove)
        XCTAssertGreaterThan(appended, 0, "\(named): \(appended) appended cards survive the retraction — a "
            + "root-only surface is not a chain and this tile makes no chaining argument")
        XCTAssertEqual(values[1], SecondOpinion.base64(values[0]),
                       "\(named): step 2 shows \(values[1]), expected this process's base64 of step 1")
        // WHICH BRANCH RAN IS RECORDED, so "the digest was checked" is a measurement. The SHA-256
        // step is the one that retracts, because dropping the LAST append is the only rule a gate
        // can state mechanically and it leaves the surviving chain's recomputation intact.
        record("second_opinion shot=\(named) values=\(values.count) "
            + "branch=\(values.count > 2 ? "base64+sha256" : "base64-only")")
        if values.count > 2 {
            XCTAssertEqual(values[2], SecondOpinion.sha256Hex(values[1]),
                           "\(named): step 3 shows \(values[2]), expected this process's SHA-256 of step 2 — "
                               + "a card that renumbered without recomputing looks exactly like this")
        }
        return named
    }

    /// Hashing at its seeded root: one input, four digests at once.
    private func hashingShot(_ named: String, _ appearance: String) -> String {
        launch(Self.pinning(LaunchState.hashingDestination, format: Self.htmlFormat), appearance)
        let source = fillFromExample(AccessibilityIdentifiers.Hashing.useExample,
                                     reading: AccessibilityIdentifiers.Hashing.input)
        gate(named, cards: 1, sources: Self.hashingCells.map { ValueSource($0, 1) },
             surface: AccessibilityIdentifiers.Hashing.digestSHA512, input: .hashing)
        assertRendersText(element(AccessibilityIdentifiers.Hashing.digestSHA256), SecondOpinion.sha256Hex(source),
                          "\(named): the SHA-256 row, against this process's own digest of the input")
        return named
    }

    /// Timestamps at its seeded root in the pinned `UTC` zone: one instant, three representations.
    private func timestampsShot(_ named: String, _ appearance: String) -> String {
        launch(Self.pinning(LaunchState.timestampsDestination, format: Self.htmlFormat), appearance)
        let source = fillFromExample(AccessibilityIdentifiers.Timestamps.useExample,
                                     reading: AccessibilityIdentifiers.Timestamps.input)
        // `Timestamps.cell.*` carry NO identifier while empty — `OutputBlock.swift:65-73` attaches on
        // the `.value` branch alone, so all three count 0 at launch and 1 after the tap above. A wait
        // assuming launch-time existence fails here and passes on Hashing: it looks like flake.
        let values = gate(named, cards: 1, sources: Self.timestampsCells.map { ValueSource($0, 1) },
                          surface: AccessibilityIdentifiers.Timestamps.cellISO8601, input: .timestamps)
        XCTAssertEqual(values[0], source,
                       "\(named): the epoch cell shows \(values[0]) against an input of \(source) — the "
                           + "`unixEpoch` read-as pin did not take")
        return named
    }

    /// Encode/decode at its seeded single step with **format = URL** — the cold-open state, and a
    /// third conversion family beside shot 01's HTML (01 is this surface mid-work, not this state).
    private func encodeURLShot(_ named: String, _ appearance: String) -> String {
        launch(Self.pinning(LaunchState.encodeDestination, format: Self.urlFormat), appearance)
        let source = fillFromExample(AccessibilityIdentifiers.Encode.useExample,
                                     reading: AccessibilityIdentifiers.Encode.input)
        let values = gate(named, cards: 1, sources: [ValueSource(AccessibilityIdentifiers.Encode.output, 1)],
                          surface: AccessibilityIdentifiers.Encode.output, input: .encode)
        XCTAssertEqual(values[0], SecondOpinion.percentEncoded(source),
                       "\(named): the root card shows \(values[0]), expected this process's percent-encoding "
                           + "— so this tile is not the URL format it claims to be")
        return named
    }

    // MARK: - The seven capture-time preconditions

    /// Assertions 1-7, all of them, before any tile is filed — returning what it read, in source
    /// order, so a caller can relate the values without a second query.
    ///
    /// **EVERYTHING IS MEASURED AND RECORDED BEFORE ANYTHING IS JUDGED.** `continueAfterFailure` is
    /// false here, so an assertion placed before the evidence line takes the evidence line with it —
    /// and the numbers that would explain the failure are exactly the ones lost.
    ///
    /// `input` is the SURFACE'S OWN input identifier, named by each shot the way `surface:` already
    /// is. It is the head of the pipeline, and until ASSERTION 7 existed nothing required it to be
    /// in the photograph at all.
    @discardableResult
    private func gate(_ shot: String, cards: Int, sources: [ValueSource], surface: String, input: SurfaceInput) -> [String] {
        let rendered = count(surface)
        let found = count(AccessibilityIdentifiers.Step.card)
        let matched = sources.map { count($0.identifier) }
        let measure = frameShot(shot, sources: sources, input: input)
        let visible = measure.band
        let seen = values(sources)
        let texts = seen.map(\.text)
        let ident = AccessibilityIdentifiers.Shell.privacyPolicy
        let controls = app.buttons.matching(identifier: ident).count // pressable population, not nodes
        let blocked = count(AccessibilityIdentifiers.Step.blocked)
        let outside = seen.filter { $0.frame.isEmpty || !visible.contains($0.frame) }
        record("shot=\(shot) cards=\(found) surface=\(rendered) population=\(matched) values=\(texts.count) "
            + "lengths=\(texts.map(\.count)) outside=\(outside.count) blocked=\(blocked) "
            + "privacy_pressable=\(controls) privacy_nodes=\(count(ident)) "
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

        // 1 — THE DRIVE LANDED. This is 1 at launch on every surface, so a chain shot whose taps
        // silently did nothing is refused here rather than filed.
        XCTAssertEqual(found, cards, "\(shot) ASSERTION 1 (cards): \(found) step cards on the surface, expected "
            + "\(cards) — the drive did nothing and this is the launch state")

        // 2 — THE POPULATION, EACH IDENTIFIER'S CONTRIBUTION ON ITS OWN, and only then the union.
        for (index, source) in sources.enumerated() {
            XCTAssertEqual(matched[index], source.expected, "\(shot) ASSERTION 2 (population): \(matched[index]) "
                + "elements carry \(source.identifier), expected \(source.expected)")
        }
        // AND EVERY VALUE INSIDE THE VISIBLE CONTENT AREA, not merely inside the window: a card under
        // the tab bar is in the accessibility tree and not in the photograph. An EMPTY frame counts as
        // outside — `CGRect.contains` answers false for one, and so does this message.
        XCTAssertTrue(outside.isEmpty, "\(shot) ASSERTION 2 (inside the frame): \(outside.count) of \(seen.count) "
            + "values are outside the visible content area \(describeRect(visible)): "
            + "\(outside.map { describeRect($0.frame) }.joined(separator: " ")) — this tile shows fewer values "
            + "than it claims to")

        // 7 — AND THE HEAD OF THE PIPELINE IS IN THE PHOTOGRAPH. The clause assertion 2 could not
        // state, and the one this gate went without: four of eight iPhone tiles shipped with the
        // input field and the "Step 1 <name>" header scrolled off the top while every VALUE was
        // inside the band and every assertion was green. ASSERTION 2 IS UNTOUCHED ABOVE — the
        // population being judged is WIDENED, and a widening paid for by a loosening would
        // re-create the same defect under a different name. Stated in `ScreenshotFraming.swift`.
        assertHeadInFrame(shot, measure)

        // 3 — AND READABLE AND PAIRWISE DISTINCT. Three empty reads are distinct from nothing and
        // identical to each other; `assertDistinctReadable` reports those as two different failures.
        assertDistinctReadable(texts, expected: texts.count, "\(shot): the values this tile is about")

        // 4 — THE PRIVACY CONTROL IS IN THE SHOT IT WILL SHIP IN. Counted over the PRESSABLE
        // population: one iOS navigation-bar item publishes a wrapper AND a button at nearly the same
        // frame (08-11), so an unscoped count answers 2 for ONE control. That number is recorded
        // beside this one rather than asserted.
        XCTAssertEqual(controls, 1, "\(shot) ASSERTION 4 (privacy): \(controls) pressable controls carry \(ident), "
            + "expected exactly 1 in the tile that ships")

        // 6 — AND NOTHING ON SCREEN IS AN ERROR CARD.
        XCTAssertEqual(blocked, 0, "\(shot) ASSERTION 6 (blocked): \(blocked) cards are blocked — this tile is a "
            + "screenshot of a broken pipeline")

        return texts
    }

    // `contentBounds()`, `frames(_:)`, `values(_:)` and `scrollValuesIntoFrame(_:head:)` MOVED to
    // `ScreenshotFraming.swift`, with their measurements carried across verbatim, beside ASSERTION 7
    // and the fit arithmetic they now share. The move is the 400-line file budget `swiftlint --strict`
    // enforces (UL-056), the same reason `ScreenshotValues.swift` and the macOS twin's
    // `ScreenshotDriver.swift` exist. Nothing was deleted to make room.

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

    /// A fresh application, pinned, in the requested appearance. `+=` throughout: `setupSnapshot`
    /// appends fastlane's own arguments and an assignment here would drop them.
    private func launch(_ pinning: [String], _ appearance: String) {
        app = XCUIApplication()
        composition = "appended=0 retracted=0"
        setupSnapshot(app)
        app.launchArguments += ["-UITestColorScheme", appearance]
        app.launchArguments += pinning
        app.launch()
    }

    /// Fill a surface's input from its worked-value control and hand back what the field holds, read
    /// from the tree rather than spelled here: `InputExample` is app code this process cannot link.
    private func fillFromExample(_ control: String, reading field: String) -> String {
        let button = element(control)
        XCTAssertTrue(button.waitForExistence(timeout: 30), "no worked-value control carries \(control)")
        button.tap()
        let text = (element(field).value as? String) ?? ""
        XCTAssertFalse(text.isEmpty, "the worked-value control left \(field) empty, so every value below this "
            + "would be about the empty string")
        return text
    }

    /// Open an add-step control and choose the item at `menuIndex` — having first proven the menu's
    /// population is `Operation.allCases.count` AND that the index resolves to `title`.
    /// `Pipeline.appending(_:)` always appends to the END (`Pipeline.swift:150`), so which control is
    /// tapped does not decide where the step lands; index 0 is the root's.
    private func addStep(_ menuIndex: Int, _ title: String) {
        let controls = all(AccessibilityIdentifiers.Step.addStep)
        XCTAssertTrue(controls.element(boundBy: 0).waitForExistence(timeout: 20), "no add-step control on the surface")
        controls.element(boundBy: 0).tap()

        let items = all(AccessibilityIdentifiers.Step.addStepMenu)
        XCTAssertTrue(items.element(boundBy: menuIndex).waitForExistence(timeout: 20),
                      "the add-step menu presented no item at index \(menuIndex)")
        let population = items.count
        XCTAssertEqual(population, Self.operationCount,
                       "the menu presented \(population) items, expected Operation.allCases.count = \(Self.operationCount)")
        let item = items.element(boundBy: menuIndex)
        XCTAssertEqual(assertReadable(item, "the add-step menu item at index \(menuIndex)"), title,
                       "menu index \(menuIndex) resolves to something other than \(title) — `Operation.allCases` has "
                           + "been reordered and this chain is not the chain it says it is")
        item.tap()
    }

    /// Every element carrying `identifier`, whatever kind of element it is.
    func all(_ identifier: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: identifier)
    }

    /// How many elements carry `identifier` right now — one round trip, never a doomed wait.
    func count(_ identifier: String) -> Int {
        all(identifier).count
    }

    func element(_ identifier: String) -> XCUIElement {
        all(identifier).firstMatch
    }

    /// One measured line, emitted twice — `print` for a local run and an `XCTContext` activity, which
    /// is the channel that reaches the `.xcresult`.
    func record(_ line: String) {
        print(line)
        XCTContext.runActivity(named: line) { _ in }
    }
}
