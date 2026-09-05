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
        let model = AppModel()
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
        let model = AppModel()
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
}
