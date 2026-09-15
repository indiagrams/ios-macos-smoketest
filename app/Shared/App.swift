import SwiftUI

#if os(macOS)
    import AppKit
#endif

@main
struct AppMain: App {
    /// UI test override: when launched with `-UITestColorScheme light` or
    /// `-UITestColorScheme dark`, force the SwiftUI scene's preferred color
    /// scheme. Used by AppStoreScreenshotTests to capture light + dark
    /// appearance screenshots WITHOUT calling `XCUIDevice.shared.appearance`,
    /// which has a known cold-simulator timeout flake on GHA macOS runners
    /// (the setter waits for springboard confirmation; on freshly-booted
    /// simulators the confirmation handshake can timeout ~5-10% of runs).
    /// Real users never pass `-UITestColorScheme`, so this is a no-op
    /// outside UI tests — the system's own light/dark preference wins.
    private let forcedColorScheme: ColorScheme? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-UITestColorScheme"),
              i + 1 < args.count else { return nil }
        switch args[i + 1] {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(forcedColorScheme)
                // macOS ONLY in effect, unconditional at the call site: the
                // `#if` lives on the two whole extensions below, so neither
                // platform's opaque return type is decided by a preprocessor
                // branch inside this body. See `KeyboardDismiss.swift`, which
                // established that shape for the same reason.
                .uiTestWindowSize()
                // Inert unless `-UITestPersistenceProbe` is passed; unconditional so the
                // scene's content type, and with it the window's persisted identity
                // (UL-087), is the same with and without the flag.
                .uiTestPersistenceProbe()
        }
        // THE SCENE'S FIRST `.commands`, AND macOS ONLY (D-117, META-06).
        // `CommandGroup(after: .appInfo)` is the standard placement beside
        // About, which is where a Mac user looks for something about the app
        // rather than about the document. 08-UI-SPEC.md forbids answering this
        // on macOS with a window bar item by name: the same widget in both
        // chromes is the ported-iOS tell guideline 2.4.5 punishes, and D-11
        // already paid for two containers rather than one adaptive one.
        //
        // The `#if` wraps the WHOLE modifier and not its contents, so the iOS
        // build has no commands block at all rather than an empty one — and
        // `CommandGroup` is an AppKit-menu construct with no iOS meaning.
        //
        // No key equivalent is claimed, deliberately: 08-UI-SPEC.md declines
        // one by name, because a chord for a link that leaves the app spends
        // system-reserved key space on an action nobody performs twice.
        #if os(macOS)
        .commands {
            CommandGroup(after: .appInfo) {
                PrivacyPolicyLink()
            }
        }
        #endif
    }
}

// MARK: - The window-size UI test override (D-128)

