// TimestampDetection — D-88 (one field, format auto-detected) and D-89 (the
// detection shown and overridable).
//
// The positional scan that fills `timestamps.error.iso8601` is the other half
// of this type and lives in `TimestampTemplateScan.swift`. It is an extension
// rather than a second type so there is ONE namespace for detection, and it is
// a second FILE because `swiftlint --strict` enforces file_length (400) on this
// repo's config and one file carrying both halves is 526 lines. The same call
// `HTMLEntityTablePacking` and `TimestampContractTests` already made; the lint
// config is not touched.
//
// WHY THE RULE IS AN ORDERED LIST AND NOT A HEURISTIC
//
// `20260904` is a plausible Unix epoch AND a plausible calendar date. Any
// detector has to choose, so the choice is written down as six numbered
// clauses applied in order, first match wins. That makes it a table-driven
// test (DetectionTests.clauseCases carries the clause number each row
// exercises) and it gives D-89's "Read as" segmented control something named
// to display. A wrong guess is then a two-tap inconvenience rather than a
// dead end, which is the reason the rule is allowed to be opinionated at all.
//
// THE MEASUREMENTS EACH CLAUSE RESTS ON, taken on this tree 2026-09-04:
//
//   8-digit  min 10000000     -> 1970-04-26T17:46:40Z
//   10-digit max 9999999999   -> 2286-11-20T17:46:39Z
//   13-digit 1788480000000 as seconds -> year 58644; as milliseconds -> 2026-09-04T00:00:00Z
//   20260904 as seconds       -> 1970-08-23T12:01:44Z
//   Int("99999999999999999999") -> nil          (overflow, and see below)
//
// WHY FOUNDATION'S REGULAR-EXPRESSION CLASS IS NOT NAMED ANYWHERE BELOW
//
// Two separate reasons, both measured elsewhere in this engine, and one
// procedural one. First, that class is a Foundation reference type and raises
// the same non-`Sendable` shared-state question the reference-type formatters do
// (see TimestampCodec's header) — a question this file has no way to answer
// without the unsafe annotations ROADMAP criterion 5 forbids by name. Second,
// a `Regex` value held in a `static let` would be that same shared state. The
// three patterns are therefore written as literals INSIDE the one function
// that uses them: they are anchored by `wholeMatch(of:)` rather than by `^`
// and `$`, bounded (`{1,10}`, `{13}`, `{2}`), and alternation-free at the
// tail, with NO NESTED QUANTIFIERS — catastrophic backtracking is threat
// T-06-32 and this shape cannot exhibit it.
//
// TOTALITY, AND THE TWO TRAP SITES THIS SUBJECT HAS
//
// These unit bundles are HOST-BASED, so a Swift runtime trap does not fail a
// test — it kills the host, aborts the run and posts a crash dialog on the
// developer's desktop. Timestamps have two trap sites and both are closed
// here: a FORCE-UNWRAPPED INTEGER CONVERSION of a string that does not fit
// (measured `nil`; the conversion below is bound with `guard let` instead),
// and a `Date` built from a value outside the window the formatter can render
// (clause 6 refuses those by name). The scan's own trap site — an index walked
// past the end of its input — is closed in `TimestampTemplateScan.swift`.
//
// THE PROCEDURAL REASON THIS FILE SPELLS NEITHER OF THOSE TWO THINGS
//
// Both are policed by a `grep -c` over THIS FILE, so a comment quoting either
// verbatim would make its own gate return a non-zero count and the gate could
// never be green — the anti-pattern where a file that configures a content
// gate is also swept by it, which this phase has now met eight times. Both are
// therefore described rather than written out, which leaves each grep's
// population exactly the executable code it is meant to police.

import Foundation

