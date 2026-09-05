// TestVectors — the ONE corpus both unit targets assert against.
//
// This file lives in one place and is compiled into BOTH AppTests and
// AppMacOSTests by explicit `sources:` entries in app/project.yml and
// app/Project.swift. iOS and macOS therefore assert the SAME numbers. Two
// copies would drift, and a drift between two corpora is invisible: each
// suite stays green against its own stale expectations.
//
// EVERY VALUE HERE WAS MEASURED, not recalled and not copied from prose.
// Provenance, and re-measured on this tree on 2026-09-04 before being written:
//
//   base64Corpus     06-RESEARCH.md §"Error Classification (D-85) — the
//                    differential result", the 18-input classifier/Foundation
//                    table. Re-run through `Data(base64Encoded:)`; all 18
//                    Foundation verdicts reproduced exactly.
//   percentCases     06-RESEARCH.md §"What Foundation gives you", the
//                    `String.removingPercentEncoding` table. All 8 reproduced.
//   digestVectors    06-RESEARCH.md §"CryptoKit (APP-04)". Re-run through
//                    CryptoKit; all four "hello" digests reproduced, and the
//                    SHA-512 is written out in full here because RESEARCH
//                    quotes it truncated.
//   timestampCases   06-RESEARCH.md §"Timestamps" comparison table and
//                    §"Auto-detection (D-88, D-89)" boundary probes. All
//                    reproduced.
//   positionCases    06-RESEARCH.md §"Pattern 2". Re-measured with a swiftc
//                    probe; see app/EngineTests/PositionTests.swift.
//
// THE DATED-MEASUREMENT RULE. A number in this file that starts to disagree
// with reality is a SIGNAL, not an annoyance. Re-measure it, and treat the
// change as a finding worth writing down — a Foundation behaviour that moved
// between OS versions is exactly the sort of thing this corpus exists to
// catch. Do NOT bump a literal to make a suite green.
//
// One measured subtlety already caught by re-measuring: RESEARCH quotes
// "2026-09-04T00:00:00.123Z" as parsing to 1788480000.123. The actual Double
// is 1788480000.1230001 — .123 is not representable in binary floating point.
// A corpus asserting exact equality on that value would fail. Compare
// fractional instants with a tolerance; the literal below is the true one.

// MARK: - Base64 (APP-02, D-85)

/// The verdict a hand-written Base64 classifier is expected to return.
///
/// This is the expectation VOCABULARY, fixed here before any classifier
/// exists, so the corpus does not have to be rewritten when one lands. A
/// classifier whose own failure type has a different shape maps onto this in
/// its own test — the measured values do not move to accommodate it.
enum ExpectedBase64Verdict: Equatable, Sendable {
    /// No fault found; the classifier would hand the input to the decoder.
    case valid
    /// Length is not a multiple of 4. Payload is the measured length.
    case badLength(Int)
    /// A character outside the standard alphabet, at a 1-based Character position.
    case unexpectedCharacter(Character, position: Int)
    /// A `=` before the end of the input, at a 1-based Character position.
    case earlyPadding(position: Int)
}

/// One Base64 input, what the classifier should say about it, and what
/// Foundation actually does with it.
struct Base64Case: Sendable {
    /// The untrusted input string.
    let input: String
    /// What the classifier is expected to return.
    let expected: ExpectedBase64Verdict
    /// Whether `Data(base64Encoded:)` returns non-nil. MEASURED, not predicted.
    ///
    /// Measured on the 26.x runtimes (macOS 26.1, iOS 26.1). For inputs listed
    /// in ``TestVectors/foundationOSVariantInputs`` this value is NOT stable
    /// across the OS versions this app supports — see that property.
    let foundationDecodes: Bool

    /// True when the classifier and Foundation reach opposite conclusions.
    ///
    /// Computed rather than stored on purpose: a stored flag can drift out of
    /// step with the two fields that define it, and this is precisely the
    /// number the suite counts.
    var foundationDisagrees: Bool {
        (expected == .valid) != foundationDecodes
    }
}

// MARK: - Percent-encoding (APP-02)

/// What `String.removingPercentEncoding` is expected to return, and why.
enum ExpectedPercentOutcome: Equatable, Sendable {
    /// Decodes to this exact string.
    case decodes(String)
    /// `%` not followed by two hex digits — UI-SPEC key `encode.error.url.escape`.
    case badEscape
    /// Escapes are well-formed but the bytes are not UTF-8 — key `encode.error.url.utf8`.
    case badUTF8
}

