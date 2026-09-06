// EncodeSurface — Format x Direction, ONE in-out block, six composed operation
// names (D-87, D-82, D-83, 06-UI-SPEC.md §"1. Encode/decode — a single in→out
// block").
//
// D-87 IS THE POINT OF THIS FILE. APP-10's "three distinct screens" is carried
// by PRESENTATION, not by three copies of one canvas: the honest answer to
// "what are the three screens?" must not be "one screen with three entry
// points". This surface is a single in-out block. The Hashing surface beside it
// is a four-row table with leading algorithm labels. A checker should be able
// to tell which surface a screenshot came from with the text blurred out.
//
// THE STEP STACK IS AN EAGER CONTAINER, NEVER THE OTHER ONE. Plan 06-11
// MEASURED what the lazy variant costs: thirty cards in one scroll view harvest
// 21 strings and 7 addressable cards lazily against 90 and 30 eagerly — 77% of
// plan 06-16's population gone, with every assertion still passing. That is "a
// correct check pointed at the wrong population" baked into the UI rather than
// into the checker, where nobody would look for it. The forbidden container is
// described and never spelled here, because this plan's acceptance criteria
// sweep this file for it.
//
// NOTHING HERE DEFERS, DELAYS OR RE-IDENTIFIES (D-83). The output and the error
// are recomputed synchronously on the main actor on every keystroke — no
// deferred re-evaluation, no concurrency hop, no delay before an error appears,
// and no re-identifying the view by its input (which would force a rebuild and
// a fade that §Motion forbids). 06-RESEARCH measured a whole pipeline at around
// 2 ms over a 100 KB input against the 16.7 ms a 60 Hz frame allows, so there
// is nothing to move off the main actor and everything to lose by trying: a
// result that arrived late is a result derived from input the user no longer
// has, which D-84 forbids outright. All four constructs are DESCRIBED and never
// spelled, for the same reason as the container above.
//
// WHERE THE SELECTIONS LIVE, AND WHY IT IS NOT IN THIS VIEW. `encodeFormat` and
// `encodeDirection` are properties of `AppModel`, not view-local state. D-82
// requires them to survive navigating away and back, and the platform trap that
// closes is specific: on macOS a `NavigationSplitView` swaps the detail view
// when the sidebar selection changes, and anything held inside that detail view
// is discarded with it. This file therefore declares no view-local storage at
// all.

import SwiftUI

// MARK: - The composed operation name

/// The `Localizable.xcstrings` key the seeded card's header renders, for one
/// pair of picker selections.
///
/// **Six pairs, six keys, and they are THE SAME KEYS the add-step menu offers**
/// — `Operation`'s raw value *is* its catalog key, so a menu item and the card
/// header it produces are one string rather than two that can drift. Routed
/// through `EncodeFormat.operation(_:)`, which is total and exhaustive with no
/// catch-all branch, so a seventh format that nobody wired to an operation is a
/// compile error there rather than an unlabelled card here.
///
/// A named function rather than an expression buried in a view body, so
/// `EncodeSurfaceTests` can enumerate all six pairs and compare each RENDERED
/// name against the UI-SPEC's inventory.
func encodeHeaderKey(format: EncodeFormat, direction: EncodeDirection) -> String {
    format.operation(direction).rawValue
}

// MARK: - The two pickers

/// The Base64 / URL / HTML picker.
///
/// **Segmented, deliberately, and it is a harvest decision rather than a taste
/// one.** Three closed options here and two on its neighbour, six in total, so
/// every one of their labels is permanently in the accessibility tree and
/// harvestable by plan 06-16's sweep WITHOUT the sweep having to open anything.
/// The alternative style would present the options in a pull-down and hide four
/// of the six until something taps it — six strings the app renders that the
/// gate could not see. That style is described here and never spelled, because
/// this plan's acceptance criteria sweep this file for it.
struct FormatPicker: View {
    /// The app-level model. The selection is its property, not this view's.
    @Bindable var model: AppModel

