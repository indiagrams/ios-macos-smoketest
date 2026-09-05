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
