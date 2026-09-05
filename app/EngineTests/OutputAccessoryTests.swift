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
//
// WHY THIS SUITE IS MACOS-ONLY, AND HOW THAT WAS DECIDED. The identical suite
// was written for iOS first and it MEASURABLY HANGS the iOS unit target. Each
// suite passes on its own — `-only-testing:AppTests/OutputAccessoryTests` is
// green on iOS 17.5, 18.6 and 26.1 — but with it present the whole target hangs
// three runs in four, indefinitely, with no output and ~6 s of CPU in 25
// minutes. Measured on iOS 17.5, 8 full-target runs:
//
//   without this suite   196 tests / 11 suites, then 202 / 12   2 runs, 2 passes
//   with this suite      205 tests / 13 suites                  6 runs, 2 passes
//
// Serializing the suite did not change it, so it is not intra-suite
// parallelism. A host-based unit bundle sharing the simulator's pasteboard
// daemon is simply not a viable place to touch `UIPasteboard.general`, and a
// test that hangs three runs in four is worse than no test: it would time the
// PR out rather than fail it, and the next person would learn to re-run CI.
//
// The iOS copy path is therefore NOT executed here, and this plan's evidence
// records `copy_roundtrip_ios=n/a` with these numbers rather than a flaky
// green. It closes in plan 06-16, whose sweep drives a REAL copy control in a
// UI test — a different execution model, out of process, where the app owns
// its own pasteboard access and the test only observes the label changing from
// "Copy" to "Copied". That walk step already exists (step 6).

import Testing

#if os(macOS)
    import AppKit
#endif

#if os(macOS)

    /// The pasteboard write behind the copy control (D-86).
    @Suite("Output accessory", .serialized)
    struct OutputAccessoryTests {
        /// Read the general pasteboard's string contents, or `nil`.
        @MainActor
        private func pasteboardString() -> String? {
            NSPasteboard.general.string(forType: .string)
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

#endif
