// TimestampCells — the three representation cells of one instant, as DATA
// first and views second (D-87, D-88, 06-UI-SPEC.md §"3. Timestamps — one
// instant, several representations side by side").
//
// THE CELL IS THE VISUAL UNIT HERE, and that is what carries D-87. Encode is a
// single in→out block; Hashing is a four-row aligned table; this surface is a
// grid of bordered boxes, each one a different WAY OF WRITING the same instant.
// A checker should be able to tell the three apart with the text blurred out.
//
// WHY THE STATES ARE COMPUTED AS DATA AND NOT INSIDE A VIEW BODY. `ViewThatFits`
// picks a branch from the width the runner happens to offer. If the two branches
// derived their strings independently, plan 06-16's harvested population would
// silently depend on the window size — a correct check pointed at a
// window-dependent population, which is this phase's own failure class. Both
// branches below render the SAME `[TimestampCell]` through the same leaf view,
// so UI-SPEC Harvest rule 5 holds by construction, and `TimestampsSurfaceTests`
// asserts the array rather than reading this file.
//
// THE FIT IS DECIDED ON A DECLARED IDEAL WIDTH, NOT ON THE VALUE'S OWN. 06-12
// measured that `ViewThatFits` reads each branch's IDEAL width, so a branch
// built from views with no width opinion always "fits" and the fallback becomes
// dead code. An output block is `maxWidth: .infinity` and has no opinion, so the
// two-column branch declares the narrowest width at which a monospaced ISO 8601
// value is still legible, scaled with Dynamic Type. Below that the grid folds to
// one column with identical strings — which is also why the macOS window has a
// declared 720 pt minimum: side by side is the whole point of this layout.
//
// THE STACK CONTAINERS HERE ARE EAGER, NEVER THE DEFERRED KIND. 06-11 measured
// the deferred variant at 77% population loss for plan 06-16's sweep with every
// assertion still passing. The forbidden container is described and never
// spelled, because this plan's acceptance criteria sweep this directory for it.

import SwiftUI

// MARK: - What the surface concluded about the input

/// The instant the surface is showing, or why there is not one.
///
/// Three cases rather than an optional pair, so "nothing typed yet" and "typed
/// something that does not parse" cannot be confused — they render differently
/// and only one of them is an error of the user's making.
enum TimestampOutcome: Equatable, Sendable {
    /// The input is empty (or is only whitespace). The Empty state, never a
    /// conversion failure: converting nothing is not a conversion that went
    /// wrong (UI-SPEC §State Contract 1).
    case empty

    /// Seconds since 1970, as `TimestampDetection.parse` read them.
    case instant(Double)

    /// The named reason and the character position, unchanged from the engine.
    case failure(ConversionFailure)
}

/// What `input` denotes when read as `readAs`, with local time resolved in
/// `timeZone`.
///
/// Recomputed on every pass and never stored — `AppModel` holds the OVERRIDE
/// and the ZONE, which the user chose, and nothing that is derived from them
/// (D-84's premise). A stored instant would be a value that outlives the input
/// it came from.
func timestampOutcome(for input: String, readAs: ReadAs, timeZone: TimeZone) -> TimestampOutcome {
    guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return .empty
    }
    switch TimestampDetection.parse(input, as: readAs, timeZone: timeZone) {
    case let .success(instant): return .instant(instant)
    case let .failure(reason): return .failure(reason)
    }
}

/// The segment the picker shows for `input`: the user's choice when they have
/// made one, and the detector's otherwise (D-89).
///
/// `nil` is not a fourth segment — it is the ABSENCE of a choice, which is why
/// `AppModel.timestampsReadAs` is optional and why the `Detect` control's whole
/// job is to put it back to `nil`.
func effectiveReadAs(for input: String, chosen: ReadAs?) -> ReadAs {
    chosen ?? TimestampDetection.segment(for: TimestampDetection.detect(input))
}

// MARK: - The three representations

extension TimestampRepresentation {
    /// The `AccessibilityIdentifiers.Timestamps.cell*` constant this cell's
    /// value carries. Never a string literal at a use site.
    var identifier: String {
        switch self {
        case .epoch: AccessibilityIdentifiers.Timestamps.cellEpoch
        case .iso8601: AccessibilityIdentifiers.Timestamps.cellISO8601
        case .dateTime: AccessibilityIdentifiers.Timestamps.cellDateTime
        }
    }

