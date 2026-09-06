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

    /// The cards the add-step control has produced, each beside its state and
    /// its position.
    ///
    /// `model.hashing.steps` is empty until something is chained. Once it is
    /// not, its FIRST element is the digest the user chained FROM — it has to
    /// be, because a chain's second step is computed from the first step's
    /// output — and everything after it is an appended card. So the appended
    /// cards are the steps and states from the second onward.
    ///
    /// **`stepOffset: 1` IS THAT SENTENCE, AND IT IS WHY THIS SURFACE IS NOT A
    /// COPY OF THE OTHER TWO.** 07-UI-SPEC §"The index mapping" says
    /// `model.<surface>.steps` holds "only the appended steps"; here it does
    /// not, and a remove wired straight to the appended index would delete the
    /// CHAIN ROOT the first time a user asked to delete the first appended
    /// card. `stateOffset: 1` for the matching reason on the other array: the
    /// root digest evaluates to the first state.
    ///
    /// `zip` rather than an index, so there is no subscript here to go out of
    /// range: these bundles are host-based and a trap takes the whole run.
    ///
    /// - Note: Internal rather than `private` so a host-based unit test can
    ///   read the offset this surface ACTUALLY uses rather than a copy of it.
    var appendedCards: [AppendedStepCard] {
        appendedStepCards(
            steps: model.hashing.steps,
            states: model.hashing.evaluate(),
            stepOffset: 1,
            stateOffset: 1
        )
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
        // GAP-06-01's scroll half. The toolbar half is on the field itself, in
        // InputArea; both live in Views/KeyboardDismiss.swift, which is where
        // the reason for having two is written down. No-op on macOS.
        .dismissesKeyboardOnScroll()
    }

    /// The eager step stack: the four-row card, then anything chained below it.
    ///
    /// The root is rendered ALONE, outside the `ForEach`, which is what makes
    /// D-100's absence a CALL-SITE decision rather than a flag: the root passes
    /// ``StepRootNote`` and the repeated view passes ``StepFooter``, so no card
    /// ever asks whether it is first.
    private var stepStack: some View {
        let cards = appendedCards
        let total = StepStackPosition.totalCards(appendedCount: cards.count)
        return VStack(alignment: .leading, spacing: Spacing.lg) {
            // The header is the FAMILY name, not one algorithm's. The
            // UI-SPEC's mockup sketches "Hash" there, but its own string
            // inventory — which is the normative list, and which says every
            // string the app renders is in it — carries no such key. Minting a
            // 66th user-visible string that no contract approved is worse than
            // using the approved name of the thing this card is; a card that
            // renders four operations cannot honestly be titled with one of
            // them either. Recorded as a deviation in this plan's summary.
            StepCard(
                title: "shell.destination.hashing",
                diagnostic: seededDiagnostic,
                position: StepStackPosition.rootOrdinal,
                total: total,
                operationName: localizedSentence(key: "shell.destination.hashing"),
                footer: { StepRootNote() },
                content: { HashBody(rows: rows, onAddStep: chain) }
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

    /// Start a chain at `row`'s digest and put `operation` after it — or
    /// APPEND, when the chain is already rooted at that same digest.
    ///
    /// The chain is rooted at whichever digest the user reached for, which is
    /// what "feed any tool's output into another tool" means on a surface with
    /// four outputs. Choosing a DIFFERENT digest re-roots the chain there.
    ///
    /// - Important: **The root check is the whole point (WR-01).** Until
    ///   2026-09-05 this assigned a fresh `Pipeline` unconditionally, so a user
    ///   who had built `SHA-256 → Base64 encode → MD5` and then tapped `+` on
    ///   the SAME SHA-256 row lost both appended cards, with no confirmation
    ///   and no undo. The doc comment justified re-rooting as "choosing a
    ///   different digest re-roots the chain there" — but the code never
    ///   checked which output was tapped, so it re-rooted on the same one too.
    ///   The `+` control is identical on every row and is this surface's
    ///   primary call to action, so it was easy to hit by accident. That is
    ///   D-84's family inverted: work the user still has, thrown away.
    /// - Note: Internal rather than `private` so a host-based unit test can
    ///   drive THIS function. The test that covered chaining before rebuilt the
    ///   pipeline by hand and asserted the result, which is a test of the
    ///   test's copy of the rule — it could not have caught WR-01, and did not.
    func chain(from row: DigestRow, to operation: Operation) {
        guard model.hashing.steps.first?.operation != row.operation else {
            model.hashing = model.hashing.appending(operation)
            return
        }
        model.hashing = Pipeline(
            input: model.hashing.input,
            steps: [Step(operation: row.operation), Step(operation: operation)]
        )
    }

    /// Append a card below an already-chained one.
    private func append(_ operation: Operation) {
        model.hashing = model.hashing.appending(operation)
    }

    /// Drop one appended card — a splice, not a truncation (APP-09). The card
    /// below it re-runs on the output of the card above it, and every
    /// downstream value updates in the same pass.
    ///
    /// One assignment, exactly like ``append(_:)``, so the whole new
    /// arrangement arrives in ONE render pass and no intermediate state is
    /// ever rendered. Nothing animates.
    ///
    /// **`position.modelIndex` carries this surface's offset**, so the chain
    /// root can never be the step that goes: the topmost appended card is
    /// model index 1, not 0.
    ///
    /// - Note: Internal rather than `private` so a host-based unit test can
    ///   drive THIS function rather than a copy of its rule — the shape
    ///   ``chain(from:to:)`` was given after WR-01, where a test of the test's
    ///   own copy could not have caught the defect and did not.
    func remove(_ position: StepStackPosition) {
        model.hashing = model.hashing.removing(at: position.modelIndex)
    }

    /// Swap one appended card with its neighbour. The same one-assignment
    /// shape, and internal for the same reason. The topmost appended card
    /// cannot rise past the chain root: its move-up is disabled, and
    /// ``StepStackPosition/destinationIndex(_:)`` answers its own index there
    /// so the pipeline refuses the swap as non-adjacent even if it is asked.
    func move(_ position: StepStackPosition, _ direction: StepMoveDirection) {
        model.hashing = model.hashing.moving(from: position.modelIndex, to: position.destinationIndex(direction))
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
