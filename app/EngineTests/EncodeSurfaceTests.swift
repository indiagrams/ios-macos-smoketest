// EncodeSurfaceTests — all six composed operation names, ENUMERATED AND
// RENDERED, and the two selections proven to live where D-82 requires.
//
// WHY SIX AND NOT A COUNT. "The header changes with the pickers" is satisfied
// by a function that returns the same key twice as easily as by one that
// returns six distinct keys, so the assertion below names the expected key for
// each of the six pairs INDIVIDUALLY, checks the six are distinct as a set, and
// then resolves each one through the string catalog and compares the rendered
// sentence to 06-UI-SPEC.md's inventory character for character. A total-only
// assertion would pass on three keys reached twice — the same shape 06-13 was
// tightened for.
//
// AND WHY THE RENDERED NAME MATTERS RATHER THAN THE KEY ALONE.
// `NSLocalizedString` returns the KEY on a miss, so a header wired to a key the
// catalog does not carry renders `op.url.decode` on screen, non-empty and
// distinct from its neighbours. Only comparing against the approved English
// sentence catches that.

import Testing

/// The Encode/decode surface's composition and its selections.
@Suite("Encode surface")
@MainActor
struct EncodeSurfaceTests {
    /// One of the six pairs and the key it must compose.
    ///
    /// A named value rather than a three-member tuple, which `swiftlint
    /// --strict` rejects — measured, not predicted.
    private struct Pair {
        let format: EncodeFormat
        let direction: EncodeDirection
        let key: String
    }

    /// The six pairs, spelled out one by one.
    private static let pairs: [Pair] = [
        Pair(format: .base64, direction: .encode, key: "op.base64.encode"),
        Pair(format: .base64, direction: .decode, key: "op.base64.decode"),
        Pair(format: .url, direction: .encode, key: "op.url.encode"),
        Pair(format: .url, direction: .decode, key: "op.url.decode"),
        Pair(format: .html, direction: .encode, key: "op.html.encode"),
        Pair(format: .html, direction: .decode, key: "op.html.decode")
    ]

    /// The approved English name each key renders — 06-UI-SPEC.md §"Add-step
    /// menu", which is the same table the card headers draw from.
    private static let approvedNames: [String: String] = [
        "op.base64.encode": "Base64 encode",
        "op.base64.decode": "Base64 decode",
        "op.url.encode": "URL encode",
        "op.url.decode": "URL decode",
        "op.html.encode": "HTML encode",
        "op.html.decode": "HTML decode"
    ]

    @Test("each of the six format x direction pairs composes its own header key")
    func eachPairComposesItsOwnHeaderKey() {
        #expect(Self.pairs.count == 6)
        for pair in Self.pairs {
            let composed = encodeHeaderKey(format: pair.format, direction: pair.direction)
            #expect(composed == pair.key, "\(pair.format) x \(pair.direction) composed \(composed)")
        }
        #expect(Set(Self.pairs.map(\.key)).count == 6)
    }

    @Test("the six composed keys are exactly the six codec operations, as a set")
    func theSixKeysAreExactlyTheSixCodecOperations() {
        let composed = Set(Self.pairs.map { encodeHeaderKey(format: $0.format, direction: $0.direction) })
        let codecs = Set(Operation.allCases.prefix(6).map(\.rawValue))
        #expect(composed == codecs)
    }

    @Test("all six headers render their approved name, not their key")
    func allSixHeadersRenderTheirApprovedName() {
        var rendered: [String] = []
        for pair in Self.pairs {
            let key = encodeHeaderKey(format: pair.format, direction: pair.direction)
            let name = localizedSentence(key: key)
            #expect(name == Self.approvedNames[key], "\(key) rendered as \(name)")
            #expect(name != key, "\(key) rendered as its own key")
            rendered.append(name)
        }
        // encode_headers_covered=6
        #expect(Set(rendered).count == 6)
    }