#if os(macOS)

    extension View {
        /// UI test override: when launched with `-UITestWindowSize 1440x900`,
        /// force the hosting window's FRAME to that exact POINT size.
        ///
        /// Real users never pass `-UITestWindowSize`, so this is a no-op
        /// outside UI tests — the window keeps whatever size AppKit and
        /// SwiftUI give it, exactly as before. The argument shape is the one
        /// ``AppMain/forcedColorScheme`` already ships: find the flag in
        /// `CommandLine.arguments`, read the element after it.
        ///
        /// **Why this lives in the app and not in the test.** XCUITest has no
        /// public window-resize API, so the only process that can size the
        /// window is the one that owns it.
        ///
        /// **Why a size at all.** `ci/extract-mac-screenshots.sh`'s
        /// `crop_to_apple_size` picks the LARGEST App-Store-accepted macOS
        /// size that FITS the capture — 2880x1800, 2560x1600, 1440x900,
        /// 1280x800, first fit wins. A window one pixel short therefore yields
        /// a perfectly valid 1440x900 PNG and the run looks green. D-128 locks
        /// 2880x1800, which at a 2.0 backing scale is a 1440x900 POINT window.
        ///
        /// **`Spacing.macOSMinWindowWidth` / `macOSMinWindowHeight` (720/480)
        /// are NOT involved.** They are minimums that 1440x900 clears; a
        /// capture concern must not move a shipped layout constant.
        func uiTestWindowSize() -> some View {
            background(UITestWindowSizer(requested: UITestWindowSize.requested))
        }
    }

    /// `-UITestWindowSize WIDTHxHEIGHT`, parsed once, in points.
    ///
    /// The value is supplied by the caller rather than baked in, so a machine
    /// with a different backing scale produces a legible wrong-size failure in
    /// the measurement step instead of a silently cropped image.
    private enum UITestWindowSize {
        static let flag = "-UITestWindowSize"

        /// The requested POINT size, or nil when the flag is absent or its
        /// value is not a positive `WIDTHxHEIGHT` pair.
        static var requested: CGSize? {
            let args = CommandLine.arguments
            guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
            let parts = args[index + 1].split(separator: "x")
            guard parts.count == 2,
                  let width = Double(parts[0]), let height = Double(parts[1]),
                  width > 0, height > 0 else { return nil }
            return CGSize(width: width, height: height)
        }
    }

    /// Reaches the hosting `NSWindow` so the frame can be set on it.
    ///
    /// A zero-sized backing view in the content's `.background`, which is the
    /// supported route from SwiftUI content to its own window. Nothing is
    /// drawn.
    ///
    /// **INTERNAL, AND IT MUST NOT BE MADE `private` OR `fileprivate`.** This
    /// type sits in the scene's root content type, and SwiftUI on macOS names
    /// the window's persisted identity after that type — the `NSWindow Frame`
    /// and `NSSplitView Subview Frames` defaults keys and its restoration
    /// state. A private type's name renders as `(unknown context at $<addr>)`,
    /// and that address moves with ASLR on EVERY LAUNCH, so every launch got a
    /// new window identity. Measured 2026-09-12: 50 distinct identities in one
    /// preferences file, a fresh key pair per launch; and on the CI runner, once
    /// one launch had saved restorable state, every later launch "restored"
    /// a window no process could match and presented NONE — `windows=0` with a
    /// built menu bar, until `-ApplePersistenceIgnoreState YES` brought it
    /// back in 1.2 s (UL-087). An internal type's name is stable across launches.
    struct UITestWindowSizer: NSViewRepresentable {
        let requested: CGSize?

        func makeNSView(context _: Context) -> UITestWindowSizingView {
            UITestWindowSizingView(requesting: requested)
        }

        func updateNSView(_ nsView: UITestWindowSizingView, context _: Context) {
            // Re-asked on every SwiftUI update pass, because the window can be
            // resized by the framework AFTER the view first joins it. The call
            // is a no-op once the frame already matches, and it is bounded, so
            // it can neither loop nor fight a window it cannot reach.
            nsView.applyRequestedSize()
        }
    }

    /// The backing view, which applies the size the moment it has a window.
    ///
    /// `viewDidMoveToWindow` rather than an async hop: it is called on the main
    /// actor with `window` already non-nil, so no non-Sendable value crosses an
    /// isolation boundary and neither of the two concurrency-safety escape
    /// hatches a Phase 6 criterion forbids is needed anywhere in this file.
    ///
    /// **The two are named in prose and never spelled**, deliberately: the gate
    /// that forbids them greps this file for their literal text, so a comment
    /// explaining the constraint would turn that gate red by existing — the
    /// exact failure `.planning/.continue-here.md` records as blocking. An
    /// async hop here would have needed one of them, which is why the shape of
    /// this method is the constraint's consequence rather than a style choice.
    final class UITestWindowSizingView: NSView {
        /// Enough passes to survive SwiftUI's own post-layout resizes, and few
        /// enough that a window which CANNOT take the size stops being asked and
        /// leaves one legible mismatch line behind instead of a spin.
        private static let maxAttempts = 8

        private let requested: CGSize?
        private var attempts = 0

        init(requesting size: CGSize?) {
            requested = size
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("UITestWindowSizingView is never loaded from a nib")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyRequestedSize()
        }

        /// Sets the window's FRAME to the requested point size, centred.
        ///
        /// **The FRAME, not the content rect.** `setFrame(_:display:)` takes the
        /// frame INCLUDING the title bar; sizing the content rect instead leaves
        /// the window short by the title bar's height, and `crop_to_apple_size`
        /// then silently picks the next size down.
        ///
        /// **The autosave name is cleared FIRST.** A saved autosave frame is
        /// re-imposed by AppKit and defeats `setFrame` outright — silently, which
        /// is the same failure wearing a different coat.
        func applyRequestedSize() {
            guard let requested, let window, attempts < Self.maxAttempts else { return }
            guard window.frame.size != requested else { return }
            attempts += 1

            _ = window.setFrameAutosaveName("")
            let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
            let origin = CGPoint(
                x: visible.midX - requested.width / 2,
                y: visible.midY - requested.height / 2
            )
            window.setFrame(NSRect(origin: origin, size: requested), display: true)

            // Emitted so the override can be OBSERVED rather than assumed: an
            // argument that is read but not applied looks exactly like one that
            // works, right up until the PNG comes out at the wrong size. Only
            // ever reached when the flag was passed, so a real user sees nothing.
            let frame = window.frame
            let content = window.contentLayoutRect
            print(
                "uitest_window attempt=\(attempts) requested=\(requested.width)x\(requested.height)"
                    + " frame=\(frame.width)x\(frame.height)"
                    + " content=\(content.width)x\(content.height)"
                    + " backingScale=\(window.backingScaleFactor)"
                    + " visibleFrame=\(visible.width)x\(visible.height)"
            )
            fflush(stdout)
        }
    }

    // MARK: - The persisted-window-state UI test probe (08.5-08)

    extension View {
        /// UI test measurement: when launched with `-UITestPersistenceProbe`, expose what this
        /// process's OWN defaults domain held at launch as one accessibility value, identifier
        /// ``AccessibilityIdentifiers/Shell/uiTestPersistenceProbe``.
        ///
        /// **Why the app reads it and not the test.** The app is sandboxed, so its domain may live
        /// in its container, and the UI-test runner is a different process. Only the app can prove
        /// which domain it reads. Its standard output never reaches the xcresult, so the value
        /// travels through the accessibility tree instead.
        ///
        /// **Why.** Run 34978692666: `PrivacyLinkTests` passes no window size, yet its worked-value
        /// control sat at the same off-screen x as the 1440-point capture window's, in the
        /// test that runs after the capture suite. The hypothesis is a frame saved under the
        /// window's stable identity (UL-087) and restored. This line is how that gets measured
        /// before anything is fixed. Real users never pass the flag, and it draws nothing.
        func uiTestPersistenceProbe() -> some View {
            background(UITestPersistenceProbeElement(line: UITestPersistenceProbe.line).frame(width: 1, height: 1))
        }
    }

    /// Reads the defaults domain once, the first time the scene body asks.
    enum UITestPersistenceProbe {
        static let flag = "-UITestPersistenceProbe"

        static let line: String? = {
            // VALUED, like every `-UITest*` flag: a bare flag takes the NEXT argument as its value
            // in the argument domain, and on run 34984109925 that was `-settings.selection`,
            // shifting every launch pin after it. `test/app_source_rules_test.rb` enforces the shape.
            let args = CommandLine.arguments
            guard let index = args.firstIndex(of: flag), index + 1 < args.count, args[index + 1] == "YES" else {
                return nil
            }
            let domain = Bundle.main.bundleIdentifier ?? "none"
            let values = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
            let frameKeys = values.keys.filter { $0.hasPrefix("NSWindow Frame") }.sorted()
            let frames = frameKeys.map { "\"\($0)\"=\"\(values[$0] ?? "")\"" }.joined(separator: " ")
            let savedState = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Saved Application State/\(domain).savedState")
            let savedStateExists = savedState.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            return "persistence_probe domain=\(domain) home=\(NSHomeDirectory()) keys=\(values.count) "
                + "window_frame_keys=\(frameKeys.count) saved_state_exists=\(savedStateExists) \(frames)"
        }()
    }

    /// Internal, never private — it enters the scene's root content type (UL-087).
    struct UITestPersistenceProbeElement: NSViewRepresentable {
        let line: String?

        func makeNSView(context _: Context) -> NSView {
            let view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
            guard let line else { return view }
            view.setAccessibilityElement(true)
            view.setAccessibilityRole(.staticText)
            view.setAccessibilityIdentifier(AccessibilityIdentifiers.Shell.uiTestPersistenceProbe)
            view.setAccessibilityValue(line)
            return view
        }

        func updateNSView(_: NSView, context _: Context) {}
    }

#else

    extension View {
        func uiTestPersistenceProbe() -> some View {
            self
        }

        /// No AppKit window to size on this platform, so nothing to do.
        ///
        /// The signature matches the macOS one so the scene above has a single
        /// unconditional call site — the platform difference lives here, once.
        func uiTestWindowSize() -> some View {
            self
        }
    }

#endif
