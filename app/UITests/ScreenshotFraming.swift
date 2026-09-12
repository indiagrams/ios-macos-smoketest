import XCTest

// THE FRAMING HALF of `AppStoreScreenshotTests` — the band a capture can show, the two populations
// whose frames decide the shot, the arithmetic that replaced centring, and ASSERTION 7.
//
// AN EXTENSION IN A SECOND FILE, the shape `app/MacOSUITests/ScreenshotDriver.swift` already uses
// and the move `app/UITests/ScreenshotValues.swift` made for the same reason: `swiftlint --strict`
// promotes the 400-line file WARNING to an error (UL-056) and the class file is AT that budget.
// Every measurement below cost a capture run; deleting them to save lines is what the split avoids.
//
// AND FOR THE SAME REASON AGAIN, `ScreenshotBand.swift` NOW CARRIES THE MEASUREMENT HALF —
// `HeadElement`, `FitMeasurement`, `contentBounds()`, `frames(_:)`, `values(_:)`, `headElements(_:)`,
// `topmost(_:)` and `fit(_:head:)`. THIS file keeps the MOTION and the JUDGMENT: ASSERTION 7, the
// framing drags, the retraction and `scrollToTop()`. The twin split is `MacOSUITests/ScreenshotBand.swift`.
//
// ══ WHY THIS FILE EXISTS: THE GATE COULD NOT FAIL ON THE DEFECT THAT SHIPPED ══════════════════
//
// `scrollValuesIntoFrame(_:)` used to CENTRE the span of the OUTPUT VALUES in the band, and
// assertion 2 judged that same population and only it. Nothing required the INPUT FIELD or the
// "Step 1 <name>" header to be in the captured frame, so FOUR OF EIGHT iPhone tiles shipped without
// either — 01-chain-light, 03-timestamps-light, 05-chain-dark, 07-timestamps-dark — every assertion
// green. A correct check pointed at the wrong population, in the code producing the lead tiles.
//
// CENTRING IS THE MECHANISM, AND THE ARITHMETIC SAYS SO. It leaves `(band.height - span) / 2` of
// slack BELOW the last value, so it scrolls that much further than the shot needs: on iPhone 16 Pro
// Max (band 772.67) the chain's 685 pt span over-scrolls by 43.8 pt and a 250 pt span by 261 pt —
// which is how a surface overflowing the fold by 2.31 pt loses its entire head.
//
// ══ THE HEAD POPULATION — the elements whose absence IS the defect ════════════════════════════
//
// `<surface>.inputLabel` and `<surface>.input`, then `Step.position` and `Step.header` (EVERY card,
// the root included). `EncodeSurface.swift:253-268`, and the same skeleton in HashingSurface /
// TimestampsSurface, lays out `ScrollView { VStack(spacing: .lg) { InputArea(...); stepStack } }`
// with `.padding(.top, .xl)` — so the input block sits ABOVE the root card rather than inside it,
// and governs `headTop` on every shot of both devices. See `headIdentifiers(_:)` for what the
// LABEL cost before it was in the set. "First" is by SMALLEST minY rather than by index, so
// nothing depends on how XCUITest enumerates the tree, and the winning index is RECORDED.
//
// ══ THE ARITHMETIC, named once and used by the framing, the retraction and ASSERTION 7 ════════
//
//   band           = contentBounds()                   // window minus LOCATED chrome. UNCHANGED.
//   headTop        = min(first Step.card's minY, and every head element's minY)
//   tailBottom     = max(maxY over values(sources))    // the SAME population assertion 2 judges
//   requiredDelta  = max(0, tailBottom - band.maxY)    // how far content must rise to show the tail
//   availableDelta = max(0, headTop - (band.minY + scrollMargin))  // how far before the head clips
//   fits           = requiredDelta <= availableDelta — REARRANGED so a scroll cannot fool it, and
//                    measured at the content origin so a clipped frame cannot either. Both halves
//                    were found by running it; see `FitMeasurement.fits` and `scrollToTop()`.
//
// C-25: Swift 5.9 / `SWIFT_STRICT_CONCURRENCY: minimal`, like every file in this target.

