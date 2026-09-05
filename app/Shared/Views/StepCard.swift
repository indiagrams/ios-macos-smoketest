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
/// The generic parameter is named `Content` and the closure `content` rather
/// than the `Body` / `body` the UI-SPEC's sketch uses, because both of those
/// names are already taken by `View`'s own associated type and requirement.
struct StepCard<Content: View>: View {
    /// The composed operation name, rendered `.headline`.
    ///
    /// A `LocalizedStringKey` is right here and only here: an operation name
    /// takes no runtime arguments, and ``Operation``'s raw value **is** its
    /// catalog key, so `StepCard(title: LocalizedStringKey(operation.rawValue))`
    /// renders the same string the add-step menu offered.
    let title: LocalizedStringKey

    /// Always present, never empty. See ``DiagnosticContent``.
    let diagnostic: DiagnosticContent

    /// The body renderer. Four ship in Phase 6 — `EncodeBody`, `HashBody` and
    /// `TimestampBody` for the three seeded first cards, and
    /// ``SingleOutputBody`` for every appended card.
    @ViewBuilder let content: () -> Content

    /// Header, divider, body, divider, strip — in that order, always.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(verbatim: "demo app")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(AccessibilityIdentifiers.Step.header)
            Divider()
            content()
            Divider()
            DiagnosticStrip(content: diagnostic)
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
        .accessibilityIdentifier(AccessibilityIdentifiers.Step.card)
    }
}

/// One output's value area, in whichever of the four states it is in.
///
/// **All four states are named and rendered, and none of them is blank**
/// (06-UI-SPEC.md §"State Contract"). The `switch` below is exhaustive with no
/// catch-all branch, so a fifth state added to ``StepRenderState`` is a compile
/// error here rather than an empty rectangle on a screen. (That branch keyword
/// is described and not spelled, for the reason in this file's header rule 2.)
///
/// The reserved height is the same in all four states, which is what makes a
/// card's height independent of whether its input currently parses.
struct OutputBlock: View {
    /// What this output is showing right now. Never stored, never cached —
    /// `Pipeline.evaluate()` is called fresh, so nothing here can go stale.
    let state: StepRenderState

    /// The per-surface placeholder shown while the pipeline input is empty,
    /// at the same metrics as a real output.
    let placeholder: LocalizedStringKey

    /// Which family of failure sentences this output renders. Only
    /// `.unexpectedCharacter` reads differently between the two; see
    /// ``FailureDomain``.
    var domain: FailureDomain = .text

    /// The identifier attached to the rendered value.
    ///
    /// Defaults to the shared `Step.output`. The Hashing surface overrides it
    /// per digest row (`Hashing.digestMD5` and friends), which is why this is a
    /// parameter rather than a constant.
    var valueIdentifier: String = AccessibilityIdentifiers.Step.output

    /// Three lines of body text, reserved in every state so the card's height
    /// does not change when the input goes from valid to invalid.
    @ScaledMetric(relativeTo: .body) private var reservedHeight: CGFloat = 60

    /// The blocked sentence is centred; every other state is top-leading.
    private var alignment: Alignment {
        state == .blocked ? .center : .topLeading
    }

    /// The four states, exhaustively, with no catch-all branch.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch state {
            case .empty:
                Text(placeholder)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            case let .value(value):
                Text(verbatim: value)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier(valueIdentifier)
            case let .failure(failure):
                // The error REPLACES the output, in the same monospaced body
                // metrics at full contrast, where the value would have been.
                // No stale previous value is left anywhere on screen (D-84).
                Text(verbatim: failureText(failure, in: domain))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier(valueIdentifier)
            case .blocked:
                // No glyph: an earlier step failed, which is not an error of
                // the user's making at THIS step (UI-SPEC §State Contract 4).
                Text("step.blocked")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier(AccessibilityIdentifiers.Step.blocked)
            }
        }
        .frame(maxWidth: .infinity, minHeight: reservedHeight, alignment: alignment)
        .padding(Spacing.md)
        .background(
            Palette.recessedSurface,
            in: RoundedRectangle(cornerRadius: Spacing.outputRadius, style: .continuous)
        )
    }
}

/// The body every APPENDED card uses — one output, one accessory.
///
/// The three seeded first cards have specialised bodies (`EncodeBody`,
/// `HashBody`, `TimestampBody`, built by plans 06-12 and 06-13). Every card the
/// add-step control appends uses this one, which is what lets Phase 7 grow the
/// stack without touching either the chrome or the surfaces.
///
/// The accessory is enabled ONLY in the `.value` state: you cannot copy or
/// chain a value that does not exist. In the other three states both controls
/// stay in the tree and are disabled, never removed.
struct SingleOutputBody: View {
    /// What this step is showing. `.blocked` is reachable here and only here —
    /// the seeded first card of a surface is never blocked.
    let state: StepRenderState

    /// Appends a step seeded with THIS output. The surface wires it to
    /// `Pipeline.appending(_:)` through the app-level model.
    let onAddStep: (Operation) -> Void

    /// The per-surface placeholder for the empty state.
    var placeholder: LocalizedStringKey = "encode.output.placeholder"

    /// Which family of failure sentences this step renders.
    var domain: FailureDomain = .text

    /// The value, when there is one. `nil` in the empty, error and blocked
    /// states — which is exactly when both controls are disabled and when the
    /// macOS copy command has nothing to yield.
    private var copyableValue: String? {
        if case let .value(value) = state {
            return value
        }
        return nil
    }

    /// Output block on the leading side, accessory on the trailing side.
    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            OutputBlock(state: state, placeholder: placeholder, domain: domain)
            OutputAccessory(
                value: copyableValue ?? "",
                isEnabled: copyableValue != nil,
                onAddStep: onAddStep
            )
        }
        .copyableOutput(copyableValue)
    }
}

#Preview("Empty") {
    StepCard(title: "op.base64.encode", diagnostic: .neutral("Enter text above to see the result.")) {
        SingleOutputBody(state: .empty, onAddStep: { _ in })
    }
    .padding()
}

#Preview("Valid") {
    StepCard(title: "op.base64.encode", diagnostic: .neutral("8 characters")) {
        SingleOutputBody(state: .value("aGVsbG8="), onAddStep: { _ in })
    }
    .padding()
}

#Preview("Error") {
    StepCard(
        title: "op.base64.decode",
        diagnostic: .problem(failureText(.unexpectedCharacter("!", position: 12)))
    ) {
        SingleOutputBody(state: .failure(.unexpectedCharacter("!", position: 12)), onAddStep: { _ in })
    }
    .padding()
}

#Preview("Blocked") {
    StepCard(title: "op.hash.sha256", diagnostic: .neutral(blockedStepText())) {
        SingleOutputBody(state: .blocked, onAddStep: { _ in })
    }
    .padding()
}
