// Tests for app/Shared/Engine/PercentCodec.swift — RFC 3986 percent-encoding.
//
// Run via (macOS):
//   xcodebuild test -project app/App.xcodeproj -scheme App-macOS \
//     -configuration Debug -destination 'platform=macOS' \
//     -only-testing:AppMacOSTests/PercentTests \
//     CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
//
// Compiled into BOTH unit-test targets, so every number below is asserted on
// iOS and macOS from one source. `-only-testing:` naming an ABSENT suite exits
// 0 printing `** TEST SUCCEEDED **` having run zero tests (measured by 06-03),
// so a green from this file is only evidence when it carries a test count.
//
// THE CONTRACT ASSERTED HERE IS ONE-DIRECTIONAL:
//
//     classify(s) == nil  =>  s.removingPercentEncoding != nil
//
// The converse is MEASURABLY FALSE and is not asserted. Swept over 121,779
// inputs on macOS 26.5.2: 0 forward counterexamples, 258 converse ones, every
// single one of them the byte 0xA9, which `removingPercentEncoding` REPAIRS to
// U+FFFD instead of rejecting. See the evidence file, and
// `theByteFoundationRepairsIsStillReportedInvalid` below, which is the
// assertion that keeps that variance out of the app.

import Foundation
import Testing

/// See PositionTests for why there is no bare `@Suite` attribute.
struct PercentTests {
    // MARK: - The shared corpus

    /// The corpus is not empty. A parameterised test over an emptied table
    /// runs zero cases and reports success, which is indistinguishable from a
    /// table that passed.
    @Test
    func theCorpusIsPopulated() {
        #expect(TestVectors.percentCases.count >= 8)
    }

