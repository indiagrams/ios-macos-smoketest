import XCTest

// THE DRIVING HALF of `AppStoreScreenshotTests` — launching, filling, appending, the head
// population, the fit arithmetic, the retraction and the framing scroll. All by IDENTIFIER and
// never by visible text. `ScreenshotContract.swift` carries the contract and the measurement TYPES;
// the class file carries the shots and the gate. AN EXTENSION IN A SECOND FILE, the shape
// `SweepDriver.swift` already uses: `swiftlint --strict` promotes the 400-line WARNING to an error.
//
// **THE ARITHMETIC BELOW IS THE iOS TWIN'S, NAME FOR NAME** (`app/UITests/ScreenshotFraming.swift`).
// `headIdentifiers`, `chainSources`, `fit`, `frameShot`, `retractChainToFit` and `scrollToTop` mean
// the same thing on both platforms and are spelled the same way, so a divergence is a defect rather
// than a platform difference. What genuinely differs is the SCROLL PRIMITIVE — ``wheel(_:)`` — and
// every platform difference in this file is concentrated there.
//
// C-25: Swift 5.9 / `SWIFT_STRICT_CONCURRENCY: minimal`, like every file in this target.

extension AppStoreScreenshotTests {
    /// All five settings keys; surface and encode format chosen by the caller.
    static func pinning(_ surface: String, format: String) -> [String] {
        [
            LaunchState.selectionKey, surface,
            LaunchState.encodeFormatKey, format,
            LaunchState.encodeDirectionKey, LaunchState.forwardDirection,
            LaunchState.timestampsReadAsKey, LaunchState.epochReadAs,
            LaunchState.timestampsTimeZoneKey, LaunchState.fixedTimeZone
        ]
    }

