// RootView — three destinations, each platform in its OWN container (D-11,
// D-82, D-90, 06-UI-SPEC.md §"Navigation shell", §"Platform Divergence").
//
// TWO CONTAINERS, AND A SHARED ADAPTIVE ONE IS FORBIDDEN BY NAME. iOS gets a
// `TabView` with a `NavigationStack` per tab; macOS gets a `NavigationSplitView`
// with a `List` sidebar. The UI-SPEC forbids collapsing the two into one
// adaptive container, and the reason is review risk rather than taste:
// guideline 2.4.5 judges Mac-nativeness, and an app that feels like a ported
// iOS build is a known macOS rejection theme. The two-layout cost is accepted
// by D-11. Neither branch uses the deprecated pre-`NavigationStack` container;
// that type is described here and never spelled, because this plan's acceptance
// criteria grep this file for it.
//
// ONE MODEL FOR THE LAUNCH, CONSTRUCTED HERE AND NOWHERE ELSE (D-82). This is
// the only place in `app/Shared/` that constructs the app-level model, which is
// asserted by grep rather than by convention — previews reach a throwaway one
// through `AppModel.preview`. The trap this closes is specific and is a macOS
// trap: a `NavigationSplitView` swaps its detail view when the sidebar
// selection changes, so anything held INSIDE a surface would be discarded every
// time the user glanced at another tool. Holding it one level up is what makes
// switching destination and coming back restore exactly what was there, and
// `ShellTests.testPipelineSurvivesDestinationSwitch` demonstrates it on both
// platforms rather than asserting it.
//
// THREE DESTINATIONS, NOT FOUR (D-90). Each tool screen IS the pipeline canvas
// (D-09); there is no separate Pipeline destination in Phase 6, and History is
// Phase 7's fourth. APP-10's floor of three is met by three destinations whose
// LAYOUTS are genuinely different (D-87) — a single in→out block, a four-row
// aligned table, and a grid of representation cells — not by the count.
//
// THE MODEL IS PASSED AS AN EXPLICIT PARAMETER, never through the environment.
// One mechanism, stated once: every surface takes `model:`, which makes the
// dependency visible in each call site and keeps a surface constructible in a
// preview and in a test without a host view to inject it.

import SwiftUI

// MARK: - The three destinations

/// One of the app's three destinations.
///
/// The raw value is the `Localizable.xcstrings` key naming the destination, as
/// with ``Operation`` and ``TimestampRepresentation``, so a sidebar row and the
/// navigation title it leads to are one string rather than two that can drift.
enum Destination: String, CaseIterable, Identifiable, Hashable {
    /// `shell.destination.encode` — "Encode/decode".
    case encode = "shell.destination.encode"

    /// `shell.destination.hashing` — "Hashing".
    case hashing = "shell.destination.hashing"

    /// `shell.destination.timestamps` — "Timestamps".
    case timestamps = "shell.destination.timestamps"

    /// Destinations are identified by their catalog key, which is unique.
    var id: String {
        rawValue
    }

    /// The navigation title, on BOTH platforms, and the macOS sidebar label.
    ///
    /// The full name is what the user reads at the top of the screen on either
    /// platform, so the surface name `docs/PRODUCT-IDENTITY.md` records is the
    /// one on screen.
    var titleKey: LocalizedStringKey {
        LocalizedStringKey(rawValue)
    }

    /// The iOS TAB label, which is the same word except in one case.
    ///
    /// **`shell.tab.encode` is the one deliberate string divergence in the app**
    /// (UI-SPEC §"Platform Divergence" row 2), and it is deliberate for a
    /// measured reason: "Encode/decode" is 13 characters and truncates in an
    /// iOS tab item at default Dynamic Type, and worse at accessibility sizes.
    /// The full name is still the navigation title inside the tab. Do not
    /// "fix" this by collapsing the two keys.
    var tabLabelKey: LocalizedStringKey {
        switch self {
        case .encode: "shell.tab.encode"
        case .hashing, .timestamps: titleKey
        }
    }

