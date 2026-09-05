// ChainRerootTests — tapping `+` twice on the same output must not destroy the
// chain already built below it (WR-01, plan 06-20).
//
// WHY THIS IS ITS OWN SUITE AND NOT AN EXTENSION
//
// The defect spans BOTH surfaces with the same shape, and the assertion is the
// same sentence on each: re-root when the root CHANGES, append when it does
// not. Splitting it across `HashingSurfaceTests` and `TimestampsSurfaceTests`
// would state the rule twice and let the two copies drift, which is the shape
// of the defect it is about.
//
// WHAT WAS WRONG
//
// Both `chain(from:to:)` implementations assigned a brand-new `Pipeline`
// unconditionally. Their doc comments justified this as "choosing a different
// digest re-roots the chain there" — but neither tested WHICH output was
// tapped, so tapping the same one re-rooted too. A user who had built
// `SHA-256 → Base64 encode → MD5` and then tapped `+` on that same SHA-256 row
// lost both appended cards: no confirmation, no undo, and the `+` control is
// identical on every row and is each surface's primary call to action.
//
// D-84 governs "no step may display a value derived from input the user no
// longer has". This is that family inverted — work the user still HAS, thrown
// away — and it is user data loss, which is why it was fixed here rather than
// deferred to Phase 7.
//
// WHY THE TESTS DRIVE `chain(from:to:)` AND NOT A COPY OF IT
//
// The test that covered chaining before this plan rebuilt the pipeline by hand
// and asserted the result. That asserts the TEST's copy of the rule; it could
// not have caught WR-01, and did not. Both `chain` methods were made internal
// so these tests can call the code that ships — the same reason
// `TimeZonePicker.options` was lifted out of `body`.

import Foundation
import Testing

/// Re-rooting and appending on the two surfaces that chain from several outputs.
@Suite("Chain re-rooting")
@MainActor
struct ChainRerootTests {
    /// A row standing for one digest.
    ///
    /// `chain(from:to:)` reads only `operation`, so the other two fields are
    /// filler — stated here rather than left for a reader to infer from a
    /// literal. `.empty` and not a value, because a row that has not been
    /// evaluated is exactly what the surface holds before the user types.
    static func row(_ operation: Operation) -> DigestRow {
        DigestRow(operation: operation, identifier: "chain-reroot-fixture", state: .empty)
    }

    // MARK: - Hashing

    /// Tapping `+` on the row the chain is ALREADY rooted at appends. It does
    /// not throw the chain away.
    @Test
    func hashingAppendsWhenTheRootIsUnchanged() {
        let model = AppModel()
        model.hashing.input = InputExample.hashing
        let surface = HashingSurface(model: model)
        let root = Self.row(.sha256)

        surface.chain(from: root, to: .base64Encode)
        #expect(model.hashing.steps.map(\.operation) == [.sha256, .base64Encode])

        // The second tap on the SAME row. Before 06-20 this reset the chain to
        // [.sha256, .md5] and the Base64 card the user had built vanished.
        surface.chain(from: root, to: .md5)
        #expect(model.hashing.steps.map(\.operation) == [.sha256, .base64Encode, .md5],
                "the second tap on the same row must append, not destroy the chain below it")
    }

    /// Tapping `+` on a DIFFERENT row re-roots, which is the behaviour the doc
    /// comment always claimed and the reason the check is on the root rather
    /// than on the step count.
    @Test
    func hashingReRootsWhenTheRootChanges() {
        let model = AppModel()
        model.hashing.input = InputExample.hashing
        let surface = HashingSurface(model: model)
        let sha256 = Self.row(.sha256)
        let md5 = Self.row(.md5)

        surface.chain(from: sha256, to: .base64Encode)
        surface.chain(from: sha256, to: .urlEncode)
        #expect(model.hashing.steps.count == 3, "two appends onto one root")

        surface.chain(from: md5, to: .base64Encode)
        #expect(model.hashing.steps.map(\.operation) == [.md5, .base64Encode],
                "a different digest re-roots the chain there, which is the documented behaviour")
    }

    /// The input is carried across a re-root, so the new chain is about the
    /// same text the old one was.
    @Test
    func hashingKeepsTheInputAcrossAReRoot() {
        let model = AppModel()
        model.hashing.input = InputExample.hashing
        let surface = HashingSurface(model: model)
        surface.chain(from: Self.row(.sha1), to: .base64Encode)
        #expect(model.hashing.input == InputExample.hashing)
    }

    // MARK: - Timestamps

    /// The same rule on the Timestamps surface, where the root is
    /// `model.timestampsChainRoot` — already stored before this plan, and
    /// simply never read by `chain(from:to:)`.
    @Test
    func timestampsAppendsWhenTheRootIsUnchanged() {
        let model = AppModel()
        model.timestamps.input = InputExample.timestamps
        let surface = TimestampsSurface(model: model)

        surface.chain(from: .iso8601, to: .base64Encode)
        #expect(model.timestampsChainRoot == .iso8601)
        #expect(model.timestamps.steps.map(\.operation) == [.base64Encode])

        surface.chain(from: .iso8601, to: .sha256)
        #expect(model.timestamps.steps.map(\.operation) == [.base64Encode, .sha256],
                "the second tap on the same cell must append, not destroy the chain below it")
        #expect(model.timestampsChainRoot == .iso8601)
    }

    /// Reaching for a different cell re-roots there and the root follows.
    @Test
    func timestampsReRootsWhenTheRootChanges() {
        let model = AppModel()
        model.timestamps.input = InputExample.timestamps
        let surface = TimestampsSurface(model: model)

        surface.chain(from: .iso8601, to: .base64Encode)
        surface.chain(from: .iso8601, to: .sha256)
        #expect(model.timestamps.steps.count == 2)

        surface.chain(from: .epoch, to: .md5)
        #expect(model.timestampsChainRoot == .epoch)
        #expect(model.timestamps.steps.map(\.operation) == [.md5],
                "a different cell re-roots the chain there, which is the documented behaviour")
    }

    /// The very first tap on a surface whose root happens to match the default
    /// still starts a chain rather than appending onto nothing.
    ///
    /// `timestampsChainRoot` is `nil` until something is chained, so the guard
    /// has to survive the case where a caller sets it without any steps. This
    /// drives that state directly rather than trusting it cannot arise.
    @Test
    func timestampsStartsAChainEvenIfTheRootWasAlreadySet() {
        let model = AppModel()
        model.timestamps.input = InputExample.timestamps
        model.timestampsChainRoot = .iso8601
        let surface = TimestampsSurface(model: model)

        surface.chain(from: .iso8601, to: .base64Encode)
        #expect(model.timestamps.steps.map(\.operation) == [.base64Encode],
                "no steps yet, so this is a start and not an append")
    }
}
