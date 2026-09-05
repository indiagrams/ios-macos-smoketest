// Sweeps for app/Shared/Engine/HTMLEntityCodec.swift, kept out of
// HTMLEntityTests.swift so that file stays a readable list of stated
// behaviours.
//
// They are an EXTENSION of the same suite, not a suite of their own, which
// is the idiom PercentContractTests.swift established: everything below runs
// under `-only-testing:AppMacOSTests/HTMLEntityTests`, so the plan's own verify
// command cannot silently miss half the evidence.
//
// Run via (macOS):
//   xcodebuild test -project app/App.xcodeproj -scheme App-macOS \
//     -configuration Debug -destination 'platform=macOS' \
//     -only-testing:AppMacOSTests/HTMLEntityTests \
//     CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
//
// THE CONTRACT, AND WHY IT IS WEAKER EVIDENCE HERE THAN IT IS FOR BASE64
//
//     classify(s) == nil  =>  decode(s) is .success
//
// For Base64 and percent-encoding that statement is load-bearing, because a
// SECOND authority (Foundation) is consulted and measurably disagrees. Here
// there is no second authority: the SDK has no HTML entity codec, `classify`
// and `decode` are the same traversal called twice, and the implication
// therefore holds BY CONSTRUCTION. It is asserted anyway, over a seeded sweep,
// because it would stop holding the moment someone gave `decode` its own
// traversal — which is the refactor this file exists to fail on. It is NOT
// presented as a measurement of anything external, and no test asserts the
// converse.
//
// The sweeps below use `SeededGenerator` from EngineTestSupport with a seed of
// this suite's own, so a failure reproduces exactly rather than vanishing on
// the next run.

import Foundation
import Testing

extension HTMLEntityTests {
    /// A pool chosen to actually generate entity-shaped text: the five escaped
    /// characters, a `;` and a `#` so numeric references form, digits and
    /// letters so names form, whitespace so the terminator rule is exercised,
    /// and non-ASCII including a combining mark so multi-byte offsets and
    /// multi-scalar graphemes appear.
    private static let pool: [Unicode.Scalar] = [
        "&", "<", ">", "\"", "'", ";", "#", "x",
        "a", "Z", "0", "9", "m", "p",
        " ", "\t", "\n",
        "\u{E9}", "\u{65}", "\u{301}", "\u{1F600}", "\u{4E00}", "\u{A0}"
    ]

    /// The pool is populated and covers each class it claims to.
    ///
    /// Without this, a pool emptied by a bad merge would make every sweep
    /// below generate empty strings and pass.
    @Test
    func theSweepPoolCoversWhatItClaimsTo() {
        #expect(Self.pool.count >= 20)
        #expect(Set(Self.pool).isSuperset(of: ["&", "<", ">", "\"", "'"]))
        #expect(Self.pool.contains { $0.value > 0x7F })
        #expect(Self.pool.contains { $0.value > 0xFFFF })
        #expect(Self.pool.contains { $0 == "\u{301}" })
    }

    /// `decode(encode(x)) == .success(x)` over 2,000 seeded inputs.
    ///
    /// The sample set in `TestVectors.htmlRoundTripSamples` states the
    /// properties; this states that nothing outside them breaks it either.
    @Test
    func theRoundTripHoldsOverASeededSweep() {
        var generator = SeededGenerator(seed: 0x0606_4854_4D4C_0001)
        var checked = 0
        for _ in 0 ..< 2000 {
            let input = generator.randomScalarString(from: Self.pool, maxScalars: 24)
            let encoded = HTMLEntityCodec.encode(input)
            guard HTMLEntityCodec.decode(encoded).success == input else {
                #expect(Bool(false), "round trip lost \(String(reflecting: input))")
                return
            }
            checked += 1
        }
        #expect(checked == 2000)
    }

