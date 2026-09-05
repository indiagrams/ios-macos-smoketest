// Pipeline — the input, the ordered steps, and the dispatch into the pure
// engines (D-79, D-84, APP-08).
//
// `apply(_:to:)` is a FREE FUNCTION, not a static member, matching
// `characterPosition(utf8Offset:in:)` in Shared/Engine/Position.swift. It is
// the one place that turns an ``Operation`` into a call, and its `switch` has
// no catch-all branch, so adding a case is a compile error here rather than a
// silent fall-through that renders an unlabelled card.
//
// NOTHING IN THIS FILE KNOWS ABOUT A VIEW. It imports no UI framework and it
// never sees the app-level model: everything crossing this boundary is a
// `String`, a `Result` or one of this phase's own value types. 06-RESEARCH
// measured the alternative — a free function reaching into a main-actor
// `@Observable` class is a hard compile error under
// `-strict-concurrency=complete`, which is the shape this file avoids by
// construction rather than by discipline.

/// A surface's whole conversion: one input, and the steps applied to it in
/// order.
///
/// A value type on purpose. The app-level model mutates a pipeline by
/// assignment, which is what makes `@Observable` see the change; a reference
/// type would mutate in place and the UI would not update.
struct Pipeline: Sendable, Equatable {
    /// The text the user typed. The empty string is the Empty state, not a
    /// conversion of nothing.
    var input: String = ""

    /// The steps, top to bottom. The first is the surface's seeded card; the
    /// rest were appended by the add-step control.
    var steps: [Step] = []
}

/// What one step card renders. Four named states, so "blank" is not
/// representable.
///
/// 06-UI-SPEC.md §"State Contract" defines exactly these four and requires
/// that none of them is blank and none is ever stale. Making them a type
/// rather than a pair of optionals is what stops a fifth, accidental state —
/// an empty string standing in for "nothing yet" — from reaching the screen.
enum StepRenderState: Equatable, Sendable {
    /// The pipeline input is empty. Intercepts before any classifier runs, so
    /// an empty input is never reported as a conversion failure.
    case empty

    /// This step converted its input and this is the result.
    case value(String)

    /// This step's own input does not parse. Carries D-85's named reason and
    /// character position, unchanged from the engine that produced it.
    case failure(ConversionFailure)

    /// An EARLIER step failed, so this one did not run (D-84). Reachable only
    /// on an appended card; the seeded first card is never blocked.
    case blocked
}

/// Perform one operation on one piece of text.
///
/// The `switch` is exhaustive with **no catch-all branch**: a new
/// ``Operation`` that nobody wired up fails to compile here.
///
/// - Returns: Whatever the engine returned, unchanged. The reason and the
///   position travel through so the card can render them; wrapping or
///   flattening the failure would throw away the half of D-85 that makes the
///   message actionable.
nonisolated func apply(_ operation: Operation, to input: String) -> Result<String, ConversionFailure> {
    switch operation {
    case .base64Encode: .success(Base64Codec.encode(input))
    case .base64Decode: Base64Codec.decode(input)
    case .urlEncode: .success(PercentCodec.encode(input))
    case .urlDecode: PercentCodec.decode(input)
    case .htmlEncode: .success(HTMLEntityCodec.encode(input))
    case .htmlDecode: HTMLEntityCodec.decode(input)
    case .md5: .success(DigestCodec.md5(input))
    case .sha1: .success(DigestCodec.sha1(input))
    case .sha256: .success(DigestCodec.sha256(input))
    case .sha512: .success(DigestCodec.sha512(input))
    }
}

extension Pipeline {
    /// What every step renders, top to bottom — one ``StepRenderState`` per
    /// step, in order.
    ///
    /// **The halt rule (D-84).** The walk carries the current text forward and
    /// switches to a halted mode on the first `.failure`. After that, every
    /// remaining step emits `.blocked` **without calling ``apply(_:to:)`` at
    /// all**: a blocked step never re-runs and never shows a stale value,
    /// because no step may display a value derived from input the user no
    /// longer has. The four digest operations cannot fail, so a fold that
    /// merely *reported* the halt while continuing to compute would produce a
    /// value for a digest below a failure — which is exactly the case
    /// `PipelineTests.aBlockedStepNeverReRuns` drives.
    ///
    /// **The Empty state intercepts first.** An empty input is the Empty state
    /// for every step, never `.value("")` and never a failure: converting
    /// nothing is not a conversion that went wrong.
    ///
    /// **Pure and synchronous, deliberately, and measured rather than assumed**
    /// (06-RESEARCH.md §"Does anything need to leave the main actor? No —
    /// measured", swiftc -O, arm64-apple-macosx14.0). Over a 100 KB input:
    /// four digests plus hex 0.858 ms, Base64 encode 0.193 ms, Base64 decode
    /// 0.175 ms, percent encode 1.881 ms — a whole pipeline around 2 ms
    /// against the 16.7 ms a 60 Hz frame allows. Handing this to another
    /// isolation domain would therefore buy nothing measurable, and it would
    /// risk rendering a result that no longer corresponds to what the user has
    /// typed, which D-84 forbids outright. **Nothing in this file may
    /// introduce a concurrency hop or a delayed re-evaluation**, and a grep in
    /// this plan's acceptance criteria enforces it.
    ///
    /// - Complexity: One pass over `steps`. No index arithmetic, so there is
    ///   no subscript here to go out of range — which matters because these
    ///   test bundles are host-based and a trap takes the whole run with it.
    nonisolated func evaluate() -> [StepRenderState] {
        guard !input.isEmpty else {
            return Array(repeating: .empty, count: steps.count)
        }
        var states: [StepRenderState] = []
        states.reserveCapacity(steps.count)
        var carried = input
        var halted = false
        for step in steps {
            guard !halted else {
                states.append(.blocked)
                continue
            }
            switch apply(step.operation, to: carried) {
            case let .success(value):
                states.append(.value(value))
                carried = value
            case let .failure(reason):
                states.append(.failure(reason))
                halted = true
            }
        }
        return states
    }

    /// A copy of this pipeline with one more step on the end.
    ///
    /// This is the model half of the add-step control (D-80/D-81/APP-08). The
    /// new step is seeded with the previous step's output because
    /// ``evaluate()`` carries the text forward — there is nothing to copy and
    /// nothing to paste, which is the whole of APP-08.
    ///
    /// Returns a new value rather than mutating in place, so the app-level
    /// model assigns it and `@Observable` sees the change. The fresh `UUID`
    /// means appending the same operation twice produces two cards.
    nonisolated func appending(_ operation: Operation) -> Pipeline {
        Pipeline(input: input, steps: steps + [Step(operation: operation)])
    }
}
