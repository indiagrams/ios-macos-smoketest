import XCTest

// THE BAND A CAPTURE CAN SHOW, AND THE HEAD POPULATION MEASURED AGAINST IT.
//
// A THIRD FILE FOR THE SAME ONE REASON THE SECOND EXISTS, recorded so it is not mistaken for
// taste: `swiftlint --strict` promotes the 400-line file WARNING to an error (UL-056), and
// `ScreenshotFraming.swift` reached that budget. The alternative was deleting the measurements
// written in its comments, each of which cost a capture run. `ScreenshotValues.swift` carries the
// same note for the same reason, and the macOS twin splits three ways already.
//
// THE SUBJECT IS THE MEASUREMENT AND NOT THE MOTION: what area the photograph covers, which
// elements are the head of the pipeline, where each of them is, and what room lies between the
// head and the tail. Nothing here scrolls and nothing here judges — `ScreenshotFraming.swift`
// does the framing and the retraction, and `AppStoreScreenshotTests.swift` takes the verdicts.
// Everything below was MOVED verbatim out of `ScreenshotFraming.swift`; no behaviour changed in
// the move, and the twin members live in `app/MacOSUITests/ScreenshotBand.swift`.
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

    /// BOTH POPULATIONS WERE ACTUALLY FOUND. False means `headTop` or `tailBottom` below
    /// is a DEFAULT and not a measurement, so `fits` is an answer about nothing — and
    /// `fits` drives a DESTRUCTIVE action. See ``retractChainToFit(_:head:appended:)``.
    let measurable: Bool

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
        // AND THE BAND MAY NOT BE DERIVED FROM CHROME THAT WAS NEVER LOCATED. The `guard … continue`
        // above is SILENT AND PERMISSIVE: a bar not in the tree at that instant leaves `top` at the
        // window's own edge and the band GROWS to swallow the chrome strip. This is the assertion
        // four lines up — 'inside the frame' would be a comparison against nothing — applied to the
        // edge that actually decides the verdict, which is where it was simply not applied before.
        //
        // ON THIS PLATFORM IT IS A TAUTOLOGY AND NOT MERELY A WIDENING. UL-078 pins a top-clipped
        // element's reported `minY` to EXACTLY the window's top edge, which is then exactly
        // `band.minY`, so BOTH clauses of ASSERTION 7 reduce to `0 >= 0` and the shipped defect —
        // the navigation bar through the middle of the "Input" letterforms — files with
        // `outside=0`. Driven red on that input: `nav` absent, `tab=bottom(0,873,440,83)`,
        // `band=(0,0,440,873)`, label reported at `(28,0,384,46)`, both clauses TRUE, tile FILED.
        //
        // THE TOP SPECIFICALLY, NOT `bars.isEmpty`: a run locating the BOTTOM tab bar alone has a
        // NON-empty `bars` and a raw-window top, so an emptiness check would pass on the exact
        // input that breaks the gate. Every recorded run of both devices located top chrome —
        // iPhone `nav=top(0,56.33,440,44)`, iPad `nav=top(0,24,1032,64)` — so this refuses nothing
        // that has ever been captured, and a tile it wrongly refuses is merely absent.
        XCTAssertGreaterThan(top, bounds.minY, "no chrome was located at the top of the window, so the band is "
            + "the raw window and 'inside the frame' cannot fail on a top-clipped element (UL-078) — \(chrome)")
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

    /// The index of the rect with the smallest `minY` — **EMPTY RECTS RANKED FIRST**, because a
    /// member that cannot be measured is not a member that can be skipped.
    ///
    /// **SKIPPING THEM MADE THIS FUNCTION ANSWER ABOUT A DIFFERENT CARD.** `Step.position` and
    /// `Step.header` have ONE ELEMENT PER CARD, so "ignoring empty ones" meant "the topmost card
    /// that still has a measurable frame" and not "the root card". Driven red on a two-card chain
    /// scrolled so the ROOT header is fully above the window top (an empty rect, UL-078) while the
    /// APPENDED header is inside the band: the clause answered with the appended card's
    /// `(40,420,200,22)`, `band.contains` was TRUE, and ASSERTION 7 reported `outside=0` for a
    /// tile whose root header is not in the photograph. Ranked first, it answers `#0(0,0,0,0)`,
    /// which ASSERTION 7 already counts as outside, and `outside=2`.
    ///
    /// A NON-EMPTY POPULATION IS STILL ORDERED BY GEOMETRY and not by query order, so nothing
    /// depends on how XCUITest enumerates the tree; an ENTIRELY empty array still yields nil and
    /// the `index: -1` sentinel. The only input whose answer changes is the mixed one.
    func topmost(_ rects: [CGRect]) -> Int? {
        if let unmeasurable = rects.firstIndex(where: { $0.isEmpty }) { return unmeasurable }
        return rects.enumerated().min { $0.element.minY < $1.element.minY }?.offset
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
        // EMPTINESS IS REPRESENTABLE RATHER THAN DEFAULTED. `?? band.maxY` and `?? band.minY`
        // are INVENTIONS, and `fits` — which drives the retraction's destructive tap — was
        // computed from them without ever knowing the populations were empty. With an empty
        // tail, `fits` collapses to `headTop >= band.minY + scrollMargin`: a statement about
        // the HEAD alone, with nothing to do with whether the tail fits.
        let tails = values(sources).map(\.frame).filter { !$0.isEmpty }.map(\.maxY)
        let tailBottom = tails.max() ?? band.maxY
        let requiredDelta = max(0, tailBottom - band.maxY)
        // AN UNMEASURABLE HEAD MEMBER CLAMPS THE BOUND RATHER THAN VANISHING FROM IT. `candidates`
        // FILTERS empty frames out of `headTop`, so the member that is ALREADY pushed out of frame
        // is the one member excluded from the measurement that decides how far the head may be
        // pushed. Driven red on the input UL-078 produces: with `Encode.inputLabel` fully above the
        // window top its frame degenerates to zero height, it is dropped, `headTop` reports the
        // FIELD's 162.33 instead, and `availableDelta` reads the recorded run's own 50.0 — licensing
        // the next drag to rise 50 pt further while the label is already gone. Clamped, `scrollBy`
        // is `min(requiredDelta, 0)` and nothing rises at all until the head can be measured.
        // INERT when every member is measurable, which is every recorded run.
        let unmeasurableHead = head.contains { $0.frame.isEmpty }
        let availableDelta = unmeasurableHead ? 0 : max(0, headTop - (band.minY + Self.scrollMargin))
        return FitMeasurement(band: band, head: head, headTop: headTop, headTopBy: winner?.0 ?? "none",
                              tailBottom: tailBottom, requiredDelta: requiredDelta,
                              availableDelta: availableDelta, scrollBy: min(requiredDelta, availableDelta),
                              measurable: winner != nil && !tails.isEmpty)
    }
}
