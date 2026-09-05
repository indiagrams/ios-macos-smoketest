// Tests for app/EngineTests/TestVectors.swift — the shared corpus.
//
// Run via (macOS):
//   xcodebuild test -project app/App.xcodeproj -scheme App-macOS \
//     -configuration Debug -destination 'platform=macOS' \
//     -only-testing:AppMacOSTests/TestVectorsTests \
//     CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
//
// These are not tests of the corpus's spelling. They RE-MEASURE it against the
// live platform on every run, so a Foundation or CryptoKit behaviour that
// moves between OS versions turns this suite red on the exact input that
// moved, in both unit targets, on both platforms. That is the whole point of
// keeping one corpus instead of two.
//
// Every iteration below is guarded by a non-empty assertion on its own
// collection first. A loop over an empty collection asserts nothing and is
// indistinguishable from a loop that passed.

import CryptoKit
import Foundation
import Testing

/// See PositionTests for why there is no bare `@Suite` attribute.
struct TestVectorsTests {
    /// Lowercase hex, matching what the app will render. `Digest.description`
    /// is NOT usable — it carries an `"<ALG> digest: "` prefix (measured).
    ///
    /// NOTE FOR 06-06 (hashing): 06-RESEARCH's recommended `hexString` builds a
    /// `[UInt8]` and returns `String(decoding: out, as: UTF8.self)`. That exact
    /// shape FAILS `swiftlint --strict` on this repo's config:
    ///
    ///   error: Optional Data -> String Conversion Violation: Prefer failable
    ///   `String(bytes:encoding:)` initializer when converting `Data` to
    ///   `String` (optional_data_string_conversion)
    ///
    /// `non_optional_string_data_conversion` is in `.swiftlint.yml`'s
    /// `disabled_rules`; this is the OTHER rule of the pair and is enabled.
    /// Appending Characters avoids it with no failable initializer to unwrap.
    /// The subscript cannot trap: a nibble is 0...15 and the table has 16.
    private static func hex(_ bytes: some Sequence<UInt8>) -> String {
        let table: [Character] = Array("0123456789abcdef")
        var out = ""
        out.reserveCapacity(128)
        for byte in bytes {
            out.append(table[Int(byte >> 4)])
            out.append(table[Int(byte & 0x0F)])
        }
        return out
    }

    /// The corpus is the inputs RESEARCH measured, plus the two plan 06-20
    /// measured. A later plan that adds a case must add it deliberately, and
    /// re-measure.
    ///
    /// - Note: **18 -> 20 on 2026-09-05 (plan 06-20, WR-03).** `"AAAA===="` and
    ///   `"AAAAAAAA===="` were added because they are the shapes whose
    ///   Foundation byte COUNT differs across this app's deployment floor, and
    ///   the corpus is where measured Foundation divergences are recorded. The
    ///   count moving is this assertion doing its job, not an obstacle to it.
    @Test
    func base64CorpusHasTwentyEntries() {
        #expect(TestVectors.base64Corpus.count == 20)
    }

    /// Exactly five entries diverge — and they are the five known ones,
    /// asserted BY NAME before being counted. A count of 5 reached by five
    /// different entries is a different corpus with the same total, and a
    /// total-only assertion cannot tell the two apart.
    ///
    /// - Note: **2 -> 5 on 2026-09-05 (plan 06-20, WR-03).**
    @Test
    func exactlyFiveEntriesDivergeAndTheyAreTheKnownFive() {
        let diverging = Set(TestVectors.base64Corpus.filter(\.foundationDisagrees).map(\.input))
        #expect(diverging == TestVectors.base64DivergentInputs)
        #expect(diverging == ["aGVsbG8==", "AB=A", "====", "AAAA====", "AAAAAAAA===="])
        #expect(diverging.count == 5)
    }

    /// Re-measure every Foundation verdict. This is the drift detector: it
    /// fails on the specific input whose behaviour moved.
    ///
    /// One input is exempt because its verdict is genuinely OS-dependent. The
    /// exemption is printed as a COUNT and the remainder is asserted as a
    /// count, so an exemption that quietly grows to cover a second input turns
    /// this red instead of silently swallowing it.
    @Test
    func foundationBase64VerdictsAreStillWhatWasMeasured() {
        #expect(TestVectors.base64Corpus.count == 20, "corpus is empty or truncated; the loop below would assert nothing")
        #expect(TestVectors.foundationOSVariantInputs.count == 1, "the OS-variant exemption changed size")
        var stableChecked = 0
        let variant = TestVectors.foundationOSVariantInputs
        for testCase in TestVectors.base64Corpus where !variant.contains(testCase.input) {
            stableChecked += 1
            let decodes = Data(base64Encoded: testCase.input) != nil
            #expect(decodes == testCase.foundationDecodes, "Data(base64Encoded:) changed for \(String(reflecting: testCase.input))")
        }
        #expect(stableChecked == 19, "20 entries minus a 1-input exemption must leave 19 checked, not \(stableChecked)")
    }

