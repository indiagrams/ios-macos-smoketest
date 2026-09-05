// Tests for app/Shared/Engine/TimestampDetection.swift — D-88's one-field
// auto-detection and D-89's overridable "Read as" control.
//
// Run via (macOS):
//   xcodebuild test -project app/App.xcodeproj -scheme App-macOS \
//     -configuration Debug -destination 'platform=macOS' \
//     -only-testing:AppMacOSTests/DetectionTests \
//     CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
//
// Compiled into BOTH unit-test targets, so every clause below is asserted on
// iOS and macOS from one source. `-only-testing:` naming an ABSENT suite exits
// 0 printing `** TEST SUCCEEDED **` having run zero tests (measured by 06-03),
// so a green from this file is only evidence when it carries a test count.
//
// THE SIX CLAUSES, EACH WITH AT LEAST ONE EXECUTED CASE
//
// `clauseCases` below is the table the parameterised sweep runs, and it carries
// the clause number each row exercises. `theRuleHasSixClausesAndEveryOneIsCovered`
// derives the covered-clause count FROM THAT TABLE rather than asserting a
// hand-written 6, so a row deleted from the table fails the count instead of
// silently shrinking the population — the defect 06-07 met as
// `control=timestamp-corpus-shrank`.
//
// WHY THE BOUNDARY ROWS ARE THE INTERESTING ONES
//
// Clause 1 is the only clause that can steal input from another, so it is the
// only one with a stated window: `(19|20)\d{2}` years, months 01-12, days
// 01-31. `20261304` and `20260032` and `18260904` are in the table precisely
// because they must NOT match it, and each of them detects as an epoch instead.

import Foundation
import Testing

/// What a clause row is asserted to produce. `detects` covers clauses 1-5,
/// which are decisions `detect` makes; `readAsEpochIsOutOfRange` covers clause
/// 6, which is a decision `parse` makes and which no `DetectedFormat` can
/// express — the value is refused rather than classified.
enum ClauseOutcome: Sendable, Equatable {
    /// `detect` returns this format.
    case detects(DetectedFormat)
    /// `parse(_:as: .unixEpoch)` fails with `.outOfRange` carrying the input.
    case readAsEpochIsOutOfRange
}

/// One row of the detection rule, tagged with the clause it exercises.
struct ClauseCase: Sendable {
    /// 1-6, matching the ordered rule in `TimestampDetection.detect`.
    let clause: Int
    /// The untrusted input.
    let input: String
    /// What the rule must produce for it.
    let outcome: ClauseOutcome
    /// Why this row is here.
    let reason: String
}

/// Swift Testing discovers this type as a suite named after the type itself, so
/// `-only-testing:AppMacOSTests/DetectionTests` selects exactly these cases.
/// Deliberately no bare `@Suite` attribute — see `PositionTests` for why.
struct DetectionTests {
    // MARK: - The clause table

    /// Every clause of the ordered rule, with the boundary rows that make each
    /// one falsifiable. Order here is presentation only; `detect` applies its
    /// clauses in its own stated order and first match wins.
    static let clauseCases: [ClauseCase] = [
        // Clause 1 — ISO 8601 basic-format calendar date. Shape beats
        // magnitude. This is RESEARCH Open Question 4, resolved.
        ClauseCase(clause: 1, input: "20260904", outcome: .detects(.iso8601BasicDate),
                   reason: "Open Question 4: a plausible epoch AND a plausible date; shape wins"),
        ClauseCase(clause: 1, input: "19700101", outcome: .detects(.iso8601BasicDate),
                   reason: "the other end of the year window"),
        ClauseCase(clause: 1, input: "20261304", outcome: .detects(.unixEpochSeconds),
                   reason: "month 13 falls out of clause 1 and is read as an epoch by clause 2"),
        ClauseCase(clause: 1, input: "20260032", outcome: .detects(.unixEpochSeconds),
                   reason: "month 00 and day 32 both fall through"),
        ClauseCase(clause: 1, input: "18260904", outcome: .detects(.unixEpochSeconds),
                   reason: "the year window is 19xx/20xx, so 1826 falls through"),

        // Clause 2 — Unix epoch seconds. 10 digits reaches 2286-11-20.
        ClauseCase(clause: 2, input: "1788480000", outcome: .detects(.unixEpochSeconds),
                   reason: "the reference instant"),
        ClauseCase(clause: 2, input: "0", outcome: .detects(.unixEpochSeconds),
                   reason: "the epoch itself"),
        ClauseCase(clause: 2, input: "-86400", outcome: .detects(.unixEpochSeconds),
                   reason: "the sign is accepted"),
        ClauseCase(clause: 2, input: "9999999999", outcome: .detects(.unixEpochSeconds),
                   reason: "10 digits, the clause's stated maximum: 2286-11-20T17:46:39Z"),
        ClauseCase(clause: 2, input: "99999999999", outcome: .detects(.localTime),
                   reason: "11 digits is one past the clause and reaches clause 5"),

        // Clause 3 — Unix epoch milliseconds.
        ClauseCase(clause: 3, input: "1788480000000", outcome: .detects(.unixEpochMilliseconds),
                   reason: "13 digits read as seconds land in year 58644"),

        // Clause 4 — extended ISO 8601, handed to the parser.
        ClauseCase(clause: 4, input: "2026-09-04T00:00:00Z", outcome: .detects(.iso8601Extended),
                   reason: "the ordinary internet date-time"),
        ClauseCase(clause: 4, input: "00:00:00", outcome: .detects(.iso8601Extended),
                   reason: "a colon alone is enough to reach clause 4"),

        // Clause 5 — everything else.
        ClauseCase(clause: 5, input: "hello", outcome: .detects(.localTime),
                   reason: "no shape matches"),
        ClauseCase(clause: 5, input: "", outcome: .detects(.localTime),
                   reason: "the Empty state intercepts this in the UI, but the function is total"),

        // Clause 6 — refused rather than classified.
        ClauseCase(clause: 6, input: "99999999999999999999", outcome: .readAsEpochIsOutOfRange,
                   reason: "Int(_:) returns nil on overflow; measured, and never force-unwrapped"),
        ClauseCase(clause: 6, input: "999999999999", outcome: .readAsEpochIsOutOfRange,
                   reason: "fits in Int and lands in year 33658, outside the displayable window")
    ]

