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

    // MARK: - Parsing

    /// The fraction is compared with a tolerance, and the second expectation
    /// says how wide the truth actually is: WITHIN ONE ULP of the decimal
    /// literal, which is a far tighter claim than the suite's 0.001 s and is
    /// the same on every supported OS.
    ///
    /// It is not asserted as EQUAL to the literal and not asserted as
    /// DIFFERENT from it, because measured on four runtimes it is both:
    ///
    ///     iOS 17.5              1788480000.12299990653991699  == the literal
    ///     iOS 18.6 / 26.1 / macOS 1788480000.12300014495849609  one ULP above
    ///
    /// Pinning either answer would make the suite red on half the OS range for
    /// no defect. This is why the tolerance exists.
    @Test
    func fractionalSecondsParseWithinOneULPOfTheDecimalLiteral() {
        guard let value = TimestampCodec.parseISO8601("2026-09-04T00:00:00.123Z").success else {
            Issue.record("fractional seconds did not parse at all")
            return
        }
        let decimalLiteral = 1_788_480_000.123
        #expect(abs(value - decimalLiteral) < Self.tolerance)
        #expect(abs(value - decimalLiteral) <= decimalLiteral.ulp,
                "\(value) is more than one ULP from the literal; re-measure before widening this")
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
    /// bare `nil`. The position is now REAL: 06-07 returned a stated
    /// placeholder because the parser throws without one, and 06-08's
    /// positional scan replaced it. `"2026-09-04"` is a complete calendar date
    /// missing its time, so the expected token is the `T` that would follow.
    @Test
    func aFailureIsAConversionFailureAndNotABareNil() {
        #expect(TimestampCodec.parseISO8601("2026-09-04").failure == .expectedCharacter("T", position: 11))
        #expect(TimestampCodec.parseISO8601("").failure == .expectedCharacter("a digit", position: 1))
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

    /// The fraction renders to three digits, is never rounded up into the
    /// next second, and never invents one. MEASURED IDENTICAL on macOS,
    /// iOS 17.5, iOS 18.6 and iOS 26.1.
    ///
    /// THE ROUNDING MODE OF THE THIRD DIGIT IS NOT ASSERTED, because it is not
    /// the same on every supported OS. Measured, for the Double one ULP below
    /// a millisecond boundary (1788480000.12299990653991699):
    ///
    ///     iOS 17.5                 renders .123   (rounds)
    ///     iOS 18.6 / 26.1 / macOS  renders .122   (truncates)
    ///
    /// It costs the app nothing: the divergence needs an input one ULP off a
    /// boundary, and no parse produces one — the same instant coming OUT of
    /// the parser renders .123 on all four. Every value below is at least an
    /// ULP clear of a boundary and renders identically everywhere.
    @Test
    func theFractionRendersToThreeDigitsAndNeverIntoTheNextSecond() {
        #expect(TimestampCodec.renderISO8601(1_788_480_000.999_9, timeZone: .gmt) == "2026-09-04T00:00:00.999Z")
        #expect(TimestampCodec.renderISO8601(1_788_480_000.999_999, timeZone: .gmt) == "2026-09-04T00:00:00.999Z")
        #expect(TimestampCodec.renderISO8601(1_788_480_000.122_9, timeZone: .gmt) == "2026-09-04T00:00:00.122Z")
        #expect(TimestampCodec.renderISO8601(1_788_480_000.000_5, timeZone: .gmt) == "2026-09-04T00:00:00.000Z")
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
    ///
    /// - Important: **AMENDED 2026-09-05 (plan 06-20, CR-02).** The second
    ///   expectation used to read
    ///   `timeZoneIdentifiers.contains(defaultTimeZone.identifier)` — against
    ///   the RUNNER'S zone. This machine and CI are both `America/Los_Angeles`,
    ///   which is in the platform table, so it was green here and on CI and red
    ///   on an India-configured device: a correct check pointed at the wrong
    ///   POPULATION. The reachability claim now lives in
    ///   `theOptionListAlwaysContainsTheSelection` and
    ///   `thePickerViewOffersTheZoneTheModelIsSetTo`, which INJECT a link name
    ///   the table omits instead of reading the environment. What is left here
    ///   is the half that is actually about the default: that it is the
    ///   device's zone and not some other one.
    @Test
    func theDefaultZoneIsTheDeviceZone() {
        #expect(TimestampCodec.defaultTimeZone.identifier == TimeZone.current.identifier)
        let reachable = TimestampCodec.timeZoneIdentifiers(including: TimestampCodec.defaultTimeZone.identifier)
            .contains(TimestampCodec.defaultTimeZone.identifier)
        #expect(reachable, "whatever zone this runner is in, the picker offers it")
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
