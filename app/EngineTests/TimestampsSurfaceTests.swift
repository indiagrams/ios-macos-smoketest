// TimestampsSurfaceTests — THREE representations DRIVEN from one field, the
// override proven to change what is rendered, and the one cell whose text may
// never be asserted kept out of every literal comparison.
//
// WHY THE EPOCH AND ISO VALUES ARE ASSERTED LITERALLY AND THE THIRD IS NOT.
// `renderEpochSeconds` and `renderISO8601` are locale-independent by
// construction — plain digits with no grouping separator, and an RFC 3339
// string. `renderDateTime` is `Date.FormatStyle` output and is locale- AND
// region-dependent: the UI-SPEC's mockup and the machine the phase research ran
// on render the same instant differently and both are correct. So that cell is
// asserted by its accessibility identifier and by being non-empty, and its
// dependence on the zone is asserted as a DIFFERENCE between two zones rather
// than against any literal — which is the assertion that proves the zone
// argument is used at all.
//
// WHY EVERY CASE PASSES AN EXPLICIT ZONE. `TimestampCodec.defaultTimeZone` is
// the machine's own, so a suite that let it default would assert different
// strings on a developer Mac and on a CI runner. Every expectation below that
// names a string names the zone it was rendered in.
//
// WHY THE HARVEST ARRAY IS THE THING ASSERTED. `ViewThatFits` chooses its
// branch from the width the runner offers. Both branches render the same
// `TimestampCell` through the same leaf view, and that view renders exactly the
// two entries of `harvestStrings` — so plan 06-16's population cannot depend on
// the window size. This suite reads that array rather than reading the file.

import Foundation
import Testing

/// The Timestamps surface's three cells, its detection control and its zone.
@Suite("Timestamps surface")
@MainActor
struct TimestampsSurfaceTests {
    /// Every literal expectation below is rendered in this zone, never in the
    /// machine's own.
    private static let utc = TimeZone.gmt

    /// A second zone, seven hours away, used only to prove the zone is read.
    private static let losAngeles = TimeZone(identifier: "America/Los_Angeles") ?? TimeZone.gmt

    /// The three cells in the UI-SPEC's order, with the title and the selector
    /// each one must carry.
    private struct Representation {
        let representation: TimestampRepresentation
        let title: String
        let identifier: String
    }

    /// The table, spelled out one row at a time.
    private static let representations: [Representation] = [
        Representation(representation: .epoch, title: "Unix epoch", identifier: "Timestamps.cell.epoch"),
        Representation(representation: .iso8601, title: "ISO 8601", identifier: "Timestamps.cell.iso8601"),
        Representation(representation: .dateTime, title: "Date and time", identifier: "Timestamps.cell.dateTime")
    ]

    /// The cells for one input, read as one segment, in one zone.
    private func cells(_ input: String, as readAs: ReadAs, in zone: TimeZone = utc) -> [TimestampCell] {
        timestampCells(for: input, readAs: readAs, timeZone: zone)
    }

    @Test("three cells render at once from one field, each its own representation")
    func threeCellsRenderAtOnceFromOneField() {
        let rendered = cells(InputExample.timestamps, as: .unixEpoch)
        // timestamps_cells_rendered=3
        #expect(rendered.count == 3)
        #expect(rendered.count == TimestampRepresentation.allCases.count)
        for (cell, expected) in zip(rendered, Self.representations) {
            #expect(cell.representation == expected.representation)
            #expect(cell.identifier == expected.identifier)
            #expect(cell.title == expected.title, "\(expected.representation) titled \(cell.title)")
            #expect(cell.value?.isEmpty == false, "\(expected.title) produced no value")
        }
        #expect(Set(rendered.map(\.identifier)).count == 3)
    }

    /// The two locale-independent renderings of `InputExample.timestamps`,
    /// which is 2026-01-01T00:00:00Z. The third cell is deliberately absent
    /// from this assertion; see the file header.
    @Test("the epoch and ISO cells render the worked example exactly")
    func theEpochAndISOCellsRenderTheWorkedExampleExactly() {
        let rendered = cells(InputExample.timestamps, as: .unixEpoch)
        let byRepresentation = Dictionary(uniqueKeysWithValues: rendered.map { ($0.representation, $0) })
        // example_timestamps=1767225600
        #expect(byRepresentation[.epoch]?.value == "1767225600")
        // iso_offset_separator=colon; in UTC the offset is the Z designator.
        #expect(byRepresentation[.iso8601]?.value == "2026-01-01T00:00:00Z")
        // datetime_cell_asserted_by=identifier
        #expect(byRepresentation[.dateTime]?.identifier == "Timestamps.cell.dateTime")
        #expect(byRepresentation[.dateTime]?.value?.isEmpty == false)
    }

