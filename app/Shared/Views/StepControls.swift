// StepControls — the ONE implementation of the step card's footer: the
// move-up / move-down / remove cluster an APPENDED card carries, and the note
// that stands in its place on the pinned root (D-99, D-100, D-101,
// 07-UI-SPEC.md §"The Step Control Cluster").
//
// ONE IMPLEMENTATION, SHARED BY ALL THREE SURFACES. Encode, Hashing and
// Timestamps render the same footer out of this file. A per-surface copy is
// precisely how three surfaces drift, and rule AA below is FIVE normative
// clauses — a layout that satisfies four of five fails the contract — so
// there is one place to get it right and one place to fix it.
//
// WHY PLACEMENT IS THE ENTIRE MITIGATION. D-101 gives remove no confirmation
// and no undo. What stands between a mis-tap and lost work is the five
// separations of rule AA, and three of them are decided in this file:
//
//   AA-1, DIFFERENT ROW. The remove control lives in the card FOOTER, below
//   the diagnostic strip and its divider; every add-step control lives in
//   the card BODY, above it. No view builder in this app contains both an
//   add-step identifier and the remove identifier, so this file holds no
//   add-step control of any kind and must never gain one.
//
//   AA-4, DIFFERENT GLYPH FAMILY. Remove is `trash`. It is FORBIDDEN to be a
//   minus or a cross enclosed in a circle, because the add-step control is a
//   circle-enclosed plus and a circle-enclosed minus is its exact visual
//   mirror — muscle memory is a SHAPE memory before it is a position memory.
//   THE FORBIDDEN FAMILY IS DESCRIBED HERE AND NEVER SPELLED: a later plan
//   greps `app/Shared/` for those symbol names, and a file that configures a
//   content gate is swept by that gate. Same rule, and the same reason, as
//   `OutputAccessory.swift:34-36` applies to its own forbidden modifier.
//
//   AA-5, DIFFERENT HUE. Remove is ``Palette/destructive``; the add-step
//   control keeps the accent. Neither may take the other's colour, and the
//   accent role is not named anywhere in this file.
//
// AA-2 (different column — this cluster leading, the output accessory
// trailing) and AA-3 (an 88 pt centre-to-centre floor to the nearest
// add-step control) are properties of the ASSEMBLED card rather than of this
// file, and plan 07-10 asserts both from real frames at runtime.
//
// INTRA-CLUSTER SEPARATION IS NORMATIVE, NOT DECORATIVE. The order is move
// up, move down, remove. The gap inside the move pair is ``Spacing/sm``; the
// gap BEFORE remove is ``Spacing/xl``, three times as wide. Two consequences,
// both intended: remove is never the first control in the cluster, so an
// off-by-one slip from the leading edge lands on a REVERSIBLE action; and
// remove's only in-cluster neighbour is move down, whose mistaken activation
// is undone by one tap on move up.
//
// NOTHING IN THIS FILE ANIMATES. §Motion puts removal and reorder on the
// no-animation row and names three forbidden modifiers — the imperative
// animation wrapper, the view transition, the content transition — which are
// described and never spelled, for the reason given under AA-4. The leading
// reason is not taste: criterion 2's UI test resolves these repeated
// identifiers BY INDEX, and an animated reorder is a moving hit target
// during exactly the window in which the test must resolve and query
// elements, on runners `06-SIMULATOR-CRASH-FINDINGS.md` has already measured
// to be fragile.
//
// The controls are borderless, like copy and add-step. The reserved
// icon-button corner-radius token stays unused, and `Spacing.swift` records
// that as a decision rather than an omission: three bordered icon buttons
// out of five would read as an accident rather than as emphasis.
//
// This file needs no manifest edit — both generators sweep `Shared/**`.

import SwiftUI

