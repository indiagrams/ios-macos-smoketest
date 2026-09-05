// Tests for the pipeline model — app/Shared/Model/Operation.swift, Step.swift
// and Pipeline.swift (APP-08, APP-12, D-79/D-80/D-82/D-83/D-84).
//
// Run via (macOS):
//   xcodebuild test -project app/App.xcodeproj -scheme App-macOS \
//     -configuration Debug -destination 'platform=macOS' \
//     -only-testing:AppMacOSTests/PipelineTests \
//     CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
//
// Compiled into BOTH unit-test targets by the `sources:` entries in
// app/project.yml and app/Project.swift that already carry Shared/Model.
//
// `-only-testing:` NAMING AN ABSENT SUITE EXITS 0 PRINTING `** TEST SUCCEEDED **`
// HAVING RUN ZERO TESTS — measured by 06-03, which met it after forgetting to
// regenerate the project. A green from this file is evidence only when it
// carries an executed test count, and the counts are in
// evidence/06-09-pipeline.txt quoted from the run log.
//
// EVERY ASSERTION HERE IS NON-TRAPPING. These bundles are host-based: a Swift
// runtime trap kills the host, aborts the run and posts a crash dialog on the
// developer's desktop. A fold over a step list is a classic trap site, so no
// assertion below indexes an array. `first`, `last`, `prefix`, `suffix` and
// `dropFirst` are used throughout, and each is compared as an Optional.
//
// The suite is split across two files, both extending the same type so that
// `-only-testing:…/PipelineTests` selects all of it: this file covers the
// operations, `apply` and the fold; PipelineTestsAppModel.swift covers the
// app-level model. Two files because one would exceed SwiftLint's 400-line
// file budget, which is not loosened.

import Foundation
import Testing

/// See PositionTests for why there is no bare `@Suite` attribute.
struct PipelineTests {
    // MARK: - The chainable set

    /// The add-step menu, in the order 06-UI-SPEC.md's table lists it: the six
    /// codec operations, then the four digests. The UI slices this array into
    /// its two sections, so a reordering here scrambles the menu.
    ///
    /// The UI-SPEC's table lists TEN `op.*` keys while its prose in the same
    /// section says "the eight text→text operations". The table is the
    /// observable artifact and this plan resolves the discrepancy in its
    /// favour: `operation_count=10`.
    static let menuOrder: [Operation] = [
        .base64Encode,
        .base64Decode,
        .urlEncode,
        .urlDecode,
        .htmlEncode,
        .htmlDecode,
        .md5,
        .sha1,
        .sha256,
        .sha512,
    ]

    /// The Timestamps conversions are deliberately absent: they take an
    /// instant, not text, so they are not chainable in Phase 6.
    @Test
    func theChainableSetIsTenOperations() {
        #expect(Operation.allCases.isEmpty == false, "an emptied case list makes every sweep below run zero arguments")
        #expect(Operation.allCases.count == 10)
    }

    /// A count alone would pass for ten of the wrong cases, so the set is
    /// compared against a literal list as well. An operation added without a
    /// menu string fails here rather than appearing unlabelled.
    @Test
    func theCaseListIsExactlyTheMenuOrderAndNothingElse() {
        #expect(Array(Operation.allCases) == Self.menuOrder)
        #expect(Set(Operation.allCases) == Set(Self.menuOrder))
    }

    /// The two menu sections are contiguous slices of `allCases`.
    @Test
    func theSixCodecOperationsComeBeforeTheFourDigests() {
        let cases = Array(Operation.allCases)
        #expect(Array(cases.prefix(6)) == [.base64Encode, .base64Decode, .urlEncode, .urlDecode, .htmlEncode, .htmlDecode])
        #expect(Array(cases.suffix(4)) == [.md5, .sha1, .sha256, .sha512])
    }

    /// Each raw value IS the `Localizable.xcstrings` key that names the
    /// operation, so plan 06-10's catalog and plan 06-11's menu render from
    /// one place rather than from two lists that can drift.
    @Test
    func everyOperationCarriesItsCatalogKey() {
        #expect(Operation.base64Encode.rawValue == "op.base64.encode")
        #expect(Operation.base64Decode.rawValue == "op.base64.decode")
        #expect(Operation.urlEncode.rawValue == "op.url.encode")
        #expect(Operation.urlDecode.rawValue == "op.url.decode")
        #expect(Operation.htmlEncode.rawValue == "op.html.encode")
        #expect(Operation.htmlDecode.rawValue == "op.html.decode")
        #expect(Operation.md5.rawValue == "op.hash.md5")
        #expect(Operation.sha1.rawValue == "op.hash.sha1")
        #expect(Operation.sha256.rawValue == "op.hash.sha256")
        #expect(Operation.sha512.rawValue == "op.hash.sha512")
        let keys = Set(Operation.allCases.map(\.rawValue))
        #expect(keys.count == Operation.allCases.count, "two operations share one catalog key")
    }

    // MARK: - apply — the dispatch to the pure engines

    @Test
    func base64EncodeAndDecodeDispatchToTheEngine() {
        #expect(apply(.base64Encode, to: "hello").success == "aGVsbG8=")
        #expect(apply(.base64Decode, to: "aGVsbG8=").success == "hello")
    }

