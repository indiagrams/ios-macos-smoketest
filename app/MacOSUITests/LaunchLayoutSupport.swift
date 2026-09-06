import XCTest

// THE DRIVING HALF OF `LaunchLayoutTests`, SPLIT OUT FOR ONE MEASURED REASON: SwiftLint runs
// `--strict` here, which promotes `file_length`'s WARNING threshold to the real limit, so the
// budget is 400 lines and not the 1000 the error threshold names (UL-056). The assertions grew
// past it once the clause-2 failure had to carry its geometry, and 07-09 set the precedent for
// answering that with a move rather than with deleted prose — with the caveat 07-09 also
// recorded: **a move relocates a gate's population**, so `evidence/07-11-verify-twins.rb` reads
// BOTH files of each platform rather than the test file alone.
//
// NOTHING HERE ASSERTS A CRITERION. This file drives and queries; `LaunchLayoutTests.swift` holds
// every clause. The split is along that line deliberately, so "does a clause method interact with
// the surface before it asserts" stays answerable by reading one method and the helpers it names.
//
// D-107 ROUTE 1 IS THIS FILE'S WHOLE JOB: every query below is identifier-scoped, bounded and
// count-based, `exists` is consulted before any wait, and nothing waits on an element that should
// be ABSENT. macOS drives with `.click()` and navigates by sidebar constant; the iOS twin taps a tab index.

extension LaunchLayoutTests {
    /// A fresh application at the pinned environment and the pinned settings, then launched.
    func launch(_ destination: String) {
        app = XCUIApplication()
        app.launchArguments += Self.environmentPinning
        app.launchPinned(showing: destination)
    }

    /// The criterion-3 relaunch: a new process with NO setting pinned, so every value comes off disk.
    func relaunchWithNothingPinned() {
        let reopened = XCUIApplication()
        reopened.launchArguments = Self.environmentPinning
        // THE ARGUMENTS ARE RECORDED, NOT ASSUMED. This method's entire claim is that no
        // `SettingsKey` is pinned on the second launch, so what the second launch actually carries
        // is the evidence for it — and it is the one fact that, if wrong, would make every
        // assertion after it a statement about `NSArgumentDomain` instead of about the store.
        record("criterion3_relaunch_arguments=\(reopened.launchArguments)")
        reopened.launch()
        app = reopened
    }

