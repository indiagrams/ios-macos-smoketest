// The two value-returning mutators — APP-09's remove and reorder, tested.
//
// An `extension` of `PipelineTests` rather than a suite of its own, so that
// `-only-testing:AppMacOSTests/PipelineTests` selects these cases too. A third
// file, following PipelineFoldTests.swift: PipelineTests.swift is already 220
// lines and PipelineTestsAppModel.swift 219, and SwiftLint's 400-line file
// budget is not loosened.
//
// NOTHING HERE INDEXES AN ARRAY, and that rule is load-bearing twice over in
// this file. These bundles are host-based, so a Swift runtime trap kills the
// host, aborts the run and puts a crash-reporter dialog on the developer's
// physical desktop — measured on this tree, one dialog per parameterised case.
// That also makes a trapping "red" worthless as evidence: the process dies,
// nothing after it runs, and a control that SIGTRAPs has CRASHED rather than
// failed. So the out-of-range cases below assert that the pipeline comes back
// UNCHANGED; they never let an index reach a subscript. `first`, `last`,
// `dropFirst` and whole-array equality are used throughout, each compared as
// an Optional where one is involved.
//
// THE SPLICE IS DERIVED, NOT DECIDED. ROADMAP criterion 2's own words —
// "downstream results updating to match" — settle what removing a middle step
// means: the step below re-chains onto the step above. It does not truncate.
// 07-CONTEXT.md records that as following from the criterion so that no plan
// re-litigates it, and `removingTheMiddleStepSplicesOntoTheStepAbove` is the
// executed form of it.
//
// EVERY EXPECTED VALUE BELOW IS COMPUTED HERE from the operations involved,
// never copied off a run: a literal lifted out of a transcript records what
// the code did rather than what it should do.

import Foundation
import Testing

extension PipelineTests {
    // MARK: - APP-09 — removing(at:) splices

    /// **The splice, not a truncation.** Removing the middle step re-chains the
    /// step below onto the step above, so the survivor re-runs on the FIRST
    /// step's output and its rendered value changes to match. A `removing` that
    /// truncated would return one step; one that dropped the element without
    /// the fold re-running would leave the old value on screen, which D-84
    /// forbids outright.
    ///
    /// The two expected values are computed from the surviving operations here
    /// in the test process, and `spliced != chained` is asserted first so a
    /// fixture whose operations do not visibly change the text cannot make the
    /// case pass by comparing a value with itself.
    @Test
    func removingTheMiddleStepSplicesOntoTheStepAbove() {
        let pipeline = Pipeline(input: "<b> c", steps: Self.steps(.htmlEncode, .urlEncode, .base64Encode))
        let encoded = apply(.htmlEncode, to: "<b> c").success
        let spliced = encoded.flatMap { apply(.base64Encode, to: $0).success }
        let chained = encoded
            .flatMap { apply(.urlEncode, to: $0).success }
            .flatMap { apply(.base64Encode, to: $0).success }
        #expect(encoded != nil, "the fixture's first step must convert, or every expectation below is nil == nil")
        #expect(spliced != nil)
        #expect(spliced != chained, "the fixture cannot tell a splice from a no-op — pick operations that change the text")
        #expect(pipeline.evaluate().count == 3)
        #expect(pipeline.evaluate().last == chained.map(StepRenderState.value), "the before-state, so the after-state means something")

        let after = pipeline.removing(at: 1)
        #expect(after.steps.count == 2, "a splice keeps the survivor; a truncation would have dropped it")
        #expect(after.input == pipeline.input, "removing a step does not touch the input")
        #expect(after.evaluate().count == 2)
        #expect(after.evaluate().first == encoded.map(StepRenderState.value))
        #expect(after.evaluate().last == spliced.map(StepRenderState.value), "the survivor re-ran on the step above it")
    }

    /// Removing index 0 of a two-step pipeline leaves exactly one step, and it
    /// is the step that was BELOW — compared by `Step.id`, because that is the
    /// identity `ForEach(appendedCards, id: \.step.id)` renders by.
    @Test
    func removingTheFirstStepLeavesTheSecondRatherThanAnEmptyPipeline() {
        let first = Step(operation: .base64Encode)
        let second = Step(operation: .sha256)
        let pipeline = Pipeline(input: "hello", steps: [first, second])
        #expect(first.id != second.id, "two fresh steps must not share an identity, or the comparison below proves nothing")

        let after = pipeline.removing(at: 0)
        #expect(after.steps.count == 1, "removing the top step is not emptying the pipeline")
        #expect(after.steps.map(\.id) == [second.id])
        #expect(after.steps.first?.operation == .sha256)
        #expect(after.evaluate().count == 1)
        #expect(after.evaluate().first == apply(.sha256, to: "hello").success.map(StepRenderState.value))
    }

    // MARK: - APP-09 — moving(from:to:) is an adjacent swap

    /// Move up and move down, each a swap with the immediate neighbour. The
    /// step that was not asked to move does not move, asserted by identity
    /// rather than by count.
    @Test
    func movingSwapsTwoAdjacentStepsAndLeavesTheThirdWhereItWas() {
        let top = Step(operation: .base64Encode)
        let middle = Step(operation: .urlEncode)
        let bottom = Step(operation: .sha256)
        let pipeline = Pipeline(input: "a b", steps: [top, middle, bottom])

        let up = pipeline.moving(from: 0, to: 1)
        #expect(up.steps.map(\.id) == [middle.id, top.id, bottom.id])
        #expect(up.steps.last?.id == bottom.id, "the step nobody asked to move stayed where it was")

        let down = pipeline.moving(from: 1, to: 2)
        #expect(down.steps.map(\.id) == [top.id, bottom.id, middle.id])
        #expect(down.steps.first?.id == top.id)
        #expect(down.input == pipeline.input)
    }

