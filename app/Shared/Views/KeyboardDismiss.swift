// KeyboardDismiss — the two affordances that let the iOS software keyboard be
// put away again (GAP-06-01, plan 06-19).
//
// WHY THIS IS A FILE AND NOT FOUR LINES IN `InputArea.swift`. The toolbar half
// belongs to the input block and the scroll half belongs to each surface's
// `ScrollView`, so the two halves have no single call site — but they are one
// decision and they fail together, and splitting the reasoning across four files
// is how one of them quietly gets removed. (`InputArea.swift` is also 345 lines
// against `swiftlint --strict`'s effective 400-line file limit — `--strict`
// promotes every rule's WARNING threshold to the error limit, UL-056 — so this
// would not have fitted there anyway.)
//
// WHY BOTH, WHEN EITHER ALONE READS AS ENOUGH. Each covers the other's hole.
// `.scrollDismissesKeyboard(.interactively)` needs content that actually
// scrolls: on a short screen with nothing to scroll there is no gesture to make
// and the user is stuck again. The toolbar control hangs off the keyboard
// itself, so it is present whatever the content height, and it is the one route
// that works with no gesture vocabulary at all. The user chose both, having been
// told the toolbar costs a catalog string; this file is that choice.
//
// THE TOOLBAR IS iOS-ONLY AND THE GUARD IS MEASURED, NOT ASSUMED.
// `ToolbarItemGroup(placement: .keyboard)` is an iOS placement; macOS has no
// software keyboard for it to attach to and no way to raise one. The `#if`
// wraps whole extensions rather than sitting inside a function body, so neither
// platform's opaque return type is decided by a preprocessor branch and
// SwiftFormat's `redundantReturn` has no `return` inside a `#if` to reason
// about.
//
// THE SCROLL HALF IS **NOT** GUARDED, and that is also measured rather than
// assumed: `scrollDismissesKeyboard(_:)` is available from macOS 13 and this
// app's floor is macOS 14, so it compiles on both platforms and does nothing on
// the one with no software keyboard. A `#if` there would have been a second
// branch to keep in step for no gain.
//
// NEITHER HALF IS A `TextField` SUBMIT ACTION, and that is the actual defect
// being fixed. `InputArea`'s field is `axis: .vertical`, so Return inserts a
// newline — which is right for a multiline field and is precisely why there was
// no way out. A `.submitLabel(.done)` / `onSubmit` pair would have to take
// Return away from the user to work.

import SwiftUI

#if os(iOS)

    extension View {
        /// Puts a Done control on the software keyboard's toolbar, which clears
        /// `focus` and so resigns first responder.
        ///
        /// Resigning first responder is the only thing that actually dismisses
        /// the keyboard, and a `@FocusState` binding is SwiftUI's only supported
        /// way to ask for it — hence the binding rather than a closure.
        ///
        /// The identifier comes from ``AccessibilityIdentifiers/Input/done`` and
        /// is never spelled here: `app/UITests/KeyboardDismissTests.swift`
        /// addresses this control by that constant and never by the word on it,
        /// which is what keeps the suite working in another language.
        func keyboardDismissToolbar(focus: FocusState<Bool>.Binding) -> some View {
            toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    // Trailing edge: the conventional place for a keyboard
                    // toolbar's confirm control, and it keeps the control away
                    // from the leading-edge typing-prediction bar.
                    Spacer()
                    Button("input.done") {
                        focus.wrappedValue = false
                    }
                    .accessibilityIdentifier(AccessibilityIdentifiers.Input.done)
                }
            }
        }
    }

#else

    extension View {
        /// No software keyboard on this platform, so nothing to put away.
        ///
        /// The signature is identical to the iOS one so `InputArea` has a single
        /// unconditional call site: the platform difference lives here, once,
        /// rather than as an `#if` around a view modifier in a `body`.
        func keyboardDismissToolbar(focus _: FocusState<Bool>.Binding) -> some View {
            self
        }
    }

#endif

extension View {
    /// The second dismissal route: dragging the content down pushes the keyboard
    /// away with it.
    ///
    /// `.interactively` rather than `.immediately` because the keyboard tracks
    /// the drag and comes back if the gesture is reversed, which is what makes it
    /// safe to attach to a scroll view the user also scrolls for ordinary
    /// reasons. Applied by each of the three surfaces to its own `ScrollView`.
    ///
    /// Compiles and does nothing on macOS — see this file's header.
    func dismissesKeyboardOnScroll() -> some View {
        scrollDismissesKeyboard(.interactively)
    }
}