extension AppStoreScreenshotTests {
    /// The head of the pipeline: the surface's input LABEL and FIELD, then the first card's
    /// ordinal and operation name. In that order, which is top-to-bottom on every surface.
    ///
    /// **THE LABEL WAS ADDED AFTER THE FIRST RE-CAPTURE SHIPPED THE DEFECT AGAIN.** Widening the
    /// population from the output values to {field, position, header} left the label just outside
    /// the new boundary, and two tiles came back with the navigation bar through the middle of its
    /// letterforms while ASSERTION 7 reported `outside=0`. It was not lying; it was answering a
    /// narrower question than the one that matters. The head is EVERYTHING THAT SHOWS WHERE THE
    /// PIPELINE STARTS, and a sliced label fails that as surely as a missing field.
    static func headIdentifiers(_ input: SurfaceInput) -> [String] {
        [input.label, input.field,
         AccessibilityIdentifiers.Step.position, AccessibilityIdentifiers.Step.header]
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

        // AND THE SAME FILTER HERE MADE THE SAME SUBSTITUTION. `.filter { !$0.isEmpty }` over a
        // per-card population silently promotes the SECOND card to "the first step card" once the
        // root's frame degenerates, and this clause does not even record which card won. An empty
        // member of a NON-EMPTY population is a card that is not in the photograph — UL-078 clips
        // at the top and NOT at the bottom, so a card below the fold still reports a full frame and
        // this cannot fire on one. Judged before the minimum, so the numbers reach the message.
        let allCards = frames(AccessibilityIdentifiers.Step.card)
        let cardTops = allCards.filter { !$0.isEmpty }.map(\.minY)
        XCTAssertFalse(allCards.contains { $0.isEmpty }, "\(shot) ASSERTION 7 (head): \(allCards.count - cardTops.count) "
            + "of \(allCards.count) step cards have no measurable frame, which above the fold means clipped out of "
            + "the photograph (UL-078) — cards=\(allCards.map(describeRect).joined(separator: ","))")
        guard let cardTop = cardTops.min() else { return }
        XCTAssertGreaterThanOrEqual(cardTop, band.minY, "\(shot) ASSERTION 7 (head): the first step card starts at "
            + "y=\(cardTop), above the visible content area \(describeRect(band)) — this tile does not show where "
            + "the pipeline starts")
    }

    /// Frame the shot, then hand back what was measured AFTER the drags settled. Scrolls, measures,
    /// records — and judges nothing, so that a refusal taken later carries these numbers.
    /// (`continueAfterFailure` is TRUE, so an assertion here would no longer take the evidence line
    /// with it; the load-bearing rule is that every judgment happens before `file(_:)` is called.)
    ///
    /// `floor_and_fail` is `!fits` HERE, and that is exact rather than loose: by the time the
    /// framing runs every lever is spent — the chain has already retracted to its floor of one
    /// appended card, and a seeded single-card surface never had a lever at all — so a surface that
    /// still does not fit has reached the end of what this design can do, and the gate is left to
    /// fail with its numbers. Emitted on EVERY shot, so a floor is greppable rather than inferred.
    func frameShot(_ shot: String, sources: [ValueSource], input: SurfaceInput) -> FitMeasurement {
        let identifiers = Self.headIdentifiers(input)
        scrollToTop()
        // `floor_and_fail` COMES FROM THE ORIGIN MEASUREMENT AND NOT FROM THE POST-SCROLL ONE.
        // `fits` is justified by "`tailBottom - headTop` is invariant under scrolling", which is
        // true only where the frame is not clipped — and UL-078 says iOS is exactly where it is.
        // Measured on this file's own numbers: a shot at `headTop=162.33 tailBottom=950` is at its
        // floor (extent 799.67 against a 772.67 band), and after a 202.67 pt rise that clips the
        // head the reported `headTop=0.0` understates the extent to 759.33 and `fits` reads TRUE —
        // so `floor_and_fail=!fits` recorded FALSE for a shot that is at its floor. The honest
        // extent after the rise is 799.67, identical to the origin's, which is the invariance the
        // clip breaks. `fits` on the line still reports the geometry ASSERTION 7 is about.
        let atOrigin = fit(sources, head: identifiers)
        scrollValuesIntoFrame(sources, head: identifiers)
        let measure = fit(sources, head: identifiers)
        record("frame shot=\(shot) headTop=\(measure.headTop) headTop_by=\(measure.headTopBy) "
            + "tailBottom=\(measure.tailBottom) requiredDelta=\(measure.requiredDelta) "
            + "availableDelta=\(measure.availableDelta) fits=\(measure.fits) "
            + "origin_headTop=\(atOrigin.headTop) origin_fits=\(atOrigin.fits) "
            + "floor_and_fail=\(!atOrigin.fits) scrollBy=\(measure.scrollBy) "
            + "head=\(measure.describedHead) \(composition) band=\(describeRect(measure.band))")
        return measure
    }

