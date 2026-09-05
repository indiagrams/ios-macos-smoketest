// InputArea — the one input block all three surfaces use, plus the two count
// helpers and the appended-card diagnostic every surface shares
// (06-UI-SPEC.md §"Surface anatomy", §"State Contract" item 1, §Typography).
//
// ONE BLOCK, THREE SURFACES. The three surfaces differ in what they DO with a
// piece of text (D-87); they do not differ in how the user gives it to them. A
// second copy of this block would be a second place for the prompt, the count
// and the worked-value button to drift apart, and the divergence table names
// exactly one thing about it that differs between platforms — the field's line
// limit — which is one `#if` rather than one more file.
//
// WHY THE PROMPT IS A REAL `TextField` PROMPT AND NOT A `Text` OVERLAY. Plan
// 06-16's harvest reads `label`, `title`, `placeholderValue` and `value` at
// every node, precisely because a sweep that reads `label` alone misses every
// prompt string — and this app has three of them, one per surface. A prompt
// passed to `TextField(_:text:axis:)` lands in `placeholderValue`; the same
// words drawn as an overlaid `Text` behind the field would not, and worse, it
// would stay on screen behind typed text on some layouts.
//
// WHY "Use an example" IS IN THE CONTRACT AND IS NOT SCOPE CREEP (UI-SPEC
// §"State Contract" item 1). Three things buy it, and only the third is about
// testing: (a) a guideline 4.2 reviewer meets an empty screen on launch, and
// this app's App Review argument needs them to reach a working pipeline
// without guessing an input format; (b) it removes the blank-screenshot
// problem from Phase 8's harnesses; and (c) plan 06-16's sweep needs a
// deterministic way to drive every surface into its populated state so the
// output-state strings enter the accessibility tree at all — one tap on a
// stable identifier is far more robust in an XCUITest walk than typing into a
// text field. The button is visible ONLY while the input is empty.
//
// THE DYNAMIC TYPE CONTRACT, KEPT STRUCTURALLY RATHER THAN BY PROMISE. There
// is no size clamp anywhere in this phase and no literal point size on any
// text: sizes are the system's, and only spacing and colour are ours. Nothing
// here carries a one-line limit and nothing here sits in a fixed-height frame,
// so every label, button title and count WRAPS rather than truncating. Both
// modifiers this paragraph is about are DESCRIBED and never spelled, because
// this plan's acceptance criteria sweep every file in this directory for them
// and a file that configures a content gate is swept by that gate — the shape
// this phase has now met thirteen times. `InputAreaTests` measures the
// remaining risk that wrapping cannot fix: a single unbreakable word wider
// than the narrowest screen this app supports.

import SwiftUI

// MARK: - Per-surface constants

/// The accessibility identifiers one surface attaches to its input area.
///
/// A value rather than three parameters, so a surface cannot pass Hashing's
/// input identifier beside Encode's worked-value button by accident. The three
/// members below are the only three that exist; `AccessibilityIdentifiers`
/// mints no others for this block.
struct InputAreaIdentifiers: Equatable, Sendable {
    /// The text field itself.
    let input: String

    /// The button that fills the field with ``InputExample``'s constant.
    let useExample: String

    /// The count line, where the surface has one.
    ///
    /// `nil` on Timestamps: the UI-SPEC's mockup for that surface shows the
    /// worked-value button alone under the field, because a character count of
    /// a timestamp tells the user nothing. `AccessibilityIdentifiers` mints an
    /// `inputCount` constant for Encode only, which is that same decision
    /// already taken one layer down.
    var count: String?
}

extension InputAreaIdentifiers {
    /// The Encode/decode surface's three.
    static let encode = InputAreaIdentifiers(
        input: AccessibilityIdentifiers.Encode.input,
        useExample: AccessibilityIdentifiers.Encode.useExample,
        count: AccessibilityIdentifiers.Encode.inputCount
    )

    /// The Hashing surface's. Its count line renders and carries no identifier
    /// of its own — nothing in the walk needs to address it, and inventing a
    /// constant that no query uses is how a selector list rots.
    static let hashing = InputAreaIdentifiers(
        input: AccessibilityIdentifiers.Hashing.input,
        useExample: AccessibilityIdentifiers.Hashing.useExample
    )

    /// The Timestamps surface's. No count line at all — see ``count``.
    static let timestamps = InputAreaIdentifiers(
        input: AccessibilityIdentifiers.Timestamps.input,
        useExample: AccessibilityIdentifiers.Timestamps.useExample
    )
}

/// What "Use an example" fills each surface's input with.
///
/// **Chosen to EXERCISE each surface rather than to decorate it**, and recorded
/// verbatim in this plan's evidence file so plan 06-16's walk can assert the
/// resulting output deterministically rather than merely asserting that
/// something appeared.
///
/// A caseless enum used as a namespace, the same shape as ``Spacing``.
enum InputExample {
    /// Encode/decode. Every one of the three formats has real work to do on
    /// it: the `é` is two UTF-8 bytes, so the Base64 is not a byte-per-
    /// character transliteration; the spaces, `&`, `<`, `>` and `!` all move
    /// under percent-encoding; and `&`, `<` and `>` are three of the five
    /// characters the HTML encoder escapes.
    static let encode = "Hello, world & <café>!"

    /// Hashing. Ten characters and TWELVE UTF-8 bytes — the two multibyte
    /// characters are what make the card's "%lld bytes hashed." strip say
    /// something the input's own character count does not, which is the
    /// distinction the digests are actually taken over.
    static let hashing = "naïve café"

