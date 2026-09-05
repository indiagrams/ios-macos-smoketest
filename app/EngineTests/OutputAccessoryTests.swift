// OutputAccessoryTests — the copy path, EXECUTED.
//
// A copy button asserted only by a grep over its own source is a file-level
// gate that never exercises the artefact: the grep is green whether or not the
// value ever reaches the pasteboard, and whether or not it reaches it intact.
// So this round-trips a real value through the real system pasteboard, on
// whichever platform the bundle is running on, and reads it back.
//
// T-06-48 (a truncated or prefixed value reaching the pasteboard) is what the
// long-value case is for. Middle truncation is a RENDERING concern; nothing
// truncated may ever reach ``OutputPasteboard``.
//
// THE MACOS PASTEBOARD IS THE DEVELOPER'S OWN CLIPBOARD. These unit bundles are
// host-based, so `NSPasteboard.general` here is the same pasteboard the person
// running the suite is using. Each case therefore saves the existing string
// contents first and puts them back afterwards, whether or not it passed.

import Testing

#if os(iOS)
    import UIKit
#endif

#if os(macOS)
    import AppKit
#endif

/// The pasteboard write behind the copy control (D-86).
@Suite("Output accessory")
struct OutputAccessoryTests {
    /// Read the general pasteboard's string contents, or `nil`.
    @MainActor
    private func pasteboardString() -> String? {
        #if os(iOS)
            UIPasteboard.general.string
        #elseif os(macOS)
            NSPasteboard.general.string(forType: .string)
        #endif
    }

    /// Put `value` back, so a developer's clipboard survives the suite.
    @MainActor
    private func restore(_ value: String?) {
        guard let value else { return }
        OutputPasteboard.write(value)
    }

    /// A value written by the copy control comes back off the pasteboard
    /// byte for byte.
    @MainActor
    @Test("the copy control's write round-trips through the system pasteboard")
    func theCopyWriteRoundTrips() {
        let previous = pasteboardString()
        defer { restore(previous) }

        OutputPasteboard.write("aGVsbG8=")
        #expect(pasteboardString() == "aGVsbG8=")
    }

    /// A long value is not truncated, prefixed or otherwise adjusted on its
    /// way to the pasteboard — the display concern never reaches the write.
    @MainActor
    @Test("a long value reaches the pasteboard untruncated")
    func aLongValueReachesThePasteboardUntruncated() {
        let previous = pasteboardString()
        defer { restore(previous) }

        let digest = DigestCodec.sha512("hello")
        #expect(digest.count == 128)
        OutputPasteboard.write(digest)
        #expect(pasteboardString() == digest)
    }

    /// A second copy replaces the first rather than appending to it, which is
    /// what `clearContents()` before `setString(_:forType:)` buys on macOS.
    @MainActor
    @Test("a second copy replaces the first")
    func aSecondCopyReplacesTheFirst() {
        let previous = pasteboardString()
        defer { restore(previous) }

        OutputPasteboard.write("first")
        OutputPasteboard.write("second")
        #expect(pasteboardString() == "second")
    }
}
