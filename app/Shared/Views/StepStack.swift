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
//
// WHY THE FOCUS TABLE LIVES HERE TOO (07-UI-SPEC §"VoiceOver — labels, order,
// announcements, focus"). §Motion takes the animation off removal and reorder,
// so a screen-reader user gets no signal at all unless one is posted, and
// removing the element that HOLDS focus drops focus to the top of the screen —
// on a stack of cards, that is losing your place after every single removal.
// Both remedies are decided by exactly the three integers above, so they are
// decided here, once, rather than three times in three surfaces.
//
// AND THE FOCUS TARGETS ARE APPENDED INDEXES, NEVER `Pipeline.steps` INDEXES.
// That is the whole safety argument for the shape below. `appendedIndex` and
// `appendedCount` are offset-free by construction — they count CARDS, and every
// surface has the same cards — while `modelIndex` carries `modelOffset` and is
// 1 higher on Hashing than the same card's index on Encode. A focus table
// written in model indexes would name a card one place off on exactly the
// surface where the extra element is the chain root, and it would do it
// silently, because a focus target that matches no element simply does nothing
// visible to a sighted reviewer. `focusAfterMove(_:)` and `focusAfterRemoval`
// therefore never mention `modelIndex` and never mention `modelOffset`; the one
// member that carries the offset is used for one thing only, which is deciding
// whether the pipeline accepted the move.

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

/// Which of the three footer controls a focus target names.
///
/// Focus after an edit is always *a control on a card*, never a card, so a
/// target carries both. "The remove control of the card that took the removed
/// card's position" is one of each, and the move rows of the table are the
/// same shape.
enum StepControlKind: Hashable, Sendable {
    /// The move-up arrow.
    case moveUp

    /// The move-down arrow.
    case moveDown

    /// The trash control — the only irreversible one, and the one the focus
    /// table lands on after a removal.
    case remove
}

/// Where VoiceOver focus sits in a step stack.
///
/// See this file's header for why the payload is an APPENDED index rather than
/// an index into `Pipeline.steps`.
///
/// `Hashable` because `@AccessibilityFocusState` requires it, and `Sendable`
/// because everything else in this file is.
enum StepFocusTarget: Hashable, Sendable {
    /// The pinned root card's header — where focus goes when a removal empties
    /// the appended stack and there is no remove control left to hold it.
    case rootHeader

    /// One control of the appended card at `appendedIndex`.
    case control(StepControlKind, appendedIndex: Int)
}

/// The focus table and the two after-edit counts, as pure functions of the
/// three integers above (07-UI-SPEC §"Focus management").
extension StepStackPosition {
    /// Where this card lands after a move in `direction`, or `nil` when the
    /// move is not allowed.
    ///
    /// The refusal test is ``destinationIndex(_:)`` answering this card's own
    /// index, which is the one place that question is decided — so a refused
    /// move announces nothing and moves no focus, by the same expression the
    /// pipeline uses to reject the swap as non-adjacent.
    func moved(_ direction: StepMoveDirection) -> StepStackPosition? {
        guard destinationIndex(direction) != modelIndex else { return nil }
        let landing = switch direction {
        case .up: appendedIndex - 1
        case .down: appendedIndex + 1
        }
        return StepStackPosition(
            appendedIndex: landing,
            appendedCount: appendedCount,
            modelOffset: modelOffset
        )
    }

    /// Focus after a COMPLETED move: the SAME control of the SAME step, at the
    /// index it now occupies. `nil` when the move was refused.
    ///
    /// Focus follows the step because the step is what the user is
    /// manipulating; staying at the old index would leave them on the card that
    /// moved the other way, which reads as the app having done nothing.
    func focusAfterMove(_ direction: StepMoveDirection) -> StepFocusTarget? {
        guard let landed = moved(direction) else { return nil }
        let control = switch direction {
        case StepMoveDirection.up: StepControlKind.moveUp
        case StepMoveDirection.down: StepControlKind.moveDown
        }
        return .control(control, appendedIndex: landed.appendedIndex)
    }

    /// How many appended cards survive this card's removal.
    var appendedCountAfterRemoval: Int {
        appendedCount - 1
    }

    /// The stack's card count after this card's removal — what the removal
    /// announcement counts, and the same definition every card's "Step %lld of
    /// %lld" label already reads.
    var totalCardsAfterRemoval: Int {
        Self.totalCards(appendedCount: appendedCountAfterRemoval)
    }

    /// Focus after a COMPLETED removal, all three rows of the table.
    ///
    /// The card that TOOK the removed card's position keeps this card's index;
    /// when the removed card was the last one there is no such card, and the
    /// `min` lands on the card that is now last. When nothing appended
    /// survives, focus goes to the pinned root's header — the one element that
    /// is always there, since D-100 gives the root no controls at all.
    var focusAfterRemoval: StepFocusTarget {
        let remaining = appendedCountAfterRemoval
        guard remaining > 0 else { return .rootHeader }
        return .control(.remove, appendedIndex: min(appendedIndex, remaining - 1))
    }
}
