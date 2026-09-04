// Tests for app/Shared/Model/ConversionFailure.swift — the one error type
// every conversion in this app returns.
//
// Run via (macOS):
//   xcodebuild test -project app/App.xcodeproj -scheme App-macOS \
//     -configuration Debug -destination 'platform=macOS' \
//     -only-testing:AppMacOSTests/ConversionFailureTests \
//     CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
//
// Two of the assertions here are COMPILE-TIME, not runtime, and one of the
// two is weaker than it looks. Both were driven RED before being trusted;
// the transcripts are in 06-03-base64.txt.
//
//   1. `localizationKeys(for:)` and `position(of:)` switch with NO `default:`
//      branch, so a tenth case added without a user-facing string breaks the
//      build rather than silently rendering nothing. D-85 says every error
//      names a reason and a position; a case with no string is an error the
//      user cannot read. OBSERVED RED (control=conversion-failure-exhaustiveness-red,
//      exit 65, "switch must be exhaustive" from both switches).
//
//   2. `requireSendable(ConversionFailure.self)` is BELT AND BRACES, NOT THE
//      GATE, and saying otherwise would be a control that has never been
//      executed. MEASURED 2026-09-04 on this target (Swift 6.0,
//      SWIFT_STRICT_CONCURRENCY=complete, warnings NOT errors):
//
//        - Adding a non-Sendable payload WITH the explicit `Sendable` in the
//          conformance list is an ERROR at the case declaration and the build
//          fails (control=sendable-conformance-red, exit 65).
//        - Adding the same payload with `Sendable` REMOVED from the
//          conformance list compiles and this suite PASSES
//          (control=sendable-probe-alone-is-not-a-gate, exit 0, 7 tests). The
//          compiler still grants the internal enum an implicit `Sendable`
//          conformance and downgrades the violation to a warning, so the
//          probe below has nothing to object to.
//
//      The load-bearing part is therefore the word `Sendable` in
//      ConversionFailure's conformance list, not this function. DO NOT DELETE
//      IT as redundant — deleting it converts an error into a warning and this
//      file will not notice.
//
// POPULATION NOTE. The key set below is enumerated from 06-UI-SPEC.md
// §"Full string inventory" — the `encode.error.*` table (7 rows) and the
// `timestamps.error.*` table (3 rows). That is TEN keys.
// 06-03-PLAN.md's task 1 `<behavior>` says "the UI-SPEC's twelve error
// strings"; the UI-SPEC contains ten. Counted 2026-09-04 with
//   grep -o '`[a-zA-Z0-9.]*[Ee]rror[a-zA-Z0-9.]*`' 06-UI-SPEC.md | sort -u
// which returns exactly the ten spelled below. The plan literal is wrong and
// is corrected here rather than in the plan (plans are not edited by the
// executor); the correction is recorded in 06-03-base64.txt and in the
// summary. Each of the four families is asserted by its OWN count before the
// total, so a table that gains a row in one family and loses one in another
// cannot pass on the total alone.

import Testing

/// Compile-time probe: this only type-checks if `T` is `Sendable`.
///
/// Applied to `ConversionFailure` below. It catches an outright LOSS of the
/// conformance — an `@MainActor`-isolated or explicitly `~Sendable` type — but
/// see the file header for what it measurably does NOT catch: a non-Sendable
/// payload added while the explicit conformance is also removed still leaves
/// an implicit conformance in place, and this probe stays green.
private func requireSendable(_: (some Sendable).Type) {}

/// See PositionTests for why there is no bare `@Suite` attribute.
struct ConversionFailureTests {
    /// The ten error strings in 06-UI-SPEC.md, spelled out by hand so a typo
    /// in the mapping is visible rather than tautological.
    private static let base64Keys: Set<String> = [
        "encode.error.base64.character",
        "encode.error.base64.length",
        "encode.error.base64.padding"
    ]

    private static let urlKeys: Set<String> = [
        "encode.error.url.escape",
        "encode.error.url.utf8"
    ]

    private static let htmlKeys: Set<String> = [
        "encode.error.html.unknown",
        "encode.error.html.unterminated"
    ]

    private static let timestampKeys: Set<String> = [
        "timestamps.error.notDigit",
        "timestamps.error.iso8601",
        "timestamps.error.range"
    ]

    private static var allKeys: Set<String> {
        base64Keys.union(urlKeys).union(htmlKeys).union(timestampKeys)
    }

