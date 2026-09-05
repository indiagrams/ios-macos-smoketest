// DetectionTests, continued — the ISO 8601 positional classifier and the
// one-directional contract that makes it usable.
//
// Same suite as DetectionTests.swift, so `-only-testing:AppMacOSTests/DetectionTests`
// runs both halves. Split into two files because `swiftlint --strict` enforces
// file_length (400) on this repo's config; an `extension` keeps the suite whole
// rather than creating a second suite name a `-only-testing:` invocation could
// silently miss — which matters, because 06-03 measured that `-only-testing:`
// naming an ABSENT suite exits 0 printing `** TEST SUCCEEDED **` having run
// zero tests. The same call `PercentContractTests`, `HTMLEntityContractTests`
// and `TimestampContractTests` already made.
//
// THE CONTRACT, IN ONE DIRECTION ONLY
//
//     classifyISO8601(s) == nil  ⟹  TimestampCodec.parseISO8601(s) is .success
//
// The converse is MEASURABLY FALSE and is not asserted. Measured on this tree,
// `Date.ISO8601FormatStyle` parses "2026-09-04T00:00:00Zhello world", ignoring
// everything after the zone designator; it parses "2026-09-04T00:80:00Z" and
// silently normalises minute 80 to 01:20; and it parses "…T00:00:00GMT". The
// classifier refuses all three, because converting input the user did not
// write is the "quietly wrong answer" half of criterion 1. That divergence is
// ASSERTED below, in `theClassifierRefusesThreeFormsTheParserSilentlyAccepts`,
// rather than reconciled — the same answer `Base64Codec` gives about
// `Data(base64Encoded:)`, for the same reason.
//
// WHY THE GENERATED SWEEP ALSO COUNTS ITS ACCEPTANCES
//
// A forward implication is vacuously true over a population the classifier
// rejects entirely. The sweep therefore asserts a floor on how many mutants it
// ACCEPTED before asserting anything about them — the "a correct check pointed
// at the wrong population" row, applied to a check that could otherwise pass
// by looking at nothing.

import Foundation
import Testing

extension DetectionTests {
    // MARK: - The population the contract is about

    /// The RAW parser, two styles, unmediated by the classifier.
    ///
    /// **The contract must be asserted against this and not against
    /// ``TimestampCodec/parseISO8601(_:)``.** That function consults the scan
    /// FIRST, so `classify(s) == nil ⟹ parseISO8601(s) is .success` would be
    /// circular there — it would say only that the classifier agrees with
    /// itself, and the divergence count below would be 0 by construction
    /// rather than by measurement. Duplicating the codec's two-style fallback
    /// here is deliberate: this is the differential, and a differential needs
    /// the other side to be the other side.
    static func rawParse(_ s: String) -> Double? {
        if let instant = try? Date.ISO8601FormatStyle().parse(s) {
            return instant.timeIntervalSince1970
        }
        if let instant = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(s) {
            return instant.timeIntervalSince1970
        }
        return nil
    }

    // MARK: - What a valid extended date and time looks like

    /// Every form measured as parsing ON ALL FOUR SUPPORTED RUNTIMES is also
    /// accepted by the scan.
    ///
    /// - Important: The population is the INTERSECTION, not what macOS
    ///   accepts. `"…T24:00:00Z"` and `"…T00:00:60Z"` are absent because they
    ///   are nil on iOS 17.5 and parse on the other three; `"…+05"` is absent
    ///   because it is nil on iOS 18.6 and parses on the other three. A list
    ///   drawn from the development machine would put all three here and go
    ///   red on the floor — which is exactly what it did before it was
    ///   re-measured.
    @Test
    func theClassifierAcceptsEveryZoneFormTheParserAccepts() {
        let valid = [
            "2026-09-04T00:00:00Z",
            "2026-09-04T00:00:00z",
            "2026-09-04T00:00:00+05:30",
            "2026-09-04T00:00:00+0530",
            "2026-09-04T00:00:00-0800",
            "2026-09-04T00:00:00-07:00",
            "2026-09-04T00:00:00+5:30",
            "2026-09-04T00:00:00+05:3",
            "2026-09-04T00:00:00+18:00",
            "2026-09-04T00:00:00.123Z",
            "2026-09-04T00:00:00.123456789Z",
            "2026-09-04T23:59:59Z",
            "202-09-04T00:00:00Z",
            "2024-02-29T00:00:00Z",
            "0001-01-01T00:00:00Z",
            "9999-12-31T23:59:59Z"
        ]
        #expect(valid.count >= 15)
        for input in valid {
            #expect(TimestampDetection.classifyISO8601(input) == nil, "\(input) should classify clean")
            #expect(Self.rawParse(input) != nil, "\(input) should parse")
        }
    }