/// The footer of an APPENDED card: move up, move down, remove.
///
/// The mirror of ``OutputAccessory``'s parameter shape — two enablement flags
/// and the closures the surface wires to `model.<surface> =
/// model.<surface>.moving(from:to:)` / `.removing(at:)`, assignment rather
/// than in-place mutation, which is what `@Observable` sees.
///
/// **It takes no index and computes none.** Enablement is decided by the
/// caller from the card's position in the stack, because the surface owns the
/// array. **Absence on the root is a different CALL SITE, not a flag:** the
/// root card renders ``StepRootNote`` instead, so there is no boolean here
/// asking a repeated view which card it is.
///
/// **Reserved height is owned by ``StepCard``**, which gives its footer slot
/// the platform hit target as a minimum in both variants. A root card and an
/// appended card therefore have identical geometry by construction, and
/// nothing is collapsed where a control would have been.
struct StepFooter: View {
    /// `false` on the topmost appended card. The control is then
    /// `.disabled(true)` and PRESENT, never removed by a conditional.
    ///
    /// **The ends rule, and why it extends D-100 rather than contradicting
    /// it.** A control is ABSENT when its action is impossible for the whole
    /// life of the pipeline — a property of the STEP, which is why the pinned
    /// root has no footer controls at all. A control is PRESENT and disabled
    /// when its action is impossible only for the card's current POSITION.
    /// D-100's reason ("a disabled button that does nothing when pressed is a
    /// worse signal than no button") is true of a button that will NEVER do
    /// anything; a SwiftUI disabled button is not silent — it is visibly
    /// dimmed and VoiceOver announces it as dimmed, which is a correct signal
    /// for a temporary positional fact.
    ///
    /// Using absence for a positional fact would make controls JUMP BETWEEN
    /// CARDS as the stack changes — move down would occupy move up's screen
    /// position on the topmost card — which is exactly the positional
    /// instability D-101's mitigation depends on not existing. It would also
    /// make `Step.moveUp` resolve to a different card than `Step.moveDown` at
    /// the same index, quietly corrupting criterion 2's own test.
    let canMoveUp: Bool

    /// `false` on the last card. Same rule, mirrored.
    let canMoveDown: Bool

    /// Swap this step with the one above it.
    let onMoveUp: () -> Void

    /// Swap this step with the one below it.
    let onMoveDown: () -> Void

    /// Drop this step. There is no confirmation and no undo (D-101); the
    /// mitigation is this file's placement, glyph and hue, not a dialog.
    ///
    /// Remove carries no enablement flag on purpose. A failing step and every
    /// step blocked beneath it are exactly the cards a user needs to clear,
    /// so remove is enabled in EVERY render state — the named narrowing of
    /// Phase 6's State Contract 4.
    let onRemove: () -> Void

    /// Bumped after a removal completes. Drives the iOS haptic and nothing
    /// else; a move never bumps it.
    @State private var removalGeneration = 0

    /// The iOS hit target, growing with Dynamic Type. Applied to the HIT AREA
    /// only; every glyph stays at its text-style size.
    @ScaledMetric(relativeTo: .body) private var scaledTapTarget = Spacing.iOSHitTarget

    /// 44 pt on iOS, 28 pt on macOS — the two declared exceptions in
    /// ``Spacing``, consumed unchanged. Identical to ``OutputAccessory``'s.
    private var hitTarget: CGFloat {
        #if os(iOS)
            scaledTapTarget
        #else
            Spacing.macOSHitTarget
        #endif
    }

