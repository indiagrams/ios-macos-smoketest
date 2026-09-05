// TimestampDetection, continued — the ISO 8601 positional template scan.
//
// The other half of `TimestampDetection`, split out because `swiftlint
// --strict` enforces file_length (400) on this repo's config and one file
// carrying both halves is 526 lines. An `extension` rather than a second type,
// so there stays exactly ONE namespace for detection and one place a caller
// has to look. `.swiftlint.yml` and `.swiftformat` are not touched — the same
// call `HTMLEntityTablePacking.swift` made for the entity table.
//
// WHY THERE IS A HAND-WRITTEN SCAN HERE AT ALL
//
// `Date.ISO8601FormatStyle.parse` throws `NSCocoaErrorDomain` code 2048 with
// a message that names NO POSITION, and D-85 requires every error to name a
// reason and a character position. `timestamps.error.iso8601` is
// "Not valid ISO 8601: expected '%@' at position %lld.", which is a positional
// template scan written down as a string. Plan 06-07 left a stated placeholder
// pointing here; this file is what replaces it.
//
// THE TRAP SITE, CLOSED BY CONSTRUCTION
//
// These unit bundles are HOST-BASED: a Swift runtime trap kills the host,
// aborts the run and posts a crash dialog on the developer's desktop rather
// than failing a test. A positional scan over indices is the classic way to
// cause one. Every read in `TemplateScanner` is bounds-guarded, no arithmetic
// on an offset can overflow (the largest is `index + 1` on a bounded array),
// and `characterPosition(utf8Offset:in:)` is total by construction including
// for `Int.max`. `DetectionContractTests` drives 1 KB of arbitrary text plus
// the eleven shapes most likely to walk an index off the end.

import Foundation

extension TimestampDetection {
    /// Why `s` is not extended-format ISO 8601, with the expected token and a
    /// 1-based Character position, or `nil` when it is.
    ///
    /// Fills `timestamps.error.iso8601` — *"Not valid ISO 8601: expected '%@'
    /// at position %lld."*
    ///
    /// - Important: **The `'%@'` slot carries BOTH conventions**, recorded for
    ///   plan 06-13 as `iso_expected_token_convention=both`. Where one literal
    ///   character is expected the payload is that character (`"-"`, `"T"`,
    ///   `":"`); where a class or a range is expected it is a named phrase
    ///   (`"a digit"`, `"a month from 01 to 12"`, `"a time zone designator"`,
    ///   `"the end of the input"`). Both read as a sentence in the UI string.
    ///   Forcing one convention on the other would mean reporting `expected
    ///   '0'` for month 13, which is false as well as useless.
    /// - Important: **THE SCAN IS NOT STRICTER THAN THE PARSER ABOUT FIELD
    ///   WIDTH, and that is measured rather than assumed.** Every numeric
    ///   field accepts a variable-width digit run:
    ///
    ///       "2026-09-04T00:00:0Z"    parses   (single-digit seconds)
    ///       "2026-09-04T00:0:00Z"    parses   (single-digit minutes)
    ///       "2026-09-04T0:00:00Z"    parses   (single-digit hours)
    ///       "2026-09-4T00:00:00Z"    parses   (single-digit day)
    ///       "2026-9-04T00:00:00Z"    parses   (single-digit month)
    ///       "2026-09-04T00:00:00z"   parses   (lowercase designator)
    ///
    ///   Plan 06-08 specified `expected 'a digit' at position 7` for the
    ///   fifth of those. It does not report one, because that would be a
    ///   validator refusing input the app converts successfully — the defect
    ///   `control=timestamp-classifier-is-the-authority` exists to catch, and
    ///   the same authority question Base64 and percent-encoding answered the
    ///   same way. Widths are therefore 1-2 digits, 1-6 for the year.
    /// - Important: **Where it IS stricter, that is deliberate and asserted.**
    ///   Measured, the parser accepts `"…T00:80:00Z"` (minute 80, silently
    ///   normalised to 01:20), `"…T00:00:00GMT"`, and **anything at all after
    ///   the zone designator** — `"…T00:00:00Zhello world"` parses. Converting
    ///   those would be the "quietly wrong answer" half of criterion 1, so the
    ///   scan refuses them and the app reports an error instead. The contract
    ///   that holds is one-directional, exactly as in `Base64Codec`:
    ///
    ///       classifyISO8601(s) == nil  ⟹  the ISO 8601 format style parses s
    ///
    ///   **The converse is measurably false and is not asserted.** It is
    ///   COUNTED instead, by a generated mutation sweep in
    ///   `DetectionContractTests`, which also asserts a floor on how many
    ///   mutants it accepted — an implication over a population the scan
    ///   rejects entirely is vacuously true.
    /// - Note: Total. `""` returns a failure at position 1, never `nil` and
    ///   never a trap.
    nonisolated static func classifyISO8601(_ s: String) -> ConversionFailure? {
        scan(s, shape: .iso8601Extended).failure
    }

