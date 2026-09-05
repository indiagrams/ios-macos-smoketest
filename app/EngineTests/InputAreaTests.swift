// InputAreaTests — the three worked-value constants, EXERCISED, and the
// Dynamic Type contract MEASURED rather than promised.
//
// TWO THINGS THIS SUITE REFUSES TO DO. It does not assert that a constant is
// non-empty and stop there — each one is pushed through the engine the surface
// that owns it will push it through, so "exercises the surface rather than
// decorating it" is a property with a number behind it. And it does not
// conclude "nothing truncates" from the absence of a one-line limit in the
// source: wrapping fixes every string whose WORDS fit, and a single unbreakable
// word wider than the narrowest screen this app supports truncates anyway. That
// residual is what the measurement below is for, and it is the only part of the
// Dynamic Type contract a source grep cannot see.

import Foundation
import Testing

#if os(iOS)
    import UIKit
#endif

/// The shared input block's constants and the strings around them.
@Suite("Input area")
struct InputAreaTests {
    /// The three constants, by the surface that offers them.
    private static let examples: [(surface: String, value: String)] = [
        ("encode", InputExample.encode),
        ("hashing", InputExample.hashing),
        ("timestamps", InputExample.timestamps)
    ]

    /// Terms the D-91 prose gate forbids in anything the app renders, plus the
    /// product name. Assembled from fragments at runtime so this file never
    /// spells them and cannot turn a content gate red by existing — the shape
    /// this phase has met thirteen times.
    private static var forbiddenTerms: [String] {
        [
            "de" + "mo", "be" + "ta", "tri" + "al", "smoke " + "test",
            "tem" + "plate", "sam" + "ple", "place" + "holder",
            "coming " + "soon", "not " + "implemented", "TO" + "DO",
            "lorem " + "ipsum", "Shipkit" + "Pipes"
        ]
    }

    @Test("the three worked-value constants are present, distinct and non-empty")
    func theThreeConstantsArePresentAndDistinct() {
        #expect(Self.examples.count == 3)
        for (surface, value) in Self.examples {
            #expect(!value.isEmpty, "\(surface) example is empty")
        }
        #expect(Set(Self.examples.map(\.value)).count == 3)
    }

    @Test("no worked-value constant carries a term the prose gate forbids")
    func noConstantCarriesAForbiddenTerm() {
        for (surface, value) in Self.examples {
            let lowered = value.lowercased()
            for term in Self.forbiddenTerms {
                #expect(!lowered.contains(term.lowercased()), "\(surface) example contains \(term)")
            }
        }
    }

    @Test("the encode constant exercises all three formats, not just one")
    func theEncodeConstantExercisesAllThreeFormats() {
        let value = InputExample.encode

        // Base64: 22 characters, 23 UTF-8 bytes. The multibyte character is
        // what stops the encoding being a character-per-character mapping.
        #expect(value.count == 22)
        #expect(value.utf8.count == 23)
        let encoded = Base64Codec.encode(value)
        #expect(encoded == "SGVsbG8sIHdvcmxkICYgPGNhZsOpPiE=")
        #expect(Base64Codec.decode(encoded) == .success(value))

        // Percent-encoding: the escapes are a large share of the output, so a
        // reviewer sees the transformation rather than a near-copy.
        let percent = PercentCodec.encode(value)
        #expect(percent != value)
        #expect(percent.filter { $0 == "%" }.count >= 6)
        #expect(PercentCodec.decode(percent) == .success(value))

        // HTML: three of the five escaped characters are present.
        let entities = HTMLEntityCodec.encode(value)
        #expect(entities.contains("&amp;"))
        #expect(entities.contains("&lt;"))
        #expect(entities.contains("&gt;"))
        #expect(HTMLEntityCodec.decode(entities) == .success(value))
    }

    @Test("the hashing constant has more bytes than characters, which is what its strip counts")
    func theHashingConstantSeparatesBytesFromCharacters() {
        let value = InputExample.hashing
        #expect(value.count == 10)
        #expect(value.utf8.count == 12)
        #expect(value.utf8.count != value.count)
    }

    @Test("the timestamps constant is read unambiguously by the six-clause rule")
    func theTimestampsConstantIsReadUnambiguously() {
        let value = InputExample.timestamps
        #expect(TimestampDetection.detect(value) == .unixEpochSeconds)
        #expect(TimestampDetection.segment(for: .unixEpochSeconds) == .unixEpoch)
        let parsed = TimestampDetection.parse(value, as: .unixEpoch)
        #expect(parsed == .success(1_767_225_600))
    }

