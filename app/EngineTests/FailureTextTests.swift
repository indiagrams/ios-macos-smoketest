// FailureTextTests — the twelve approved sentences, RESOLVED AND RENDERED.
//
// READING THE CATALOG IS NOT THE SAME AS RENDERING IT. A wrong format specifier
// compiles fine and renders as a mangled sentence; `%%` is a literal percent
// sign and takes no argument; `%lld` needs an `Int`. None of that is visible in
// a source grep, and none of it is visible in a JSON diff of the catalog
// either. So every assertion below goes through the same call the views make.
//
// AND: `NSLocalizedString` returns the KEY when the lookup misses. A catalog
// that stopped reaching the bundle would render `encode.error.base64.length` on
// screen, non-empty and distinct from its neighbours, and a test that only
// checked for non-emptiness and distinctness would stay green. That is what
// `noSentenceIsItsOwnKey` is for.

import Testing

/// The failure-to-sentence mapping in `app/Shared/Views/FailureText.swift`.
@Suite("Failure text")
struct FailureTextTests {
    /// One representative of every case, in both domains where the case has
    /// two. Ten cases, eleven key/domain pairs.
    private static let samples: [(failure: ConversionFailure, domain: FailureDomain)] = [
        (.unexpectedCharacter("!", position: 12), .text),
        (.unexpectedCharacter("x", position: 3), .timestamps),
        (.badLength(7), .text),
        (.paddingBeforeEnd(position: 3), .text),
        (.invalidEscape(position: 5), .text),
        (.invalidUTF8(position: 2), .text),
        (.decodedBytesAreNotUTF8(position: 5), .text),
        (.unknownEntity("&nope;", position: 4), .text),
        (.unterminatedEntity(position: 1), .text),
        (.expectedCharacter("T", position: 11), .timestamps),
        (.outOfRange("99999999999999999999"), .timestamps)
    ]

    /// The exact format strings 06-UI-SPEC.md §"Full string inventory"
    /// approves, spelled out here so a drift in either direction is visible.
    private static let approved: [(key: String, format: String)] = [
        ("encode.error.base64.character", "Not valid Base64: unexpected character '%@' at position %lld."),
        ("encode.error.base64.length", "Not valid Base64: the length must be a multiple of 4, and it is %lld."),
        ("encode.error.base64.padding", "Not valid Base64: a character appears at position %lld, after the padding."),
        (
            "encode.error.url.escape",
            "Not valid percent-encoding: '%%' at position %lld is not followed by two hexadecimal digits."
        ),
        ("encode.error.url.utf8", "Not valid percent-encoding: the bytes at position %lld are not valid UTF-8."),
        (
            "encode.error.base64.utf8",
            "Valid Base64, but the characters at position %lld decode to bytes that are not valid UTF-8."
        ),
        ("encode.error.html.unknown", "Not a known HTML entity: '%@' at position %lld."),
        ("encode.error.html.unterminated", "Unterminated HTML entity: the '&' at position %lld has no ';'."),
        ("timestamps.error.notDigit", "Not a Unix epoch: '%@' at position %lld is not a digit."),
        ("timestamps.error.iso8601", "Not valid ISO 8601: expected '%@' at position %lld."),
        ("timestamps.error.range", "Out of range: %@ is outside the dates this app can show."),
        ("step.blocked", "Blocked by an error in an earlier step.")
    ]

    /// All twelve keys resolve to the exact approved format string.
    @Test("all twelve approved strings resolve from the catalog, character for character")
    func allTwelveApprovedStringsResolve() {
        #expect(Self.approved.count == 12)
        for (key, format) in Self.approved {
            let resolved = String(localized: String.LocalizationValue(key))
            #expect(resolved == format, "\(key) resolved to \(resolved)")
        }
    }

    /// The mapping reaches every approved key and invents none.
    @Test("the mapping covers exactly the twelve approved keys")
    func theMappingCoversExactlyTheTwelveApprovedKeys() {
        var reached = Set(Self.samples.map { failureStringKey($0.failure, in: $0.domain) })
        #expect(reached.count == 11)
        reached.insert("step.blocked")
        #expect(reached == Set(Self.approved.map(\.key)))
    }