    /// What the local-time scan concluded about a string.
    ///
    /// Three answers rather than two, because "well formed" is not enough for
    /// the caller to parse it correctly: a local date and time either NAMES ITS
    /// OWN INSTANT with a zone designator or is a WALL CLOCK to be read in the
    /// picker's zone, and those are different questions with different answers.
    enum LocalTimeReading: Equatable, Sendable {
        /// A date, and optionally a time, with no zone designator. Read it in
        /// whichever zone the picker is on.
        case wallClock

        /// A date and time carrying `Z`, `z` or a `±HH:MM` offset. The input
        /// has already said which instant it means; the picker's zone is a
        /// rendering choice from here on and must not change the answer.
        case explicitOffset

        /// Why it is neither, with the token expected and its position.
        case invalid(ConversionFailure)
    }

    /// Why `s` is not a local date and time — or, when it is one, whether it
    /// named its own instant.
    ///
    /// - Important: **This exists because the scan is the AUTHORITY on the
    ///   presence of a designator and the parser must not decide it a second
    ///   time.** Until 2026-09-05 the scan accepted `Z`, `+05:30` and `-08:00`
    ///   while `parseLocalTime` built format styles with no zone field, so
    ///   Foundation dropped the designator and returned the picker-zone wall
    ///   clock: four distinct instants collapsed onto one, three of them wrong
    ///   by hours, every one reported as a success (CR-03's sibling, CR-01).
    ///   Two independent answers to "does this carry a zone?" is what made that
    ///   possible, so there is now one.
    nonisolated static func readLocalTime(_ s: String) -> LocalTimeReading {
        let result = scan(s, shape: .localTime)
        if let failure = result.failure {
            return .invalid(failure)
        }
        return result.hasZoneDesignator ? .explicitOffset : .wallClock
    }

    /// Why `s` is not a local date, optionally with a time, or `nil` when it
    /// is.
    ///
    /// The same scan as ``classifyISO8601(_:)`` with the time and the zone
    /// OPTIONAL, so a bare `"2026-09-04"` is valid here and
    /// `"2026-09-04X00:00:00"` still names the `T` at position 11. Local time
    /// is clause 5's payload, and without this it would be the one branch of
    /// the engine whose failures carried no position.
    nonisolated static func classifyLocalTime(_ s: String) -> ConversionFailure? {
        scan(s, shape: .localTime).failure
    }

    // MARK: - The positional template scan

    /// The two shapes the scan knows.
    private enum TemplateShape: Equatable {
        /// `YYYY-MM-DDTHH:MM:SS[.fff]<zone>` — every part required.
        case iso8601Extended
        /// The same, with the time and the zone optional and a space allowed
        /// in place of the `T`.
        case localTime
    }

    /// A bounds-guarded cursor over a string's UTF-8 bytes.
    ///
    /// The scan is over UTF-8 and the POSITION is not: `characterPosition` is
    /// called only where a failure is being built, for the reason measured in
    /// `Position.swift` — a grapheme walk costs 44.6 ms on 1 MB against 0.6 ms
    /// for a whole encode, and D-83/D-84 put this on the keystroke path.
    private struct TemplateScanner {
        private let bytes: [UInt8]
        private(set) var index = 0

        init(_ s: String) {
            bytes = Array(s.utf8)
        }

        var isAtEnd: Bool {
            index >= bytes.count
        }

        /// - Note: Bounds-guarded, like every other read below. A positional
        ///   scan over indices is the classic trap site in this subject and
        ///   these bundles are host-based, so there is no unguarded subscript.
        func peek() -> UInt8? {
            index < bytes.count ? bytes[index] : nil
        }

        mutating func take(_ byte: UInt8) -> Bool {
            guard peek() == byte else { return false }
            index += 1
            return true
        }

        /// Consumes between `min` and `max` digits and returns their value, or
        /// `nil` when there are fewer than `min` — in which case, because
        /// every call site passes `min: 1`, nothing has been consumed and the
        /// index still points at the offending byte.
        mutating func takeDigits(min: Int, max: Int) -> Int? {
            var value = 0
            var count = 0
            while count < max, let byte = peek(), byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") {
                value = value * 10 + Int(byte - UInt8(ascii: "0"))
                index += 1
                count += 1
            }
            return count >= min ? value : nil
        }