    /// One segment per format, titled by its own catalog key.
    var body: some View {
        Picker("encode.picker.format", selection: $model.encodeFormat) {
            ForEach(EncodeFormat.allCases, id: \.self) { format in
                Text(LocalizedStringKey(format.rawValue)).tag(format)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityIdentifier(AccessibilityIdentifiers.Encode.format)
    }
}

/// The Encode / Decode picker. Segmented for the reason in ``FormatPicker``.
struct DirectionPicker: View {
    /// The app-level model. The selection is its property, not this view's.
    @Bindable var model: AppModel

    /// One segment per direction, titled by its own catalog key.
    var body: some View {
        Picker("encode.picker.direction", selection: $model.encodeDirection) {
            ForEach(EncodeDirection.allCases, id: \.self) { direction in
                Text(LocalizedStringKey(direction.rawValue)).tag(direction)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityIdentifier(AccessibilityIdentifiers.Encode.direction)
    }
}

// MARK: - The seeded card's body

/// The seeded first card's body: two pickers, then one output.
///
/// One output, one accessory — which is exactly what makes this surface a
/// single in-out block rather than a table.
struct EncodeBody: View {
    /// Carries the two selections the pickers bind to.
    @Bindable var model: AppModel

    /// What the one output is showing, from `Pipeline.evaluate()`.
    let state: StepRenderState

    /// Appends a card seeded with THIS output (D-80/D-81/APP-08).
    let onAddStep: (Operation) -> Void

    /// The value, when there is one. `nil` in the other three states, which is
    /// when both accessory controls are disabled and the Mac's copy command
    /// has nothing to yield.
    private var copyableValue: String? {
        if case let .value(value) = state {
            return value
        }
        return nil
    }

    /// Format, Direction, then the output section.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            PickerRow(label: "encode.picker.format") { FormatPicker(model: model) }
            PickerRow(label: "encode.picker.direction") { DirectionPicker(model: model) }
            outputSection
        }
    }

    /// The "Output" label with the accessory on its trailing side, then the
    /// block itself — the arrangement the UI-SPEC's mockup draws.
    private var outputSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text("step.output.label")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                OutputAccessory(
                    value: copyableValue ?? "",
                    isEnabled: copyableValue != nil,
                    onAddStep: onAddStep
                )
            }
            OutputBlock(
                state: state,
                placeholder: "encode.output.placeholder",
                valueIdentifier: AccessibilityIdentifiers.Encode.output
            )
            .copyableOutput(copyableValue)
        }
    }
}

// MARK: - The surface

/// Encode/decode: one input, one seeded card, and whatever the add-step
/// control has appended below it.
struct EncodeSurface: View {
    /// The app-level model. Owns the input, the two selections and the steps.
    @Bindable var model: AppModel

    /// The operation the two pickers currently compose.
    private var seededOperation: Operation {
        model.encodeFormat.operation(model.encodeDirection)
    }

    /// The whole surface as one pipeline: the seeded card first, then every
    /// appended card.
    ///
    /// **The seeded step is composed here rather than stored**, because its
    /// operation is a function of the two pickers and storing it would be a
    /// second copy of the same fact — one that a change to either picker would
    /// have to remember to update. `model.encode.steps` therefore holds ONLY
    /// the appended cards. The fresh identity this creates is never used as a
    /// view identity: the seeded card is rendered on its own and only the
    /// appended cards go through a `ForEach`, keyed by the stable identities
    /// the model already holds.
    private var evaluatedPipeline: Pipeline {
        Pipeline(
            input: model.encode.input,
            steps: [Step(operation: seededOperation)] + model.encode.steps
        )
    }

    /// One render state per card, top to bottom (D-84's halt rule included).
    private var states: [StepRenderState] {
        evaluatedPipeline.evaluate()
    }

    /// The seeded card's state.
    private var seededState: StepRenderState {
        states.first ?? .empty
    }

    /// The appended cards, each beside its own state and its own position.
    ///
    /// `stepOffset: 0` and `stateOffset: 1`: the seeded step is synthesised in
    /// ``evaluatedPipeline`` and is NOT in `model.encode.steps`, so the states
    /// carry one leading element the steps do not. `zip` rather than an index,
    /// so there is no subscript here to go out of range — which matters
    /// because these bundles are host-based and a trap takes the whole run.
    ///
    /// - Note: Internal rather than `private` so a host-based unit test can
    ///   read the ordinals and the enablement flags this surface ACTUALLY
    ///   renders, rather than a copy of the rule that produces them.
    var appendedCards: [AppendedStepCard] {
        appendedStepCards(steps: model.encode.steps, states: states, stepOffset: 0, stateOffset: 1)
    }

