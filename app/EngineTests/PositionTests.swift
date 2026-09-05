// Unit tests for app/Shared/Engine/Position.swift — the one definition of
// "position" that every error string in this app reports against.
//
// Run via (macOS, ~1.5 s, safe to run locally — no UI-test target is built):
//   xcodebuild test -project app/App.xcodeproj -scheme App-macOS \
//     -configuration Debug -destination 'platform=macOS' \
//     -only-testing:AppMacOSTests/PositionTests \
//     CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
//
// Run via (iOS simulator):
//   xcodebuild test -project app/App.xcodeproj -scheme App-iOS \
//     -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
//     -only-testing:AppTests/PositionTests
//
// This file lives in one place and is compiled into BOTH unit-test targets by
// explicit `sources:` entries in app/project.yml and app/Project.swift. There
// is no second copy for iOS: two corpora drift, one does not.
//
// The expected values below were MEASURED on 2026-09-04 with a swiftc probe,
// not copied from a document:
//
//   "héllo!wörld"  Characters 11  UTF-8 13  UTF-16 11  scalars 11
//     h=[0] é=[1...2] l=[3] l=[4] o=[5] !=[6] w=[7] ö=[8...9] r=[10] l=[11] d=[12]
//   "a👨‍👩‍👧‍👦b"       Characters  3  UTF-8 27  UTF-16 13  scalars  9
//     a=[0] 👨‍👩‍👧‍👦=[1...25] b=[26]
//
// A number here that starts to drift is a signal, not an annoyance: re-measure
// with the probe, do not bump the literal.

import Testing

/// Swift Testing discovers this type as a suite named after the type itself, so
/// `-only-testing:AppMacOSTests/PositionTests` and `-only-testing:AppTests/PositionTests`
/// both select exactly these cases. Deliberately no bare `@Suite` attribute:
/// SwiftFormat's `redundantSwiftTestingSuite` rule strips an argument-less one,
/// and the runner reports `Suite PositionTests passed` without it.
struct PositionTests {
    /// The string whose UTF-8 layout is quoted in the file header.
    private static let accented = "héllo!wörld"

    /// Three Characters, twenty-seven UTF-8 bytes — the case that separates a
    /// grapheme answer from a UTF-8 or UTF-16 one.
    private static let family = "a👨‍👩‍👧‍👦b"

    /// The unit is 1-based, so it reads like a compiler column.
    @Test
    func firstByteIsPositionOne() {
        #expect(characterPosition(utf8Offset: 0, in: "abc") == 1)
    }

    /// A byte offset that lands squarely on a single-byte Character reports
    /// that Character's 1-based index. Byte 6 of `héllo!wörld` is the `!`,
    /// which is Character 6.
    @Test
    func offsetOnASingleByteCharacterReportsThatCharacter() {
        #expect(characterPosition(utf8Offset: 6, in: Self.accented) == 6)
    }

    /// A byte INSIDE a multi-byte grapheme reports the grapheme that contains
    /// it — never a fractional or interior index. Byte 2 is the second byte of
    /// `é` (Character 2); byte 9 is the second byte of `ö` (Character 8).
    @Test
    func offsetInsideAMultiByteCharacterReportsTheContainingCharacter() {
        #expect(characterPosition(utf8Offset: 2, in: Self.accented) == 2)
        #expect(characterPosition(utf8Offset: 9, in: Self.accented) == 8)
    }

    /// The whole reason the unit is a grapheme: the family emoji is ONE
    /// Character. `b` is at UTF-8 byte 26 and UTF-16 offset 12, and reports
    /// position 3 — not 27 and not 13.
    @Test
    func aGraphemeClusterCountsAsOneCharacter() {
        #expect(Self.family.count == 3)
        #expect(Self.family.utf8.count == 27)
        #expect(characterPosition(utf8Offset: 26, in: Self.family) == 3)
    }

    /// `characterAt` is what fills the `'%@'` slot in the error strings, so it
    /// must hand back the whole grapheme, not a byte.
    @Test
    func characterAtReturnsTheContainingGrapheme() {
        #expect(characterAt(utf8Offset: 1, in: Self.accented) == "é")
        #expect(characterAt(utf8Offset: 2, in: Self.accented) == "é")
        #expect(characterAt(utf8Offset: 6, in: Self.accented) == "!")
        #expect(characterAt(utf8Offset: 26, in: Self.family) == "b")
    }

    /// For pure ASCII the answer is always `offset + 1`. This is the property
    /// that makes the grapheme choice free for Base64 and percent-encoding,
    /// whose first invalid byte is by construction preceded only by ASCII.
    @Test(arguments: Array(0 ..< 12))
    func asciiPositionIsOffsetPlusOne(offset: Int) {
        let ascii = "aGVs!G8=+/xy"
        #expect(ascii.utf8.count == 12)
        #expect(characterPosition(utf8Offset: offset, in: ascii) == offset + 1)
    }

    /// Total function, part 1: an offset at or past the end returns the end
    /// position rather than trapping. A classifier must never crash the app on
    /// its own error path.
    ///
    /// Read what a green here does and does not mean. These bundles are
    /// HOST-BASED — `TEST_HOST` and `BUNDLE_LOADER` both resolve to the app
    /// binary — so a Swift runtime trap does NOT fail this test: it kills the
    /// host process and aborts the run. Measured on the deliberately-broken
    /// control (`utf8Offset + 1`): the `Int.max` case produced SIGTRAP host
    /// deaths with zero recorded issues, plus a crash-reporter dialog per
    /// launch. Swift Testing has no `#expect(doesNotTrap:)` and cannot have
    /// one — a Swift runtime trap is not catchable in-process. So the
    /// assertion below is structured the only way it can be: the NON-trapping
    /// outcome is what is asserted, on the returned value. A trap shows up as
    /// a dead run, not as a failing expectation.
    @Test(arguments: [13, 14, 99, -1, Int.max])
    func outOfRangeOffsetReturnsAPositionRatherThanTrapping(offset: Int) {
        let position = characterPosition(utf8Offset: offset, in: Self.accented)
        if offset < 0 {
            #expect(position == 1)
        } else {
            #expect(position == Self.accented.count + 1)
            #expect(position == 12)
        }
    }

    /// Total function, part 2: `characterAt` past the end yields the last
    /// Character, and on an empty string yields U+FFFD rather than trapping —
    /// there is no last Character to return.
    @Test
    func characterAtIsTotal() {
        #expect(characterAt(utf8Offset: 13, in: Self.accented) == "d")
        #expect(characterAt(utf8Offset: Int.max, in: Self.accented) == "d")
        #expect(characterAt(utf8Offset: -1, in: Self.accented) == "h")
        #expect(characterAt(utf8Offset: 0, in: "") == "\u{FFFD}")
        #expect(characterPosition(utf8Offset: 0, in: "") == 1)
    }
}
