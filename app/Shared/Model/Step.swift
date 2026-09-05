// Step — one operation in a pipeline, addressable by identity.
//
// D-79/D-80: the step model ships in Phase 6 and Phase 7 adds only remove and
// reorder on top of it (APP-09). Those two verbs are the reason `id` exists.
// A step list addressed by INDEX is correct only until something is removed
// from the middle of it, and the SwiftUI `ForEach` that renders the stack
// needs a stable identity anyway or it animates the wrong card.
//
// Compiled into the two app targets and BOTH unit-test targets via the
// Shared/Model `sources:` entries.

import Foundation

/// One operation in a pipeline, with the identity that survives a reorder.
///
/// Equality is over `id` **and** `operation` together, which is the synthesised
/// conformance: two independently created steps carrying the same operation are
/// NOT equal, because they are two cards on screen and the user can remove
/// either one. `PipelineTests.stepsAreEqualByIdentityAndOperationTogether`
/// asserts both directions.
///
/// `Sendable` is free — `UUID` and ``Operation`` are both `Sendable` — and is
/// declared explicitly rather than inferred, because 06-03 measured that an
/// implicit conformance downgrades a violation to a warning, which a probe
/// cannot catch.
struct Step: Identifiable, Sendable, Equatable {
    /// Stable for the life of the step. `let`, so a reorder moves the value
    /// rather than renumbering it.
    let id: UUID

    /// What this step does to the text handed down from above it.
    var operation: Operation

    /// - Parameters:
    ///   - operation: The conversion this step performs.
    ///   - id: Defaults to a fresh identity. A test pins it to assert equality
    ///     in both directions; nothing in the app passes it.
    init(operation: Operation, id: UUID = UUID()) {
        self.id = id
        self.operation = operation
    }
}
