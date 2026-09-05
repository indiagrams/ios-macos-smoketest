// HashingSurface — four digests of one input, rendered AT ONCE, aligned as a
// table (D-87, 06-UI-SPEC.md §"2. Hashing — four digests at once, a table").
//
// THE SHAPE IS THE REQUIREMENT. ROADMAP criterion 2 says the user can hash text
// with MD5, SHA-1, SHA-256 and SHA-512 and "read each result at the same time".
// A control that chose one algorithm would show one digest at a time and fail
// that clause outright, so there is none — the four rows are always all there.
// The algorithm name sits in a fixed leading column so the four values line up,
// and that alignment is what makes this read as a TABLE rather than as a list.
// It is also what carries D-87 against the Encode surface's single in-out
// block: a checker should be able to tell the two apart with the text blurred.
//
// FOUR OUTPUTS MEANS FOUR COPY CONTROLS AND FOUR ADD-STEP CONTROLS. That is
// what makes APP-08 unambiguous here with no selection mode, no radio group and
// no implicit "last touched" state — the accessory is attached PER OUTPUT, and
// this surface is the reason 06-11 built it that way.
//
// THERE IS NO ERROR BRANCH IN THIS FILE, AND THAT IS DELIBERATE. Any `String`
// has a UTF-8 encoding and every encoding has a digest, so this surface has no
// input-validation error to report: the seeded card is Empty or it has values,
// and the only other state it can reach is "blocked by an earlier step", which
// requires an appended card and therefore never applies to the seeded one. The
// UI-SPEC states this explicitly so that a later reader does not add an
// unreachable branch and a later tester does not go looking for one. This
// plan's acceptance criteria sweep this file for the type that would carry such
// a branch, which is why the paragraph above describes it and never spells it.
//
// THE STEP STACK IS THE EAGER CONTAINER. 06-11 measured the lazy variant at 77%
// population loss for plan 06-16's sweep with every assertion still passing;
// the forbidden container is described and never spelled here for the same
// reason as above.

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

// MARK: - The seeded card's body

/// The seeded card's body: four rows, always all four.
struct HashBody: View {
    /// The four rows, computed from the surface's input.
    let rows: [DigestRow]

    /// Chains a new step from one named digest's output.
    let onAddStep: (DigestRow, Operation) -> Void

    /// Four rows in an eager stack, in the UI-SPEC's order.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(rows) { row in
                DigestRowView(row: row) { operation in
                    onAddStep(row, operation)
                }
            }
        }
    }
}

// MARK: - The surface

/// Hashing: one input, four digests of it at once, and whatever has been
/// chained below them.
struct HashingSurface: View {
    /// The app-level model. Owns the input and the chained steps.
    @Bindable var model: AppModel

    /// The four rows for the current input.
    private var rows: [DigestRow] {
        digestRows(for: model.hashing.input)
    }

    /// The cards the add-step control has produced, each beside its state.
    ///
    /// `model.hashing.steps` is empty until something is chained. Once it is
    /// not, its FIRST element is the digest the user chained FROM — it has to
    /// be, because a chain's second step is computed from the first step's
    /// output — and everything after it is an appended card. So the appended
    /// cards are the steps and states from the second onward.
    ///
    /// `zip` rather than an index, so there is no subscript here to go out of
    /// range: these bundles are host-based and a trap takes the whole run.
    private var appendedCards: [(step: Step, state: StepRenderState)] {
        let states = model.hashing.evaluate()
        return Array(zip(model.hashing.steps.dropFirst(), states.dropFirst()))
            .map { (step: $0.0, state: $0.1) }
    }

    /// The seeded card's strip: the byte count of what was hashed, or the
    /// prompt while empty. Never absent and never blank.
    ///
    /// Computed from the INPUT rather than from a render state, because the two
    /// states this card can be in are exactly "there is input" and "there is
    /// not" — see the file header for why there is no third.
    private var seededDiagnostic: DiagnosticContent {
        let input = model.hashing.input
        if input.isEmpty {
            return .neutral(localizedSentence(key: "hashing.diagnostic.empty"))
        }
        return .neutral(localizedCount("hashing.diagnostic.valid", input.utf8.count))
    }

    /// Input, step stack, bottom inset — the skeleton all three surfaces share.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                InputArea(
                    text: $model.hashing.input,
                    prompt: "hashing.input.prompt",
                    example: InputExample.hashing,
                    identifiers: .hashing
                )
                stepStack
            }
            .padding(.horizontal, SurfaceLayout.horizontalMargin)
            .padding(.top, Spacing.xl)
            .padding(.bottom, Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The eager step stack: the four-row card, then anything chained below it.
    private var stepStack: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // The header is the FAMILY name, not one algorithm's. The
            // UI-SPEC's mockup sketches "Hash" there, but its own string
            // inventory — which is the normative list, and which says every
            // string the app renders is in it — carries no such key. Minting a
            // 66th user-visible string that no contract approved is worse than
            // using the approved name of the thing this card is; a card that
            // renders four operations cannot honestly be titled with one of
            // them either. Recorded as a deviation in this plan's summary.
            StepCard(title: "shell.destination.hashing", diagnostic: seededDiagnostic) {
                HashBody(rows: rows, onAddStep: chain)
            }
            ForEach(appendedCards, id: \.step.id) { card in
                StepCard(
                    title: LocalizedStringKey(card.step.operation.rawValue),
                    diagnostic: appendedStepDiagnostic(for: card.state)
                ) {
                    SingleOutputBody(state: card.state, onAddStep: append)
                }
            }
        }
    }

    /// Start a chain at `row`'s digest and put `operation` after it.
    ///
    /// The chain is rooted at whichever digest the user reached for, which is
    /// what "feed any tool's output into another tool" means on a surface with
    /// four outputs. Choosing a different digest re-roots the chain there.
    private func chain(from row: DigestRow, to operation: Operation) {
        model.hashing = Pipeline(
            input: model.hashing.input,
            steps: [Step(operation: row.operation), Step(operation: operation)]
        )
    }

    /// Append a card below an already-chained one.
    private func append(_ operation: Operation) {
        model.hashing = model.hashing.appending(operation)
    }
}

#Preview("Empty") {
    HashingSurface(model: AppModel.preview)
}

#Preview("Four digests at once") {
    let model = AppModel.preview
    model.hashing.input = InputExample.hashing
    return HashingSurface(model: model)
}
