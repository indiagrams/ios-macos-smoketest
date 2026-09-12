import XCTest

// THE FRAMING HALF of `AppStoreScreenshotTests` — the band a capture can show, the two populations
// whose frames decide the shot, the arithmetic that replaced centring, and ASSERTION 7.
//
// AN EXTENSION IN A SECOND FILE, the shape `app/MacOSUITests/ScreenshotDriver.swift` already uses
// and the move `app/UITests/ScreenshotValues.swift` made for the same reason: `swiftlint --strict`
// promotes the 400-line file WARNING to an error (UL-056) and the class file is AT that budget.
// The measurements below are carried across VERBATIM from the functions that moved here; each one
// cost a capture run, and deleting them to save lines is the thing the split exists to avoid.
//
// ══ WHY THIS FILE EXISTS: THE GATE COULD NOT FAIL ON THE DEFECT THAT SHIPPED ══════════════════
//
// `scrollValuesIntoFrame(_:)` used to CENTRE the span of the OUTPUT VALUES in the visible band,
// and assertion 2 judged that same population and only it. Nothing required the INPUT FIELD or the
// "Step 1 <name>" header to be inside the captured frame, so FOUR OF EIGHT iPhone tiles shipped
// without either — 01-chain-light, 03-timestamps-light, 05-chain-dark, 07-timestamps-dark — with
// every assertion green. A correct check pointed at the wrong population, in the code that
// produces the store's lead tiles.
//
// CENTRING IS THE MECHANISM, AND THE ARITHMETIC SAYS SO EXACTLY. Centring leaves a slack of
// `(band.height - span) / 2` BELOW the last value, so it scrolls that much FURTHER than the shot
// needs. On iPhone 16 Pro Max (band 772.67 pt) the chain's 685 pt span over-scrolls by 43.8 pt and
// a 250 pt span over-scrolls by 261 pt — which is how a surface whose values overflow the fold by
// 2.31 pt loses its entire head. The replacement moves by `min(requiredDelta, availableDelta)` and
// therefore never moves further than the head can afford.
//
// ══ THE HEAD POPULATION — the elements whose absence IS the defect ════════════════════════════
//
//   <surface>.input  one per surface. `EncodeSurface.swift:253-268`, and the same skeleton in
//                    HashingSurface / TimestampsSurface, lays out
//                    `ScrollView { VStack(spacing: Spacing.lg) { InputArea(...); stepStack } }`
//                    with `.padding(.top, Spacing.xl)` — so the FIELD sits ABOVE the root card
//                    rather than inside it, and is expected to govern `headTop` on every surface.
//   Step.position    EVERY card, the root included (`AccessibilityIdentifiers.swift:235-241`).
//   Step.header      every card (`StepCard.swift:185`).
//
// "First" is taken by SMALLEST minY rather than by index, so nothing here depends on how XCUITest
// happens to enumerate the tree — and the index that won is RECORDED, so a surprise is a
// measurement rather than a silent wrong pick.
//
// ══ THE ARITHMETIC, named once and used by the framing, the retraction and ASSERTION 7 ════════
//
//   band           = contentBounds()                    // window minus LOCATED chrome. UNCHANGED.
//   headTop        = min(first Step.card's minY, and every head element's minY)
//   tailBottom     = max(maxY over values(sources))     // the SAME population assertion 2 judges
//   requiredDelta  = max(0, tailBottom - band.maxY)     // how far content must rise to show the tail
//   availableDelta = max(0, headTop - (band.minY + scrollMargin))  // how far before the head clips
//   fits           = requiredDelta <= availableDelta
//
// `fits` is INVARIANT UNDER SCROLLING — a drag of d lowers both deltas by d and `max(0, ·)` is
// monotone — so it can be evaluated BEFORE the framing rather than after. That is what lets the
// chain settle its own composition before anything is judged.
//
// C-25: Swift 5.9 / `SWIFT_STRICT_CONCURRENCY: minimal`, like every file in this target.

/// One member of the head population: what it is called, WHICH element of that population won it,
/// and where that element was found. The index is carried so the evidence line can say it.
struct HeadElement {
    let identifier: String
    let index: Int
    let frame: CGRect
}

/// One measurement of whether the head of the pipeline and the tail of it can share the band, and
/// of how far the content may rise. Nothing here judges; ``AppStoreScreenshotTests`` does that.
struct FitMeasurement {
    let band: CGRect
    let head: [HeadElement]
    let headTop: CGFloat
    let headTopBy: String
    let tailBottom: CGFloat
    let requiredDelta: CGFloat
    let availableDelta: CGFloat
    let scrollBy: CGFloat

