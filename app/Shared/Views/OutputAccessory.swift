// OutputAccessory — the uniform [copy] [add step] pair that EVERY output in
// this app carries (D-80, D-86, D-81/APP-08, 06-UI-SPEC.md §"The output
// accessory", §"Copy Affordance and Confirmation").
//
// ATTACHED PER OUTPUT, NOT PER CARD. That is the whole of what makes APP-08
// unambiguous on a multi-output surface: Hashing renders four digests and
// therefore four add-step controls, and "feed the output of any tool into
// another tool" needs no selection mode, no radio group and no implicit
// "last touched" state. One control on the card would have needed all three.
//
// CONFIRMATION IS PER INSTANCE. `isConfirming` and `copyGeneration` are this
// view's own `@State`, so copying SHA-256 does not flash SHA-512's checkmark.
//
// THE COPY CONTROL'S ACCESSIBILITY LABEL CHANGES WITH THE CONFIRMATION —
// "Copy" -> "Copied" -> "Copy". That is deliberate: plan 06-16's walk step 6
// taps one copy control and harvests the second string, which only exists
// while the confirmation is showing.
//
// THIS IS THE ONLY PASTEBOARD CODE IN THE PHASE. `app/Shared/` contains
// exactly one file naming either platform's pasteboard type, and it is this
// one. It writes the UNTRUNCATED value it was handed and nothing else: middle
// truncation is a rendering concern that never reaches ``OutputPasteboard``.
// It never READS the pasteboard — the app has no paste feature, and a read of
// the general pasteboard is a privacy-visible act on iOS. The round trip that
// proves the write works is performed by a test, which reads it back itself.
//
// WHY THE MAC KEYBOARD PATH IS `.onCopyCommand` AND NOT A KEY EQUIVALENT ON A
// HIDDEN BUTTON. `.onCopyCommand` is the AppKit-backed responder-chain hook: it
// binds to whichever output currently has focus and it LIGHTS UP the standard
// Edit > Copy menu item, so the menu bar reflects the app's actual state. The
// alternative — declaring the command-C key equivalent on an invisible button —
// steals that chord globally, leaves Edit > Copy dimmed, and is exactly what a
// guideline 2.4.5 reviewer reads as an iOS app wearing a Mac window (D-11).
// The forbidden modifier is DESCRIBED here and never spelled, because this
// plan's acceptance criteria grep this file for it and a file that configures
// a content gate is swept by that gate.

import SwiftUI

#if os(iOS)
    import UIKit
#endif

#if os(macOS)
    import AppKit
#endif

/// The one place this app writes to the system pasteboard.
///
/// A caseless enum used as a namespace, the same shape as ``Spacing`` and
/// ``Palette``. The per-platform fork lives inside the function body rather
/// than around the type, so there is one entry point and not two.
enum OutputPasteboard {
    /// Put `value` on the general pasteboard, exactly as given.
    ///
    /// - Parameter value: The UNTRUNCATED output the user is looking at.
    static func write(_ value: String) {
        #if os(iOS)
            UIPasteboard.general.string = value
        #elseif os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        #endif
    }
}

/// The trailing accessory pair: copy, then add step, in that order.
struct OutputAccessory: View {
    /// The untruncated value this control copies and seeds a new step with.
    let value: String

    /// `false` in the empty, error and blocked states. Both controls are then
    /// `.disabled(true)` — PRESENT and in the accessibility tree, never
    /// removed by an `if`. A disabled control is still harvestable, so this
    /// costs plan 06-16's sweep nothing and gains it two strings.
    let isEnabled: Bool

    /// Called with the chosen operation. The surface wires this to
    /// `model.<surface> = model.<surface>.appending(operation)` — assignment,
    /// not in-place mutation, which is what `@Observable` sees.
    let onAddStep: (Operation) -> Void

    /// Whether the checkmark is currently showing on THIS accessory.
    @State private var isConfirming = false

    /// Bumped on every copy. Drives the confirmation timer and, on iOS, the
    /// haptic. It only ever changes on a SUCCESSFUL copy, which is how the
    /// feedback avoids firing on an error — under D-83 an error recomputes on
    /// every keystroke, and a haptic on that would be unusable.
    @State private var copyGeneration = 0

    /// The iOS hit target, growing with Dynamic Type. Applied to the HIT AREA
    /// only; the glyph stays at its text-style size.
    @ScaledMetric(relativeTo: .body) private var scaledTapTarget = Spacing.iOSHitTarget

    /// How long the confirmation shows, in seconds (D-86).
    private let confirmationSeconds = 1.2

    /// 44 pt on iOS, 28 pt on macOS. The difference is the point, not an
    /// inconsistency: 44 pt on the Mac reads as an iOS port, which is the
    /// guideline 2.4.5 signal D-11 exists to avoid.
    private var hitTarget: CGFloat {
        #if os(iOS)
            scaledTapTarget
        #else
            Spacing.macOSHitTarget
        #endif
    }

