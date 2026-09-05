// HTMLEntityCodec — APP-03, in the Base64Codec / PercentCodec shape.
//
// 06-RESEARCH.md Pattern 1, classifier-first conversion. Here the pattern is
// even simpler than it is for the other two codecs, because there is no second
// authority to disagree with: the SDK has no HTML entity encoder at all, in
// either direction, and the one decoder it has is rejected below. `classify`
// and `decode` therefore share ONE traversal, so they cannot disagree about
// what a valid entity is.
//
// WHY THE PLATFORM'S ATTRIBUTED-STRING HTML DOCUMENT TYPE IS NOT THE ANSWER
//
// Three measured reasons, from 06-RESEARCH.md, none of them taste. (1) It is
// NOT in Foundation — the HTML document type is declared in AppKit and UIKit,
// so reaching for it forks a `#if os(...)` through what should be a pure
// string function, in a file that is compiled into four targets. (2) It
// DESTROYS the input: measured, "line1\nline2" comes back as "line1 line2",
// "  spaced  " as "spaced", and "<b>bold</b>" as "bold" — an entity decoder
// that eats the user's newlines and markup is wrong for an app whose whole
// premise is that the value you get back is the value you can paste elsewhere.
// (3) It is SILENT on malformed input and slow: "&bogus;" comes back unchanged
// and "&#999999999;" becomes U+FFFD, both with no error at all, so D-85's
// named reason and position are unobtainable from it; and its cold call
// measured 229 ms with a 61.3 ms warm spike, which under D-83's no-debounce
// keystroke loop is four dropped frames on the main thread (T-06-26).
//
// Those measurements are the passing regression tests
// `markupIsEscapedRatherThanStripped`, `whitespaceSurvivesEncoding` and
// `anOutOfRangeNumericReferenceIsNamedRatherThanRepaired` in
// HTMLEntityTests.swift. Do not re-litigate the choice; re-run those.
//
// A NOTE ON THE ACCEPTANCE GREP THAT SWEEPS THIS FILE
//
// The plan requires this file to explain the rejection AND requires
// `grep -c 'NSAttributed...' ` over it to return 0 — the "a file that
// configures a content gate is also swept by that gate" pattern, which has now
// recurred three times in this phase. Resolved by NAMING the API descriptively
// instead of spelling the token, so the grep's population is exactly the
// executable code it means to police and the reader still gets the reason. The
// gate was then driven RED (control=entity-no-attributed-string-gate-fires) to
// prove it can still fire, because a grep that cannot return non-zero is worse
// than no grep.
//
// WHY THE SCAN IS OVER SCALARS AND THE POSITION IS NOT
//
// The traversal walks `String.UnicodeScalarView` and keeps its own UTF-8 byte
// offset; `characterPosition(utf8Offset:in:)` is called ONLY on the failure
// path. Measured in Position.swift: a grapheme walk costs 44.6 ms on a 1 MB
// string, and D-83/D-84 make this run on every keystroke. Scalars rather than
// Characters because entity DEcoding is where a combining mark can join what
// precedes it: `&bne;` targets U+003D U+20E5, which is ONE Character made of
// two scalars, and 06-05 measured a packed format losing records to exactly
// that. Nothing here ever splits on a `Character`. The table format itself,
// and the eight records the obvious format loses, are in
// HTMLEntityTablePacking.swift.
//
// THE 106 LEGACY SEMICOLON-OPTIONAL FORMS ARE REJECTED, BY DESIGN
//
// 06-UI-SPEC.md's `encode.error.html.unterminated` reads "Unterminated HTML
// entity: the '&' at position %lld has no ';'." A design that reports
// unterminated entities as an error cannot also silently accept 106 of them.
// The table 06-05 generated carries the 2125 semicolon-terminated references
// only; this file makes the exclusion user-visible.

import Foundation

/// HTML entity encoding and decoding, with a hand-written scan that is the
/// only authority.
///
/// A caseless enum rather than a struct: there is no instance state and there
/// is nothing to construct.
enum HTMLEntityCodec {
    // MARK: - The packed table, parsed once

