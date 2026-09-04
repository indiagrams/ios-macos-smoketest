// ConversionFailure — the ONE error type every conversion in this app returns.
//
// D-85: every error names a REASON and a CHARACTER POSITION. Foundation gives
// neither. Measured across 11 inputs, `Data(base64Encoded:)` returns a bare
// `nil` for every failure, and `String.removingPercentEncoding` does the same;
// `Date.ISO8601FormatStyle.parse` throws NSCocoaErrorDomain 2048 with a message
// that names no position. So the reason and the position are hand-written, and
// this type is where their shape is stated once for all four families.
//
// WHY THIS TYPE AND NOT `throws`
//
// 06-RESEARCH.md Pattern 1 (classifier-first conversion). A `throws` convert
// has to decide what to do when the classifier found nothing wrong and
// Foundation still returns `nil` — and that case is not hypothetical. Measured:
// the hand-written Base64 classifier and `Data(base64Encoded:)` disagree on two
// of eighteen inputs, always in the same direction, Foundation being the more
// permissive. Splitting `classify` from `convert` makes the contract statable
// in ONE direction and therefore assertable:
//
//     classify(s) == nil  ⟹  Data(base64Encoded: s) != nil
//
// The converse is measurably false. A `throws` API would have to smuggle a
// "shouldn't happen" branch into the throwing path; a `Result` plus a separate
// `classify` puts the honest answer in the type instead.
//
// WHERE THE STRINGS LIVE
//
// Each case names the `Localizable.xcstrings` key it renders as, so the mapping
// is discoverable from the type. The mapping itself lives in the VIEW layer
// (plan 06-11): the engine must not import SwiftUI and must not know about
// localization. The keys and their English text are 06-UI-SPEC.md
// §"Full string inventory" — ten error strings across nine cases, because
// `unexpectedCharacter` serves two of them.
//
// This file is compiled into the two app targets (which take all of Shared/)
// and into BOTH unit-test targets, by explicit `sources:` entries in
// app/project.yml and app/Project.swift. No test spells the fork's module name.

/// Why a conversion could not be performed, and where in the input it went wrong.
///
/// `Equatable`, so a test can assert the exact expected failure — reason and
/// position together — rather than "some error". `Sendable` with no
/// `@unchecked`: `Character`, `Int` and `String` are all `Sendable`, so the
/// conformance is free and holds under `-strict-concurrency=complete`.
///
/// Positions are **1-based Character (extended grapheme cluster) offsets**,
/// the unit defined by ``characterPosition(utf8Offset:in:)`` in
/// `Shared/Engine/Position.swift`. There is exactly one definition of
/// "position" in this app and it is that one.
enum ConversionFailure: Error, Equatable, Sendable {
    /// A character that cannot appear here at all.
    ///
    /// Renders as `encode.error.base64.character`
    /// ("Not valid Base64: unexpected character '%@' at position %lld.") for
    /// the Base64 alphabet, and as `timestamps.error.notDigit`
    /// ("Not a Unix epoch: '%@' at position %lld is not a digit.") for epochs.
    /// The payload is a whole grapheme, never one byte of a multi-byte one.
    case unexpectedCharacter(Character, position: Int)

    /// The input's length rules it out before any character does.
    ///
    /// Renders as `encode.error.base64.length` ("Not valid Base64: the length
    /// must be a multiple of 4, and it is %lld."). The payload is the LENGTH,
    /// not a position — that is what the string interpolates.
    case badLength(Int)

    /// Base64 padding appears somewhere other than the end.
    ///
    /// Renders as `encode.error.base64.padding` ("Not valid Base64: padding
    /// '=' appears at position %lld, before the end.").
    ///
    /// - Important: The payload is the position of the first NON-padding
    ///   character that follows a `=`, not the position of the `=` itself.
    ///   That is the measured convention in 06-RESEARCH.md's differential
    ///   table and in `TestVectors.base64Corpus`: `"a=GVsbG8="` reports 3 (the
    ///   `G`) while its `=` is at 2, and `"aGVsbG8=x"` reports 9 (the `x`).
    ///   The English string above reads as though it names the `=`. Plan 06-11
    ///   owns that string and must either reword it ("… a character appears at
    ///   position %lld, after the padding") or accept the offset; the engine
    ///   keeps the measured value, because changing a measured number to suit
    ///   prose is how a corpus stops being evidence.
    case paddingBeforeEnd(position: Int)

    /// A `%` that is not followed by two hexadecimal digits.
    ///
    /// Renders as `encode.error.url.escape` ("Not valid percent-encoding:
    /// '%%' at position %lld is not followed by two hexadecimal digits.").
    case invalidEscape(position: Int)

    /// The escapes were well formed but the bytes they produced are not UTF-8.
    ///
    /// Renders as `encode.error.url.utf8` ("Not valid percent-encoding: the
    /// bytes at position %lld are not valid UTF-8."). Also used by Base64
    /// decode, where valid Base64 can decode to bytes that are not text — the
    /// alternative would be mojibake or a crash, and criterion 1 forbids both.
    case invalidUTF8(position: Int)

    /// An HTML entity whose name is not in the table.
    ///
    /// Renders as `encode.error.html.unknown` ("Not a known HTML entity:
    /// '%@' at position %lld."). The payload is the entity as written,
    /// including its `&` and `;`.
    case unknownEntity(String, position: Int)

    /// An `&` with no closing `;`.
    ///
    /// Renders as `encode.error.html.unterminated` ("Unterminated HTML
    /// entity: the '&' at position %lld has no ';'.").
    case unterminatedEntity(position: Int)

    /// A positional template scan found the wrong thing at this position.
    ///
    /// Renders as `timestamps.error.iso8601` ("Not valid ISO 8601: expected
    /// '%@' at position %lld."). The payload is what was expected — a literal
    /// such as `"-"` or `"T"`, or a class such as `"a digit"`.
    case expectedCharacter(String, position: Int)

    /// A value that parses but does not fit.
    ///
    /// Renders as `timestamps.error.range` ("Out of range: %@ is outside the
    /// dates this app can show."). The payload is the value as the user typed
    /// it. Measured: `Int("99999999999999999999")` is `nil`.
    case outOfRange(String)
}
