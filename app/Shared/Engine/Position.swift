// Position — the ONE definition of "position" in this app.
//
// Every classifier under Engine/ reports its failures through these two
// functions, so the four error families (Base64, percent-encoding, HTML
// entities, ISO 8601) cannot disagree about what "position 12" means. The
// user-facing strings that consume it all share one shape:
//
//   "Not valid Base64: unexpected character '!' at position 12."
//   "Not valid percent-encoding: '%' at position 5 is not followed by two…"
//   "Not a known HTML entity: '&nope;' at position 3."
//   "Not valid ISO 8601: expected '-' at position 5."
//
// The unit is a 1-BASED CHARACTER (extended grapheme cluster) OFFSET, because
// a user counting characters on screen counts graphemes. Measured, 2026-09-04:
//
//   "héllo!wörld"   Characters 11   UTF-8 13   UTF-16 11   scalars 11
//   "a👨‍👩‍👧‍👦b"        Characters  3   UTF-8 27   UTF-16 13   scalars  9
//
// UTF-16 would report the family emoji as 13 code units and UTF-8 as 27; the
// user sees three characters. For Base64 and percent-encoding the choice is
// provably free at the reported position — the first invalid byte is by
// construction preceded only by valid ASCII, so all three offsets coincide
// there. It matters for HTML entities and ISO 8601, where legitimate
// non-ASCII can precede an error, and there the grapheme answer is the one
// that matches what the user is looking at.
//
// 1-based, to read like a compiler column.
//
// This file is compiled into the two app targets AND into both unit-test
// targets, by explicit `sources:` entries in app/project.yml and
// app/Project.swift. No test spells the fork's module name.

/// The 1-based Character (extended grapheme cluster) offset of the grapheme
/// containing the UTF-8 byte at `utf8Offset`.
///
/// - Important: **Failure path only.** Iterating Characters costs a measured
///   44.6 ms on a 1 MB string, against 0.6 ms for a whole `base64EncodedString()`
///   of the same input. Classifiers scan `String.UTF8View` and call this once,
///   when they have already decided to report a failure. Never call it inside a
///   scan loop.
/// - Note: Total by construction, INCLUDING for `Int.max`. A negative offset
///   returns `1`; an offset at or past `s.utf8.count` returns the end
///   position, `s.count + 1`. `utf8Offset` is only ever COMPARED, never used
///   in arithmetic — that is what makes `Int.max` safe, and it is why the
///   guard sits before the addition rather than after it. The obvious wrong
///   implementation, `utf8Offset + 1`, overflows and traps on `Int.max`.
/// - Warning: These bundles are HOST-BASED (`TEST_HOST` and `BUNDLE_LOADER`
///   both resolve to the app binary), so a Swift runtime trap in a unit test
///   does not fail a test — it kills the host process, aborts the run, and
///   posts a crash-reporter dialog on the developer's desktop. A classifier
///   must never crash the app on its own error path, and an off-by-one in a
///   caller must not become a trap.
/// - Parameters:
///   - utf8Offset: A byte offset into `s.utf8`, as produced by a UTF-8 scan.
///   - s: The string being classified.
/// - Returns: A 1-based Character offset, never fractional and never interior
///   to a grapheme.
nonisolated func characterPosition(utf8Offset: Int, in s: String) -> Int {
    guard utf8Offset > 0 else { return 1 }
    var position = 1
    var bytesConsumed = 0
    for character in s {
        // Compare before advancing, so a byte anywhere inside this grapheme
        // reports this grapheme rather than the next one.
        if utf8Offset < bytesConsumed + character.utf8.count {
            return position
        }
        bytesConsumed += character.utf8.count
        position += 1
    }
    return position
}

/// The Character containing the UTF-8 byte at `utf8Offset` — what fills the
/// `'%@'` slot in the error strings above.
///
/// - Important: **Failure path only**, for the same measured reason as
///   ``characterPosition(utf8Offset:in:)``.
/// - Note: Total by construction. A negative offset yields the first
///   Character, an offset at or past the end yields the last, and an empty
///   string yields U+FFFD REPLACEMENT CHARACTER — there is no Character to
///   return and returning an Optional would push the same decision onto every
///   caller's error path.
/// - Parameters:
///   - utf8Offset: A byte offset into `s.utf8`.
///   - s: The string being classified.
/// - Returns: A whole grapheme, never a single byte of a multi-byte one.
nonisolated func characterAt(utf8Offset: Int, in s: String) -> Character {
    guard let lastCharacter = s.last, let firstCharacter = s.first else { return "\u{FFFD}" }
    guard utf8Offset > 0 else { return firstCharacter }
    var bytesConsumed = 0
    for character in s {
        if utf8Offset < bytesConsumed + character.utf8.count {
            return character
        }
        bytesConsumed += character.utf8.count
    }
    return lastCharacter
}