    /// The seeded card's strip: the output's character count when there is an
    /// output, the reason when there is not, the prompt while empty.
    ///
    /// Exhaustive over the four named states with no catch-all branch. The
    /// blocked case is unreachable on a seeded first card and is still written,
    /// because the compiler requires totality and a card with a blank strip is
    /// what the alternative would produce.
    private var seededDiagnostic: DiagnosticContent {
        switch seededState {
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

    /// Input, step stack, bottom inset — the skeleton all three surfaces share.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                InputArea(
                    text: $model.encode.input,
                    prompt: "encode.input.prompt",
                    example: InputExample.encode,
                    identifiers: .encode
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

    /// The eager step stack: the seeded card, then the appended ones.
    ///
    /// The root is rendered ALONE, outside the `ForEach`, and that is what
    /// makes D-100's absence a CALL-SITE decision rather than a flag: the root
    /// passes ``StepRootNote`` and the repeated view passes ``StepFooter``, so
    /// no card ever asks whether it is first and
    /// `count(Step.remove) == count(Step.card) - 1` holds structurally.
    private var stepStack: some View {
        let cards = appendedCards
        let total = StepStackPosition.totalCards(appendedCount: cards.count)
        let headerKey = encodeHeaderKey(format: model.encodeFormat, direction: model.encodeDirection)
        return VStack(alignment: .leading, spacing: Spacing.lg) {
            StepCard(
                title: LocalizedStringKey(headerKey),
                diagnostic: seededDiagnostic,
                position: StepStackPosition.rootOrdinal,
                total: total,
                operationName: localizedSentence(key: headerKey),
                footer: { StepRootNote() },
                content: { EncodeBody(model: model, state: seededState, onAddStep: append) }
            )
            ForEach(cards, id: \.step.id) { card in
                StepCard(
                    title: LocalizedStringKey(card.step.operation.rawValue),
                    diagnostic: appendedStepDiagnostic(for: card.state),
                    position: card.position.visibleOrdinal,
                    total: total,
                    operationName: localizedSentence(key: card.step.operation.rawValue),
                    footer: {
                        StepFooter(
                            canMoveUp: card.position.canMoveUp,
                            canMoveDown: card.position.canMoveDown,
                            onMoveUp: { move(card.position, .up) },
                            onMoveDown: { move(card.position, .down) },
                            onRemove: { remove(card.position) }
                        )
                    },
                    content: { SingleOutputBody(state: card.state, onAddStep: append) }
                )
            }
        }
    }

    /// Append a card seeded with the output above it.
    ///
    /// Assignment rather than in-place mutation, which is what `@Observable`
    /// sees — `Pipeline` is a value type on purpose.
    private func append(_ operation: Operation) {
        model.encode = model.encode.appending(operation)
    }

    /// Drop one appended card — a splice, not a truncation (APP-09). The card
    /// below it re-runs on the output of the card above it, and every
    /// downstream value updates in the same pass.
    ///
    /// One assignment, exactly like ``append(_:)``, so the whole new
    /// arrangement arrives in ONE render pass and no intermediate state is
    /// ever rendered. Nothing animates: under D-83 the cards below are already
    /// showing their new content, so a card sliding for a third of a second
    /// while showing it is a card whose position and content disagree for
    /// exactly that long.
    ///
    /// - Note: Internal rather than `private` so a host-based unit test can
    ///   drive THIS function rather than a copy of its rule — the shape
    ///   ``HashingSurface/chain(from:to:)`` was given after WR-01, where a
    ///   test of the test's own copy could not have caught the defect.
    func remove(_ position: StepStackPosition) {
        model.encode = model.encode.removing(at: position.modelIndex)
    }

    /// Swap one appended card with its neighbour. The same one-assignment
    /// shape, and internal for the same reason.
    func move(_ position: StepStackPosition, _ direction: StepMoveDirection) {
        model.encode = model.encode.moving(from: position.modelIndex, to: position.destinationIndex(direction))
    }
}

#Preview("Empty") {
    EncodeSurface(model: AppModel.preview)
}

#Preview("Populated") {
    let model = AppModel.preview
    model.encode.input = InputExample.encode
    return EncodeSurface(model: model)
}

#Preview("Decoding something that does not parse") {
    let model = AppModel.preview
    model.encode.input = "not base64!"
    model.encodeDirection = .decode
    return EncodeSurface(model: model)
}