/// One percent-encoding input and its measured outcome.
struct PercentCase: Sendable {
    /// The untrusted input string.
    let input: String
    /// The expected outcome.
    let expected: ExpectedPercentOutcome
    /// Why this case is in the corpus at all.
    let reason: String
}

// MARK: - Hashing (APP-04)

/// The four digests of one input, lowercase hex, as CryptoKit produces them.
struct DigestVector: Sendable {
    /// The input string; digests are taken over its UTF-8 bytes.
    let input: String
    /// `Insecure.MD5`, lowercase hex.
    let md5: String
    /// `Insecure.SHA1`, lowercase hex.
    let sha1: String
    /// `SHA256`, lowercase hex.
    let sha256: String
    /// `SHA512`, lowercase hex.
    let sha512: String
}

// MARK: - Timestamps (APP-05, APP-06, APP-07, D-88, D-89)

/// What a timestamp input should be read as.
enum ExpectedTimestamp: Equatable, Sendable {
    /// `Date.ISO8601FormatStyle` parses it to this instant (seconds since 1970).
    case iso8601(Double)
    /// Detected as a Unix epoch in SECONDS; renders to this UTC ISO 8601 string.
    case epochSeconds(rendersAs: String)
    /// Detected as a Unix epoch in MILLISECONDS; renders to this UTC ISO 8601 string.
    case epochMilliseconds(rendersAs: String)
    /// The extended-format ISO 8601 parser throws on it.
    case notISO8601
    /// Does not fit in `Int` — UI-SPEC key `timestamps.error.range`.
    case outOfRange
}

/// One timestamp input, what it should be read as, and why it is here.
struct TimestampCase: Sendable {
    /// The untrusted input string.
    let input: String
    /// The measured expectation.
    let expected: ExpectedTimestamp
    /// Why this case is in the corpus.
    let reason: String
}

// MARK: - Position (Shared/Engine/Position.swift)

/// A string with its three competing length answers, so a test that reports
/// the wrong unit says so in its own failure message.
struct PositionCase: Sendable {
    /// The string.
    let string: String
    /// Extended grapheme clusters — the unit this app reports.
    let characters: Int
    /// UTF-8 code units.
    let utf8: Int
    /// UTF-16 code units.
    let utf16: Int
}

// MARK: - The corpus

/// The single shared corpus. Every engine plan in phase 6 reads from here
/// rather than inventing its own inputs.
enum TestVectors {
    /// The 20 measured Base64 inputs (18 until 06-20 added two padding shapes),
    /// with the classifier's verdict and whether Foundation decodes them.
    ///
    /// Five entries disagree, all in the same direction — Foundation is more
    /// permissive than a reasonable classifier. The contract that holds is one
    /// directional: `classify(s) == nil` implies `Data(base64Encoded: s) != nil`.
    /// **The converse is measurably false and must not be asserted.**
    static let base64Corpus: [Base64Case] = [
        Base64Case(input: "aGVsbG8=", expected: .valid, foundationDecodes: true),
        Base64Case(input: "aGVsbG8", expected: .badLength(7), foundationDecodes: false),
        Base64Case(input: "aGVs!G8=", expected: .unexpectedCharacter("!", position: 5), foundationDecodes: false),
        // DIVERGENCE 1: 9 characters, so the classifier calls it malformed;
        // Foundation decodes it to "hello" anyway.
        Base64Case(input: "aGVsbG8==", expected: .badLength(9), foundationDecodes: true),
        Base64Case(input: "a=GVsbG8=", expected: .earlyPadding(position: 3), foundationDecodes: false),
        Base64Case(input: "  aGVsbG8=  ", expected: .unexpectedCharacter(" ", position: 1), foundationDecodes: false),
        Base64Case(input: "aGVs\nbG8=", expected: .unexpectedCharacter("\n", position: 5), foundationDecodes: false),
        Base64Case(input: "", expected: .valid, foundationDecodes: true),
        // AMENDED 2026-09-05 (06-20, WR-03): `.valid` until padding with no partial
        // quantum was refused. All three still decode in Foundation, so all three
        // are DIVERGENCES now — `Base64Codec.classify` carries the measured table.
        Base64Case(input: "====", expected: .unexpectedCharacter("=", position: 1), foundationDecodes: true),
        Base64Case(input: "AAAA====", expected: .unexpectedCharacter("=", position: 5), foundationDecodes: true),
        Base64Case(input: "AAAAAAAA====", expected: .unexpectedCharacter("=", position: 9), foundationDecodes: true),
        Base64Case(input: "aGVsbG8=x", expected: .earlyPadding(position: 9), foundationDecodes: false),
        Base64Case(input: "aGVsbG9-", expected: .unexpectedCharacter("-", position: 8), foundationDecodes: false),
        Base64Case(input: "aGVsbG9_", expected: .unexpectedCharacter("_", position: 8), foundationDecodes: false),
        Base64Case(input: "héllo!==", expected: .unexpectedCharacter("é", position: 2), foundationDecodes: false),
        Base64Case(input: "AAAA", expected: .valid, foundationDecodes: true),
        Base64Case(input: "AA==", expected: .valid, foundationDecodes: true),
        Base64Case(input: "AAA=", expected: .valid, foundationDecodes: true),
        // DIVERGENCE 2: padding at position 3 of 4, and Foundation still decodes.
        Base64Case(input: "AB=A", expected: .earlyPadding(position: 4), foundationDecodes: true),
        Base64Case(input: "//++AAAA", expected: .valid, foundationDecodes: true)
    ]