    /// The `Localizable.xcstrings` keys a case can render as.
    ///
    /// NO `default:` BRANCH, on purpose — see the file header. A case can map
    /// to more than one key: `.unexpectedCharacter` is the Base64 alphabet
    /// error AND the epoch non-digit error, which is why this returns a Set
    /// and why the two counts (9 cases, 10 keys) legitimately differ.
    ///
    /// The mapping itself lives in the VIEW layer (plan 06-11). This copy
    /// exists only to make the case set's exhaustiveness assertable from the
    /// engine's own test target, which must not import SwiftUI.
    private static func localizationKeys(for failure: ConversionFailure) -> Set<String> {
        switch failure {
        case .unexpectedCharacter:
            ["encode.error.base64.character", "timestamps.error.notDigit"]
        case .badLength:
            ["encode.error.base64.length"]
        case .paddingBeforeEnd:
            ["encode.error.base64.padding"]
        case .invalidEscape:
            ["encode.error.url.escape"]
        case .invalidUTF8:
            ["encode.error.url.utf8"]
        case .unknownEntity:
            ["encode.error.html.unknown"]
        case .unterminatedEntity:
            ["encode.error.html.unterminated"]
        case .expectedCharacter:
            ["timestamps.error.iso8601"]
        case .outOfRange:
            ["timestamps.error.range"]
        }
    }

    /// The position a case carries, or `nil` for the two that carry none.
    ///
    /// Also switched with NO `default:`, so a new case must state which it is.
    private static func position(of failure: ConversionFailure) -> Int? {
        switch failure {
        case let .unexpectedCharacter(_, position): position
        case .badLength: nil
        case let .paddingBeforeEnd(position): position
        case let .invalidEscape(position): position
        case let .invalidUTF8(position): position
        case let .unknownEntity(_, position): position
        case let .unterminatedEntity(position): position
        case let .expectedCharacter(_, position): position
        case .outOfRange: nil
        }
    }

    /// One value of every case, in declaration order. The list is what the
    /// loops below iterate; `everyCaseIsRepresented` guards it against
    /// shrinking, because a loop over a short list asserts less without
    /// saying so.
    private static let oneOfEachCase: [ConversionFailure] = [
        .unexpectedCharacter("!", position: 5),
        .badLength(7),
        .paddingBeforeEnd(position: 3),
        .invalidEscape(position: 2),
        .invalidUTF8(position: 4),
        .unknownEntity("&nope;", position: 3),
        .unterminatedEntity(position: 1),
        .expectedCharacter("-", position: 5),
        .outOfRange("99999999999999999999")
    ]

    /// `ConversionFailure` is `Sendable` with no `@unchecked`.
    ///
    /// The assertion is the CALL, which only compiles under the constraint.
    /// The `#expect(true)` is not the test; it exists so the test has a body
    /// a runner can report. Read the file header for this probe's measured
    /// limits before relying on it.
    @Test
    func conversionFailureIsSendable() {
        requireSendable(ConversionFailure.self)
        #expect(Bool(true))
    }

    /// A value of the type survives a crossing of an isolation boundary.
    ///
    /// This is the runtime half of the same claim, and unlike the probe above
    /// it exercises the conformance rather than merely naming it: sending the
    /// value into a `@Sendable` closure on another executor and reading it
    /// back requires `Sendable` at the call site.
    @Test
    func aFailureCrossesAnIsolationBoundaryIntact() async {
        let failure = ConversionFailure.unexpectedCharacter("é", position: 2)
        let echoed = await Task.detached { failure }.value
        #expect(echoed == failure)
    }

    /// Nine cases, one sample each. A tenth case added without a sample here
    /// fails this, and a tenth case added without a string fails to compile.
    @Test
    func everyCaseIsRepresented() {
        #expect(Self.oneOfEachCase.count == 9)
        let keySets = Self.oneOfEachCase.map { Self.localizationKeys(for: $0) }
        #expect(keySets.count == 9, "sample list is short; the loops below would assert less")
        var union: Set<String> = []
        for keys in keySets {
            #expect(!keys.isEmpty, "a case maps to no user-facing string")
            union.formUnion(keys)
        }
        #expect(union == Self.allKeys)
    }

