// Base64Codec — APP-01, and the shape the other three codecs copy.
//
// 06-RESEARCH.md Pattern 1, classifier-first conversion: a hand-written scan
// decides validity, and Foundation is asked only afterwards. The reason is
// D-85 — every error names a REASON and a CHARACTER POSITION, and
// `Data(base64Encoded:)` supplies neither. Measured across 11 inputs, every
// one of its failures is a bare `nil`.
//
// THE CONTRACT, AND HOW IT WAS ACTUALLY ESTABLISHED
//
//     classify(s) == nil  ⟹  Data(base64Encoded: s) != nil
//
// The converse is FALSE and must not be asserted: Foundation decodes
// "aGVsbG8==" (9 characters) and "AB=A" (padding before the end), both of
// which this classifier rejects. A test named for agreement in both
// directions fails on exactly those two inputs. Do not write one.
//
// 06-RESEARCH.md's own classifier — alphabet, padding-before-end, length
// multiple of 4 — does NOT satisfy the forward direction either, which its
// 18-input corpus was too small to show. Brute-forced 2026-09-04 over every
// string of length 4, 8 and 12 from "Ab0+/=" (2.18 billion inputs), it accepts
// a whole class Foundation refuses: a final group of exactly ONE data
// character, such as "A===", "b===" or "AAAAA===". 3,135 counterexamples in
// the length-4 and length-8 slice alone.
//
// So the rule Foundation applies was measured directly rather than inferred:
// it returns nil exactly when the count of NON-PADDING characters is congruent
// to 1 mod 4. A final group of one character carries no whole byte, so there
// is nothing to decode. Every other combination of data characters and padding
// decodes, INCLUDING a whole quantum of padding.
//
//   total=4  data=1 pads=3   nil          total=4  data=0 pads=4  1 byte
//   total=8  data=5 pads=3   nil          total=8  data=4 pads=4  SEE BELOW
//   total=12 data=9 pads=3   nil          total=12 data=0 pads=12 1 byte
//
// CORRECTION, 2026-09-05 (plan 06-20, WR-03). The `data=4 pads=4` cell above
// read "3 bytes", stated as if it were universal. IT IS NOT: that number was
// measured on macOS 26 alone. Re-measured by running the unit suite on four
// runtimes, "AAAA====" decodes to 4 bytes on iOS 17.5, iOS 18.6 and macOS 15
// and to 3 bytes on iOS 26.1 and macOS 26 — a different OUTPUT LENGTH for the
// same input, inside this app's support floor. `classify` now refuses padding
// that has no partial quantum to complete, which covers that shape and "===="
// alike, so the divergence is unobservable in the app. The refusal is asserted
// on all four runtimes rather than argued.
//
// With that check added the same 2.18-billion sweep finds ZERO forward
// counterexamples, as does a 400,000-input random sweep over the full
// 65-character alphabet, and all 18 corpus expectations are unchanged — the
// tightening rejects only inputs the corpus never contained. Base64Tests.swift
// runs a bounded version of both sweeps on every test run.
//
// WHY THE SCAN IS OVER UTF-8 AND THE POSITION IS NOT
//
// `classify` walks `String.UTF8View`; `characterPosition(utf8Offset:in:)` is
// called ONLY on the failure path. Measured in Position.swift: a grapheme walk
// costs 44.6 ms on a 1 MB string against 0.6 ms for the whole encode, and
// D-83/D-84 make this run on every keystroke (T-06-10).
//
// `.ignoreUnknownCharacters` is NEVER used. A decoder that quietly drops what
// the user typed produces the "wrong answer" half of criterion 1 — with that
// option, "  aGVsbG8=  " and "aGVsbG8=x" both decode to "hello" and the user
// is never told their input was not Base64 (T-06-09).

import Foundation

