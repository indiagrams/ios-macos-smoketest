// Tests for app/Shared/Engine/HTMLEntityCodec.swift — APP-03, both directions.
//
// Run via (macOS):
//   xcodebuild test -project app/App.xcodeproj -scheme App-macOS \
//     -configuration Debug -destination 'platform=macOS' \
//     -only-testing:AppMacOSTests/HTMLEntityTests \
//     CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
//
// Compiled into BOTH unit-test targets, so every number below is asserted on
// iOS and macOS from one source. `-only-testing:` naming an ABSENT suite exits
// 0 printing `** TEST SUCCEEDED **` having run zero tests (measured by 06-03),
// so a green from this file is only evidence when it carries a test count.
//
// WHAT THE COUNT ASSERTIONS ARE FOR
//
// The packed table loses records silently under the obvious ';'-delimited
// format, because three entity TARGETS are delimiter-shaped characters
// (`equals` U+003D, `semi` U+003B, `bne` U+003D U+20E5). Measured by 06-05 and
// re-measured by this plan: the broken format still compiles at exit 0 with no
// diagnostic. A COUNT ASSERTION is the only instrument that catches it, which
// is why 2125 is asserted here per half AND in sum — a union that has stopped
// drawing from one source looks identical to one that never did.
//
// Every iteration below is guarded by a non-empty assertion on its own
// collection first. A loop over an empty collection asserts nothing.

import Foundation
import Testing

/// Compile-time probe: this only type-checks if `T` is `Sendable`.
///
/// - Important: **This probe cannot fail for `[String: String]`** and is not
///   the APP-12 gate. `Dictionary` of `Sendable` elements is unconditionally
///   `Sendable`, so no edit to `HTMLEntityCodec` could make this stop
///   compiling. It is kept because the plan asks for it and because it
///   documents the requirement, but the control that actually fires is
///   `entity-lookup-must-not-be-mutable-global` in
///   `evidence/06-06-html-codec.txt`: turning `static let lookup` into a
///   `static var` is a hard error under `-strict-concurrency=complete`, which
///   is what makes the ABSENCE of `nonisolated(unsafe)` in the shipped file
///   mean something. 06-03 shipped a Sendable probe that was measurably
///   incapable of failing; this comment exists so this one is not mistaken for
///   a gate.
private func requireSendable(_: (some Sendable).Type) {}

/// Reading the lazily-parsed table from a `nonisolated` context, which is
/// where every keystroke will reach it from. A global that needed an actor
/// would not compile here.
private nonisolated func entityCountFromANonisolatedContext() -> Int {
    HTMLEntityCodec.lookup.count
}

/// See PositionTests for why there is no bare `@Suite` attribute.
struct HTMLEntityTests {
    // MARK: - The parsed table reaches runtime intact

    /// Nothing below iterates or indexes a table that might be empty without
    /// this having run first.
    @Test
    func theParsedTableIsNotEmpty() {
        #expect(HTMLEntityCodec.lookup.isEmpty == false)
        #expect(HTMLEntityCodec.recordCount > 0)
    }

    /// Each half's contribution, asserted ON ITS OWN before any sum.
    ///
    /// Two distinct expectations, deliberately. A parser that had stopped
    /// reading `HTMLEntityTableB.chunks` entirely would still satisfy a
    /// total-only assertion if the total were wrong in a compensating way, and
    /// would satisfy every canary below, all of which live in half A.
    @Test
    func eachTableHalfContributesRecordsOfItsOwn() {
        #expect(HTMLEntityTableA.recordCount > 0)
        #expect(HTMLEntityTableB.recordCount > 0)
        #expect(HTMLEntityTableA.recordCount == 1063)
        #expect(HTMLEntityTableB.recordCount == 1062)
    }

    /// The generated per-file counts sum to the number the generator asserts
    /// against the WHATWG source: 2231 references, 2125 with a trailing `;`,
    /// 106 legacy forms excluded by design.
    @Test
    func theTwoHalvesSumToTheGeneratedTotal() {
        #expect(HTMLEntityTableA.recordCount + HTMLEntityTableB.recordCount == 2125)
    }

    /// **The regression for the silent-loss defect.** The count the PARSER
    /// produces at runtime, against the count the GENERATOR wrote. These are
    /// two independent numbers and a packing or splitting fault moves one
    /// without the other.
    @Test
    func everyGeneratedRecordSurvivesParsing() {
        #expect(HTMLEntityCodec.recordCount == 2125)
        #expect(HTMLEntityCodec.recordCount == HTMLEntityTableA.recordCount + HTMLEntityTableB.recordCount)
    }

    // MARK: - The records a broken format loses