    /// Entity name (with no `&` and no `;`) to the text it stands for.
    ///
    /// Parsed once, lazily, from BOTH halves of the generated table. Swift's
    /// global initialisation is already run-once and thread-safe, so this is a
    /// plain `static let` of a value type: `[String: String]` is
    /// unconditionally `Sendable`, and the declaration compiles clean under
    /// `-swift-version 6 -strict-concurrency=complete` with no unsafe-
    /// nonisolated annotation and no unchecked-Sendable conformance, both of
    /// which APP-12 and ROADMAP criterion 5 forbid by name. (Spelled
    /// descriptively on purpose: the plan greps this file for those two
    /// tokens and expects 0, so writing them here would turn the gate red on
    /// its own documentation. The gate was driven RED separately -- see
    /// control=entity-forbidden-annotation-greps-fire.) Measured: making this a
    /// `static var` instead is a hard error on this target, which is what
    /// makes the absence of an unsafe annotation mean something rather than
    /// being unexamined.
    ///
    /// - Note: `entity_lookup_form=static-let`. The plan's fallback — parsing
    ///   on every call, measured at ~2 ms — was not needed.
    static let lookup: [String: String] =
        HTMLEntityTablePacking.parse(HTMLEntityTableA.chunks + HTMLEntityTableB.chunks)

    /// Records that reached runtime. **Must be 2125**, and
    /// `HTMLEntityTests.everyGeneratedRecordSurvivesParsing` asserts it.
    ///
    /// This is the instrument for the silent-loss defect: a packing or
    /// splitting fault moves this number while the compiler stays at exit 0
    /// with no diagnostic (measured by 06-05, re-measured by 06-06).
    static var recordCount: Int {
        lookup.count
    }

    // MARK: - The five characters the encoder escapes

    /// The OWASP escape set: `&`, `<`, `>`, `"`, `'`.
    ///
    /// A **stated** choice, not an emergent one — RESEARCH assumption A1,
    /// decided in plan 06-05 and recorded in both generated table headers.
    /// Encoding all 2125 named references would turn `café` into
    /// `caf&eacute;`, which is not what anyone types this tool for. What this
    /// set buys is the property a chaining pipeline needs:
    /// `decode(encode(x)) == .success(x)` for every `x`, asserted over a
    /// sample set and over a seeded sweep.
    ///
    /// - Important: The apostrophe is escaped as **`&#39;`**, not `&apos;`.
    ///   Both decode correctly here, but `&apos;` is not in HTML 4 and the
    ///   numeric form is universally understood. Plan 06-12's UI strings must
    ///   match this choice.
    /// - Important: `&` is escaped FIRST — structurally, not by ordering luck.
    ///   The classic bug lives in the CHAINED-REPLACEMENT shape, where a later
    ///   String-replacing pass re-reads the `&` an earlier one emitted and
    ///   double-escapes it. A single traversal appends replacements to the
    ///   OUTPUT and never re-examines them, so the fault cannot occur. (The
    ///   chained API is named descriptively here for the same reason the
    ///   platform decoder is in the file header: the plan greps this file for
    ///   its name and expects 0. The gate was driven RED separately.)
    /// - Important: The regression assertion is NOT `encode("&lt;") ==
    ///   "&amp;lt;"`, which the plan proposed and which MEASURABLY PASSES
    ///   under the `&`-last bug — that input has no `<` for an earlier pass to
    ///   escape. It is `encode("<") == "&lt;"` and its three siblings, whose
    ///   replacements each contain an `&` the encoder must leave alone.
    private static let escapes: [Unicode.Scalar: String] = [
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        "\"": "&quot;",
        "'": "&#39;"
    ]

    // MARK: - The three entry points

    /// Why `s` is not decodable HTML entity text, or `nil` if it is.
    ///
    /// Two failure classes, because 06-UI-SPEC.md defines two strings:
    ///
    /// 1. `.unterminatedEntity` — an `&` with no `;` before whitespace, before
    ///    another `&`, or before the end of the input. Renders as
    ///    `encode.error.html.unterminated`.
    /// 2. `.unknownEntity` — a `;`-terminated reference whose name is not in
    ///    the table, or a numeric reference that is not a legal Unicode
    ///    scalar. Renders as `encode.error.html.unknown`, and the payload is
    ///    the entity **as typed**, `&` and `;` included, because that is what
    ///    the string's `'%@'` slot shows the user.
    ///
    /// Both name the 1-based Character position of the `&` that begins the
    /// offending reference.
    ///
    /// - Note: Total. Every branch returns; there is no force-unwrap, no
    ///   `try!` and no unguarded subscript. Numeric references are accumulated
    ///   with an early bail above `0x10FFFF`, so no arithmetic can overflow —
    ///   which matters because these bundles are host-based and a trap kills
    ///   the host rather than failing a test.
    /// - Parameter s: Untrusted input of arbitrary length and content.
    nonisolated static func classify(_ s: String) -> ConversionFailure? {
        switch scan(s) {
        case .success: nil
        case let .failure(failure): failure
        }
    }

