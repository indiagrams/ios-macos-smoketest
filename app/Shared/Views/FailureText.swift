// FailureText — every ``ConversionFailure`` as its exact approved sentence
// (06-UI-SPEC.md §"Full string inventory", D-85).
//
// THIS FILE IS THE ONE PLACE A FAILURE BECOMES WORDS. The engines return a
// named reason and a character position and know nothing about localization;
// the model layer carries them unchanged; this is where they turn into the
// eleven sentences the contract approved. The `switch` is exhaustive with NO
// `default:` branch, so a tenth failure case added without a string is a
// compile error here rather than a silently empty sentence on a screen.
//
// WHY THESE FUNCTIONS RETURN `String` AND NOT `LocalizedStringKey`. The catalog
// is keyed by dotted keys (`encode.error.base64.character`), not by its English
// text, and every sentence below takes at least one runtime argument. A
// `LocalizedStringKey` can express one or the other and not both: interpolating
// into it builds a key out of the interpolated TEXT, which would miss the
// dotted key entirely and render the English sentence only by falling back to
// the key it failed to find. Resolving the format string and substituting the
// arguments is the mechanism that actually works — and it is also what lets
// this plan's evidence compare all eleven RENDERED sentences against the
// UI-SPEC at runtime, which reading the catalog cannot do. Callers pass the
// result to `Text(verbatim:)`, so nothing is looked up twice.
//
// FORMAT SPECIFIERS, and the two traps in them. Every position is `%lld`, so
// the argument must be an `Int` and never an `Int32`. `encode.error.url.escape`
// contains `'%%'`, which is a LITERAL percent sign in the catalog and takes no
// argument of its own — its only argument is the position.
//
// This file needs Foundation and nothing else. It is compiled into both app
// targets by the `Shared` sources entry, and into both unit-test targets by the
// `Shared/Views` entries added by this plan, so the sentences can be asserted
// by a host-based test rather than by a grep over this source.

import Foundation

/// Which family of conversion produced a failure.
///
/// Exactly one ``ConversionFailure`` case renders differently between the two:
/// `.unexpectedCharacter` is the Base64 alphabet error on the text surfaces and
/// the epoch non-digit error on Timestamps. That is why nine cases map to ten
/// error strings, and it is why this parameter exists rather than a tenth case.
enum FailureDomain: Sendable, Hashable {
    /// The Encode/decode and Hashing surfaces, and every appended step.
    case text

    /// The Timestamps surface.
    case timestamps
}

/// The `Localizable.xcstrings` key `failure` renders from.
///
/// Split out from ``failureText(_:in:)`` so a test can enumerate the eleven
/// keys and resolve each one, rather than asserting that this file mentions
/// them. Exhaustive, with no `default:`.
func failureStringKey(_ failure: ConversionFailure, in domain: FailureDomain = .text) -> String {
    switch failure {
    case .unexpectedCharacter: unexpectedCharacterKey(in: domain)
    case .badLength: "encode.error.base64.length"
    case .paddingBeforeEnd: "encode.error.base64.padding"
    case .invalidEscape: "encode.error.url.escape"
    case .invalidUTF8: "encode.error.url.utf8"
    case .unknownEntity: "encode.error.html.unknown"
    case .unterminatedEntity: "encode.error.html.unterminated"
    case .expectedCharacter: "timestamps.error.iso8601"
    case .outOfRange: "timestamps.error.range"
    }
}

/// The one key that depends on the domain rather than only on the case.
///
/// Lifted out of ``failureStringKey(_:in:)`` because the nested `switch` put
/// that function one branch over `swiftlint --strict`'s cyclomatic-complexity
/// ceiling of 10 — measured, not predicted.
private func unexpectedCharacterKey(in domain: FailureDomain) -> String {
    switch domain {
    case .text: "encode.error.base64.character"
    case .timestamps: "timestamps.error.notDigit"
    }
}

/// `failure` as the exact approved sentence, arguments substituted.
///
/// Exhaustive over ``ConversionFailure`` with no `default:`. The payloads travel
/// through unchanged from the engine that produced them — in particular
/// `.paddingBeforeEnd` carries the position of the first character AFTER the
/// padding, which is the measured convention pinned by `TestVectors`, and this
/// plan reworded `encode.error.base64.padding` to say so rather than moving the
/// number to suit the prose.
func failureText(_ failure: ConversionFailure, in domain: FailureDomain = .text) -> String {
    let key = failureStringKey(failure, in: domain)
    switch failure {
    case let .unexpectedCharacter(character, position):
        return localizedSentence(key, String(character), position)
    case let .badLength(length):
        return localizedSentence(key, length)
    case let .paddingBeforeEnd(position):
        return localizedSentence(key, position)
    case let .invalidEscape(position):
        return localizedSentence(key, position)
    case let .invalidUTF8(position):
        return localizedSentence(key, position)
    case let .unknownEntity(entity, position):
        return localizedSentence(key, entity, position)
    case let .unterminatedEntity(position):
        return localizedSentence(key, position)
    case let .expectedCharacter(expected, position):
        return localizedSentence(key, expected, position)
    case let .outOfRange(value):
        return localizedSentence(key, value)
    }
}

/// The sentence a step shows when an EARLIER step in its pipeline failed.
///
/// `step.blocked` — "Blocked by an error in an earlier step." It carries no
/// glyph and no position: it is not an error of the user's making at this step
/// (06-UI-SPEC.md §"State Contract" item 4). Callers that need it as a
/// ``DiagnosticContent`` use `.neutral`, not `.problem`.
func blockedStepText() -> String {
    localizedSentence("step.blocked")
}

/// Resolve `key` from the app's string catalog and substitute `arguments`.
///
/// `NSLocalizedString` returns the KEY on a miss rather than throwing, so a
/// catalog that stopped reaching the bundle would render `encode.error.url.utf8`
/// on screen and nothing would fail. That is exactly what
/// `StringCatalogTests` and this plan's eleven-sentence check are for.
private func localizedSentence(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), locale: .current, arguments: arguments)
}