    // MARK: - Expected token and position

    /// `timestamps.error.iso8601` — "Not valid ISO 8601: expected '%@' at
    /// position %lld." Six distinct positions with six distinct tokens, which
    /// is what makes the message worth showing at all.
    ///
    /// The convention is `iso_expected_token_convention=both`: a LITERAL where
    /// one character is expected, a NAMED CLASS where a class or a range is.
    /// Forcing one convention on the other would mean reporting "expected '0'"
    /// for month 13, which is false and useless.
    @Test
    func theClassifierNamesTheExpectedTokenAndItsPosition() {
        #expect(TimestampDetection.classifyISO8601("2026/09/04T00:00:00Z")
            == .expectedCharacter("-", position: 5))
        #expect(TimestampDetection.classifyISO8601("2026-09-04 00:00:00Z")
            == .expectedCharacter("T", position: 11))
        #expect(TimestampDetection.classifyISO8601("2026-09-04T00-00:00Z")
            == .expectedCharacter(":", position: 14))
        #expect(TimestampDetection.classifyISO8601("2026-13-04T00:00:00Z")
            == .expectedCharacter("a month from 01 to 12", position: 6))
        // The calendar is real, and February knows what year it is.
        #expect(TimestampDetection.classifyISO8601("2026-02-31T00:00:00Z")
            == .expectedCharacter("a day from 01 to 28", position: 9))
        #expect(TimestampDetection.classifyISO8601("2024-02-31T00:00:00Z")
            == .expectedCharacter("a day from 01 to 29", position: 9))
        #expect(TimestampDetection.classifyISO8601("2026-04-31T00:00:00Z")
            == .expectedCharacter("a day from 01 to 30", position: 9))
        #expect(TimestampDetection.classifyISO8601("2026-09-04T00:00:00")
            == .expectedCharacter("a time zone designator", position: 20))
        #expect(TimestampDetection.classifyISO8601("2026-09-04T00:00:00Zx")
            == .expectedCharacter("the end of the input", position: 21))
    }

    /// A position is a 1-based CHARACTER offset, so a multi-byte grapheme
    /// before the fault does not shift it into the middle of one. This is the
    /// only unit this app reports and `Position.swift` is its one definition.
    @Test
    func aPositionIsACharacterOffsetAndNotAByteOffset() {
        // "héllo" is 5 Characters and 6 UTF-8 bytes; the fault is at the "l".
        #expect(TimestampDetection.classifyISO8601("héll-09-04T00:00:00Z")
            == .expectedCharacter("a digit", position: 1))
        #expect(TimestampDetection.classifyISO8601("2026-09-04Té0:00:00Z")
            == .expectedCharacter("a digit", position: 12))
    }

    /// The empty string is a failure at position 1 — never `nil`, and never a
    /// trap. A positional scan over indices is the classic trap site in this
    /// subject and these bundles are host-based.
    @Test
    func theEmptyStringIsAFailureAtPositionOne() {
        #expect(TimestampDetection.classifyISO8601("") == .expectedCharacter("a digit", position: 1))
    }

    // MARK: - The authority question, answered the same way as Base64

    /// MEASURED LENIENCIES, PRESERVED RATHER THAN TIGHTENED.
    ///
    /// Every numeric field of `Date.ISO8601FormatStyle` accepts a
    /// variable-width digit run, measured on all four supported runtimes. A
    /// scan requiring two digits per field would report an error for input the
    /// app converts successfully — the defect
    /// `control=timestamp-classifier-is-the-authority` was written for in
    /// 06-07, which named two of these six. The other four were found by
    /// re-measuring, and one of them (`2026-9-04T…`) is the input this plan
    /// specified as a failure at position 7.
    ///
    /// Both sides are asserted: the parser accepts it AND the scan accepts it.
    /// Asserting only the second would pass against a scan that accepts
    /// everything.
    @Test
    func theClassifierIsNotStricterThanTheParserAboutFieldWidth() {
        let lenient = [
            "2026-09-04T00:00:0Z": "single-digit seconds — named by 06-07",
            "2026-09-04T00:0:00Z": "single-digit minutes",
            "2026-09-04T0:00:00Z": "single-digit hours",
            "2026-09-4T00:00:00Z": "single-digit day",
            "2026-9-04T00:00:00Z": "single-digit month — the plan specified this as position 7",
            "2026-09-04T00:00:00z": "lowercase zone designator — found by 06-07"
        ]
        #expect(lenient.count == 6)
        for (input, why) in lenient {
            #expect(Self.rawParse(input) != nil, "the parser accepts it: \(why)")
            #expect(TimestampDetection.classifyISO8601(input) == nil, "so the scan must too: \(why)")
            #expect(TimestampCodec.parseISO8601(input).success != nil, "and the app converts it: \(why)")
        }
    }

    /// WHERE THE SCAN IS STRICTER, DELIBERATELY, AND THE DIVERGENCE IS STATED.
    ///
    /// All three of these PARSE. Accepting them would mean the app converts
    /// something the user did not write and reports no error, which is exactly
    /// the failure mode criterion 1 exists to prevent. The converse of the
    /// contract is false and this test is the evidence for that claim.
    @Test
    func theClassifierRefusesThreeFormsTheParserSilentlyAccepts() {
        let diverging = [
            "2026-09-04T00:00:00Zhello": "everything after the zone designator is ignored by the parser",
            "2026-09-04T00:00:00GMT": "a named zone parses on all four runtimes and is not ISO 8601",
            "2026-009-04T00:00:00Z": "a three-digit month parses on all four and is not ISO 8601"
        ]
        #expect(diverging.count == 3)
        for (input, why) in diverging {
            #expect(Self.rawParse(input) != nil, "the RAW parser accepts it: \(why)")
            #expect(TimestampDetection.classifyISO8601(input) != nil, "the scan refuses it: \(why)")
            #expect(TimestampCodec.parseISO8601(input).success == nil, "so the app refuses it: \(why)")
        }
    }

    /// THE REGRESSION TEST FOR THIS PLAN'S LARGEST FINDING.
    ///
    /// Ten forms whose accept/reject verdict SPLITS across the four supported
    /// runtimes. The scan refuses every one of them, so the app behaves the
    /// same on iOS 17.5, 18.6, 26.1 and macOS — which is what these codecs
    /// exist for, and what the plan's original macOS-derived accept-list would
    /// have broken on the floor.
    ///
    /// Measured, and none of it is in 06-RESEARCH.md:
    ///
    /// - **iOS 17.5 applies a real calendar; the other three normalise
    ///   forward.** `2026-02-31` is nil on the floor and 2026-03-03 elsewhere.
    /// - **iOS 17.5 rejects hour 24 and second 60**, which ISO 8601 permits
    ///   and the other three accept.
    /// - **iOS 18.6 rejects an hours-only offset** that the other three
    ///   accept, and accepts three forms (offset past 18:00, a seven-digit
    ///   year, ten fraction digits) that the other three reject.
    ///
    /// These assertions do not depend on which runtime they run on, which is
    /// the point: the scan's verdict is the app's behaviour, everywhere.
    @Test
    func theClassifierRefusesEveryFormThatSplitsAcrossTheSupportedRuntimes() {
        let split = [
            "2026-09-04T24:00:00Z": "hour 24 is nil on iOS 17.5 and parses on the other three",
            "2026-09-04T00:00:60Z": "second 60 is nil on iOS 17.5 and parses on the other three",
            "2026-09-04T00:00:61Z": "second 61, the same split",
            "2026-02-29T00:00:00Z": "Feb 29 of a non-leap year is nil on iOS 17.5, 2026-03-01 elsewhere",
            "2026-02-31T00:00:00Z": "Feb 31 is nil on iOS 17.5, 2026-03-03 elsewhere",
            "2026-04-31T00:00:00Z": "Apr 31 is nil on iOS 17.5, 2026-05-01 elsewhere",
            "2026-09-04T00:00:00+05": "an hours-only offset is nil on iOS 18.6 and parses on the other three",
            "2026-09-04T00:00:00+18:01": "an offset past 18:00 parses on iOS 18.6 alone",
            "1234567-09-04T00:00:00Z": "a seven-digit year parses on iOS 18.6 alone",
            "2026-09-04T00:00:00.1234567890Z": "ten fraction digits parse on iOS 18.6 alone"
        ]
        #expect(split.count == 10)
        for (input, why) in split {
            #expect(TimestampDetection.classifyISO8601(input) != nil, "\(input): \(why)")
            #expect(TimestampCodec.parseISO8601(input).success == nil, "\(input): \(why)")
        }
    }

    // MARK: - The one-directional contract

    /// The contract over the shared corpus. Guarded by a count, because a
    /// sweep over an emptied subset asserts nothing and reports success.
    @Test
    func aCleanClassificationImpliesTheParserSucceedsOverTheCorpus() {
        let inputs = TestVectors.timestampCases.map(\.input)
        #expect(inputs.count >= 9)
        var accepted = 0
        for input in inputs where TimestampDetection.classifyISO8601(input) == nil {
            accepted += 1
            #expect(Self.rawParse(input) != nil, "\(input) classified clean but did not parse")
        }
        #expect(accepted >= 4, "the corpus contributed \(accepted) clean classifications")
    }

    /// The contract over a generated mutation sweep, which is the population
    /// that can actually discriminate: single-character substitutions,
    /// deletions and insertions over a valid extended date and time.
    ///
    /// - Note: The ACCEPTANCE floor is asserted first. A classifier that
    ///   rejected every mutant would satisfy the implication vacuously, and a
    ///   check that passes without having looked is this phase's founding
    ///   anti-pattern.
    @Test
    func aCleanClassificationImpliesTheParserSucceedsOverAGeneratedSweep() {
        let base = "2026-09-04T00:00:00Z"
        let alphabet: [Character] = ["0", "9", "-", ":", "T", ".", "Z", "z", "+", "/", " ", "x"]
        var mutants: [String] = []
        for index in base.indices {
            for replacement in alphabet {
                var mutant = base
                mutant.replaceSubrange(index ... index, with: String(replacement))
                mutants.append(mutant)
                var inserted = base
                inserted.insert(replacement, at: index)
                mutants.append(inserted)
            }
            var deleted = base
            deleted.remove(at: index)
            mutants.append(deleted)
        }
        #expect(mutants.count >= 400, "the sweep generated \(mutants.count) mutants")

        var accepted = 0
        var stricter = 0
        for mutant in mutants {
            let clean = TimestampDetection.classifyISO8601(mutant) == nil
            let parses = Self.rawParse(mutant) != nil
            if clean {
                accepted += 1
                #expect(parses, "\(mutant.debugDescription) classified clean but did not parse")
            } else if parses {
                stricter += 1
            }
        }
        // Measured on this tree: 500 mutants, 51 accepted, 33 diverging, 0
        // contract violations. The floor is 40 rather than 51 because these
        // are Foundation parse results and this suite runs on four runtimes —
        // a frozen equality here would be a plan literal that goes stale by OS
        // release. It is still far above 0, which is what the guard is for.
        #expect(accepted >= 40, "only \(accepted) mutants classified clean; the sweep proves nothing")
        #expect(stricter >= 1, "\(stricter) mutants parse but are refused; the converse is false")
    }

    // MARK: - What the model actually receives

    /// The position-free fallback plan 06-07 left behind is gone: an ISO
    /// failure reaching the model now names a token and a real position.
    @Test
    func everyISOFailureTheModelReceivesCarriesARealPosition() {
        #expect(TimestampCodec.parseISO8601("2026-09-04").failure == .expectedCharacter("T", position: 11))
        #expect(TimestampDetection.parse("2026-09-04 00:00:00Z", as: .iso8601).failure
            == .expectedCharacter("T", position: 11))
        #expect(TimestampDetection.parse("2026/09/04T00:00:00Z", as: .iso8601).failure
            == .expectedCharacter("-", position: 5))
        // Local time is reported by the same scan, with the time and the zone
        // optional — so a bare calendar date is not an error there.
        #expect(TimestampDetection.parse("2026-09-04", as: .localTime).success != nil)
        #expect(TimestampDetection.parse("2026-09-04X00:00:00", as: .localTime).failure
            == .expectedCharacter("T", position: 11))
    }

    // MARK: - Totality

    /// 1 KB of arbitrary text through the scan, plus the shapes most likely to
    /// walk an index off the end. A trap here would kill the host process.
    @Test
    func theScanIsTotalOverArbitraryInput() {
        var generator = SeededGenerator(seed: 0x0608_15D0_C1A5)
        let pool: [Unicode.Scalar] = (32 ... 126).compactMap { Unicode.Scalar(UInt8($0)) }
            + ["\u{00E9}", "\u{FFFD}", "\u{1F600}"]
        var inputs = ["", "2", "2026", "2026-", "2026-0", "2026-09-04T", "2026-09-04T00:00:00.",
                      "2026-09-04T00:00:00+", "2026-09-04T00:00:00+0", "👨‍👩‍👧‍👦",
                      String(repeating: "9", count: 1024)]
        for _ in 0 ..< 32 {
            inputs.append(generator.randomScalarString(from: pool, maxScalars: 1024))
        }
        #expect(inputs.count >= 40)
        for input in inputs {
            _ = TimestampDetection.classifyISO8601(input)
            _ = TimestampCodec.parseISO8601(input)
            _ = TimestampDetection.parse(input, as: .localTime, timeZone: .gmt)
        }
    }
}
