// TimestampTests, continued — the corpus sweeps, as an extension.
//
// Same suite as TimestampTests.swift, so `-only-testing:AppMacOSTests/TimestampTests`
// runs both halves. Split into two files because `swiftlint --strict` enforces
// file_length (400) on this repo's config and one file carrying both the
// specified behaviour and the swept corpus exceeds it. An `extension` keeps
// the suite whole rather than creating a second suite name a `-only-testing:`
// invocation could silently miss — which matters here, because 06-03 measured
// that `-only-testing:` naming an ABSENT suite exits 0 printing
// `** TEST SUCCEEDED **` having run zero tests. The same call PercentTests and
// HTMLEntityTests already made.
//
// What lives here is the half that is EVIDENCE rather than specification: the
// shared corpus driven end to end, and the differential between the two
// format-style values the codec falls back across.

import Foundation
import Testing

extension TimestampTests {
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

    /// THE FALLBACK CANNOT TAKE A WRONG BRANCH (T-06-28), asserted rather
    /// than argued.
    ///
    /// `parseISO8601` tries a plain format style and then a fractional one,
    /// because measured on this app's OS range the two are COMPLEMENTARY below
    /// iOS 26 and IDENTICAL from iOS 26 on:
    ///
    ///                    "…T00:00:00Z"   "…T00:00:00.123Z"
    ///     iOS 17.5       plain only      fractional only
    ///     iOS 18.6       plain only      fractional only
    ///     iOS 26.1       both            both
    ///     macOS 26.5.2   both            both
    ///
    /// So the ORDER the two are tried in is unobservable, and this test is
    /// what says so: where both styles answer they must agree, and the codec's
    /// answer must be exactly the one style that answered. It fires if the
    /// fallback is removed, if it is reordered into a different answer, or if
    /// a future OS makes the two styles disagree.
    @Test(arguments: TestVectors.timestampCases)
    func theTwoStylesNeverDisagreeAboutAnInstant(_ testCase: TimestampCase) {
        let plain = (try? Date.ISO8601FormatStyle().parse(testCase.input))?.timeIntervalSince1970
        let fractional = (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            .parse(testCase.input))?.timeIntervalSince1970
        if let plain, let fractional {
            #expect(abs(plain - fractional) < Self.tolerance,
                    "the two styles disagree about \(testCase.input)")
        }
        #expect(TimestampCodec.parseISO8601(testCase.input).success == (plain ?? fractional),
                "the fallback lost or invented an answer for \(testCase.input)")
    }
}
