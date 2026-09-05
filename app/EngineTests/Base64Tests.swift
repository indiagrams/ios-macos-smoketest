// Tests for app/Shared/Engine/Base64Codec.swift — APP-01, and the pattern the
// other three codecs copy.
//
// Run via (macOS):
//   xcodebuild test -project app/App.xcodeproj -scheme App-macOS \
//     -configuration Debug -destination 'platform=macOS' \
//     -only-testing:AppMacOSTests/Base64Tests \
//     CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
//
// THE ONE-DIRECTIONAL CONTRACT
//
//     classify(s) == nil  ⟹  Data(base64Encoded: s) != nil
//
// and NOT the other way round: Foundation decodes "aGVsbG8==" and "AB=A",
// which this classifier rejects. No test here asserts the two sides reach the
// same verdict, because such a test fails on exactly those two inputs
// (06-RESEARCH.md Pitfall 7).
//
// 06-RESEARCH.md's classifier does not satisfy the forward direction either,
// and its 18 inputs were too few to show it — see Base64Codec.swift's header
// for the measured table, the tightening, and the 2.18-billion-input sweep
// that found the counterexample class. A bounded version of that sweep runs
// here on every test run.
//
// Every iteration below is guarded by a non-empty assertion on its own
// collection: a loop over an empty collection asserts nothing and is
// indistinguishable from a loop that passed.

import Foundation
import Testing

/// See PositionTests for why there is no bare `@Suite` attribute.
struct Base64Tests {
    // MARK: - Corpus plumbing

    /// Maps the corpus's own expectation vocabulary — fixed by 06-02 before
    /// any classifier existed — onto what `classify` returns. NO `default:`
    /// branch: a verdict kind added without a matching `ConversionFailure`
    /// breaks the build instead of being silently skipped.
    private static func expectedFailure(for verdict: ExpectedBase64Verdict) -> ConversionFailure? {
        switch verdict {
        case .valid: nil
        case let .badLength(length): .badLength(length)
        case let .unexpectedCharacter(character, position): .unexpectedCharacter(character, position: position)
        case let .earlyPadding(position): .paddingBeforeEnd(position: position)
        }
    }

    /// Plain text to round-trip, assembled from the shared corpus rather than
    /// invented here so it grows when the corpus does.
    private static var plainTextSamples: [String] {
        var samples = ["", "hello", "a", "ab", "abc", "abcd", "\u{0}", "  leading and trailing  "]
        samples += TestVectors.positionCases.map(\.string)
        samples += TestVectors.digestVectors.map(\.input)
        samples += TestVectors.percentCases.map(\.input)
        return samples
    }

    // MARK: - The corpus itself

    /// The corpus is the 20 measured inputs and exactly 5 of them diverge.
    ///
    /// Without this, every `@Test(arguments:)` below would silently assert
    /// less if the corpus shrank — `.continue-here.md`'s "a control that
    /// passes without having looked". The divergent inputs are asserted BY
    /// NAME before being counted, because a count of 5 reached by five other
    /// entries is a different corpus with the same total.
    ///
    /// - Note: **18 entries / 2 divergent -> 20 / 5 on 2026-09-05, plan 06-20,
    ///   WR-03.** The three added divergences are padding shapes the classifier
    ///   used to accept and Foundation still decodes; two of them decode to a
    ///   different BYTE COUNT across this app's deployment floor.
    @Test
    func theCorpusIsTheTwentyMeasuredInputs() {
        #expect(TestVectors.base64Corpus.count == 20)
        let diverging = Set(TestVectors.base64Corpus.filter(\.foundationDisagrees).map(\.input))
        #expect(diverging == ["aGVsbG8==", "AB=A", "====", "AAAA====", "AAAAAAAA===="])
        #expect(diverging.count == 5)
    }

