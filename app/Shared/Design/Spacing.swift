import CoreGraphics

// Spacing — the 8-point rhythm, the three corner radii, and the four
// divergences that are DECLARED rather than incidental (06-UI-SPEC.md
// §Spacing Scale, §Platform Divergence rows 3, 4, 5 and 10).
//
// WHY A TOKEN AND NEVER A NUMBER. A literal `16` at a call site is
// indistinguishable from a literal `16` that someone meant to be `12`, and
// the UI-SPEC's rule is that the implementation attaches the token. Every
// padding, gap, inset and radius in this phase resolves through this enum.
//
// WHY THERE IS NO Typography.swift, and why nobody should add one. The
// UI-SPEC's four type roles are SYSTEM text styles — `.headline`, `.body`,
// `.subheadline`, `.caption` — attached directly at the call site, plus
// `Font.system(.body, design: .monospaced)` for values, which is a design
// VARIANT of the same style rather than a fifth size. Wrapping system text
// styles in a fork-owned enum would add a layer that carries no decision,
// and it would make it easy to slip a `Font.system(size:)` literal in behind
// the wrapper — which the UI-SPEC forbids outright, at any size, for any
// text. Sizes are the system's; only spacing and colour are ours.
//
// This file is compiled into both app targets by the `Shared` sources entry
// in app/project.yml and the `Shared/**` glob in app/Project.swift. It needs
// no manifest edit on either side.

/// The spacing scale: an 8-point rhythm where every value is a multiple of 4.
///
/// A caseless `enum` used as a namespace, so there is no initialiser and no
/// instance of it can exist. Same shape as ``AccessibilityIdentifiers``.
public enum Spacing {
    /// 4 pt — gap between an SF Symbol and its adjacent label; gap between a
    /// value and its unit.
    public static let xs: CGFloat = 4

    /// 8 pt — gap between the two icon buttons in an output's trailing
    /// accessory; vertical gap inside a digest row.
    public static let sm: CGFloat = 8

    /// 12 pt — leading/trailing padding of an inner block; grid gutter.
    public static let md: CGFloat = 12

    /// 16 pt — the DEFAULT. Card internal padding, gap between step cards,
    /// the iOS screen horizontal margin, and the gap between the input area
    /// and the step stack.
    public static let lg: CGFloat = 16

    /// 24 pt — gap between labelled control groups inside a card; top inset
    /// below the navigation bar.
    public static let xl: CGFloat = 24

    /// 32 pt — bottom inset under the last step card, so the add-step control
    /// never sits against the safe-area edge.
    public static let xxl: CGFloat = 32

    /// 48 pt — RESERVED, and still deliberately unused.
    ///
    /// - Note: Forward reference AMENDED 2026-09-05 by plan 07-03. Phase 6
    ///   declared this for a History surface it expected in the next phase, and
    ///   07-CONTEXT.md §Phase Boundary puts History at Phase 8+, so naming a
    ///   phase number here had already gone stale. Restated as a SHAPE, which
    ///   cannot rot: this is the section-break token for a LIST-LIKE SURFACE
    ///   that has sections, declared so nobody invents a ninth value. Phase 7
    ///   has no section break — its step stack is one uninterrupted `VStack` —
    ///   so the token stays declared and unused. Using it would mean a section
    ///   break exists somewhere it was never designed.
    public static let xxxl: CGFloat = 48

    /// 12 pt — the step card's corner radius.
    public static let cardRadius: CGFloat = 12

    /// 8 pt — the corner radius of the inner output block inside a card.
    public static let outputRadius: CGFloat = 8

    /// 8 pt — the corner radius of an icon button's hit shape.
    ///
    /// - Note: **RESERVED, and still unused — by DECISION, not by omission**
    ///   (IN-01, 2026-09-05; AMENDED 2026-09-05 by plan 07-03). Phase 6 ships
    ///   no icon button with a visible hit shape: `OutputAccessory`'s copy
    ///   control and the add-step control are borderless. Phase 6 minted this
    ///   for exactly the controls Phase 7 builds — remove-step and the two
    ///   reorder affordances — and Phase 7 MEASURED that question and chose
    ///   BORDERLESS (07-UI-SPEC.md §"Reserved tokens — reconciliation"). Giving
    ///   the three footer controls a visible hit shape would make them the only
    ///   bordered icon buttons in the app, when copy and add-step are
    ///   borderless, and an inconsistency confined to three controls out of
    ///   five reads as an accident rather than as emphasis. The remove
    ///   control's legibility is carried by the five separations of the
    ///   anti-adjacency rule, not by a rectangle. So: read the unused token as
    ///   a recorded decision, not as an oversight. It stays declared, with the
    ///   same value as ``outputRadius``, so a future BORDERED control has
    ///   somewhere to land — and it is NAMED separately so a later change to
    ///   one radius does not silently move the other. Reaching for
    ///   ``outputRadius`` here because the two happen to be 8 is exactly the
    ///   mistake this token prevents.
    public static let iconButtonRadius: CGFloat = 8

    /// 44 pt — the iOS icon-button minimum hit target.
    ///
    /// EXCEPTION, declared: 44 is not on the 8-point scale. It is the HIG
    /// minimum for a touch target, and a control smaller than it is a real
    /// usability failure rather than a stylistic one. Apply it through
    /// `@ScaledMetric(relativeTo: .body)` so it grows with Dynamic Type; the
    /// button's visible glyph stays at its text-style size and only the HIT
    /// AREA is 44.
    public static let iOSHitTarget: CGFloat = 44

    /// 28 pt — the macOS icon-button minimum hit target.
    ///
    /// EXCEPTION, declared: macOS pointer targets are smaller by convention,
    /// and a 44 pt control on the Mac reads as an iOS app ported across —
    /// which is exactly the guideline 2.4.5 signal D-11 exists to avoid. The
    /// difference from ``iOSHitTarget`` is the point, not an inconsistency.
    public static let macOSHitTarget: CGFloat = 28

    /// 20 pt — the macOS screen horizontal margin.
    ///
    /// EXCEPTION, declared: the macOS window content inset convention is 20
    /// where the iOS screen margin is ``lg`` (16). Still a multiple of 4, and
    /// still not on the scale, because it belongs to the platform rather than
    /// to this app.
    public static let macOSScreenMargin: CGFloat = 20

    /// 720 pt — the macOS minimum window width.
    ///
    /// EXCEPTION, declared: below 720 the Timestamps grid cannot show its
    /// representations side by side, and side-by-side is the whole point of
    /// that surface's layout under D-87. This number is a layout requirement
    /// that was measured against content, not a preference.
    public static let macOSMinWindowWidth: CGFloat = 720

    /// 480 pt — the macOS minimum window height, the companion to
    /// ``macOSMinWindowWidth``.
    public static let macOSMinWindowHeight: CGFloat = 480
}