/// Base64 encoding and decoding, with a classifier that is the authority.
///
/// A caseless enum rather than a struct: there is no instance state and there
/// is nothing to construct.
enum Base64Codec {
    /// Why `s` is not valid Base64, or `nil` if it is.
    ///
    /// Checks run in this order, and the order is observable: a character
    /// fault is reported before a length fault, so `"aGVsbG8=x"` reports the
    /// `x` after the padding rather than its length of 9.
    ///
    /// 1. every byte is in the standard alphabet `A-Z a-z 0-9 + /` or is `=`
    /// 2. no alphabet byte follows a `=`
    /// 3. the total length is a multiple of 4
    /// 4. the count of non-padding characters is not congruent to 1 mod 4
    ///
    /// - Note: Total. Every branch returns; there is no force-unwrap, no
    ///   `try!` and no subscript. `characterPosition` and `characterAt` are
    ///   total by construction (see Position.swift), so a failure position can
    ///   never trap — which matters because these unit bundles are host-based
    ///   and a trap would kill the host rather than fail a test.
    /// - Parameter s: Untrusted input of arbitrary length and encoding.
    /// - Returns: `nil` when the input is valid Base64 by the rules above.
    nonisolated static func classify(_ s: String) -> ConversionFailure? {
        var totalCount = 0
        var dataCount = 0
        var offset = 0
        var firstPaddingOffset: Int?

        for byte in s.utf8 {
            switch byte {
            case UInt8(ascii: "="):
                if firstPaddingOffset == nil {
                    firstPaddingOffset = offset
                }
            case UInt8(ascii: "A") ... UInt8(ascii: "Z"),
                 UInt8(ascii: "a") ... UInt8(ascii: "z"),
                 UInt8(ascii: "0") ... UInt8(ascii: "9"),
                 UInt8(ascii: "+"), UInt8(ascii: "/"):
                if firstPaddingOffset != nil {
                    return .paddingBeforeEnd(position: characterPosition(utf8Offset: offset, in: s))
                }
                dataCount += 1
            default:
                return .unexpectedCharacter(characterAt(utf8Offset: offset, in: s),
                                            position: characterPosition(utf8Offset: offset, in: s))
            }
            offset += 1
            totalCount += 1
        }

        // Any input reaching here is all-ASCII, so the byte count and the
        // Character count coincide and either is the length the UI-SPEC's
        // `encode.error.base64.length` means.
        if totalCount % 4 != 0 {
            return .badLength(totalCount)
        }

        // A final group of one data character. Measured: Foundation refuses
        // these, so accepting them would break the contract above and leave
        // `decode` holding a `nil` it has no reason to explain. Reported as
        // the padding that cannot be there, which is both true and the most
        // actionable thing to say — `encode.error.base64.length` would claim
        // the length is not a multiple of 4 when it is.
        if dataCount % 4 == 1 {
            guard let paddingOffset = firstPaddingOffset else {
                // Unreachable: with no padding, totalCount == dataCount and the
                // length check above already returned. Kept so the function is
                // total by inspection rather than by argument.
                return .badLength(totalCount)
            }
            return .unexpectedCharacter(characterAt(utf8Offset: paddingOffset, in: s),
                                        position: characterPosition(utf8Offset: paddingOffset, in: s))
        }

        // PADDING COMPLETES A PARTIAL FINAL QUANTUM AND HAS NO OTHER JOB. When
        // the data characters already fill whole quanta there is nothing left
        // to complete, so RFC 4648 does not consider the padding valid — and
        // more importantly, **Foundation's answer for that shape is NOT STABLE
        // ACROSS THIS APP'S DEPLOYMENT FLOOR.** Measured 2026-09-05 by running
        // this suite on four runtimes:
        //
        //   input          iOS 17.5   iOS 18.6   iOS 26.1   macOS 26   macOS 15
        //   "AAAA===="     4 bytes    4 bytes    3 bytes    3 bytes    4 bytes
        //   "AAAAAAAA====" 7 bytes    7 bytes    6 bytes    6 bytes    —
        //
        // A trailing all-padding quantum contributes an extra NUL byte on the
        // older runtimes and nothing on the newer ones. Accepting it would mean
        // the app hands the user a DIFFERENT NUMBER OF BYTES for the same input
        // depending on which OS they are running, which is the one thing these
        // codecs exist to prevent — the same answer `TimestampTemplateScan`
        // gives for `2026-02-31` and this file already gives for `"AB=A"`:
        // refuse it on every OS, and the variance becomes unobservable.
        //
        // This also retires the last source of a NUL byte in a "successful"
        // output, which `OutputPasteboard` would write to the general
        // pasteboard where any C-string consumer truncates it.
        //
        // `""` is unaffected: no padding, so nothing to reject.
        if dataCount % 4 == 0, let paddingOffset = firstPaddingOffset {
            return .unexpectedCharacter(characterAt(utf8Offset: paddingOffset, in: s),
                                        position: characterPosition(utf8Offset: paddingOffset, in: s))
        }

        return nil
    }

