import CryptoKit
import XCTest

// THE SECOND OPINION, AND THE POPULATION TYPE THAT GOES WITH IT.
//
// A UI-test process cannot link the application module, and here that is a FEATURE rather than an
// obstacle: every value `AppStoreScreenshotTests` asserts is compared against a string THIS PROCESS
// computed for itself, from the definition rather than from the app's implementation. That is the
// house rule from plan 07-10 — a card that renumbers without recomputing fails, and a screenshot
// whose pinned format silently fell back to the app's default fails with it.
//
// SPLIT OUT OF `AppStoreScreenshotTests.swift` FOR ONE REASON, RECORDED SO IT IS NOT MISTAKEN FOR
// TASTE: that file is at `swiftlint --strict`'s 400-line file budget, and `--strict` promotes the
// 400-line WARNING to an error (UL-056). The alternative was deleting the measurements written in
// its comments, which are the part of it hardest to re-derive.
//
// THE NAMESPACE IS NOT DECORATION. `StepEditTests.swift` already declares a file-private
// `base64(_:)` at file scope; a second top-level function of the same name and signature in the same
// module is at best confusing and at worst ambiguous at the call site. `SecondOpinion.base64(…)`
// cannot collide and says at every call site what the comparison is for.
//
// C-25: Swift 5.9 / `SWIFT_STRICT_CONCURRENCY: minimal`, like every file in this target.

/// One identifier and how many elements must carry it, so a population assembled from two
/// identifiers asserts each contribution before either is unioned.
struct ValueSource {
    let identifier: String
    let expected: Int

    init(_ identifier: String, _ expected: Int) {
        (self.identifier, self.expected) = (identifier, expected)
    }
}

/// One surface's input block, as the capture gate addresses it: the FIELD and the LABEL standing
/// above it.
///
/// **THE LABEL IS HERE BECAUSE LEAVING IT OUT SHIPPED THE DEFECT TWICE.** Plan 08-20 widened the
/// gate's head population from {output values} to {field, Step.position, Step.header} and
/// re-captured; `iPhone-03-timestamps-light` and `-07-timestamps-dark` came back with the
/// navigation bar slicing the "Input" LABEL through the middle of its letterforms, and ASSERTION 7
/// reported `outside=0` because the label was the one element sitting just outside the new
/// boundary. A correct check pointed at the wrong population, recurring one ring further out
/// inside the fix for an instance of itself.
///
/// A value rather than two parameters at every call site, so a shot cannot name Hashing's label
/// beside Encode's field — and so the gate stays inside `function_parameter_count`'s five.
struct SurfaceInput {
    /// The text field.
    let field: String

    /// The "Input" label above it.
    let label: String

    static let encode = SurfaceInput(field: AccessibilityIdentifiers.Encode.input,
                                     label: AccessibilityIdentifiers.Encode.inputLabel)
    static let hashing = SurfaceInput(field: AccessibilityIdentifiers.Hashing.input,
                                      label: AccessibilityIdentifiers.Hashing.inputLabel)
    static let timestamps = SurfaceInput(field: AccessibilityIdentifiers.Timestamps.input,
                                         label: AccessibilityIdentifiers.Timestamps.inputLabel)
}

/// What the values on screen are compared AGAINST — each arrived at from the definition, never read
/// back out of the application that is under test.
enum SecondOpinion {
    /// Base64, as `Base64Codec` defines it: the UTF-8 bytes, standard alphabet, padded.
    static func base64(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
    }

    /// SHA-256 over the UTF-8 bytes, as 64 LOWERCASE hex characters — the rendering `DigestCodec`
    /// ships. CryptoKit's own textual printout of a digest is not hex, which is why this spells the
    /// conversion rather than interpolating the digest.
    static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// HTML entity encoding of the five characters HTML 4 requires, with the apostrophe as `&#39;`
    /// rather than `&apos;` — `&apos;` is not in HTML 4.
    static func htmlEncoded(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    /// Percent encoding against RFC 3986 §2.3's unreserved set — `ALPHA / DIGIT / "-" / "." / "_" /
    /// "~"` — with every other UTF-8 byte as `%` and two UPPERCASE hex digits. Spelled out as bytes
    /// rather than reached for through a `CharacterSet`, which does not agree with §2.3.
    static func percentEncoded(_ text: String) -> String {
        let unreserved = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".utf8)
        var out = ""
        for byte in text.utf8 {
            if unreserved.contains(byte) {
                out.append(Character(UnicodeScalar(byte)))
            } else {
                out += String(format: "%%%02X", byte)
            }
        }
        return out
    }
}