    @Test("every cell shows the placeholder while the input is empty, and none is blank")
    func everyCellShowsThePlaceholderWhileTheInputIsEmpty() {
        for input in ["", "   ", "\n"] {
            let rendered = cells(input, as: .unixEpoch)
            #expect(rendered.count == 3)
            for cell in rendered {
                #expect(cell.value == nil)
                #expect(cell.state == .empty)
                #expect(cell.displayedValue == "Representations appear here as you type.")
            }
        }
    }

    @Test("a failure replaces every cell's value, and names a reason and a position")
    func aFailureReplacesEveryCellsValue() {
        let rendered = cells("12x4", as: .unixEpoch)
        #expect(rendered.count == 3)
        for cell in rendered {
            #expect(cell.value == nil, "\(cell.title) kept a value through a failure")
            #expect(cell.displayedValue == "Not a Unix epoch: 'x' at position 3 is not a digit.")
        }
    }

    /// D-89's override, asserted where the user would see it: the SAME input
    /// renders different values under the two segments.
    @Test("changing the segment changes what the cells render")
    func changingTheSegmentChangesWhatTheCellsRender() {
        let asDate = cells("20260904", as: .iso8601)
        let asEpoch = cells("20260904", as: .unixEpoch)
        #expect(asDate.first?.value == "1788480000")
        #expect(asEpoch.first?.value == "20260904")
        #expect(asDate.first?.value != asEpoch.first?.value)
    }

    /// The detector drives the selection until the user chooses otherwise, and
    /// the choice then wins whatever the detector would have said.
    @Test("the selection is the detector's until the user makes one")
    func theSelectionIsTheDetectorsUntilTheUserMakesOne() {
        #expect(effectiveReadAs(for: "20260904", chosen: nil) == .iso8601)
        #expect(effectiveReadAs(for: InputExample.timestamps, chosen: nil) == .unixEpoch)
        #expect(effectiveReadAs(for: "not a timestamp", chosen: nil) == .localTime)
        #expect(effectiveReadAs(for: "20260904", chosen: .unixEpoch) == .unixEpoch)
        #expect(effectiveReadAs(for: InputExample.timestamps, chosen: .localTime) == .localTime)
    }

    /// The zone is read, and it is read by exactly one of the three cells.
    ///
    /// Asserted as a difference rather than against a literal, which is the
    /// only honest assertion available for a region-dependent rendering.
    @Test("the zone changes the date-and-time cell and nothing else")
    func theZoneChangesTheDateAndTimeCellAndNothingElse() {
        let here = cells(InputExample.timestamps, as: .unixEpoch, in: Self.utc)
        let there = cells(InputExample.timestamps, as: .unixEpoch, in: Self.losAngeles)
        let epochs = (here.first?.value, there.first?.value)
        #expect(epochs.0 == epochs.1, "the epoch is an instant and does not move with the zone")
        let dateTimes = (here.last?.value, there.last?.value)
        #expect(dateTimes.0 != dateTimes.1, "the date-and-time cell ignored the zone it was given")
        #expect(dateTimes.0?.isEmpty == false)
        #expect(dateTimes.1?.isEmpty == false)
    }

    /// Both `ViewThatFits` branches read a cell's strings from here and nowhere
    /// else, so the harvest cannot depend on the runner's window size.
    @Test("a cell contributes exactly its title and its displayed value")
    func aCellContributesExactlyItsTitleAndItsDisplayedValue() {
        for input in ["", InputExample.timestamps, "12x4"] {
            for cell in cells(input, as: .unixEpoch) {
                #expect(cell.harvestStrings == [cell.title, cell.displayedValue])
                #expect(cell.harvestStrings.allSatisfy { !$0.isEmpty })
            }
        }
    }

    /// The strip names the segment in force, resolved from the catalog rather
    /// than composed in English at a call site.
    @Test("the valid diagnostic names the segment in force")
    func theValidDiagnosticNamesTheSegmentInForce() {
        #expect(readAsDiagnostic(.unixEpoch) == "Read as Unix epoch.")
        #expect(readAsDiagnostic(.iso8601) == "Read as ISO 8601.")
        #expect(readAsDiagnostic(.localTime) == "Read as Local time.")
        #expect(Set(ReadAs.allCases.map(readAsDiagnostic)).count == 3)
    }

    /// Every segment resolves to the catalog string the UI-SPEC assigns it.
    @Test("every segment resolves to its inventory string")
    func everySegmentResolvesToItsInventoryString() {
        let expected: [ReadAs: String] = [
            .unixEpoch: "Unix epoch",
            .iso8601: "ISO 8601",
            .localTime: "Local time"
        ]
        #expect(expected.count == ReadAs.allCases.count)
        for readAs in ReadAs.allCases {
            #expect(localizedSentence(key: readAs.stringKey) == expected[readAs])
        }
    }