        /// Exactly two digits, consumed only if both are there — the `+HHMM`
        /// offset form, where consuming one and then failing would misreport.
        mutating func takeTwoDigits() -> Int? {
            guard index + 1 < bytes.count else { return nil }
            let high = bytes[index]
            let low = bytes[index + 1]
            guard high >= UInt8(ascii: "0"), high <= UInt8(ascii: "9"),
                  low >= UInt8(ascii: "0"), low <= UInt8(ascii: "9") else { return nil }
            index += 2
            return Int(high - UInt8(ascii: "0")) * 10 + Int(low - UInt8(ascii: "0"))
        }
    }

    private nonisolated static func expected(_ token: String, at offset: Int, in s: String) -> ConversionFailure {
        .expectedCharacter(token, position: characterPosition(utf8Offset: offset, in: s))
    }

    /// The whole scan: date, separator, time, fraction, zone, end.
    ///
    /// - Returns: The failure, or `nil` when there is none, together with
    ///   whether a zone designator was CONSUMED. The second value is only
    ///   meaningful when the first is `nil`; ``readLocalTime(_:)`` is what
    ///   enforces that, and it is the only caller that reads it.
    private nonisolated static func scan(
        _ s: String, shape: TemplateShape
    ) -> (failure: ConversionFailure?, hasZoneDesignator: Bool) {
        var scanner = TemplateScanner(s)
        var hasZone = false
        if let failure = classifyDate(&scanner, in: s) {
            return (failure, hasZone)
        }

        // The date-time separator. A bare calendar date is a complete local
        // time and is not a complete extended-format ISO 8601 date and time.
        if shape == .localTime, scanner.isAtEnd {
            return (nil, hasZone)
        }
        let separated = shape == .localTime
            ? scanner.take(UInt8(ascii: "T")) || scanner.take(UInt8(ascii: " "))
            : scanner.take(UInt8(ascii: "T"))
        guard separated else { return (expected("T", at: scanner.index, in: s), hasZone) }

        if let failure = classifyTime(&scanner, in: s) {
            return (failure, hasZone)
        }
        if let failure = classifyZone(&scanner, in: s, shape: shape, sawDesignator: &hasZone) {
            return (failure, hasZone)
        }
        guard scanner.isAtEnd else {
            return (expected("the end of the input", at: scanner.index, in: s), hasZone)
        }
        return (nil, hasZone)
    }

    /// `YYYY-MM-DD`, with the widths and ranges measured across ALL FOUR
    /// supported runtimes rather than on the development machine.
    ///
    /// Year 1-6 digits: `"202-09-04T…"` parses as year 202 on all four, and a
    /// seventh digit parses on iOS 18.6 alone. Month 01-12. Day 01 to the
    /// LENGTH OF THAT MONTH, leap years included — and that calendar check is
    /// not tidiness, it is the contract. Measured: **iOS 17.5 applies a real
    /// calendar and the other three normalise forward.** `2026-02-31` is nil
    /// on the deployment floor and 2026-03-03 everywhere else; so are
    /// `2026-04-31` and `2026-02-29` in a non-leap year. Accepting a day this
    /// calendar rejects would break the one-directional contract on the floor
    /// AND would silently show the user a different date depending on which OS
    /// they are running, which is the one thing these codecs exist to prevent.
    private nonisolated static func classifyDate(_ scanner: inout TemplateScanner, in s: String) -> ConversionFailure? {
        guard let year = scanner.takeDigits(min: 1, max: 6) else { return expected(digitToken, at: scanner.index, in: s) }
        guard scanner.take(UInt8(ascii: "-")) else { return expected("-", at: scanner.index, in: s) }
        let monthStart = scanner.index
        guard let month = scanner.takeDigits(min: 1, max: 2) else { return expected(digitToken, at: scanner.index, in: s) }
        guard (1 ... 12).contains(month) else { return expected("a month from 01 to 12", at: monthStart, in: s) }
        guard scanner.take(UInt8(ascii: "-")) else { return expected("-", at: scanner.index, in: s) }
        let dayStart = scanner.index
        guard let day = scanner.takeDigits(min: 1, max: 2) else { return expected(digitToken, at: scanner.index, in: s) }
        let lastDay = daysInMonth(month, ofYear: year)
        guard (1 ... lastDay).contains(day) else {
            return expected("a day from 01 to \(lastDay)", at: dayStart, in: s)
        }
        return nil
    }

    /// The length of `month` in `year`, proleptic Gregorian.
    ///
    /// - Note: A `switch` rather than a table subscript. `month` is validated
    ///   1-12 by its only caller, so an array lookup would be provably in
    ///   range today and one edit away from a trap tomorrow — and a trap in
    ///   these host-based bundles aborts the run instead of failing a test.
    private nonisolated static func daysInMonth(_ month: Int, ofYear year: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: 31
        case 4, 6, 9, 11: 30
        case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        default: 0
        }
    }

    /// `HH:MM:SS[.fff]`, with every range the INTERSECTION of the four
    /// supported runtimes.
    ///
    /// Hour 00-23 and second 00-59, NOT the 24 and 60 that ISO 8601 permits
    /// for end-of-day and leap seconds. Measured: `"…T24:00:00Z"` and
    /// `"…T00:00:60Z"` are nil on **iOS 17.5** and parse on 18.6, 26.1 and
    /// macOS. Accepting them would break the one-directional contract on the
    /// deployment floor and would convert on three OS versions out of four.
    ///
    /// Minute 00-59 for a different reason: `"…T00:80:00Z"` parses on three of
    /// the four and is silently normalised to 01:20, which is the "quietly
    /// wrong answer" criterion 1 forbids.
    ///
    /// Fractional seconds are 1-9 digits — a tenth digit parses on iOS 18.6
    /// alone and is reported here as content past the end.
    private nonisolated static func classifyTime(_ scanner: inout TemplateScanner, in s: String) -> ConversionFailure? {
        let hourStart = scanner.index
        guard let hour = scanner.takeDigits(min: 1, max: 2) else { return expected(digitToken, at: scanner.index, in: s) }
        guard hour <= 23 else { return expected("an hour from 00 to 23", at: hourStart, in: s) }
        guard scanner.take(UInt8(ascii: ":")) else { return expected(":", at: scanner.index, in: s) }
        let minuteStart = scanner.index
        guard let minute = scanner.takeDigits(min: 1, max: 2) else { return expected(digitToken, at: scanner.index, in: s) }
        guard minute <= 59 else { return expected("a minute from 00 to 59", at: minuteStart, in: s) }
        guard scanner.take(UInt8(ascii: ":")) else { return expected(":", at: scanner.index, in: s) }
        let secondStart = scanner.index
        guard let second = scanner.takeDigits(min: 1, max: 2) else { return expected(digitToken, at: scanner.index, in: s) }
        guard second <= 59 else { return expected("a second from 00 to 59", at: secondStart, in: s) }
        if scanner.take(UInt8(ascii: ".")) {
            guard scanner.takeDigits(min: 1, max: 9) != nil else { return expected(digitToken, at: scanner.index, in: s) }
        }
        return nil
    }

    /// `Z`, `z`, or `±HHMM` / `±HH:MM` with a magnitude of at most 18:00.
    ///
    /// - Important: **THE MINUTES ARE REQUIRED, and that is a floor
    ///   measurement rather than a style choice.** An hours-only `"+05"`
    ///   parses on iOS 17.5, iOS 26.1 and macOS and is **nil on iOS 18.6** —
    ///   the one split in this whole subject where the middle version is the
    ///   strict one. The digit widths inside the field stay flexible, because
    ///   `"+5:30"` and `"+05:3"` parse on all four.
    /// - Note: `-18:00` parses on all four and `-18:01` on iOS 18.6 alone, so
    ///   the magnitude bound is 18:00. A named zone such as `GMT` or `UTC`
    ///   parses on all four and is refused here: it is not ISO 8601.
    /// - Parameter sawDesignator: Set to `true` exactly when a designator was
    ///   CONSUMED, which is the fact ``readLocalTime(_:)`` needs and the fact
    ///   the parser must not re-derive. Left untouched on every failure path
    ///   and on the local-time path where the zone is simply absent.
    private nonisolated static func classifyZone(
        _ scanner: inout TemplateScanner, in s: String, shape: TemplateShape, sawDesignator: inout Bool
    ) -> ConversionFailure? {
        let start = scanner.index
        if scanner.take(UInt8(ascii: "Z")) || scanner.take(UInt8(ascii: "z")) {
            sawDesignator = true
            return nil
        }
        guard scanner.take(UInt8(ascii: "+")) || scanner.take(UInt8(ascii: "-")) else {
            return shape == .iso8601Extended ? expected("a time zone designator", at: start, in: s) : nil
        }
        guard let hours = scanner.takeDigits(min: 1, max: 2) else { return expected(digitToken, at: scanner.index, in: s) }
        let minutes: Int
        if scanner.take(UInt8(ascii: ":")) {
            guard let taken = scanner.takeDigits(min: 1, max: 2) else {
                return expected(digitToken, at: scanner.index, in: s)
            }
            minutes = taken
        } else if let taken = scanner.takeTwoDigits() {
            minutes = taken
        } else {
            return expected("an offset minute, as in +05:30", at: scanner.index, in: s)
        }
        guard minutes <= 59 else { return expected("a minute from 00 to 59", at: start, in: s) }
        guard hours * 60 + minutes <= 18 * 60 else {
            return expected("an offset from -18:00 to +18:00", at: start, in: s)
        }
        sawDesignator = true
        return nil
    }

    /// The one token that appears in more than one place.
    private nonisolated static let digitToken = "a digit"
}
