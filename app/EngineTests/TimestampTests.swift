// Tests for app/Shared/Engine/TimestampCodec.swift — ISO 8601, the Unix epoch,
// and the timezone selection APP-07 renders through.
//
// Run via (macOS):
//   xcodebuild test -project app/App.xcodeproj -scheme App-macOS \
//     -configuration Debug -destination 'platform=macOS' \
//     -only-testing:AppMacOSTests/TimestampTests \
//     CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
//
// Compiled into BOTH unit-test targets, so every number below is asserted on
// iOS and macOS from one source. `-only-testing:` naming an ABSENT suite exits
// 0 printing `** TEST SUCCEEDED **` having run zero tests (measured by 06-03),
// so a green from this file is only evidence when it carries a test count.
//
// THREE RULES THIS FILE OBEYS, ALL THREE FOR MEASURED REASONS
//
// 1. FRACTIONAL INSTANTS ARE COMPARED WITH A TOLERANCE, NEVER FOR EQUALITY.
//    "2026-09-04T00:00:00.123Z" parses to 1788480000.1230001 on this tree —
//    binary floating point, not a parser defect. Rendering truncates the
//    fraction to three digits, so the largest round-trip error measured over
//    this corpus is 0.0009 s, and the tolerance below is 0.001 s.
//
// 2. NO TEST ASSERTS THE LITERAL TEXT OF `renderDateTime`. It is locale- and
//    region-dependent: the UI spec's mockup and the research machine render
//    the same instant differently. Non-emptiness, the four-digit year, and a
//    difference between two zones are all that can honestly be asserted.
//
// 3. NO COUNT OF THE PLATFORM'S TIMEZONE TABLE IS ASSERTED FOR EQUALITY. The
//    tz database ships with the OS and grows; a frozen number is a plan
//    literal that goes stale by allocation. The count is PRINTED and asserted
//    only as a lower bound.

import Foundation
import Testing

/// See PositionTests for why there is no bare `@Suite` attribute.
struct TimestampTests {
    // MARK: - Shared fixtures

    /// Wider than the largest measured round-trip error (0.0009 s, which comes
    /// from the three-digit fraction the renderer emits) and far narrower than
    /// one second, so a whole-second mistake still fails.
    static let tolerance = 0.001

    /// The instant every literal below is about: 2026-09-04T00:00:00Z.
    static let referenceInstant = 1_788_480_000.0

    /// `?? .gmt` rather than `!`: these bundles are host-based, so a force
    /// unwrap that ever failed would kill the host instead of failing a test.
    /// `theSampleZonesReallyExist` below is what stops the fallback hiding a
    /// missing identifier — every literal in this file is a `-07:00` or
    /// `+05:30` string that GMT could not produce.
    static let losAngeles = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
    static let kolkata = TimeZone(identifier: "Asia/Kolkata") ?? .gmt

    /// The three-zone sample the round trip runs over: zero offset, a negative
    /// offset with a whole-hour value, and a positive offset with a half-hour
    /// value, which is the one that catches an offset written as hours only.
    static let sampleZones: [TimeZone] = [.gmt, losAngeles, kolkata]

    @Test
    func theSampleZonesReallyExist() {
        #expect(TimeZone(identifier: "America/Los_Angeles") != nil)
        #expect(TimeZone(identifier: "Asia/Kolkata") != nil)
    }

    // MARK: - The shared corpus

    /// The corpus is not empty. A parameterised test over an emptied table
    /// runs zero cases and reports success, which is indistinguishable from a
    /// table that passed.
    @Test
    func theCorpusIsPopulated() {
        #expect(TestVectors.timestampCases.count >= 9)
    }