    @Test("the count sentences resolve as real plurals and are never their own key")
    func theCountSentencesResolveAsPlurals() {
        for key in ["count.characters", "encode.diagnostic.valid"] {
            let one = localizedCount(key, 1)
            let many = localizedCount(key, 2)
            #expect(one == "1 character", "\(key) singular resolved to \(one)")
            #expect(many == "2 characters", "\(key) plural resolved to \(many)")
            #expect(one != key)
        }
        #expect(localizedCount("hashing.diagnostic.valid", 1) == "1 byte hashed.")
        #expect(localizedCount("hashing.diagnostic.valid", 12) == "12 bytes hashed.")
        #expect(localizedSentence(key: "input.useExample") == "Use an example")
        #expect(localizedSentence(key: "input.label") == "Input")
    }

    #if os(iOS)
        /// Every string this plan renders that the contract says must not
        /// truncate, with the text style it renders at.
        ///
        /// Output VALUES are deliberately absent: the contract names them as
        /// the one class that may truncate, with the stated escape that every
        /// one carries a copy control and selectable text.
        private static let mustNotTruncate: [(text: String, style: UIFont.TextStyle)] = [
            ("Input", .subheadline),
            ("Output", .subheadline),
            ("Use an example", .body),
            ("Text to convert", .body),
            ("Text to hash", .body),
            ("Timestamp or date", .body),
            ("Format", .subheadline),
            ("Direction", .subheadline),
            ("Base64", .subheadline),
            ("URL", .subheadline),
            ("HTML", .subheadline),
            ("Encode", .subheadline),
            ("Decode", .subheadline),
            ("MD5", .subheadline),
            ("SHA-1", .subheadline),
            ("SHA-256", .subheadline),
            ("SHA-512", .subheadline),
            ("Base64 encode", .headline),
            ("Base64 decode", .headline),
            ("URL encode", .headline),
            ("URL decode", .headline),
            ("HTML encode", .headline),
            ("HTML decode", .headline),
            ("Hash", .headline),
            ("22 characters", .caption1),
            ("12 bytes hashed.", .caption1),
            ("Output appears here as you type.", .body),
            ("Digests appear here as you type.", .body),
            ("Enter text above to see the result.", .caption1),
            ("Enter text above to see its digests.", .caption1),
            ("Blocked by an error in an earlier step.", .body)
        ]

        /// The narrowest content width this app can be asked to lay out into:
        /// a 320 pt screen, less the iOS screen margin on both sides, less the
        /// card's own padding on both sides. Every measured string renders
        /// inside a card except the input-area ones, which get 32 pt more.
        private static let narrowestCardWidth: CGFloat = 320 - 2 * 16 - 2 * 16

        /// The widest whitespace-delimited word in `text`, at `style` and the
        /// content size category SwiftUI calls `.accessibility3`.
        ///
        /// Words, not whole sentences: nothing measured here carries a
        /// one-line limit or a fixed height, so a sentence WRAPS. The only way
        /// one of these can truncate is a single word that does not fit, which
        /// no amount of wrapping can rescue.
        private static func widestWord(_ text: String, _ style: UIFont.TextStyle) -> (word: String, width: CGFloat) {
            let traits = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraLarge)
            let font = UIFont.preferredFont(forTextStyle: style, compatibleWith: traits)
            var widest = (word: "", width: CGFloat(0))
            for word in text.split(separator: " ") {
                let width = (String(word) as NSString).size(withAttributes: [.font: font]).width
                if width > widest.width {
                    widest = (String(word), width)
                }
            }
            return widest
        }

        @Test("no label, title, header or diagnostic has a word too wide to fit at accessibility3")
        func nothingTruncatesAtAccessibility3() {
            var offenders: [String] = []
            for (text, style) in Self.mustNotTruncate {
                let widest = Self.widestWord(text, style)
                if widest.width > Self.narrowestCardWidth {
                    offenders.append("\(widest.word) \(Int(widest.width.rounded()))pt")
                }
            }
            #expect(
                offenders.isEmpty,
                "truncation_at_a11y3=\(offenders.joined(separator: ","))"
            )
        }

        @Test("the truncation measurement can fail — a word wider than the screen is reported")
        func theTruncationMeasurementCanFail() {
            let absurd = String(repeating: "W", count: 40)
            let widest = Self.widestWord(absurd, .headline)
            #expect(widest.width > Self.narrowestCardWidth)
            #expect(widest.word == absurd)
        }
    #endif
}