    /// Every element carrying `identifier`.
    func all(_ identifier: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: identifier)
    }

    /// How many carry it right now — a count, never a doomed wait.
    func count(_ identifier: String) -> Int {
        all(identifier).count
    }

    /// The first carrying it.
    func element(_ identifier: String) -> XCUIElement {
        all(identifier).firstMatch
    }

    /// Wait for the pinned surface to be the one on screen, before anything is measured on it.
    func awaitSurface(_ probe: String, _ surface: String) {
        XCTAssertTrue(element(probe).waitForExistence(timeout: 30), "the app did not open on \(surface): no \(probe)")
    }

    /// Which of the three surfaces is showing, asserted to be exactly one.
    func surfaceShowing() -> String {
        var found: [String] = []
        for surface in Self.surfaces where element(surface.probe).waitForExistence(timeout: found.isEmpty ? 30 : 1) {
            found.append(surface.name)
        }
        XCTAssertEqual(found.count, 1, "\(found.count) surfaces are showing at once: \(found)")
        return found.first ?? ""
    }

    /// The window the clauses are measured at, resolved and recorded before anything is read from
    /// it, and asserted to honour the app's OWN declared minimum.
    ///
    /// **A GAP, STATED RATHER THAN CLAIMED SHUT.** Criterion 5 scopes clause 2 to 720 x 480 and
    /// this asserts AT OR ABOVE rather than AT: XCUITest cannot set a macOS window's size, and a
    /// corner-drag resize is a mechanism this suite cannot rehearse, because macOS UI tests do not
    /// run on this machine at all — an unrehearsed drag would ship straight into a required check.
    /// A LARGER window can only make clause 2 easier, so the size the verdict was taken at is
    /// recorded and the residual is named in `evidence/07-11-launch-layout.txt`.
    func assertTheMeasuredEnvironment(_ surface: String) -> CGRect {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 30), "no window resolved, so every frame below is at an unknown size")
        let frame = window.frame
        let honoured = frame.width >= Self.minimumWindow.width && frame.height >= Self.minimumWindow.height
        record("criterion5_screen_\(surface)=\(frame.width)x\(frame.height) atleastminimum=\(honoured)")
        XCTAssertTrue(honoured, "the window is \(describeRect(frame)), below the declared \(Self.minimumWindow) minimum")
        return frame
    }

    /// What a control reports as its selection, in the four shapes the platforms use: a title, a
    /// selected-segment index, its one chosen segment's label, or — for a `.menu` `Picker` — the
    /// trailing comma-separated component of its LABEL. **Empty means a control rendering WITHOUT a
    /// selection**, D-98's exact failure, so each shape is narrowed to exclude a non-answer: a
    /// NEGATIVE index is rejected rather than returned as `segment-1`, and the label is read only
    /// from its second component on. MEASURED on iOS 17.5, which is why that last branch exists:
    /// the time-zone picker reports `value=""` and `label="Time zone, GMT"`, so returning the WHOLE
    /// label would answer "Time zone" for a picker with NOTHING selected — the exact false pass
    /// this function is here to prevent.
    ///
    /// **BRANCH 3 IS macOS's, AND UNTIL 2026-09-06 IT ASKED THE WRONG QUESTION.** It filtered on
    /// `isSelected`, which XCUITest answers from `AXSelected`, and macOS never sets that attribute
    /// on a segmented picker — so branch 3 returned nothing for a control WITH a selection and
    /// nothing for one without, and this whole function was a constant `""` on this platform. That
    /// is what failed CI run 34050504430 on the Encode Format control, and it is why the corrupted
    /// key (`settings.selection`) and the reported control (`Format`, bound to
    /// `settings.encodeFormat`) had nothing to do with each other: the read never consulted the
    /// corruption, and `continueAfterFailure = false` stopped the case at the first control it
    /// looked at. ``isChosen(_:)`` asks the question the platform actually answers, and the
    /// negative control in `evidence/07-11-D98-selection-shape.swift` is what keeps this branch
    /// falsifiable rather than merely green.
    func selectionShown(_ identifier: String) -> String {
        let control = element(identifier)
        guard control.exists else { return "" }
        if let title = control.value as? String, !title.isEmpty {
            return title
        }
        if let index = control.value as? NSNumber, index.intValue >= 0 {
            return "segment\(index.intValue)"
        }
        let options = segments(of: control)
        let chosen = (0 ..< options.count).filter { isChosen(options[$0]) }
        if chosen.count == 1 {
            let label = options[chosen[0]].label
            return label.isEmpty ? "segment\(chosen[0])" : label
        }
        let parts = control.label.components(separatedBy: ", ")
        return parts.count > 1 ? parts[parts.count - 1] : ""
    }

    /// Whether one segment of a segmented control is the CHOSEN one, in the shape macOS publishes.
    ///
    /// MEASURED 2026-09-06 out of process, against the same accessibility API XCUITest reads, with
    /// a picker whose selection matches a `.tag` and one whose selection matches NONE
    /// (`evidence/07-11-D98-selection-shape.swift`, macOS 26.5.2):
    ///
    ///     WITH a selection     AXRadioGroup AXValue=<an AX ELEMENT>  segments AXValue=[1,0,0]
    ///     WITHOUT one          AXRadioGroup AXValue=nil              segments AXValue=[0,0,0]
    ///     either way           AXSelected=nil on the group AND on every segment
    ///
    /// So the segment's OWN `AXValue` is the only attribute that distinguishes the two, and it goes
    /// to all-zero exactly when the control genuinely renders blank — which is what keeps every
    /// caller of this able to FAIL. `isSelected` is still asked first and deliberately: it is what
    /// iOS answers, and if a future macOS starts setting `AXSelected` this reads it rather than
    /// going stale.
    func isChosen(_ segment: XCUIElement) -> Bool {
        if segment.isSelected {
            return true
        }
        if let value = segment.value as? NSNumber {
            return value.intValue == 1
        }
        return (segment.value as? String) == "1"
    }

    /// The selectable segments of a segmented control, queried by SUBTREE and by whichever element
    /// type the platform uses — a button on iOS, a radio button on macOS. Bounded (D-107 route 1).
    func segments(of control: XCUIElement) -> [XCUIElement] {
        let buttons = control.descendants(matching: .button)
        let radios = control.descendants(matching: .radioButton)
        let pool = buttons.count >= radios.count ? buttons : radios
        return (0 ..< pool.count).map { pool.element(boundBy: $0) }
    }

    /// Move the "Read as" selection to a segment that is not already chosen; population first.
    func changeTheReadAsSegment() -> String {
        let picker = element(AccessibilityIdentifiers.Timestamps.readAs)
        XCTAssertTrue(picker.waitForExistence(timeout: 20), "the Read as picker is missing")
        let options = segments(of: picker)
        XCTAssertEqual(options.count, 3, "the Read as picker offers \(options.count) segments, expected one per ReadAs case")
        // ``isChosen(_:)`` AND NOT `isSelected`, for the reason that function records: macOS sets
        // no `AXSelected` on a segment, so `!option.isSelected` is TRUE of all three and this loop
        // would click segment 0 — which is usually the one already chosen, leaving the caller's
        // `XCTAssertNotEqual(changed, before)` to fail on a correct app.
        var moved = false
        for option in options where !moved && !isChosen(option) {
            option.click()
            moved = true
        }
        XCTAssertTrue(moved, "every Read as segment reports itself selected, so there was nothing to change")
        return selectionShown(AccessibilityIdentifiers.Timestamps.readAs)
    }

    /// Fill a surface's input from its worked-value button, rendered only while the input is empty.
    func tapUseExample(_ identifier: String) {
        let button = element(identifier)
        XCTAssertTrue(button.waitForExistence(timeout: 30), "no worked-value button carries \(identifier)")
        button.click()
    }

    /// Open the first add-step control and choose its first operation, scrolling to it first when
    /// it is off screen. **The scroll is here because of THIS PLAN'S OWN FINDING** — on Timestamps
    /// at iPhone SE the first add-step control is below the fold at launch, which is what
    /// `criterion5_hittable_timestamps=false` records. It is legitimate here and would not be in a
    /// clause-2 method, which is why the two live in different methods.
    func addOneStep() {
        var control = all(AccessibilityIdentifiers.Step.addStep).element(boundBy: 0)
        XCTAssertTrue(control.waitForExistence(timeout: 20), "no add-step control on the surface")
        // The SCROLL VIEW is swiped, not the application: on iOS 26.1 three `app.swipeUp()` calls
        // left the control exactly where it started, and the same swipes on the scroller move it.
        // Bounded at six, because an unbounded retry against a control that will never arrive is
        // the doomed wait D-107 route 1 exists to keep out of this suite.
        let scroller = app.scrollViews.firstMatch
        var scrolls = 0
        while !control.isHittable, scrolls < 6 {
            if scroller.exists {
                scroller.swipeUp()
            } else {
                app.swipeUp()
            }
            scrolls += 1
            control = all(AccessibilityIdentifiers.Step.addStep).element(boundBy: 0)
        }
        record("criterion3_scrolls_to_reach_addstep=\(scrolls)")
        XCTAssertTrue(control.isHittable, "the add-step control is still off screen after \(scrolls) scrolls")
        control.click()
        let items = all(AccessibilityIdentifiers.Step.addStepMenu)
        XCTAssertTrue(items.element(boundBy: 0).waitForExistence(timeout: 20), "the add-step menu presented no items")
        items.element(boundBy: 0).click()
    }

    /// The Encode/decode sidebar row, addressed by its own constant.
    func navigateToEncode() {
        visit(AccessibilityIdentifiers.Shell.sidebarEncode,
              expecting: AccessibilityIdentifiers.Encode.input, named: "Encode/decode")
    }

    /// The Timestamps sidebar row, the same way.
    func navigateToTimestamps() {
        visit(AccessibilityIdentifiers.Shell.sidebarTimestamps,
              expecting: AccessibilityIdentifiers.Timestamps.input, named: "Timestamps")
    }

    /// Click the sidebar row carrying `row` and confirm it showed the surface carrying
    /// `identifier`. A `NavigationSplitView` renders all three rows at every selection, so the row
    /// is addressed by its OWN constant rather than by an index — the divergence `ShellTests`
    /// already carries. Nothing here is queried by visible text.
    func visit(_ row: String, expecting identifier: String, named name: String) {
        let entry = element(row)
        XCTAssertTrue(entry.waitForExistence(timeout: 20), "the sidebar carries no row identified \(row)")
        entry.click()
        XCTAssertTrue(
            element(identifier).waitForExistence(timeout: 20),
            "cannot reach the \(name) surface — the \(row) row does not show \(identifier)"
        )
    }

    /// One evidence line, emitted twice — the file header says why.
    func record(_ line: String) {
        print(line)
        XCTContext.runActivity(named: line) { _ in }
    }
}

/// One surface: the pinning that opens it, its evidence label, and the identifier proving it is
/// the one showing.
struct Surface {
    let destination: String, name: String, probe: String

    init(_ destination: String, _ name: String, _ probe: String) {
        (self.destination, self.name, self.probe) = (destination, name, probe)
    }
}

/// One frame as `(x,y,w,h)`, so a failure message carries what was measured.
func describeRect(_ frame: CGRect) -> String {
    "(\(frame.minX),\(frame.minY),\(frame.width),\(frame.height))"
}
