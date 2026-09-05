// Shared helpers for the engine test suites — compiled into BOTH unit-test
// targets by the same `sources:` entries that carry TestVectors.swift.
//
// Nothing here asserts anything. It exists so Base64Tests, and the codec
// suites 06-04 / 06-06 / 06-07 / 06-08 will add, do not each grow their own
// copy of a random generator and their own Result unwrapper — two copies of a
// generator with two different seeds make a failure irreproducible in a way
// that is very hard to see from a log.

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
