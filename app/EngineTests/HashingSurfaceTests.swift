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

    // MARK: - The chain root is not an appended card (plan 07-08)

    /// A surface whose chain is rooted at SHA-256, with `count` cards appended
    /// below it — the shape `chain(from:to:)` actually writes.
    private func chainedSurface(appending operations: [Operation]) -> HashingSurface {
        let model = AppModel.isolated()
        model.hashing = Pipeline(
            input: InputExample.hashing,
            steps: [Step(operation: .sha256)] + operations.map { Step(operation: $0) }
        )
        return HashingSurface(model: model)
    }

    @Test("the chain root is rendered by the root card and is never an appended card")
    func theChainRootIsNeverAnAppendedCard() {
        let surface = chainedSurface(appending: [.base64Encode, .md5])
        let cards = surface.appendedCards
        // Three steps, TWO appended cards. 07-UI-SPEC's index mapping says
        // `steps` holds "only the appended steps"; on this surface it does not.
        #expect(surface.model.hashing.steps.count == 3)
        #expect(cards.count == 2)
        #expect(!cards.isEmpty)
        #expect(cards.first?.step.operation == .base64Encode)
        #expect(cards.last?.step.operation == .md5)

        // The offset, stated as the two numbers it separates: the first
        // appended card is appended index 0 and MODEL index 1.
        #expect(cards.first?.position.appendedIndex == 0)
        #expect(cards.first?.position.modelIndex == 1)
        #expect(cards.first?.position.modelOffset == 1)
        // The ordinal is unaffected by the offset — the root card is Step 1
        // here exactly as it is on the other two surfaces.
        #expect(cards.first?.position.visibleOrdinal == 2)
        #expect(cards.last?.position.visibleOrdinal == 3)
        #expect(cards.first?.position.totalCards == 3)
    }

    @Test("removing the first appended card leaves the chain root exactly where it was")
    func removingTheFirstAppendedCardLeavesTheChainRootIntact() {
        let surface = chainedSurface(appending: [.base64Encode, .md5])

        // EXISTENCE BEFORE ABSENCE: the root is there, and it is SHA-256.
        #expect(surface.model.hashing.steps.first?.operation == .sha256)
        let rootID = surface.model.hashing.steps.first?.id
        #expect(rootID != nil)
        let target = surface.appendedCards.first
        #expect(target != nil)

        // Driven through the surface's OWN remove, which is the call site a
        // wrong index would live at. With `stepOffset: 0` this deletes the
        // chain root instead — every card below then reads a different value
        // under an unchanged header, with no confirmation and no undo (D-101).
        if let target {
            surface.remove(target.position)
        }

        #expect(surface.model.hashing.steps.count == 2)
        #expect(surface.model.hashing.steps.first?.operation == .sha256,
                "the removal deleted the chain root instead of the first appended card")
        #expect(surface.model.hashing.steps.first?.id == rootID)
        let after = surface.appendedCards
        #expect(after.count == 1)
        #expect(after.first?.step.operation == .md5)
        #expect(after.first?.position.visibleOrdinal == 2)
    }

    @Test("the topmost appended card cannot rise above the chain root")
    func theTopmostAppendedCardCannotRiseAboveTheChainRoot() {
        let surface = chainedSurface(appending: [.base64Encode, .md5])
        let top = surface.appendedCards.first
        #expect(top != nil)
        #expect(top?.position.canMoveUp == false)
        // Its model index is 1, so `modelIndex - 1` is a REAL index holding the
        // chain root. destinationIndex answers its own index instead, and the
        // pipeline rejects the swap as non-adjacent — the boundary is safe by
        // construction and not only by the disabled modifier.
        #expect(top?.position.destinationIndex(.up) == 1)
        let before = surface.model.hashing.steps.map(\.operation)
        if let top {
            surface.move(top.position, .up)
        }
        #expect(surface.model.hashing.steps.map(\.operation) == before)
        #expect(surface.model.hashing.steps.first?.operation == .sha256)

        // A move that IS allowed still works, so the guard above is not simply
        // breaking every move.
        if let top {
            surface.move(top.position, .down)
        }
        #expect(surface.model.hashing.steps.map(\.operation) == [.sha256, .md5, .base64Encode])
    }

    @Test("footer enablement on this surface depends on position only")
    func footerEnablementDependsOnPositionOnly() {
        // A failing card and the card blocked beneath it: base64 decoding a
        // hex digest fails, which blocks everything below it.
        let surface = chainedSurface(appending: [.base64Decode, .md5])
        let cards = surface.appendedCards
        #expect(cards.count == 2)
        #expect(!cards.isEmpty)
        let blocked = cards.filter { $0.state == .blocked }.count
        #expect(blocked > 0, "nothing was blocked, so the independence claim below proves nothing")

        // Both cards answer the ends rule and nothing else, in a stack where
        // one has failed and one is blocked.
        #expect(cards.first?.position.canMoveUp == false)
        #expect(cards.first?.position.canMoveDown == true)
        #expect(cards.last?.position.canMoveUp == true)
        #expect(cards.last?.position.canMoveDown == false)
    }
}
