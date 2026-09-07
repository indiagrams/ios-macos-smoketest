// StepCard — the unit the whole UI is made of (D-80, 06-UI-SPEC.md §"The step
// card"). Shared chrome with a swappable body, specified as a REPEATABLE
// element precisely so Phase 7 can append more cards to the same stack without
// touching the chrome.
//
// THREE RULES THIS FILE EXISTS TO KEEP, all of them easy to violate by accident
// and expensive to fix later:
//
// 1. LAYOUT STABILITY. Under D-83 the error state recomputes on EVERY keystroke
//    with no debounce, so a user typing a 40-character Base64 string sees the
//    error state on roughly 39 of those 40 keystrokes. The output block
//    therefore reserves three lines of body text and the diagnostic strip
//    reserves two lines of caption, both through `@ScaledMetric` so they grow
//    with Dynamic Type, and the strip is ALWAYS present rather than being
//    inserted and removed. A keystroke that flips a decode from valid to
//    invalid changes the words in two text views and the visibility of one
//    small glyph. Nothing moves, nothing reflows, nothing recolours.
//
// 2. NO ANIMATION ON RECOMPUTATION. §Motion names five things by name and
//    forbids all of them here: the imperative animation wrapper, the view
//    transition modifier, the content transition modifier, the symbol effect
//    modifier, and re-identifying a view by its input (which would force a
//    rebuild and a fade). Animation is permitted only on a discrete user action
//    — the copy tap, choosing from the add-step menu, a new card appearing —
//    and must be gated on the reduce-motion environment value. Nothing in this
//    file animates, and this plan's acceptance criteria grep for all five.
//
//    THIS COMMENT DELIBERATELY DESCRIBES THOSE FIVE RATHER THAN SPELLING THEM.
//    A file that configures a content gate is also swept by that gate, and this
//    phase has met that shape eleven times; writing the forbidden token into
//    the prose that forbids it turns the gate red against its own explanation.
//
// 3. THE EAGER STACK, NEVER THE LAZY ONE. A lazy container does not materialise
//    off-screen children, so their strings never enter the accessibility tree
//    and plan 06-16's D-93 sweep would silently stop seeing them — a correct
//    check pointed at an incomplete population, which is the failure class this
//    phase exists to stop repeating. Same de-spelling rule as above.
//
// 4. THE FOOTER ROW IS CHROME, NOT SURFACE. Present on every card, in every
//    state, at the same reserved height whether it holds three controls or
//    the root's sentence, and always LAST. Nothing goes above the output
//    section: criterion 5's margin on the smallest supported iPhone is
//    roughly 77 pt against an 88 pt two-hit-target floor, and a header-row
//    cluster would spend more than half of it on every card.
//
// The card's fill, corner radius and padding DO NOT CHANGE with the error
// state, and there is no border, no shadow and no elevation stack: cards are
// distinguished from the background by fill alone.

import SwiftUI

/// What a card's always-present diagnostic strip is saying.
///
/// **There is deliberately no `.none` case.** 06-UI-SPEC.md §Motion requires the
/// strip to be a fixed part of the layout rather than an error container that
/// pops in and out, so it is never empty on any surface in any state: in the
/// valid state it carries result metadata (a count, or the detected format), in
/// the empty state the per-surface prompt, and in the error state the same
/// reason the output block is showing.
///
/// Both cases carry an **already-localized sentence**, not a key. Every
/// diagnostic this app renders takes runtime arguments — a count, a character,
/// a position — and the catalog is keyed by dotted keys rather than by its
/// English text, which is a combination `LocalizedStringKey` cannot express.
/// See `FailureText.swift` for the resolution helper and the full reasoning.
enum DiagnosticContent: Equatable {
    /// The empty and valid states: a prompt, a count, or the detected format.
    case neutral(String)

    /// The error state: the same reason, with the diagnostic glyph beside it.
    case problem(String)
}

/// The card: a header, a swappable body, and exactly one diagnostic strip.
///
/// **Exactly one strip per card, regardless of how many outputs its body has.**
/// The Hashing surface renders four digests inside one card and still shows one
/// strip.
///
/// The generic parameters are named `Content` / `Footer` and their closures
/// `content` / `footer` rather than the `Body` / `body` the UI-SPEC's sketch
/// uses, because both of those names are already taken by `View`'s own
/// associated type and requirement. The note applied to one closure in Phase
/// 6 and applies to both now.
struct StepCard<Content: View, Footer: View>: View {
    /// The composed operation name, rendered `.headline`.
    ///
    /// A `LocalizedStringKey` is right here and only here: an operation name
    /// takes no runtime arguments, and ``Operation``'s raw value **is** its
    /// catalog key, so `StepCard(title: LocalizedStringKey(operation.rawValue))`
    /// renders the same string the add-step menu offered.
    let title: LocalizedStringKey