    /// The forward contract, over the same sweep, on raw (unencoded) inputs so
    /// that both verdicts actually occur.
    ///
    /// Both branches are COUNTED and both counts are asserted non-zero: a
    /// sweep that happened to generate only valid inputs would exercise one
    /// branch and report success.
    @Test
    func classifyingValidImpliesDecodeSucceeds() {
        var generator = SeededGenerator(seed: 0x0606_4854_4D4C_0002)
        var valid = 0
        var invalid = 0
        for _ in 0 ..< 2000 {
            let input = generator.randomScalarString(from: Self.pool, maxScalars: 24)
            if HTMLEntityCodec.classify(input) == nil {
                valid += 1
                #expect(HTMLEntityCodec.decode(input).success != nil,
                        "classified valid but did not decode: \(String(reflecting: input))")
            } else {
                invalid += 1
                #expect(HTMLEntityCodec.decode(input).failure == HTMLEntityCodec.classify(input),
                        "decode returned a different failure: \(String(reflecting: input))")
            }
        }
        #expect(valid > 0, "the sweep produced no valid inputs; the forward branch asserted nothing")
        #expect(invalid > 0, "the sweep produced no invalid inputs; the failure branch asserted nothing")
        #expect(valid + invalid == 2000)
    }

    /// Both functions are TOTAL over arbitrary text, including a 1 KB
    /// random-byte string read as UTF-8.
    ///
    /// A trap here would not fail this test — these bundles are host-based, so
    /// it would kill the host process and abort the whole run. That is why the
    /// codec has no force-unwrap and why its numeric accumulator bails before
    /// it can overflow.
    @Test
    func classifyAndDecodeAreTotalOverArbitraryBytes() {
        var generator = SeededGenerator(seed: 0x0606_4854_4D4C_0003)
        var bytes = [UInt8]()
        bytes.reserveCapacity(1024)
        for _ in 0 ..< 1024 {
            bytes.append(UInt8(truncatingIfNeeded: generator.next()))
        }
        #expect(bytes.count == 1024)

        // `String(bytes:encoding:)` rather than `String(decoding:as:)`: the
        // latter violates `optional_data_string_conversion` under this repo's
        // swiftlint --strict (measured by 06-04). Random bytes are usually not
        // valid UTF-8, so the fallback is exercised on most runs and both
        // paths are swept.
        let text = String(bytes: bytes, encoding: .utf8) ?? String(bytes.map { Character(UnicodeScalar($0)) })
        #expect(text.isEmpty == false)
        _ = HTMLEntityCodec.classify(text)
        _ = HTMLEntityCodec.decode(text)
        _ = HTMLEntityCodec.encode(text)

        // A 4 KB run of nothing but ampersands, which is the pathological
        // shape for a scanner that restarts its lookahead at every one.
        let manyAmpersands = String(repeating: "&", count: 4096)
        #expect(HTMLEntityCodec.classify(manyAmpersands) == .unterminatedEntity(position: 1))

        // A very long unterminated name: the accumulator must not be bounded
        // by a fixed buffer and must not trap.
        let longName = "&" + String(repeating: "a", count: 4096)
        #expect(HTMLEntityCodec.classify(longName) == .unterminatedEntity(position: 1))

        // A numeric reference with 4,096 digits, which is where an
        // `Int(digits)` implementation overflows.
        let longDigits = "&#" + String(repeating: "9", count: 4096) + ";"
        #expect(HTMLEntityCodec.decode(longDigits).success == nil)
    }

    /// **The offset arithmetic, swept.** The scan walks scalars while keeping
    /// a UTF-8 byte offset, and hands that offset to
    /// `characterPosition(utf8Offset:in:)` only on the failure path. If the
    /// per-scalar UTF-8 width were wrong for any class, the reported position
    /// would drift — and only for inputs containing that class.
    ///
    /// Each prefix below is a different UTF-8 width or a multi-scalar
    /// grapheme, and the expected position is the prefix's CHARACTER count
    /// plus one.
    @Test
    func theReportedPositionIsThePrefixesCharacterCountPlusOne() {
        let prefixes: [String] = [
            "",
            "a",
            "abc",
            "\u{E9}",
            "e\u{301}",
            "\u{4E00}\u{4E00}",
            "\u{1F600}",
            "a\u{1F600}b",
            "a👨\u{200D}👩\u{200D}👧\u{200D}👦b",
            "  \t",
            "café au lait "
        ]
        #expect(prefixes.count == 11, "the prefix table is empty or truncated; the loop below would assert nothing")

        for prefix in prefixes {
            let expected = prefix.count + 1
            #expect(HTMLEntityCodec.classify(prefix + "&bogus;") == .unknownEntity("&bogus;", position: expected),
                    "unknown-entity position drifted after \(String(reflecting: prefix))")
            #expect(HTMLEntityCodec.classify(prefix + "&x") == .unterminatedEntity(position: expected),
                    "unterminated position drifted after \(String(reflecting: prefix))")
        }
    }
}