    /// The SF Symbol beside the label, from the UI-SPEC's table.
    ///
    /// Decorative: the label beside it carries the meaning, which is what makes
    /// the symbol the one class of view UI-SPEC Harvest rule 2 permits to be
    /// hidden from assistive technology — and neither container hides it, so it
    /// costs the harvest nothing either way.
    var symbol: String {
        switch self {
        case .encode: "arrow.left.arrow.right"
        case .hashing: "number"
        case .timestamps: "clock"
        }
    }

    /// The iOS tab item's selector.
    var tabIdentifier: String {
        switch self {
        case .encode: AccessibilityIdentifiers.Shell.tabEncode
        case .hashing: AccessibilityIdentifiers.Shell.tabHashing
        case .timestamps: AccessibilityIdentifiers.Shell.tabTimestamps
        }
    }

    /// The macOS sidebar row's selector.
    ///
    /// A separate set from ``tabIdentifier`` because the two containers are two
    /// different views, not because the identifier carries a platform suffix —
    /// a suffix would mean plan 06-16's sweep had to know which platform it was
    /// running on.
    var sidebarIdentifier: String {
        switch self {
        case .encode: AccessibilityIdentifiers.Shell.sidebarEncode
        case .hashing: AccessibilityIdentifiers.Shell.sidebarHashing
        case .timestamps: AccessibilityIdentifiers.Shell.sidebarTimestamps
        }
    }
}

// MARK: - The shell

/// The app's root: one model, three destinations, one container per platform.
struct RootView: View {
    /// **The one app-level model a launch has** (D-82). Every surface below
    /// reads and writes its own pipeline on this instance, so a destination
    /// change is a change of view and never a change of state.
    @State private var model = AppModel()

    #if os(macOS)
        /// Which sidebar row is showing. Navigation state, not work in
        /// progress — the work lives on the model, one level up from the detail
        /// view the split view swaps.
        @State private var selection: Destination? = .encode
    #endif

    /// The platform's own container. Two branches, deliberately (D-11).
    var body: some View {
        #if os(macOS)
            macOSShell
        #else
            iOSShell
        #endif
    }

    #if os(iOS)
        /// Three tabs, each wrapping its surface in its own navigation stack.
        private var iOSShell: some View {
            TabView {
                ForEach(Destination.allCases) { destination in
                    NavigationStack {
                        surface(destination)
                            .navigationTitle(destination.titleKey)
                            .navigationBarTitleDisplayMode(.inline)
                            .background(Palette.surface)
                    }
                    .tabItem {
                        Label(destination.tabLabelKey, systemImage: destination.symbol)
                    }
                    .accessibilityIdentifier(destination.tabIdentifier)
                }
            }
        }
    #endif

    #if os(macOS)
        /// A sidebar of three rows and a detail area showing the selected one.
        ///
        /// The minimum window is a LAYOUT REQUIREMENT measured against content,
        /// not a preference: below 720 pt the Timestamps grid cannot show its
        /// representations side by side, and side by side is the whole point of
        /// that surface under D-87. Both numbers come from ``Spacing``, where
        /// they are declared exceptions to the 8-point scale.
        private var macOSShell: some View {
            NavigationSplitView {
                List(selection: $selection) {
                    ForEach(Destination.allCases) { destination in
                        Label(destination.titleKey, systemImage: destination.symbol)
                            .accessibilityIdentifier(destination.sidebarIdentifier)
                            .tag(destination)
                    }
                }
                .navigationSplitViewColumnWidth(min: 168, ideal: 200, max: 280)
            } detail: {
                let shown = selection ?? .encode
                surface(shown)
                    .navigationTitle(shown.titleKey)
                    .background(Palette.surface)
            }
            .frame(
                minWidth: Spacing.macOSMinWindowWidth,
                minHeight: Spacing.macOSMinWindowHeight
            )
        }
    #endif

    /// The surface a destination shows.
    ///
    /// Exhaustive over ``Destination`` with no catch-all branch, so a fourth
    /// destination is a compile error here rather than an empty detail area.
    @ViewBuilder
    private func surface(_ destination: Destination) -> some View {
        switch destination {
        case .encode: EncodeSurface(model: model)
        case .hashing: HashingSurface(model: model)
        case .timestamps: TimestampsSurface(model: model)
        }
    }
}

#Preview {
    RootView()
}
