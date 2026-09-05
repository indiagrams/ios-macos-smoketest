// TimestampsSurface — ONE field, the format auto-detected and overridable, and
// three representations of one instant rendered at once (D-87, D-88, D-89,
// APP-05, APP-06, APP-07, 06-UI-SPEC.md §"3. Timestamps").
//
// ONE FIELD SATISFIES BOTH DIRECTIONS. APP-05 asks for epoch → ISO 8601 and
// local time; APP-06 asks for the way back. D-88's answer is that the user types
// whatever they have and the app works out which it is, so there is no direction
// control on this surface and no second field — the three cells below are all
// three answers, all of the time. That is also what makes this surface
// structurally different from the other two (D-87): Encode is one in→out block,
// Hashing is a four-row aligned table, and this is a grid of representation
// cells. The distinctness is what carries APP-10's "three distinct screens".
//
// APP-05'S "AND TO LOCAL TIME" IS THE DEFAULT STATE OF THE DATE-AND-TIME CELL,
// not a fourth cell. The zone picker starts on the device's own zone (APP-07),
// so with nothing touched that cell already IS the local-time reading. The
// reasoning is recorded on `TimestampRepresentation.render(_:in:)`, next to the
// code it is about.
//
// THE STEP STACK IS THE EAGER CONTAINER, as on both other surfaces. 06-11
// measured the deferred variant at 77% population loss for plan 06-16's sweep
// with every assertion still passing. The forbidden container is described and
// never spelled here, because this plan's acceptance criteria sweep this file
// for it — the fourteenth time this phase has met a file that configures a
// content gate being swept by that gate.
//
// NO ASSERTION ANYWHERE MAY COMPARE THE DATE-AND-TIME CELL AGAINST LITERAL
// TEXT. It is `Date.FormatStyle` output and is locale- and region-dependent:
// the UI-SPEC's mockup and the machine the phase research ran on render the
// same instant differently, and both are correct for their region. The cell is
// reached by its accessibility identifier and asserted non-empty; this plan's
// acceptance criteria grep this whole directory for the two literal renderings
// so that neither can be written into a test by habit.
//
// NOTHING HERE DEFERS OR RE-IDENTIFIES (D-83). The outcome, the cells and the
// diagnostic are recomputed synchronously on the main actor on every keystroke.
// A result that arrived late is a result derived from input the user no longer
// has, which D-84 forbids outright.

import SwiftUI

// MARK: - The seeded card's body

/// The seeded first card's body: the detection control, the zone picker, and
/// the three representation cells.
struct TimestampBody: View {
    /// Carries the selection and the zone the controls bind to.
    @Bindable var model: AppModel

    /// What the detector says about the current input.
    let detected: ReadAs

    /// The three cells, already computed from one outcome.
    let cells: [TimestampCell]

    /// Chains a new step from one named cell's value.
    let onAddStep: (TimestampRepresentation, Operation) -> Void

    /// Read as, Time zone, then the grid — the UI-SPEC's order.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            ReadAsControl(model: model, detected: detected)
            PickerRow(label: "timestamps.picker.timeZone") { TimeZonePicker(model: model) }
            TimestampCellsView(cells: cells, onAddStep: onAddStep)
        }
    }
}

// MARK: - The surface

/// Timestamps: one input, three simultaneous representations of it, and
/// whatever has been chained below them.
struct TimestampsSurface: View {
    /// The app-level model. Owns the input, the "Read as" selection, the zone,
    /// the chain's root and the chained steps — everything D-82 requires to
    /// survive navigating away and back.
    @Bindable var model: AppModel

    /// What the detector concludes about the current input.
    private var detected: ReadAs {
        TimestampDetection.segment(for: TimestampDetection.detect(model.timestamps.input))
    }

    /// The segment actually in force: the user's choice, or the detector's.
    private var readAs: ReadAs {
        effectiveReadAs(for: model.timestamps.input, chosen: model.timestampsReadAs)
    }

    /// What the input denotes right now. Recomputed, never stored.
    private var outcome: TimestampOutcome {
        timestampOutcome(for: model.timestamps.input, readAs: readAs, timeZone: model.timestampsTimeZone)
    }

    /// The three cells for the current input, in the UI-SPEC's order.
    private var cells: [TimestampCell] {
        timestampCells(for: model.timestamps.input, readAs: readAs, timeZone: model.timestampsTimeZone)
    }