    /// The five inputs on which the classifier and Foundation disagree, named
    /// rather than merely counted — a count of 5 reached by five different
    /// entries would pass a total-only assertion. Two until 06-20 refused
    /// padding with no partial quantum. A property of the RECORDED corpus, not
    /// a live probe, so it is the same number on every runtime.
    static let base64DivergentInputs: Set<String> = ["aGVsbG8==", "AB=A", "====", "AAAA====", "AAAAAAAA===="]

    /// Inputs whose `Data(base64Encoded:)` verdict is NOT stable across the OS
    /// versions this app supports (iOS 17.0+ / macOS 14.0+).
    ///
    /// MEASURED 2026-09-04, by running this very corpus in both unit targets:
    /// `"AB=A"` decodes to 2 bytes on macOS 26.1 and iOS 26.1 and is nil on
    /// iOS 18.6.
    ///
    /// Found by the shared corpus on its first cross-platform run, which is what
    /// one corpus compiled into two targets is for. 06-RESEARCH recorded only the
    /// macOS number and could not have seen it. **06-20 found a second instance
    /// of the same class in the padding shapes.**
    ///
    /// **This variance is unobservable in the app**, and that is asserted
    /// rather than assumed: the classifier is the authority, it returns
    /// `.earlyPadding` for this input, and the app therefore never calls the
    /// decoder on it. `TestVectorsTests.theOSVariantInputIsNeverHandedToTheDecoder`
    /// is the assertion that keeps it that way — if a later plan ever
    /// classifies a variant input `.valid`, that test goes red.
    static let foundationOSVariantInputs: Set<String> = ["AB=A"]

    /// The 8 measured percent-encoding inputs.
    ///
    /// Note `"a+b"`: `+` is NOT a space. RFC 3986 percent-encoding is not
    /// form-encoding, and the UI-SPEC's "URL" format is the former.
    static let percentCases: [PercentCase] = [
        PercentCase(input: "a%20b", expected: .decodes("a b"), reason: "the ordinary case"),
        PercentCase(input: "a%2", expected: .badEscape, reason: "truncated escape at end of input"),
        PercentCase(input: "a%zz", expected: .badEscape, reason: "escape digits are not hexadecimal"),
        PercentCase(input: "%", expected: .badEscape, reason: "a bare percent is the whole input"),
        PercentCase(input: "100%", expected: .badEscape, reason: "a bare percent a user did not mean as an escape"),
        PercentCase(input: "a%C3", expected: .badUTF8, reason: "valid escape, truncated UTF-8 sequence"),
        PercentCase(input: "a%FF", expected: .badUTF8, reason: "valid escape, invalid UTF-8 lead byte"),
        PercentCase(input: "a+b", expected: .decodes("a+b"), reason: "plus is NOT a space under RFC 3986")
    ]