/// The three segments of the UI-SPEC's "Read as" `.segmented` `Picker`, and
/// the value the override binds to.
///
/// - Important: **Milliseconds is a DETECTION RESULT, not a fourth segment.**
///   The UI-SPEC's three segments are Unix epoch / ISO 8601 / Local time, and
///   `timestamps.diagnostic.valid` is `"Read as %@."` with the spec's own
///   example `"Read as Unix epoch (seconds)."` — so the UNIT travels in the
///   diagnostic string, not in the picker. Five ``DetectedFormat`` results map
///   onto these three segments through ``TimestampDetection/segment(for:)``,
///   and that mapping is asserted case by case rather than by a total.
/// - Note: The raw values are the enum case names and are NOT user-facing
///   text. The visible strings are `timestamps.readAs.epoch`,
///   `timestamps.readAs.iso8601` and `timestamps.readAs.localTime`, owned by
///   the view layer — the engine must not import SwiftUI and must not know
///   about localization.
enum ReadAs: String, CaseIterable, Sendable, Hashable {
    /// `timestamps.readAs.epoch` — "Unix epoch".
    case unixEpoch
    /// `timestamps.readAs.iso8601` — "ISO 8601".
    case iso8601
    /// `timestamps.readAs.localTime` — "Local time".
    case localTime
}

/// What the detector concluded, at the granularity the diagnostic string
/// renders — which is finer than the picker's.
enum DetectedFormat: Equatable, Sendable {
    /// A run of up to 10 digits, optionally signed. Clause 2.
    case unixEpochSeconds
    /// Exactly 13 digits. Clause 3.
    case unixEpochMilliseconds
    /// Contains a `-`, a `T` or a `:`. Clause 4.
    case iso8601Extended
    /// The anchored 8-digit `YYYYMMDD` window. Clause 1.
    case iso8601BasicDate
    /// Everything else. Clause 5.
    case localTime
}

/// The auto-detection rule and the override path it produces.
///
/// The positional classifier every date failure in this app is reported
/// through is an extension of this type, in `TimestampTemplateScan.swift`.
///
/// A caseless enum: no instance state, nothing to construct, and — as in
/// `TimestampCodec` — no static stored property that could be shared mutable
/// state under `-strict-concurrency=complete`. The one `static let` is a
/// `ClosedRange<Double>`, which is `Sendable`.
enum TimestampDetection {
    // MARK: - Clause 6's window

    /// The instants the app is willing to show: **years 1 through 9999**,
    /// inclusive, in UTC.
    ///
    /// Measured with a Gregorian calendar in UTC: 0001-01-01T00:00:00Z is
    /// `-62_135_769_600` and 10000-01-01T00:00:00Z is `253_402_300_800`, so
    /// the last representable second is one below the latter. Outside this
    /// range the result is ``ConversionFailure/outOfRange(_:)`` naming the
    /// value the user typed, rather than a `Date` the formatter renders as
    /// garbage (threat T-06-35).
    nonisolated static let displayableWindow: ClosedRange<Double> = -62_135_769_600 ... 253_402_300_799

    // MARK: - D-88 / D-89: the six-clause rule