    /// One drag of `move` points of CONTENT movement — positive rises, negative descends.
    ///
    /// **A DRAG DELIVERS `asked - hysteresis`, AND DELIVERS NOTHING AT ALL BELOW IT.** Measured
    /// twice in one run: an ask of 389.48 moved 379.67, short by 9.81; an ask of 2.31 moved 0.00,
    /// six attempts in a row. That is how the first green run failed on a tile whose own arithmetic
    /// said it fitted — `fits=true requiredDelta=2.31 availableDelta=50.0`, and the value stayed
    /// 2.31 pt below the fold because the gesture never began. `UIPanGestureRecognizer` consumes a
    /// fixed translation before a scroll view starts, so the ask is the wanted movement PLUS that
    /// constant. NOTHING IS LOOSENED: `move` is still bounded by `availableDelta`, and the
    /// hysteresis is spent before any content moves.
    ///
    /// **AND THE HOLD IS LOAD-BEARING.** A two-argument press-and-drag releases with velocity, the
    /// scroll view throws a fling, and the correcting drag flings back past the target: a capture
    /// run failed on its first pass and passed on fastlane's retry with the root value at y=5.31,
    /// which is an OSCILLATION rather than a shortfall (UL-074). With `thenHoldForDuration` the
    /// finger stays down, the scroll view samples zero velocity at release, and no fling is thrown.
    /// Where the finger goes down, as a fraction of the SCREEN's height. Named rather than spelled
    /// at the two places that now need it: the coordinate and the room that coordinate leaves.
    static let gripOffset: CGFloat = 0.6

