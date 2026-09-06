// DigestRow — the Hashing surface's table row: one algorithm's name, its
// digest, and the accessory on that digest, in the two layouts a row folds
// between (D-87, 06-UI-SPEC.md §"2. Hashing — four digests at once, a table").
//
// A COMPANION FILE, NOT A NEW COMPONENT. Every declaration below was moved out
// of `HashingSurface.swift` UNCHANGED by plan 07-08, when wiring the step
// footer took that file past SwiftLint's 400-line budget. The split is the one
// the code already implied: the four leaf views and the row that composes them
// are the DIGEST TABLE, and what is left behind is the surface — its input,
// its step stack, and the chain root the `+` control writes.
//
// THE ROW IS WHAT MAKES THIS SURFACE A TABLE. The algorithm name sits in a
// fixed leading column so the four values line up, and that alignment is what
// a checker uses to tell a Hashing screenshot from an Encode one with the text
// blurred out. The footer added below the strip in 07-08 is the same row in
// the same place on all three surfaces and changes nothing here.

import SwiftUI

// MARK: - The four rows

/// One algorithm's row: its name, its value and the selector on that value.
///
/// A value type computed fresh from the input on every pass — nothing derived
/// is stored, so nothing here can go stale (D-84's premise).
struct DigestRow: Identifiable, Equatable, Sendable {
    /// Which digest this row is. Also its identity in the stack.
    let operation: Operation

    /// The `AccessibilityIdentifiers.Hashing.digest*` constant this row's value
    /// carries. A parameter rather than a constant because `OutputBlock` and
    /// this row both need per-row selectors on a surface with four outputs.
    let identifier: String

    /// What this row is showing. Empty, or a value — never anything else on the
    /// seeded card; see the file header.
    let state: StepRenderState

    /// Rows are identified by their algorithm, which is unique in the four.
    var id: Operation {
        operation
    }

    /// The algorithm's display name, already localized. `Operation`'s raw value
    /// **is** its catalog key, so this is the same string the add-step menu
    /// offers for the same algorithm.
    var name: String {
        localizedSentence(key: operation.rawValue)
    }

    /// The digest, when there is one. `nil` while the input is empty — which is
    /// exactly when this row's two controls are disabled.
    var value: String? {
        if case let .value(digest) = state {
            return digest
        }
        return nil
    }

    /// What the value column shows: the digest, or the surface's placeholder.
    ///
    /// Never blank in either case (UI-SPEC §"State Contract").
    var displayedValue: String {
        value ?? localizedSentence(key: "hashing.output.placeholder")
    }

    /// **The two strings this row contributes to the harvest, and the ONLY two
    /// places either layout branch reads a string from.**
    ///
    /// Both `ViewThatFits` branches below render `DigestName` and `DigestValue`
    /// over the same row, and those two views render exactly these two strings.
    /// That is how UI-SPEC Harvest rule 5 is kept by construction rather than
    /// by inspection: there is no second place for a word to be written, so the
    /// harvest cannot depend on which branch the runner's window size selects.
    /// `HashingSurfaceTests` reads this array rather than eyeballing the file.
    var harvestStrings: [String] {
        [name, displayedValue]
    }
}

/// The four rows for one input, in the order the UI-SPEC's table lists them.
///
/// Each digest is taken over the INPUT, not over the row above it — the four
/// are siblings, not a chain. Routed through `Pipeline.evaluate()` so the empty
/// input is intercepted by the same rule every other surface uses, rather than
/// by a second copy of that rule here.
func digestRows(for input: String) -> [DigestRow] {
    let algorithms: [(operation: Operation, identifier: String)] = [
        (.md5, AccessibilityIdentifiers.Hashing.digestMD5),
        (.sha1, AccessibilityIdentifiers.Hashing.digestSHA1),
        (.sha256, AccessibilityIdentifiers.Hashing.digestSHA256),
        (.sha512, AccessibilityIdentifiers.Hashing.digestSHA512)
    ]
    return algorithms.map { algorithm in
        DigestRow(
            operation: algorithm.operation,
            identifier: algorithm.identifier,
            state: Pipeline(
                input: input,
                steps: [Step(operation: algorithm.operation)]
            ).evaluate().first ?? .empty
        )
    }
}

