// Base64Tests, continued — the decode failure that named the wrong codec and
// pointed at the wrong string (CR-03, plan 06-20, GAP-06-02).
//
// Same suite as Base64Tests.swift, so `-only-testing:AppMacOSTests/Base64Tests`
// runs both halves. A second FILE because `swiftlint --strict` enforces
// file_length (400) and Base64Tests.swift is at it; an `extension` keeps the
// suite whole rather than minting a second suite name a `-only-testing:`
// invocation could silently miss.
//
// WHAT WAS WRONG, MEASURED BEFORE IT WAS FIXED
//
// `Base64Codec.decode` returned `.invalidUTF8`, which `failureStringKey` maps
// unconditionally to `encode.error.url.utf8` — a PERCENT-ENCODING sentence,
// rendered on a Base64 card. And the position it carried was
// `invalidOffset + 1`, a byte offset into the DECODED OUTPUT, while
// `Position.swift` states there is exactly one definition of position in this
// app and it is a 1-based Character offset into the INPUT. Measured on this
// tree at 929ba9c by a `swiftc` harness over the engine sources:
//
//   decode("YWJj/w==") -> invalidUTF8(position: 4)  key=encode.error.url.utf8
//   decode("//8=")     -> invalidUTF8(position: 1)  key=encode.error.url.utf8
//   decode("4A==")     -> invalidUTF8(position: 1)  key=encode.error.url.utf8
//   decode("YWJjZGX/") -> invalidUTF8(position: 6)  key=encode.error.url.utf8
//
// Character 4 of `"YWJj/w=="` is `j` — a perfectly valid Base64 character, in
// the quantum BEFORE the one that produced the bad byte. Character 6 of
// `"YWJjZGX/"` is `G`, likewise. The user was pointed at the wrong place with
// an authoritative-sounding number, in a sentence naming a codec they were not
// using.
//
// WHERE THE NEW POSITION COMES FROM
//
// Base64 is a 4:3 code, so output byte `i` comes from input characters
// `4*(i/3) … 4*(i/3)+3`. The reported position is the FIRST character of that
// quantum, resolved through `characterPosition(utf8Offset:in:)` so it goes
// through the app's one definition rather than around it. The input is pure
// ASCII by the time this runs — the classifier is the authority and has
// already refused everything outside the alphabet — so byte and Character
// offsets coincide there, and the function is used anyway because the DEFINITION
// is what must not fork, not the arithmetic.

import Foundation
import Testing

extension Base64Tests {
    /// One measured input, the position its failure must report, and the
    /// input character that position must land on.
    ///
    /// A `struct` rather than a three-member tuple: `swiftlint --strict`
    /// enforces `large_tuple` at 2 on this repo's config, and the three fields
    /// are the whole point of the row — the position assertion is only worth
    /// anything next to the character it is claimed to name.
    struct NotTextRow: Sendable {
        let input: String
        let position: Int
        let character: Character
    }

    /// The four inputs CR-03 measured, with the quantum each bad byte came
    /// from and the character that quantum starts at.
    static let notTextRows: [NotTextRow] = [
        NotTextRow(input: "YWJj/w==", position: 5, character: "/"),
        NotTextRow(input: "//8=", position: 1, character: "/"),
        NotTextRow(input: "4A==", position: 1, character: "4"),
        NotTextRow(input: "YWJjZGX/", position: 5, character: "Z")
    ]

    // MARK: - CR-03 (a): the sentence names Base64

