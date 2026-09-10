import XCTest

// CR-02 / D-98, ON THE POPULATION THE DEFECT WAS REPORTED FROM — AND WITHOUT TOUCHING THE MACHINE.
//
// THE DEFECT. A SwiftUI `Picker` whose selection matches no `.tag` renders a BLANK closed menu.
// `TimeZonePicker`'s selection is the device's own zone identifier and its option list was once
// `TimeZone.knownTimeZoneIdentifiers` alone. Foundation's curated table keeps the LEGACY name
// `Asia/Calcutta` and omits the MODERN `Asia/Kolkata`, so a device on Kolkata selected a value the
// list did not offer and the control came up empty. `UTC` sits in the same gap, so this was never
// India-specific — a runner on UTC rendered the same blank menu.
//
// WHY THE ORIGINAL ASSERTION WAS GREEN THROUGHOUT. It ran on a Mac in `America/Los_Angeles`, which
// IS in the table. A check correct in form, pointed at the wrong population, by geography — this
// phase's signature defect, and the reason the environment below is stated rather than inherited.
//
// WHAT THIS FILE ADDS THAT `LaunchLayoutTests` DOES NOT. Its corruption case pins the zone through
// the ARGUMENT DOMAIN, so it measures an unresolvable STORED value. That is a different subject:
// the defect is about `TimeZone.current` ITSELF being outside the table, which no pinned value can
// reproduce. This drives the real `.current` path.
//
// HOW THE DEVICE ZONE IS REACHED, AND WHY NOT THROUGH SETTINGS. `xcrun simctl` has no time-zone
// subcommand [measured 2026-09-10, Xcode 26.1.1 — `status_bar --time` sets the displayed clock, not
// the zone], and `07-UAT.md` verification 3 therefore specified eleven Settings.app steps by hand,
// including putting the simulator back afterwards. Measured instead, 2026-09-10, on iPhone SE (3rd
// generation): `XCUIApplication.launchEnvironment["TZ"]` DOES move `TimeZone.current` inside the
// app. Three cases, two of them controls — unset read `America/Los_Angeles`, `Asia/Kolkata` read
// `Asia/Kolkata`, `Europe/Dublin` read `Europe/Dublin`. Both controls moved, so the gap reading is
// real and not a coincidence or a value left behind by an earlier run.
//
// WHAT THAT EQUIVALENCE IS AND IS NOT. `TZ` moves the PROCESS's zone, not the DEVICE's. The app
// reads its zone through `TimeZone.current` and nothing else, so the code path under test is the
// one a Kolkata device drives — but this does NOT exercise Settings.app, the system's own zone
// store, or anything that observes zone CHANGES while running. It is stated here as an
// equivalence with a boundary rather than left to be read as identity.
//
// AND WHAT IT BUYS: nothing on the simulator is mutated, so there is no restore step to forget.
final class TimeZoneGapTests: XCTestCase {
    /// The identifier the original report came from, and the reason it is the right probe: it
    /// RESOLVES through `TimeZone(identifier:)` and is ABSENT from `knownTimeZoneIdentifiers`.
    /// Re-measured 2026-09-06 over all 604 files under `/usr/share/zoneinfo`: 598 resolve, the
    /// known table holds 443, and 155 identifiers resolve while being absent from it.
    private static let gapZone = "Asia/Kolkata"

