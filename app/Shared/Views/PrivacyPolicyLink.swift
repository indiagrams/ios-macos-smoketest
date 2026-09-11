// PrivacyPolicyLink — the in-app route to the published privacy policy
// (META-06, D-117/D-118/D-119/D-120, 08-UI-SPEC.md §"The Privacy Control").
//
// WHY THIS IS A FILE AND NOT TWO LINES IN EACH SHELL. App Review asks for a
// privacy policy link "within the app in an easily accessible manner"
// (guideline 5.1.1(i)), and the two platforms answer it in two different
// chromes — a navigation-bar item on iOS, an app-menu item on macOS. The
// chromes differ. The decision, the URL, the acceptance rule, the identifier
// and the hand-off do not. Split across `RootView.swift` and `App.swift`,
// one half quietly stops following the rule the other half still follows,
// which is the same argument `KeyboardDismiss.swift` records for its own two
// halves.
//
// THE `#if` WRAPS WHOLE TYPES AND NEVER A FUNCTION BODY, which is the shape
// `KeyboardDismiss.swift` established: neither platform's opaque return type
// is decided by a preprocessor branch, and SwiftFormat's `redundantReturn`
// has no `return` inside an `#if` to reason about. There is exactly ONE such
// branch in this file. It wraps one whole type on each side — what the
// control LOOKS like — and nothing else. Presence, acceptance, identifier
// and action are all above it and are shared.
//
// ONE HAND-OFF, WITH NO PLATFORM BRANCH ON IT. `@Environment(\.openURL)`
// exists on both platforms and there is exactly one call site in this file.
// AppKit's workspace API is never spelled: `openURL` reaches it, and one path
// cannot drift from itself. The app makes no request and gains no capability
// — that is D-119, and `test/app_offline_test.rb` is the gate that keeps it
// true. An embedded browser view would have needed the client-networking
// entitlement, turned that gate red, changed what CI's built-bundle
// entitlements job sees, and falsified APP-11, a Phase 6 criterion already
// verified.
//
// THE URL IS NOT WRITTEN HERE. It is read from this build's own `Info.plist`
// under the key named below, which `app/Identity.xcconfig` supplies through
// both generators (plan 08-06). A Swift literal would be a second identity
// source — which `PROJECT.md`'s parameterization constraint refuses — and
// would ship one fork's URL into every other fork.
//
// ABSENCE, NOT DISABLEMENT. The control renders if and only if that value
// parses to a URL whose scheme is exactly `https` and which carries a host;
// otherwise nothing is rendered at all. This is not a breach of
// 06-UI-SPEC.md's State Contract 1: that rule governs controls whose
// enablement tracks USER INPUT — the add-step control is disabled beside an
// empty field because the user can fill it. Nothing a user can do turns an
// empty plist key into a URL, so a permanently disabled control here would be
// dead chrome forever, and upstream ships the slot empty.
//
// THE FAILURE IS MOVED LEFT RATHER THAN SWALLOWED. "No URL" is not a silent
// no-op: `test/built_plist_test.rb` reads the key out of the BUILT bundle on
// both platforms and fails when it is absent, non-`https`, or authority-less.
// A broken link is therefore a build-time red, which is the only place it can
// be caught before a reviewer finds it.
//
// WHAT THIS FILE MUST NOT GROW. Named in prose rather than spelled, because
// this plan's acceptance criteria grep this file for the tokens and a file
// that spells what a gate scans for is swept green by its own source:
//   * no fixed width-and-height box and no inset on the bar item. The system
//     supplies bar-button metrics; copying the output accessory's hit-target
//     box is the named regression plan 08-12 drives red on purpose.
//   * no symbol-size override, no bar-background override, no accent
//     override, no centred bar placement, no label style that shows a title
//     beside the glyph.
//   * no command-key equivalent on macOS and no spoken usage hint on either
//     platform — 08-UI-SPEC.md declines both by name.
//   * no in-app browser view, no sheet, no popover, no fourth destination.
//
// THE macOS TITLE IS VISIBLE PROSE AND IS NOT OVERRIDDEN. AppKit publishes a
// menu item's title; an accessibility-label override there would replace it
// and take the string out of the D-93 harvest — the shape D-111 measured and
// rejected. The override belongs on the iOS control alone, which is icon-only
// and has no visible text of its own to publish.

import SwiftUI

// MARK: - Where the link goes

/// The privacy policy this build points at, resolved once from the app's own
/// `Info.plist`.
///
/// `nil` means the slot was empty or held something this app refuses to open,
/// and `nil` is what makes the control absent rather than disabled.
enum PrivacyPolicyDestination {
    /// The `Info.plist` key `app/Identity.xcconfig` feeds through both
    /// generators (plan 08-06).
    ///
    /// `test/built_plist_test.rb` asserts this key on the BUILT bundle on both
    /// platforms, so a fork that empties the slot fails a gate rather than
    /// shipping a control that opens nothing.
    static let plistKey = "PrivacyPolicyURL"

