// AppModel — D-82's per-surface state, and D-12's "nothing is kept".
//
// An `extension` of `PipelineTests` rather than a suite of its own, so that
// `-only-testing:AppMacOSTests/PipelineTests` selects these cases too.
//
// `AppModel` is `@MainActor`, so every case here is `@MainActor`. The unit
// targets are Swift 6 with `-strict-concurrency=complete`, which means a case
// that got the isolation wrong would FAIL TO COMPILE rather than fail at run
// time. That compile step is the mechanism that makes APP-12 continuously
// enforced rather than checked once.

import Foundation
import Testing

extension PipelineTests {
    // MARK: - D-82 — one pipeline per surface, for the life of the launch

    @MainActor
    @Test
    func theModelOwnsOneEmptyPipelinePerSurface() {
        let model = AppModel()
        #expect(model.encode == Pipeline())
        #expect(model.hashing == Pipeline())
        #expect(model.timestamps == Pipeline())
    }

    /// The trap D-82 closes, at the model layer: on macOS a
    /// `NavigationSplitView` detail swap would otherwise discard in-progress
    /// work. Three pipelines that are genuinely separate storage is what makes
    /// navigating away and back restore exactly what was there — so the
    /// assertion is that writing to one surface leaves the other two alone.
    @MainActor
    @Test
    func writingToOneSurfaceLeavesTheOtherTwoUntouched() {
        let model = AppModel()
        model.encode.input = "hello"
        model.encode.steps = Self.steps(.base64Encode)
        #expect(model.encode.input == "hello")
        #expect(model.encode.evaluate() == [.value("aGVsbG8=")])
        #expect(model.hashing == Pipeline(), "the Hashing surface lost or gained state it does not own")
        #expect(model.timestamps == Pipeline(), "the Timestamps surface lost or gained state it does not own")
        model.hashing.input = "hello"
        model.hashing.steps = Self.steps(.sha256)
        #expect(model.encode.input == "hello")
        #expect(model.encode.steps.first?.operation == .base64Encode, "the Encode surface's steps were disturbed")
        #expect(model.hashing.evaluate() == [.value(DigestCodec.sha256("hello"))])
    }

    /// The add-step control, all the way through the model: append, and read
    /// the chained result back off the surface that owns the pipeline. This is
    /// APP-08 at the layer the view will actually call.
    @MainActor
    @Test
    func appendingThroughTheModelProducesTheChainedResult() {
        let model = AppModel()
        model.encode.input = "hello"
        model.encode.steps = Self.steps(.base64Encode)
        model.encode = model.encode.appending(.md5)
        #expect(model.encode.steps.count == 2)
        #expect(model.encode.evaluate() == [.value("aGVsbG8="), .value(DigestCodec.md5("aGVsbG8="))])
    }