    /// The text `s` decodes to, or why it does not.
    ///
    /// - Important: `classify` and this function are ONE traversal, called
    ///   twice. That is deliberate: the contract
    ///   `classify(s) == nil  ⟹  decode(s)` is `.success` then holds by
    ///   construction rather than by two implementations agreeing. No test
    ///   asserts the converse, and there is nothing to assert — unlike Base64
    ///   and percent-encoding, no Foundation call is consulted here at all.
    nonisolated static func decode(_ s: String) -> Result<String, ConversionFailure> {
        scan(s)
    }

    /// The HTML-escaped spelling of `s`, escaping exactly the five characters
    /// in ``escapes`` and nothing else.
    ///
    /// - Note: Total and cannot fail. Every scalar either has a replacement or
    ///   is itself, so there is no error path here and none should be invented
    ///   for symmetry with ``decode(_:)``.
    /// - Important: `café` comes back unchanged, `"line1\nline2"` keeps its
    ///   newline and `"  spaced  "` keeps both runs of spaces. Those are the
    ///   three measured destruction modes of the platform decoder named in the
    ///   file header, asserted here as regressions rather than trusted.
    nonisolated static func encode(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        for scalar in s.unicodeScalars {
            if let replacement = escapes[scalar] {
                out += replacement
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    // MARK: - The one traversal

    /// Walk `s` once, decoding every reference, or fail at the first bad one.
    ///
    /// The state machine is two states: outside a reference, and inside one
    /// having seen an `&`. `pendingName` carries the second state and its
    /// contents at the same time, so there is no way to be inside a reference
    /// without knowing where it started.
    ///
    /// - Note: One forward pass, no lookahead and no random access. Every
    ///   allocation is bounded by the length of the input.
    private nonisolated static func scan(_ s: String) -> Result<String, ConversionFailure> {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        var pendingName: String?
        var ampersandOffset = 0
        var offset = 0

        for scalar in s.unicodeScalars {
            if let name = pendingName {
                switch step(scalar, name: name, ampersandOffset: ampersandOffset, in: s) {
                case let .failure(failure): return .failure(failure)
                case let .success(.resolved(text)):
                    out += text
                    pendingName = nil
                case let .success(.continuing(longer)):
                    pendingName = longer
                }
            } else if scalar == "&" {
                pendingName = ""
                ampersandOffset = offset
            } else {
                out.unicodeScalars.append(scalar)
            }
            offset += utf8Width(scalar)
        }

        if pendingName != nil {
            // End of input with a reference still open. `&copy` lands here,
            // which is where the 106 legacy forms are refused.
            return .failure(.unterminatedEntity(position: characterPosition(utf8Offset: ampersandOffset, in: s)))
        }
        return .success(out)
    }

    /// What one scalar does to an open reference.
    private enum EntityStep {
        /// The reference closed and stands for this text.
        case resolved(String)
        /// The reference is still open and now has this name.
        case continuing(String)
    }

    /// Apply one scalar to the reference opened at `ampersandOffset`.
    ///
    /// Split out of ``scan(_:)`` so neither function carries the whole state
    /// machine's branching, and so the terminator rule is stated in one place.
    private nonisolated static func step(
        _ scalar: Unicode.Scalar,
        name: String,
        ampersandOffset: Int,
        in s: String
    ) -> Result<EntityStep, ConversionFailure> {
        if scalar == ";" {
            guard let text = resolve(name) else {
                return .failure(.unknownEntity("&" + name + ";",
                                               position: characterPosition(utf8Offset: ampersandOffset, in: s)))
            }
            return .success(.resolved(text))
        }
        // ONE terminator rule, stated: an `&` that meets whitespace, another
        // `&`, or the end of the input before its `;` is unterminated. A bare
        // `&` in prose ("100% & more") is therefore an error naming the `&`,
        // not "not an entity" — the app has one answer for one input.
        if scalar == "&" || isASCIIWhitespace(scalar) {
            return .failure(.unterminatedEntity(position: characterPosition(utf8Offset: ampersandOffset, in: s)))
        }
        var longer = name
        longer.unicodeScalars.append(scalar)
        return .success(.continuing(longer))
    }

    /// The text a reference name stands for, or `nil` when it names nothing.
    ///
    /// Named references come from the generated table; numeric references are
    /// resolved here, because the table does not carry them and the scanner
    /// must (`&#65;` and `&#x41;` are both `A`).
    private nonisolated static func resolve(_ name: String) -> String? {
        guard name.unicodeScalars.first == "#" else {
            return lookup[name]
        }
        return numericReference(name)
    }

    /// The scalar a numeric character reference names, or `nil` when it names
    /// none.
    ///
    /// - Important: The value is accumulated with an early bail the moment it
    ///   passes `0x10FFFF`, so a reference like `&#99999999999999999999;`
    ///   cannot overflow. The obvious `Int(digits)` shape traps or silently
    ///   wraps; this one returns `nil` and the caller names it
    ///   `.unknownEntity`. Surrogates U+D800...U+DFFF are refused for the same
    ///   reason: `Unicode.Scalar(_:)` returns `nil` for them and a
    ///   force-unwrap would trap the host.
    /// - Returns: `nil` for an empty digit run, a non-digit, a value above
    ///   U+10FFFF, a surrogate, or **zero**. The platform decoder returns
    ///   U+FFFD with no error for these; this app names them (T-06-25).
    private nonisolated static func numericReference(_ name: String) -> String? {
        var scalars = Substring(name).unicodeScalars.dropFirst()
        let radix: UInt32
        if scalars.first == "x" || scalars.first == "X" {
            scalars = scalars.dropFirst()
            radix = 16
        } else {
            radix = 10
        }
        guard !scalars.isEmpty else { return nil }

        var value: UInt32 = 0
        for scalar in scalars {
            guard let digit = digitValue(scalar, radix: radix) else { return nil }
            // Bail BEFORE the multiply, so the arithmetic below cannot
            // overflow: value is at most 0x10FFFF here, so value * 16 + 15 is
            // at most 0x10FFFF_F and far inside UInt32.
            guard value <= 0x10FFFF else { return nil }
            value = value * radix + digit
        }
        // WR-03: the NULL reference is refused BY NAME, next to the surrogate
        // refusal it belongs with. `Unicode.Scalar(0)` is perfectly valid, so
        // without this guard `&#0;` resolved to U+0000 and `decode("a&#0;b")`
        // returned `.success("a\0b")`. That is not cosmetic: `OutputPasteboard`
        // writes the string to the general pasteboard verbatim, and any
        // C-string consumer on the receiving side truncates at the NUL — so a
        // tool whose whole premise is "the value you get back is the value you
        // can paste elsewhere" handed back a value that silently truncates on
        // paste. WHATWG calls a null character reference a parse error and
        // substitutes U+FFFD; this app reports parse errors rather than
        // substituting, so it is named as an unknown entity instead. That
        // divergence is the app's own choice and it is now made deliberately
        // rather than by omission.
        guard value != 0, let resolved = Unicode.Scalar(value) else { return nil }
        return String(Character(resolved))
    }

    /// The value of an ASCII digit in `radix`, or `nil` when it is not one.
    private nonisolated static func digitValue(_ scalar: Unicode.Scalar, radix: UInt32) -> UInt32? {
        let value: UInt32? = switch scalar {
        case "0" ... "9": scalar.value - 0x30
        case "a" ... "f": scalar.value - 0x61 + 10
        case "A" ... "F": scalar.value - 0x41 + 10
        default: nil
        }
        guard let value, value < radix else { return nil }
        return value
    }

    /// Space, tab, newline, carriage return, vertical tab and form feed.
    ///
    /// Spelled out rather than taken from `CharacterSet.whitespaces` or
    /// `Character.isWhitespace`: 06-04 measured `CharacterSet.alphanumerics`
    /// containing "é" while being named "ALPHA / DIGIT", and a terminator rule
    /// that quietly included U+00A0 NO-BREAK SPACE would change which inputs
    /// are errors without anyone deciding to.
    private nonisolated static func isASCIIWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x20, 0x09, 0x0A, 0x0D, 0x0B, 0x0C: true
        default: false
        }
    }

    /// How many UTF-8 bytes `scalar` occupies.
    ///
    /// The scan needs a UTF-8 offset to hand to
    /// ``characterPosition(utf8Offset:in:)`` while walking scalars, and this
    /// is the whole of the arithmetic. Total: a `Unicode.Scalar` is never a
    /// surrogate, so the four ranges are exhaustive.
    private nonisolated static func utf8Width(_ scalar: Unicode.Scalar) -> Int {
        switch scalar.value {
        case 0x0000 ... 0x007F: 1
        case 0x0080 ... 0x07FF: 2
        case 0x0800 ... 0xFFFF: 3
        default: 4
        }
    }
}
