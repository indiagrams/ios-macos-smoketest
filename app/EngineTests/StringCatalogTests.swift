import Foundation
import Testing

// StringCatalogTests — the string catalog is a RESOURCE, and a resource that
// stops reaching the bundle fails silently: `NSLocalizedString` returns the KEY
// when the lookup misses, so a screen would render "step.blocked" and nothing
// would throw. Every assertion below therefore compares against the sentence
// rather than against non-emptiness, which is what makes a missing catalog show
// up as a failure instead of as a pass.
//
// These run in the two HOST-BASED unit targets, so `Bundle.main` is the app
// bundle and the strings resolve from exactly the resource the app ships.
// Measured: `Bundle.main.bundlePath` ends in `.app` under `-only-testing:
// AppMacOSTests`.

/// The Phase 6 string catalog: the three plural entries, the ten operation
/// titles, and a sample of the keys the three surfaces render from.
@Suite("String catalog")
struct StringCatalogTests {
    /// Resolve `key` the way the app does, with `count` applied to its plural
    /// variation if it has one.
    private func rendered(_ key: String, _ count: Int) -> String {
        String.localizedStringWithFormat(NSLocalizedString(key, comment: ""), count)
    }

    /// Resolve `key` with no format arguments.
    private func rendered(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    /// The three plural entries pick the singular at one and ONLY at one.
    ///
    /// The catalog has never carried a `variations.plural` block before this
    /// plan, so this is the assertion that says the new shape works rather than
    /// merely parses. It discriminates: a flat `"%lld characters"` entry would
    /// render "1 characters" and fail the middle case, and a flat
    /// `"%lld character"` entry would fail the outer two.
    @Test("plural entries select the singular at one, and only at one")
    func pluralEntriesSelectTheSingularOnlyAtOne() {
        #expect(rendered("count.characters", 0) == "0 characters")
        #expect(rendered("count.characters", 1) == "1 character")
        #expect(rendered("count.characters", 2) == "2 characters")

        #expect(rendered("encode.diagnostic.valid", 0) == "0 characters")
        #expect(rendered("encode.diagnostic.valid", 1) == "1 character")
        #expect(rendered("encode.diagnostic.valid", 2) == "2 characters")

        #expect(rendered("hashing.diagnostic.valid", 0) == "0 bytes hashed.")
        #expect(rendered("hashing.diagnostic.valid", 1) == "1 byte hashed.")
        #expect(rendered("hashing.diagnostic.valid", 2) == "2 bytes hashed.")
    }

    /// Every `Operation` raw value resolves to the menu title the UI-SPEC gives
    /// it, in the order `allCases` declares.
    ///
    /// 06-09 made the raw value BE the catalog key so the add-step menu item
    /// and the resulting card's header could not drift apart. That property is
    /// only worth anything if the key is actually in the catalog — which is
    /// what this asserts, over all ten cases rather than over a sample.
    @Test("every operation raw value resolves to its menu title")
    func everyOperationRawValueResolvesToItsMenuTitle() {
        let expected: [Operation: String] = [
            .base64Encode: "Base64 encode",
            .base64Decode: "Base64 decode",
            .urlEncode: "URL encode",
            .urlDecode: "URL decode",
            .htmlEncode: "HTML encode",
            .htmlDecode: "HTML decode",
            .md5: "MD5",
            .sha1: "SHA-1",
            .sha256: "SHA-256",
            .sha512: "SHA-512"
        ]
        #expect(expected.count == Operation.allCases.count)
        for operation in Operation.allCases {
            let title = rendered(operation.rawValue)
            #expect(title == expected[operation], "\(operation.rawValue) resolved to \(title)")
        }
    }

    /// A key from every section of the inventory resolves to its sentence.
    ///
    /// The population is one key per section rather than all of them, because
    /// the whole-inventory diff is done against the UI-SPEC by script and
    /// recorded in this plan's evidence file; what this adds is proof that the
    /// RESOURCE reaches a running bundle, which a file diff cannot show.
    @Test("a key from every section resolves to its sentence")
    func aKeyFromEverySectionResolves() {
        let expected = [
            "shell.destination.encode": "Encode/decode",
            "shell.destination.timestamps": "Timestamps",
            "step.output.label": "Output",
            "step.blocked": "Blocked by an error in an earlier step.",
            "input.useExample": "Use an example",
            "menu.section.encodeDecode": "Encode/decode",
            "encode.output.placeholder": "Output appears here as you type.",
            "encode.error.base64.character":
                "Not valid Base64: unexpected character '%@' at position %lld.",
            "encode.error.url.escape":
                "Not valid percent-encoding: '%%' at position %lld is not followed by two hexadecimal digits.",
            "hashing.diagnostic.empty": "Enter text above to see its digests.",
            "timestamps.readAs.caption":
                "Set automatically from the input. Change it if the detection is wrong.",
            "timestamps.error.range": "Out of range: %@ is outside the dates this app can show."
        ]
        for (key, sentence) in expected {
            let value = rendered(key)
            #expect(value == sentence, "\(key) resolved to \(value)")
        }
    }
}