    @Test("the picker labels and every segment title are real catalog entries")
    func thePickerLabelsAndSegmentsResolve() {
        let expected: [String: String] = [
            "encode.picker.format": "Format",
            "encode.picker.direction": "Direction",
            "encode.format.base64": "Base64",
            "encode.format.url": "URL",
            "encode.format.html": "HTML",
            "encode.direction.encode": "Encode",
            "encode.direction.decode": "Decode"
        ]
        for (key, sentence) in expected {
            let rendered = localizedSentence(key: key)
            #expect(rendered == sentence, "\(key) rendered as \(rendered)")
        }
        // The segment titles ARE the enum raw values, so the picker cannot
        // offer a title the catalog does not carry.
        #expect(EncodeFormat.allCases.map(\.rawValue) == ["encode.format.base64", "encode.format.url", "encode.format.html"])
        #expect(EncodeDirection.allCases.map(\.rawValue) == ["encode.direction.encode", "encode.direction.decode"])
    }

    @Test("the two selections live on the model, and the header follows them")
    func theSelectionsLiveOnTheModelAndTheHeaderFollows() {
        let model = AppModel.isolated()
        // D-09: the surface is seeded, and this is the operation it is seeded
        // with — the first card a user ever sees says "Base64 encode".
        #expect(encodeHeaderKey(format: model.encodeFormat, direction: model.encodeDirection) == "op.base64.encode")

        model.encodeFormat = .html
        model.encodeDirection = .decode
        // D-82: the pair the view renders is read back off the model, which is
        // what survives a macOS sidebar swap discarding the detail view.
        #expect(encodeHeaderKey(format: model.encodeFormat, direction: model.encodeDirection) == "op.html.decode")
    }

    @Test("the seeded card and an appended card chain, and the chain halts on a failure")
    func theSeededCardAndAnAppendedCardChain() {
        let model = AppModel.isolated()
        model.encode.input = InputExample.encode

        // The surface composes [seeded] + the appended steps and evaluates
        // once; this is that composition, with nothing appended yet.
        let seeded = Step(operation: model.encodeFormat.operation(model.encodeDirection))
        let alone = Pipeline(input: model.encode.input, steps: [seeded]).evaluate()
        #expect(alone == [.value("SGVsbG8sIHdvcmxkICYgPGNhZsOpPiE=")])

        // APP-08 at the model layer: appending seeds the new step with the
        // output above it, so the second card shows the CHAINED result.
        model.encode = model.encode.appending(.base64Decode)
        let chained = Pipeline(input: model.encode.input, steps: [seeded] + model.encode.steps).evaluate()
        #expect(chained == [.value("SGVsbG8sIHdvcmxkICYgPGNhZsOpPiE="), .value(InputExample.encode)])

        // D-84: a failing step halts the chain and everything below it is
        // blocked rather than blank or stale.
        model.encodeDirection = .decode
        let halted = Pipeline(
            input: model.encode.input,
            steps: [Step(operation: model.encodeFormat.operation(model.encodeDirection))] + model.encode.steps
        ).evaluate()
        #expect(halted.count == 2)
        #expect(halted.last == .blocked)
    }

    // MARK: - The footer's arithmetic (plan 07-08)

    /// A name for each render state, so a case can assert WHICH state it drove
    /// without pattern-matching inside an expectation.
    private func stateName(_ state: StepRenderState) -> String {
        switch state {
        case .empty: "empty"
        case .value: "value"
        case .failure: "failure"
        case .blocked: "blocked"
        }
    }

    /// A stack of `count` appended `.base64Encode` cards over a non-empty
    /// input, read back through the SURFACE.
    ///
    /// `appendedCards` is what the view actually renders, so an off-by-one
    /// introduced between the model and the render is visible here.
    /// `Pipeline`'s own splice and swap are covered by `PipelineTests`; this
    /// suite covers the surface's composition of a synthesised root plus the
    /// appended steps, which is the part `Pipeline` cannot see.
    private func surface(appending count: Int) -> EncodeSurface {
        let model = AppModel.isolated()
        model.encode = Pipeline(
            input: InputExample.encode,
            steps: (0 ..< count).map { _ in Step(operation: .base64Encode) }
        )
        return EncodeSurface(model: model)
    }