    /// The head and the tail can share the band. False is not a failure here — it is what makes
    /// the chain retract, and only when the chain has nothing left to retract does it reach a gate.
    ///
    /// **STATED AS AN EXTENT RATHER THAN AS `requiredDelta <= availableDelta`, and the two are the
    /// SAME PREDICATE at the top of the scroll view:**
    ///
    ///       requiredDelta <= availableDelta
    ///     ⟺ tailBottom - band.maxY <= headTop - band.minY - scrollMargin
    ///     ⟺ (tailBottom - headTop) + scrollMargin <= band.height
    ///
    /// The rearranged form is the one that SURVIVES A SCROLL, and that is not a refinement — it is
    /// a bug fix. Both deltas clamp at zero, so once the surface has been scrolled past
    /// `requiredDelta` — which is exactly where the retraction's own `scrollIntoBand` leaves it —
    /// the delta form reads `0 <= 0` and answers TRUE for a composition that does not fit. A
    /// measurement that cannot answer false, inside the loop whose whole job is to decide the
    /// composition. `tailBottom - headTop` is invariant under scrolling, so this form cannot.
    var fits: Bool {
        (tailBottom - headTop) + AppStoreScreenshotTests.scrollMargin <= band.height
    }

    /// Every head element as `identifier#index(x,y,w,h)`, so a failure NAMES what was missing.
    var describedHead: String {
        head.map { "\($0.identifier)#\($0.index)\(describeRect($0.frame))" }.joined(separator: ",")
    }
}

extension AppStoreScreenshotTests {
    // MARK: - The two populations

    /// The head of the pipeline on a surface whose input carries `input`.
    static func headIdentifiers(_ input: String) -> [String] {
        [input, AccessibilityIdentifiers.Step.position, AccessibilityIdentifiers.Step.header]
    }

    /// The chain's value population for a surface carrying `appended` appended cards: ONE
    /// `Encode.output` from the seeded root and one `Step.output` per appended card. MEASURED, not
    /// assumed — `EncodeSurface.swift:169` passes `valueIdentifier: Encode.output` into the seeded
    /// card's `OutputBlock` and only the APPENDED cards keep the default, so a gate counting three
    /// `Step.output` would be a correct check pointed at the wrong population.
    static func chainSources(_ appended: Int) -> [ValueSource] {
        [
            ValueSource(AccessibilityIdentifiers.Encode.output, 1),
            ValueSource(AccessibilityIdentifiers.Step.output, appended)
        ]
    }

