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
///   is what makes the ABSENCE of the unsafe-isolation annotation in the
///   shipped file mean something. 06-03 shipped a Sendable probe that was
///   measurably incapable of failing; this comment exists so this one is not
///   mistaken for a gate.
///   Its spelling is deliberately NOT written here: 06-17 measured this line
///   as the ONLY match in all of `app/` for the grep counting the two hatches
///   APP-12 forbids, so the file explaining the ban was the sole thing keeping
///   that count off zero — 06-09's fix to `PercentCodec.swift`, same reason.
///   The standing gate is `test/app_offline_test.rb`.
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

    // MARK: - Encoding: exactly five characters, and the ordering bug

    /// Markup is ESCAPED, not stripped. The platform decoder measured
    /// `"<b>bold</b>"` -> `"bold"`; this is that measurement as a regression.
    @Test
    func markupIsEscapedRatherThanStripped() {
        #expect(HTMLEntityCodec.encode("<b>x</b>") == "&lt;b&gt;x&lt;/b&gt;")
        #expect(HTMLEntityCodec.encode("<b>bold</b>") == "&lt;b&gt;bold&lt;/b&gt;")
    }

    /// **The ordering bug, asserted directly.** `&` must be escaped first, or
    /// the `&` of an escape sequence gets escaped again by a later pass and
    /// `"&lt;"` comes back as `"&lt;"` instead of `"&amp;lt;"`.
    ///
    /// - Important: **The first four expectations below do NOT discriminate
    ///   the ordering**, and that was measured rather than assumed. Driving
    ///   `control=entity-ampersand-ordering` — the chained
    ///   `replacingOccurrences` shape with `&` escaped LAST — left this test
    ///   GREEN: under that bug `encode("&lt;")` is still `"&amp;lt;"`, because
    ///   the input has no `<` to escape in the first place. The plan named
    ///   that line as its ordering assertion; it is not one. The four
    ///   expectations that DO fire are the last four here, where the bug
    ///   double-escapes an ampersand the encoder itself produced.
    @Test
    func theAmpersandIsEscapedFirstSoAnEscapeIsEscapedAgain() {
        #expect(HTMLEntityCodec.encode("a & b") == "a &amp; b")
        #expect(HTMLEntityCodec.encode("&lt;") == "&amp;lt;")
        #expect(HTMLEntityCodec.encode("&amp;") == "&amp;amp;")
        #expect(HTMLEntityCodec.encode("&&") == "&amp;&amp;")
        // The discriminating four: each replacement contains an `&` that must
        // NOT be escaped again.
        #expect(HTMLEntityCodec.encode("<") == "&lt;")
        #expect(HTMLEntityCodec.encode(">") == "&gt;")
        #expect(HTMLEntityCodec.encode("\"") == "&quot;")
        #expect(HTMLEntityCodec.encode("'") == "&#39;")
    }

    /// The apostrophe is `&#39;`, NOT `&apos;`. Stated in the codec's doc
    /// comment and asserted here; plan 06-12's UI strings must match.
    @Test
    func theApostropheIsTheNumericFormAndTheQuoteIsNamed() {
        #expect(HTMLEntityCodec.encode("\"'") == "&quot;&#39;")
        #expect(HTMLEntityCodec.decode("&#39;").success == "'")
        // &apos; still DECODES — it is a legitimate table entry. It is simply
        // not what this encoder emits.
        #expect(HTMLEntityCodec.decode("&apos;").success == "'")
    }

    /// Whitespace survives. The platform decoder measured `"line1\nline2"` ->
    /// `"line1 line2"` and `"  spaced  "` -> `"spaced"`.
    @Test
    func whitespaceSurvivesEncoding() {
        #expect(HTMLEntityCodec.encode("line1\nline2") == "line1\nline2")
        #expect(HTMLEntityCodec.encode("  spaced  ") == "  spaced  ")
        #expect(HTMLEntityCodec.encode("\t\ttabs\t") == "\t\ttabs\t")
    }

    /// Non-ASCII is left alone. Encoding all 2125 named references would turn
    /// `café` into `caf&eacute;`, which is the choice A1 rejected.
    @Test
    func nonASCIIIsLeftAlone() {
        #expect(HTMLEntityCodec.encode("café") == "café")
        #expect(HTMLEntityCodec.encode("日本語") == "日本語")
        #expect(HTMLEntityCodec.encode("\u{A0}") == "\u{A0}")
    }

    /// **The population assertion for A1.** Every ASCII scalar is put through
    /// `encode` and the set that CHANGES is compared against the stated five.
    /// A total-only count would pass on the wrong five.
    @Test
    func exactlyFiveCharactersAreEscapedAndNoOthers() {
        var changed = Set<Unicode.Scalar>()
        for value in UInt32(0) ... UInt32(0x7F) {
            guard let scalar = Unicode.Scalar(value) else { continue }
            let input = String(String.UnicodeScalarView([scalar]))
            if HTMLEntityCodec.encode(input) != input {
                changed.insert(scalar)
            }
        }
        #expect(changed == ["&", "<", ">", "\"", "'"])
        #expect(changed.count == 5)
    }

    // MARK: - Decoding: named and numeric references

    /// Named references, including the two the encoder emits.
    @Test
    func namedReferencesDecode() {
        #expect(HTMLEntityCodec.decode("&amp;").success == "&")
        #expect(HTMLEntityCodec.decode("&lt;b&gt;").success == "<b>")
        #expect(HTMLEntityCodec.decode("&quot;").success == "\"")
        #expect(HTMLEntityCodec.decode("&Tab;").success == "\u{9}")
        #expect(HTMLEntityCodec.decode("&NotEqualTilde;").success == "\u{2242}\u{338}")
    }

    /// Numeric character references, decimal and hexadecimal. The generated
    /// table does not carry these and the scanner must.
    @Test
    func numericReferencesDecode() {
        #expect(HTMLEntityCodec.decode("&#65;").success == "A")
        #expect(HTMLEntityCodec.decode("&#x41;").success == "A")
        #expect(HTMLEntityCodec.decode("&#X41;").success == "A")
        #expect(HTMLEntityCodec.decode("&#233;").success == "é")
        #expect(HTMLEntityCodec.decode("&#x1F600;").success == "\u{1F600}")
        #expect(HTMLEntityCodec.decode("&#0;").success == "\u{0}")
    }

    /// **The measurement this codec exists to not reproduce.** The platform
    /// decoder turns `"&#999999999;"` into U+FFFD with no error at all, so the
    /// user is shown a replacement character where their text was and never
    /// told. Here it is a named failure with a position (T-06-25).
    @Test
    func anOutOfRangeNumericReferenceIsNamedRatherThanRepaired() {
        let failure = HTMLEntityCodec.decode("&#999999999;").failure
        #expect(failure == .unknownEntity("&#999999999;", position: 1))
        #expect(HTMLEntityCodec.decode("&#999999999;").success == nil)
        // ...and specifically NOT the platform's answer.
        #expect(HTMLEntityCodec.decode("&#999999999;").success != "\u{FFFD}")
    }

    /// The other numeric references that name nothing: a surrogate, an empty
    /// digit run, and a digit run with a stray letter. None of these may trap
    /// — `Unicode.Scalar(_:)` returns nil for a surrogate and a force-unwrap
    /// would kill the host process rather than fail a test.
    @Test
    func malformedNumericReferencesAreNamedAndNeverTrap() {
        #expect(HTMLEntityCodec.decode("&#xD800;").failure == .unknownEntity("&#xD800;", position: 1))
        #expect(HTMLEntityCodec.decode("&#x110000;").failure == .unknownEntity("&#x110000;", position: 1))
        #expect(HTMLEntityCodec.decode("&#;").failure == .unknownEntity("&#;", position: 1))
        #expect(HTMLEntityCodec.decode("&#x;").failure == .unknownEntity("&#x;", position: 1))
        #expect(HTMLEntityCodec.decode("&#12a;").failure == .unknownEntity("&#12a;", position: 1))
        #expect(HTMLEntityCodec.decode("&#99999999999999999999999;").success == nil)
    }

    // MARK: - The two named failures, and where they point

    /// `.unknownEntity`'s payload is the entity AS TYPED — `&` and `;`
    /// included — because that is what `'%@'` renders in
    /// `encode.error.html.unknown`.
    @Test
    func anUnknownEntityCarriesTheTextTheUserTyped() {
        #expect(HTMLEntityCodec.classify("&bogus;") == .unknownEntity("&bogus;", position: 1))
        #expect(HTMLEntityCodec.classify("ok &nope; ok") == .unknownEntity("&nope;", position: 4))
    }

    /// `.unterminatedEntity` names the position of the `&`, 1-based, in
    /// Characters. Three terminators, one rule: another `&`, whitespace, or
    /// the end of the input.
    @Test
    func anUnterminatedEntityNamesItsAmpersand() {
        #expect(HTMLEntityCodec.classify("a &copy") == .unterminatedEntity(position: 3))
        #expect(HTMLEntityCodec.classify("100% & more") == .unterminatedEntity(position: 6))
        #expect(HTMLEntityCodec.classify("&") == .unterminatedEntity(position: 1))
        #expect(HTMLEntityCodec.classify("&amp&amp;") == .unterminatedEntity(position: 1))
        #expect(HTMLEntityCodec.classify("x&\ny") == .unterminatedEntity(position: 2))
    }

    /// Positions are CHARACTER offsets, so non-ASCII text before the fault
    /// does not shift them. This is the assertion that would fail if the
    /// scan's UTF-8 offset arithmetic were wrong.
    @Test
    func positionsAreCharacterOffsetsEvenAfterNonASCII() {
        #expect(HTMLEntityCodec.classify("héllo &bogus;") == .unknownEntity("&bogus;", position: 7))
        #expect(HTMLEntityCodec.classify("日本 &bogus;") == .unknownEntity("&bogus;", position: 4))
        // Three Characters, 27 UTF-8 bytes (TestVectors.positionCases).
        #expect(HTMLEntityCodec.classify("a👨\u{200D}👩\u{200D}👧\u{200D}👦b &x") == .unterminatedEntity(position: 5))
    }

    /// Text with no `&` in it is not an entity problem.
    @Test
    func plainTextClassifiesAsValidAndDecodesToItself() {
        #expect(HTMLEntityCodec.classify("plain text") == nil)
        #expect(HTMLEntityCodec.decode("plain text").success == "plain text")
        #expect(HTMLEntityCodec.classify("") == nil)
        #expect(HTMLEntityCodec.decode("").success == "")
    }

    // MARK: - The round trip

    /// The sample set is populated. A sweep over an emptied list runs zero
    /// cases and reports success.
    @Test
    func theRoundTripSampleSetIsPopulated() {
        #expect(TestVectors.htmlRoundTripSamples.count >= 10)
    }

    /// `decode(encode(x)) == .success(x)`, which is the property the
    /// five-character escape set exists to buy for a chaining pipeline.
    @Test(arguments: TestVectors.htmlRoundTripSamples)
    func encodingThenDecodingReturnsTheInput(_ input: String) {
        let encoded = HTMLEntityCodec.encode(input)
        #expect(HTMLEntityCodec.classify(encoded) == nil,
                "encode produced text its own classifier rejects: \(String(reflecting: encoded))")
        #expect(HTMLEntityCodec.decode(encoded).success == input,
                "round trip lost \(String(reflecting: input))")
    }
}
