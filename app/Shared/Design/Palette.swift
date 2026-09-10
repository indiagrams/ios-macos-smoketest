import SwiftUI

#if os(iOS)
    import UIKit
#endif

#if os(macOS)
    import AppKit
#endif

// Palette — the 60/30/10 split expressed as SYSTEM SEMANTIC colours
// (06-UI-SPEC.md §Color, §Platform Divergence row 10).
//
// WHY THIS FILE EXISTS AT ALL. `.systemGroupedBackground` is a UIKit
// semantic and has no AppKit equivalent under that name; `.windowBackgroundColor`
// is an AppKit semantic and has no UIKit equivalent. That asymmetry is the
// entire reason for this type. The per-platform fork therefore lives INSIDE
// each constant's body, never around the whole file: a file-level fork would
// mean two Palettes that can drift, and a caller could not tell which one it
// was compiled against.
//
// ZERO HEX LITERALS. Every value below resolves from the system, so light and
// dark, increased contrast and the user's own accent choice are all correct by
// construction rather than by a second hand-written palette.
//
// This file is compiled into both app targets by the `Shared` sources entry in
// app/project.yml and the `Shared/**` glob in app/Project.swift. It needs no
// manifest edit on either side, and it adds no resource.

/// The app's colour roles, each resolved from a system semantic colour.
///
/// A caseless `enum` used as a namespace — no initialiser, no instance. The
/// members are computed `static var`s rather than stored `static let`s so the
/// per-platform fork can live inside a body and so the type introduces no
/// mutable global state for Swift 6's concurrency checking to reason about.
///
/// TWO DECISIONS RECORDED HERE, WITH THEIR REASONS, because both are the kind
/// of absence a later reader would otherwise "fix":
///
/// **1. No custom `AccentColor` asset is added — deliberately.** `Color.accentColor`
/// with no asset follows the user's own System Settings → Appearance accent on
/// macOS. Overriding that with a brand colour is one of the recognised tells of
/// an iOS app ported to the Mac, which is precisely the guideline 2.4.5 risk
/// D-11 exists to manage. The absence of the asset IS the decision, not an
/// omission. It also keeps `app/*/Assets.xcassets` untouched, which matters
/// mechanically: Tuist lists resources explicitly while XcodeGen sweeps the
/// directory, so a new asset would ship under one generator and vanish under
/// the other, and `tools/identity-parity.rb` compares identity keys only and
/// cannot see that drift.
///
/// Accent is reserved for exactly four things: the add-step control's symbol
/// and title; the copy control's confirmation checkmark for the 1.2 s it is
/// shown; the selected segment of a `.segmented` `Picker` (system-supplied);
/// and the macOS keyboard focus ring (system-supplied). Nothing else — not
/// card borders, not section headers, not output text, not navigation tint.
///
/// **2. ``diagnostic`` is the GLYPH ONLY, never text and never a fill.** Under
/// D-83 the error state recomputes on every keystroke with no debounce, so a
/// user typing a 40-character string sees it on roughly 39 of those 40
/// keystrokes. Orange at caption size fails the 4.5:1 contrast ratio as text on
/// a light background, so the diagnostic SENTENCE stays `.primary` at full
/// contrast and does not change colour between the valid and invalid states —
/// nothing about the words flickers. Only a 16 pt leading
/// `exclamationmark.triangle.fill` changes, and it is `.accessibilityHidden(true)`
/// because it is redundant with the sentence beside it, which names the problem
/// in words.
///
/// **3. ``destructive`` is the GLYPH ONLY too, and it is the only red here.**
/// Phase 6's version of this comment said there is no destructive role in this
/// palette, because Phase 6 had no destructive action, and that remove-step is
/// APP-09 and belongs to Phase 7. Phase 7 is now: that sentence is AMENDED
/// here, 2026-09-05 (plan 07-03), in the same edit that makes it false, rather
/// than left to rot into a forward reference nobody re-reads. The role is
/// filled by ``destructive``, and the restriction it lands with is the same
/// shape as ``diagnostic``'s — the remove control's glyph, never a fill, never
/// a border, never text, never a card outline, exactly one control per APPENDED
/// card. **The accent reserved-for list above is UNCHANGED**: remove is not one
/// of its four items and must never be accent-coloured.
public enum Palette {
    /// Dominant (60%) — the scene background behind the scroll content, set
    /// once at the root of each surface.
    public static var surface: Color {
        #if os(iOS)
            Color(uiColor: .systemGroupedBackground)
        #elseif os(macOS)
            Color(nsColor: .windowBackgroundColor)
        #endif
    }