    /// Dynamic Type `.large`, pinned as the default rather than clamped — `LaunchLayoutTests`'
    /// rationale, restated here because an environment a test INHERITS is an environment nobody
    /// reads.
    private static let environmentPinning = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    /// Verification 3, end to end: the closed control renders the gap zone, the open list carries it
    /// as its one chosen row, and a different choice survives a full quit and relaunch.
    func testAZoneAbsentFromTheKnownTableRendersOpensAndSurvivesARelaunch() {
        // WHAT IS ALREADY ON DISK IS READ FIRST, AND IT IS READ BECAUSE IT CAN MASK A REGRESSION.
        // The row this test changes to is picked deterministically, so two runs in a row pick the
        // SAME zone — and if the app stopped persisting today, the value yesterday's working run
        // wrote would still be on disk and the relaunch assertion below would pass on a broken app.
        // That is this phase's signature defect exactly: a check correct in form, satisfied by the
        // wrong source. So the pre-existing value is read, recorded, and excluded from the choice.
        // THE SURFACE IS PINNED HERE AND THE ZONE IS NOT, AND THE DIFFERENCE IS THE WHOLE POINT.
        // This launch's job is to read what the STORE holds for the zone, so pinning the zone would
        // defeat it — but the app has to be ON Timestamps for the control to exist at all, and with
        // NOTHING pinned it opens whereever the store's `selection` says, which on a store that has
        // never been written is the declared default `.encode`.
        //
        // THAT IS NOT HYPOTHETICAL: it is how this test first failed. It passed on this machine and
        // failed on BOTH CI simulator jobs — "the time-zone control is not rendered at all" — because
        // the local simulator had `selection` left at `timestamps` by earlier runs and CI's was
        // clean. A check that was green only because of state an earlier run left behind, pointed at
        // a surface that was not on screen. Reproduced locally by uninstalling the app first, which
        // is the only way to make this machine resemble a runner.
        launch(zone: Self.gapZone, pinning: LaunchState.onlySurface(LaunchState.timestampsDestination))
        let preexisting = closedSelection()
        record("cr02_preexisting=\(preexisting)")
        app.terminate()

        // THE STORE IS NEUTRALISED, NOT TRUSTED. Whatever an earlier run left in this app's
        // defaults would otherwise be restored and `TimeZone.current` would never be consulted —
        // and the test would then be measuring the store while claiming to measure the device.
        // `Mars/Olympus` is `LaunchState`'s measured unresolvable value: the argument domain
        // outranks the store, `TimeZone(identifier:)` declines it, and `hydrate()` keeps the
        // declared default, which is `.current`. So the first launch reads the device zone no
        // matter what is on disk.
        launch(zone: Self.gapZone,
               pinning: LaunchState.onlySurface(LaunchState.timestampsDestination)
                   + LaunchState.timeZoneTheSystemRejects)

        // STEP 6 — the whole point of the item: read the closed label.
        let closed = closedSelection()
        record("cr02_closed_label=\(closed)")
        XCTAssertFalse(closed.isEmpty, "the closed time-zone control renders NOTHING — CR-02's exact failure, "
            + "a Picker whose selection matches no tag. \(describeControl())")
        XCTAssertEqual(closed, Self.gapZone, "the closed control reads \(closed) and not \(Self.gapZone), so the "
            + "device zone is not what this test believes it to be and every claim below is about the wrong "
            + "population. \(describeControl())")

        // STEPS 7 AND 8 — the chosen row is marked in the open list, then the selection is moved.
        guard let picked = openTheMenuAndChangeTheZone(avoiding: preexisting) else { return }

        // The change has to have taken effect IN THIS SESSION before a relaunch can say anything
        // about it surviving one.
        let afterTap = closedSelection()
        record("cr02_after_tap=\(afterTap)")
        XCTAssertEqual(afterTap, picked, "the control still reads \(afterTap) after \(picked) was tapped, so "
            + "nothing was changed and there is nothing for the relaunch to restore")

        // STEPS 9 AND 10 — a full quit, then a launch with NOTHING pinning the zone.
        app.terminate()
        relaunchWithTheZoneUnpinned(zone: Self.gapZone)

        // The surface is RECORDED, NOT ASSERTED. Nothing here persisted a destination — the first
        // launch pinned it through the argument domain, which does not write — so which surface
        // reopens is not this test's claim. `testCriterion3TheAppReopensOnTheLastUsedSurfaceWithSettingsIntact`
        // is the file that carries it, against a destination it actually changed.
        record("cr02_reopened_on=\(surfaceShowing())")
        navigateToTimestamps()

        let restored = closedSelection()
        record("cr02_restored=\(restored) expected=\(picked)")
        XCTAssertFalse(restored.isEmpty, "the control renders NOTHING after the relaunch. \(describeControl())")
        XCTAssertEqual(restored, picked, "the control reopened as \(restored), not as the \(picked) it was left "
            + "on — and the device zone is still \(Self.gapZone), so a store that was ignored would read "
            + "\(Self.gapZone) here, and one left over from an earlier run would read \(preexisting). "
            + "\(describeControl())")
    }

    /// Steps 7 and 8: assert the open list marks the gap zone as its one chosen row, then move the
    /// selection to a row that is neither the starting value nor whatever is already on disk.
    ///
    /// STEP 8'S ZONE IS READ FROM THE LIST, NOT NAMED. `Europe/Dublin`, which `07-UAT.md` names, is
    /// NOT reachable: the menu renders a window of roughly sixteen rows AROUND the selection
    /// [measured — with Kolkata chosen the window ran `Asia/Kamchatka`..`Asia/Muscat`], so Dublin
    /// does not exist to be tapped. The requirement the step actually carries is "a zone that is not
    /// the starting one", and that is what is taken — by reading the population rather than by
    /// naming a row and hoping it is on screen.
    ///
    /// Returns nil only after failing, so the caller stops rather than asserting on a dead surface.
    private func openTheMenuAndChangeTheZone(avoiding preexisting: String) -> String? {
        XCTAssertEqual(optionRows().count, 0, "zone rows are queryable while the menu is CLOSED, so the counts "
            + "below would not show that the tap opened anything")
        control().tap()
        let rows = optionRows()
        let chosen = rows.filter(\.isSelected).map(\.label)
        record("cr02_open_rows=\(rows.count) chosen=\(chosen)")
        XCTAssertGreaterThan(rows.count, 0, "the tap opened no menu at all: no button carries a resolvable zone "
            + "identifier as its label")
        XCTAssertEqual(chosen, [Self.gapZone], "the open list marks \(chosen) as chosen, not [\(Self.gapZone)] — "
            + "a list with no checked row at all is the second half of CR-02's failure")

        guard let target = rows.first(where: {
            !$0.isSelected && $0.isHittable && $0.label != preexisting
        }) else {
            XCTFail("no rendered zone row is unchosen, hittable and different from the \(preexisting) already on "
                + "disk, so nothing can be changed to a value the store could not already hold")
            return nil
        }
        let picked = target.label
        record("cr02_changed_to=\(picked)")
        XCTAssertNotEqual(picked, Self.gapZone, "the row picked to change to IS the starting value, so the "
            + "relaunch would pass without anything having been persisted")
        XCTAssertNotEqual(picked, preexisting, "the row picked to change to is what was ALREADY on disk, so an app "
            + "that persisted nothing today would still satisfy the relaunch assertion")
        target.tap()
        return picked
    }