    /// Both ISO classes are present, asserted separately. A count of 16
    /// reached entirely by inputs the parser refuses would pass a total-only
    /// assertion and never exercise a successful parse.
    @Test
    func theCorpusCoversBothISOClassesSeparately() {
        let cases = TestVectors.timestampCases
        #expect(cases.filter {
            if case .iso8601 = $0.expected {
                true
            } else {
                false
            }
        }.count >= 4)
        #expect(cases.filter { $0.expected == .notISO8601 }.count >= 5)
    }

    /// Every corpus row through the parser. The epoch rows are asserted to
    /// FAIL here on purpose: this function parses extended-format ISO 8601 and
    /// nothing else, and a bare run of digits is not that. Reading digits as an
    /// epoch is plan 06-08's detection step, layered above this one.
    @Test(arguments: TestVectors.timestampCases)
    func theParserReproducesTheCorpus(_ testCase: TimestampCase) {
        let result = TimestampCodec.parseISO8601(testCase.input)
        switch testCase.expected {
        case let .iso8601(expected):
            guard let value = result.success else {
                Issue.record("\(testCase.input) did not parse (\(testCase.reason))")
                return
            }
            #expect(abs(value - expected) < Self.tolerance,
                    "\(testCase.input) parsed to \(value), corpus says \(expected)")
        case .notISO8601, .epochSeconds, .epochMilliseconds, .outOfRange:
            #expect(result.failure != nil,
                    "\(testCase.input) parsed as ISO 8601 and should not have (\(testCase.reason))")
        }
    }

    // MARK: - Parsing

    /// The fraction is compared with a tolerance. The second expectation is
    /// the reason why, asserted rather than left in a comment: the parsed
    /// value is measurably NOT the decimal literal. If that ever stops being
    /// true it is a finding about the parser, not a test to bump.
    @Test
    func fractionalSecondsParseWithinToleranceAndNotExactly() {
        guard let value = TimestampCodec.parseISO8601("2026-09-04T00:00:00.123Z").success else {
            Issue.record("fractional seconds did not parse at all")
            return
        }
        #expect(abs(value - 1_788_480_000.123) < Self.tolerance)
        #expect(value != 1_788_480_000.123,
                "the decimal literal is now exactly representable; re-measure before relaxing the tolerance")
    }

    /// One style value covers both, so there is no try-both fallback that
    /// could take the wrong branch (T-06-28). The colon-free offset is the one
    /// the reference-type formatter's default options reject.
    @Test
    func offsetsWithAndWithoutAColonBothParse() {
        #expect(TimestampCodec.parseISO8601("2026-09-04T00:00:00+05:30").success == 1_788_460_200)
        #expect(TimestampCodec.parseISO8601("2026-09-04T00:00:00-0800").success == 1_788_508_800)
    }

    /// MEASURED LENIENCY, asserted as a leniency rather than repaired.
    ///
    /// Both of these are accepted by the parser and would be rejected by a
    /// hand-written validator that required two seconds digits and an
    /// uppercase designator. The classifier is the authority — the same answer
    /// the Base64 and percent-encoding families gave — so plan 06-08's
    /// positional scan must accept both. The lowercase `z` was found here; it
    /// is not in the phase research table.
    @Test
    func theParserAcceptsTwoFormsAStricterValidatorWouldReject() {
        #expect(TimestampCodec.parseISO8601("2026-09-04T00:00:0Z").success == Self.referenceInstant,
                "single-digit seconds")
        #expect(TimestampCodec.parseISO8601("2026-09-04T00:00:00z").success == Self.referenceInstant,
                "lowercase zone designator")
    }

    /// A failure names a reason and carries a position (D-85), and never a
    /// bare `nil`. The position is a stated placeholder, not a guess: the
    /// parser throws without one. Plan 06-08 replaces it with a scan.
    @Test
    func aFailureIsAConversionFailureAndNotABareNil() {
        #expect(TimestampCodec.parseISO8601("2026-09-04").failure == .expectedCharacter("ISO 8601", position: 1))
        #expect(TimestampCodec.parseISO8601("").failure != nil)
    }

    // MARK: - Rendering

    /// The chosen offset form is `+05:30`, asserted literally so the code and
    /// the string inventory cannot drift. The style's default is the colon-free
    /// `+0530`, which mixes a basic-format offset into an otherwise
    /// extended-format string; the colon form is what RFC 3339 requires and
    /// what the corpus inputs are written in.
    @Test
    func renderingPutsAColonInTheOffset() {
        #expect(TimestampCodec.renderISO8601(Self.referenceInstant, timeZone: .gmt) == "2026-09-04T00:00:00Z")
        #expect(TimestampCodec.renderISO8601(Self.referenceInstant, timeZone: Self.losAngeles)
            == "2026-09-03T17:00:00-07:00")
        #expect(TimestampCodec.renderISO8601(Self.referenceInstant, timeZone: Self.kolkata)
            == "2026-09-04T05:30:00+05:30")
    }

    /// A fraction the user typed is not silently dropped, and a whole second
    /// does not grow a `.000` it never had. Dropping it would be the same
    /// class of quiet data loss the Base64 codec refuses.
    ///
    /// The instant comes from the PARSER, not from a decimal literal, and that
    /// is load-bearing — see the test below.
    @Test
    func aFractionSurvivesRenderingAndAWholeSecondDoesNotGrowOne() {
        guard let parsed = TimestampCodec.parseISO8601("2026-09-04T00:00:00.123Z").success else {
            Issue.record("fractional seconds did not parse at all")
            return
        }
        #expect(TimestampCodec.renderISO8601(parsed, timeZone: .gmt) == "2026-09-04T00:00:00.123Z")
        #expect(TimestampCodec.renderISO8601(Self.referenceInstant, timeZone: .gmt) == "2026-09-04T00:00:00Z")
    }

    /// MEASURED, and found by this suite going red against the plan's own
    /// wording: the millisecond field is TRUNCATED, not rounded, and the
    /// Double nearest the decimal literal one-two-three-thousandths sits ONE
    /// ULP BELOW the value the parser produces for the same text.
    ///
    ///     decimal literal   1788480000.12299990653991699   renders .122
    ///     parser output     1788480000.12300014495849609   renders .123
    ///     bit patterns differ by exactly 1
    ///
    /// So writing the literal into an expectation and rendering it does NOT
    /// reproduce what the app does with that input — it is one millisecond
    /// low. This is asserted rather than avoided, because it is the whole
    /// shape of this subject: an epoch is a Double, a decimal fraction is not
    /// exactly representable, and the two sides of a round trip must not be
    /// allowed to make the same rounding error and call it agreement.
    @Test
    func theMillisecondFieldIsTruncatedAndADecimalLiteralIsNotTheParsedValue() {
        let decimalLiteral = 1_788_480_000.123
        let parserOutput = 1_788_480_000.123_000_1
        #expect(TimestampCodec.renderISO8601(decimalLiteral, timeZone: .gmt) == "2026-09-04T00:00:00.122Z")
        #expect(decimalLiteral < parserOutput, "the literal is one ULP below the parsed value")
        #expect(TimestampCodec.renderISO8601(1_788_480_000.999_9, timeZone: .gmt) == "2026-09-04T00:00:00.999Z",
                "truncated, not rounded up into the next second")
    }

    /// The property the whole feature rests on: rendering an instant in any
    /// zone and reading it back gives the same instant.
    @Test
    func everyCorpusInstantRoundTripsThroughEverySampleZone() {
        let instants = TestVectors.timestampCases.compactMap { testCase -> Double? in
            if case let .iso8601(value) = testCase.expected {
                value
            } else {
                nil
            }
        }
        #expect(instants.count >= 4, "no instants in the corpus; the loops below would assert nothing")
        #expect(Self.sampleZones.count == 3, "no zones; the loops below would assert nothing")
        for zone in Self.sampleZones {
            for instant in instants {
                let rendered = TimestampCodec.renderISO8601(instant, timeZone: zone)
                guard let recovered = TimestampCodec.parseISO8601(rendered).success else {
                    Issue.record("\(rendered) (\(zone.identifier)) did not re-parse")
                    continue
                }
                #expect(abs(recovered - instant) < Self.tolerance,
                        "\(instant) rendered as \(rendered) in \(zone.identifier) came back as \(recovered)")
            }
        }
    }

    // MARK: - The epoch cell

    /// No decimal point, no grouping separator, no locale digits. The second
    /// expectation is what gives the first one teeth: a locale-aware integer
    /// formatter renders this same number in Arabic-Indic digits, so an
    /// implementation that reached for one would break copy-paste silently.
    @Test
    func theEpochRendersAsPlainASCIIDigits() {
        let rendered = TimestampCodec.renderEpochSeconds(Self.referenceInstant)
        #expect(rendered == "1788480000")
        let localeAware = 1_788_480_000.formatted(.number.locale(Locale(identifier: "ar_EG@numbers=arab")))
        #expect(rendered != localeAware, "a locale-aware formatter would have produced \(localeAware)")
        #expect(rendered.filter { !$0.isASCII }.isEmpty, "an Eastern Arabic digit would land here")
    }

    /// The epoch cell and the ISO cell agree about which second an instant is
    /// in, including before 1970 — which is the case that discriminates.
    /// Truncating toward zero would render this instant as second 0 while the
    /// ISO cell showed the second before it.
    @Test
    func theEpochCellAndTheISOCellAgreeOnWhichSecondAnInstantIsIn() {
        #expect(TimestampCodec.renderEpochSeconds(-0.5) == "-1")
        #expect(TimestampCodec.renderISO8601(-0.5, timeZone: .gmt) == "1969-12-31T23:59:59.500Z")
        #expect(TimestampCodec.renderEpochSeconds(1_788_480_000.9) == "1788480000")
    }

    /// Total by construction. A non-finite Double reaches Foundation's date
    /// initializer as a trap site, and these bundles are host-based: a trap
    /// kills the host and aborts the run rather than failing one test. The
    /// guards are asserted here so nobody removes them as dead code.
    @Test
    func nonFiniteInputRendersEmptyInsteadOfTrapping() {
        #expect(TimestampCodec.renderISO8601(.nan, timeZone: .gmt).isEmpty)
        #expect(TimestampCodec.renderISO8601(.infinity, timeZone: .gmt).isEmpty)
        #expect(TimestampCodec.renderEpochSeconds(.nan).isEmpty)
        #expect(TimestampCodec.renderEpochSeconds(-.infinity).isEmpty)
        #expect(TimestampCodec.renderDateTime(.nan, timeZone: .gmt).isEmpty)
        #expect(TimestampCodec.renderDateTime(-.infinity, timeZone: Self.kolkata).isEmpty)
    }

    // MARK: - Timezone selection (APP-07)

    /// A RE-MEASUREMENT OF THE PLATFORM, not a test of this codec. The count
    /// is PRINTED and asserted only as a lower bound, because the tz database
    /// ships with the OS and grows: an equality assertion on it is a plan
    /// literal that goes stale by allocation.
    ///
    /// The sortedness expectation here is deliberately WEAK EVIDENCE and is
    /// labelled as such — measured, the platform's own array already arrives
    /// sorted and duplicate-free, so this assertion passes whether or not the
    /// implementation orders anything. The test below is where the guarantee
    /// is actually asserted.
    @Test
    func thePlatformTimeZoneTableIsUsableAsAPickerPopulation() {
        let identifiers = TimestampCodec.timeZoneIdentifiers
        print("timezone_count=\(identifiers.count)")
        print("timezone_contains_current=\(identifiers.contains(TimeZone.current.identifier))")
        #expect(identifiers.count > 300)
        #expect(identifiers.contains(TimeZone.current.identifier))
        #expect(identifiers.count == Set(identifiers).count, "a repeated identifier collides in a ForEach")
        #expect(identifiers.filter { TimeZone(identifier: $0) == nil }.isEmpty)
        #expect(identifiers == identifiers.sorted())
    }

    /// The ordering guarantee, asserted somewhere it CAN fail.
    ///
    /// MEASURED on this tree: the platform's identifier array is already in
    /// ascending order and already free of duplicates, so an assertion made
    /// only against the live list is a control that cannot fire — dropping the
    /// sort from the implementation leaves it green. `pickerOrder` exists so
    /// the guarantee has an input that discriminates; the second expectation
    /// is what ties the live property to it, so the two cannot drift apart.
    @Test
    func theOrderingIsAppliedAndNotInheritedFromThePlatform() {
        let scrambled = ["Zulu", "Africa/Abidjan", "Zulu", "America/Los_Angeles", "Africa/Accra"]
        #expect(TimestampCodec.pickerOrder(scrambled)
            == ["Africa/Abidjan", "Africa/Accra", "America/Los_Angeles", "Zulu"])
        #expect(TimestampCodec.timeZoneIdentifiers
            == TimestampCodec.pickerOrder(TimeZone.knownTimeZoneIdentifiers))
    }

    /// APP-07's default is the device zone, and it is reachable in the list
    /// the picker is populated from — a default that is not one of the options
    /// renders as an empty menu label.
    @Test
    func theDefaultZoneIsTheDeviceZone() {
        #expect(TimestampCodec.defaultTimeZone.identifier == TimeZone.current.identifier)
        #expect(TimestampCodec.timeZoneIdentifiers.contains(TimestampCodec.defaultTimeZone.identifier))
    }

    /// The assertion that proves the zone parameter is actually USED.
    ///
    /// No literal text is asserted anywhere in this test. `renderDateTime` is
    /// locale- and region-dependent — the UI spec's mockup and the machine the
    /// phase research ran on render this very instant differently — so
    /// non-emptiness, the four-digit year, and a difference between two zones
    /// are all that can honestly be claimed. A UI test reaches this cell by
    /// the `Timestamps.cell.dateTime` accessibility identifier, never by text.
    @Test
    func theDateAndTimeCellDiffersBetweenTwoZonesForTheSameInstant() {
        let west = TimestampCodec.renderDateTime(Self.referenceInstant, timeZone: Self.losAngeles)
        let east = TimestampCodec.renderDateTime(Self.referenceInstant, timeZone: Self.kolkata)
        #expect(!west.isEmpty)
        #expect(!east.isEmpty)
        #expect(west != east, "the zone argument changed nothing")
        #expect(west.contains("2026"))
        #expect(east.contains("2026"))
    }

    /// What makes the picker meaningful: the same instant reads differently in
    /// two zones without becoming a different instant.
    @Test
    func theSameInstantRendersDifferentlyInTwoZonesAndStillParsesBack() {
        let west = TimestampCodec.renderISO8601(Self.referenceInstant, timeZone: Self.losAngeles)
        let east = TimestampCodec.renderISO8601(Self.referenceInstant, timeZone: Self.kolkata)
        #expect(west != east)
        #expect(TimestampCodec.parseISO8601(west).success == Self.referenceInstant)
        #expect(TimestampCodec.parseISO8601(east).success == Self.referenceInstant)
    }

    // MARK: - Concurrency

    /// Nothing in the codec is cached, and the six types it names are all
    /// value types that satisfy `Sendable`. This compiles or it does not;
    /// there is no runtime assertion to make.
    @Test
    func theDateTypesTheCodecUsesAreAllSendable() {
        requireSendable(Date.ISO8601FormatStyle.self)
        requireSendable(Date.FormatStyle.self)
        requireSendable(TimeZone.self)
        requireSendable(Locale.self)
        requireSendable(Calendar.self)
        requireSendable(Date.self)
    }
}

/// A compile-time probe: naming a type here at all requires it to satisfy
/// `Sendable` under `-strict-concurrency=complete`. `private`, because
/// ConversionFailureTests and HTMLEntityTests each declare their own and all
/// three are compiled into one module.
private func requireSendable(_: (some Sendable).Type) {}
