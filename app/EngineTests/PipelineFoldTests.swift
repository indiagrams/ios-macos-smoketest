// The fold — D-84's halt rule and APP-08's chaining, tested.
//
// An `extension` of `PipelineTests` rather than a suite of its own, so that
// `-only-testing:AppMacOSTests/PipelineTests` selects these cases too. Two
// files because one would exceed SwiftLint's 400-line file budget, which is
// not loosened.
//
// NOTHING HERE INDEXES AN ARRAY. A fold over a step list is the classic trap
// site for this subject and these bundles are host-based, so a trap would kill
// the host and put a crash dialog on the developer's desktop. `first`, `last`,
// `prefix`, `dropLast` and equality against a whole literal array are used
// instead, each compared as an Optional.
//
// THE TWO FIXED FAILURES THESE CASES ARE BUILT ON, both measured against
// Base64Codec.classify on this tree:
//
//   apply(.base64Decode, to: "hello")  -> .badLength(5)
//       five characters, all in the alphabet, and 5 % 4 == 1
//   apply(.base64Decode, to: "a%20b")  -> .unexpectedCharacter("%", position: 2)
//       the '%' that `urlEncode` just produced is not in the Base64 alphabet
//
// The second is the one used for the [ok, err, …] shapes, because it makes the
// upstream step's output visibly different from its input and carries a
// position — so a fold that quietly passed the ORIGINAL input downstream
// instead of the previous step's output would fail here rather than pass.

import Testing

extension PipelineTests {
    // MARK: - Fixtures

    /// Steps for a list of operations, each with a fresh identity.
    static func steps(_ operations: Operation...) -> [Step] {
        operations.map { Step(operation: $0) }
    }

    /// `urlEncode` turns this into `a%20b`, which `base64Decode` then rejects
    /// at a named position. One input drives every halt case below.
    static let chainInput = "a b"

    /// The failure the second step of every halt case produces.
    static let chainFailure = ConversionFailure.unexpectedCharacter("%", position: 2)

    // MARK: - APP-08 — the output of one tool is the input of the next

    @Test
    func aSingleStepEvaluatesToItsValue() {
        let pipeline = Pipeline(input: "hello", steps: Self.steps(.base64Encode))
        #expect(pipeline.evaluate() == [.value("aGVsbG8=")])
    }

    /// **APP-08, as an executed assertion.** Step 2's input is step 1's output:
    /// `"hello"` → `"aGVsbG8="` → `"YUdWc2JHOD0="`. No copy, no paste, no
    /// intermediate user action. A fold that handed the ORIGINAL input to every
    /// step would produce `"aGVsbG8="` twice and fail here.
    @Test
    func stepTwosInputIsStepOnesOutput() {
        let pipeline = Pipeline(input: "hello", steps: Self.steps(.base64Encode, .base64Encode))
        #expect(pipeline.evaluate() == [.value("aGVsbG8="), .value("YUdWc2JHOD0=")])
        #expect(apply(.base64Encode, to: "aGVsbG8=").success == "YUdWc2JHOD0=", "the second value is the first one converted again")
    }

    /// Chaining across three different families, so the assertion is not about
    /// one codec being idempotent-looking.
    @Test
    func aThreeStepChainCarriesTheTextThroughAllThreeFamilies() {
        let pipeline = Pipeline(input: "<b>", steps: Self.steps(.htmlEncode, .urlEncode, .sha256))
        let encoded = "&lt;b&gt;"
        let escaped = "%26lt%3Bb%26gt%3B"
        #expect(apply(.urlEncode, to: encoded).success == escaped)
        #expect(pipeline.evaluate() == [.value(encoded), .value(escaped), .value(DigestCodec.sha256(escaped))])
    }

    // MARK: - D-84 — the halt rule

    /// `[ok, err, ok]` yields `[value, failure, blocked]`. The third element is
    /// `.blocked` — not a stale value, not `.empty`, not a second copy of the
    /// failure.
    @Test
    func aFailureHaltsTheChainAndTheStepBelowIsBlocked() {
        let pipeline = Pipeline(input: Self.chainInput, steps: Self.steps(.urlEncode, .base64Decode, .base64Encode))
        #expect(pipeline.evaluate() == [.value("a%20b"), .failure(Self.chainFailure), .blocked])
    }

