// DetectionTests, continued — the Local time path and the UTC offset it used
// to discard (CR-01, plan 06-20, GAP-06-02).
//
// Same suite as DetectionTests.swift and DetectionContractTests.swift, so
// `-only-testing:AppMacOSTests/DetectionTests` runs all three halves. A third
// FILE because `swiftlint --strict` enforces file_length (400) on this repo's
// config and the other two are near it; an `extension` keeps the suite whole
// rather than minting a second suite name a `-only-testing:` invocation could
// silently miss. `-only-testing:` naming an ABSENT suite exits 0 printing
// `** TEST SUCCEEDED **` having run zero tests, which 06-03 measured.
//
// WHAT WAS WRONG, MEASURED BEFORE IT WAS FIXED
//
// `classifyLocalTime` accepted `Z`, `+05:30` and `-08:00`, but the three
// format styles `parseLocalTime` built came from a `base` declaring NO zone
// field, so Foundation dropped the designator and read the wall clock in the
// picker's zone. With the picker on Asia/Tokyo, measured on this tree at
// 929ba9c by a `swiftc` harness over the engine sources:
//
//   2026-09-04T00:00:00+05:30   localTime=1788447600   iso8601=1788460200
//   2026-09-04T00:00:00-08:00   localTime=1788447600   iso8601=1788508800
//   2026-09-04T00:00:00Z        localTime=1788447600   iso8601=1788480000
//   2026-09-04T00:00:00         localTime=1788447600   iso8601=failure
//
// Four instants collapsed to one, three of them wrong by hours, and every one
// of the four returned `.success`. The validator accepted input the parser
// could not honour — the app's own "the classifier is the authority" principle
// inverted, and the "quietly wrong answer" half of ROADMAP criterion 1.
//
// THE INVARIANT THESE TESTS PIN, AND WHY IT IS STATED OVER BOTH PATHS
//
//     readLocalTime(s) == .explicitOffset  ⟹
//         parse(s, as: .localTime, timeZone: ANY) == parse(s, as: .iso8601)
//
// Stated over both paths rather than over the fixed one alone, because the
// defect was a DISAGREEMENT and an assertion about one side of a disagreement
// cannot see it. The deliberate divergence — a wall clock DOES depend on the
// picker's zone — is asserted here too rather than left implicit, since an
// undocumented divergence is how this one started.

import Foundation
import Testing

extension DetectionTests {
    // MARK: - The four inputs the review measured

    /// The three zone-bearing shapes plus the zone-free one they collapsed
    /// onto, with the instant each one names.
    ///
    /// `2026-09-04T00:00:00Z` is 1788480000. Its `+05:30` and `-08:00`
    /// spellings name different instants by construction — that is what an
    /// offset IS — and the whole defect was that all three produced the
    /// picker-zone wall-clock reading 1788447600 instead.
    static let zonedInstants: [(input: String, instant: Double)] = [
        ("2026-09-04T00:00:00+05:30", 1_788_460_200),
        ("2026-09-04T00:00:00-08:00", 1_788_508_800),
        ("2026-09-04T00:00:00Z", 1_788_480_000),
        ("2026-09-04T00:00:00z", 1_788_480_000),
        ("2026-09-04T00:00:00+0000", 1_788_480_000),
        ("2026-09-04T00:00:00-0730", 1_788_507_000),
        ("2026-09-04 00:00:00Z", 1_788_480_000)
    ]

    /// The zone the review measured against, and two more with different
    /// signs and a half-hour offset, so "the answer does not depend on the
    /// picker" has a population that could fail.
    static let pickerZones: [TimeZone] = [
        TimeZone(identifier: "Asia/Tokyo") ?? .gmt,
        TimeZone(identifier: "America/Los_Angeles") ?? .gmt,
        TimeZone(identifier: "Asia/Kolkata") ?? .gmt,
        .gmt
    ]

    // MARK: - CR-01

