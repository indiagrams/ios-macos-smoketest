// PercentTests, continued — the MEASURED contracts, as an extension.
//
// Same suite as PercentTests.swift, so `-only-testing:AppMacOSTests/PercentTests`
// runs both halves. Split into two files because `swiftlint --strict` enforces
// file_length (400) and type_body_length (250) on this repo's config, and one
// file carrying both the specified behaviour and the swept contracts exceeds
// both. An `extension` keeps the suite whole rather than creating a second
// suite name a `-only-testing:` invocation could silently miss — which matters
// here, because 06-03 measured that `-only-testing:` naming an ABSENT suite
// exits 0 printing `** TEST SUCCEEDED **` having run zero tests.
//
// What lives here is the half that is EVIDENCE rather than specification:
// sweeps over seeded random populations, and the differential against the
// Foundation APIs this engine deliberately does not trust.

import Foundation
import Testing

extension PercentTests {
    /// The same round trip over a seeded random population, so the property is
    /// asserted about the function rather than about fifteen hand-picked
    /// strings.
    @Test
    func encodingRoundTripsOverASweptPopulation() {
        var generator = SeededGenerator(seed: 0x5045_5243_454E_5401)
        var checked = 0
        for _ in 0 ..< 2000 {
            let sample = generator.randomScalarString(from: Self.textPool, maxScalars: 12)
            let encoded = PercentCodec.encode(sample)
            #expect(PercentCodec.decode(encoded).success == sample,
                    "round trip lost \(String(reflecting: sample))")
            checked += 1
        }
        #expect(checked == 2000)
    }

    // MARK: - The one-directional contract

    /// `classify(s) == nil  =>  s.removingPercentEncoding != nil`, over a
    /// swept population, with BOTH branches counted and both counts asserted
    /// non-zero — a sweep that only ever hit one branch would pass while
    /// proving nothing.
    ///
    /// The CONVERSE is not asserted. It is measurably false: see
    /// ``theByteFoundationRepairsIsStillReportedInvalid()``.
    @Test
    func classifyingValidImpliesFoundationDecodes() {
        var generator = SeededGenerator(seed: 0x5045_5243_454E_5402)
        var accepted = 0
        var rejected = 0
        for _ in 0 ..< 4000 {
            let sample = generator.randomString(from: Self.percentishPool, maxLength: 10)
            if PercentCodec.classify(sample) == nil {
                accepted += 1
                #expect(sample.removingPercentEncoding != nil,
                        "FORWARD COUNTEREXAMPLE: \(String(reflecting: sample)) classifies valid, Foundation returns nil")
            } else {
                rejected += 1
            }
        }
        #expect(accepted > 0, "the sweep never produced a valid input; the assertion above never ran")
        #expect(rejected > 0, "the sweep never produced an invalid input; it is not exercising the classifier")
        #expect(accepted + rejected == 4000)
    }

    /// The byte `removingPercentEncoding` REPAIRS is still reported invalid,
    /// on every runtime.
    ///
    /// Measured on macOS 26.5.2: `"%A9".removingPercentEncoding` returns
    /// `Optional("\u{FFFD}")` rather than nil, and it is the ONLY byte in
    /// `0x80...0xFF` that does — enumerated exhaustively, then confirmed over
    /// a 65,536-input pair sweep in which all 257 disagreements contained
    /// `%A9` and all 257 were repaired to U+FFFD. A decoder that trusted
    /// Foundation would answer `"a\u{FFFD}"` for `"a%A9"` and call it success,
    /// showing the user a replacement character where their byte was.
    ///
    /// This assertion is OS-independent by construction: it is about the
    /// classifier, which is the authority, not about Foundation.
    @Test
    func theByteFoundationRepairsIsStillReportedInvalid() {
        #expect(PercentCodec.classify("%A9") == .invalidUTF8(position: 1))
        #expect(PercentCodec.classify("a%A9") == .invalidUTF8(position: 2))
        #expect(PercentCodec.decode("a%A9").failure == .invalidUTF8(position: 2))
        #expect(PercentCodec.decode("a%A9").success == nil,
                "0xA9 decoded to a String — Foundation's U+FFFD repair reached the user")
        #expect(PercentCodec.decode("%a9").failure == .invalidUTF8(position: 1),
                "the lowercase spelling of the same escape must be rejected too")
    }

    /// The classifier is never MORE permissive than Foundation, which is the
    /// direction that holds; and the population really does contain inputs
    /// where Foundation is more permissive, counted rather than assumed.
    @Test
    func theClassifierIsNeverMorePermissiveThanFoundation() {
        var generator = SeededGenerator(seed: 0x5045_5243_454E_5403)
        var agreements = 0
        var foundationMorePermissive = 0
        for _ in 0 ..< 4000 {
            let sample = generator.randomString(from: Self.percentishPool, maxLength: 8)
            let ours = PercentCodec.classify(sample) == nil
            let theirs = sample.removingPercentEncoding != nil
            if ours == theirs {
                agreements += 1
            } else {
                #expect(!ours, "the classifier accepted what Foundation rejected: \(String(reflecting: sample))")
                foundationMorePermissive += 1
            }
        }
        #expect(agreements > 0)
        #expect(agreements + foundationMorePermissive == 4000)
    }

    // MARK: - Decode short-circuits on the classifier

    /// When `classify` finds a fault, `decode` returns THAT failure — the same
    /// reason and the same position — rather than some other error. This is
    /// the observable form of "decode never calls `removingPercentEncoding`
    /// when classify is non-nil": if it did and mapped the result itself, the
    /// positions would not survive.
    @Test
    func decodeReturnsTheClassifiersOwnFailure() {
        var generator = SeededGenerator(seed: 0x5045_5243_454E_5404)
        var checked = 0
        for _ in 0 ..< 3000 {
            let sample = generator.randomString(from: Self.percentishPool, maxLength: 8)
            guard let failure = PercentCodec.classify(sample) else { continue }
            #expect(PercentCodec.decode(sample).failure == failure,
                    "decode disagreed with classify on \(String(reflecting: sample))")
            checked += 1
        }
        #expect(checked > 0, "the sweep produced no invalid input; the assertion above never ran")
    }

    // MARK: - The engine's byte set versus Foundation's CharacterSet route

    /// The hand-rolled encoder and 06-RESEARCH's `CharacterSet` route agree,
    /// measured on every runtime this suite runs on.
    ///
    /// The engine does NOT use `addingPercentEncoding` — see PercentCodec's
    /// file header for why (its allowed set is documented as Unicode
    /// `.alphanumerics`, which contains "é", yet it escapes "é" anyway; and it
    /// returns an Optional that a total `encode` would have to unwrap through
    /// a branch no test can reach). This test is the differential that would
    /// tell us if those two routes ever part company — including on the iOS
    /// 17.0 floor, where two Foundation string APIs have already been measured
    /// behaving differently than on 26.x.
    @Test
    func encodeAgreesWithFoundationsCustomSetRoute() {
        var researchSet = CharacterSet.alphanumerics
        researchSet.insert(charactersIn: "-._~")
        var generator = SeededGenerator(seed: 0x5045_5243_454E_5405)
        var compared = 0
        for _ in 0 ..< 1500 {
            let sample = generator.randomScalarString(from: Self.textPool, maxScalars: 10)
            let foundation = sample.addingPercentEncoding(withAllowedCharacters: researchSet)
            #expect(foundation != nil, "addingPercentEncoding returned nil for \(String(reflecting: sample))")
            #expect(PercentCodec.encode(sample) == foundation,
                    "the two encode routes diverge on \(String(reflecting: sample))")
            compared += 1
        }
        #expect(compared == 1500)
        #expect(CharacterSet.alphanumerics.contains("é"),
                "`.alphanumerics` no longer contains é — the reason this engine spells its own set may have changed")
    }

    // MARK: - Generator pools

    /// Arbitrary text, biased towards the characters that matter here.
    private static let textPool: [Unicode.Scalar] =
        Array("abz09-._~/?=&+% \n\u{00E9}\u{65E5}\u{1F44D}\u{0}".unicodeScalars)

    /// Strings shaped like percent-encoded input — escapes, half-escapes and
    /// literals — so a sweep lands on both sides of the classifier.
    private static let percentishPool: [Character] = Array("%0189AFafgz-._~ ")
}
