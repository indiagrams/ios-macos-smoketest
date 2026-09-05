// WarningTriageTests — the review WARNINGs that were fixed, and the one that
// was deliberately NOT fixed, asserted rather than left to prose (plan 06-20).
//
// Three findings live here, and the third is the interesting one.
//
// WR-02: `parseEpoch` reported "Out of range" for input containing no digits
// at all. Measured at 929ba9c, `parse("+", as: .unixEpoch)` was
// `.outOfRange("+")` and rendered "Out of range: + is outside the dates this
// app can show.", and `parse("")` rendered the same sentence with an EMPTY
// `%@` slot. Neither is true: those are not numbers out of range, they are not
// numbers. `.outOfRange` is also the one `ConversionFailure` case carrying no
// position, so this was the single place in the subject where D-85's "every
// error names a reason AND a position" was absent.
//
// WR-03, entity half: `&#0;` resolved to U+0000 and `decode("a&#0;b")`
// returned `.success("a\0b")`. `OutputPasteboard` writes that to the general
// pasteboard verbatim and any C-string consumer truncates at the NUL, so a
// tool whose premise is "the value you get back is the value you can paste
// elsewhere" returned a value that silently truncates on paste. Now refused by
// name, next to the surrogate refusal.
//
// WR-03, Base64 half: **NOT CHANGED, AND THAT IS THE POINT.** `decode("====")`
// still returns `.success("\0")`. The classifier deliberately mirrors
// Foundation's acceptance of a whole quantum of padding, which
// `Base64Codec.swift` documents, and RFC 4648 does not consider that valid
// Base64 at all. The review named three options and called silence the only
// unacceptable one. Parity is KEPT and ASSERTED here, so the choice is
// recorded in an executed test rather than in a comment — and so the day
// somebody changes it, they have to change this test and say why.

import Foundation
import Testing

/// The review warnings this plan closed, and the one it kept on purpose.
@Suite("Warning triage")
struct WarningTriageTests {
    // MARK: - WR-02

    /// A lone sign is reported as a non-digit at a position, not as a value out
    /// of range.
    ///
    /// The sentence this produces is `timestamps.error.notDigit` — "Not a Unix
    /// epoch: '+' at position 1 is not a digit." — which is true, where the old
    /// one was not.
    @Test
    func aLoneSignIsNotADigitRatherThanOutOfRange() {
        for sign in ["+", "-"] {
            let failure = TimestampDetection.parse(sign, as: .unixEpoch).failure
            #expect(failure == .unexpectedCharacter(Character(sign), position: 1), "\(sign)")
            guard let failure else { continue }
            #expect(failureStringKey(failure, in: .timestamps) == "timestamps.error.notDigit")
            #expect(failureText(failure, in: .timestamps) == "Not a Unix epoch: '\(sign)' at position 1 is not a digit.")
        }
    }

    /// Every failure on this path now carries a position, which is what
    /// `.outOfRange` could not do.
    @Test
    func theNoDigitPathCarriesAPosition() {
        for input in ["+", "-", ""] {
            guard case let .unexpectedCharacter(_, position)? = TimestampDetection.parse(input, as: .unixEpoch).failure
            else {
                Issue.record("\(String(reflecting: input)) should report a non-digit with a position")
                continue
            }
            #expect(position == 1, "\(String(reflecting: input))")
        }
    }