    /// What `s` looks like, by the ordered rule. **First match wins.**
    ///
    /// Applied to the whitespace-trimmed input:
    ///
    /// 1. `(19|20)\d{2}(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])` → ``DetectedFormat/iso8601BasicDate``.
    ///    **Shape beats magnitude.** This is 06-RESEARCH.md Open Question 4,
    ///    resolved here: `20260904` is a valid 8-digit integer (1970-08-23T12:01:44Z
    ///    as seconds) *and* a valid ISO 8601 basic-format calendar date, and it
    ///    reads as the date. The `19xx`/`20xx` year window keeps `18260904`-shaped
    ///    numbers from stealing plausible epochs, and month `13` / month `00` /
    ///    day `32` fall through to clause 2.
    /// 2. `[+-]?\d{1,10}` → ``DetectedFormat/unixEpochSeconds``. 10 digits
    ///    reaches 2286-11-20T17:46:39Z, the whole plausible range for a
    ///    developer tool. The research states this clause as "and fits in
    ///    `Int`"; that conjunct is **structurally unable to fail here** —
    ///    eleven characters cannot overflow `Int64` — so it is not written as
    ///    a check that could never fire. Overflow is clause 6's job, in
    ///    ``parse(_:as:)``, where a 20-digit input actually reaches it.
    /// 3. `\d{13}` → ``DetectedFormat/unixEpochMilliseconds``. 13 digits read
    ///    as seconds land in year 58644 — never what anyone meant.
    /// 4. contains `-`, `T` or `:` → ``DetectedFormat/iso8601Extended``.
    ///    Handed to the parser, which reports its own positional error.
    /// 5. otherwise → ``DetectedFormat/localTime``.
    ///
    /// - Note: Total. The empty string returns ``DetectedFormat/localTime``;
    ///   in the UI it never arrives, because the Empty state intercepts it
    ///   (UI-SPEC §State Contract 1), but the function is defined for it.
    /// - Parameter s: Untrusted input of arbitrary length and encoding.
    nonisolated static func detect(_ s: String) -> DetectedFormat {
        let trimmed = trim(s)
        if trimmed.wholeMatch(of: /(19|20)\d{2}(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])/) != nil {
            return .iso8601BasicDate
        }
        if trimmed.wholeMatch(of: /[+-]?\d{1,10}/) != nil {
            return .unixEpochSeconds
        }
        if trimmed.wholeMatch(of: /\d{13}/) != nil {
            return .unixEpochMilliseconds
        }
        if trimmed.contains("-") || trimmed.contains("T") || trimmed.contains(":") {
            return .iso8601Extended
        }
        return .localTime
    }

    /// The picker segment a detection result maps onto — five results, three
    /// segments. See ``ReadAs`` for why the unit does not get a segment.
    nonisolated static func segment(for format: DetectedFormat) -> ReadAs {
        switch format {
        case .unixEpochSeconds, .unixEpochMilliseconds: .unixEpoch
        case .iso8601Extended, .iso8601BasicDate: .iso8601
        case .localTime: .localTime
        }
    }

    // MARK: - Parsing under an explicit ReadAs (D-89's override)

    /// `s` read as `readAs`, **whatever ``detect(_:)`` would have said**.
    ///
    /// That independence is D-89's entire point and it is an executed
    /// assertion: `parse("20260904", as: .unixEpoch)` succeeds and yields
    /// 20260904 seconds, even though `detect` calls the same string an ISO
    /// 8601 basic date.
    ///
    /// - Note: Local time is read in ``TimestampCodec/defaultTimeZone``. The
    ///   zone-taking overload exists so that assertion has a population it can
    ///   fail against — the lesson `TimestampCodec.pickerOrder(_:)` records.
    nonisolated static func parse(_ s: String, as readAs: ReadAs) -> Result<Double, ConversionFailure> {
        parse(s, as: readAs, timeZone: TimestampCodec.defaultTimeZone)
    }

    /// `s` read as `readAs`, with local time resolved in `timeZone`.
    nonisolated static func parse(_ s: String, as readAs: ReadAs, timeZone: TimeZone) -> Result<Double, ConversionFailure> {
        let trimmed = trim(s)
        switch readAs {
        case .unixEpoch: return parseEpoch(trimmed)
        case .iso8601: return parseISO8601(trimmed)
        case .localTime: return parseLocalTime(trimmed, timeZone: timeZone)
        }
    }

    // MARK: - Clause 2/3/6: the integer path

    /// Digits (with an optional sign), then a unit, then the window.
    private nonisolated static func parseEpoch(_ trimmed: String) -> Result<Double, ConversionFailure> {
        var offset = 0
        var sawDigit = false
        for byte in trimmed.utf8 {
            let isSign = offset == 0 && (byte == UInt8(ascii: "+") || byte == UInt8(ascii: "-"))
            if !isSign {
                guard byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") else {
                    // Fills `timestamps.error.notDigit`.
                    return .failure(.unexpectedCharacter(characterAt(utf8Offset: offset, in: trimmed),
                                                         position: characterPosition(utf8Offset: offset,
                                                                                     in: trimmed)))
                }
                sawDigit = true
            }
            offset += 1
        }
        // WR-02. This used to be `.outOfRange(trimmed)`, which rendered "Out of
        // range: + is outside the dates this app can show." for `"+"` and left
        // the `%@` slot EMPTY for `""`. Neither sentence was true: those are
        // not numbers out of range, they are not numbers. The loop above can
        // only end here when `trimmed` is empty or is a lone sign — every other
        // path returns inside it — so the offending character is the first one,
        // and reporting it positionally is what D-85 asks for and what every
        // other classifier in this engine does. `.outOfRange` is also the one
        // case carrying no position, so this was the single place in the
        // subject where D-85's promise was absent.
        //
        // For the empty string `characterAt` is documented to yield U+FFFD;
        // that input never reaches here from the UI, because UI-SPEC §State
        // Contract 1 intercepts it with the Empty state before any parse runs.
        guard sawDigit else {
            return .failure(.unexpectedCharacter(characterAt(utf8Offset: 0, in: trimmed), position: 1))
        }

        // Clause 6. Measured: `Int("99999999999999999999")` is nil, so the
        // overflow is a value to handle, bound with `guard let` and never
        // force-unwrapped — a trap here would kill the host process rather
        // than fail a test.
        guard let magnitude = Int(trimmed) else { return .failure(.outOfRange(trimmed)) }

        // Clause 3's unit, applied and not merely detected: exactly 13 plain
        // digits are milliseconds. A signed value is always seconds — 13
        // digits plus a sign is 14 characters and matches no clause.
        let isSigned = trimmed.hasPrefix("+") || trimmed.hasPrefix("-")
        let isMilliseconds = !isSigned && trimmed.utf8.count == 13
        let seconds = isMilliseconds ? Double(magnitude) / 1000 : Double(magnitude)

        guard displayableWindow.contains(seconds) else { return .failure(.outOfRange(trimmed)) }
        return .success(seconds)
    }

    // MARK: - Clause 1/4: the ISO path

    /// Extended format straight through; the clause-1 basic-format date
    /// expanded first.
    ///
    /// - Note: A bare calendar date carries no zone, so `20260904` is read as
    ///   **UTC midnight**. That keeps this function zone-free and makes the
    ///   ISO cell render back exactly what the user typed, in its extended
    ///   form.
    private nonisolated static func parseISO8601(_ trimmed: String) -> Result<Double, ConversionFailure> {
        var candidate = trimmed
        if trimmed.wholeMatch(of: /(19|20)\d{2}(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])/) != nil {
            let year = trimmed.prefix(4)
            let month = trimmed.dropFirst(4).prefix(2)
            let day = trimmed.suffix(2)
            candidate = "\(year)-\(month)-\(day)T00:00:00Z"
        }
        return TimestampCodec.parseISO8601(candidate).flatMap(withinWindow(trimmed))
    }

    /// A date, and optionally a time, read in `timeZone`.
    ///
    /// Three styles are tried because one value does not cover the three
    /// shapes a user writes: measured, the `T`-separated style returns nil for
    /// `"2026-09-04 00:00:00"`, the space-separated style returns nil for
    /// `"2026-09-04T00:00:00"`, and only the date-only style accepts a bare
    /// `"2026-09-04"`. The same complementary-styles finding `TimestampCodec`
    /// records for fractional seconds, in a second place.
    ///
    /// - Important: **AN EXPLICIT OFFSET IS HONOURED, NOT DISCARDED, AND IT IS
    ///   HONOURED BY CALLING THE ISO 8601 PATH RATHER THAN BY A FOURTH STYLE.**
    ///   The local scan accepts `Z`, `z` and `±HH:MM`; until 2026-09-05 the
    ///   styles below carried no zone field, so Foundation dropped the
    ///   designator and returned the wall clock in the picker's zone. Measured
    ///   with the picker on Asia/Tokyo: `"…+05:30"`, `"…-08:00"`, `"…Z"` and
    ///   the bare `"…"` all returned 1788447600, three of them wrong by hours
    ///   and every one of them a `.success`. That is the "quietly wrong answer"
    ///   half of ROADMAP criterion 1, produced by the validator accepting input
    ///   the parser could not honour.
    ///
    ///   Adding a zoned style here would have made the two paths agree by
    ///   coincidence — two implementations that have to be kept in step. So the
    ///   zoned branch DELEGATES: `TimestampCodec.parseISO8601` is the answer,
    ///   already measured across all four runtimes, and the two paths cannot
    ///   disagree because on this input there is only one of them. The scan is
    ///   also the sole authority on whether a designator is present, through
    ///   ``readLocalTime(_:)`` — two independent answers to that question is
    ///   exactly what went wrong.
    /// - Note: Failures are reported by the same positional scan, run with the
    ///   time and the zone optional — so a bare calendar date is valid here
    ///   and `"2026-09-04X00:00:00"` still names the `T` at position 11.
    private nonisolated static func parseLocalTime(_ trimmed: String, timeZone: TimeZone) -> Result<Double, ConversionFailure> {
        switch readLocalTime(trimmed) {
        case let .invalid(failure):
            .failure(failure)
        case .explicitOffset:
            // `withinWindow(trimmed)` and not `withinWindow(isoSpelling(...))`,
            // so an out-of-range message still quotes what the user typed.
            TimestampCodec.parseISO8601(isoSpelling(trimmed)).flatMap(withinWindow(trimmed))
        case .wallClock:
            parseWallClock(trimmed, timeZone: timeZone)
        }
    }

    /// `trimmed` with its date-time separator written the one way extended
    /// format accepts.
    ///
    /// The local shape allows a SPACE where ISO 8601 requires a `T` — measured,
    /// `classifyISO8601("2026-09-04 00:00:00Z")` reports `expected 'T' at
    /// position 11`. That is the ONLY spelling difference between the two
    /// shapes once a zone is present, which is what makes the delegation above
    /// total rather than merely usual, and
    /// `everyZonedLocalInputIsAlsoWellFormedISO8601OnceTheSeparatorIsNormalised`
    /// is where it is asserted rather than argued. Only the separator moves; no
    /// field is reinterpreted. The scan has already accepted the string by the
    /// time this runs, so the one space it can contain is that separator.
    private nonisolated static func isoSpelling(_ trimmed: String) -> String {
        guard let space = trimmed.firstIndex(of: " ") else { return trimmed }
        return trimmed.replacingCharacters(in: space ... space, with: "T")
    }

    /// A date, and optionally a time, that named no zone of its own — read in
    /// `timeZone`, which is what "Local time" means when the input is silent.
    private nonisolated static func parseWallClock(_ trimmed: String, timeZone: TimeZone) -> Result<Double, ConversionFailure> {
        let base = Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day().dateSeparator(.dash)
        let styles = [
            base.dateTimeSeparator(.standard).time(includingFractionalSeconds: false),
            base.dateTimeSeparator(.space).time(includingFractionalSeconds: false),
            base
        ]
        for style in styles {
            if let instant = try? style.parse(trimmed) {
                return withinWindow(trimmed)(instant.timeIntervalSince1970)
            }
        }
        // Unreachable while the one-directional contract holds, and it is the
        // contract that is asserted rather than this branch that is argued
        // away. It still needs a value, and the honest one names the end of
        // the input rather than inventing an interior position no scan found.
        return .failure(.expectedCharacter("a date this app can read",
                                           position: characterPosition(utf8Offset: trimmed.utf8.count,
                                                                       in: trimmed)))
    }

    /// Clause 6's second half, shared by both date paths.
    private nonisolated static func withinWindow(_ typed: String) -> (Double) -> Result<Double, ConversionFailure> {
        { seconds in
            guard seconds.isFinite, displayableWindow.contains(seconds) else {
                return .failure(.outOfRange(typed))
            }
            return .success(seconds)
        }
    }

    // MARK: -

    private nonisolated static func trim(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