    /// The chain is rooted at a CELL and the value is re-derived, so editing the
    /// input cannot leave a chained card showing a result from input the user no
    /// longer has (D-84).
    @Test("a chained step is re-derived from the cell it was rooted at")
    func aChainedStepIsReDerivedFromTheCellItWasRootedAt() {
        let model = AppModel.preview
        model.timestamps.input = InputExample.timestamps
        model.timestampsChainRoot = .epoch
        model.timestamps = Pipeline(input: model.timestamps.input, steps: [Step(operation: .md5)])

        let rooted = cells(model.timestamps.input, as: .unixEpoch).first?.value
        #expect(rooted == "1767225600")
        let chained = Pipeline(input: rooted ?? "", steps: model.timestamps.steps).evaluate().first
        #expect(chained == .value(DigestCodec.md5("1767225600")))

        model.timestamps.input = "1767225601"
        let moved = cells(model.timestamps.input, as: .unixEpoch).first?.value
        #expect(moved == "1767225601")
        let rechained = Pipeline(input: moved ?? "", steps: model.timestamps.steps).evaluate().first
        #expect(rechained != chained, "the chained card kept a digest of input the user no longer has")
    }

    // MARK: - The footer's index mapping on this surface (plan 07-08)

    /// A surface with a chain rooted at the epoch cell and `operations`
    /// appended below it.
    ///
    /// The root card here is the three-cell card, and `model.timestamps.steps`
    /// holds ONLY appended cards — so both offsets are 0, which is true of this
    /// surface and of no other. Encode synthesises its root step into the
    /// states; Hashing keeps its chain root in `steps`.
    private func chainedSurface(appending operations: [Operation]) -> TimestampsSurface {
        let model = AppModel.isolated()
        model.timestamps.input = InputExample.timestamps
        model.timestampsChainRoot = .epoch
        model.timestamps = Pipeline(
            input: InputExample.timestamps,
            steps: operations.map { Step(operation: $0) }
        )
        return TimestampsSurface(model: model)
    }

    @Test("every appended step is an appended card, and the model index is the appended index")
    func everyAppendedStepIsAnAppendedCard() {
        let surface = chainedSurface(appending: [.base64Encode, .md5, .sha1])
        let cards = surface.appendedCards
        #expect(surface.model.timestamps.steps.count == 3)
        #expect(cards.count == 3, "this surface's steps and its appended cards are the same set")
        #expect(!cards.isEmpty)
        for card in cards {
            #expect(card.position.modelOffset == 0)
            #expect(card.position.modelIndex == card.position.appendedIndex)
            #expect(card.position.visibleOrdinal == card.position.appendedIndex + 2)
            #expect(card.position.totalCards == 4)
        }
        #expect(cards.first?.position.visibleOrdinal == 2, "the first appended card is Step 2, not Step 1")
        #expect(cards.last?.position.visibleOrdinal == 4)
        #expect(cards.first?.position.canMoveUp == false)
        #expect(cards.last?.position.canMoveDown == false)
    }

    @Test("removing a middle card is a splice, and every survivor is a step that existed")
    func removingAMiddleCardIsASplice() {
        let surface = chainedSurface(appending: [.base64Encode, .md5, .sha1])
        let before = surface.appendedCards
        #expect(before.count == 3)
        let target = before.dropFirst().first
        #expect(target != nil)
        #expect(target?.step.operation == .md5)
        #expect(target?.position.modelIndex == 1)

        if let target {
            surface.remove(target.position)
        }

        let after = surface.appendedCards
        #expect(after.count == 2, "the removal was a truncation rather than a splice")
        #expect(after.map(\.step.operation) == [.base64Encode, .sha1])
        #expect(Set(after.map(\.step.id)).isSubset(of: Set(before.map(\.step.id))))
        // The card below the removal renumbers, which is the feedback that
        // replaces the animation this phase deliberately does not have.
        #expect(after.last?.position.visibleOrdinal == 3)
    }

    @Test("a move swaps exactly the two adjacent cards and carries their identities")
    func aMoveSwapsExactlyTheTwoAdjacentCards() {
        let surface = chainedSurface(appending: [.base64Encode, .md5, .sha1])
        let before = surface.appendedCards
        #expect(before.count == 3)
        let identities = Set(before.map(\.step.id))
        let middle = before.dropFirst().first
        #expect(middle != nil)

        if let middle {
            #expect(middle.position.destinationIndex(.up) == 0)
            surface.move(middle.position, .up)
        }

        let after = surface.appendedCards
        #expect(after.map(\.step.operation) == [.md5, .base64Encode, .sha1])
        // A swap carries `Step.id` rather than renumbering it, which is what
        // the ForEach identity needs and why `Step.id` is a `let`.
        #expect(Set(after.map(\.step.id)) == identities)
        #expect(after.count == before.count)
        // The bottom card did not move and still cannot sink.
        #expect(after.last?.step.operation == .sha1)
        #expect(after.last?.position.canMoveDown == false)
    }
}