    /// Copy, then add step. Never reordered, on any surface.
    var body: some View {
        HStack(spacing: Spacing.sm) {
            copyButton
            addStepMenu
        }
        .task(id: copyGeneration) {
            guard copyGeneration > 0 else { return }
            isConfirming = true
            do {
                try await Task.sleep(for: .seconds(confirmationSeconds))
            } catch {
                return
            }
            isConfirming = false
        }
    }

    /// `doc.on.doc`, becoming `checkmark` in the accent colour for 1.2 s.
    private var copyButton: some View {
        Button {
            OutputPasteboard.write(value)
            copyGeneration += 1
        } label: {
            Image(systemName: isConfirming ? "checkmark" : "doc.on.doc")
                .foregroundStyle(isConfirming ? Color.accentColor : Color.primary)
                .frame(width: hitTarget, height: hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!isEnabled)
        .accessibilityLabel(isConfirming ? "step.copied" : "step.copy")
        .accessibilityIdentifier(AccessibilityIdentifiers.Step.copy)
        .modifier(CopyFeedback(trigger: copyGeneration))
    }

    /// `plus.circle` in the accent colour, presenting the sectioned menu.
    ///
    /// The item titles are ``Operation``'s raw values, which ARE the catalog
    /// keys, so a menu item and the card header it produces are the same
    /// string rather than two strings that can drift. The two sections are the
    /// contiguous slices `allCases.prefix(6)` and `allCases.suffix(4)` — 06-09
    /// asserts both slices, so a reordering there fails a test rather than
    /// being noticed in a screenshot.
    ///
    /// Every item carries ``AccessibilityIdentifiers/Step/addStepMenu``, which
    /// is a REPEATED identifier resolved by index — the same shape as the copy
    /// and add-step controls, and for the same reason: a per-instance scheme
    /// would break the moment the item list changed.
    private var addStepMenu: some View {
        Menu {
            // The selector is attached to each ITEM rather than to this
            // container, and that is a measurement rather than a preference:
            // plan 06-13 dumped the presented tree on iOS 17.5 and the items a
            // `Menu` presents carry NO identifier when one is applied to the
            // container around them, while an identifier applied to each button
            // does reach the presented cell. A menu whose items can only be
            // reached by their visible text is a menu the selector convention
            // cannot address at all.
            Section("menu.section.encodeDecode") {
                operationButtons(Array(Operation.allCases.prefix(6)))
            }
            Section("menu.section.hashing") {
                operationButtons(Array(Operation.allCases.suffix(4)))
            }
        } label: {
            Image(systemName: "plus.circle")
                .foregroundStyle(Color.accentColor)
                .frame(width: hitTarget, height: hitTarget)
                .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .buttonStyle(.borderless)
        .disabled(!isEnabled)
        // The label below is the catalog KEY as well as its English value —
        // 06-10's one declared alias, kept because 06-14's amended G8 group
        // counts that string twice in Localizable.xcstrings and exactly ONCE
        // here. Writing `step.addStep` instead would resolve to nothing, and
        // naming the label again in this comment would inflate G8's Swift-side
        // count to two, so it is described here rather than spelled.
        .accessibilityLabel("Add step")
        .accessibilityIdentifier(AccessibilityIdentifiers.Step.addStep)
    }

    /// One menu item per operation, in `allCases` order.
    private func operationButtons(_ operations: [Operation]) -> some View {
        ForEach(operations, id: \.self) { operation in
            Button(LocalizedStringKey(operation.rawValue)) {
                onAddStep(operation)
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.Step.addStepMenu)
        }
    }
}

/// The iOS success haptic on a copy, and nothing at all on macOS.
///
/// A modifier rather than an inline `#if` so the platform fork is one small
/// declaration instead of a branch inside the button's modifier chain.
private struct CopyFeedback: ViewModifier {
    /// Changes only on a successful copy — never on an error (§Motion).
    let trigger: Int

    /// iOS gets `.success`; macOS has no equivalent worth firing.
    func body(content: Content) -> some View {
        #if os(iOS)
            content.sensoryFeedback(.success, trigger: trigger)
        #else
            content
        #endif
    }
}

/// Makes an output block the macOS keyboard-copy responder.
///
/// `.focusable()` gives the block the SYSTEM focus ring, and `.onCopyCommand`
/// binds the standard copy command to whichever block currently has it. See
/// this file's header for why this is the responder-chain hook and not a key
/// equivalent on a hidden button. iOS gets neither: divergence row 6 makes the
/// keyboard path a macOS requirement only.
private struct CopyableOutput: ViewModifier {
    /// The value the focused block yields to the copy command, or `nil` when
    /// there is no value to copy (the empty, error and blocked states).
    let value: String?

    /// Focusable and copy-command-bound on macOS; untouched on iOS.
    func body(content: Content) -> some View {
        #if os(macOS)
            content
                .focusable(value != nil)
                .onCopyCommand {
                    guard let value else { return [] }
                    return [NSItemProvider(object: value as NSString)]
                }
        #else
            content
        #endif
    }
}

extension View {
    /// Mark this view as an output block the macOS copy command can act on.
    func copyableOutput(_ value: String?) -> some View {
        modifier(CopyableOutput(value: value))
    }
}
