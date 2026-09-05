// TimestampTests, continued — the timezone picker's option list and the
// selection it did not contain (CR-02, plan 06-20, GAP-06-02).
//
// Same suite as TimestampTests.swift, so
// `-only-testing:AppMacOSTests/TimestampTests` runs both halves. A second FILE
// because `swiftlint --strict` enforces file_length (400); an `extension`
// keeps the suite whole rather than minting a second suite name a
// `-only-testing:` invocation could silently miss.
//
// WHAT WAS WRONG, AND WHY THE OLD TEST WAS GREEN ANYWAY
//
// `TimeZone.current.identifier` is NOT guaranteed to be a member of
// `TimeZone.knownTimeZoneIdentifiers` — that table omits tzdata LINK names,
// and several of them are what Apple platforms report for the system zone.
// Measured on this tree at 929ba9c against 443 known identifiers:
//
//   Asia/Kolkata  America/Buenos_Aires  Asia/Istanbul  US/Pacific
//   Asia/Saigon   Africa/Asmera         Atlantic/Faeroe  UTC
//
// all resolve through `TimeZone(identifier:)` and are all ABSENT from the
// list. When the device zone is one of them the `Picker`'s selection matches
// no `.tag`: the closed menu renders with no label, and SwiftUI emits a
// runtime issue on every evaluation of that body — at typing rate, since D-83
// rebuilds the Timestamps body per keystroke.
//
// The assertion that was supposed to catch this read
// `timeZoneIdentifiers.contains(defaultTimeZone.identifier)` — against the
// RUNNER'S zone. This machine and CI are both `America/Los_Angeles`, which IS
// in the table, so the check was green here and on CI and red on an
// India-configured device. A correct check pointed at the wrong POPULATION,
// which is the blocking anti-pattern this phase inherited and, in this one
// case, committed.
//
// SO THESE TESTS INJECT THE HOSTILE ZONE RATHER THAN READING THE RUNNER'S.
//
// Two populations, on purpose. `Self.linkNameProbes` is filtered against the
// LIVE table at run time rather than trusted as a list, because tzdata moves
// and a hard-coded "these are absent" would become a control that cannot fire
// the day one of them is promoted. And one synthetic name the platform table
// can never contain is driven too, so the guarantee still has an input that
// can fail even if every real link name were promoted at once.

import Foundation
import Testing

extension TimestampTests {
    /// Names that resolve through `TimeZone(identifier:)` and may or may not
    /// be in `TimeZone.knownTimeZoneIdentifiers`. Filtered live below.
    static let linkNameProbes = [
        "Asia/Kolkata", "America/Buenos_Aires", "Asia/Istanbul", "US/Pacific",
        "Asia/Saigon", "Africa/Asmera", "Atlantic/Faeroe", "UTC"
    ]

    /// A name no platform table contains, so the guarantee below has an input
    /// that can fail regardless of what tzdata does next.
    static let syntheticAbsentZone = "Etc/NoSuchZoneInAnyTable"

    /// The probes that are, right now, resolvable AND absent from the list the
    /// picker is populated from. Measured, never assumed.
    static var absentLinkNames: [String] {
        let known = Set(TimestampCodec.timeZoneIdentifiers)
        return linkNameProbes.filter { TimeZone(identifier: $0) != nil && !known.contains($0) }
    }

    // MARK: - CR-02

    /// The population this guarantee exists for is not empty.
    ///
    /// Asserted FIRST and separately, because every expectation below is
    /// vacuously true over an empty set. If this ever fails it is not a
    /// regression in the app — it is tzdata having moved, and the probe list
    /// needs re-measuring rather than the assertion relaxing.
    @Test
    func theHostilePopulationIsNotEmpty() {
        let absent = Self.absentLinkNames
        let reMeasure = "no probe is both resolvable and absent any more — re-measure "
            + "TimeZone.knownTimeZoneIdentifiers against link names rather than relaxing this"
        #expect(!absent.isEmpty, "\(reMeasure)")
        #expect(TimeZone(identifier: Self.syntheticAbsentZone) == nil, "the synthetic name must stay unresolvable")
        let synthetic = TimestampCodec.timeZoneIdentifiers.contains(Self.syntheticAbsentZone)
        #expect(!synthetic, "the platform table does not contain the synthetic name")
    }

