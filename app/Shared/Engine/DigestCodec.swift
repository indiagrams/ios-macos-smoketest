// DigestCodec — APP-04, the four digests, rendered as lowercase hex.
//
// This is the ONE place in this phase where a cryptographic API is called.
// CryptoKit only; nothing here is hand-rolled. 06-RESEARCH measured the full
// surface under `-swift-version 6 -strict-concurrency=complete`, and it was
// re-measured on this tree before this file was written.
//
// HASHING CANNOT FAIL, AND NO FAILURE PATH IS BUILT FOR ONE. Every String has
// a UTF-8 encoding and every byte sequence has a digest. 06-UI-SPEC.md states
// this and it is correct: the Hashing card has no error state. Adding one for
// symmetry with Base64Codec or PercentCodec would be inventing a branch that
// no input can reach and no test can cover.
//
// THE MEASURED TRAP: CryptoKit's own textual printout of a digest is NOT hex.
// On macOS 26.5.2, printing the MD5 of "hello" yields
//
//     MD5 digest: 5d41402abc4b2a76b9719d911017c592
//
// The `"<ALG> digest: "` prefix is part of the string. A copy button wired to
// that printout puts the prefix on the pasteboard, which is the "wrong answer"
// half of ROADMAP criterion 1. `hexString` below is the only rendering used
// anywhere, and `DigestTests.noDigestOutputContainsTheSubstringDigest` asserts
// both that the trap is still real and that no output falls into it.
//
// AVAILABILITY: CryptoKit is iOS 13 / macOS 10.15, far below this app's iOS 17
// / macOS 14 floor, so no annotation is needed and none is present.

import CryptoKit
import Foundation

/// The four digests this app offers, each rendered as lowercase hex.
///
/// A caseless enum rather than a struct: there is no instance state and there
/// is nothing to construct.
enum DigestCodec {
    /// Lowercase hex for any byte sequence.
    ///
    /// - Note: Total. The empty sequence yields the empty string, and the two
    ///   subscripts cannot be out of range: a nibble is 0...15 and the table
    ///   has 16 entries. There is no failable initializer to unwrap and no
    ///   branch this function can take that a test cannot reach.
    /// - Important: This appends `Character`s rather than accumulating
    ///   `[UInt8]` and finishing with `String(decoding:as:)`, which is the
    ///   shape 06-RESEARCH recommends. That shape MEASURABLY FAILS
    ///   `swiftlint --strict` on this repo's config:
    ///
    ///       error: Optional Data -> String Conversion Violation: Prefer
    ///       failable `String(bytes:encoding:)` initializer when converting
    ///       `Data` to `String` (optional_data_string_conversion)
    ///
    ///   The rule's own advice cannot be taken either: `String(bytes:encoding:)`
    ///   returns an Optional, which this function has no honest way to unwrap,
    ///   and 06-03 measured that same initializer silently REPAIRING the byte
    ///   0xA9 to U+FFFD on iOS 17.5. Appending Characters satisfies the linter
    ///   and keeps the function total. `non_optional_string_data_conversion`
    ///   is in `.swiftlint.yml`'s `disabled_rules`; this is the other rule of
    ///   that pair and is enabled. The config was not loosened.
    nonisolated static func hexString(_ bytes: some Sequence<UInt8>) -> String {
        let table: [Character] = Array("0123456789abcdef")
        var out = ""
        out.reserveCapacity(128)
        for byte in bytes {
            out.append(table[Int(byte >> 4)])
            out.append(table[Int(byte & 0x0F)])
        }
        return out
    }

    /// The MD5 of `s`'s UTF-8 bytes, as 32 lowercase hex characters.
    ///
    /// MD5 is cryptographically broken, and shipping it here is deliberate
    /// rather than an oversight: it is **the product**, a user-facing tool for
    /// inspecting digests that already exist, not a security control
    /// protecting anything. Nothing in this app authenticates, signs or
    /// derives a key. Apple's `Insecure.` namespace is itself the
    /// documentation, and no suppression of any kind is used or needed.
    ///
    /// - Note: Cannot fail. See the file header.
    nonisolated static func md5(_ s: String) -> String {
        hexString(Insecure.MD5.hash(data: Data(s.utf8)))
    }

    /// The SHA-1 of `s`'s UTF-8 bytes, as 40 lowercase hex characters.
    ///
    /// SHA-1 is cryptographically broken, and is here for the same reason MD5
    /// is: it is a user-facing conversion tool for reading digests other
    /// systems produced, not a control this app relies on. Nothing here
    /// authenticates, signs or derives a key.
    ///
    /// - Note: Cannot fail. See the file header.
    nonisolated static func sha1(_ s: String) -> String {
        hexString(Insecure.SHA1.hash(data: Data(s.utf8)))
    }

    /// The SHA-256 of `s`'s UTF-8 bytes, as 64 lowercase hex characters.
    ///
    /// - Note: Cannot fail. See the file header.
    nonisolated static func sha256(_ s: String) -> String {
        hexString(SHA256.hash(data: Data(s.utf8)))
    }

    /// The SHA-512 of `s`'s UTF-8 bytes, as 128 lowercase hex characters.
    ///
    /// - Note: Cannot fail. See the file header.
    nonisolated static func sha512(_ s: String) -> String {
        hexString(SHA512.hash(data: Data(s.utf8)))
    }
}