    /// Measured CryptoKit digests. The empty-input SHA-256 is the digest shown
    /// in 06-UI-SPEC.md's Hashing mockup, so the spec's example is real.
    ///
    /// Hashing has no failure mode: every String has a UTF-8 encoding and every
    /// byte sequence has a digest. Do not build an error path for it.
    static let digestVectors: [DigestVector] = [
        DigestVector(
            input: "",
            md5: "d41d8cd98f00b204e9800998ecf8427e",
            sha1: "da39a3ee5e6b4b0d3255bfef95601890afd80709",
            sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            sha512: "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce"
                + "47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e"
        ),
        DigestVector(
            input: "hello",
            md5: "5d41402abc4b2a76b9719d911017c592",
            sha1: "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d",
            sha256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
            sha512: "9b71d224bd62f3785d96d46ad3ea3d73319bfbc2890caadae2dff72519673ca7"
                + "2323c3d99ba5c11d7c7acc6e14b8c5da0c4663475c2e5c3adef46f73bcdec043"
        ),
        // Added by 06-04, which needs at least five. The two rows above were
        // measured only against CryptoKit; these first two are ALSO the
        // published vectors of their specifications, so the corpus now
        // contains values that would catch CryptoKit itself being wrong
        // rather than merely catching a change in it. Re-measured through
        // CryptoKit on 2026-09-04 before being written, and re-measured
        // against the live platform on every run by
        // `TestVectorsTests.digestVectorsAreStillWhatCryptoKitProduces`.
        DigestVector(
            input: "abc",
            md5: "900150983cd24fb0d6963f7d28e17f72",
            sha1: "a9993e364706816aba3e25717850c26c9cd0d89d",
            sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            sha512: "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a"
                + "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f"
        ),
        DigestVector(
            input: "The quick brown fox jumps over the lazy dog",
            md5: "9e107d9d372bb6826bd81d3542a419d6",
            sha1: "2fd4e1c67a2d28fced849ee1bb76e7391b93eb12",
            sha256: "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592",
            sha512: "07e547d9586f6a73f73fbac0435ed76951218fb7d0c8d788a309d785436bbb64"
                + "2e93a252a954f23912547d1e8a3b5ed6e1bfd7097821233fa0538f3db854fee6"
        ),
        // Non-ASCII, so a digest taken over the wrong encoding differs. "é" is
        // ONE Character and TWO UTF-8 bytes (C3 A9) — and 0xA9 is the byte
        // both Foundation string APIs on this project have been measured
        // mishandling, which is a coincidence worth having in the corpus.
        DigestVector(
            input: "é",
            md5: "66ddcd97cfdeabb2f6fb8a999b4bc76f",
            sha1: "bf15be717ac1b080b4f1c456692825891ff5073d",
            sha256: "4a99557e4033c3539de2eb65472017cad5f9557f7a0625a09f1c3f6e2ba69c4c",
            sha512: "9e2ad28633f24451bd4f3c1cb20586a21a44c3aeedbdc01b9cc8fa72917ea7bd"
                + "689c82b8bf1fef89b911cf8cc46fa2c1ccc10087b2094fd4d3350ecd88526a2c"
        ),
        // A multi-scalar grapheme: 3 Characters, 27 UTF-8 bytes — the same
        // string `positionCases` uses. A hasher that walked Characters or
        // UTF-16 rather than UTF-8 bytes produces a different digest here and
        // the same digest for every ASCII row above.
        DigestVector(
            input: "a👨‍👩‍👧‍👦b",
            md5: "4ea1b8b17344dee37995309729714d0f",
            sha1: "f369187e6c175d4b39815116cadd2894d884cbe6",
            sha256: "43ea233b1b448e7e2b2c456f6b40908dd404ff891da171e7d8baa54b12bc665c",
            sha512: "ae0fd92f114962b8f35d120c5fd6ce1585a04d8c84f55c893e86bafff4a00ba0"
                + "d41c5f4ed199985246132165c977369d54da973894bb9318fcbd58bc5b1b1d57"
        )
    ]

