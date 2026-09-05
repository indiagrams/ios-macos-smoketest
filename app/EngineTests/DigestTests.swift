// Tests for app/Shared/Engine/DigestCodec.swift — the four digests (APP-04).
//
// Run via (macOS):
//   xcodebuild test -project app/App.xcodeproj -scheme App-macOS \
//     -configuration Debug -destination 'platform=macOS' \
//     -only-testing:AppMacOSTests/DigestTests \
//     CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
//
// Compiled into BOTH unit-test targets. `-only-testing:` naming an ABSENT
// suite exits 0 printing `** TEST SUCCEEDED **` having run zero tests
// (measured by 06-03), so a green from this file is only evidence when it
// carries an executed test count.
//
// HASHING HAS NO FAILURE MODE, and there is therefore no error path to test.
// Every String has a UTF-8 encoding and every byte sequence has a digest. The
// API shape is asserted by there being no failure case to assert — see
// `everyInputInAHostilePopulationProducesAFullDigest`.
//
// THE TRAP THIS SUITE EXISTS TO CATCH is that CryptoKit's debug printout of a
// digest is NOT hex: it carries an `"<ALG> digest: "` prefix. Measured on
// macOS 26.5.2, the printout of MD5 of "hello" is
// `MD5 digest: 5d41402abc4b2a76b9719d911017c592`. A copy button wired to that
// puts the prefix on the pasteboard.

import CryptoKit
import Foundation
import Testing

/// See PositionTests for why there is no bare `@Suite` attribute.
struct DigestTests {
    // MARK: - The shared corpus

    /// The corpus is populated. A parameterised test over an emptied table
    /// runs zero cases and reports success.
    @Test
    func theCorpusIsPopulated() {
        #expect(TestVectors.digestVectors.count >= 5)
    }

    /// The corpus is not five copies of the same shape: it holds the empty
    /// input, ASCII, non-ASCII and a multi-scalar grapheme, each asserted
    /// separately. A count reached by five ASCII rows would exercise one path.
    @Test
    func theCorpusCoversMoreThanOneShapeOfInput() {
        let inputs = Set(TestVectors.digestVectors.map(\.input))
        #expect(inputs.contains(""), "the empty input is the one vector every specification publishes")
        #expect(inputs.contains("abc"), "the FIPS 180 / RFC 1321 published vector")
        #expect(inputs.contains("hello"))
        #expect(inputs.contains(where: { $0.utf8.count > $0.count }), "no non-ASCII input in the corpus")
        #expect(inputs.count == TestVectors.digestVectors.count, "the corpus contains a duplicate input")
    }

    /// Every corpus row, through all four functions.
    @Test(arguments: TestVectors.digestVectors)
    func theFourDigestsReproduceTheCorpus(_ vector: DigestVector) {
        let label = String(reflecting: vector.input)
        #expect(DigestCodec.md5(vector.input) == vector.md5, "MD5 differs for \(label)")
        #expect(DigestCodec.sha1(vector.input) == vector.sha1, "SHA-1 differs for \(label)")
        #expect(DigestCodec.sha256(vector.input) == vector.sha256, "SHA-256 differs for \(label)")
        #expect(DigestCodec.sha512(vector.input) == vector.sha512, "SHA-512 differs for \(label)")
    }

    // MARK: - Published vectors, written out rather than referenced

    /// The empty-input SHA-256, spelled here as a literal.
    ///
    /// This is also the digest shown in 06-UI-SPEC.md's Hashing mockup, so
    /// this assertion is what makes the spec's example real rather than
    /// decorative.
    @Test
    func theEmptyInputSHA256IsThePublishedVector() {
        let published = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        #expect(published.count == 64, "the literal above is truncated; SHA-256 is 64 hex characters")
        #expect(DigestCodec.sha256("") == published)
    }

    /// The three other published digests of `"hello"`, and the SHA-512 in
    /// full.
    ///
    /// 06-RESEARCH quotes this SHA-512 TRUNCATED, with a trailing ellipsis. It
    /// is written out here at its full 128 characters and its length is
    /// asserted, because a truncated literal pasted from prose is a defect
    /// this project has already met.
    @Test
    func thePublishedHelloVectorsAreReproduced() {
        #expect(DigestCodec.md5("hello") == "5d41402abc4b2a76b9719d911017c592")
        #expect(DigestCodec.sha1("hello") == "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d")
        let sha512 = "9b71d224bd62f3785d96d46ad3ea3d73319bfbc2890caadae2dff72519673ca7"
            + "2323c3d99ba5c11d7c7acc6e14b8c5da0c4663475c2e5c3adef46f73bcdec043"
        #expect(sha512.count == 128, "the literal above is truncated; SHA-512 is 128 hex characters")
        #expect(DigestCodec.sha512("hello") == sha512)
        #expect(DigestCodec.sha512("hello").hasPrefix("9b71d224bd62f3785d96d46ad3ea3d73319bfbc2890caadae2dff72519673ca7"))
    }