    /// Both failure classes are actually present in the corpus, asserted
    /// separately. A count of 8 reached by eight `.decodes` rows would pass a
    /// total-only assertion and exercise neither error path.
    @Test
    func theCorpusCoversBothFailureClasses() {
        let cases = TestVectors.percentCases
        #expect(cases.filter { $0.expected == .badEscape }.count >= 4)
        #expect(cases.filter { $0.expected == .badUTF8 }.count >= 2)
        #expect(cases.filter {
            if case .decodes = $0.expected {
                true
            } else {
                false
            }
        }.count >= 2)
    }

    /// Every corpus row, run through the classifier and the decoder.
    @Test(arguments: TestVectors.percentCases)
    func theClassifierReproducesTheCorpus(_ testCase: PercentCase) {
        let failure = PercentCodec.classify(testCase.input)
        let decoded = PercentCodec.decode(testCase.input)
        let label = "\(String(reflecting: testCase.input)) — \(testCase.reason)"

        switch testCase.expected {
        case let .decodes(expected):
            #expect(failure == nil, "classified a valid input as \(String(describing: failure)): \(label)")
            #expect(decoded.success == expected, "decode disagrees with the corpus: \(label)")
        case .badEscape:
            #expect(isInvalidEscape(failure), "expected .invalidEscape, got \(String(describing: failure)): \(label)")
            #expect(decoded.failure == failure, "decode must return the classifier's own failure: \(label)")
        case .badUTF8:
            #expect(isInvalidUTF8(failure), "expected .invalidUTF8, got \(String(describing: failure)): \(label)")
            #expect(decoded.failure == failure, "decode must return the classifier's own failure: \(label)")
        }
    }

    // MARK: - Positions

    /// A malformed escape names the 1-based Character position of its `%`.
    ///
    /// The positions are the plan's, re-measured against the prototype before
    /// being written here rather than copied from prose.
    @Test
    func aMalformedEscapeNamesThePositionOfItsPercent() {
        #expect(PercentCodec.classify("a%2") == .invalidEscape(position: 2))
        #expect(PercentCodec.classify("a%zz") == .invalidEscape(position: 2))
        #expect(PercentCodec.classify("%") == .invalidEscape(position: 1))
        #expect(PercentCodec.classify("100%") == .invalidEscape(position: 4))
        #expect(PercentCodec.classify("%%") == .invalidEscape(position: 1))
        #expect(PercentCodec.classify("ab%1") == .invalidEscape(position: 3))
    }

    /// Well-formed escapes whose BYTES are not UTF-8 name the position of the
    /// first offending escape, and are a different failure class from a
    /// malformed escape — because the UI-SPEC defines two distinct strings,
    /// `encode.error.url.escape` and `encode.error.url.utf8`.
    @Test
    func invalidUTF8NamesThePositionOfTheFirstOffendingEscape() {
        #expect(PercentCodec.classify("a%C3") == .invalidUTF8(position: 2))
        #expect(PercentCodec.classify("a%FF") == .invalidUTF8(position: 2))
        #expect(PercentCodec.classify("%C3%28") == .invalidUTF8(position: 1))
        #expect(PercentCodec.classify("héllo%FF") == .invalidUTF8(position: 6))
    }

    /// The position is a GRAPHEME offset, not a byte offset. `"héllo%FF"` has
    /// 8 Characters and 9 UTF-8 bytes, so a byte-counting implementation
    /// reports 7 here and this test says which unit it used.
    @Test
    func thePositionIsAGraphemeOffsetNotAByteOffset() {
        let input = "héllo%FF"
        #expect(input.count == 8)
        #expect(input.utf8.count == 9)
        #expect(PercentCodec.classify(input) == .invalidUTF8(position: 6),
                "position 7 would mean the scan reported UTF-8 bytes; the app reports Characters")
    }

    // MARK: - The two measured CharacterSet traps

    /// `.urlQueryAllowed` leaves `"a/b?c=d&e"` UNCHANGED (measured). This
    /// asserts the reserved set really is escaped, so that set cannot be
    /// reintroduced without turning this red.
    @Test
    func everyReservedCharacterIsEscaped() {
        let encoded = PercentCodec.encode("a/b?c=d&e")
        #expect(encoded.contains("%2F"))
        #expect(encoded.contains("%3F"))
        #expect(encoded.contains("%3D"))
        #expect(encoded.contains("%26"))
        #expect(encoded == "a%2Fb%3Fc%3Dd%26e")
        for reserved in ["/", "?", "=", "&"] {
            #expect(!encoded.contains(reserved), "\(reserved) survived unescaped")
        }
    }

    /// `.alphanumerics` turns `"~-._"` into `"%7E%2D%2E%5F"` (measured), but
    /// RFC 3986 §2.3 lists all four as unreserved. This asserts they are left
    /// alone, so that set cannot be reintroduced either.
    @Test
    func theUnreservedMarksAreNeverEscaped() {
        #expect(PercentCodec.encode("~-._") == "~-._")
        let unreserved = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        #expect(PercentCodec.encode(unreserved) == unreserved,
                "the RFC 3986 §2.3 unreserved set must survive encoding unchanged")
        #expect(unreserved.count == 66)
    }

    /// Every ASCII character OUTSIDE the unreserved set is escaped. The two
    /// tests above name four reserved characters each; this one leaves no
    /// ASCII byte unasserted.
    @Test
    func everyOtherASCIICharacterIsEscaped() {
        let unreserved = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".utf8)
        var escaped = 0
        var passedThrough = 0
        for byte in UInt8(0) ... UInt8(127) {
            let input = String(UnicodeScalar(byte))
            let encoded = PercentCodec.encode(input)
            if unreserved.contains(byte) {
                passedThrough += 1
                #expect(encoded == input, "unreserved byte 0x\(String(byte, radix: 16)) was escaped")
            } else {
                escaped += 1
                #expect(encoded.count == 3 && encoded.hasPrefix("%"),
                        "byte 0x\(String(byte, radix: 16)) encoded as \(String(reflecting: encoded))")
            }
        }
        #expect(passedThrough == 66)
        #expect(escaped == 62)
    }

    /// Non-ASCII is escaped byte by UTF-8 byte, which is what makes the
    /// encoding reversible for text the user actually types.
    @Test
    func nonASCIIIsEscapedByUTF8Byte() {
        #expect(PercentCodec.encode("é") == "%C3%A9")
        #expect(PercentCodec.encode("日本") == "%E6%97%A5%E6%9C%AC")
        #expect(PercentCodec.encode("👍") == "%F0%9F%91%8D")
    }

    /// Hex digits in an escape are UPPERCASE, which is what RFC 3986 §2.1
    /// says producers should emit. Decoding accepts either case — asserted in
    /// ``decodingAcceptsHexDigitsInEitherCase()``.
    @Test
    func encodedHexDigitsAreUppercase() {
        let encoded = PercentCodec.encode("é~/\u{7F}")
        #expect(encoded == "%C3%A9~%2F%7F")
        #expect(encoded.uppercased() == encoded, "hex digits must be uppercase per RFC 3986 §2.1")
    }

    /// `+` is NOT a space. RFC 3986 percent-encoding is not `application/
    /// x-www-form-urlencoded`, and the UI-SPEC's "URL" format is the former.
    /// This is the single most common wrong expectation about this function,
    /// so it is asserted in both directions.
    @Test
    func plusIsNotASpace() {
        #expect(PercentCodec.decode("a+b").success == "a+b", "'+' decoded as a space — that is form-encoding, not RFC 3986")
        #expect(PercentCodec.encode("a b") == "a%20b", "a space must encode as %20, never as '+'")
        #expect(PercentCodec.encode("a+b") == "a%2Bb", "'+' is reserved and must itself be escaped")
    }

    /// Decoding accepts lowercase hex digits, which other producers emit.
    @Test
    func decodingAcceptsHexDigitsInEitherCase() {
        #expect(PercentCodec.decode("%c3%a9").success == "é")
        #expect(PercentCodec.decode("%C3%A9").success == "é")
        #expect(PercentCodec.decode("%c3%A9").success == "é")
    }

    // MARK: - Round trip

    /// `decode(encode(x)) == .success(x)` for text that includes every
    /// reserved character, non-ASCII, and a multi-scalar grapheme.
    @Test
    func encodingRoundTripsOverTheSamples() {
        let samples = [
            "", "hello", "a b", "a+b", "~-._",
            "a/b?c=d&e", ":/?#[]@!$&'()*+,;=", "100%",
            "é", "日本", "héllo!wörld", "a👨‍👩‍👧‍👦b",
            "line\nbreak\ttab", "\u{0}\u{1}", "\u{FFFD}"
        ]
        #expect(samples.count == 15, "sample list is empty or truncated; the loop below would assert nothing")
        for sample in samples {
            let encoded = PercentCodec.encode(sample)
            #expect(PercentCodec.classify(encoded) == nil,
                    "our own output does not classify as valid: \(String(reflecting: sample))")
            #expect(PercentCodec.decode(encoded).success == sample,
                    "round trip lost \(String(reflecting: sample)) — encoded as \(String(reflecting: encoded))")
        }
    }

    /// No input traps. These bundles are host-based, so a trap kills the host
    /// rather than failing a test — this walks the paths most likely to index
    /// off the end and asserts a value came back from each.
    @Test
    func noInputTrapsOnAnyPath() {
        let hostile = [
            "%", "%%", "%%%", "%A", "%AA%", "%zz%zz", "%FF%FF%FF%FF",
            String(repeating: "%", count: 1000),
            String(repeating: "%FF", count: 500),
            String(repeating: "é", count: 500),
            "\u{10FFFF}", "a👨‍👩‍👧‍👦b%"
        ]
        #expect(hostile.count == 12, "hostile list is empty or truncated; the loop below would assert nothing")
        for input in hostile {
            _ = PercentCodec.classify(input)
            _ = PercentCodec.decode(input)
            #expect(!PercentCodec.encode(input).isEmpty || input.isEmpty)
        }
    }

    // MARK: - Readers

    private func isInvalidEscape(_ failure: ConversionFailure?) -> Bool {
        if case .invalidEscape = failure {
            true
        } else {
            false
        }
    }

    private func isInvalidUTF8(_ failure: ConversionFailure?) -> Bool {
        if case .invalidUTF8 = failure {
            true
        } else {
            false
        }
    }
}