    /// Reading a zone-bearing timestamp as Local time yields the instant the
    /// input NAMES, not the picker's wall clock.
    ///
    /// The four measured inputs, one expectation each, with the wrong value
    /// named in the message — so a regression says what it produced instead of
    /// only that it differed.
    @Test
    func theLocalTimePathHonoursAnExplicitOffset() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
        for row in Self.zonedInstants {
            let got = TimestampDetection.parse(row.input, as: .localTime, timeZone: tokyo).success
            let why = "\(row.input) as Local time in Asia/Tokyo must be \(row.instant), "
                + "not the wall-clock reading 1788447600 CR-01 measured; got \(String(describing: got))"
            #expect(got == row.instant, "\(why)")
        }
    }

    /// The three shapes name three different instants, so they cannot all be
    /// the same number.
    ///
    /// The bug's signature was a COLLAPSE — four inputs, one answer. This
    /// asserts the count of distinct answers directly, which is the shape of
    /// the defect rather than a sample of it.
    @Test
    func fourDistinctInstantsDoNotCollapseOntoOne() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
        let inputs = ["2026-09-04T00:00:00+05:30",
                      "2026-09-04T00:00:00-08:00",
                      "2026-09-04T00:00:00Z",
                      "2026-09-04T00:00:00"]
        let answers = inputs.compactMap { TimestampDetection.parse($0, as: .localTime, timeZone: tokyo).success }
        #expect(answers.count == 4, "all four still parse: \(answers)")
        #expect(Set(answers).count == 4, "four different instants, four different answers; got \(answers)")
    }

    /// The invariant, over every zone-bearing input and every picker zone:
    /// **the two paths never silently disagree.**
    ///
    /// This is the assertion the defect would have failed at 929ba9c and the
    /// one that keeps a future edit to either path from re-opening it. It runs
    /// over the product of the inputs and the zones, and asserts the accepted
    /// population is non-empty first — a forward implication over an empty set
    /// is vacuously true, which is the "control that cannot fire" this phase
    /// has now met eight times.
    @Test
    func noAcceptedZonedInputReadsAsADifferentInstantThanISO8601() {
        var compared = 0
        for row in Self.zonedInstants {
            #expect(TimestampDetection.readLocalTime(row.input) == .explicitOffset,
                    "\(row.input) carries a designator the local scan accepts")
            let iso = TimestampDetection.parse(Self.isoSpelling(row.input), as: .iso8601).success
            #expect(iso == row.instant, "the ISO path is the reference: \(row.input)")
            for zone in Self.pickerZones {
                let local = TimestampDetection.parse(row.input, as: .localTime, timeZone: zone).success
                let why = "\(row.input) in \(zone.identifier): Local time \(String(describing: local)) "
                    + "must equal ISO 8601 \(String(describing: iso))"
                #expect(local == iso, "\(why)")
                compared += 1
            }
        }
        #expect(compared == Self.zonedInstants.count * Self.pickerZones.count)
        #expect(compared >= 20, "the population the implication runs over is not empty: \(compared)")
    }

    /// The one documented divergence, asserted rather than assumed: a WALL
    /// CLOCK carries no instant of its own, so it does depend on the picker's
    /// zone — and ISO 8601 refuses it outright, so the two paths are never
    /// both defined on it and cannot disagree.
    @Test
    func aWallClockDependsOnThePickerZoneAndISO8601RefusesIt() {
        let wallClocks = ["2026-09-04T00:00:00", "2026-09-04 00:00:00", "2026-09-04"]
        for input in wallClocks {
            #expect(TimestampDetection.readLocalTime(input) == .wallClock, "\(input) names no zone")
            #expect(TimestampDetection.parse(input, as: .iso8601).failure != nil,
                    "\(input) is not extended-format ISO 8601, so the paths never overlap here")
            let answers = Self.pickerZones.compactMap {
                TimestampDetection.parse(input, as: .localTime, timeZone: $0).success
            }
            #expect(answers.count == Self.pickerZones.count, "\(input) parses in every zone")
            #expect(Set(answers).count == Self.pickerZones.count,
                    "\(input) is a wall clock, so each zone gives its own instant: \(answers)")
        }
    }

    /// The local scan and the ISO scan agree about which strings are well
    /// formed once the one spelling difference between them is removed.
    ///
    /// The local shape allows a SPACE where extended-format ISO 8601 requires
    /// a `T`; measured, `classifyISO8601("2026-09-04 00:00:00Z")` reports
    /// `expected 'T' at position 11`. That is the ONLY difference for a
    /// zone-bearing input, and this is what makes delegating the parse safe
    /// rather than merely convenient.
    @Test
    func everyZonedLocalInputIsAlsoWellFormedISO8601OnceTheSeparatorIsNormalised() {
        for row in Self.zonedInstants {
            let iso = Self.isoSpelling(row.input)
            #expect(TimestampDetection.classifyLocalTime(row.input) == nil, "\(row.input) is a well-formed local time")
            #expect(TimestampDetection.classifyISO8601(iso) == nil, "\(iso) is well-formed ISO 8601")
        }
    }

    /// A rejected local input is still rejected, with the position it always
    /// reported — the fix moves the PARSE, not the scan.
    @Test
    func theLocalScanStillReportsTheSamePositions() {
        #expect(TimestampDetection.classifyLocalTime("2026-09-04X00:00:00") == .expectedCharacter("T", position: 11))
        #expect(TimestampDetection.classifyLocalTime("2026-13-04")
            == .expectedCharacter("a month from 01 to 12", position: 6))
        #expect(TimestampDetection.classifyLocalTime("2026-09-04T00:00:00+19:00")
            == .expectedCharacter("an offset from -18:00 to +18:00", position: 20))
        #expect(TimestampDetection.classifyLocalTime("2026-09-04T00:00:00Zx")
            == .expectedCharacter("the end of the input", position: 21))
    }

    // MARK: -

    /// `input` with its date-time separator written the one way extended
    /// format accepts. Only the separator moves; no field is reinterpreted.
    static func isoSpelling(_ input: String) -> String {
        guard let space = input.firstIndex(of: " ") else { return input }
        return input.replacingCharacters(in: space ... space, with: "T")
    }
}