    /// The Base64 spelling of `s`'s UTF-8 bytes.
    ///
    /// - Note: Total and cannot fail. Every String has a UTF-8 encoding and
    ///   every byte sequence has a Base64 spelling, so there is no error path
    ///   here and none should be invented for symmetry with ``decode(_:)``.
    nonisolated static func encode(_ s: String) -> String {
        Data(s.utf8).base64EncodedString()
    }

    /// The text `s` decodes to, or why it does not.
    ///
    /// - Important: **The classifier is the authority.** When ``classify(_:)``
    ///   returns a failure this returns that same failure and
    ///   `Data(base64Encoded:)` is never called. That is what makes the app's
    ///   answer independent of Foundation's extra permissiveness — and, for
    ///   `"AB=A"`, independent of the OS version: 06-02 measured that input
    ///   decoding on macOS 26.1 and iOS 26.1 and returning nil on iOS 18.6,
    ///   inside this app's iOS 17.0 floor. The classifier rejects it on every
    ///   OS, so the variance is unobservable.
    /// - Note: Total. The only Foundation results consulted are Optionals, and
    ///   both are handled with `guard`.
    /// - Returns: `.success` with the decoded text, or `.failure` naming a
    ///   reason and a position.
    nonisolated static func decode(_ s: String) -> Result<String, ConversionFailure> {
        if let failure = classify(s) {
            return .failure(failure)
        }

        guard let data = Data(base64Encoded: s) else {
            // Unreachable while the contract holds — measured over 2.18 billion
            // swept inputs and the 18-row corpus. If it ever fires, that is a
            // FINDING about a Foundation behaviour that moved, not a case to
            // paper over: re-measure, and give it its own ConversionFailure
            // case rather than leaving this approximation in place.
            return .failure(.badLength(s.utf8.count))
        }

        let bytes = [UInt8](data)
        if let invalidOffset = firstInvalidUTF8Offset(bytes) {
            return .failure(.decodedBytesAreNotUTF8(position: inputPosition(ofDecodedByte: invalidOffset, in: s)))
        }
        guard let text = String(bytes: bytes, encoding: .utf8) else {
            // Unreachable because the scan above is strictly STRICTER than
            // this initializer, never the other way round — asserted over
            // random bytes in Base64Tests. A failure keeps the path total
            // where a force-unwrap would trap and kill the host.
            return .failure(.decodedBytesAreNotUTF8(position: 1))
        }
        return .success(text)
    }

    /// The 1-based CHARACTER position, in the INPUT, of the quantum that
    /// produced the decoded byte at `decodedOffset`.
    ///
    /// - Important: **The position a user is shown must be a position in the
    ///   string the user typed.** `Position.swift` states there is exactly ONE
    ///   definition of position in this app and it is a 1-based Character
    ///   offset into the input. Until 2026-09-05 this path reported
    ///   `invalidOffset + 1`, a byte offset into the decoded OUTPUT — a string
    ///   the user cannot see. Measured: `decode("YWJj/w==")` reported 4, and
    ///   character 4 of that input is `j`, a perfectly valid Base64 character
    ///   sitting in the quantum BEFORE the one at fault (CR-03).
    /// - Note: Base64 is a 4:3 code, so output byte `i` comes from input
    ///   characters `4*(i/3) … 4*(i/3)+3` and the honest answer is the first of
    ///   them. The result is therefore always one of 1, 5, 9, …, which
    ///   `everyReportedPositionStartsAQuantum` sweeps rather than samples.
    /// - Note: The offset is resolved through
    ///   ``characterPosition(utf8Offset:in:)`` even though the input is pure
    ///   ASCII here — the classifier has already refused everything outside the
    ///   alphabet, so byte and Character offsets coincide. The DEFINITION is
    ///   what must not fork, not the arithmetic; going around it is how this
    ///   path came to report an output offset in the first place.
    /// - Note: Total. `decodedOffset` is only ever divided and multiplied by
    ///   small constants and is bounded by the decoded length, so no overflow
    ///   is reachable, and `characterPosition` is total for every `Int`.
    private nonisolated static func inputPosition(ofDecodedByte decodedOffset: Int, in s: String) -> Int {
        let quantumStart = (decodedOffset / 3) * 4
        return characterPosition(utf8Offset: quantumStart, in: s)
    }