    /// This build's policy URL, or `nil`.
    static let url: URL? = resolve(Bundle.main.infoDictionary?[plistKey])

    /// The acceptance rule, kept apart from `Bundle` so it is one expression a
    /// reader can check and a test can reach.
    ///
    /// **The scheme is compared as PARSED, never as a prefix of the raw text,
    /// and the host is required.** Both halves are measurements rather than
    /// belt-and-braces. `//` opens a comment at any position in an xcconfig
    /// value, so a plainly written URL collapses to the six characters
    /// `https:` — measured on Xcode 26.1.1 in plan 08-06 — and that string
    /// still parses with a scheme of `https` and no host at all. A prefix test
    /// on the text would accept it; so would a scheme-only test. Decomposing
    /// is what refuses it, which is the same route `test/built_plist_test.rb`
    /// takes for the same value.
    static func resolve(_ raw: Any?) -> URL? {
        guard let text = raw as? String,
              let components = URLComponents(string: text),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              let parsed = components.url
        else { return nil }

        return parsed
    }
}

// MARK: - The affordance

/// The privacy-policy control — or nothing at all.
///
/// **Population: three on iOS, one per destination**, attached once inside
/// `RootView.iOSShell`'s `ForEach` over `Destination.allCases`; **one on
/// macOS**, app-wide, in the app menu after About. D-118 is satisfied
/// structurally rather than by three copies: the `ForEach` body is the one
/// place where "every surface" is a single expression.
///
/// This type owns PRESENCE and nothing else, which is why the button below
/// takes a non-optional `URL`. Two places deciding presence is how a fork ends
/// up with a control that is absent on one platform and dead on the other.
struct PrivacyPolicyLink: View {
    /// Nothing is rendered when no acceptable URL resolved. Not a disabled
    /// control, not an empty box that still takes bar width — nothing. See
    /// this file's header for why that is the right shape here.
    var body: some View {
        if let url = PrivacyPolicyDestination.url {
            PrivacyPolicyButton(url: url)
        }
    }
}

/// The control itself: one action path, one identifier, two faces.
struct PrivacyPolicyButton: View {
    /// The environment's own opener. This is the whole hand-off, and it is the
    /// same expression on both platforms.
    @Environment(\.openURL) private var openURL

    /// Non-optional deliberately — see ``PrivacyPolicyLink``.
    let url: URL

    /// No confirmation, no alert, no interstitial, no haptic, no animation and
    /// no in-app feedback: the system browser coming forward is the feedback,
    /// and nothing in this app's own layout changes.
    ///
    /// The identifier is attached here, to the `Button`, so both platforms
    /// carry the same selector with no platform suffix — which is what lets
    /// one sweep implementation run against both targets. Whether it survives
    /// into a macOS MENU BAR item is an open question 08-UI-SPEC.md records
    /// and plan 08-11 measures; nothing here assumes an answer.
    var body: some View {
        Button {
            openURL(url)
        } label: {
            PrivacyPolicyContent()
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.Shell.privacyPolicy)
    }
}

// MARK: - The one platform split: what the control looks like

#if os(iOS)

    /// iOS: the glyph alone, in a navigation-bar item.
    ///
    /// `hand.raised` is Apple's own privacy glyph in Settings → Privacy &
    /// Security, so the association is already installed in a reviewer's head;
    /// it is an outline symbol like every other glyph this app ships; and it
    /// is SF Symbols 1, far below this app's iOS 17 floor. A shield was
    /// rejected because this app ships a Hashing surface and a shield beside a
    /// digest tool claims something `PrivacyInfo.xcprivacy` does not support.
    ///
    /// **The spoken name is attached HERE, to the glyph, and the catalog key
    /// is the only name this control has.** A `Button` composes its
    /// accessibility element from its label, so the name reaches the bar item;
    /// the identifier stays on the `Button` above. Icon-only is what keeps the
    /// surface name whole at 375 pt — a bar item carrying text competes with
    /// an inline title of "Encode/decode" and can truncate it.
    struct PrivacyPolicyContent: View {
        var body: some View {
            Image(systemName: "hand.raised")
                .accessibilityLabel("app.privacyPolicy")
        }
    }

#else

    /// macOS: the menu item's title IS the control.
    ///
    /// **No accessibility-label override, deliberately** — see this file's
    /// header. Title Case is the platform convention the items around it
    /// already follow ("About", "Services", "Hide Others", "Quit"), and
    /// deviating in a menu is a guideline 2.4.5 tell. No trailing ellipsis:
    /// macOS reserves it for a command that needs further input, and handing a
    /// URL to the browser needs none.
    struct PrivacyPolicyContent: View {
        var body: some View {
            Text("app.privacyPolicy")
        }
    }

#endif