    /// However deep: exactly one `.failure` and three `.blocked`.
    @Test
    func everythingBelowAFailureIsBlockedHoweverDeep() {
        let pipeline = Pipeline(
            input: Self.chainInput,
            steps: Self.steps(.urlEncode, .base64Decode, .md5, .base64Encode, .sha512)
        )
        let states = pipeline.evaluate()
        #expect(states.count == 5)
        #expect(states.filter { $0 == .blocked }.count == 3)
        #expect(states.filter {
            if case .failure = $0 {
                true
            } else {
                false
            }
        }.count == 1)
        #expect(states == [.value("a%20b"), .failure(Self.chainFailure), .blocked, .blocked, .blocked])
    }

    /// **A blocked step never re-runs**, asserted observably rather than by
    /// inspection. `sha256` CANNOT fail, so a fold that kept going past the
    /// failure — even one that "reported" the halt — would produce a `.value`
    /// here. This is the case that separates a halt from a label.
    @Test
    func aBlockedStepNeverReRuns() {
        let pipeline = Pipeline(input: "hello", steps: Self.steps(.base64Decode, .sha256))
        let states = pipeline.evaluate()
        #expect(states == [.failure(.badLength(5)), .blocked])
        #expect(states.last != .value(DigestCodec.sha256("hello")), "the digest of the ORIGINAL input")
        #expect(states.last != .value(DigestCodec.sha256("")), "the digest of the empty string")
    }

    /// The seeded first card is never blocked (06-UI-SPEC.md §State Contract 4:
    /// Blocked is reachable only at index ≥ 2). Swept over every operation and
    /// a population of inputs that reaches all three of the other states.
    @Test
    func theFirstStepIsNeverBlocked() {
        let inputs = ["", "hello", "a%20b", "&amp;", "<b>", "aGVsbG8=", "aGVs!G8="]
        #expect(Operation.allCases.isEmpty == false)
        var checked = 0
        var blockedFirsts = 0
        for operation in Operation.allCases {
            for input in inputs {
                let pipeline = Pipeline(input: input, steps: Self.steps(operation, .base64Decode, .md5))
                if pipeline.evaluate().first == .blocked {
                    blockedFirsts += 1
                }
                checked += 1
            }
        }
        #expect(checked == 70, "the sweep population shrank")
        #expect(blockedFirsts == 0)
    }

    // MARK: - The Empty state intercepts before the classifier

    @Test
    func emptyInputYieldsEmptyForEveryStepAndNeverAFailure() {
        #expect(Pipeline(input: "", steps: Self.steps(.base64Encode)).evaluate() == [.empty])
        #expect(Pipeline(input: "", steps: Self.steps(.base64Decode, .urlDecode, .md5)).evaluate() == [.empty, .empty, .empty])
        #expect(Pipeline().evaluate() == [], "no steps, nothing to render")
        #expect(Pipeline(input: "", steps: Self.steps(.base64Encode)).evaluate() != [.value("")])
    }

    // MARK: - Purity

    /// Two evaluations of the same value are equal, because the fold holds no
    /// state and reads nothing outside the value it is called on. This is
    /// D-84's premise: nothing can go stale if nothing is remembered.
    @Test
    func evaluateIsPureAndRepeatable() {
        let pipeline = Pipeline(input: Self.chainInput, steps: Self.steps(.urlEncode, .base64Decode, .md5))
        #expect(pipeline.evaluate() == pipeline.evaluate())
        let hashing = Pipeline(input: "hello", steps: Self.steps(.md5, .sha512))
        #expect(hashing.evaluate() == hashing.evaluate())
    }

    // MARK: - appending — the add-step control's model half (APP-08)

    /// The VALIDATION matrix's APP-08 row: appending a step seeded with a given
    /// output produces the chained result, and that result is exactly
    /// `apply(op, to: <the previous output>)`.
    @Test
    func appendingSeedsTheNewStepWithThePreviousOutput() {
        let base = Pipeline(input: "hello", steps: Self.steps(.base64Encode))
        let previousOutput = "aGVsbG8="
        #expect(base.evaluate().last == .value(previousOutput))
        let extended = base.appending(.md5)
        #expect(extended.steps.count == base.steps.count + 1)
        #expect(Array(extended.steps.dropLast()) == base.steps, "appending must not disturb the steps already there")
        #expect(extended.steps.last?.operation == .md5)
        #expect(extended.input == base.input)
        guard let expected = apply(.md5, to: previousOutput).success else {
            Issue.record("apply(.md5, to: \(previousOutput)) failed, which no input can cause")
            return
        }
        #expect(extended.evaluate().last == .value(expected))
        #expect(extended.evaluate() == [.value(previousOutput), .value(expected)])
    }

    /// Each appended step gets a fresh identity, so two appends of the same
    /// operation are two cards rather than one.
    @Test
    func appendingTwiceProducesTwoDistinctSteps() {
        let twice = Pipeline(input: "hello").appending(.md5).appending(.md5)
        #expect(twice.steps.count == 2)
        #expect(twice.steps.first != twice.steps.last)
        #expect(twice.steps.first?.id != twice.steps.last?.id)
    }

    /// Appending to a pipeline whose last step failed produces a `.blocked`
    /// card — not a crash, and not a value.
    @Test
    func appendingToAFailedPipelineProducesABlockedCard() {
        let failed = Pipeline(input: "hello", steps: Self.steps(.base64Decode))
        #expect(failed.evaluate() == [.failure(.badLength(5))])
        let extended = failed.appending(.sha256)
        #expect(extended.evaluate() == [.failure(.badLength(5)), .blocked])
        #expect(extended.evaluate().last == .blocked)
    }
}