    /// `instant` written this way, in `timeZone`.
    ///
    /// - Note: **There is no fourth "local time" cell, and that is a decision
    ///   rather than an omission.** APP-05 asks for a conversion "to local
    ///   time"; the zone picker beside these cells DEFAULTS to the device's own
    ///   zone, so with the picker untouched the selected zone *is* the local
    ///   zone and ``dateTime`` already IS the local-time representation. A
    ///   fourth cell would render the same string as this one until the user
    ///   changed the picker, and then disagree with it for no stated reason.
    func render(_ instant: Double, in timeZone: TimeZone) -> String {
        switch self {
        case .epoch: TimestampCodec.renderEpochSeconds(instant)
        case .iso8601: TimestampCodec.renderISO8601(instant, timeZone: timeZone)
        case .dateTime: TimestampCodec.renderDateTime(instant, timeZone: timeZone)
        }
    }
}

/// One representation cell: which one it is, its selector, and what it shows.
///
/// A value type computed fresh from the input on every pass — the same shape
/// `DigestRow` takes on the Hashing surface, and for the same reason: nothing
/// derived is stored, so nothing here can go stale.
struct TimestampCell: Identifiable, Equatable, Sendable {
    /// Which of the three this is. Also its identity in the grid.
    let representation: TimestampRepresentation

    /// The selector attached to this cell's VALUE. A stored property rather
    /// than a computed one so a test can compare it against the constant.
    let identifier: String

    /// What this cell is showing, in the same four-state vocabulary every other
    /// output in the app uses.
    let state: StepRenderState

    /// Cells are identified by which representation they are.
    var id: TimestampRepresentation {
        representation
    }

    /// The cell's title, already localized. ``TimestampRepresentation``'s raw
    /// value **is** its catalog key, so the title and the selection are one
    /// string rather than two that can drift.
    var title: String {
        localizedSentence(key: representation.rawValue)
    }

    /// The value, when there is one. `nil` in the other three states, which is
    /// exactly when this cell's two controls are disabled.
    var value: String? {
        if case let .value(rendered) = state {
            return rendered
        }
        return nil
    }

    /// What the value area actually renders — never blank in any state
    /// (UI-SPEC §"State Contract").
    ///
    /// Mirrors `OutputBlock`, which is the view that renders it, so the two
    /// cannot disagree about what is on screen.
    var displayedValue: String {
        switch state {
        case .empty: localizedSentence(key: "timestamps.output.placeholder")
        case let .value(rendered): rendered
        case let .failure(reason): failureText(reason, in: .timestamps)
        case .blocked: blockedStepText()
        }
    }

    /// **The two strings this cell contributes to the harvest, and the only two
    /// places either layout branch reads a string from.**
    ///
    /// `TimestampsSurfaceTests` reads this array rather than eyeballing the
    /// file, which is what makes UI-SPEC Harvest rule 5 a measurement.
    var harvestStrings: [String] {
        [title, displayedValue]
    }
}

/// The three cells for one input, in the UI-SPEC's order.
///
/// All three are produced from ONE outcome, which is what makes them three
/// representations of one instant rather than three independent conversions —
/// and it is why a single field satisfies APP-05 and APP-06 together (D-88).
func timestampCells(for input: String, readAs: ReadAs, timeZone: TimeZone) -> [TimestampCell] {
    let outcome = timestampOutcome(for: input, readAs: readAs, timeZone: timeZone)
    return TimestampRepresentation.allCases.map { representation in
        TimestampCell(
            representation: representation,
            identifier: representation.identifier,
            state: cellState(representation, showing: outcome, in: timeZone)
        )
    }
}

/// One cell's render state for one outcome.
///
/// Exhaustive over ``TimestampOutcome`` with no catch-all branch, so a fourth
/// outcome is a compile error here rather than a blank cell on a screen. (That
/// branch keyword is described and not spelled, for the reason in the file
/// header.) A failure REPLACES every cell's value rather than leaving one of
/// them showing an older conversion — no output may survive the input it came
/// from (D-84).
private func cellState(
    _ representation: TimestampRepresentation,
    showing outcome: TimestampOutcome,
    in timeZone: TimeZone
) -> StepRenderState {
    switch outcome {
    case .empty: .empty
    case let .instant(instant): .value(representation.render(instant, in: timeZone))
    case let .failure(reason): .failure(reason)
    }
}

// MARK: - The cell, and the two layouts it appears in