    /// The value the chained cards are computed from: the cell the user reached
    /// for, as it reads RIGHT NOW.
    ///
    /// The model stores WHICH cell rooted the chain and never the value it had,
    /// so editing the input re-derives everything below it rather than leaving
    /// a card showing a result derived from input the user no longer has
    /// (D-84). An empty string here puts every chained card in the Empty state,
    /// which is the honest reading of "the thing this chain was rooted at does
    /// not currently exist".
    private var chainRootValue: String {
        guard let root = model.timestampsChainRoot else { return "" }
        return cells.first { $0.representation == root }?.value ?? ""
    }

    /// The cards the add-step control has produced, each beside its state.
    ///
    /// Composed fresh from the root value rather than stored, the same call
    /// `EncodeSurface` makes about its seeded step: `model.timestamps.steps`
    /// holds ONLY the appended cards, because the thing they are rooted at is a
    /// representation of an instant and there is no ``Operation`` that produces
    /// one from text.
    ///
    /// `zip` rather than an index, so there is no subscript here to go out of
    /// range — these bundles are host-based and a trap takes the whole run.
    private var appendedCards: [(step: Step, state: StepRenderState)] {
        let chained = Pipeline(input: chainRootValue, steps: model.timestamps.steps)
        return Array(zip(model.timestamps.steps, chained.evaluate()))
            .map { (step: $0.0, state: $0.1) }
    }

    /// The seeded card's strip: the segment in force when the input reads, the
    /// reason when it does not, the prompt while empty.
    ///
    /// Exhaustive over the three outcomes with no catch-all branch.
    private var seededDiagnostic: DiagnosticContent {
        switch outcome {
        case .empty:
            .neutral(localizedSentence(key: "timestamps.diagnostic.empty"))
        case .instant:
            .neutral(readAsDiagnostic(readAs))
        case let .failure(reason):
            .problem(failureText(reason, in: .timestamps))
        }
    }

    /// Input, step stack, bottom inset — the skeleton all three surfaces share.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                InputArea(
                    text: $model.timestamps.input,
                    prompt: "timestamps.input.prompt",
                    example: InputExample.timestamps,
                    identifiers: .timestamps,
                    countKey: nil
                )
                stepStack
            }
            .padding(.horizontal, SurfaceLayout.horizontalMargin)
            .padding(.top, Spacing.xl)
            .padding(.bottom, Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // GAP-06-01's scroll half. The toolbar half is on the field itself, in
        // InputArea; both live in Views/KeyboardDismiss.swift, which is where
        // the reason for having two is written down. No-op on macOS.
        .dismissesKeyboardOnScroll()
    }

    /// The eager step stack: the three-cell card, then anything chained below.
    ///
    /// The header is the DESTINATION name. The UI-SPEC's mockup sketches
    /// "Timestamp" there and its own string inventory — the normative list —
    /// carries no key for it, so this uses the approved name of the surface,
    /// exactly as plan 06-12 did on the Hashing card for the same reason.
    private var stepStack: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            StepCard(title: "shell.destination.timestamps", diagnostic: seededDiagnostic) {
                TimestampBody(model: model, detected: detected, cells: cells, onAddStep: chain)
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

    /// Start a chain at `representation`'s value and put `operation` after it.
    ///
    /// The chain is rooted at whichever cell the user reached for, which is what
    /// "feed any tool's output into another tool" means on a surface with three
    /// outputs. Reaching for a different cell re-roots the chain there.
    private func chain(from representation: TimestampRepresentation, to operation: Operation) {
        model.timestampsChainRoot = representation
        model.timestamps = Pipeline(input: model.timestamps.input, steps: [Step(operation: operation)])
    }

    /// Append a card below an already-chained one.
    private func append(_ operation: Operation) {
        model.timestamps = model.timestamps.appending(operation)
    }
}

#Preview("Empty") {
    TimestampsSurface(model: AppModel.preview)
}

#Preview("One instant, three ways") {
    let model = AppModel.preview
    model.timestamps.input = InputExample.timestamps
    return TimestampsSurface(model: model)
}

#Preview("Something that does not read as a timestamp") {
    let model = AppModel.preview
    model.timestamps.input = "12x4"
    return TimestampsSurface(model: model)
}