    /// Timestamps. Ten digits, so `TimestampDetection.detect` reads it by
    /// clause 2 as Unix-epoch seconds with nothing else in the six-clause rule
    /// able to claim it: the eight-digit calendar-date window cannot match a
    /// ten-digit run, and the thirteen-digit clause cannot either. It is
    /// 2026-01-01T00:00:00Z, comfortably inside the displayable window.
    static let timestamps = "1767225600"
}

/// The horizontal margin between a surface's content and the screen edge.
///
/// Divergence row 3: 16 pt on iOS, 20 pt on macOS. Both come from ``Spacing``
/// — `lg` is the iOS screen margin and `macOSScreenMargin` is the declared
/// exception — so neither number is written at a call site.
enum SurfaceLayout {
    /// The per-platform screen horizontal margin.
    static var horizontalMargin: CGFloat {
        #if os(macOS)
            Spacing.macOSScreenMargin
        #else
            Spacing.lg
        #endif
    }
}

// MARK: - Shared sentence helpers

/// A catalog sentence with one count substituted, plural rule applied.
///
/// The catalog is keyed by dotted keys and every count entry is a real plural
/// variation, which is a combination `LocalizedStringKey` cannot express —
/// interpolating into one builds a key out of the interpolated TEXT and misses
/// the dotted key entirely. See `FailureText.swift` for the full reasoning;
/// callers pass the result to `Text(verbatim:)`.
func localizedCount(_ key: String, _ count: Int) -> String {
    String.localizedStringWithFormat(NSLocalizedString(key, comment: ""), count)
}

/// A catalog sentence that takes no arguments, already localized.
func localizedSentence(key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// The diagnostic strip content for a card the add-step control APPENDED.
///
/// Every appended card on every surface is a text→text step, so all three
/// surfaces share these strings — the same reason ``SingleOutputBody`` defaults
/// its placeholder to `encode.output.placeholder`. The seeded first card of
/// each surface has its own, because each surface's own diagnostic says
/// something different about the thing it produced.
///
/// Exhaustive over the four named states with no catch-all branch, so a fifth
/// state is a compile error here rather than a card with a blank strip. (That
/// branch keyword is described and never spelled in this file, for the reason
/// in the header.)
func appendedStepDiagnostic(for state: StepRenderState) -> DiagnosticContent {
    switch state {
    case .empty:
        .neutral(localizedSentence(key: "encode.diagnostic.empty"))
    case let .value(value):
        .neutral(localizedCount("encode.diagnostic.valid", value.count))
    case let .failure(reason):
        .problem(failureText(reason))
    case .blocked:
        .neutral(blockedStepText())
    }
}

// MARK: - The block itself

/// The pipeline's input: a label, a monospaced field, a count and the
/// worked-value button.
struct InputArea: View {
    /// The surface's pipeline input, written on every keystroke with no
    /// intermediate storage (D-83).
    @Binding var text: String

    /// The per-surface prompt — `encode.input.prompt`, `hashing.input.prompt`
    /// or `timestamps.input.prompt`. Reaches the accessibility tree as the
    /// field's `placeholderValue`; see the file header.
    let prompt: LocalizedStringKey

    /// What the worked-value button fills ``text`` with. One of
    /// ``InputExample``'s three.
    let example: String

    /// Which surface's identifiers to attach.
    let identifiers: InputAreaIdentifiers

    /// The plural count key, or `nil` for a surface with no count line.
    var countKey: String? = "count.characters"

    /// Divergence row 8: the window height affords more lines on the Mac.
    private var lineLimitRange: ClosedRange<Int> {
        #if os(macOS)
            6 ... 16
        #else
            4 ... 12
        #endif
    }

    /// Label, field, then the count-and-button row.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("input.label")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            field
            trailingRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The monospaced, vertically growing text field.
    private var field: some View {
        TextField(prompt, text: $text, axis: .vertical)
            .font(.system(.body, design: .monospaced))
            .textFieldStyle(.plain)
            .lineLimit(lineLimitRange)
            .padding(Spacing.md)
            .background(
                Palette.recessedSurface,
                in: RoundedRectangle(cornerRadius: Spacing.outputRadius, style: .continuous)
            )
            .accessibilityIdentifier(identifiers.input)
    }

    /// The count on the leading side, the worked-value button on the trailing
    /// side — and the button ONLY while the input is empty (State Contract 1).
    private var trailingRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
            if let countKey {
                Text(verbatim: localizedCount(countKey, text.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .modifier(OptionalIdentifier(identifier: identifiers.count))
            }
            Spacer(minLength: 0)
            if text.isEmpty {
                Button("input.useExample") {
                    text = example
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier(identifiers.useExample)
            }
        }
    }
}

/// Attach an accessibility identifier when there is one to attach.
///
/// A modifier rather than an `if` at the call site, so the view itself is
/// never conditionally built — only whether it carries a selector changes. An
/// empty-string identifier would have been the cheap alternative and it is
/// worse: it resolves in a query and matches every other element that also
/// forgot one.
private struct OptionalIdentifier: ViewModifier {
    /// The identifier, or `nil` where the surface mints none.
    let identifier: String?

    /// Identical content either way.
    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

#Preview("Empty — the worked-value button is showing") {
    InputArea(
        text: .constant(""),
        prompt: "encode.input.prompt",
        example: InputExample.encode,
        identifiers: .encode
    )
    .padding()
}

#Preview("Populated — the button is gone, the count is live") {
    InputArea(
        text: .constant(InputExample.encode),
        prompt: "encode.input.prompt",
        example: InputExample.encode,
        identifiers: .encode
    )
    .padding()
}

#Preview("Timestamps — no count line at all") {
    InputArea(
        text: .constant(""),
        prompt: "timestamps.input.prompt",
        example: InputExample.timestamps,
        identifiers: .timestamps,
        countKey: nil
    )
    .padding()
}