    /// The nine ISO/epoch inputs from the measured comparison table, the
    /// epoch-boundary probes, and the `Int` overflow.
    static let timestampCases: [TimestampCase] = [
        TimestampCase(input: "2026-09-04T00:00:00Z", expected: .iso8601(1_788_480_000),
                      reason: "the ordinary internet date-time"),
        TimestampCase(input: "2026-09-04T00:00:00.123Z", expected: .iso8601(1_788_480_000.123_000_1),
                      reason: "fractional seconds; the literal is the true Double, .123 is not representable"),
        TimestampCase(input: "2026-09-04T00:00:00+05:30", expected: .iso8601(1_788_460_200),
                      reason: "colon-separated offset (APP-07)"),
        TimestampCase(input: "2026-09-04T00:00:00-0800", expected: .iso8601(1_788_508_800),
                      reason: "compact offset; ISO8601DateFormatter's default options reject this"),
        TimestampCase(input: "2026-09-04T00:00:00", expected: .notISO8601,
                      reason: "no timezone designator"),
        TimestampCase(input: "2026-09-04", expected: .notISO8601,
                      reason: "date only, no time"),
        TimestampCase(input: "20260904", expected: .notISO8601,
                      reason: "basic-format date: D-88 clause 1 DETECTS this as ISO 8601 on shape, "
                          + "but the extended-format parser throws. Reconciling the two is 06-08's job"),
        TimestampCase(input: "2026-09-04 00:00:00Z", expected: .notISO8601,
                      reason: "space instead of T"),
        TimestampCase(input: "2026-13-04T00:00:00Z", expected: .notISO8601,
                      reason: "month 13"),
        TimestampCase(input: "10000000", expected: .epochSeconds(rendersAs: "1970-04-26T17:46:40Z"),
                      reason: "8-digit minimum"),
        TimestampCase(input: "99999999", expected: .epochSeconds(rendersAs: "1973-03-03T09:46:39Z"),
                      reason: "8-digit maximum"),
        TimestampCase(input: "999999999", expected: .epochSeconds(rendersAs: "2001-09-09T01:46:39Z"),
                      reason: "9-digit maximum"),
        TimestampCase(input: "1000000000", expected: .epochSeconds(rendersAs: "2001-09-09T01:46:40Z"),
                      reason: "10-digit minimum"),
        TimestampCase(input: "9999999999", expected: .epochSeconds(rendersAs: "2286-11-20T17:46:39Z"),
                      reason: "10-digit maximum; the whole plausible range for a developer tool"),
        TimestampCase(input: "1788480000000", expected: .epochMilliseconds(rendersAs: "2026-09-04T00:00:00Z"),
                      reason: "13 digits read as seconds land in year 58644 — never what anyone meant"),
        TimestampCase(input: "99999999999999999999", expected: .outOfRange,
                      reason: "Int(...) returns nil; measured, and must be handled")
    ]

    // MARK: - HTML entities (APP-03, assumption A1)

    /// Inputs the HTML round trip `decode(encode(x)) == .success(x)` is
    /// asserted over, one member per property that could break it.
    ///
    /// The last five are the interesting ones: `encode` makes text that is
    /// ALREADY malformed HTML safe, so `"&bogus;"`, `"&copy"` and
    /// `"&#999999999;"` — every one of which `decode` alone refuses by name —
    /// round-trip through the pair unchanged. That is the property a chaining
    /// pipeline needs and it is why the escape set is exactly five characters
    /// rather than all 2125 named references.
    ///
    /// - Note: Lives here rather than in HTMLEntityTests because this file is
    ///   the ONE shared corpus for phase 6's engine work. `HTMLEntityTests`
    ///   asserts this list has at least 10 members before sweeping it, so an
    ///   emptied list fails rather than asserting nothing.
    static let htmlRoundTripSamples: [String] = [
        "",
        "&",
        "<",
        ">",
        "\"",
        "'",
        "&<>\"'",
        "plain text",
        "café",
        "日本語",
        "line1\nline2",
        "  spaced  ",
        "\ttabs\t",
        "a👨\u{200D}👩\u{200D}👧\u{200D}👦b",
        "<b>bold</b>",
        "a & b",
        "&amp;",
        "&bogus;",
        "&copy",
        "&#999999999;"
    ]

    /// The two strings whose three length answers differ, so a test reporting
    /// the wrong unit fails with the wrong unit visible in its message.
    static let positionCases: [PositionCase] = [
        PositionCase(string: "héllo!wörld", characters: 11, utf8: 13, utf16: 11),
        PositionCase(string: "a👨‍👩‍👧‍👦b", characters: 3, utf8: 27, utf16: 13)
    ]
}