    /// The picker's options always contain its selection, for a zone the
    /// platform table omits.
    ///
    /// This is the guarantee CR-02 says was missing. It is driven with an
    /// INJECTED link name, not with `TimeZone.current`, which is the whole
    /// point: reading the runner's zone is what made the old check green.
    @Test
    func theOptionListAlwaysContainsTheSelection() {
        var driven = 0
        for name in Self.absentLinkNames + [Self.syntheticAbsentZone] {
            let options = TimestampCodec.timeZoneIdentifiers(including: name)
            // A `Bool` local, not `options.contains(...)` inline: Swift Testing
            // expands the operands of a failed expectation, and expanding a
            // 443-element array buries the transcript the evidence is read from.
            let offered = options.contains(name)
            #expect(offered, "\(name) is the selection, so it must be one of the \(options.count) options")
            driven += 1
        }
        #expect(driven >= 2, "driven against \(driven) selections the platform table omits")
    }

    /// Including a selection keeps the ordering and the de-duplication the
    /// list already promised — a repeated identifier collides as a `ForEach`
    /// id, and an unsorted list is not the one APP-07 specifies.
    @Test
    func includingASelectionPreservesOrderAndUniqueness() {
        for name in Self.absentLinkNames + [Self.syntheticAbsentZone] {
            let options = TimestampCodec.timeZoneIdentifiers(including: name)
            let ascending = options == options.sorted()
            #expect(ascending, "\(name): still ascending")
            #expect(options.count == Set(options).count, "\(name): still free of duplicates")
            #expect(options.count == TimestampCodec.timeZoneIdentifiers.count + 1,
                    "\(name): exactly one option added")
        }
    }

    /// A selection the table already has adds nothing — the list does not grow
    /// by one every time the picker is rendered.
    @Test
    func includingAZoneAlreadyInTheTableChangesNothing() {
        let present = TimestampCodec.timeZoneIdentifiers.first ?? "Africa/Abidjan"
        let unchanged = TimestampCodec.timeZoneIdentifiers(including: present) == TimestampCodec.timeZoneIdentifiers
        #expect(unchanged, "a selection already in the table adds no option")
    }

    /// The VIEW's own option list, not just the codec's.
    ///
    /// `TimeZonePicker.options` is what `body`'s `ForEach` iterates, so this
    /// asserts the thing that ships rather than a function the view might have
    /// been wired to. The model is driven to a link-name zone the way a device
    /// in India arrives already configured.
    @Test
    @MainActor
    func thePickerViewOffersTheZoneTheModelIsSetTo() {
        for name in Self.absentLinkNames {
            guard let zone = TimeZone(identifier: name) else { continue }
            let model = AppModel()
            model.timestampsTimeZone = zone
            let offered = TimeZonePicker(model: model).options.contains(zone.identifier)
            #expect(offered, "the closed menu renders the selection, so \(name) must be tagged among the options")
        }
    }

    /// The list is computed once and reused, not rebuilt per access.
    ///
    /// WR-07: `TimeZonePicker.body` reads this inside a `ForEach` and the
    /// Timestamps body is rebuilt per keystroke under D-83's no-debounce rule,
    /// so a computed `static var` meant a 443-element `Set` construction plus a
    /// string sort per character typed. Identity is the honest assertion —
    /// equality would hold either way.
    @Test
    func theTableIsBuiltOnceAndNotPerAccess() {
        let first = TimestampCodec.timeZoneIdentifiers
        let second = TimestampCodec.timeZoneIdentifiers
        #expect(first.withUnsafeBufferPointer { $0.baseAddress } == second.withUnsafeBufferPointer { $0.baseAddress },
                "the same storage, so nothing is rebuilt on the keystroke path")
    }
}