    // MARK: - The clause table is a population, not a decoration

    /// The table is not empty and covers every clause. A parameterised test
    /// over an emptied table runs zero cases and reports success.
    @Test
    func theRuleHasSixClausesAndEveryOneIsCovered() {
        let covered = Set(Self.clauseCases.map(\.clause))
        #expect(Self.clauseCases.count >= 15)
        #expect(covered == Set(1 ... 6), "clauses covered: \(covered.sorted())")
        #expect(covered.count == 6)
    }

    /// Every row of the table, driven end to end.
    @Test(arguments: DetectionTests.clauseCases)
    func theRuleReproducesEveryClause(_ testCase: ClauseCase) {
        switch testCase.outcome {
        case let .detects(expected):
            #expect(TimestampDetection.detect(testCase.input) == expected,
                    "clause \(testCase.clause): \(testCase.reason)")
        case .readAsEpochIsOutOfRange:
            #expect(TimestampDetection.parse(testCase.input, as: .unixEpoch)
                == .failure(.outOfRange(testCase.input)),
                "clause \(testCase.clause): \(testCase.reason)")
        }
    }

    // MARK: - Clause 1, stated separately because it is the one that can steal

    /// RESEARCH Open Question 4, resolved: `20260904` reads as an ISO 8601
    /// basic-format calendar date, not as the epoch 1970-08-23T12:01:44Z.
    /// Shape beats magnitude, and D-89's overridable control is what makes a
    /// wrong guess a two-tap inconvenience rather than a dead end.
    @Test
    func theBasicDateShapeBeatsMagnitude() {
        #expect(TimestampDetection.detect("20260904") == .iso8601BasicDate)
        #expect(TimestampDetection.segment(for: .iso8601BasicDate) == .iso8601)
    }

    // MARK: - Clause 3, where detecting the unit is not the same as applying it

    /// The assertion that proves the millisecond unit is APPLIED rather than
    /// merely detected: the 13-digit input and its second-valued twin must
    /// name the same instant.
    @Test
    func themillisecondUnitIsAppliedAndNotJustDetected() throws {
        #expect(TimestampDetection.detect("1788480000000") == .unixEpochMilliseconds)
        let fromMilliseconds = try TimestampDetection.parse("1788480000000", as: .unixEpoch).get()
        let fromSeconds = try TimestampDetection.parse("1788480000", as: .unixEpoch).get()
        #expect(fromMilliseconds == fromSeconds)
        #expect(TimestampCodec.renderISO8601(fromMilliseconds, timeZone: .gmt) == "2026-09-04T00:00:00Z")
    }

    // MARK: - Clause 6, the two ways a number is refused rather than read

    /// `Int(_:)` returns `nil` on overflow — measured,
    /// `Int("99999999999999999999")` is `nil`. The engine never force-unwraps
    /// that conversion: these bundles are host-based, so a trap would kill the
    /// host and abort the run rather than fail a test.
    @Test
    func anEpochTooLargeForIntNamesItselfInsteadOfTrapping() {
        #expect(TimestampDetection.parse("99999999999999999999", as: .unixEpoch)
            == .failure(.outOfRange("99999999999999999999")))
    }

    /// A value that fits in `Int` but not in the displayable window is refused
    /// with the same failure, rather than becoming a `Date` the formatter
    /// renders as garbage. The window is years 1 through 9999.
    @Test
    func anEpochOutsideTheDisplayableWindowIsOutOfRange() {
        #expect(TimestampDetection.parse("999999999999", as: .unixEpoch)
            == .failure(.outOfRange("999999999999")))
        #expect(TimestampDetection.parse("-99999999999", as: .unixEpoch)
            == .failure(.outOfRange("-99999999999")))
        // Both ends of the window itself are inside it.
        let low = TimestampCodec.renderEpochSeconds(TimestampDetection.displayableWindow.lowerBound)
        let high = TimestampCodec.renderEpochSeconds(TimestampDetection.displayableWindow.upperBound)
        #expect(TimestampDetection.parse(low, as: .unixEpoch).success != nil, "low bound \(low)")
        #expect(TimestampDetection.parse(high, as: .unixEpoch).success != nil, "high bound \(high)")
    }

    /// `timestamps.error.notDigit` — "Not a Unix epoch: '%@' at position %lld
    /// is not a digit." The position is the 1-based Character offset every
    /// other classifier in this app reports.
    @Test
    func aNonDigitInAnEpochNamesItsCharacterAndPosition() {
        #expect(TimestampDetection.parse("12a34", as: .unixEpoch)
            == .failure(.unexpectedCharacter("a", position: 3)))
        #expect(TimestampDetection.parse("héllo", as: .unixEpoch)
            == .failure(.unexpectedCharacter("h", position: 1)))
    }

    // MARK: - Trimming

    /// Whitespace is trimmed before detection, and the trimmed value is what
    /// parses — so the padded input and the bare one name the same instant.
    @Test
    func whitespaceIsTrimmedBeforeDetectionAndBeforeParsing() throws {
        #expect(TimestampDetection.detect("  1788480000  ") == .unixEpochSeconds)
        let padded = try TimestampDetection.parse("  1788480000  ", as: .unixEpoch).get()
        let bare = try TimestampDetection.parse("1788480000", as: .unixEpoch).get()
        #expect(padded == bare)
        #expect(TimestampDetection.detect("\t2026-09-04T00:00:00Z\n") == .iso8601Extended)
    }

    // MARK: - Five results, three segments (the UI-SPEC's reconciliation)

    /// Milliseconds is a DETECTION RESULT, not a fourth picker segment. The
    /// UI-SPEC's three segments are Unix epoch / ISO 8601 / Local time and the
    /// unit travels in `timestamps.diagnostic.valid`'s `%@` ("Read as Unix
    /// epoch (seconds)."). Each mapping is asserted individually before the
    /// total, because a count of 3 reached by the wrong three would pass a
    /// total-only assertion.
    @Test
    func fiveDetectionResultsMapOntoThreeSegments() {
        #expect(TimestampDetection.segment(for: .unixEpochSeconds) == .unixEpoch)
        #expect(TimestampDetection.segment(for: .unixEpochMilliseconds) == .unixEpoch)
        #expect(TimestampDetection.segment(for: .iso8601Extended) == .iso8601)
        #expect(TimestampDetection.segment(for: .iso8601BasicDate) == .iso8601)
        #expect(TimestampDetection.segment(for: .localTime) == .localTime)
        #expect(ReadAs.allCases.count == 3)
        #expect(Set(ReadAs.allCases) == [.unixEpoch, .iso8601, .localTime])
    }

    // MARK: - D-89: the override is independent of the guess

    /// The whole point of making the rule visible: a user who meant an epoch
    /// can say so, and the override then parses `20260904` as 20260904
    /// seconds — 1970-08-23T12:01:44Z — even though `detect` said ISO 8601.
    @Test
    func theOverrideParsesIndependentlyOfWhatWasDetected() throws {
        #expect(TimestampDetection.detect("20260904") == .iso8601BasicDate)

        let asEpoch = try TimestampDetection.parse("20260904", as: .unixEpoch).get()
        #expect(asEpoch == 20_260_904)
        #expect(TimestampCodec.renderISO8601(asEpoch, timeZone: .gmt) == "1970-08-23T12:01:44Z")

        let asISO = try TimestampDetection.parse("20260904", as: .iso8601).get()
        #expect(TimestampCodec.renderISO8601(asISO, timeZone: .gmt) == "2026-09-04T00:00:00Z")
        #expect(asEpoch != asISO)
    }

    // MARK: - Totality

    /// 1 KB of arbitrary text through `detect` and all three `parse` paths. No
    /// trap, no force-unwrap, no `try!` — a trap here would kill the host
    /// process rather than fail this test.
    @Test
    func detectAndParseAreTotalOverArbitraryInput() {
        var generator = SeededGenerator(seed: 0x0608_D37E_C701)
        let pool: [Unicode.Scalar] = (32 ... 126).compactMap { Unicode.Scalar(UInt8($0)) }
            + ["\u{00E9}", "\u{FFFD}", "\u{1F600}"]
        let noise = generator.randomScalarString(from: pool, maxScalars: 1024)
        let inputs = [noise, "", "   ", "-", "+", ".", ":", "T", "\u{FFFD}", "👨‍👩‍👧‍👦",
                      String(repeating: "9", count: 512), "2026-09-04T", "--::--"]
        #expect(inputs.count >= 10)
        for input in inputs {
            _ = TimestampDetection.detect(input)
            for readAs in ReadAs.allCases {
                _ = TimestampDetection.parse(input, as: readAs)
            }
        }
    }
}
