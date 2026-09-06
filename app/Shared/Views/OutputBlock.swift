// OutputBlock — the value area every card renders, in all four states, and
// the one-output body every APPENDED card uses (06-UI-SPEC.md §"State
// Contract", D-84).
//
// A COMPANION FILE, NOT A NEW COMPONENT. Both declarations were moved out of
// `StepCard.swift` UNCHANGED by plan 07-08, when deleting that file's
// transitional footer initialiser and giving its previews a real footer left
// it seven lines over SwiftLint's 400-line budget. 07-06 recorded the same
// split as the obvious one and declined it because its own plan forbade
// restructuring the file; 07-08's plan asks for exactly this — a companion
// file rather than a loosened config or trimmed reasoning.
//
// THE SPLIT IS THE ONE THE CODE ALREADY IMPLIED. `StepCard` is the CHROME —
// header, dividers, diagnostic strip, footer slot, container label. What is
// here is what goes INSIDE it: the output's four states, none of them blank
// and none of them stale, at a height that does not change between them.

import SwiftUI

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