    /// A fresh application, pinned, in the requested appearance, at the requested POINT size.
    /// `activate()` so the window comes to front: without it the window may launch behind others
    /// and XCUITest's window queries return nothing on a real Mac with other GUI apps running.
    func launch(_ pinning: [String], _ appearance: String) {
        app = XCUIApplication()
        failuresBefore = testRun?.totalFailureCount ?? 0
        composition = "appended=0 retracted=0"
        scrollSign = 1
        scrollTargetIndex = 0
        scrollCalibrated = false
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
    /// **Also the per-shot RENDER GUARD**, on THAT surface's own identifier rather than shot 01's:
    /// a window can exist before SwiftUI has drawn into it, which is how a screenshot of an empty
    /// frame gets captured and uploaded.
    @discardableResult
    func fillFromExample(_ control: String, reading field: String) -> String {
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

    /// Open an add-step control, choose the item at `menuIndex`, and prove the step that LANDED is
    /// the one that was asked for — see `ScreenshotContract.swift` §"the menu item is unreadable".
    ///
    /// **THE LANDING INDEX FOLLOWS THE TREE RATHER THAN A CONSTANT.** `Pipeline.appending(_:)`
    /// always appends to the END, so the card that landed is the LAST one, read off the surface
    /// after the click. A constant is right only for a composition that never changes, and this
    /// chain's is now decided by ``retractChainToFit(_:head:appended:)``.
    func addStep(_ menuIndex: Int, _ title: String) {
        let before = count(AccessibilityIdentifiers.Step.card)
        let controls = all(AccessibilityIdentifiers.Step.addStep)
        XCTAssertTrue(controls.element(boundBy: 0).waitForExistence(timeout: 20), "no add-step control on the surface")
        controls.element(boundBy: 0).click()

        let items = all(AccessibilityIdentifiers.Step.addStepMenu)
        XCTAssertTrue(items.element(boundBy: menuIndex).waitForExistence(timeout: 20),
                      "the add-step menu presented no item at index \(menuIndex)")
        let population = items.count
        let item = items.element(boundBy: menuIndex)
        // A MEASUREMENT AND NOT AN ASSERTION, emitted whatever its value: every attribute an
        // out-of-process client can ask a macOS menu item for, so the next reader has the answer.
        record("addstep index=\(menuIndex) population=\(population) type=\(item.elementType.rawValue) "
            + "label=\"\(item.label)\" value=\"\((item.value as? String) ?? "")\" title=\"\(item.title)\"")
        XCTAssertEqual(population, Self.operationCount,
                       "the menu presented \(population) items, expected Operation.allCases.count "
                           + "= \(Self.operationCount)")
        item.click()

        let landed = count(AccessibilityIdentifiers.Step.card) - 1
        XCTAssertEqual(landed, before, "the add-step click left \(landed + 1) step cards, expected \(before + 1)")
        let headers = all(AccessibilityIdentifiers.Step.header)
        XCTAssertTrue(headers.element(boundBy: landed).waitForExistence(timeout: 20),
                      "nothing carries \(AccessibilityIdentifiers.Step.header) at card index \(landed)")
        assertRendersText(headers.element(boundBy: landed), title,
                          "the header of the card menu index \(menuIndex) appended — if this is another "
                              + "operation, `Operation.allCases` has been reordered and this chain is not "
                              + "the chain it says it is")
    }

    // MARK: - The band, the two populations, and the arithmetic between them

    /// Every value in `sources`, in source order, frame and text in ONE pass. MOVED here from the
    /// class file UNCHANGED, the move the iOS twin made: the frame reads belong beside the
    /// arithmetic. Assertion 2 still judges this population, filter and message byte-identical.
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

    /// The head of the pipeline, top to bottom: the surface's input LABEL and FIELD, then the first
    /// card's ordinal and operation name.
    ///
    /// **FOUR MEMBERS RATHER THAN THREE, AND THE LABEL IS THE ONE THAT COST A RE-CAPTURE.** The iOS
    /// twin widened this to {field, position, header} first and shipped two tiles with the
    /// navigation bar through the middle of the "Input" letterforms while the clause reported
    /// `outside=0`. `InputArea.swift` is SHARED, so the identifiers were already attached here.
    static func headIdentifiers(_ input: SurfaceInput) -> [String] {
        [input.label, input.field,
         AccessibilityIdentifiers.Step.position, AccessibilityIdentifiers.Step.header]
    }

    /// The TOPMOST element of each head population, with the index that won it. An empty population
    /// yields an EMPTY frame at index -1, which ASSERTION 7 counts as outside — the same rule
    /// assertion 2 applies: `CGRect.contains` answers false for an empty rect, so an element that
    /// is not in the tree cannot be inside the photograph.
    func headElements(_ identifiers: [String]) -> [HeadElement] {
        identifiers.map { identifier in
            let rects = frames(identifier)
            guard let index = topmost(rects) else {
                return HeadElement(identifier: identifier, index: -1, frame: .zero)
            }
            return HeadElement(identifier: identifier, index: index, frame: rects[index])
        }
    }

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

    /// Frame the shot, then hand back what was measured AFTER the scroll settled. Scrolls, measures,
    /// records — and judges nothing, because an assertion above the evidence line takes the evidence
    /// line with it.
    ///
    /// `floor_and_fail` is `!fits` HERE, and that is exact rather than loose: by the time the framing
    /// runs every lever is spent — the chain has retracted to its floor of one appended card, and a
    /// seeded single-card surface never had a lever. Emitted on EVERY shot, so a floor is greppable.
    func frameShot(_ shot: String, sources: [ValueSource], input: SurfaceInput) -> FitMeasurement {
        let identifiers = Self.headIdentifiers(input)
        scrollToTop()
        scrollValuesIntoFrame(sources, head: identifiers)
        let measure = fit(sources, head: identifiers)
        record("frame shot=\(shot) headTop=\(measure.headTop) headTop_by=\(measure.headTopBy) "
            + "tailBottom=\(measure.tailBottom) requiredDelta=\(measure.requiredDelta) "
            + "availableDelta=\(measure.availableDelta) fits=\(measure.fits) "
            + "floor_and_fail=\(!measure.fits) scrollBy=\(measure.scrollBy) "
            + "head=\(measure.describedHead) \(composition) band=\(describeRect(measure.band))")
        return measure
    }

    // MARK: - The scroll primitive, which is the one thing this platform does differently

    /// The bottom of the card stack — the single movement probe every scroll here is measured on.
    /// THE BOTTOM AND NOT THE TOP, because the iOS twin measured XCUITest pinning an element's
    /// reported minY to the window's top edge while leaving its maxY exact (UL-078). Whether this
    /// platform does the same is answered by ``measureScrollResponse(_:)``, not assumed here.
    func cardStackBottom() -> CGFloat? {
        frames(AccessibilityIdentifiers.Step.card).filter { !$0.isEmpty }.map(\.maxY).max()
    }

    /// One WHEEL EVENT asking the CONTENT to RISE by `move` points — negative descends. Returns how
    /// far it actually rose, measured on ``cardStackBottom()``.
    /// **macOS NEEDS `XCUIElement.scroll(byDeltaX:deltaY:)` RATHER THAN A PRESS-AND-DRAG**, because
    /// a mouse drag on a scroll view does not scroll it. UL-079's pan-gesture hysteresis — an iOS
    /// drag delivering `asked - 12` and delivering NOTHING below that — therefore does not transfer
    /// and is not assumed either way: every event records `asked` and `delivered`, and
    /// ``measureScrollResponse(_:)`` probes the small ask deliberately on every chain shot.
    ///
    /// **`app.scrollViews` ANSWERS 2 HERE AND `firstMatch` IS THE WRONG ONE.** A
    /// `NavigationSplitView` publishes the SIDEBAR's scroll view as well as the detail pane's, and a
    /// sidebar holding three rows has nothing to scroll — so a wheel event there succeeds and does
    /// nothing. 08-14 measured four attempts across BOTH SIGNS moving the content by exactly 0.0 pt.
    /// The target is chosen by CONTAINMENT of the card stack, every candidate frame is recorded, and
    /// the card is the fallback because a wheel event reaches the nearest enclosing scroll view
    /// either way. **THE SIGN IS DISCOVERED BY TRIAL, NOT TAKEN FROM A DOC COMMENT.**
    @discardableResult
    func wheel(_ move: CGFloat) -> CGFloat {
        guard abs(move) > 0.01 else { return 0 }
        for _ in 0 ..< (scrollCalibrated ? 1 : Self.discoveryAttempts) {
            guard let before = cardStackBottom(), let target = scrollTarget() else { return 0 }
            target.scroll(byDeltaX: 0, deltaY: scrollSign * move)
            let delivered = before - (cardStackBottom() ?? before)
            record("wheel asked=\(move) delivered=\(delivered) sign=\(scrollSign) "
                + "target=\(scrollTargetIndex) calibrated=\(scrollCalibrated)")
            if delivered != 0, (delivered > 0) == (move > 0) {
                // ONE correctly-signed delivery LOCKS the convention, and the lock is load-bearing
                // rather than an optimisation: a surface already AT its limit answers 0 to a
                // correctly-signed ask, which is indistinguishable from a wrong sign. Without it,
                // `scrollToTop()` at the content origin would flip a proven convention.
                scrollCalibrated = true
                return delivered
            }
            guard !scrollCalibrated else { return delivered }
            if scrollSign > 0 {
                scrollSign = -1
            } else {
                // CLAMPED AT THE INCREMENT SITE, where 08-14's mechanism clamped it. Unbounded, it
                // selects the same element but RECORDS an ordinal naming nothing — RED control A
                // emitted `target=10` for a two-element list, and that is not a measurement.
                scrollSign = 1
                scrollTargetIndex = min(scrollTargetIndex + 1, Self.scrollTargets - 1)
            }
        }
        return 0
    }

    /// The element the next wheel event is delivered on: the scroll view CONTAINING the card stack,
    /// then the card itself. Re-resolved per event and recorded, so a target that stops working is
    /// visible rather than inferred. AN EMPTY POPULATION RETURNS NIL, AND THE RED CONTROL IS WHY:
    /// `element(boundBy: 0)` of a query that matched nothing throws XCUITest's own "No matches
    /// found" — a failure, but an OPAQUE one, raised BEFORE assertion 5 can say the app has not
    /// drawn yet.
    func scrollTarget() -> XCUIElement? {
        guard count(AccessibilityIdentifiers.Step.card) > 0 else { return nil }
        let anchor = all(AccessibilityIdentifiers.Step.card).element(boundBy: 0)
        let rect = anchor.frame
        guard !rect.isEmpty else { return nil }
        let query = app.scrollViews
        let candidates = (0 ..< query.count).map { query.element(boundBy: $0).frame }
        let chosen = candidates.firstIndex { $0.contains(CGPoint(x: rect.midX, y: rect.midY)) }
        record("scroll_target scrollviews=\(candidates.count) chosen=\(chosen.map { "\($0)" } ?? "none") "
            + "index=\(scrollTargetIndex) frames=\(candidates.map(describeRect).joined(separator: ",")) "
            + "anchor=\(describeRect(rect))")
        let targets = [chosen.map { query.element(boundBy: $0) } ?? anchor, anchor]
        XCTAssertEqual(targets.count, Self.scrollTargets, "the target list and its bound disagree")
        return targets[min(scrollTargetIndex, targets.count - 1)]
    }

    /// **THE WHEEL RESPONSE OF THIS PLATFORM, MEASURED RATHER THAN INHERITED.** Emitted on every
    /// chain shot whatever its values, before the retraction, while the content is still taller than
    /// the band. Two asks: a LARGE one clear of any plausible threshold, then a SMALL one at the
    /// magnitude UL-079 measured an iOS drag swallowing whole. THE LARGE ONE FIRST, and the order
    /// is the measurement rather than housekeeping — it is what discovers the sign, so "below the
    /// threshold" cannot be confounded with "the sign was not known yet".
    ///
    /// The card stack's TOP is recorded scrolled and back at the origin, which answers UL-078 here:
    /// if a frame is clipped at the window's top edge the scrolled reading is the shorter one, and
    /// a `headTop` read at any scrolled position would then be optimistic.
    func measureScrollResponse(_ shot: String) {
        guard let origin = cardStackBottom() else { return }
        let large = wheel(Self.largeAsk)
        let small = wheel(Self.smallAsk)
        let scrolled = frames(AccessibilityIdentifiers.Step.card).first.map(describeRect) ?? "none"
        scrollToTop()
        let back = cardStackBottom() ?? origin
        let atOrigin = frames(AccessibilityIdentifiers.Step.card).first.map(describeRect) ?? "none"
        record("wheelprobe shot=\(shot) large_asked=\(Self.largeAsk) large_delivered=\(large) "
            + "small_asked=\(Self.smallAsk) small_delivered=\(small) origin=\(origin) returned=\(back) "
            + "restored=\(abs(back - origin) < 0.5) card0_scrolled=\(scrolled) card0_origin=\(atOrigin)")
    }

    // MARK: - Framing, and the retraction that makes it satisfiable

    /// Move the content so the tail comes into the band — and NEVER so far that the head leaves it.
    ///
    /// **THE CENTRING TARGET IS GONE.** It left half the leftover band BELOW the last value and
    /// scrolled that much further than the shot needed, which is how a chain overflowing the fold by
    /// a little lost its entire head under a TRANSLUCENT title bar. The target is now
    /// `min(requiredDelta, availableDelta)`, and a `requiredDelta` of 0 returns immediately — which
    /// after the retraction is every shot, so this mechanism should now do nothing at all.
    ///
    /// **BIDIRECTIONAL, because the retraction leaves the surface wherever the remove control was.**
    /// NOTHING IS LOOSENED: a span taller than the band returns immediately and assertion 2 reports
    /// it with the frames.
    func scrollValuesIntoFrame(_ sources: [ValueSource], head identifiers: [String]) {
        for attempt in 0 ..< Self.scrollAttempts {
            let measure = fit(sources, head: identifiers)
            let rects = values(sources).map(\.frame).filter { !$0.isEmpty }
            guard let top = rects.map(\.minY).min(), let bottom = rects.map(\.maxY).max() else { return }
            let span = bottom - top
            let headSlack = measure.headTop - (measure.band.minY + Self.scrollMargin)
            let move = headSlack < -0.5 ? headSlack : (measure.requiredDelta > 0.5 ? measure.scrollBy : 0)
            record("frame attempt=\(attempt) span=\(span) headTop=\(measure.headTop) "
                + "headTop_by=\(measure.headTopBy) headSlack=\(headSlack) requiredDelta=\(measure.requiredDelta) "
                + "availableDelta=\(measure.availableDelta) fits=\(measure.fits) scrollBy=\(measure.scrollBy) "
                + "move=\(move) band=\(describeRect(measure.band))")
            guard span <= measure.band.height else { return }
            guard abs(move) > 0.5 else { return }
            record("frame attempt=\(attempt) asked=\(move) moved=\(wheel(move))")
        }
    }

    /// Put the surface back at its content origin — the position every `fit` is measured at.
    func scrollToTop() {
        for _ in 0 ..< Self.scrollAttempts {
            let band = contentBounds()
            guard let before = cardStackBottom() else { return }
            let delivered = wheel(-band.height * 0.8)
            record("scrolltop before=\(before) after=\(cardStackBottom() ?? before) moved=\(delivered)")
            guard delivered < -0.5 else { return }
        }
    }

    /// Bring one control inside the band before it is clicked. A control below the fold has a hit
    /// point the scroll view has not drawn, and the click then lands on whatever IS there.
    func scrollIntoBand(_ target: XCUIElement) {
        for _ in 0 ..< Self.scrollAttempts {
            let band = contentBounds()
            let rect = target.frame
            guard !rect.isEmpty else { return }
            let below = rect.maxY + Self.scrollMargin - band.maxY
            let above = band.minY + Self.scrollMargin - rect.minY
            let move = below > 0 ? below : (above > 0 ? -above : 0)
            guard abs(move) > 0.5 else { return }
            wheel(move)
        }
    }

    /// While the head and the tail cannot share the band, DROP THE LAST APPENDED STEP — and prove
    /// each removal landed, because a silent no-op click and a successful removal are
    /// indistinguishable without the card count. **FLOORED AT ONE APPENDED CARD**: a root-only
    /// surface is not a chain, so the loop stops there rather than filing a one-card "chain" as a
    /// pass, and ``frameShot(_:sources:input:)`` reports the floor. **THE LAST APPEND IS THE ONE
    /// THAT GOES** — the only rule a gate can state mechanically, and it leaves the surviving
    /// chain's recomputation intact.
    func retractChainToFit(_ shot: String, head identifiers: [String], appended: Int) -> Int {
        measureScrollResponse(shot)
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

    /// Click the LAST appended card's remove control, having first brought it inside the band and
    /// asserted the population is long enough to be indexed — the shape `StepEditTests`'
    /// `appendedControl(_:_:)` uses. `Step.remove`'s population is the APPENDED cards only (D-100),
    /// so the last one is at `count - 1`.
    func retractLastAppendedStep(_ shot: String) {
        let controls = all(AccessibilityIdentifiers.Step.remove)
        let population = controls.count
        XCTAssertGreaterThan(population, 0, "\(shot): nothing carries \(AccessibilityIdentifiers.Step.remove), so "
            + "the last appended step cannot be retracted")
        let before = count(AccessibilityIdentifiers.Step.card)
        let last = controls.element(boundBy: population - 1)
        scrollIntoBand(last)
        last.click()
        let after = count(AccessibilityIdentifiers.Step.card)
        XCTAssertEqual(after, before - 1, "\(shot): the retraction click left \(after) step cards, expected "
            + "\(before - 1) — a silent no-op click and a successful removal look identical without this")
    }
}