    /// D-84's premise: the model holds no derived cache, so there is nothing
    /// that can be stale. Asserted across a mutation, not just at rest.
    @MainActor
    @Test
    func theModelHoldsNoDerivedCacheSoEvaluationIsStable() {
        let model = AppModel()
        model.encode.input = "a b"
        model.encode.steps = Self.steps(.urlEncode, .base64Decode, .md5)
        #expect(model.encode.evaluate() == model.encode.evaluate())
        #expect(model.encode.evaluate() == [.value("a%20b"), .failure(Self.chainFailure), .blocked])
        model.encode.input = "hello"
        #expect(model.encode.evaluate() == model.encode.evaluate())
        #expect(model.encode.evaluate().first == .value("hello"), "urlEncode leaves an unreserved string alone")
        #expect(
            model.encode.evaluate() != [.value("a%20b"), .failure(Self.chainFailure), .blocked],
            "a stale result survived a rewrite of the input"
        )
    }

    // MARK: - The per-surface selections that must survive navigation

    /// The Encode surface's two selections are exactly the six codec
    /// operations, three formats by two directions. Asserted as a product
    /// rather than as a count, so a format added without an operation — or two
    /// selections that collapse onto one operation — fails here.
    @Test
    func theEncodeSelectionsCoverExactlyTheSixCodecOperations() {
        #expect(EncodeFormat.allCases.count == 3)
        #expect(EncodeDirection.allCases.count == 2)
        let produced = Set(EncodeFormat.allCases.flatMap { format in
            EncodeDirection.allCases.map { format.operation($0) }
        })
        #expect(produced.count == 6, "two selections mapped onto one operation")
        #expect(produced == Set(Operation.allCases.prefix(6)))
        #expect(EncodeFormat.base64.operation(.encode) == .base64Encode)
        #expect(EncodeFormat.base64.operation(.decode) == .base64Decode)
        #expect(EncodeFormat.url.operation(.encode) == .urlEncode)
        #expect(EncodeFormat.html.operation(.decode) == .htmlDecode)
    }

    @MainActor
    @Test
    func theEncodeSelectionDefaultsToBase64EncodeAndSurvivesAWrite() {
        let model = AppModel()
        #expect(model.encodeFormat == .base64)
        #expect(model.encodeDirection == .encode)
        #expect(model.encodeFormat.operation(model.encodeDirection) == .base64Encode)
        model.encodeFormat = .html
        model.encodeDirection = .decode
        #expect(model.encodeFormat.operation(model.encodeDirection) == .htmlDecode)
    }

    /// D-89: the detection override starts inactive, and whether it is active
    /// is what drives the Detect control's disabled state. `nil` means "read
    /// whatever detection says", which is a different thing from any of the
    /// three ``ReadAs`` values and is why the property is Optional.
    @MainActor
    @Test
    func theReadAsOverrideStartsInactiveAndBecomesActiveWhenSet() {
        let model = AppModel()
        #expect(model.timestampsReadAs == nil)
        #expect(model.isReadAsOverridden == false)
        model.timestampsReadAs = .iso8601
        #expect(model.isReadAsOverridden)
        #expect(model.timestampsReadAs == .iso8601)
        model.timestampsReadAs = nil
        #expect(model.isReadAsOverridden == false, "clearing the override must return the surface to detection")
    }

    /// Phase 7 criterion 3 requires any persisted date-like value to be a
    /// `Double`, so the instant is stored as one. The property that makes that
    /// free is that the `Double` survives the write BIT-IDENTICALLY, which is
    /// total — not that a `Date` survives a trip through it, which 06-09
    /// measured to be FALSE. See
    /// ``theDateRoundTripResearchClaimedIsExactIsOffByOneUnitInTheLastPlace``.
    @MainActor
    @Test
    func theTimestampsInstantIsADoubleThatSurvivesTheWriteBitIdentically() {
        let model = AppModel()
        #expect(model.timestampsInstant == nil, "nothing parsed yet must not read as the epoch")
        let moment = Date()
        let interval = moment.timeIntervalSince1970
        model.timestampsInstant = interval
        guard let stored = model.timestampsInstant else {
            Issue.record("the instant did not survive the write")
            return
        }
        #expect(stored == interval)
        #expect(stored.bitPattern == interval.bitPattern, "the stored interval is not the same Double")
        #expect(Date(timeIntervalSince1970: stored) == Date(timeIntervalSince1970: interval), "the same Double must build the same instant")
        #expect(TimestampCodec.renderEpochSeconds(stored) == TimestampCodec.renderEpochSeconds(interval))
    }

    /// **06-RESEARCH.md is wrong here, and this pins it.** RESEARCH recorded
    /// `Date(timeIntervalSince1970: d.timeIntervalSince1970) == d` as an exact
    /// round trip, and this plan's own text repeated the claim. It is not
    /// exact: `Date` stores seconds since the 2001 reference date, so the trip
    /// adds 978 307 200 and subtracts it again, and in binary floating point
    /// that is a rounding operation. Measured on this tree, HALF of a 20 000
    /// sample population comes back unequal, always by exactly one unit in the
    /// last place — 1.1920928955078125e-07 s at 2026 magnitudes.
    ///
    /// This is why the model stores the `Double` as the source of truth and
    /// never a `Date`: with no round trip there is no rounding. The assertion
    /// is deliberately two-sided — the discrepancy must still be REAL (so a
    /// future OS that fixes it reports the change rather than drifting
    /// silently) and must still be bounded at one unit in the last place (so a
    /// regression that made it worse is caught).
    @Test
    func theDateRoundTripResearchClaimedIsExactIsOffByOneUnitInTheLastPlace() {
        var mismatches = 0
        var worstUnits = 0.0
        var sampled = 0
        for micros in 0 ..< 2000 {
            let reference = 812_345_678.123_456 + Double(micros) * 0.000_001
            let original = Date(timeIntervalSinceReferenceDate: reference)
            let returned = Date(timeIntervalSince1970: original.timeIntervalSince1970)
            sampled += 1
            guard returned != original else { continue }
            mismatches += 1
            let delta = abs(returned.timeIntervalSinceReferenceDate - reference)
            worstUnits = max(worstUnits, delta / reference.ulp)
        }
        #expect(sampled == 2000, "the sample population shrank")
        #expect(mismatches > 0, "the round trip is now exact — 06-RESEARCH's claim has become true; re-measure before trusting it")
        #expect(worstUnits <= 1.0, "the round-trip error grew beyond one unit in the last place")
    }

    @MainActor
    @Test
    func theTimeZoneSelectionDefaultsToTheDeviceZoneAndSurvivesAWrite() {
        let model = AppModel()
        #expect(model.timestampsTimeZone == TimeZone.current)
        guard let tokyo = TimeZone(identifier: "Asia/Tokyo") else {
            Issue.record("Asia/Tokyo is missing from the tz database")
            return
        }
        model.timestampsTimeZone = tokyo
        #expect(model.timestampsTimeZone == tokyo)
        #expect(model.timestampsTimeZone.identifier == "Asia/Tokyo")
    }

    /// Two models are separate storage. `AppModel` is constructed once by the
    /// root view as `@State private var model = AppModel()`; nothing about it
    /// is shared, static or global, and this is the assertion that would fail
    /// if a singleton were introduced later.
    @MainActor
    @Test
    func twoModelsShareNothing() {
        let one = AppModel()
        let other = AppModel()
        one.encode.input = "hello"
        one.timestampsReadAs = .unixEpoch
        #expect(other.encode.input.isEmpty)
        #expect(other.timestampsReadAs == nil)
    }
}