    /// The 0-based offset of the first byte that cannot start or continue a
    /// well-formed UTF-8 sequence, or `nil` when `bytes` is valid UTF-8.
    ///
    /// This exists for two measured reasons, not one.
    ///
    /// The first is D-85: `String(bytes:encoding:)` answers the same question
    /// and gives no position.
    ///
    /// The second is that it does not reliably answer the same question.
    /// MEASURED 2026-09-04 by running the suite on three runtimes: on **iOS
    /// 17.5**, inside this app's iOS 17.0 floor, `String(bytes: [0xA9],
    /// encoding: .utf8)` returns `Optional("\u{FFFD}")` rather than nil — it
    /// silently repairs the byte. On iOS 18.6 and macOS 26.1 the same call
    /// returns nil. `0xA9` is the only byte in `0x80...0xFF` that differs,
    /// enumerated exhaustively on all three. A decoder that trusted that
    /// initializer would show a replacement character in place of the user's
    /// byte and call it success, on the oldest supported OS only.
    ///
    /// So this scan is the authority for validity, and it is asserted to be
    /// never MORE permissive than Foundation — the one direction that holds —
    /// in `Base64Tests.theUTF8ScanIsNeverMorePermissiveThanFoundation`.
    ///
    /// The ranges are the Unicode 15 well-formed byte-sequence table: `0xC0`
    /// and `0xC1` are always overlong, `0xE0` needs a continuation of `0xA0`
    /// or above, `0xED` must stay below `0xA0` to exclude surrogates, `0xF0`
    /// needs `0x90` or above and `0xF4` must stay at or below `0x8F` to stop
    /// at U+10FFFF.
    ///
    /// - Note: Total. Every subscript is bounds-checked by the `guard` on the
    ///   sequence width before it, so this cannot trap on a truncated
    ///   sequence at the end of the array.
    nonisolated static func firstInvalidUTF8Offset(_ bytes: [UInt8]) -> Int? {
        var index = 0
        while index < bytes.count {
            let lead = bytes[index]
            if lead < 0x80 {
                index += 1
                continue
            }
            guard let shape = sequenceShape(forLead: lead) else { return index }
            guard index + shape.width <= bytes.count else { return index }
            let second = bytes[index + 1]
            guard second >= shape.secondLowerBound, second <= shape.secondUpperBound else { return index }
            var continuation = index + 2
            while continuation < index + shape.width {
                if bytes[continuation] < 0x80 || bytes[continuation] > 0xBF {
                    return index
                }
                continuation += 1
            }
            index += shape.width
        }
        return nil
    }

    /// The width of the sequence a non-ASCII lead byte starts, and the range
    /// its FIRST continuation byte must fall in.
    ///
    /// The second byte's range is narrower than `0x80...0xBF` for three lead
    /// bytes, and each narrowing excludes a real ill-formed class rather than
    /// being decorative: `0xE0` with a second byte below `0xA0` is an overlong
    /// three-byte form, `0xED` with `0xA0` or above is a UTF-16 surrogate, and
    /// `0xF4` with `0x90` or above is beyond U+10FFFF. `0xC0` and `0xC1` are
    /// absent because every sequence they start is overlong, and `0xF5...0xFF`
    /// because no scalar needs them.
    ///
    /// - Returns: `nil` when `lead` cannot start a sequence at all.
    private nonisolated static func sequenceShape(forLead lead: UInt8) -> UTF8SequenceShape? {
        switch lead {
        case 0xC2 ... 0xDF: UTF8SequenceShape(width: 2)
        case 0xE0: UTF8SequenceShape(width: 3, secondLowerBound: 0xA0)
        case 0xE1 ... 0xEC, 0xEE ... 0xEF: UTF8SequenceShape(width: 3)
        case 0xED: UTF8SequenceShape(width: 3, secondUpperBound: 0x9F)
        case 0xF0: UTF8SequenceShape(width: 4, secondLowerBound: 0x90)
        case 0xF1 ... 0xF3: UTF8SequenceShape(width: 4)
        case 0xF4: UTF8SequenceShape(width: 4, secondUpperBound: 0x8F)
        default: nil
        }
    }

    /// How many bytes a UTF-8 sequence occupies and what its first
    /// continuation byte is allowed to be.
    private struct UTF8SequenceShape {
        let width: Int
        var secondLowerBound: UInt8 = 0x80
        var secondUpperBound: UInt8 = 0xBF
    }
}