    /// Every row of the corpus, asserted against the classifier.
    @Test(arguments: TestVectors.base64Corpus)
    func classifyReturnsTheMeasuredVerdict(_ testCase: Base64Case) {
        #expect(Base64Codec.classify(testCase.input) == Self.expectedFailure(for: testCase.expected),
                "classify(\(String(reflecting: testCase.input)))")
    }

    // MARK: - The contract, in the one direction that holds

    /// `classify(s) == nil ⟹ Data(base64Encoded: s) != nil`, over the corpus.
    ///
    /// `Data(base64Encoded:)` is called LIVE here, not read off the corpus, so
    /// this is a re-measurement against the running OS and not a restatement
    /// of a literal.
    @Test
    func aClassifierVerdictOfValidImpliesFoundationDecodes() {
        let accepted = TestVectors.base64Corpus.filter { Base64Codec.classify($0.input) == nil }
        #expect(accepted.count == 6, "expected 6 accepted inputs; the loop below would otherwise assert little")
        for testCase in accepted {
            #expect(Data(base64Encoded: testCase.input) != nil,
                    "\(String(reflecting: testCase.input)) is classified valid but Foundation refuses it")
        }
    }

    /// No input whose Foundation verdict is OS-dependent is ever classified
    /// valid, so the app never asks Foundation a question whose answer depends
    /// on the OS version.
    ///
    /// 06-02 measured `"AB=A"` decoding on macOS 26.1 and iOS 26.1 and
    /// returning nil on iOS 18.6 — inside this app's iOS 17.0 floor. The
    /// exemption's SIZE is asserted so it cannot quietly grow.
    @Test
    func noOSVariantInputIsEverHandedToTheDecoder() {
        #expect(TestVectors.foundationOSVariantInputs == ["AB=A"])
        #expect(TestVectors.foundationOSVariantInputs.count == 1, "no variant inputs; the loop below would assert nothing")
        for input in TestVectors.foundationOSVariantInputs {
            #expect(Base64Codec.classify(input) != nil,
                    "\(String(reflecting: input)) is accepted, so the app WOULD call a decoder whose verdict is OS-dependent")
            #expect(Base64Codec.decode(input).failure != nil)
        }
    }

    /// A bounded re-run of the sweep that found the counterexample class.
    ///
    /// Two populations, asserted separately: every length-4 string over a
    /// small alphabet covering each structural class (upper, lower, digit,
    /// both non-alphanumerics, padding), and a seeded random sample of longer
    /// strings over the full 65-character set. One source alone would be the
    /// wrong population.
    @Test
    func theContractHoldsOverASweptPopulation() {
        let structural = Array("Ab0+/=")
        #expect(structural.count == 6)
        var exhaustiveAccepted = 0
        for i in 0 ..< (6 * 6 * 6 * 6) {
            var value = i
            var s = ""
            for _ in 0 ..< 4 {
                s.append(structural[value % 6])
                value /= 6
            }
            if Base64Codec.classify(s) == nil {
                exhaustiveAccepted += 1
                #expect(Data(base64Encoded: s) != nil, "contract broken by \(String(reflecting: s))")
            }
        }
        #expect(exhaustiveAccepted > 0, "the exhaustive half accepted nothing, so it asserted nothing")

        let full = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
        #expect(full.count == 65)
        var generator = SeededGenerator(seed: 0x0603_2026)
        var randomAccepted = 0
        for _ in 0 ..< 20000 {
            let length = Int.random(in: 0 ... 24, using: &generator)
            var s = ""
            for _ in 0 ..< length {
                s.append(full[Int.random(in: 0 ..< full.count, using: &generator)])
            }
            if Base64Codec.classify(s) == nil {
                randomAccepted += 1
                #expect(Data(base64Encoded: s) != nil, "contract broken by \(String(reflecting: s))")
            }
        }
        #expect(randomAccepted > 0, "the random half accepted nothing, so it asserted nothing")
    }

    /// The class of input the 18-row corpus never contained: a final group of
    /// exactly one data character.
    ///
    /// These are what the RESEARCH classifier accepted and Foundation refused.
    /// Each is rejected with a reason naming the offending padding character
    /// and its position.
    @Test
    func aFinalGroupOfOneCharacterIsRejected() {
        let cases: [(String, ConversionFailure)] = [
            ("A===", .unexpectedCharacter("=", position: 2)),
            ("b===", .unexpectedCharacter("=", position: 2)),
            ("0===", .unexpectedCharacter("=", position: 2)),
            ("+===", .unexpectedCharacter("=", position: 2)),
            ("/===", .unexpectedCharacter("=", position: 2)),
            ("AAAAA===", .unexpectedCharacter("=", position: 6)),
            ("AAAAAAAAA===", .unexpectedCharacter("=", position: 10))
        ]
        #expect(cases.count == 7, "no cases; the loop below would assert nothing")
        for (input, expected) in cases {
            #expect(Base64Codec.classify(input) == expected, "classify(\(String(reflecting: input)))")
            #expect(Data(base64Encoded: input) == nil,
                    "\(String(reflecting: input)) is the counterexample class only while Foundation refuses it")
        }
    }

    /// The two divergent inputs are REJECTED even though Foundation decodes
    /// them — the observable proof that `decode` short-circuits, since if it
    /// consulted Foundation these would succeed. `"AB=A"` is OS-variant so
    /// only its rejection is asserted; `"aGVsbG8=="` is stable, so its
    /// Foundation verdict is asserted too.
    @Test
    func theInputsWhereFoundationDisagreesAreRejectedAnyway() {
        let divergent = Set(TestVectors.base64Corpus.filter(\.foundationDisagrees).map(\.input))
        #expect(divergent.count == 5, "no divergent inputs; the loop below would assert nothing")
        var stableChecked = 0
        for input in divergent {
            #expect(Base64Codec.classify(input) != nil, "\(String(reflecting: input)) should be rejected")
            #expect(Base64Codec.decode(input).failure != nil,
                    "decode(\(String(reflecting: input))) succeeded, so it asked Foundation instead of the classifier")
            if !TestVectors.foundationOSVariantInputs.contains(input) {
                stableChecked += 1
                #expect(Data(base64Encoded: input) != nil,
                        "\(String(reflecting: input)) no longer diverges — Foundation now refuses it too")
            }
        }
        #expect(stableChecked == 4, "5 divergent inputs minus a 1-input OS exemption must leave 4 checked, not \(stableChecked)")
    }

    // MARK: - The "====" decision, RE-DECIDED against a four-runtime measurement

    /// Padding with no partial quantum to complete is REFUSED.
    ///
    /// - Important: **This test asserted the opposite until 2026-09-05**, and
    ///   the reason it changed is a measurement rather than a preference. The
    ///   old text argued that rejecting `"===="` "would take a rule written for
    ///   this one input". That was true of `"===="` alone — but the rule that
    ///   covers it, *padding completes a PARTIAL final quantum and has no other
    ///   job*, is RFC 4648's own and it also covers `"AAAA===="`, which is where
    ///   the real defect was. Measured by running this suite on four runtimes:
    ///
    ///       input          iOS 17.5   iOS 18.6   iOS 26.1   macOS 26   macOS 15
    ///       "AAAA===="     4 bytes    4 bytes    3 bytes    3 bytes    4 bytes
    ///       "AAAAAAAA====" 7 bytes    7 bytes    6 bytes    6 bytes    —
    ///
    ///   The app was handing the user a DIFFERENT NUMBER OF BYTES for the same
    ///   input depending on their OS version, which is exactly what
    ///   `noOSVariantInputIsEverHandedToTheDecoder` one screen up says must
    ///   never happen — that test's population simply did not contain this
    ///   shape. `"===="` itself is stable at one byte on all four, so it is not
    ///   refused for being variant; it is refused because the RULE is what is
    ///   being applied, and a rule with an exception for one literal input is
    ///   the thing the old comment was right to warn against.
    /// - Note: This also retires the last source of a NUL byte in a
    ///   "successful" output (WR-03).
    @Test
    func paddingWithNoPartialQuantumToCompleteIsRefused() {
        #expect(Base64Codec.classify("====") == .unexpectedCharacter("=", position: 1))
        #expect(Base64Codec.classify("AAAA====") == .unexpectedCharacter("=", position: 5))
        #expect(Base64Codec.classify("AAAAAAAA====") == .unexpectedCharacter("=", position: 9))
        #expect(Base64Codec.decode("AAAA====").failure == .unexpectedCharacter("=", position: 5))

        // Foundation still decodes all three, so this is the classifier being
        // the authority and not an agreement.
        for input in ["====", "AAAA====", "AAAAAAAA===="] {
            #expect(Data(base64Encoded: input) != nil, "\(input) still decodes in Foundation, which is the point")
        }

        // The rule is one clause wide: padding that DOES complete a partial
        // quantum is untouched, and so is an input with no padding at all.
        #expect(Base64Codec.classify("AA==") == nil)
        #expect(Base64Codec.classify("AAA=") == nil)
        #expect(Base64Codec.classify("AAAA") == nil)
        #expect(Base64Codec.classify("") == nil)
        #expect(Base64Codec.decode("AAAA").success?.utf8.count == 3)
    }

    // MARK: - encode

    /// `encode` is total: every String has a UTF-8 encoding and every byte
    /// sequence has a Base64 spelling. There is no failure path to test.
    @Test
    func encodeIsTotal() {
        #expect(Base64Codec.encode("hello") == "aGVsbG8=")
        #expect(Base64Codec.encode("") == "")
        #expect(Base64Codec.encode("a") == "YQ==")
        #expect(Base64Codec.encode("ab") == "YWI=")
        #expect(Base64Codec.encode("abc") == "YWJj")
    }

    /// Anything `encode` produces, `classify` accepts. If that ever stopped
    /// being true the app could generate output it then refused to read back.
    @Test
    func everythingEncodeProducesIsAccepted() {
        let samples = Self.plainTextSamples
        #expect(samples.count >= 8, "sample set is short; the loop below would assert less")
        for sample in samples {
            let encoded = Base64Codec.encode(sample)
            #expect(Base64Codec.classify(encoded) == nil,
                    "encode(\(String(reflecting: sample))) produced \(String(reflecting: encoded)), which classify rejects")
        }
    }

    @Test
    func decodeOfEncodeIsTheOriginal() {
        let samples = Self.plainTextSamples
        #expect(samples.count >= 8, "sample set is short; the loop below would assert less")
        for sample in samples {
            #expect(Base64Codec.decode(Base64Codec.encode(sample)) == .success(sample),
                    "round trip lost \(String(reflecting: sample))")
        }
    }

    // MARK: - decode

    /// `decode` returns EXACTLY the failure `classify` returned, for every
    /// rejected input in the corpus. Not "a failure" — the same one.
    @Test
    func decodeReturnsTheClassifiersOwnFailure() {
        let rejected = TestVectors.base64Corpus.compactMap { testCase -> (String, ConversionFailure)? in
            guard let failure = Base64Codec.classify(testCase.input) else { return nil }
            return (testCase.input, failure)
        }
        #expect(rejected.count == 14, "expected 14 rejected corpus inputs, not \(rejected.count)")
        for (input, failure) in rejected {
            #expect(Base64Codec.decode(input) == .failure(failure), "decode(\(String(reflecting: input)))")
        }
    }

    /// The hand-written scan is never MORE permissive than Foundation, and the
    /// codec's answer is the scan's either way.
    ///
    /// Only this direction is asserted, for the same reason as the Base64
    /// contract above: the other one is measurably false. MEASURED 2026-09-04
    /// by running this very suite on three runtimes — on **iOS 17.5**, which is
    /// inside this app's iOS 17.0 floor, `String(bytes:encoding: .utf8)`
    /// accepts the byte `0xA9` and returns U+FFFD; on iOS 18.6 and macOS 26.1
    /// it returns nil. `0xA9` is the only byte in `0x80...0xFF` that differs,
    /// enumerated exhaustively on all three.
    ///
    /// Both branches are counted and both counts are asserted non-zero, so a
    /// generator that happened to produce only valid — or only invalid —
    /// sequences would fail rather than quietly assert half as much.
    @Test
    func theUTF8ScanIsNeverMorePermissiveThanFoundation() {
        var generator = SeededGenerator(seed: 0x5554_4638_2026)
        var scanValid = 0
        var scanInvalid = 0
        for _ in 0 ..< 5000 {
            let count = Int.random(in: 0 ... 12, using: &generator)
            var bytes: [UInt8] = []
            for _ in 0 ..< count {
                bytes.append(UInt8.random(in: 0 ... 255, using: &generator))
            }
            let encoded = Data(bytes).base64EncodedString()
            if Base64Codec.firstInvalidUTF8Offset(bytes) == nil {
                scanValid += 1
                #expect(String(bytes: bytes, encoding: .utf8) != nil,
                        "the scan accepted bytes Foundation cannot render: \(bytes)")
                #expect(Base64Codec.decode(encoded).success != nil, "decode rejected bytes the scan accepted: \(bytes)")
            } else {
                scanInvalid += 1
                #expect(Base64Codec.decode(encoded).failure != nil,
                        "decode accepted bytes the scan rejected: \(bytes)")
            }
        }
        #expect(scanValid + scanInvalid == 5000)
        #expect(scanValid > 0, "no valid sequences were generated, so that branch asserted nothing")
        #expect(scanInvalid > 0, "no invalid sequences were generated, so that branch asserted nothing")
    }

    // MARK: - Totality (V5, T-06-08)

    /// A kilobyte of arbitrary bytes through all three functions.
    ///
    /// These unit bundles are HOST-BASED, so a trap here would kill the host
    /// process rather than fail a test (06-02). This test passing is the
    /// evidence that no path force-unwraps, `try!`s or subscripts out of range.
    @Test
    func aKilobyteOfArbitraryInputDoesNotTrap() {
        var generator = SeededGenerator(seed: 0x4B42_2026)
        var scalars = ""
        var byteString = ""
        for _ in 0 ..< 1024 {
            byteString.append(Character(UnicodeScalar(UInt8.random(in: 0 ... 255, using: &generator))))
            let value = UInt32.random(in: 0 ... 0x10FFFF, using: &generator)
            if let scalar = UnicodeScalar(value), !(0xD800 ... 0xDFFF).contains(value) {
                scalars.unicodeScalars.append(scalar)
            }
        }
        #expect(byteString.count == 1024)
        #expect(!scalars.isEmpty, "the scalar sample is empty, so the calls below would assert nothing")
        for input in [byteString, scalars] {
            _ = Base64Codec.classify(input)
            _ = Base64Codec.decode(input)
            let encoded = Base64Codec.encode(input)
            #expect(Base64Codec.decode(encoded) == .success(input))
        }
    }

    /// Position arithmetic on the failure path is total for a pathological
    /// input — one very long grapheme with the offending byte inside it.
    @Test
    func aFailurePositionInsideALongGraphemeIsTotal() {
        let family = "👨‍👩‍👧‍👦"
        let input = family + "!"
        #expect(Base64Codec.classify(input) == .unexpectedCharacter(family.first ?? "?", position: 1))
        #expect(input.count == 2)
    }
}