    func drag(_ move: CGFloat, within band: CGRect) {
        // **THE CLAMP GOES ON THE MOVEMENT AND THE COMPENSATION GOES OUTSIDE IT.** Clamping the ask
        // deleted the compensation on exactly the call that needs it most: `scrollToTop()` asks
        // `-618.13`, the ask becomes `-630.13`, and `max(-618.13, -630.13)` is `-618.13` — the whole
        // 12 pt is gone and every descent under-delivers by the full hysteresis. Bounding `move`
        // first and adding the compensation after is what the doc comment above already claims
        // happens: the ask is the wanted movement PLUS the constant, never a clamp applied to both.
        //
        // **AND THE BOUND IS WHAT THE GESTURE CAN PHYSICALLY DELIVER, WHICH IS THE SCREEN'S ROOM
        // AND NOT `band.height`.** The grip sits at 0.6 of the screen, so a descent has only
        // `screen.maxY - gripY` beneath it. On iPhone 16 Pro Max that is 382.4 pt against a
        // `band.height * 0.8` of 618.13, and the end point computed from the band lands at y=1191.73
        // on a 956 pt screen — 235.73 pt PAST its edge; on iPad, 1856 on 1376, off by 480. The
        // delivered movement was therefore capped by the screen rather than by the clamp the code
        // computes, so `asked` and `moved` could never be reconciled and `scrollToTop()` could
        // exhaust its six attempts without reaching the origin — the ONE position where
        // ``scrollToTop()`` says the head's frame can be believed. Bounded here, the same call
        // lands at y=944.0 with `scrollMargin` to spare and converges in ONE attempt of six.
        let screen = app.frame
        let gripY = screen.minY + screen.height * Self.gripOffset
        let room = move > 0 ? gripY - screen.minY : screen.maxY - gripY
        let bound = max(0, min(band.height * 0.8, room - Self.scrollMargin - Self.dragHysteresis))
        let step = max(-bound, min(bound, move)) + (move > 0 ? Self.dragHysteresis : -Self.dragHysteresis)
        let grip = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: Self.gripOffset))
        grip.press(forDuration: 0.1, thenDragTo: grip.withOffset(CGVector(dx: 0, dy: -step)),
                   withVelocity: .slow, thenHoldForDuration: 0.4)
    }

    /// Move the content so the tail comes into the band — and NEVER so far that the head leaves it.
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
            // FILTERED, WHICH IS WHAT THE macOS TWIN ALWAYS DID AND WHAT `ScreenshotDriver.swift:118`
            // CLAIMS THIS LINE ALREADY DID ("filter and message byte-identical"). Unfiltered, an
            // element reporting an empty frame — the documented `Timestamps.cell.*` case, which
            // carries no identifier while empty — puts its `0` into `top`: span becomes 820 against
            // a 772.67 band, `guard span <= band.height` RETURNS on attempt 0, and the shot is never
            // framed at all. The same unfiltered read made `moved=` garbage on the evidence line.
            let rects = values(sources).map(\.frame).filter { !$0.isEmpty }
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

            drag(move, within: measure.band)
            let moved = top - (values(sources).map(\.frame).filter { !$0.isEmpty }.map(\.minY).min() ?? top)
            record("frame attempt=\(attempt) asked=\(move) moved=\(moved)")
        }
    }

    /// While the head and the tail cannot share the band, DROP THE LAST APPENDED STEP — and prove
    /// each removal landed, because a silent no-op click and a successful removal are
    /// indistinguishable without the card count. **FLOORED AT ONE APPENDED CARD**: a root-only
    /// surface is not a chain, so the loop stops there rather than filing a one-card "chain" as a
    /// pass, and ``frameShot(_:sources:input:)`` reports the floor. **THE LAST APPEND IS THE ONE
    /// THAT GOES**, because dropping the last is the only rule a gate can state mechanically and it
    /// leaves the surviving chain's recomputation intact.
    func retractChainToFit(_ shot: String, head identifiers: [String], appended: Int) -> Int {
        var surviving = appended
        for _ in 0 ..< appended {
            scrollToTop()
            let measure = fit(Self.chainSources(surviving), head: identifiers)
            record("retract shot=\(shot) appended=\(appended) surviving=\(surviving) "
                + "headTop=\(measure.headTop) headTop_by=\(measure.headTopBy) tailBottom=\(measure.tailBottom) "
                + "requiredDelta=\(measure.requiredDelta) availableDelta=\(measure.availableDelta) "
                + "fits=\(measure.fits) floor_and_fail=\(!measure.fits && surviving <= 1) "
                + "measurable=\(measure.measurable) "
                + "head=\(measure.describedHead) band=\(describeRect(measure.band))")
            // NOTHING DESTRUCTIVE IS DECIDED ON NUMBERS NOTHING MEASURED. `fit()` defaults an
            // empty tail population to `band.maxY` and an empty head to `band.minY`, and `fits`
            // — which is what taps the remove control — was computed from those inventions
            // without ever knowing they were inventions. With an empty tail it collapses to
            // `headTop >= band.minY + scrollMargin`, a statement about the HEAD alone: on a
            // surface the add-step interaction has left scrolled that reads FALSE, a real card is
            // permanently removed, and `AppStoreScreenshotTests.swift:150-153` says degrading that
            // tile "would be a regression caused by the fix, and is refused". Assertions 2 and 7
            // still refuse the shot afterwards; this stops it losing a card on the way.
            guard measure.measurable else {
                record("retract shot=\(shot) unmeasurable — no card is removed on a defaulted measurement")
                break
            }
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
        // A GUARD RATHER THAN AN ASSERTION, because `continueAfterFailure` is TRUE here. This used
        // to abort the method; now it records and falls straight through into
        // `controls.element(boundBy: population - 1)`. On a population of 0 that is `boundBy: -1`,
        // which `scrollIntoBand(last)`'s `target.frame` resolves and XCUITest answers with its
        // OPAQUE "no matches found" — ending the test METHOD and taking the tiles for the shots
        // after it, which is the exact regression flipping the flag to `true` was meant to prevent.
        guard population > 0 else {
            return XCTFail("\(shot): nothing carries \(AccessibilityIdentifiers.Step.remove), so the last "
                + "appended step cannot be retracted")
        }
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
        for attempt in 0 ..< Self.scrollAttempts {
            let band = contentBounds()
            guard let before = frames(AccessibilityIdentifiers.Step.card).map(\.maxY).max() else { return }
            drag(-band.height * 0.8, within: band)
            let after = frames(AccessibilityIdentifiers.Step.card).map(\.maxY).max() ?? before
            record("scrolltop attempt=\(attempt) before=\(before) after=\(after) moved=\(after - before)")
            // The probe is the BOTTOM of the card stack, which is the end XCUITest does not clip.
            guard after - before > 0.5 else { return }
        }
        // FALLING OUT OF THE LOOP MEANS THE LAST ATTEMPT WAS STILL DESCENDING, which is the ONE
        // outcome this function must not pass over in silence: every `headTop` measured afterwards
        // is optimistic by the clipped amount (UL-078), and a `fits` computed from it can answer
        // TRUE for a composition that does not fit. Reachable, and not only in principle — content
        // taller than six times the per-attempt bound reaches it. Today's compositions converge in
        // ONE attempt of six on iPhone and zero on iPad, so this has roughly threefold headroom.
        XCTFail("the surface was still descending after \(Self.scrollAttempts) attempts, so it is NOT at its "
            + "content origin and every head measurement taken from here is optimistic (UL-078)")
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
            drag(move, within: band)
        }
    }

    // MARK: - Driving, all of it by identifier and never by visible text
    //
    // MOVED from the class file, which is at the 400-line budget `swiftlint --strict` enforces
    // (UL-056). This is also where the macOS twin keeps them — `ScreenshotDriver.swift` carries
    // `fillFromExample` and `addStep` — so the move restores a symmetry rather than inventing
    // one. INTERNAL rather than private for the reason the class file already gives for `app`:
    // an extension in another file cannot see a `private` member.

    /// Fill a surface's input from its worked-value control and hand back what the field holds, read
    /// from the tree rather than spelled here: `InputExample` is app code this process cannot link.
    func fillFromExample(_ control: String, reading field: String) -> String {
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
    func addStep(_ menuIndex: Int, _ title: String) {
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
}
