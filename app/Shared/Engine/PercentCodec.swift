// PercentCodec — APP-02, RFC 3986 percent-encoding, in the Base64Codec shape.
//
// 06-RESEARCH.md Pattern 1, classifier-first conversion: a hand-written scan
// decides validity and Foundation is asked only afterwards. D-85 is the reason
// — every error names a REASON and a CHARACTER POSITION, and
// `String.removingPercentEncoding` supplies neither. Every one of its failures
// is a bare `nil`.
//
// THE CONTRACT, AND THE MEASUREMENT BEHIND IT
//
//     classify(s) == nil  ⟹  s.removingPercentEncoding != nil
//
// Swept before anything here was written, on macOS 26.5.2, over three
// populations totalling 121,779 inputs: every string of length 0…6 over
// ["%","A","2","z","-","é"] (55,987), "a%XX" for every byte (256), and
// "%XX%YY" for every byte pair (65,536). FORWARD COUNTEREXAMPLES: 0.
//
// The CONVERSE IS FALSE and must not be asserted. 258 counterexamples, and
// every single one of them is the same byte:
//
//     "%A9".removingPercentEncoding == Optional("\u{FFFD}")
//
// `removingPercentEncoding` does not reject 0xA9 — it REPAIRS it to U+FFFD.
// Enumerated exhaustively over 0x80…0xFF, it is the only high byte Foundation
// accepts alone, and all 257 disagreements in the byte-pair sweep contain
// `%A9` and are all repaired the same way.
//
// This is a DIFFERENT defect from the one 06-03 recorded, in a different API
// and on a different runtime. 06-03 measured `String(bytes: [0xA9], encoding:
// .utf8)` returning U+FFFD on iOS 17.5 only; on macOS 26.5.2 that same call
// returns nil while `removingPercentEncoding` of the same byte returns U+FFFD,
// in the same process. Two Foundation entry points, two answers. 0xA9 is
// U+00A9 COPYRIGHT SIGN in Mac OS Roman, which is the shape of a legacy
// CFString fallback.
//
// So the classifier is load-bearing rather than decorative: a decoder that
// trusted Foundation would answer "a\u{FFFD}" for the input "a%A9" and call it
// SUCCESS, showing the user a replacement character where their byte was, with
// no error at all. That is the "wrong answer" half of ROADMAP criterion 1.
// `PercentTests.theByteFoundationRepairsIsStillReportedInvalid` is the
// assertion that keeps it out of the app, on every runtime.
//
// WHY THE ALLOWED SET IS BYTES AND NOT A `CharacterSet`
//
// 06-RESEARCH Pitfall 3 recommends `CharacterSet.alphanumerics` with "-._~"
// inserted, named "ALPHA / DIGIT". Those are not the same set —
// `.alphanumerics` is the Unicode L*/M*/N* categories, and it CONTAINS "é"
// (measured). By the set as written, `encode("é")` would return "é" unchanged.
// It does not, but only because `addingPercentEncoding` restricts the allowed
// set to ASCII itself, which is undocumented and contradicts the set. Relying
// on it would also force `encode` — which this plan requires to be TOTAL — to
// unwrap an Optional it can never see fail, i.e. to carry an untestable
// branch. The unreserved production is therefore spelled out here as bytes,
// once, and `PercentTests.encodeAgreesWithFoundationsCustomSetRoute` measures
// the two routes against each other on every runtime so a divergence is a
// finding rather than a surprise.
//
// WHY THE SCAN IS OVER UTF-8 AND THE POSITION IS NOT
//
// `classify` walks the UTF-8 bytes; `characterPosition(utf8Offset:in:)` is
// called ONLY on the failure path. Measured in Position.swift: a grapheme walk
// costs 44.6 ms on a 1 MB string against 0.6 ms for a whole encode, and
// D-83/D-84 make this run on every keystroke (T-06-10).

import Foundation

