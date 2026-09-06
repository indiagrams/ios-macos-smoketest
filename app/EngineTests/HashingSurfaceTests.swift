// HashingSurfaceTests — four digests DRIVEN from one input, and the claim that
// the two layout branches carry identical strings established from the composed
// data rather than by reading the file.
//
// WHY THE HEX LENGTHS AND NOT JUST "FOUR NON-EMPTY VALUES". Four rows that all
// rendered the same digest would be four non-empty distinct-from-empty strings,
// and a count would pass on them. 32 / 40 / 64 / 128 are the lengths that say
// the four rows are four DIFFERENT algorithms, and the distinctness assertion
// beside them says no two rows were wired to the same one.
//
// WHY THE HARVEST ARRAY IS THE THING ASSERTED. `ViewThatFits` chooses a branch
// from the runner's window size. If the two branches carried different strings,
// plan 06-16's population would silently depend on how wide the simulator
// happened to be — a correct check pointed at a window-dependent population,
// which is this phase's own failure class. Both branches render `DigestName`
// and `DigestValue` over one row, and those two views render exactly the two
// entries of `harvestStrings`. This suite reads that array.

import Testing

/// The Hashing surface's four rows and their strings.
@Suite("Hashing surface")
@MainActor
struct HashingSurfaceTests {
    /// The four algorithms in the UI-SPEC's table order, with the hex length
    /// each digest must have and the selector its value must carry.
    private struct Algorithm {
        let operation: Operation
        let name: String
        let hexLength: Int
        let identifier: String
    }

    /// The table, spelled out one row at a time.
    private static let algorithms: [Algorithm] = [
        Algorithm(operation: .md5, name: "MD5", hexLength: 32, identifier: "Hashing.digest.md5"),
        Algorithm(operation: .sha1, name: "SHA-1", hexLength: 40, identifier: "Hashing.digest.sha1"),
        Algorithm(operation: .sha256, name: "SHA-256", hexLength: 64, identifier: "Hashing.digest.sha256"),
        Algorithm(operation: .sha512, name: "SHA-512", hexLength: 128, identifier: "Hashing.digest.sha512")
    ]

    @Test("four rows render at once from one input, each its own algorithm")
    func fourRowsRenderAtOnceFromOneInput() {
        let rows = digestRows(for: InputExample.hashing)
        // hashing_digests_rendered=4
        #expect(rows.count == 4)
        for (row, algorithm) in zip(rows, Self.algorithms) {
            #expect(row.operation == algorithm.operation)
            #expect(row.identifier == algorithm.identifier)
            #expect(row.name == algorithm.name, "\(algorithm.operation) named \(row.name)")
            let value = row.value
            #expect(value != nil, "\(algorithm.name) produced no value")
            #expect(value?.count == algorithm.hexLength, "\(algorithm.name) is \(value?.count ?? 0) characters")
            #expect(value?.allSatisfy(\.isHexDigit) == true)
        }
        #expect(Set(rows.compactMap(\.value)).count == 4)
        #expect(Set(rows.map(\.identifier)).count == 4)
    }

    @Test("every row is empty while the input is, and none of them is blank")
    func everyRowIsEmptyWhileTheInputIs() {
        let rows = digestRows(for: "")
        #expect(rows.count == 4)
        for row in rows {
            #expect(row.state == .empty)
            #expect(row.value == nil)
            // Never blank: the value column falls back to the surface's
            // placeholder, which is a real catalog sentence.
            #expect(row.displayedValue == "Digests appear here as you type.")
        }
    }

    @Test("no input reaches an error state on this surface — there is nothing to fail")
    func noInputReachesAnErrorState() {
        let corpus = [
            "", " ", InputExample.hashing, InputExample.encode, "\u{0}",
            "not base64!", "&nope;", "%zz", String(repeating: "x", count: 5000),
            "🧪🧪🧪", "\u{FFFD}", "line\nbreak\ttab"
        ]
        for input in corpus {
            for row in digestRows(for: input) {
                let isValueOrEmpty = row.state == .empty || row.value != nil
                #expect(isValueOrEmpty, "\(row.operation) reached another state on \(input.debugDescription)")
            }
        }
    }

    @Test("both layout branches read from one shared array of strings")
    func bothLayoutBranchesReadFromOneSharedArray() {
        // viewthatfits_branches_identical=true — established from the composed
        // data. `DigestName` renders harvestStrings[0] and `DigestValue`
        // renders harvestStrings[1]; both `ViewThatFits` branches are built
        // from those two views over the SAME row, so there is exactly one
        // source for each string and the branch choice cannot change it.
        let populated = digestRows(for: InputExample.hashing)
        let empty = digestRows(for: "")
        for rows in [populated, empty] {
            var harvested: [String] = []
            for row in rows {
                #expect(row.harvestStrings.count == 2)
                #expect(row.harvestStrings.first == row.name)
                #expect(row.harvestStrings.last == row.displayedValue)
                #expect(row.harvestStrings.allSatisfy { !$0.isEmpty })
                harvested.append(contentsOf: row.harvestStrings)
            }
            #expect(harvested.count == 8)
        }
        // The four names are distinct in both states; the four values are
        // distinct only when there is something to hash.
        #expect(Set(populated.flatMap(\.harvestStrings)).count == 8)
        #expect(Set(empty.map(\.name)).count == 4)
    }

    @Test("the algorithm names are catalog entries, never their own keys")
    func theAlgorithmNamesAreCatalogEntries() {
        for algorithm in Self.algorithms {
            let name = localizedSentence(key: algorithm.operation.rawValue)
            #expect(name == algorithm.name)
            #expect(name != algorithm.operation.rawValue)
        }
        #expect(localizedSentence(key: "hashing.diagnostic.empty") == "Enter text above to see its digests.")
        #expect(localizedSentence(key: "hashing.output.placeholder") == "Digests appear here as you type.")
        #expect(localizedSentence(key: "shell.destination.hashing") == "Hashing")
    }

    @Test("the strip counts BYTES, which is not the same number as characters here")
    func theStripCountsBytes() {
        let input = InputExample.hashing
        #expect(input.utf8.count == 12)
        #expect(input.count == 10)
        #expect(localizedCount("hashing.diagnostic.valid", input.utf8.count) == "12 bytes hashed.")
        #expect(localizedCount("count.characters", input.count) == "10 characters")
    }

    @Test("chaining from one named digest produces the chained result")
    func chainingFromOneNamedDigestProducesTheChainedResult() {
        let model = AppModel.isolated()
        model.hashing.input = InputExample.hashing
        let rows = digestRows(for: model.hashing.input)
        let sha256 = rows.first { $0.operation == .sha256 }
        #expect(sha256 != nil)

        // What the surface's chain(from:to:) builds: the chosen digest as the
        // root, then the operation the add-step menu offered.
        model.hashing = Pipeline(
            input: model.hashing.input,
            steps: [Step(operation: .sha256), Step(operation: .base64Encode)]
        )
        let states = model.hashing.evaluate()
        #expect(states.count == 2)
        #expect(states.first == .value(sha256?.value ?? ""))
        // The appended card shows the Base64 of the digest above it — the
        // chained result, with nothing copied and nothing pasted (APP-08).
        let chained = Base64Codec.encode(sha256?.value ?? "")
        #expect(states.last == .value(chained))
    }
}