    /// The engine's failure travels through unchanged — the model neither
    /// wraps it nor flattens it to "something went wrong". D-85's reason and
    /// position survive the hop, which is what lets a step card render them.
    @Test
    func theEnginesFailureTravelsThroughApplyUnchanged() {
        #expect(apply(.base64Decode, to: "aGVs!G8=").failure == .unexpectedCharacter("!", position: 5))
        #expect(apply(.base64Decode, to: "hello").failure == .badLength(5))
        #expect(apply(.base64Decode, to: "aGVs!G8=") == Base64Codec.decode("aGVs!G8="))
        #expect(apply(.urlDecode, to: "a%2") == PercentCodec.decode("a%2"))
        #expect(apply(.htmlDecode, to: "&nope;") == HTMLEntityCodec.decode("&nope;"))
    }

    @Test
    func urlEncodeAndDecodeDispatchToTheEngine() {
        #expect(apply(.urlEncode, to: "a/b").success?.contains("%2F") == true)
        #expect(apply(.urlDecode, to: "a%20b").success == "a b")
    }

    @Test
    func htmlEncodeAndDecodeDispatchToTheEngine() {
        #expect(apply(.htmlEncode, to: "<b>").success == "&lt;b&gt;")
        #expect(apply(.htmlDecode, to: "&amp;").success == "&")
    }

    @Test
    func theDigestsDispatchToTheEngine() {
        #expect(apply(.sha256, to: "").success == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(apply(.md5, to: "hello").success == DigestCodec.md5("hello"))
        #expect(apply(.sha1, to: "hello").success == DigestCodec.sha1("hello"))
        #expect(apply(.sha512, to: "hello").success == DigestCodec.sha512("hello"))
    }

    /// Hashing has NO input-validation failure mode, and no error path is built
    /// for one: every `String` has a UTF-8 encoding and every byte sequence has
    /// a digest. Asserted as a property over a varied population rather than by
    /// inspection — replacement characters, lone combining marks, NUL, and
    /// astral graphemes are the text a hand-rolled encoder would choke on.
    @Test
    func theFourDigestOperationsNeverFailOverAVariedPopulation() {
        var generator = SeededGenerator(seed: 0x0609_2026_0904)
        let pool: [Unicode.Scalar] = ["a", "%", "&", "=", "\u{0000}", "\u{FFFD}", "\u{0301}", "\u{1F600}", "é", " "]
        var inputs = ["", "hello", "a👨‍👩‍👧‍👦b", "\u{FFFD}", "\u{0301}", "&#xZZ;", "%%%%"]
        for _ in 0 ..< 250 {
            inputs.append(generator.randomScalarString(from: pool, maxScalars: 24))
        }
        #expect(inputs.count == 257, "the population shrank; a sweep over an empty list reports success")
        let digests: [Operation] = [.md5, .sha1, .sha256, .sha512]
        let widths: [Operation: Int] = [.md5: 32, .sha1: 40, .sha256: 64, .sha512: 128]
        var failures = 0
        var wrongWidth = 0
        for input in inputs {
            for operation in digests {
                guard let value = apply(operation, to: input).success else {
                    failures += 1
                    continue
                }
                if value.count != widths[operation] { wrongWidth += 1 }
            }
        }
        #expect(failures == 0, "a digest operation reported a failure, which no input can cause")
        #expect(wrongWidth == 0, "a digest rendered at the wrong hex width")
    }

    // MARK: - Step identity

    /// Identity, not index. This is what makes the stack Phase 7 grows
    /// addressable when a step is removed or reordered from the middle.
    @Test
    func stepsAreEqualByIdentityAndOperationTogether() {
        let one = Step(operation: .md5)
        let other = Step(operation: .md5)
        #expect(one.id != other.id)
        #expect(one != other, "two independently created steps must not collapse into one")
        let shared = UUID()
        #expect(Step(operation: .md5, id: shared) == Step(operation: .md5, id: shared))
        #expect(Step(operation: .md5, id: shared) != Step(operation: .sha1, id: shared))
    }

    @Test
    func aDefaultPipelineIsEmptyAndTwoOfThemAreEqual() {
        #expect(Pipeline().input.isEmpty)
        #expect(Pipeline().steps.isEmpty)
        #expect(Pipeline() == Pipeline())
    }

    // MARK: - APP-12

    /// The probe alone is NOT the gate — 06-03 measured that an implicit
    /// conformance downgrades the violation to a warning, so `requireSendable`
    /// can pass on a type whose conformance is not explicit. The evidence is
    /// the boundary crossing below, which the compiler must prove under
    /// `-strict-concurrency=complete`.
    @Test
    func theModelTypesAreSendableAndCrossAnActorBoundary() async {
        requireSendable(Operation.self)
        requireSendable(Step.self)
        requireSendable(Pipeline.self)
        requireSendable(StepRenderState.self)
        requireSendable(ConversionFailure.self)
        let pipeline = Pipeline(input: "hello", steps: [Step(operation: .base64Encode)])
        let results = await Task.detached { pipeline.steps.map { apply($0.operation, to: pipeline.input) } }.value
        #expect(results.first?.success == "aGVsbG8=")
    }
}

/// Compiles only for a `Sendable` type. See the caller for why it is
/// documentation rather than the gate.
private func requireSendable(_: (some Sendable).Type) {}