    /// Each family's contribution is asserted on its own BEFORE the total.
    ///
    /// A total of 10 reached by four Base64 keys and two timestamp keys is a
    /// different inventory with the same total; a total-only assertion cannot
    /// tell the two apart. `.continue-here.md`: a correct check pointed at the
    /// wrong population.
    @Test
    func eachStringFamilyContributesItsOwnKeys() {
        let union = Self.oneOfEachCase.reduce(into: Set<String>()) { $0.formUnion(Self.localizationKeys(for: $1)) }
        #expect(union.intersection(Self.base64Keys) == Self.base64Keys, "a Base64 error string has no case")
        #expect(union.intersection(Self.urlKeys) == Self.urlKeys, "a percent-encoding error string has no case")
        #expect(union.intersection(Self.htmlKeys) == Self.htmlKeys, "an HTML entity error string has no case")
        #expect(union.intersection(Self.timestampKeys) == Self.timestampKeys, "a timestamp error string has no case")
        #expect(Self.base64Keys.count == 3)
        #expect(Self.urlKeys.count == 2)
        #expect(Self.htmlKeys.count == 2)
        #expect(Self.timestampKeys.count == 3)
        #expect(union.count == 10, "06-UI-SPEC.md has TEN error strings, not the twelve 06-03-PLAN.md cites")
    }

    /// Seven of the nine cases carry a position; the two that do not carry
    /// the payload the UI-SPEC's string actually interpolates.
    ///
    /// `badLength(Int)` renders "the length must be a multiple of 4, and it
    /// is %lld" — the length, not a position. `outOfRange(String)` renders
    /// "%@ is outside the dates this app can show" — the value.
    @Test
    func everyCaseCarriesAPositionExceptTheTwoThatCarryAValue() {
        #expect(Self.oneOfEachCase.count == 9, "sample list is short; the loop below would assert less")
        var withPosition = 0
        for failure in Self.oneOfEachCase {
            // No `default:` here either. The two value-carrying cases are named
            // and the seven position-carrying ones are named; a tenth case
            // cannot slip into a catch-all and be silently counted as one or
            // the other.
            switch failure {
            case .badLength, .outOfRange:
                #expect(Self.position(of: failure) == nil, "\(failure) should carry a value, not a position")
            case .unexpectedCharacter, .paddingBeforeEnd, .invalidEscape, .invalidUTF8,
                 .unknownEntity, .unterminatedEntity, .expectedCharacter:
                #expect(Self.position(of: failure) != nil, "\(failure) carries no position")
                withPosition += 1
            }
        }
        #expect(withPosition == 7, "7 of 9 cases carry a position, not \(withPosition)")
    }

    /// `Equatable` means a test can assert the EXACT expected failure —
    /// reason and position together — rather than "some error was returned".
    /// That is what makes the Base64 corpus assertions meaningful.
    @Test
    func failuresCompareOnReasonAndPositionTogether() {
        #expect(ConversionFailure.unexpectedCharacter("!", position: 5) == .unexpectedCharacter("!", position: 5))
        #expect(ConversionFailure.unexpectedCharacter("!", position: 5) != .unexpectedCharacter("!", position: 6))
        #expect(ConversionFailure.unexpectedCharacter("!", position: 5) != .unexpectedCharacter("?", position: 5))
        #expect(ConversionFailure.paddingBeforeEnd(position: 3) != .invalidEscape(position: 3))
        #expect(ConversionFailure.badLength(7) != .badLength(9))
        #expect(ConversionFailure.outOfRange("1") != .outOfRange("2"))
    }

    /// The reported Character is a GRAPHEME, not a byte — the same unit
    /// Position.swift reports. A case that compared bytes would make
    /// "unexpected character 'Ã'" possible for an input containing 'é'.
    @Test
    func theReportedCharacterIsAGrapheme() {
        let failure = ConversionFailure.unexpectedCharacter("é", position: 2)
        #expect(failure == .unexpectedCharacter("é", position: 2))
        #expect(failure != .unexpectedCharacter("e", position: 2))
    }

    /// `ConversionFailure` is an `Error`, so a caller that wants `throws`
    /// still can — the engine simply does not, because a `throws` convert
    /// has no way to express "the classifier found nothing wrong and
    /// Foundation still said no".
    @Test
    func conversionFailureIsAnError() {
        let failure: any Error = ConversionFailure.badLength(7)
        #expect(failure as? ConversionFailure == .badLength(7))
    }
}