    // MARK: - Driving

    /// A fresh app at a pinned process zone, pinned Dynamic Type and the given settings.
    private func launch(zone: String, pinning: [String]) {
        app = XCUIApplication()
        app.launchArguments = Self.environmentPinning + pinning
        app.launchEnvironment["TZ"] = zone
        record("cr02_launch tz=\(zone) arguments=\(app.launchArguments)")
        app.launch()
    }

    /// The relaunch this test turns on: the process zone is STILL the gap zone, and NO settings key
    /// is pinned, so the zone can only come off disk.
    ///
    /// THE ARGUMENTS ARE RECORDED RATHER THAN ASSUMED, for `relaunchWithNothingPinned`'s reason:
    /// this method's entire claim is that nothing pins the zone on the second launch, and what the
    /// second launch actually carries is the only evidence for it.
    private func relaunchWithTheZoneUnpinned(zone: String) {
        let reopened = XCUIApplication()
        reopened.launchArguments = Self.environmentPinning
        reopened.launchEnvironment["TZ"] = zone
        record("cr02_relaunch tz=\(zone) arguments=\(reopened.launchArguments)")
        reopened.launch()
        app = reopened
    }

    private func navigateToTimestamps() {
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 20), "the app presents no tab bar at all")
        XCTAssertEqual(bar.buttons.count, 3, "the tab bar carries \(bar.buttons.count) items, expected 3")
        bar.buttons.element(boundBy: 2).tap()
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: AccessibilityIdentifiers.Timestamps.input)
                .firstMatch.waitForExistence(timeout: 20),
            "cannot reach the Timestamps surface — tab item 2 does not show its input"
        )
    }

    /// Which surface is showing, by its input identifier. Recorded, never asserted, here.
    private func surfaceShowing() -> String {
        let probes = [(AccessibilityIdentifiers.Encode.input, "encode"),
                      (AccessibilityIdentifiers.Hashing.input, "hashing"),
                      (AccessibilityIdentifiers.Timestamps.input, "timestamps")]
        var found: [String] = []
        for (identifier, name) in probes {
            let probe = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            if probe.waitForExistence(timeout: found.isEmpty ? 30 : 1) {
                found.append(name)
            }
        }
        return found.joined(separator: "+")
    }

    // MARK: - Reading

    private func control() -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: AccessibilityIdentifiers.Timestamps.timeZone).firstMatch
    }

    /// What the CLOSED `.menu` `Picker` reports as its selection, in the shape this suite measured
    /// on iOS: `value` is empty and the selection is the TRAILING comma-separated component of the
    /// label — `label="Time zone, GMT"`. Returning the WHOLE label would answer "Time zone" for a
    /// control with NOTHING selected, which is the exact false pass CR-02 is about.
    private func closedSelection() -> String {
        let control = control()
        XCTAssertTrue(control.waitForExistence(timeout: 30), "the time-zone control is not rendered at all")
        if let title = control.value as? String, !title.isEmpty {
            return title
        }
        let parts = control.label.components(separatedBy: ", ")
        return parts.count > 1 ? parts[parts.count - 1] : ""
    }

    /// The OPEN menu's option rows.
    ///
    /// POPULATION, AND WHY IT IS FILTERED RATHER THAN COUNTED. The open menu publishes its rows as
    /// BUTTONS — `menuItems` and `cells` are both empty on iOS [measured 2026-09-10] — but
    /// `app.buttons` is the WHOLE app's buttons, and three of them report `isSelected` with the
    /// menu open: the Timestamps TAB, the chosen zone, and the "Local time" segment of the Read as
    /// control. A count over `app.buttons` would therefore be a check correct in form over the
    /// wrong population, which is the defect this phase kept finding. The rows are narrowed to
    /// buttons whose LABEL RESOLVES as a time zone, which is what an option of this picker is and
    /// which no other control in the app satisfies — the closed control's own label,
    /// `"Time zone, Asia/Kolkata"`, does not resolve.
    private func optionRows() -> [XCUIElement] {
        let buttons = app.buttons
        return (0 ..< buttons.count)
            .map { buttons.element(boundBy: $0) }
            .filter { TimeZone(identifier: $0.label) != nil }
    }

    /// Everything a failing read could need, so a red run does not require a second run to diagnose.
    private func describeControl() -> String {
        let control = control()
        return "exists=\(control.exists) value=\(String(describing: control.value)) label=\(control.label)"
    }

    private func record(_ line: String) {
        print(line)
        XCTContext.runActivity(named: line) { _ in }
    }
}