    /// Always present, never empty. See ``DiagnosticContent``.
    let diagnostic: DiagnosticContent

    /// This card's 1-based place in its surface's stack.
    ///
    /// PASSED, never computed here and never read from the environment: the
    /// surface owns the array. The ordinal it renders is what makes a removal
    /// or a move visible — every number below the edit renumbers in the same
    /// pass, and that is the feedback replacing the animation this phase
    /// deliberately does not have.
    let position: Int

    /// How many cards the stack holds, for the container label's "of N".
    let total: Int

    /// The already-localized operation name, for the container label.
    /// ``title`` cannot serve: a `LocalizedStringKey` is opaque, with no
    /// supported way back to the string it resolves to.
    let operationName: String

    /// The stack-wide accessibility focus — passed ONLY by the call site that
    /// renders the pinned root, and `nil` on every appended card.
    ///
    /// Root-ness stays a CALL-SITE fact here, exactly as ``footer`` already
    /// makes it: no repeated view asks whether it is first. The root's header
    /// is where focus goes when a removal empties the appended stack, because
    /// D-100 leaves the root no controls to land on and dropping focus to the
    /// top of the screen is the failure the focus table exists to prevent.
    let headerFocus: AccessibilityFocusState<StepFocusTarget?>.Binding?

    /// What the footer row holds: ``StepFooter`` on an appended card,
    /// ``StepRootNote`` on the pinned root. WHICH CALL SITE FILLS IT is what
    /// makes D-100's absence a decision rather than a flag inside a repeated
    /// view — the root card is rendered outside the surface's loop, so no
    /// card ever asks whether it is first.
    @ViewBuilder let footer: () -> Footer

    /// The body renderer. Four ship in Phase 6 — `EncodeBody`, `HashBody` and
    /// `TimestampBody` for the three seeded first cards, and
    /// ``SingleOutputBody`` for every appended card.
    @ViewBuilder let content: () -> Content

    /// The footer row's reserved height, growing with Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var scaledFooterHeight = Spacing.iOSHitTarget

    /// 44 pt on iOS, 28 pt on macOS, applied in BOTH footer variants so a root
    /// card and an appended card have identical geometry.
    private var footerHeight: CGFloat {
        #if os(iOS)
            scaledFooterHeight
        #else
            Spacing.macOSHitTarget
        #endif
    }

    /// "Step 2 of 5, Base64 encode" — announced on entering the group, so a
    /// user who lands on a control has the step's identity and its position
    /// without hunting for them.
    ///
    /// `NSLocalizedString` plus a format — ``localizedCount(_:_:)``'s route,
    /// not a `LocalizedStringKey`, which would build a key out of the
    /// interpolated TEXT and miss the dotted key. Neither shipped helper takes
    /// two counts and a string, so their two calls are spelled here.
    private var containerLabel: String {
        String.localizedStringWithFormat(
            NSLocalizedString("step.card.label", comment: ""),
            position, total, operationName
        )
    }

    /// Header, divider, body, divider, strip, divider, footer — in that
    /// order, always. The footer is the last row and nothing goes above the
    /// output section; see rule 4 in this file's header.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                // Visible prose: an identifier, no label override.
                // `.monospacedDigit()` is a numeric variant of the same text
                // style, not a fifth size — it keeps the number from changing
                // width between 9 and 10. The ordinal is fixed and prioritised;
                // the operation name has no line limit and WRAPS.
                Text(verbatim: localizedCount("step.position", position))
                    .monospacedDigit()
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .layoutPriority(1)
                    .accessibilityIdentifier(AccessibilityIdentifiers.Step.position)
                Text(title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(AccessibilityIdentifiers.Step.header)
                    .modifier(RootHeaderFocus(focus: headerFocus))
            }
            Divider()
            content()
            Divider()
            DiagnosticStrip(content: diagnostic)
            Divider()
            footer()
                .frame(maxWidth: .infinity, minHeight: footerHeight, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.lg)
        .background(
            Palette.raisedSurface,
            in: RoundedRectangle(cornerRadius: Spacing.cardRadius, style: .continuous)
        )
        // `.contain` keeps every descendant in the accessibility tree while
        // still giving the container an addressable identity. The forbidden
        // alternative — the other argument this same modifier accepts, the one
        // that discards descendants rather than containing them — deletes them
        // wholesale and would blind plan 06-16's sweep (UI-SPEC Harvest rule 4).
        // It is described and not spelled for the reason in rule 2 of this
        // file's header. RESEARCH assumption A7 asked whether `.contain`
        // disturbs the harvest; this plan's evidence file answers it with
        // measured counts rather than with reasoning.
        .accessibilityElement(children: .contain)
        // The container GAINS a label; it does not replace its children.
        .accessibilityLabel(containerLabel)
        .accessibilityIdentifier(AccessibilityIdentifiers.Step.card)
    }
}

