// StepStack — the index algebra every surface's step stack runs on: the
// ordinal a card's header renders, the two enablement flags its footer reads,
// and the index into `Pipeline.steps` that its remove and move controls act
// on (D-99, D-100, APP-09, 07-UI-SPEC.md §"The index mapping, stated because
// it is where the off-by-one lives").
//
// ONE IMPLEMENTATION, FOR THE REASON `StepControls.swift` IS ONE. That file is
// the single place the footer cluster is BUILT; this is the single place the
// numbers it is built from are COMPUTED. Three surfaces call both, and a
// per-surface copy of either is precisely how three surfaces drift.
//
// THE OFFSET IS WHY THIS IS A TYPE AND NOT AN EXPRESSION AT THREE CALL SITES.
// 07-UI-SPEC §"The index mapping" states that `model.<surface>.steps` holds
// "only the appended steps". That is true of Encode and of Timestamps and it
// is FALSE of Hashing: `HashingSurface.chain(from:to:)` writes
// `[Step(operation: row.operation), Step(operation: operation)]`, so the FIRST
// element of `model.hashing.steps` is the digest the chain is rooted at — a
// step that surface renders inside its four-row root card and never as an
// appended card, which is why `HashingSurface.appendedCards` has dropped it
// since Phase 6. A remove wired straight to the appended index would therefore
// delete the CHAIN ROOT whenever a user asked to delete the first appended
// card on Hashing: a different value under every header below it, with no
// confirmation and no undo (D-101). `modelOffset` is that one difference,
// named rather than implied, and asserted per surface in `*SurfaceTests`.
//
// NOTHING HERE MUTATES AND NOTHING HERE RENDERS. Every member is a pure
// function of three integers, which is what lets a host-based unit test assert
// the ends rule and the ordinal without a running app — the two rules most
// able to ship a trap are the two this file makes reachable.

/// Which way a move goes.
///
/// Two cases, because the footer offers exactly two move controls. A general
/// reorder would be a wider contract than anything asserts, which is the same
/// reason ``Pipeline/moving(from:to:)`` refuses a non-adjacent request.
enum StepMoveDirection: Sendable {
    /// Swap with the card above this one.
    case up

    /// Swap with the card below this one.
    case down
}

/// Where one APPENDED card sits in its surface's stack, and everything that
/// follows from that.
///
/// Constructed by ``appendedStepCards(steps:states:stepOffset:stateOffset:)``
/// and never by a view body, so the three integers below are decided once per
/// surface rather than once per card.
struct StepStackPosition: Equatable, Sendable {
    /// The visible ordinal of the pinned root card. Every surface renders
    /// exactly one, ahead of every appended card, and D-100 gives it the note
    /// instead of the three controls.
    static let rootOrdinal = 1

    /// This card's 0-based place among the APPENDED cards — not its place in
    /// `Pipeline.steps`, which is what ``modelIndex`` is for.
    let appendedIndex: Int

    /// How many appended cards the stack holds in total.
    let appendedCount: Int

    /// How many leading elements of `Pipeline.steps` are NOT appended cards.
    ///
    /// **0 on Encode and on Timestamps; 1 on Hashing.** See this file's header
    /// for the measurement behind that one difference — it is the whole reason
    /// this type exists rather than an `index` passed straight through.
    let modelOffset: Int

    /// The ordinal this card's header renders — `appendedIndex + 2`.
    ///
    /// Spelled as *the root's own ordinal, plus one for the root card itself,
    /// plus the index*, because a bare `+ 2` is one refactor away from an
    /// off-by-one on every surface at once. `07-UI-SPEC.md` §"The index
    /// mapping" derives the same number independently, and the surface tests
    /// assert it at three stack lengths.
    var visibleOrdinal: Int {
        Self.rootOrdinal + 1 + appendedIndex
    }

    /// The stack's total card count, for "Step %lld of %lld".
    var totalCards: Int {
        Self.totalCards(appendedCount: appendedCount)
    }