    /// The three entities whose TARGETS are delimiter-shaped, named
    /// individually. Under a ';'- or '='-delimited pack `equals` and `semi`
    /// vanish while `bne` survives BY ACCIDENT — `"="` followed by U+20E5 is a
    /// single grapheme cluster, so a `Character`-based split does not break
    /// inside it. A spot check of `bne` alone would report a broken table
    /// healthy, so all three are asserted.
    @Test
    func theThreeDelimiterShapedEntitiesSurvive() {
        #expect(HTMLEntityCodec.lookup["equals"] == "=")
        #expect(HTMLEntityCodec.lookup["semi"] == ";")
        #expect(HTMLEntityCodec.lookup["bne"] == "\u{3D}\u{20E5}")
        #expect(HTMLEntityCodec.lookup["bne"]?.unicodeScalars.count == 2)
        // ...and it is ONE Character, which is exactly why the naive split
        // keeps it. Measured, not assumed.
        #expect(HTMLEntityCodec.lookup["bne"]?.count == 1)
    }

    /// The two lowest target codepoints in the whole table. U+0009 is the
    /// reason U+0001 and U+0002 are provably safe delimiters: nothing in the
    /// data can collide with them.
    @Test
    func theTwoLowestCodepointEntitiesSurvive() {
        #expect(HTMLEntityCodec.lookup["Tab"] == "\u{9}")
        #expect(HTMLEntityCodec.lookup["NewLine"] == "\u{A}")
    }

    /// 93 references target more than one codepoint. A parser that kept only
    /// the first scalar of a field would pass every single-scalar assertion
    /// above.
    @Test
    func aMultiCodepointTargetSurvives() {
        #expect(HTMLEntityCodec.lookup["NotEqualTilde"]?.unicodeScalars.count == 2)
        #expect(HTMLEntityCodec.lookup["NotEqualTilde"] == "\u{2242}\u{338}")
    }

    /// 17 references target invisible or format characters. They are the ones
    /// a human reviewer cannot see go missing.
    @Test
    func anInvisibleCharacterTargetSurvives() {
        #expect(HTMLEntityCodec.lookup["ZeroWidthSpace"] == "\u{200B}")
        #expect(HTMLEntityCodec.lookup["zwnj"] == "\u{200C}")
    }

    /// The longest name in the table, which is where a chunk boundary or a
    /// line-continuation fault would show first.
    ///
    /// - Note: **31 characters, measured on this tree** — not the 32 this
    ///   plan's prose says. RESEARCH's figure of 33 is the length of
    ///   `&CounterClockwiseContourIntegral;`, which counts BOTH the leading
    ///   `&` and the trailing `;`. The key is the bare name.
    @Test
    func theLongestNameIsPresent() {
        #expect(HTMLEntityCodec.lookup["CounterClockwiseContourIntegral"] != nil)
        #expect("CounterClockwiseContourIntegral".count == 31)
        let longest = HTMLEntityCodec.lookup.keys.max { $0.count < $1.count }
        #expect(longest?.count == 31)
    }

    // MARK: - The 106 legacy forms are absent, and that is user-visible

    /// The legacy semicolon-optional references are excluded from the table by
    /// the generator. Asserted through the CONSEQUENCE rather than through a
    /// missing key: `lookup["copy"]` exists (`&copy;` is a legitimate
    /// semicolon-terminated reference) and it is the *unterminated spelling*
    /// that must be refused.
    ///
    /// `encode.error.html.unterminated` reads "Unterminated HTML entity: the
    /// '&' at position %lld has no ';'." A design that reports unterminated
    /// entities as an error cannot also silently accept 106 of them.
    @Test
    func noLegacySemicolonlessFormIsAccepted() {
        #expect(HTMLEntityCodec.lookup["copy"] == "\u{A9}")
        #expect(HTMLEntityCodec.decode("&copy").failure == .unterminatedEntity(position: 1))
        #expect(HTMLEntityCodec.decode("&amp").failure == .unterminatedEntity(position: 1))
        #expect(HTMLEntityCodec.decode("&lt").failure == .unterminatedEntity(position: 1))
        #expect(HTMLEntityCodec.decode("&nbsp").failure == .unterminatedEntity(position: 1))
    }

    /// `NSAttributedString` decodes `"&notit;"` to `"\u{AC}it;"` — legacy
    /// semicolon-less matching of `&not` inside a longer name, measured in
    /// 06-RESEARCH.md. This codec names it instead.
    @Test
    func theLegacyPrefixMatchThatFoundationPerformsIsRefused() {
        #expect(HTMLEntityCodec.lookup["notit"] == nil)
        #expect(HTMLEntityCodec.lookup["not"] == "\u{AC}")
        #expect(HTMLEntityCodec.decode("&notit;").failure == .unknownEntity("&notit;", position: 1))
    }

    // MARK: - APP-12: usable from a nonisolated context

    /// See `requireSendable`'s doc comment for why this is documentation
    /// rather than a gate, and which control is the gate.
    @Test
    func theTableIsSendableAndReachableWithoutAnActor() {
        requireSendable([String: String].self)
        #expect(entityCountFromANonisolatedContext() == 2125)
    }
}