/// One bordered representation cell: its title, its value, its own accessory.
///
/// **Its own accessory, one per cell**, which is the same per-OUTPUT rule the
/// Hashing surface's four digests follow — no selection mode and no implicit
/// "last touched" state on a card that renders three outputs.
struct TimestampCellView: View {
    /// The cell to render.
    let cell: TimestampCell

    /// Chains a new step from THIS cell's value.
    let onAddStep: (Operation) -> Void

    /// Title with the accessory on its trailing side, then the value block —
    /// in that order, in every state.
    ///
    /// **The accessory shares the TITLE ROW rather than owning a row beneath
    /// the value block, and that is criterion 5 rather than a preference**
    /// (amended 2026-09-06; the original arrangement, and 06-UI-SPEC's mockup
    /// of it, drew the accessory below the value block). Measured on iPhone SE
    /// (3rd generation), 375 × 667, portrait, Dynamic Type `.large`, at launch:
    /// with the accessory on its own row the first cell's add-step control sat
    /// at `(299, 626, 44, 44)` — under a tab bar whose top edge is y ≈ 618 and
    /// past the bottom of a 667 pt screen — so D-102 clause 2 was FALSE on this
    /// surface and `docs/REVIEW-ARGUMENTS.md`'s 4.3(b) "primary work surface"
    /// argument was false with it. Timestamps was the app's only output that
    /// let its accessory own a row: ``DigestRowView`` puts the accessory beside
    /// the value in BOTH of its branches, and `EncodeBody.outputSection` puts
    /// it on the "Output" label's row. This is that same house arrangement, and
    /// it reclaims the accessory's row plus one `Spacing.sm` per cell.
    ///
    /// **Still one accessory per CELL** (D-80, D-86, D-81/APP-08). Three cells,
    /// three add-step controls; nothing here consolidates them onto the card,
    /// which is the arrangement `OutputAccessory`'s own header rules out.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(verbatim: cell.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                OutputAccessory(
                    value: cell.value ?? "",
                    isEnabled: cell.value != nil,
                    onAddStep: onAddStep
                )
            }
            OutputBlock(
                state: cell.state,
                placeholder: "timestamps.output.placeholder",
                domain: .timestamps,
                valueIdentifier: cell.identifier
            )
            .copyableOutput(cell.value)
        }
    }
}

/// The three cells: two side by side and one across the width, or all three
/// stacked.
///
/// Both branches are built from the same `cells` array through the same
/// ``TimestampCellView``, so they carry identical strings by construction.
struct TimestampCellsView: View {
    /// The three cells, in the UI-SPEC's order.
    let cells: [TimestampCell]

    /// Chains a new step from one named cell's value.
    let onAddStep: (TimestampRepresentation, Operation) -> Void

    /// The narrowest a monospaced ISO 8601 value stays legible at, scaled with
    /// the text size. This is what the two-column branch is MEASURED on; see
    /// the file header for why declaring it is what keeps the fallback alive.
    @ScaledMetric(relativeTo: .body) private var minimumCellWidth: CGFloat = 196

    /// Two columns when they fit; one when they do not.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            twoColumns
            oneColumn
        }
    }

    /// The UI-SPEC's grid: epoch and ISO 8601 side by side, date and time
    /// across both columns beneath them.
    ///
    /// Built with `prefix` and `dropFirst` rather than by subscript. There is
    /// no index arithmetic here to go out of range, which matters because a
    /// Swift trap in a host-based bundle takes the whole run with it.
    private var twoColumns: some View {
        Grid(alignment: .topLeading, horizontalSpacing: Spacing.md, verticalSpacing: Spacing.md) {
            GridRow {
                ForEach(cells.prefix(2)) { cell in
                    cellView(cell)
                        .frame(idealWidth: minimumCellWidth, maxWidth: .infinity, alignment: .leading)
                }
            }
            GridRow {
                ForEach(cells.dropFirst(2)) { cell in
                    cellView(cell)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .gridCellColumns(2)
                }
            }
        }
    }

    /// The fallback: the same three cells, stacked, in the same order.
    private var oneColumn: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            ForEach(cells) { cell in
                cellView(cell)
            }
        }
    }

    /// One cell, wired to the chain callback with its own representation.
    private func cellView(_ cell: TimestampCell) -> some View {
        TimestampCellView(cell: cell) { operation in
            onAddStep(cell.representation, operation)
        }
    }
}
