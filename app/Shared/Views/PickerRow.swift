// PickerRow — the labelled control row two surfaces share, and the one place
// its label is spelled (06-UI-SPEC.md §"Dynamic Type", Harvest rule 5).
//
// A COMPANION FILE, NOT A NEW COMPONENT. This pair was declared inside
// `EncodeSurface.swift` in Phase 6 and `TimestampsSurface.swift` has called it
// since 06-13 — one surface's file owning a type another surface renders is a
// misplacement rather than a design. Plan 07-08 moved it out UNCHANGED, byte
// for byte, when wiring the step footer took `EncodeSurface.swift` past
// SwiftLint's 400-line file budget; splitting the shared thing out is the
// split this codebase already makes, and it was preferred over trimming prose
// that records measured reasoning.

import SwiftUI

/// A labelled control row that gives its control the whole width when the
/// label beside it would leave too little.
///
/// The label is hidden on the control itself and drawn as a real `Text`, so it
/// renders identically on both platforms — the Mac's segmented control would
/// otherwise place its own title and iOS would drop it — and so the word is a
/// harvestable string in its own right rather than only an accessibility label.
///
/// **Both branches contain the same strings** (UI-SPEC Harvest rule 5), by
/// construction: each is built from the same `label` and the same `picker`
/// closure, so there is no second place for a word to be written. The first
/// branch takes the control at its natural width, which is what lets
/// `ViewThatFits` genuinely reject it — a segmented control left flexible
/// compresses to anything it is offered and would always "fit", squeezing its
/// six titles until they truncated at large text sizes.
struct PickerRow<Control: View>: View {
    /// The catalog key naming the control.
    let label: LocalizedStringKey

    /// The control itself, built twice from one closure.
    @ViewBuilder let picker: () -> Control

    /// Side by side when it fits; stacked when it does not.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                PickerRowLabel(label: label)
                picker().fixedSize()
            }
            VStack(alignment: .leading, spacing: Spacing.sm) {
                PickerRowLabel(label: label)
                picker()
            }
        }
    }
}

/// The one place a picker row's label is spelled, so both layout branches
/// render the identical string.
struct PickerRowLabel: View {
    /// The catalog key naming the control.
    let label: LocalizedStringKey

    /// `.subheadline` `.secondary`, matching every other section label.
    var body: some View {
        Text(label)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}