    /// One row while it fits, two rows when it does not.
    ///
    /// Both branches are built from the SAME three button subviews, declared
    /// once below, so they carry identical strings by construction (Harvest
    /// rule 5) rather than by two authors agreeing. Rule AA holds in both:
    /// remove stays in the footer, stays leading-aligned, stays below every
    /// add-step control, and in the second branch it is FURTHER from them
    /// than in the first — the reflow can only strengthen the mitigation.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            singleRow
            reflowedRows
        }
        .modifier(RemovalFeedback(trigger: removalGeneration))
    }

    /// Move up, 8 pt, move down, 24 pt, remove.
    ///
    /// The gaps are leading padding on the two trailing controls rather than
    /// stack spacing, because one stack cannot carry two different gaps and
    /// arithmetic on two tokens would invent a third value.
    private var singleRow: some View {
        HStack(spacing: 0) {
            moveUpButton
            moveDownButton
                .padding(.leading, Spacing.sm)
            removeButton
                .padding(.leading, Spacing.xl)
        }
    }

    /// Row one: move up, 8 pt, move down. Row two: remove, further away than
    /// it was in ``singleRow``.
    private var reflowedRows: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: 0) {
                moveUpButton
                moveDownButton
                    .padding(.leading, Spacing.sm)
            }
            removeButton
        }
    }

    /// An arrow rather than a chevron: an arrow names an action, a chevron
    /// names a disclosure, and there is no disclosure here.
    ///
    /// The ends rule is spelled here as `.disabled(!canMoveUp)` on the button
    /// itself. There is no conditional around it: on the topmost appended
    /// card this control is dimmed, and it is still in the accessibility
    /// tree for the sweep and for criterion 2 to resolve by index.
    private var moveUpButton: some View {
        iconButton(
            symbol: "arrow.up",
            tint: .primary,
            label: "step.moveUp",
            identifier: AccessibilityIdentifiers.Step.moveUp,
            action: onMoveUp
        )
        .disabled(!canMoveUp)
    }

    /// The mirror of ``moveUpButton``, and remove's only neighbour. Dimmed
    /// on the last card, by the same rule and never by a conditional.
    private var moveDownButton: some View {
        iconButton(
            symbol: "arrow.down",
            tint: .primary,
            label: "step.moveDown",
            identifier: AccessibilityIdentifiers.Step.moveDown,
            action: onMoveDown
        )
        .disabled(!canMoveDown)
    }

    /// The only irreversible control in the app, in the only red in the
    /// palette. See this file's header for the glyph family it may not join.
    ///
    /// **No enablement modifier, deliberately.** Remove is enabled in every
    /// render state, `.failure` and `.blocked` included — those are exactly
    /// the cards a user needs to clear, and a disabled remove there would
    /// make APP-09 false in the one situation that motivates it.
    private var removeButton: some View {
        iconButton(
            symbol: "trash",
            tint: Palette.destructive,
            label: "step.remove",
            identifier: AccessibilityIdentifiers.Step.remove
        ) {
            onRemove()
            // The closure returned, so the removal happened: every
            // arrangement of steps is a legal pipeline and removal cannot
            // fail. This is the only place the haptic trigger moves.
            removalGeneration += 1
        }
    }

    /// The shipped icon-button chain, factored so all three controls are
    /// the same control with different arguments.
    ///
    /// Only the FRAME is the hit target; the glyph renders at its text-style
    /// size. The label is a catalog key resolved as a `LocalizedStringKey`,
    /// the same treatment the copy control's two labels get.
    ///
    /// Enablement is NOT a parameter here: the two moves attach their own
    /// `.disabled(_:)` and remove attaches none, which keeps the difference
    /// between a positional fact and a permanent one at the call site where
    /// it can be read, rather than behind a flag.
    private func iconButton(
        symbol: String,
        tint: Color,
        label: LocalizedStringKey,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: hitTarget, height: hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

/// The pinned root's footer: a sentence where the three controls stand.
///
/// D-100 removes remove and both moves from the root card entirely. Absence
/// on its own reads as a rendering bug, and three things turn it into a
/// statement: this sentence, the step ordinal in every header, and card
/// geometry that is identical to an appended card's. It is the answer a
/// reviewer gets to *"why can't I delete the first one?"* without opening a
/// support page.
///
/// Visible prose, so it carries an identifier and NO accessibility-label
/// override — Harvest rule 3 forbids overriding a string the user can read.
/// Same treatment as `DiagnosticStrip.swift:62-65`, without the monospace.
struct StepRootNote: View {
    /// Leading, `.caption`, `.secondary`, and the full width of the footer
    /// row so the root's geometry matches an appended card's.
    var body: some View {
        Text("step.root")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(AccessibilityIdentifiers.Step.rootNote)
    }
}

/// The iOS haptic on a completed removal, and nothing at all on macOS.
///
/// A modifier rather than an inline platform branch, so the fork is one small
/// declaration instead of a condition inside a modifier chain — the shape
/// `CopyFeedback` established.
///
/// **A move fires nothing.** It is reversible, and a repeat-pressed reorder
/// control would buzz on every tap. Never on macOS, never on an error, never
/// on a keystroke.
private struct RemovalFeedback: ViewModifier {
    /// Changes only when a removal has completed.
    let trigger: Int

    /// `.impact(weight: .medium)` — an acknowledgement, not a celebration.
    func body(content: Content) -> some View {
        #if os(iOS)
            content.sensoryFeedback(.impact(weight: .medium), trigger: trigger)
        #else
            content
        #endif
    }
}