    /// The OS-variant input is never handed to the decoder, so its variance is
    /// unobservable in the app.
    ///
    /// This is the assertion that makes the exemption above safe. An exempt
    /// input classified `.valid` would mean the app calls a decoder whose
    /// answer depends on the OS version — the same string accepted on iOS 26
    /// and rejected on iOS 18.
    @Test
    func theOSVariantInputIsNeverHandedToTheDecoder() {
        #expect(TestVectors.foundationOSVariantInputs == ["AB=A"])
        #expect(TestVectors.foundationOSVariantInputs.count == 1, "no variant inputs; the loop below would assert nothing")
        for input in TestVectors.foundationOSVariantInputs {
            let entry = TestVectors.base64Corpus.first { $0.input == input }
            #expect(entry != nil, "\(String(reflecting: input)) is exempt but is not in the corpus")
            #expect(entry?.expected != .valid,
                    "\(String(reflecting: input)) is classified valid, so the app WOULD call the decoder, whose verdict is OS-dependent")
        }
    }

    /// The one direction of the contract that holds: a classifier verdict of
    /// `.valid` implies Foundation decodes. The converse is measurably false —
    /// the two divergent entries are exactly the counterexamples.
    @Test
    func validAlwaysImpliesFoundationDecodes() {
        let valid = TestVectors.base64Corpus.filter { $0.expected == .valid }
        // 7 -> 6 on 2026-09-05 (plan 06-20, WR-03): "====" moved from valid to
        // rejected when padding-with-no-partial-quantum was refused.
        #expect(valid.count == 6, "expected 6 valid entries; the loop below would otherwise assert little")
        for testCase in valid {
            #expect(testCase.foundationDecodes, "\(String(reflecting: testCase.input)) is classified valid but does not decode")
        }
    }

    /// Re-measure every `String.removingPercentEncoding` outcome.
    @Test
    func percentOutcomesAreStillWhatWasMeasured() {
        #expect(TestVectors.percentCases.count == 8, "corpus is empty or truncated; the loop below would assert nothing")
        for testCase in TestVectors.percentCases {
            let decoded = testCase.input.removingPercentEncoding
            switch testCase.expected {
            case let .decodes(expected):
                #expect(decoded == expected, "removingPercentEncoding changed for \(String(reflecting: testCase.input))")
            case .badEscape, .badUTF8:
                #expect(decoded == nil, "\(String(reflecting: testCase.input)) now decodes to \(String(describing: decoded))")
            }
        }
    }

    /// Re-measure every digest through CryptoKit itself.
    @Test
    func digestVectorsAreStillWhatCryptoKitProduces() {
        #expect(TestVectors.digestVectors.count == 6, "corpus is empty or truncated; the loop below would assert nothing")
        for vector in TestVectors.digestVectors {
            let data = Data(vector.input.utf8)
            #expect(Self.hex(Insecure.MD5.hash(data: data)) == vector.md5, "MD5 changed for \(String(reflecting: vector.input))")
            #expect(Self.hex(Insecure.SHA1.hash(data: data)) == vector.sha1, "SHA1 changed for \(String(reflecting: vector.input))")
            #expect(Self.hex(SHA256.hash(data: data)) == vector.sha256, "SHA256 changed for \(String(reflecting: vector.input))")
            #expect(Self.hex(SHA512.hash(data: data)) == vector.sha512, "SHA512 changed for \(String(reflecting: vector.input))")
        }
    }

    /// Every digest is full-length hex. Guards against a truncated literal
    /// being pasted in — which is how RESEARCH quotes the SHA-512.
    @Test
    func digestLiteralsAreFullLength() {
        #expect(TestVectors.digestVectors.count == 6, "corpus is empty or truncated; the loop below would assert nothing")
        for vector in TestVectors.digestVectors {
            #expect(vector.md5.count == 32)
            #expect(vector.sha1.count == 40)
            #expect(vector.sha256.count == 64)
            #expect(vector.sha512.count == 128)
        }
    }

    /// Re-measure the three competing length answers for each position case.
    @Test
    func positionCasesCarryTheirMeasuredCounts() {
        #expect(TestVectors.positionCases.count == 2, "corpus is empty; the loop below would assert nothing")
        for testCase in TestVectors.positionCases {
            #expect(testCase.string.count == testCase.characters, "Character count moved for \(String(reflecting: testCase.string))")
            #expect(testCase.string.utf8.count == testCase.utf8, "UTF-8 count moved for \(String(reflecting: testCase.string))")
            #expect(testCase.string.utf16.count == testCase.utf16, "UTF-16 count moved for \(String(reflecting: testCase.string))")
        }
    }

    /// The timestamp corpus covers each measured class, each asserted on its
    /// own. A total of 16 reached by sixteen entries of one class would pass a
    /// total-only assertion.
    @Test
    func timestampCorpusCoversEachMeasuredClassSeparately() {
        let cases = TestVectors.timestampCases
        #expect(cases.count == 16)
        #expect(cases.filter {
            if case .iso8601 = $0.expected {
                true
            } else {
                false
            }
        }.count == 4)
        #expect(cases.filter { $0.expected == .notISO8601 }.count == 5)
        #expect(cases.filter {
            if case .epochSeconds = $0.expected {
                true
            } else {
                false
            }
        }.count == 5)
        #expect(cases.filter {
            if case .epochMilliseconds = $0.expected {
                true
            } else {
                false
            }
        }.count == 1)
        #expect(cases.filter { $0.expected == .outOfRange }.count == 1)
    }

    /// The overflow case really overflows. `Int(...)` returning nil is the
    /// measured mechanism behind `timestamps.error.range`.
    @Test
    func theOverflowCaseReallyOverflows() {
        let overflowing = TestVectors.timestampCases.filter { $0.expected == .outOfRange }
        #expect(overflowing.count == 1, "no overflow case; the loop below would assert nothing")
        for testCase in overflowing {
            #expect(Int(testCase.input) == nil, "\(testCase.input) now fits in Int")
        }
    }
}
