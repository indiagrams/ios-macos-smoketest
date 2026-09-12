import XCTest

// THE BAND A CAPTURE CAN SHOW, AND THE HEAD POPULATION MEASURED AGAINST IT — the twin of
// `app/UITests/ScreenshotBand.swift`, member for member.
//
// A FOURTH FILE FOR THE ONE REASON THE OTHER THREE EXIST, recorded so it is not mistaken for
// taste: `swiftlint --strict` promotes the 400-line file WARNING to an error (UL-056), and
// `ScreenshotDriver.swift` was AT that budget while `AppStoreScreenshotTests.swift` was within
// twelve lines of it. The alternative was deleting the measurements written in their comments,
// each of which cost a capture run.
//
// THE SUBJECT IS THE MEASUREMENT AND NOT THE MOTION: what area the photograph covers, which
// elements are the head of the pipeline, where each of them is, and what room lies between the
// head and the tail. Nothing here scrolls and nothing here judges — `ScreenshotDriver.swift`
// does the driving, the framing and the retraction, `ScreenshotContract.swift` carries the
// contract, and `AppStoreScreenshotTests.swift` takes the verdicts. Everything below was MOVED
// verbatim out of those three files; no behaviour changed in the move.

/// One member of the head population: what it is called, WHICH element of that population won it,
/// and where that element was found. The index is carried so the evidence line can say it.
struct HeadElement {
    let identifier: String
    let index: Int
    let frame: CGRect
}

/// One measurement of whether the head of the pipeline and the tail of it can share the band, and
/// of how far the content may rise. Nothing here judges; ``AppStoreScreenshotTests`` does that.
///
/// The iOS twin's ``FitMeasurement`` is this type field for field, deliberately: the two harnesses
/// are twins and a divergence in the arithmetic would be a defect rather than a platform
/// difference. What genuinely differs on this platform is the SCROLL PRIMITIVE — wheel events
/// rather than press-and-drag — and that lives in `ScreenshotDriver.swift`, not here.
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
    /// The rearranged form is the one that SURVIVES A SCROLL. Both deltas clamp at zero, so once
    /// the surface has been scrolled past `requiredDelta` the delta form reads `0 <= 0` and
    /// answers TRUE for a composition that does not fit — a measurement that cannot answer false,
    /// inside the loop whose whole job is to decide the composition. The iOS twin measured exactly
    /// that (plan 08-20, commit `020d974`). `tailBottom - headTop` is invariant under scrolling.
    var fits: Bool {
        (tailBottom - headTop) + AppStoreScreenshotTests.scrollMargin <= band.height
    }

    /// Every head element as `identifier#index(x,y,w,h)`, so a failure NAMES what was missing.
    var describedHead: String {
        head.map { "\($0.identifier)#\($0.index)\(describeRect($0.frame))" }.joined(separator: ",")
    }
}

extension AppStoreScreenshotTests {
    /// The band a capture can actually show: the window minus any chrome LOCATED at its top.
    /// Measured rather than assumed — on this platform the title bar does not overlay content, so
    /// subtracting it is conservative, and what was found lands in ``chrome`` and comes out of the
    /// run rather than out of this sentence.
    func contentBounds() -> CGRect {
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
        // AND THE BAND MAY NOT BE DERIVED FROM CHROME THAT WAS NEVER LOCATED — the assertion four
        // lines up, applied to the edge that decides the verdict. The `where` clause is SILENT AND
        // PERMISSIVE: a toolbar not in the tree at that instant leaves `top` at the window's own
        // edge and the 52 pt TRANSLUCENT title strip is back inside the band, which is this
        // platform's half of the defect the UAT found by cropping the title band. The failing input
        // is concrete here: `privacyItemsInTheAppMenu`'s `app.activate()` can return before the
        // window is front again, and `frameShot` takes its geometry immediately afterwards.
        //
        // WHAT DIFFERS FROM iOS: there is NO TAUTOLOGY on this platform. UL-082 measured
        // `Encode.inputLabel(372.0,-94.97,27.0,14.0)` — a NEGATIVE origin with FULL height — where
        // UIKit would have pinned minY to 0 and cut the height, so a head pushed clear of the window
        // still fails `band.contains` even against the raw-window band. What the fallback re-admits
        // here is the strip itself: driven red on a head at y=118, which is inside
        // `(144,102,1440,900)` and outside the real `(144,154,1440,848)`, and which renders as a
        // blurred half-line under the window title rather than as a clean crop. Every recorded run
        // located `toolbar=top(144,102,1440,52)`, so this refuses nothing already captured.
        XCTAssertGreaterThan(top, bounds.minY, "no chrome was located at the top of the window, so the band is "
            + "the raw window and the 52 pt translucent title strip is inside it — \(chrome)")
        return CGRect(x: bounds.minX, y: top, width: bounds.width, height: bounds.maxY - top)
    }

    /// Every frame carrying `identifier`, for the evidence line.
    func frames(_ identifier: String) -> [CGRect] {
        let query = all(identifier)
        return (0 ..< query.count).map { query.element(boundBy: $0).frame }
    }

    /// The index of the rect with the smallest `minY` — "first" by GEOMETRY and not by query
    /// order, so the head population does not depend on how XCUITest enumerates — with **EMPTY
    /// RECTS RANKED FIRST**, because a member that cannot be measured is not one that can be
    /// skipped.
    ///
    /// **SKIPPING THEM MADE THIS FUNCTION ANSWER ABOUT A DIFFERENT CARD.** `Step.position` and
    /// `Step.header` have ONE ELEMENT PER CARD, so "ignoring empty ones" meant "the topmost card
    /// that still has a measurable frame" rather than "the root card": with the root's member
    /// unmeasurable and the appended card's inside the band, the clause answered about the SECOND
    /// card and reported `outside=0`. The iOS twin's finding, carried across — the twins must not
    /// diverge on the head population, whichever route produces the unmeasurable frame.
    func topmost(_ rects: [CGRect]) -> Int? {
        if let unmeasurable = rects.firstIndex(where: { $0.isEmpty }) { return unmeasurable }
        return rects.enumerated().min { $0.element.minY < $1.element.minY }?.offset
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
        // AN UNMEASURABLE HEAD MEMBER CLAMPS THE BOUND RATHER THAN VANISHING FROM IT — the iOS
        // twin's finding, carried across because the twins must not diverge on the arithmetic.
        // `candidates` FILTERS empty frames out of `headTop`, so the member that is already out of
        // frame is the one excluded from the measurement deciding how far the head may be pushed.
        // The clip that produces an empty frame is UIKit's (UL-078) and not this platform's, so the
        // input arrives differently here — an identifier not yet published, a surface not yet drawn
        // — but the bound is wrong in the same direction, and ASSERTION 7 refuses the tile either
        // way. INERT when every member is measurable, which is every recorded run.
        let unmeasurableHead = head.contains { $0.frame.isEmpty }
        let availableDelta = unmeasurableHead ? 0 : max(0, headTop - (band.minY + Self.scrollMargin))
        return FitMeasurement(band: band, head: head, headTop: headTop, headTopBy: winner?.0 ?? "none",
                              tailBottom: tailBottom, requiredDelta: requiredDelta,
                              availableDelta: availableDelta, scrollBy: min(requiredDelta, availableDelta))
    }
}