    /// Secondary (30%) — the step card fill and the input field fill, one step
    /// forward of ``surface``.
    public static var raisedSurface: Color {
        #if os(iOS)
            Color(uiColor: .secondarySystemGroupedBackground)
        #elseif os(macOS)
            Color(nsColor: .controlBackgroundColor)
        #endif
    }

    /// The inner output block's fill, one step further back than
    /// ``raisedSurface``.
    ///
    /// On macOS this resolves to the same control background as
    /// ``raisedSurface``: AppKit has no third grouped-background tier, and
    /// inventing one from a hex value would be the first hex literal in the
    /// app. The block is separated from the card by its corner radius and its
    /// padding instead.
    public static var recessedSurface: Color {
        #if os(iOS)
            Color(uiColor: .tertiarySystemGroupedBackground)
        #elseif os(macOS)
            Color(nsColor: .controlBackgroundColor)
        #endif
    }

    /// The error glyph's tint — the ONLY place this hue appears.
    ///
    /// Never the error text, never a fill, never a border. See the type's
    /// documentation for why.
    public static var diagnostic: Color {
        Color.orange
    }

    /// The remove control's glyph tint — the ONLY red in the app.
    ///
    /// Never a fill, never a border, never text, never a card outline. Exactly
    /// one control per APPENDED card carries it; under D-100 the root card has
    /// no remove control at all, so the root card carries no red.
    ///
    /// **Why the hue is spendable here and was not in Phase 6.** Red means
    /// danger and irreversibility. Phase 6 had no irreversible action, so red
    /// there would have been decoration. Under D-101 removal has NO
    /// confirmation and NO undo — it is the only genuinely irreversible action
    /// in the app — and the hue that means exactly that should be spent on
    /// exactly it. Spending it anywhere else drains the meaning back out.
    ///
    /// **Why the glyph only, exactly as ``diagnostic`` is the glyph only.** Red
    /// as text, or as a large fill at caption metrics on a light background, is
    /// a 4.5:1 contrast risk; and a permanently red REGION on every appended
    /// card would read as an error state rather than as a control. The `trash`
    /// symbol and the "Remove step" accessibility label carry the meaning
    /// without hue, so nothing here depends on colour alone.
    ///
    /// **Never accent.** Accent is the add-step control's signature (see the
    /// reserved-for list in this type's documentation). Giving remove the same
    /// hue would visually equate the app's primary action with its only
    /// irreversible one — D-101's muscle-memory failure expressed in colour
    /// instead of in position.
    public static var destructive: Color {
        Color.red
    }

    /// Hairline separators, where `Divider()` is not what the layout wants.
    ///
    /// - Note: **RESERVED, and still unused** (IN-01, 2026-09-05; forward
    ///   reference AMENDED 2026-09-05 by plan 07-03). Every Phase 6 surface
    ///   separates content with spacing and card edges, so `Divider()` is never
    ///   wanted and neither is this. This comment used to name a PHASE — Phase
    ///   6 reserved the token for a History list it expected next — and
    ///   07-CONTEXT.md §Phase Boundary puts History at Phase 8+, so the promise
    ///   had already gone stale. It is restated as a SHAPE, which cannot rot:
    ///   this is for a hairline between rows in a LIST-LIKE SURFACE. Phase 7 is
    ///   not that surface. Its step-card footer separator is a plain
    ///   `Divider()`, matching the two dividers already inside `StepCard`.
    ///   Declared rather than left to be invented, because the alternative the
    ///   next author reaches for is a hex literal, which the design rule
    ///   forbids by name.
    public static var separator: Color {
        #if os(iOS)
            Color(uiColor: .separator)
        #elseif os(macOS)
            Color(nsColor: .separatorColor)
        #endif
    }
}
