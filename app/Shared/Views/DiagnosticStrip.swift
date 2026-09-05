// DiagnosticStrip — the caption line under every card's body, ALWAYS present
// (06-UI-SPEC.md §Motion, §"The step card").
//
// The strip is never conditionally inserted or removed; only its content
// changes. That is half of the anti-flicker position — the other half is that
// nothing here animates. See StepCard.swift's header for the whole rule.
//
// WHY THE SENTENCE DOES NOT CHANGE COLOUR. Orange at caption size fails the
// 4.5:1 contrast ratio as text on a light background, so the sentence stays
// `.primary` at full contrast in both states and only a small leading glyph
// distinguishes them. Colour is never the only signal: the sentence names the
// problem in words (WCAG 1.4.1), which is also why the glyph is hidden from
// assistive technology.
//
// WHY THE GLYPH IS ALWAYS LAID OUT. Inserting the glyph only in the problem
// state would shift the sentence sideways on the keystroke that makes an input
// invalid — the exact movement §Motion forbids. It is therefore always in the
// layout and only its opacity differs, so the sentence sits at the same
// horizontal position in every state.

import SwiftUI

/// The always-present diagnostic strip beneath a card's body.
///
/// Takes a ``DiagnosticContent``, which has no empty case, so this view cannot
/// render a blank line.
struct DiagnosticStrip: View {
    /// What the strip is saying. Never empty.
    let content: DiagnosticContent

    /// Two lines of caption text, reserved in both states so the strip's
    /// height is constant.
    @ScaledMetric(relativeTo: .caption) private var reservedHeight: CGFloat = 30

    /// Whether the diagnostic glyph is showing.
    private var isProblem: Bool {
        if case .problem = content {
            return true
        }
        return false
    }

    /// The sentence, identical in shape in both states.
    private var sentence: String {
        switch content {
        case let .neutral(text): text
        case let .problem(text): text
        }
    }

    /// Glyph slot, then sentence. Both always laid out.
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Palette.diagnostic)
                .opacity(isProblem ? 1 : 0)
                // Decorative — the sentence beside it names the problem in
                // words. Mark hidden so VoiceOver doesn't announce
                // "warning, image" on top of a sentence that already says it.
                .accessibilityHidden(true)
            Text(verbatim: sentence)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .accessibilityIdentifier(AccessibilityIdentifiers.Step.diagnostic)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: reservedHeight, alignment: .topLeading)
    }
}