    // MARK: - Pitfall 4: the debug printout is not hex

    /// No digest output contains the substring `digest`, which is exactly what
    /// CryptoKit's own printout of a digest would have contributed.
    ///
    /// The trap is MEASURED here, in the same test, rather than asserted about
    /// from memory: the printout really does carry the prefix, and the codec's
    /// answer really is different from it. A regression assertion whose
    /// premise is never checked is a gate that cannot fire.
    @Test
    func noDigestOutputContainsTheSubstringDigest() {
        let printout = String(describing: Insecure.MD5.hash(data: Data("hello".utf8)))
        #expect(printout.contains("digest"), "CryptoKit's printout no longer carries the prefix this test guards against")
        #expect(printout.contains("MD5"))

        for output in Self.allFour(of: "hello") + Self.allFour(of: "") {
            #expect(!output.contains("digest"), "\(String(reflecting: output)) looks like a debug printout")
            #expect(!output.contains(" "), "a digest must contain no space")
            #expect(!output.contains(":"), "a digest must contain no colon")
        }
        #expect(DigestCodec.md5("hello") != printout)
    }

    // MARK: - Shape of the output

    /// Lowercase hex only, for all four functions over a range of inputs.
    @Test
    func everyOutputIsLowercaseHexOnly() {
        let allowed = Set("0123456789abcdef")
        var checked = 0
        for vector in TestVectors.digestVectors {
            for output in Self.allFour(of: vector.input) {
                #expect(!output.isEmpty)
                #expect(output.allSatisfy { allowed.contains($0) },
                        "\(String(reflecting: output)) is not lowercase hex")
                #expect(output == output.lowercased())
                checked += 1
            }
        }
        #expect(checked == TestVectors.digestVectors.count * 4)
        #expect(checked >= 20, "fewer than five vectors were checked")
    }

    /// Each algorithm's own length: 32, 40, 64 and 128 hex characters.
    @Test
    func lengthsAreTheAlgorithms() {
        var checked = 0
        for vector in TestVectors.digestVectors {
            #expect(DigestCodec.md5(vector.input).count == 32)
            #expect(DigestCodec.sha1(vector.input).count == 40)
            #expect(DigestCodec.sha256(vector.input).count == 64)
            #expect(DigestCodec.sha512(vector.input).count == 128)
            checked += 1
        }
        #expect(checked >= 5, "fewer than five vectors were checked")
    }

    /// The four lengths are DIFFERENT from each other, so a codec that wired
    /// all four functions to one algorithm fails here rather than passing four
    /// identical assertions.
    @Test
    func theFourAlgorithmsAreFourDifferentAlgorithms() {
        let outputs = Self.allFour(of: "hello")
        #expect(Set(outputs).count == 4, "two of the four functions returned the same digest")
        #expect(Set(outputs.map(\.count)) == [32, 40, 64, 128])
    }

    // MARK: - Input is hashed as UTF-8 bytes

    /// Non-ASCII hashes its UTF-8 bytes, asserted against a reference computed
    /// here from the bytes themselves rather than against a copied constant.
    @Test
    func nonASCIIHashesItsUTF8Bytes() {
        let bytes: [UInt8] = [0xC3, 0xA9]
        #expect(Array("é".utf8) == bytes)
        let reference = DigestCodec.hexString(Insecure.MD5.hash(data: Data(bytes)))
        #expect(DigestCodec.md5("é") == reference)
        #expect(DigestCodec.sha256("é") == DigestCodec.hexString(SHA256.hash(data: Data(bytes))))
        #expect(DigestCodec.md5("é") != DigestCodec.md5("e"), "the accent made no difference to the digest")
    }

    /// A multi-scalar grapheme hashes all 27 of its UTF-8 bytes. A hasher that
    /// walked Characters or UTF-16 would agree with UTF-8 on every ASCII row
    /// in the corpus and disagree here.
    @Test
    func aMultiScalarGraphemeHashesAllOfItsBytes() {
        let input = "a👨‍👩‍👧‍👦b"
        #expect(input.count == 3)
        #expect(input.utf8.count == 27)
        #expect(DigestCodec.sha256(input) == DigestCodec.hexString(SHA256.hash(data: Data(input.utf8))))
    }

    // MARK: - hexString

    /// `hexString` is total over any byte sequence, including the empty one.
    @Test
    func hexStringIsTotalOverAnySequence() {
        #expect(DigestCodec.hexString([UInt8]()) == "")
        #expect(DigestCodec.hexString([0x00]) == "00")
        #expect(DigestCodec.hexString([0xFF]) == "ff")
        #expect(DigestCodec.hexString([0x0F, 0xF0]) == "0ff0")
        #expect(DigestCodec.hexString([0xDE, 0xAD, 0xBE, 0xEF]) == "deadbeef")
    }

    /// Every one of the 256 byte values renders as two lowercase hex digits,
    /// enumerated rather than sampled — this is the function that would show a
    /// nibble-table off-by-one, and only at one specific byte.
    @Test
    func everyByteValueRendersAsTwoLowercaseHexDigits() {
        var rendered = 0
        for byte in UInt8(0) ... UInt8(255) {
            let hex = DigestCodec.hexString([byte])
            #expect(hex.count == 2, "byte \(byte) rendered as \(String(reflecting: hex))")
            #expect(hex == String(format: "%02x", Int(byte)),
                    "byte \(byte) rendered as \(String(reflecting: hex)) — the nibble table disagrees with Foundation")
            rendered += 1
        }
        #expect(rendered == 256)
    }

    // MARK: - No failure path

    /// A hostile population produces a full digest for every input, with no
    /// failure to handle — which is the assertion that Hashing has no error
    /// path, made by there being nothing to unwrap.
    @Test
    func everyInputInAHostilePopulationProducesAFullDigest() {
        var generator = SeededGenerator(seed: 0x4449_4745_5354_0001)
        var hashed = 0
        var inputs = [
            "", "\u{0}", "\u{FFFD}", "a👨‍👩‍👧‍👦b",
            String(repeating: "é", count: 5000),
            String(repeating: "\u{0}", count: 1000)
        ]
        for _ in 0 ..< 500 {
            inputs.append(generator.randomScalarString(from: Self.scalarPool, maxScalars: 20))
        }
        #expect(inputs.count == 506, "the population is empty or truncated; the loop below would assert little")
        for input in inputs {
            #expect(DigestCodec.md5(input).count == 32)
            #expect(DigestCodec.sha1(input).count == 40)
            #expect(DigestCodec.sha256(input).count == 64)
            #expect(DigestCodec.sha512(input).count == 128)
            hashed += 1
        }
        #expect(hashed == 506)
    }

    /// The codec agrees with CryptoKit called directly, over the same swept
    /// population — so the corpus rows are not the only thing keeping the
    /// wiring honest.
    @Test
    func theCodecAgreesWithCryptoKitOverASweptPopulation() {
        var generator = SeededGenerator(seed: 0x4449_4745_5354_0002)
        var compared = 0
        for _ in 0 ..< 500 {
            let input = generator.randomScalarString(from: Self.scalarPool, maxScalars: 16)
            let data = Data(input.utf8)
            #expect(DigestCodec.md5(input) == DigestCodec.hexString(Insecure.MD5.hash(data: data)))
            #expect(DigestCodec.sha1(input) == DigestCodec.hexString(Insecure.SHA1.hash(data: data)))
            #expect(DigestCodec.sha256(input) == DigestCodec.hexString(SHA256.hash(data: data)))
            #expect(DigestCodec.sha512(input) == DigestCodec.hexString(SHA512.hash(data: data)))
            compared += 1
        }
        #expect(compared == 500)
    }

    // MARK: - Helpers

    /// A pool wide enough to exercise every UTF-8 sequence width.
    private static let scalarPool: [Unicode.Scalar] =
        Array("abz09 \n\u{0}\u{00E9}\u{20AC}\u{65E5}\u{1F44D}\u{FFFD}".unicodeScalars)

    /// The four digests of one input, in the fixed order MD5, SHA-1, SHA-256,
    /// SHA-512.
    private static func allFour(of input: String) -> [String] {
        [
            DigestCodec.md5(input),
            DigestCodec.sha1(input),
            DigestCodec.sha256(input),
            DigestCodec.sha512(input)
        ]
    }
}
