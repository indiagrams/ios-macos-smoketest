// Shared helpers for the engine test suites — compiled into BOTH unit-test
// targets by the same `sources:` entries that carry TestVectors.swift.
//
// Nothing here asserts anything. It exists so Base64Tests, and the codec
// suites 06-04 / 06-06 / 06-07 / 06-08 will add, do not each grow their own
// copy of a random generator and their own Result unwrapper — two copies of a
// generator with two different seeds make a failure irreproducible in a way
// that is very hard to see from a log.
//
// Since 07-05 it also owns ``AppModel/isolated(_:_:)``, which is the ONLY way
// a case that is not about persistence may construct the app model. See that
// method for the failure that put it here.

import Foundation
import Testing

// MARK: - The app model, never bound to the shipped settings domain

extension AppModel {
    /// A model bound to a throwaway settings suite, wiped clean first.
    ///
    /// **Every case that is not ABOUT persistence must use this, and none may
    /// call the bare initialiser.** The reason is measured rather than
    /// stylistic. `AppModel.init(defaults:)` defaults to the standard domain,
    /// which is correct for the shipping app and catastrophic for a test:
    /// both unit bundles are host-based (`TEST_HOST` is set in `project.yml`
    /// and `Project.swift` alike), so a case constructing the bare initialiser
    /// hydrates from — and, the moment it assigns a persisted property, writes
    /// to — the REAL ShipkitPipes settings on the developer's Mac and on every
    /// CI simulator.
    ///
    /// That is not hypothetical. On the first green run of 07-05, five cases in
    /// two suites failed. The encode-selection defaults case in
    /// `PipelineTestsAppModel.swift` read back `.html` and `.decode` where it
    /// asserted the declared `.base64` and `.encode`, because an earlier case
    /// had assigned those values through the bare initialiser and the `didSet`
    /// had written them to the host app's domain. A test that pollutes the
    /// state a later test reads is a test whose result depends on ordering.
    ///
    /// **The suite is named after the calling case, not after a fresh `UUID`.**
    /// A UUID per construction would leak one preferences domain per model per
    /// run, forever. Deriving the name from `#fileID` and `#function` bounds
    /// the set at one domain per case, reuses it across runs, and — because
    /// the domain is REMOVED before the model is built — still hands every
    /// case a store with nothing in it. A case does not run concurrently with
    /// itself, so the shared name races with nothing.
    ///
    /// A case that genuinely needs two models over ONE store, which is what a
    /// round-trip assertion is, must not use this: see
    /// `PipelineTests.withSettingsStore(_:)`.
    @MainActor
    static func isolated(_ function: String = #function, _ fileID: String = #fileID) -> AppModel {
        let leaf = fileID.split(separator: "/").last.map(String.init) ?? fileID
        let suite = isolatedSuitePrefix
            + leaf.replacingOccurrences(of: ".swift", with: "")
            + "."
            + function.replacingOccurrences(of: "()", with: "")
        if let store = UserDefaults(suiteName: suite) {
            store.removePersistentDomain(forName: suite)
            return AppModel(defaults: store)
        }
        // Unreachable: `init(suiteName:)` fails only for `nil`, the app's own
        // bundle identifier and the global domain. Recorded and retried under a
        // name that cannot collide, so the run goes red before any case is
        // allowed to bind the shipped domain by accident.
        Issue.record("the throwaway settings suite \(suite) could not be created")
        if let retry = UserDefaults(suiteName: "\(isolatedSuitePrefix)\(UUID().uuidString)") {
            return AppModel(defaults: retry)
        }
        Issue.record("no throwaway settings suite could be created at all; this model reaches the shipped domain")
        return AppModel()
    }

    /// The prefix every suite ``isolated(_:_:)`` builds is named under, so a
    /// leaked domain is greppable and attributable.
    private static var isolatedSuitePrefix: String {
        "com.indiagram.shipkitpipes.enginetests."
    }
}

/// SplitMix64 — a SEEDED generator, so a property-test failure reproduces
/// exactly instead of vanishing on the next run.
///
/// The constants are Steele, Lea and Flood's; the algorithm is chosen for
/// being three lines rather than for cryptographic strength, which is not
/// wanted here. Do NOT swap this for `SystemRandomNumberGenerator`: an
/// unseeded sweep that goes red once and green afterwards is worse than no
/// sweep, because it teaches the next reader to re-run instead of to look.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    /// - Parameter seed: Any value. Each suite uses a distinct literal so two
    ///   suites do not sweep the same inputs and report it as two results.
    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// String generators shared by the codec suites.
///
/// These live here rather than in one suite for the same reason
/// ``SeededGenerator`` does: 06-04, 06-06, 06-07 and 06-08 all sweep over
/// random text, and four private copies with four different pools make a
/// cross-suite failure impossible to compare.
extension SeededGenerator {
    /// A string of up to `maxScalars` scalars drawn from `pool`.
    ///
    /// Scalars rather than Characters, so a pool can contain combining marks
    /// and the generator can build multi-scalar graphemes.
    mutating func randomScalarString(from pool: [Unicode.Scalar], maxScalars: Int) -> String {
        guard !pool.isEmpty, maxScalars > 0 else { return "" }
        var out = ""
        let count = Int(next() % UInt64(maxScalars + 1))
        for _ in 0 ..< count {
            out.unicodeScalars.append(pool[Int(next() % UInt64(pool.count))])
        }
        return out
    }

    /// A string of up to `maxLength` Characters drawn from `pool`.
    mutating func randomString(from pool: [Character], maxLength: Int) -> String {
        guard !pool.isEmpty, maxLength > 0 else { return "" }
        var out = ""
        let count = Int(next() % UInt64(maxLength + 1))
        for _ in 0 ..< count {
            out.append(pool[Int(next() % UInt64(pool.count))])
        }
        return out
    }
}

/// Readers that keep an assertion about a codec from being mostly about
/// unwrapping a `Result`.
extension Result {
    /// The value, or `nil` when this is a failure.
    var success: Success? {
        if case let .success(value) = self {
            value
        } else {
            nil
        }
    }

    /// The error, or `nil` when this is a success.
    var failure: Failure? {
        if case let .failure(error) = self {
            error
        } else {
            nil
        }
    }
}