    @Test("the ends rule holds at both ends, for stacks of one, two and five")
    func theEndsRuleHoldsAtBothEndsForThreeStackLengths() {
        for length in [1, 2, 5] {
            let cards = surface(appending: length).appendedCards
            #expect(cards.count == length, "a stack of \(length) rendered \(cards.count) appended cards")
            #expect(!cards.isEmpty)

            // The topmost appended card must not rise: it sits directly under
            // the pinned root, which carries no footer controls at all (D-100).
            #expect(cards.first?.position.canMoveUp == false)
            // The bottom card must not sink.
            #expect(cards.last?.position.canMoveDown == false)

            // Everything strictly between the ends goes both ways. A stack of
            // one has no such card, which is why one, two and five are all
            // asserted rather than one convenient length.
            let middle = cards.dropFirst().dropLast()
            #expect(middle.count == max(length - 2, 0))
            for card in middle {
                let position = card.position
                #expect(position.canMoveUp)
                #expect(position.canMoveDown)
            }

            // The degenerate stack: one card is BOTH ends, and both answers
            // must still be false. An off-by-one at either end shows up here
            // before it shows up anywhere else.
            if length == 1 {
                #expect(cards.first?.position.canMoveDown == false)
                #expect(cards.last?.position.canMoveUp == false)
            }
        }
    }

    /// One driven case: the state it was built to reach, and the middle card
    /// that reached it.
    private struct DrivenCard {
        let expected: String
        let card: AppendedStepCard
    }

    /// The four render states, each driven at the SAME appended index, so the
    /// enablement answers can be compared with nothing else varying.
    ///
    /// `.decode` on the root makes the ROOT fail, which blocks every appended
    /// card below it — the only way an appended card reaches `.blocked` on this
    /// surface without a second failing step confusing the comparison.
    private func middleCards() -> [DrivenCard] {
        Self.drivers.compactMap { driver in
            let model = AppModel.isolated()
            model.encodeDirection = driver.direction
            model.encode = Pipeline(input: driver.input, steps: driver.steps.map { Step(operation: $0) })
            let middle = EncodeSurface(model: model).appendedCards.dropFirst().first
            return middle.map { DrivenCard(expected: driver.expected, card: $0) }
        }
    }

    /// One setup and the state it exists to drive the MIDDLE card into.
    ///
    /// A named value rather than a four-member tuple, which `swiftlint
    /// --strict` rejects at three — measured here, exactly as the `Pair` type
    /// above records it being measured in Phase 6.
    private struct Driver {
        let expected: String
        let input: String
        let direction: EncodeDirection
        let steps: [Operation]
    }

    /// The four setups, one per render state, all three cards deep.
    private static let drivers: [Driver] = [
        Driver(expected: "empty", input: "", direction: .encode,
               steps: [.base64Encode, .base64Encode, .base64Encode]),
        Driver(expected: "value", input: InputExample.encode, direction: .encode,
               steps: [.base64Encode, .base64Encode, .base64Encode]),
        Driver(expected: "failure", input: InputExample.encode, direction: .encode,
               steps: [.base64Decode, .base64Decode, .htmlEncode]),
        Driver(expected: "blocked", input: InputExample.encode, direction: .decode,
               steps: [.base64Encode, .base64Encode, .base64Encode])
    ]

    @Test("footer enablement is identical across empty, value, failure and blocked")
    func footerEnablementIsIdenticalAcrossAllFourRenderStates() {
        let driven = middleCards()
        #expect(driven.count == 4, "one of the four render states could not be driven at all")
        #expect(!driven.isEmpty)

        // EXISTENCE BEFORE INDEPENDENCE. Four cases that all landed in the same
        // state would make the comparison below vacuous, so each case is first
        // asserted to have reached the state it was built to reach.
        for one in driven {
            #expect(stateName(one.card.state) == one.expected,
                    "the \(one.expected) case reached \(stateName(one.card.state))")
        }
        #expect(Set(driven.map { stateName($0.card.state) }).count == 4)