    /// `false` on the topmost appended card, `true` everywhere else.
    ///
    /// **A function of position and of nothing else** — in particular not of
    /// the card's render state. 07-UI-SPEC §"Enablement depends on POSITION
    /// ONLY" narrows Phase 6's State Contract 4 by name: the three footer
    /// controls need no VALUE to act on, and a failing step with every step
    /// blocked beneath it is exactly the stack a user needs to edit.
    var canMoveUp: Bool {
        appendedIndex > 0
    }

    /// `false` on the last appended card. The same rule, mirrored, for the
    /// same reason.
    var canMoveDown: Bool {
        appendedIndex < appendedCount - 1
    }

    /// The index into `Pipeline.steps` this card's step occupies — what
    /// ``Pipeline/removing(at:)`` takes.
    var modelIndex: Int {
        appendedIndex + modelOffset
    }

    /// The total for a stack holding `appendedCount` appended cards.
    ///
    /// A static, so the ROOT call site — which has no position of its own —
    /// reads the same definition its appended siblings read instead of
    /// spelling the `+ 1` a second time where it could drift.
    static func totalCards(appendedCount: Int) -> Int {
        appendedCount + 1
    }

    /// The index this card swaps with — what ``Pipeline/moving(from:to:)``
    /// takes as its destination.
    ///
    /// **Answers ``modelIndex`` itself when the move is not allowed**, so a
    /// move requested at either end asks the pipeline to swap a step with
    /// itself, which `moving(from:to:)` rejects as non-adjacent and answers
    /// with an unchanged pipeline. The footer already disables both controls
    /// at the ends; this makes the boundary safe by construction rather than
    /// by that one modifier, which matters on Hashing where the index below
    /// the topmost appended card is a real index holding the chain root.
    func destinationIndex(_ direction: StepMoveDirection) -> Int {
        switch direction {
        case .up:
            canMoveUp ? modelIndex - 1 : modelIndex
        case .down:
            canMoveDown ? modelIndex + 1 : modelIndex
        }
    }
}

/// One appended card, ready to render: the step, the state it evaluated to,
/// and where it sits.
///
/// A named type rather than a three-member tuple, which `swiftlint --strict`
/// rejects outright (`large_tuple`); the two-member tuple this replaces was
/// already at that limit.
struct AppendedStepCard: Sendable {
    /// The step itself. Its `id` is the `ForEach` identity, and `Step.id` is a
    /// `let` so a reorder moves the value rather than renumbering it.
    let step: Step

    /// What this card renders, from the surface's own `evaluate()` pass.
    let state: StepRenderState

    /// The ordinal, the two enablement flags and the model index.
    let position: StepStackPosition
}

/// Pair every appended step with the state it evaluated to and with the
/// position that decides its ordinal, its footer's enablement and the index
/// its controls act on.
///
/// **The two offsets are independent, and the three surfaces pass three
/// different pairs of them** — which is exactly why they are parameters and
/// not a constant:
///
/// | Surface | `stepOffset` | `stateOffset` | Why |
/// |---|---|---|---|
/// | Encode | 0 | 1 | the seeded step is synthesised into the evaluated pipeline and is not in `steps` |
/// | Hashing | 1 | 1 | the first step IS the chain root, rendered inside the four-row card |
/// | Timestamps | 0 | 0 | the states come from a pipeline built from the appended steps alone |
///
/// `zip` and `dropFirst` rather than an index, so no subscript here can go out
/// of range — these bundles are host-based and a trap takes the whole run with
/// it. A surface holding fewer states than steps simply yields fewer cards.
func appendedStepCards(
    steps: [Step],
    states: [StepRenderState],
    stepOffset: Int,
    stateOffset: Int
) -> [AppendedStepCard] {
    let paired = Array(zip(steps.dropFirst(stepOffset), states.dropFirst(stateOffset)))
    return paired.enumerated().map { entry in
        AppendedStepCard(
            step: entry.element.0,
            state: entry.element.1,
            position: StepStackPosition(
                appendedIndex: entry.offset,
                appendedCount: paired.count,
                modelOffset: stepOffset
            )
        )
    }
}