// MARK: - The three leaf views a row is built from

/// The algorithm name — the table's leading column.
struct DigestName: View {
    /// The row this name belongs to.
    let row: DigestRow

    /// `.subheadline` `.secondary`, the same role every section label uses.
    var body: some View {
        Text(verbatim: row.name)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}

/// The digest itself.
///
/// One line with MIDDLE truncation, which keeps both ends visible — that is how
/// people actually eyeball one digest against another, and it is the one class
/// of string the Dynamic Type contract allows to truncate, with the stated
/// escape that the value is selectable and carries a copy control. The
/// truncation is a RENDERING concern only: the accessory beside it receives the
/// untruncated value (T-06-54).
struct DigestValue: View {
    /// The row this value belongs to.
    let row: DigestRow

    /// Monospaced body, because column position carries meaning in a digest.
    var body: some View {
        Text(verbatim: row.displayedValue)
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(row.value == nil ? Color.secondary : Color.primary)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .accessibilityIdentifier(row.identifier)
            .copyableOutput(row.value)
    }
}

/// The copy and add-step pair for one digest.
///
/// One of these per row, so four per card. Disabled rather than removed while
/// the input is empty: a disabled control is still in the accessibility tree
/// and gains plan 06-16's sweep two strings.
struct DigestAccessory: View {
    /// The row these controls act on.
    let row: DigestRow

    /// Chains a new step from THIS digest's output.
    let onAddStep: (Operation) -> Void

    /// The uniform accessory, unchanged from every other output in the app.
    var body: some View {
        OutputAccessory(
            value: row.value ?? "",
            isEnabled: row.value != nil,
            onAddStep: onAddStep
        )
    }
}

// MARK: - The row, in its two layouts

/// One table row: name, value, controls — on one line, or on two.
///
/// **Both branches are built from the same three leaf views over the same
/// row**, so they carry identical strings by construction (Harvest rule 5).
///
/// The fit is decided on the value's MINIMUM legible width rather than on its
/// natural width, and that distinction is what makes the fallback reachable at
/// all: a one-line, middle-truncated digest compresses to any width it is
/// offered, so a branch measured on the real value would always "fit" and the
/// two-line layout would be dead code — while a branch measured on the value's
/// natural 128-character width would NEVER fit and the one-line layout would be
/// dead instead. `idealWidth` is what a `ViewThatFits` measurement reads, and
/// it scales with the text size, so the row folds when the name column and the
/// controls have squeezed the value below legibility.
struct DigestRowView: View {
    /// The row to render.
    let row: DigestRow

    /// Chains a new step from this digest's output.
    let onAddStep: (Operation) -> Void

    /// The leading column's width. Fixed across the four rows — the alignment
    /// is what makes this a table — and scaled, so it still holds the longest
    /// name at large text sizes.
    @ScaledMetric(relativeTo: .subheadline) private var nameColumnWidth: CGFloat = 76

    /// The narrowest a digest may be squeezed before the row folds.
    @ScaledMetric(relativeTo: .body) private var minimumValueWidth: CGFloat = 110

    /// One line when the three fit; two lines when they do not.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                DigestName(row: row)
                    .frame(width: nameColumnWidth, alignment: .leading)
                DigestValue(row: row)
                    .frame(idealWidth: minimumValueWidth, maxWidth: .infinity, alignment: .leading)
                DigestAccessory(row: row, onAddStep: onAddStep)
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                DigestName(row: row)
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    DigestValue(row: row)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    DigestAccessory(row: row, onAddStep: onAddStep)
                }
            }
        }
    }
}