    /// **A swap, not an insertion.** The count and the `Step.id` set are both
    /// unchanged, which is what stops `ForEach(appendedCards, id: \.step.id)`
    /// from animating a card that is not there; only the order moves.
    @Test
    func movingPreservesTheStepIdentitySetAndOnlyChangesTheOrder() {
        let pipeline = Pipeline(input: "a b", steps: Self.steps(.base64Encode, .urlEncode, .sha256))
        let ids = pipeline.steps.map(\.id)
        #expect(ids.count == 3)
        #expect(Set(ids).count == 3, "the fixture reused an identity, which would make the set comparison below vacuous")

        let moved = pipeline.moving(from: 1, to: 0)
        #expect(moved.steps.count == pipeline.steps.count, "a swap neither inserts a step nor drops one")
        #expect(Set(moved.steps.map(\.id)) == Set(ids), "the identity set survives the move")
        #expect(moved.steps.map(\.id) != ids, "…and the order did in fact change")
        #expect(moved.steps.map(\.id) == [ids.dropFirst().first, ids.first, ids.last].compactMap { $0 })
    }

    // MARK: - T-07-TRAP — totality on a bad index

    /// One bad request, the receiver it was made against, and what came back.
    /// A named type rather than a tuple so the sweep below can say WHICH case
    /// came back changed — SwiftLint caps a tuple at two members, and a failure
    /// message that names nothing is the thing this repository keeps catching.
    private struct MutatorRequest {
        let label: String
        let receiver: Pipeline
        let result: Pipeline

        init(_ label: String, _ receiver: Pipeline, _ result: Pipeline) {
            self.label = label
            self.receiver = receiver
            self.result = result
        }
    }

    /// **Every out-of-range and every non-adjacent request returns the receiver
    /// unchanged.** A view hands these methods an index derived from a stack it
    /// rendered a frame ago, so the index is untrusted input; and a `guard` is
    /// used rather than a `precondition` because these bundles are host-based
    /// and a trap takes the whole run with it, exactly as `evaluate()`'s own
    /// doc comment says.
    ///
    /// The sweep asserts its own population before iterating: an `each` over an
    /// empty collection asserts nothing and prints success, and this repository
    /// has shipped that defect.
    @Test
    func everyOutOfRangeOrNonAdjacentRequestReturnsTheReceiverUnchanged() {
        let two = Pipeline(input: "hello", steps: Self.steps(.base64Encode, .sha256))
        let three = Pipeline(input: "hello", steps: Self.steps(.base64Encode, .urlEncode, .sha256))
        let none = Pipeline(input: "hello", steps: [])
        let requests: [MutatorRequest] = [
            MutatorRequest("removing past the end", two, two.removing(at: 5)),
            MutatorRequest("removing at the count", two, two.removing(at: 2)),
            MutatorRequest("removing a negative index", two, two.removing(at: -1)),
            MutatorRequest("removing from an empty step list", none, none.removing(at: 0)),
            MutatorRequest("moving to past the end", two, two.moving(from: 0, to: 9)),
            MutatorRequest("moving from a negative index", two, two.moving(from: -1, to: 0)),
            MutatorRequest("moving from past the end", two, two.moving(from: 7, to: 6)),
            MutatorRequest("moving within an empty step list", none, none.moving(from: 0, to: 1)),
            MutatorRequest("moving a step onto itself", two, two.moving(from: 0, to: 0)),
            MutatorRequest("moving two positions at once", three, three.moving(from: 0, to: 2))
        ]
        #expect(requests.count == 10, "the sweep lost its cases; a loop over an empty list asserts nothing")
        for request in requests {
            #expect(request.result == request.receiver, "\(request.label): the receiver came back changed")
            #expect(request.result.evaluate() == request.receiver.evaluate(),
                    "\(request.label): what the surface renders came back changed")
        }
    }

    // MARK: - Criterion 2 — the blocked states clear in one pass

    /// Removing the failing step takes the `.blocked` count from greater than
    /// zero to exactly zero in ONE evaluation. No second pass, no new machinery
    /// in `evaluate()`: the halt flag stops setting once the failure is gone.
    ///
    /// The non-zero count is asserted BEFORE the removal, so "exactly zero
    /// after" cannot pass by comparing nothing with nothing.
    @Test
    func removingTheFailingStepClearsEveryBlockedStateInOnePass() {
        let pipeline = Pipeline(input: Self.chainInput, steps: Self.steps(.urlEncode, .base64Decode, .sha256, .md5))
        let before = pipeline.evaluate()
        #expect(before.count == 4)
        #expect(before.contains(.failure(Self.chainFailure)), "the fixture never reached the failing state")
        #expect(before.filter { $0 == .blocked }.count > 0, "nothing was blocked, so asserting zero afterwards would be vacuous")

        let after = pipeline.removing(at: 1).evaluate()
        #expect(after.count == 3)
        #expect(after.filter { $0 == .blocked }.count == 0, "a blocked state survived the removal of the step that caused it")
        let encoded = apply(.urlEncode, to: Self.chainInput).success
        #expect(encoded != nil)
        #expect(after.first == encoded.map(StepRenderState.value))
        let hashed = encoded.flatMap { apply(.sha256, to: $0).success }
        let digested = hashed.flatMap { apply(.md5, to: $0).success }
        #expect(after.dropFirst().first == hashed.map(StepRenderState.value),
                "the step that was blocked now carries a value computed from the step above it")
        #expect(after == [encoded, hashed, digested].compactMap { $0.map(StepRenderState.value) },
                "every surviving step renders a value; nothing failed and nothing is blocked")
    }
}