/// The root header's focus anchor, applied only where a binding was passed.
///
/// A modifier rather than an `if` inside the header row, so the two branches
/// resolve to one type and the header keeps its modifier CHAIN — the shape
/// ``RemovalFeedback`` and `CopyFeedback` established for the platform forks.
private struct RootHeaderFocus: ViewModifier {
    /// `nil` on every appended card; the pinned root's binding on exactly one
    /// card per surface.
    let focus: AccessibilityFocusState<StepFocusTarget?>.Binding?

    /// Anchored where there is a binding, untouched where there is not.
    /// `ViewModifier.body(content:)` is declared `@ViewBuilder` by the protocol
    /// itself, so the two branches resolve without repeating the attribute.
    func body(content: Content) -> some View {
        if let focus {
            content.accessibilityFocused(focus, equals: .rootHeader)
        } else {
            content
        }
    }
}

/// The shape the previews below share: an APPENDED card, numbered 2 of 2,
/// with a live footer.
///
/// A preview type rather than five repeated arguments per preview, and an
/// appended card rather than a root one, because the four states below are
/// exactly the four an appended card reaches — and because the footer's
/// enablement being a function of POSITION ONLY is the property most worth
/// seeing beside a `.failure` and a `.blocked` card.
private struct StepCardPreview: View {
    /// The operation name's catalog key.
    let title: LocalizedStringKey

    /// What the strip is saying.
    let diagnostic: DiagnosticContent

    /// The state the one output renders.
    let state: StepRenderState

    /// The footer needs a real binding; a preview has no VoiceOver to move.
    @AccessibilityFocusState private var focus: StepFocusTarget?

    /// The appended card of a two-card stack: move up enabled, move down
    /// disabled at the bottom end, remove enabled in all four states.
    private var position: StepStackPosition {
        StepStackPosition(appendedIndex: 0, appendedCount: 1, modelOffset: 0)
    }

    /// Card two of two: move up enabled, move down disabled at the bottom
    /// end, remove enabled in every one of the four states.
    var body: some View {
        StepCard(
            title: title,
            diagnostic: diagnostic,
            position: 2,
            total: 2,
            operationName: "Base64 encode",
            headerFocus: nil,
            footer: { StepFooter(position: position, focus: $focus, onMoveUp: {}, onMoveDown: {}, onRemove: {}) },
            content: { SingleOutputBody(state: state, onAddStep: { _ in }) }
        )
        .padding()
    }
}

#Preview("Empty") {
    StepCardPreview(
        title: "op.base64.encode",
        diagnostic: .neutral("Enter text above to see the result."),
        state: .empty
    )
}

#Preview("Valid") {
    StepCardPreview(title: "op.base64.encode", diagnostic: .neutral("8 characters"), state: .value("aGVsbG8="))
}

#Preview("Error") {
    StepCardPreview(
        title: "op.base64.decode",
        diagnostic: .problem(failureText(.unexpectedCharacter("!", position: 12))),
        state: .failure(.unexpectedCharacter("!", position: 12))
    )
}

#Preview("Blocked") {
    StepCardPreview(title: "op.hash.sha256", diagnostic: .neutral(blockedStepText()), state: .blocked)
}

/// The pinned root, which is the only card that carries a header focus anchor.
private struct StepRootCardPreview: View {
    /// The root header is a focus target; the binding has to exist to anchor it.
    @AccessibilityFocusState private var focus: StepFocusTarget?

    /// Ordinal 1, the note instead of the three controls, and the anchor.
    var body: some View {
        StepCard(
            title: "op.base64.encode",
            diagnostic: .neutral("8 characters"),
            position: StepStackPosition.rootOrdinal,
            total: 2,
            operationName: "Base64 encode",
            headerFocus: $focus,
            footer: { StepRootNote() },
            content: { SingleOutputBody(state: .value("aGVsbG8="), onAddStep: { _ in }) }
        )
        .padding()
    }
}

#Preview("The pinned root") {
    StepRootCardPreview()
}