/// RFC 3986 percent-encoding and decoding, with a classifier that is the
/// authority.
///
/// A caseless enum rather than a struct: there is no instance state and there
/// is nothing to construct.
enum PercentCodec {
    /// RFC 3986 §2.3 unreserved: `ALPHA / DIGIT / "-" / "." / "_" / "~"`.
    ///
    /// Spelled out rather than derived from a `CharacterSet`, for the reason
    /// in the file header. This is the ONE definition of the allowed set; both
    /// `encode` and the tests' regression assertions read from it.
    ///
    /// - Note: A `static let` inside the namespace rather than a `private let`
    ///   at file scope. `Set<UInt8>` is `Sendable`, so this compiles clean
    ///   under `-swift-version 6 -strict-concurrency=complete` with no
    ///   `nonisolated(unsafe)` — which APP-12 and ROADMAP criterion 5 forbid
    ///   by name.
    static let unreserved: Set<UInt8> = Set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".utf8
    )

    /// Uppercase hex digits, because RFC 3986 §2.1 says producers should emit
    /// uppercase. Decoding accepts either case.
    private static let upperHexDigits: [Character] = Array("0123456789ABCDEF")

    /// Why `s` is not valid percent-encoded text, or `nil` if it is.
    ///
    /// Two distinct failure classes, because 06-UI-SPEC.md defines two
    /// distinct strings for them:
    ///
    /// 1. `.invalidEscape` — a `%` not followed by two hexadecimal digits,
    ///    rendering as `encode.error.url.escape`
    /// 2. `.invalidUTF8` — the escapes were well formed but the bytes they
    ///    produce are not UTF-8, rendering as `encode.error.url.utf8`
    ///
    /// Both name the 1-based Character position of the `%` that begins the
    /// offending escape.
    ///
    /// - Note: Total. Every branch returns; there is no force-unwrap, no
    ///   `try!` and no unguarded subscript. `characterPosition` is total by
    ///   construction (see Position.swift), so a failure position can never
    ///   trap — which matters because these unit bundles are host-based and a
    ///   trap would kill the host rather than fail a test.
    /// - Parameter s: Untrusted input of arbitrary length and encoding.
    /// - Returns: `nil` when the input decodes to well-formed UTF-8 text.
    nonisolated static func classify(_ s: String) -> ConversionFailure? {
        let scan: PercentScan
        switch scanEscapes(s) {
        case let .failure(failure): return failure
        case let .success(result): scan = result
        }

        guard let invalidIndex = Base64Codec.firstInvalidUTF8Offset(scan.bytes) else {
            return nil
        }
        guard scan.origins.indices.contains(invalidIndex) else {
            // Unreachable: `origins` is appended to in lockstep with `bytes`,
            // so the two have the same count and any index into one is an
            // index into the other. Kept so the function is total by
            // inspection rather than by argument.
            return .invalidUTF8(position: 1)
        }
        return .invalidUTF8(position: characterPosition(utf8Offset: scan.origins[invalidIndex], in: s))
    }

    /// The percent-encoded spelling of `s`, escaping every byte outside the
    /// RFC 3986 §2.3 unreserved set.
    ///
    /// - Note: Total and cannot fail. Every String has a UTF-8 encoding and
    ///   every byte has a `%XX` spelling, so there is no error path here and
    ///   none should be invented for symmetry with ``decode(_:)``.
    /// - Important: Neither `.urlQueryAllowed` nor `.urlPathAllowed` nor
    ///   `.alphanumerics` is used, and each is wrong in its own measured way:
    ///   `"a/b?c=d&e"` comes back UNCHANGED from the first, comes back with
    ///   only the `?` escaped from the second, and `"~-._"` becomes
    ///   `"%7E%2D%2E%5F"` under the third although RFC 3986 §2.3 lists all
    ///   four as unreserved.
    nonisolated static func encode(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        for byte in s.utf8 {
            if unreserved.contains(byte) {
                out.append(Character(UnicodeScalar(byte)))
            } else {
                // The nibble is 0...15 and the table has 16 entries, so
                // neither subscript can be out of range.
                out.append("%")
                out.append(upperHexDigits[Int(byte >> 4)])
                out.append(upperHexDigits[Int(byte & 0x0F)])
            }
        }
        return out
    }

    /// The text `s` decodes to, or why it does not.
    ///
    /// - Important: **The classifier is the authority.** When ``classify(_:)``
    ///   returns a failure this returns that same failure and
    ///   `removingPercentEncoding` is never called. That is what makes the
    ///   app's answer independent of Foundation's repair of `%A9` — see the
    ///   file header.
    /// - Note: Total. The only Foundation result consulted is an Optional and
    ///   it is handled with `guard`.
    /// - Returns: `.success` with the decoded text, or `.failure` naming a
    ///   reason and a position.
    nonisolated static func decode(_ s: String) -> Result<String, ConversionFailure> {
        if let failure = classify(s) {
            return .failure(failure)
        }

        guard let text = s.removingPercentEncoding else {
            // Unreachable while the contract holds — 0 counterexamples over
            // 121,779 swept inputs, re-swept on every test run by
            // `classifyingValidImpliesFoundationDecodes`. If it ever fires,
            // that is a FINDING about a Foundation behaviour that moved, not a
            // case to paper over: re-measure, and give it its own
            // ConversionFailure case rather than leaving this approximation.
            return .failure(.invalidUTF8(position: 1))
        }
        return .success(text)
    }

    /// The bytes `s`'s escapes produce, and where each came from.
    ///
    /// `origins[i]` is the UTF-8 offset in `s` of the byte that produced
    /// `bytes[i]` — the `%` when it came from an escape, the byte itself
    /// otherwise. That mapping is what lets an invalid-UTF-8 verdict name a
    /// position in the INPUT rather than in the decoded output.
    private struct PercentScan {
        let bytes: [UInt8]
        let origins: [Int]
    }

    /// Walk `s`, decoding escapes, or fail at the first malformed one.
    ///
    /// - Note: Total. The two-byte lookahead is bounds-checked by the `guard`
    ///   before either subscript, so a `%` at the very end of the input cannot
    ///   trap.
    private nonisolated static func scanEscapes(_ s: String) -> Result<PercentScan, ConversionFailure> {
        let source = Array(s.utf8)
        var bytes = [UInt8]()
        var origins = [Int]()
        bytes.reserveCapacity(source.count)
        origins.reserveCapacity(source.count)

        var index = 0
        while index < source.count {
            guard source[index] == UInt8(ascii: "%") else {
                bytes.append(source[index])
                origins.append(index)
                index += 1
                continue
            }
            guard index + 2 < source.count,
                  let high = hexDigitValue(source[index + 1]),
                  let low = hexDigitValue(source[index + 2])
            else {
                return .failure(.invalidEscape(position: characterPosition(utf8Offset: index, in: s)))
            }
            // `high` is at most 15, so `high << 4` is at most 240 and the
            // combination cannot overflow UInt8.
            bytes.append(high << 4 | low)
            origins.append(index)
            index += 3
        }
        return .success(PercentScan(bytes: bytes, origins: origins))
    }

    /// The numeric value of an ASCII hexadecimal digit, in either case, or
    /// `nil` when `byte` is not one.
    private nonisolated static func hexDigitValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0") ... UInt8(ascii: "9"): byte - UInt8(ascii: "0")
        case UInt8(ascii: "a") ... UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A") ... UInt8(ascii: "F"): byte - UInt8(ascii: "A") + 10
        default: nil
        }
    }
}