    /// Every sentence renders with its arguments in the right places.
    ///
    /// The `%%` case is the one that would go unnoticed: it renders as a single
    /// percent sign, and passing it an extra argument, or writing a single `%`
    /// in the catalog, mangles the sentence without failing to compile.
    @Test("every sentence renders with its arguments substituted")
    func everySentenceRendersWithItsArgumentsSubstituted() {
        #expect(failureText(.unexpectedCharacter("!", position: 12))
            == "Not valid Base64: unexpected character '!' at position 12.")
        #expect(failureText(.unexpectedCharacter("x", position: 3), in: .timestamps)
            == "Not a Unix epoch: 'x' at position 3 is not a digit.")
        #expect(failureText(.badLength(7))
            == "Not valid Base64: the length must be a multiple of 4, and it is 7.")
        #expect(failureText(.paddingBeforeEnd(position: 3))
            == "Not valid Base64: a character appears at position 3, after the padding.")
        #expect(failureText(.invalidEscape(position: 5))
            == "Not valid percent-encoding: '%' at position 5 is not followed by two hexadecimal digits.")
        #expect(failureText(.invalidUTF8(position: 2))
            == "Not valid percent-encoding: the bytes at position 2 are not valid UTF-8.")
        #expect(failureText(.decodedBytesAreNotUTF8(position: 5))
            == "Valid Base64, but the characters at position 5 decode to bytes that are not valid UTF-8.")
        #expect(failureText(.unknownEntity("&nope;", position: 4))
            == "Not a known HTML entity: '&nope;' at position 4.")
        #expect(failureText(.unterminatedEntity(position: 1))
            == "Unterminated HTML entity: the '&' at position 1 has no ';'.")
        #expect(failureText(.expectedCharacter("T", position: 11), in: .timestamps)
            == "Not valid ISO 8601: expected 'T' at position 11.")
        #expect(failureText(.outOfRange("99999999999999999999"), in: .timestamps)
            == "Out of range: 99999999999999999999 is outside the dates this app can show.")
        #expect(blockedStepText() == "Blocked by an error in an earlier step.")
    }

    /// No rendered sentence is its own key, which is what a missing catalog
    /// would produce — non-empty, distinct, and completely wrong.
    @Test("no rendered sentence is its own key")
    func noSentenceIsItsOwnKey() {
        for sample in Self.samples {
            let key = failureStringKey(sample.failure, in: sample.domain)
            let sentence = failureText(sample.failure, in: sample.domain)
            #expect(!sentence.isEmpty)
            #expect(sentence != key, "\(key) rendered as its own key")
        }
        #expect(blockedStepText() != "step.blocked")
    }

    /// Every case renders a DIFFERENT sentence, so no two failures are
    /// indistinguishable to a user.
    @Test("every failure case renders a distinct sentence")
    func everyFailureCaseRendersADistinctSentence() {
        let sentences = Self.samples.map { failureText($0.failure, in: $0.domain) }
        #expect(Set(sentences).count == sentences.count)
    }

    /// All four render states exist, are distinguishable, and none of them is
    /// an empty string standing in for "nothing yet".
    ///
    /// `StepRenderState` makes blank unrepresentable at the type level; this
    /// asserts the property the type is FOR, over all four cases at once.
    @Test("all four render states are distinct and none is blank")
    func allFourRenderStatesAreDistinctAndNoneIsBlank() {
        let states: [StepRenderState] = [
            .empty,
            .value("aGVsbG8="),
            .failure(.badLength(7)),
            .blocked
        ]
        #expect(states.count == 4)
        #expect(Set(states.map { "\($0)" }).count == 4)
        #expect(states.contains(.empty))
        #expect(states.contains(.blocked))
        for state in states {
            if case let .failure(reason) = state {
                #expect(!failureText(reason).isEmpty)
            }
            if case let .value(value) = state {
                #expect(!value.isEmpty)
            }
        }
    }
}