    /// The area a capture can actually show: the window minus the chrome at its top and bottom.
    ///
    /// **Both bars are located rather than assumed**, because how `TabView` renders on iPadOS 18
    /// with the legacy `.tabItem` API — bottom tab bar or top bar — was open when this was written.
    /// A bar centred in the upper half cuts the top, anything else cuts the bottom, and which
    /// branch was taken lands in ``chrome`` so the answer comes out of the run. It came out as the
    /// iPadOS 18 TOP bar: every iPad shot records `chrome=nav=top(0,24,1032,64)` and NO `tab=`
    /// entry at all, against the iPhone's `tab=bottom(0,873,440,83)`.
    func contentBounds() -> CGRect {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 30),
                      "no window resolved, so 'inside the frame' would be a comparison against nothing")
        let bounds = window.frame
        var top = bounds.minY
        var bottom = bounds.maxY
        var bars: [String] = []
        for bar in [("nav", app.navigationBars.firstMatch), ("tab", app.tabBars.firstMatch)] {
            guard bar.1.exists, !bar.1.frame.isEmpty else { continue }
            let rect = bar.1.frame
            if rect.midY < bounds.midY {
                top = max(top, rect.maxY)
                bars.append("\(bar.0)=top\(describeRect(rect))")
            } else {
                bottom = min(bottom, rect.minY)
                bars.append("\(bar.0)=bottom\(describeRect(rect))")
            }
        }
        chrome = "window=\(describeRect(bounds)) chrome=\(bars.isEmpty ? "none" : bars.joined(separator: ","))"
        return CGRect(x: bounds.minX, y: top, width: bounds.width, height: bottom - top)
    }

    /// Every frame carrying `identifier`, for the evidence line.
    func frames(_ identifier: String) -> [CGRect] {
        let query = all(identifier)
        return (0 ..< query.count).map { query.element(boundBy: $0).frame }
    }

    /// Every value in `sources`, in source order, with the frame and the text read in ONE pass.
    func values(_ sources: [ValueSource]) -> [(frame: CGRect, text: String)] {
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

    /// The TOPMOST element of each head population, with the index that won it. An empty
    /// population yields an EMPTY frame at index -1, which ASSERTION 7 counts as outside — the
    /// same rule assertion 2 applies, and for the same reason: `CGRect.contains` answers false for
    /// an empty rect, so an element that is not in the tree cannot be inside the photograph.
    func headElements(_ identifiers: [String]) -> [HeadElement] {
        identifiers.map { identifier in
            let rects = frames(identifier)
            guard let index = topmost(rects) else {
                return HeadElement(identifier: identifier, index: -1, frame: .zero)
            }
            return HeadElement(identifier: identifier, index: index, frame: rects[index])
        }
    }

    /// The index of the rect with the smallest `minY`, ignoring empty ones — "first" by GEOMETRY
    /// rather than by tree order.
    func topmost(_ rects: [CGRect]) -> Int? {
        rects.enumerated()
            .filter { !$0.element.isEmpty }
            .min { $0.element.minY < $1.element.minY }?
            .offset
    }

    // MARK: - The fit arithmetic

    /// One measurement of the head, the tail and the room between them, at the CURRENT scroll
    /// position. Nothing is judged and nothing is moved.
    func fit(_ sources: [ValueSource], head identifiers: [String]) -> FitMeasurement {
        let band = contentBounds()
        let head = headElements(identifiers)
        var candidates = head.filter { !$0.frame.isEmpty }.map { ($0.identifier, $0.frame.minY) }
        if let card = frames(AccessibilityIdentifiers.Step.card).filter({ !$0.isEmpty }).map(\.minY).min() {
            candidates.append((AccessibilityIdentifiers.Step.card, card))
        }
        let winner = candidates.min { $0.1 < $1.1 }
        let headTop = winner?.1 ?? band.minY
        let tailBottom = values(sources).map(\.frame).filter { !$0.isEmpty }.map(\.maxY).max() ?? band.maxY
        let requiredDelta = max(0, tailBottom - band.maxY)
        let availableDelta = max(0, headTop - (band.minY + Self.scrollMargin))
        return FitMeasurement(band: band, head: head, headTop: headTop, headTopBy: winner?.0 ?? "none",
                              tailBottom: tailBottom, requiredDelta: requiredDelta,
                              availableDelta: availableDelta, scrollBy: min(requiredDelta, availableDelta))
    }

    // MARK: - ASSERTION 7

    /// **ASSERTION 7 (head) — the head of the pipeline is in the photograph.** Two clauses, and the
    /// second is the macOS blurred-half-line in its general form: content clipped at the TOP is the
    /// defect, content continuing past the bottom fold is not.
    ///
    /// IT DOES NOT REPLACE ASSERTION 2 AND IT DOES NOT SOFTEN IT. A tile must satisfy BOTH — the
    /// population is being WIDENED, and widening paid for by loosening would re-create the defect
    /// under a different name.
    func assertHeadInFrame(_ shot: String, _ measure: FitMeasurement) {
        let band = measure.band
        let outside = measure.head.filter { $0.frame.isEmpty || !band.contains($0.frame) }
        XCTAssertTrue(outside.isEmpty, "\(shot) ASSERTION 7 (head): \(outside.count) of \(measure.head.count) head "
            + "elements are outside the visible content area \(describeRect(band)): "
            + "\(outside.map { "\($0.identifier)\(describeRect($0.frame))" }.joined(separator: " ")) — this tile "
            + "does not show where the pipeline starts")

        let cardTops = frames(AccessibilityIdentifiers.Step.card).filter { !$0.isEmpty }.map(\.minY)
        guard let cardTop = cardTops.min() else { return }
        XCTAssertGreaterThanOrEqual(cardTop, band.minY, "\(shot) ASSERTION 7 (head): the first step card starts at "
            + "y=\(cardTop), above the visible content area \(describeRect(band)) — this tile does not show where "
            + "the pipeline starts")
    }

    // MARK: - The framing, and the retraction that lets it succeed

    /// Frame the shot, then hand back what was measured AFTER the drags settled. Scrolls, measures,
    /// records — and judges nothing, because `continueAfterFailure` is false and an assertion above
    /// the evidence line takes the evidence line with it.
    func frameShot(_ shot: String, sources: [ValueSource], input: String) -> FitMeasurement {
        let identifiers = Self.headIdentifiers(input)
        scrollToTop()
        scrollValuesIntoFrame(sources, head: identifiers)
        let measure = fit(sources, head: identifiers)
        record("frame shot=\(shot) headTop=\(measure.headTop) headTop_by=\(measure.headTopBy) "
            + "tailBottom=\(measure.tailBottom) requiredDelta=\(measure.requiredDelta) "
            + "availableDelta=\(measure.availableDelta) fits=\(measure.fits) scrollBy=\(measure.scrollBy) "
            + "head=\(measure.describedHead) \(composition) band=\(describeRect(measure.band))")
        return measure
    }

    /// Move the content so the tail comes into the band — and NEVER so far that the head leaves it.
    ///
    /// **THE HOLD IS LOAD-BEARING AND IT IS NOT COSMETIC.** A two-argument press-and-drag releases
    /// with velocity, the scroll view throws a fling, and the correcting drag flings back past the
    /// target: a capture run failed on its first pass and passed on fastlane's retry with the root
    /// value at y=5.31, which is an OSCILLATION rather than a shortfall (UL-074). With
    /// `thenHoldForDuration` the finger stays down, the scroll view samples zero velocity at
    /// release, and no fling is thrown.
    ///
    /// **BIDIRECTIONAL, because the retraction leaves the surface wherever the remove control
    /// was.** A rise-only framing would photograph a head that a previous drag had already pushed
    /// off the top. So a clipped head is put back FIRST and the tail is brought up second, which
    /// converges: after the descent `headTop` sits at `band.minY + scrollMargin`, and the rise is
    /// bounded by exactly that slack.
    ///
    /// NOTHING IS LOOSENED: a value span taller than the band returns immediately, and assertion 2
    /// reports it with the frames that prove it.
    func scrollValuesIntoFrame(_ sources: [ValueSource], head identifiers: [String]) {
        for attempt in 0 ..< Self.scrollAttempts {
            let measure = fit(sources, head: identifiers)
            let rects = values(sources).map(\.frame)
            guard let top = rects.map(\.minY).min(), let bottom = rects.map(\.maxY).max() else { return }
            let span = bottom - top
            // EXACT IN BOTH DIRECTIONS, because ``scrollToTop()`` has already put the surface at
            // its content origin: the rise is bounded by `availableDelta` and therefore cannot clip
            // the head, and the descent exists only to correct a drag that overshot.
            let headSlack = measure.headTop - (measure.band.minY + Self.scrollMargin)
            let move = headSlack < -0.5 ? headSlack : (measure.requiredDelta > 0.5 ? measure.scrollBy : 0)
            record("frame attempt=\(attempt) span=\(span) headTop=\(measure.headTop) "
                + "headTop_by=\(measure.headTopBy) headSlack=\(headSlack) requiredDelta=\(measure.requiredDelta) "
                + "availableDelta=\(measure.availableDelta) fits=\(measure.fits) scrollBy=\(measure.scrollBy) "
                + "move=\(move) band=\(describeRect(measure.band))")
            guard span <= measure.band.height else { return }
            guard abs(move) > 0.5 else { return }

            let step = max(-measure.band.height * 0.8, min(measure.band.height * 0.8, move))
            let grip = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            grip.press(forDuration: 0.1, thenDragTo: grip.withOffset(CGVector(dx: 0, dy: -step)),
                       withVelocity: .slow, thenHoldForDuration: 0.4)
            let moved = top - (values(sources).map(\.frame).map(\.minY).min() ?? top)
            record("frame attempt=\(attempt) asked=\(step) moved=\(moved)")
        }
    }

    /// While the head and the tail cannot share the band, DROP THE LAST APPENDED STEP — and prove
    /// each removal landed, because a silent no-op click and a successful removal are
    /// indistinguishable without the card count.
    ///
    /// **FLOORED AT ONE APPENDED CARD.** A root-only surface is not a chain, so the loop stops
    /// there and lets the gate fail with its numbers rather than filing a one-card "chain" as a
    /// pass. `floor_and_fail=true` on the record is that state, named so it is greppable.
    ///
    /// **THE LAST APPEND IS THE ONE THAT GOES**, because dropping the last is the only rule a gate
    /// can state mechanically and it leaves the surviving chain's recomputation intact.
    func retractChainToFit(_ shot: String, head identifiers: [String], appended: Int) -> Int {
        var surviving = appended
        for _ in 0 ..< appended {
            scrollToTop()
            let measure = fit(Self.chainSources(surviving), head: identifiers)
            record("retract shot=\(shot) appended=\(appended) surviving=\(surviving) "
                + "headTop=\(measure.headTop) headTop_by=\(measure.headTopBy) tailBottom=\(measure.tailBottom) "
                + "requiredDelta=\(measure.requiredDelta) availableDelta=\(measure.availableDelta) "
                + "fits=\(measure.fits) floor_and_fail=\(!measure.fits && surviving <= 1) "
                + "head=\(measure.describedHead) band=\(describeRect(measure.band))")
            guard !measure.fits, surviving > 1 else { break }
            retractLastAppendedStep(shot)
            surviving -= 1
        }
        composition = "appended=\(appended) retracted=\(appended - surviving)"
        record("composition shot=\(shot) \(composition) cards=\(count(AccessibilityIdentifiers.Step.card))")
        return surviving
    }

    /// Tap the LAST appended card's remove control, having first brought it inside the band and
    /// asserted the population is long enough to be indexed — the shape `StepEditTests`'
    /// `appendedControl(_:_:)` uses, and for the same reason.
    private func retractLastAppendedStep(_ shot: String) {
        let controls = all(AccessibilityIdentifiers.Step.remove)
        let population = controls.count
        XCTAssertGreaterThan(population, 0, "\(shot): nothing carries \(AccessibilityIdentifiers.Step.remove), so "
            + "the last appended step cannot be retracted")
        let before = count(AccessibilityIdentifiers.Step.card)
        let last = controls.element(boundBy: population - 1)
        scrollIntoBand(last)
        last.tap()
        let after = count(AccessibilityIdentifiers.Step.card)
        XCTAssertEqual(after, before - 1, "\(shot): the retraction tap left \(after) step cards, expected "
            + "\(before - 1) — a silent no-op click and a successful removal look identical without this")
    }

    /// Put the surface back at its content origin, which is the ONLY position where the head's
    /// frame can be believed.
    ///
    /// **XCUITest CLIPS AN ELEMENT'S FRAME AT THE WINDOW'S TOP EDGE AND NOT AT ITS BOTTOM.**
    /// Measured 2026-09-11, both halves inside one run, on `Encode.input`:
    ///
    ///     at the content origin   (28.0, 162.33, 384.0, 86.33)   maxY 248.67
    ///     scrolled 202.67 down    (28.0,   0.00, 384.0, 46.00)   maxY  46.00
    ///
    /// The true minY there is -40.33. The reported minY is pinned to ZERO and the height cut by
    /// exactly the 40.33 pt above the edge, so the maxY stays exact. Downwards there is no such
    /// clip: at the origin the chain's third value reports maxY=1218.64 in a 956 pt window, 262 pt
    /// below the fold, untouched.
    ///
    /// **SO A `headTop` READ AT A SCROLLED POSITION IS OPTIMISTIC, AND `fits` READS TRUE FOR A
    /// COMPOSITION THAT DOES NOT FIT.** The floor control measured exactly that: after one
    /// retraction the chain reported `headTop=0.0 fits=true` where the honest extent was 40.33 pt
    /// larger and false. Stating `fits` as an extent removed the clamp-at-zero half of that
    /// problem; only measuring at the origin removes the clipped-frame half. Both halves were
    /// found by running the thing, not by reading it.
    func scrollToTop() {
        for _ in 0 ..< Self.scrollAttempts {
            let band = contentBounds()
            guard let before = frames(AccessibilityIdentifiers.Step.card).map(\.maxY).max() else { return }
            let grip = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            grip.press(forDuration: 0.1, thenDragTo: grip.withOffset(CGVector(dx: 0, dy: band.height * 0.8)),
                       withVelocity: .slow, thenHoldForDuration: 0.4)
            let after = frames(AccessibilityIdentifiers.Step.card).map(\.maxY).max() ?? before
            record("scrolltop before=\(before) after=\(after) moved=\(after - before)")
            // The probe is the BOTTOM of the card stack, which is the end XCUITest does not clip.
            guard after - before > 0.5 else { return }
        }
    }

    /// Bring one control inside the band before it is tapped. A control below the fold has a hit
    /// point the scroll view has not drawn, and the tap then lands on whatever IS there.
    private func scrollIntoBand(_ target: XCUIElement) {
        for _ in 0 ..< Self.scrollAttempts {
            let band = contentBounds()
            let rect = target.frame
            guard !rect.isEmpty else { return }
            let below = rect.maxY + Self.scrollMargin - band.maxY
            let above = band.minY + Self.scrollMargin - rect.minY
            let move = below > 0 ? below : (above > 0 ? -above : 0)
            guard abs(move) > 0.5 else { return }
            let step = max(-band.height * 0.8, min(band.height * 0.8, move))
            let grip = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            grip.press(forDuration: 0.1, thenDragTo: grip.withOffset(CGVector(dx: 0, dy: -step)),
                       withVelocity: .slow, thenHoldForDuration: 0.4)
        }
    }
}