        // The narrowing itself: the same index in four different render states
        // yields ONE set of answers. Phase 6's State Contract 4 as narrowed by
        // plan 07-01 — without this, a failing card and every card blocked
        // beneath it would be the cards a user needs to clear and exactly the
        // ones that could not be cleared.
        let answers = Set(driven.map { [$0.card.position.canMoveUp, $0.card.position.canMoveDown] })
        #expect(answers.count == 1, "footer enablement varied with render state: \(answers)")
        let ups = Set(driven.map(\.card.position.canMoveUp))
        let downs = Set(driven.map(\.card.position.canMoveDown))
        #expect(ups == [true])
        #expect(downs == [true])

        // The ordinal is state-independent for the same reason, and remove
        // carries no enablement flag at all — see StepControls.swift.
        let ordinals = Set(driven.map(\.card.position.visibleOrdinal))
        #expect(ordinals.count == 1, "the ordinal varied with render state: \(ordinals)")
        #expect(ordinals.first == 3)
    }

    @Test("the appended ordinal is index + 2 and the total is one more than the steps")
    func theOrdinalIsIndexPlusTwoAndTheTotalIsOneMoreThanTheSteps() {
        #expect(StepStackPosition.rootOrdinal == 1)
        for length in [1, 2, 5] {
            let cards = surface(appending: length).appendedCards
            #expect(cards.count == length)
            #expect(!cards.isEmpty)
            for card in cards {
                // i + 2, because the root step is synthesised in
                // evaluatedPipeline and is NOT in model.encode.steps.
                #expect(card.position.visibleOrdinal == card.position.appendedIndex + 2)
                #expect(card.position.totalCards == length + 1)
                // On THIS surface the model index and the appended index are
                // the same number. HashingSurfaceTests asserts the surface
                // where they are not.
                #expect(card.position.modelIndex == card.position.appendedIndex)
            }
            #expect(cards.first?.position.visibleOrdinal == 2, "the first appended card is Step 2, not Step 1")
            #expect(cards.last?.position.visibleOrdinal == length + 1)
        }
    }

    @Test("removing the failing card takes the blocked count from above zero to zero")
    func removingTheFailingCardClearsEveryBlockedCardBelowIt() {
        let model = AppModel.isolated()
        model.encode = Pipeline(
            input: InputExample.encode,
            steps: [Step(operation: .base64Decode), Step(operation: .base64Decode), Step(operation: .htmlEncode)]
        )
        let surface = EncodeSurface(model: model)

        // EXISTENCE BEFORE ABSENCE. A blocked count of zero here would make the
        // "exactly zero after" assertion below vacuous.
        let before = surface.appendedCards
        #expect(before.count == 3)
        let blockedBefore = before.filter { $0.state == .blocked }.count
        #expect(blockedBefore > 0,
                "nothing was blocked before the removal, so the assertion after it proves nothing")
        let failing = before.dropFirst().first
        #expect(failing != nil)
        #expect(failing.map { stateName($0.state) } == "failure", "the card being removed is not the failing one")

        // Driven through the SURFACE's own call site, not through Pipeline: a
        // wrong index here is exactly the defect this case exists to catch.
        if let failing {
            surface.remove(failing.position)
        }

        let after = surface.appendedCards
        #expect(after.count == 2, "the removal was a truncation rather than a splice")
        let blockedAfter = after.filter { $0.state == .blocked }.count
        #expect(blockedAfter == 0)
        #expect(blockedBefore > blockedAfter)
        // The splice is visible: the card that WAS blocked keeps its header,
        // shows a real value, and renumbers one ordinal further up the stack.
        #expect(after.last?.step.operation == .htmlEncode)
        #expect(after.last?.position.visibleOrdinal == 3)
        #expect(after.last.map { stateName($0.state) } == "value")
        // The identity of every survivor existed before the removal.
        let survived = Set(after.map(\.step.id))
        #expect(survived.isSubset(of: Set(before.map(\.step.id))))
    }
}