    /// Genuine out-of-range input is untouched: it still reports
    /// `.outOfRange` carrying the value the user typed.
    ///
    /// Asserted so the WR-02 change cannot be read as having removed the case.
    /// `Int("99999999999999999999")` is measured `nil`, and a 20-digit run is
    /// how clause 6 is actually reached.
    @Test
    func realOutOfRangeInputStillReportsOutOfRange() {
        #expect(TimestampDetection.parse("99999999999999999999", as: .unixEpoch).failure
            == .outOfRange("99999999999999999999"))
        #expect(TimestampDetection.parse("-99999999999999999999", as: .unixEpoch).failure
            == .outOfRange("-99999999999999999999"))
    }

    /// A digit anywhere in the run still takes the numeric path, so the guard
    /// above cannot be reached by anything that is a number.
    @Test
    func aSignedNumberStillParses() {
        #expect(TimestampDetection.parse("+1788480000", as: .unixEpoch).success == 1_788_480_000)
        #expect(TimestampDetection.parse("-1", as: .unixEpoch).success == -1)
    }

    // MARK: - WR-03, entity half

    /// The null character reference is refused by name rather than resolved.
    @Test
    func theNullCharacterReferenceIsRefused() {
        for input in ["a&#0;b", "&#0;", "&#x0;", "&#00;", "&#x000;"] {
            let failure = HTMLEntityCodec.decode(input).failure
            #expect(failure != nil, "\(input) must not decode to a NUL")
        }
    }

    /// No successful HTML decode contains a NUL, swept rather than sampled.
    ///
    /// The floor on `decoded` is what keeps this from passing by decoding
    /// nothing — a property over an empty set is vacuously true.
    @Test
    func noSuccessfulEntityDecodeContainsANul() {
        var generator = SeededGenerator(seed: 0x0620_0002)
        let pool: [Character] = Array("&#x;0123456789abcdefABCDEFgtltampquotapos")
        var decoded = 0
        for _ in 0 ..< 3000 {
            let input = generator.randomString(from: pool, maxLength: 12)
            guard let text = HTMLEntityCodec.decode(input).success else { continue }
            decoded += 1
            #expect(!text.unicodeScalars.contains("\u{0}"), "\(String(reflecting: input)) decoded to a NUL")
        }
        #expect(decoded >= 100, "the sweep must actually decode things; it decoded \(decoded)")
    }

    /// Everything else about numeric references is unchanged — the guard is one
    /// value wide and not a new policy.
    @Test
    func otherNumericReferencesStillDecode() {
        #expect(HTMLEntityCodec.decode("&#65;").success == "A")
        #expect(HTMLEntityCodec.decode("&#x41;").success == "A")
        #expect(HTMLEntityCodec.decode("&#1;").success == "\u{1}")
        #expect(HTMLEntityCodec.decode("&#xD800;").failure != nil, "surrogates were already refused")
        #expect(HTMLEntityCodec.decode("&#x110000;").failure != nil, "above U+10FFFF was already refused")
    }

    // MARK: - WR-03, Base64 half — KEPT, and asserted because it was kept

    /// A whole quantum of padding decodes to NUL bytes, and this app agrees
    /// with Foundation about that ON PURPOSE.
    ///
    /// RFC 4648 does not consider `"===="` valid Base64. `Base64Codec` accepts
    /// it because the classifier mirrors `Data(base64Encoded:)` here and that
    /// mirroring is what makes the one-directional contract hold. The review
    /// named three options — keep parity and assert it, add a length rule, or
    /// stay silent — and said silence was the only unacceptable one. Parity is
    /// kept, so it is asserted: this test is the record of the decision, and
    /// changing the behaviour means changing this test and saying why.
    @Test
    func aWholeQuantumOfPaddingStillDecodesToNulAndThatIsDeliberate() {
        #expect(Base64Codec.classify("====") == nil, "the classifier accepts it, mirroring Foundation")
        // Measured, not assumed: `"===="` yields ONE NUL and `"AAAA===="`
        // yields THREE, the same as `"AAAA"` — Foundation drops the trailing
        // all-padding quantum rather than decoding it to a fourth byte.
        #expect(Base64Codec.decode("====").success == "\u{0}")
        #expect(Base64Codec.decode("AAAA====").success == "\u{0}\u{0}\u{0}")
        #expect(Base64Codec.decode("AAAA====").success == Base64Codec.decode("AAAA").success)
    }
}