    /// A Base64 decode failure renders from a BASE64 key, not from the
    /// percent-encoding one.
    ///
    /// D-85 requires every error to name a reason; naming the wrong codec is
    /// naming the wrong reason. Asserted through `failureStringKey` rather
    /// than by grepping `FailureText.swift`, because the mapping is what ships
    /// and the source is only how it is spelled.
    @Test
    func aBase64DecodeFailureNamesBase64AndNotPercentEncoding() {
        for row in Self.notTextRows {
            let failure = Base64Codec.decode(row.input).failure
            #expect(failure != nil, "\(row.input) decodes to bytes that are not text")
            guard let failure else { continue }
            #expect(failureStringKey(failure, in: .text) == "encode.error.base64.utf8",
                    "\(row.input) must not render the percent-encoding sentence encode.error.url.utf8")
        }
    }

    /// The percent path keeps the percent sentence — the fix separates the two
    /// families, it does not swap them.
    ///
    /// `%A9` is the byte `PercentCodec` maps back through `scan.origins` to its
    /// `%` in the input, which is what made the percent side's position right
    /// while the Base64 side's was wrong.
    @Test
    func thePercentPathStillNamesPercentEncoding() {
        let failure = PercentCodec.decode("%A9").failure
        #expect(failure == .invalidUTF8(position: 1))
        guard let failure else { return }
        #expect(failureStringKey(failure, in: .text) == "encode.error.url.utf8")
    }

    // MARK: - CR-03 (b): the position is in the input

    /// The reported position is a 1-based Character offset into the INPUT, and
    /// the character it lands on is the first of the quantum that produced the
    /// bad byte.
    ///
    /// The second expectation is the one that would have caught the original
    /// defect on its own: it reads the input at the reported position and
    /// compares it to the character that must be there. A position assertion
    /// that only checks a number cannot tell 4 from 5.
    @Test
    func theReportedPositionIsACharacterOffsetIntoTheInput() {
        for row in Self.notTextRows {
            let failure = Base64Codec.decode(row.input).failure
            #expect(failure == .decodedBytesAreNotUTF8(position: row.position), "\(row.input)")
            guard case let .decodedBytesAreNotUTF8(position)? = failure else { continue }
            let characters = Array(row.input)
            #expect(position >= 1 && position <= characters.count,
                    "\(row.input): position \(position) is inside the input the user typed")
            guard position >= 1, position <= characters.count else { continue }
            #expect(characters[position - 1] == row.character,
                    "\(row.input): character \(position) is '\(characters[position - 1])', expected '\(row.character)'")
        }
    }

    /// Every reported position starts a quantum, so it is always one of
    /// 1, 5, 9, … — the property the 4:3 arithmetic guarantees, asserted over
    /// a swept population rather than only over the four measured rows.
    ///
    /// The sweep asserts a floor on how many inputs actually FAILED before
    /// asserting anything about them: a property over an empty set is
    /// vacuously true, which is the control-that-cannot-fire shape this phase
    /// has met eight times.
    @Test
    func everyReportedPositionStartsAQuantum() {
        var generator = SeededGenerator(seed: 0x0620_0003)
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
        var notText = 0
        for _ in 0 ..< 4000 {
            let quanta = 1 + Int(generator.next() % 6)
            let input = generator.randomString(from: alphabet, maxLength: 0) + String((0 ..< quanta * 4).map { _ in
                alphabet[Int(generator.next() % UInt64(alphabet.count))]
            })
            guard case let .decodedBytesAreNotUTF8(position)? = Base64Codec.decode(input).failure else { continue }
            notText += 1
            #expect(position % 4 == 1, "\(input): position \(position) must start a quantum")
            #expect(position <= input.count, "\(input): position \(position) is inside the input")
        }
        #expect(notText >= 100, "the sweep must actually reach the not-text path; it reached it \(notText) times")
    }

    // MARK: - Moved here 2026-09-05 (plan 06-20) from Base64Tests.swift

    // Both tests below asserted the OLD case and the OLD positions, so both
    // had to be amended by CR-03; they were moved into this file at the same
    // time because rewriting them in place put Base64Tests.swift at 415 lines
    // and `swiftlint --strict` enforces file_length (400). Same suite, so
    // `-only-testing:AppMacOSTests/Base64Tests` still runs them.

    /// Valid Base64 whose bytes are not text fails with a named reason and a
    /// position IN THE INPUT — not a crash, and not mojibake.
    ///
    /// - Important: **AMENDED 2026-09-05 (plan 06-20, CR-03).** These three
    ///   expectations previously read `.invalidUTF8(position: 4 / 2 / 1)` —
    ///   the percent-encoding case, carrying a byte offset into the DECODED
    ///   OUTPUT. Both halves were wrong and this test asserted them. The case
    ///   is now `.decodedBytesAreNotUTF8` and the position is a 1-based
    ///   Character offset into the input, per `Position.swift`. The numbers
    ///   below are DERIVED from that definition (`4 * (i / 3) + 1`, the start
    ///   of the quantum that produced output byte `i`) and then confirmed by
    ///   execution, not read off a run and written down.
    @Test
    func decodeOfBytesThatAreNotTextFailsWithAPosition() {
        // 0xFF is never a valid UTF-8 lead byte. "aGkA//8=" is "hi\0" followed
        // by 0xFF 0xFF, so the first invalid byte is output byte 3 (0-based),
        // which came from the second quantum — input characters 5-8, "//8=".
        let encoded = Data([0x68, 0x69, 0x00, 0xFF, 0xFF]).base64EncodedString()
        #expect(encoded == "aGkA//8=")
        #expect(Base64Codec.classify(encoded) == nil, "the fixture must be valid Base64 for this test to mean anything")
        #expect(Base64Codec.decode(encoded) == .failure(.decodedBytesAreNotUTF8(position: 5)))

        // A truncated multi-byte sequence: 0xC3 with nothing after it. One
        // quantum, so the answer is its first character whichever byte failed.
        let truncated = Data([0x61, 0xC3]).base64EncodedString()
        #expect(Base64Codec.decode(truncated) == .failure(.decodedBytesAreNotUTF8(position: 1)))

        // A lone continuation byte at the very start.
        let orphan = Data([0x80]).base64EncodedString()
        #expect(Base64Codec.decode(orphan) == .failure(.decodedBytesAreNotUTF8(position: 1)))
    }

    /// The one byte the deployment floor silently repairs is still reported as
    /// invalid, with a position — on every runtime.
    ///
    /// MEASURED on iOS 17.5: `String(bytes: [0xA9], encoding: .utf8)` is
    /// `Optional("\u{FFFD}")`, and `[0x61, 0xA9, 0x62]` is `"a\u{FFFD}b"`. A
    /// decoder that took Foundation's word for it would show the user a
    /// replacement character where their byte was and call it success — the
    /// "wrong answer" half of criterion 1, on the oldest OS this app supports
    /// and nowhere else. That is the second reason the scan exists; the first
    /// is that D-85 needs a position.
    @Test
    func theByteTheDeploymentFloorRepairsIsStillReportedInvalid() {
        let single = Data([0xA9]).base64EncodedString()
        #expect(Base64Codec.classify(single) == nil, "the fixture must be valid Base64 for this test to mean anything")
        #expect(Base64Codec.decode(single) == .failure(.decodedBytesAreNotUTF8(position: 1)))

        // Both bytes came out of the one quantum this three-byte input encodes
        // to, so the input position is 1 — not the 2 the output offset gave.
        let embedded = Data([0x61, 0xA9, 0x62]).base64EncodedString()
        #expect(Base64Codec.decode(embedded) == .failure(.decodedBytesAreNotUTF8(position: 1)))
    }

    /// Valid Base64 that decodes to text is untouched by any of this.
    @Test
    func textStillDecodesToText() {
        #expect(Base64Codec.decode("aGVsbG8=").success == "hello")
        #expect(Base64Codec.decode("").success == "")
        #expect(Base64Codec.decode(Base64Codec.encode("héllo!wörld")).success == "héllo!wörld")
    }
}
