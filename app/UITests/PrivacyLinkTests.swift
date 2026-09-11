import XCTest

// THE PRIVACY CONTROL, ASSERTED PER SURFACE — iOS HALF (META-06, D-117/D-118,
// 08-UI-SPEC.md §Accessibility). `app/MacOSUITests/PrivacyLinkTests.swift` is
// the twin and declares the same three test names for the same three claims,
// exactly as the `ShellTests` pair already does across two different containers.
//
// ADDRESSED ONLY BY `AccessibilityIdentifiers.Shell.privacyPolicy`, NEVER BY
// ANYTHING A USER CAN READ. The control is icon-only on iOS and the name it
// speaks comes from the string catalog, so a query by its glyph or by its
// spoken word would assert on the very string the D-93 sweep exists to govern —
// and a localisation would then break a test that is not about localisation.
//
// WHAT IS NOT THIS CONTROL'S GUARD, NAMED IN PROSE AND DELIBERATELY NOT SPELLED.
// Four iOS files assert that the TAB bar presents exactly three items, and zero
// macOS files carry that assertion at all. It binds `app.tabBars.firstMatch` at
// five sites, so it counts items in the TAB bar; this control is an item in the
// NAVIGATION bar, and nothing it does can move a tab-bar total. Citing it for
// this control would be a correct check pointed at the wrong population — the
// failure class this phase exists to stop repeating — and "asserted on both
// twins" was never true of it. The token is described here rather than written
// because this suite's own acceptance criteria grep this file for it, and a
// file that spells what a gate scans for sweeps that gate green by existing.
//
// THE REAL INVARIANT IS ONE PER SURFACE, ASSERTED PER SURFACE, BEFORE ANY
// TOTAL. A total of three reached by two controls on one surface and one on
// another is a DIFFERENT defect from one on each, and a total-only assertion
// cannot tell the two apart. Each surface therefore carries its own assertion
// with its own message naming which surface it is about, and the total is
// asserted afterwards, from the three numbers already taken.
//
// EVERY LAUNCH PINS ITS SURFACE (07-07). `selection` persists since 07-05, so a
// case that ended on Hashing decides the next case's launch surface; a test that
// inherited its surface from a dirty store passed four times in this repository
// and was caught only by a machine whose store held something else.
//
// BOUNDED QUERIES ONLY (UL-064, `app/UITestSupport/ElementText.swift:87-101`):
// one `count` read and a bounded loop, never a wait. A query's `count` is a
// single round trip where `waitForExistence` polls for a full second per call,
// and a whole-tree accessibility walk is rate-sensitive enough to take the
// application under test down with it. Nothing below waits for an element that
// is expected to be ABSENT, and nothing below walks the whole tree.
//
// NOTHING HERE FOLLOWS THE LINK OUT OF THE APP. The hand-off is measured once, by
// a throwaway probe on a real build; an XCUITest that chases the app into Safari
// asserts something the system owns and flakes for reasons that are not this app's.
//
// C-25 BOUNDS WHAT THIS PROVES: Swift 5.9 / `SWIFT_STRICT_CONCURRENCY: minimal`,
// like every file in this target, so this is META-06 evidence and never
// evidence for APP-12.

/// One privacy control on every iOS surface — asserted per surface, hittable,
/// and with the Phase 7 structural counts unmoved (META-06, D-118).
@MainActor
final class PrivacyLinkTests: XCTestCase {
    private var app: XCUIApplication!

    /// The three surfaces: the pinning that opens each one, the name its failure
    /// messages use, and the identifier that proves the surface really rendered.
    ///
    /// ``Surface`` and these three rows are `LaunchLayoutTests.swift:67-71`'s,
    /// reused rather than re-typed — one more copy of the list is one more place
    /// for a fourth destination to be missed. The population is the pinning
    /// enum's three destinations, which `evidence/07-07-verify-launchstate.rb`
    /// already asserts resolve against the app's own `Destination` cases, so
    /// "three" here is the app's number and not this file's.
    private static let surfaces = [
        Surface(LaunchState.encodeDestination, "encode", AccessibilityIdentifiers.Encode.input),
        Surface(LaunchState.hashingDestination, "hashing", AccessibilityIdentifiers.Hashing.input),
        Surface(LaunchState.timestampsDestination, "timestamps", AccessibilityIdentifiers.Timestamps.input)
    ]

    /// The root card is ALONE on a surface at launch: nothing has been appended
    /// yet. Not a number from a plan — `app/UITests/VisibleStringSweep.swift:372`
    /// asserts exactly this for the root-alone state that step 14 drives to.
    private static let cardsAtLaunch = 1

    /// D-100 as a RELATION rather than a literal: one remove control per APPENDED
    /// card. `app/UITests/StepEditTests.swift:226` and
    /// `app/UITests/VisibleStringSweep.swift:375` are where that relation is
    /// asserted today; evaluated at ``cardsAtLaunch`` it is zero, and it moves
    /// with the relation rather than having to be re-typed.
    private static let removesAtLaunch = cardsAtLaunch - 1

    /// The Hashing surface's four value cells, enumerated from the shipped enum
    /// rather than counted — so adding a fifth digest moves this population
    /// without an edit here, and losing one fails.
    private static let hashingCells = [
        AccessibilityIdentifiers.Hashing.digestMD5,
        AccessibilityIdentifiers.Hashing.digestSHA1,
        AccessibilityIdentifiers.Hashing.digestSHA256,
        AccessibilityIdentifiers.Hashing.digestSHA512
    ]

    /// The Timestamps surface's representation cells, the same way.
    private static let timestampsCells = [
        AccessibilityIdentifiers.Timestamps.cellEpoch,
        AccessibilityIdentifiers.Timestamps.cellISO8601,
        AccessibilityIdentifiers.Timestamps.cellDateTime
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - D-118, per surface and only then in total

    /// Exactly one privacy control on EACH surface, each asserted on its own,
    /// each failure naming its surface, all three before any total.
    ///
    /// **THIS ONE CASE CONTINUES AFTER A FAILURE, AND THE REASON IS THE CLAIM.**
    /// Every other case here stops at the first failure because it DRIVES
    /// something and a later step would measure wreckage. Nothing is driven here:
    /// each surface gets its own pinned launch, so the three measurements are
    /// independent. "Missing on Timestamps" and "missing everywhere" are
    /// different defects with different causes, and a suite that can only ever
    /// name the first surface cannot tell them apart.
    func testOnePrivacyControlOnEverySurface() {
        continueAfterFailure = true
        var perSurface: [(name: String, found: Int)] = []

        for surface in Self.surfaces {
            launch(surface.destination)
            awaitSurface(surface.probe, surface.name)

            // ONE `count` READ per population. The control is either there or it
            // is not; waiting could only turn an absence into a slower absence.
            let ident = AccessibilityIdentifiers.Shell.privacyPolicy
            let found = controlCount(ident)
            let drawn = frames(ident).filter { !$0.isEmpty }
            let span = drawn.dropFirst().reduce(drawn.first ?? .zero) { $0.union($1) }
            let largest = drawn.max { $0.width * $0.height < $1.width * $1.height } ?? .zero
            record("privacy_control_\(surface.name)=\(found) privacy_nodes_\(surface.name)=\(drawn.count) "
                + "privacy_frames_\(surface.name)=\(Set(drawn.map(describeRect)).count) "
                + "privacy_span_\(surface.name)=\(describeRect(span)) "
                + "privacy_largest_\(surface.name)=\(describeRect(largest))")

            XCTAssertEqual(
                found,
                1,
                "the \(surface.name) surface carries \(found) privacy controls, expected exactly 1 "
                    + "pressable element carrying \(ident)"
            )
            // IT OCCUPIES SPACE. An element published with an empty frame renders
            // nothing a reviewer can reach, and the clause below would then be
            // comparing two zero rects and passing about nothing.
            XCTAssertFalse(
                drawn.isEmpty,
                "\(surface.name): every element carrying \(ident) has an empty frame — the control occupies no space"
            )
            // AND THEY ARE ONE CONTROL, not two that happen to be pressable once.
            // Type-agnostic where the clause above is not, so a runtime that
            // publishes the wrapper as something other than a button still fails
            // here the moment a SECOND control appears on a surface.
            XCTAssertTrue(
                Self.isOneControl(span: span, largest: largest),
                "\(surface.name): the \(drawn.count) elements carrying \(ident) span "
                    + "\(describeRect(span)), which exceeds the largest single node "
                    + "\(describeRect(largest)) by more than \(Self.frameTolerance) pt on some edge "
                    + "— that is more than one control"
            )
            perSurface.append((surface.name, found))
        }

        // AND ONLY NOW A TOTAL, computed from the three numbers already asserted
        // rather than from a fresh query that could match anything anywhere.
        let total = perSurface.reduce(0) { $0 + $1.found }
        let breakdown = perSurface.map { "\($0.name)=\($0.found)" }.joined(separator: " ")
        record("privacy_controls_total=\(total) \(breakdown)")
        XCTAssertEqual(total, Self.surfaces.count, "privacy_controls_total=\(total), expected one per surface: \(breakdown)")
    }

    // MARK: - Present is not the same as usable

    /// The control a reviewer has to reach is hit-testable and enabled.
    ///
    /// Present-but-unhittable is a control guideline 5.1.1(i) is not satisfied
    /// by, and the two properties are independent in XCUITest — an element can
    /// exist, be enabled, and still be underneath something.
    func testThePrivacyControlIsHittableAndEnabled() {
        let surface = Self.surfaces[0]
        launch(surface.destination)
        awaitSurface(surface.probe, surface.name)

        // The population FIRST, before an index is taken into it.
        let found = controlCount(AccessibilityIdentifiers.Shell.privacyPolicy)
        XCTAssertEqual(found, 1, "\(surface.name) carries \(found) privacy controls, so index 0 is not a safe read")

        let control = controls(AccessibilityIdentifiers.Shell.privacyPolicy).element(boundBy: 0)
        record("privacy_hittable_\(surface.name)=\(control.isHittable) privacy_enabled_\(surface.name)=\(control.isEnabled)")
        XCTAssertTrue(control.isHittable, "the privacy control on \(surface.name) exists but is not hit-testable")
        XCTAssertTrue(control.isEnabled, "the privacy control on \(surface.name) exists but is disabled")
    }

    // MARK: - The control added chrome, not content

    /// Every Phase 7 structural count on every surface is where Phase 7 left it.
    ///
    /// **The expectations are read from the assertions that already carry them**,
    /// not typed from a plan: plan literals go stale by allocation, and if one of
    /// these numbers has genuinely moved the right action is to re-measure and
    /// move both sites, never to copy a paragraph.
    func testStructuralCountsAreUnchangedOnEverySurface() {
        for surface in Self.surfaces {
            launch(surface.destination)
            awaitSurface(surface.probe, surface.name)

            let cards = count(AccessibilityIdentifiers.Step.card)
            let adds = count(AccessibilityIdentifiers.Step.addStep)
            let removes = count(AccessibilityIdentifiers.Step.remove)
            record("structural_\(surface.name) cards=\(cards) addsteps=\(adds) removes=\(removes)")

            XCTAssertEqual(cards, Self.cardsAtLaunch, "\(surface.name): \(cards) cards at launch, expected the pinned root alone")
            XCTAssertEqual(removes, Self.removesAtLaunch, "\(surface.name): \(removes) remove controls beside \(cards) cards")
            // The add-step population is per-output and therefore differs by
            // surface, so the Phase 7 assertion on it is "greater than zero"
            // (`app/UITests/LaunchLayoutTests.swift:104-106`) and this one is the
            // same assertion. The number itself is RECORDED above, which is what
            // makes a change visible without inventing a literal to guard it.
            XCTAssertGreaterThan(adds, 0, "\(surface.name): no add-step control at launch at all")

            assertCellsAreIntact(on: surface)
        }
    }

    /// One element per declared value cell on the surface that owns them.
    ///
    /// The population comes from the shipped identifier enum rather than from a
    /// count written here, and one-per-identifier is the relation
    /// `app/UITests/StepEditTests.swift:173` already asserts for the first digest.
    ///
    /// **THE WORKED VALUE IS TYPED IN FIRST, AND THAT IS A MEASUREMENT RATHER
    /// THAN A CONVENIENCE.** `OutputBlock.swift:65-73` attaches the value
    /// identifier on the `.value` branch ALONE, so on a surface whose cells are
    /// showing a placeholder those identifiers are not in the accessibility tree
    /// at all: measured on iOS 18.6, all three `Timestamps.cell.*` count 0 at
    /// launch and 1 after one tap on the worked-value button. Hashing does not
    /// behave that way — `DigestRow.swift:141` attaches the row identifier
    /// unconditionally, so its four count 1 either side of the tap. Asserting
    /// these at launch would therefore have been an assertion about the EMPTY
    /// state wearing a structural-invariant's name, and it is the one place this
    /// suite drives anything at all.
    private func assertCellsAreIntact(on surface: Surface) {
        let cells: [String]
        let example: String
        switch surface.name {
        case "hashing":
            cells = Self.hashingCells
            example = AccessibilityIdentifiers.Hashing.useExample
        case "timestamps":
            cells = Self.timestampsCells
            example = AccessibilityIdentifiers.Timestamps.useExample
        default:
            return
        }

        let button = element(example)
        XCTAssertTrue(button.waitForExistence(timeout: 20), "\(surface.name): no worked-value button carries \(example)")
        button.tap()

        // A BOUNDED LOOP over a population that is known before it is entered.
        for cell in cells {
            let found = count(cell)
            record("structural_\(surface.name)_cell \(cell)=\(found)")
            XCTAssertEqual(found, 1, "\(surface.name): \(found) elements carry \(cell), expected exactly 1")
        }

        // The control survives the one thing this test drives.
        let still = controlCount(AccessibilityIdentifiers.Shell.privacyPolicy)
        record("privacy_control_after_value_\(surface.name)=\(still)")
        XCTAssertEqual(still, 1, "\(surface.name): \(still) privacy controls once the surface has a value, expected 1")
    }

    // MARK: - Launching, and queries, all of them by identifier

    /// A fresh application pinned to `destination`, because `selection` persists.
    private func launch(_ destination: String) {
        app = XCUIApplication()
        app.launchPinned(showing: destination)
    }

    /// The surface really rendered before anything is counted on it.
    ///
    /// The one wait in this file, and it waits for a PRESENCE: a count taken
    /// before SwiftUI has drawn the surface would be a zero about timing.
    private func awaitSurface(_ probe: String, _ name: String) {
        XCTAssertTrue(
            element(probe).waitForExistence(timeout: 30),
            "the app did not present the \(name) surface — no element carries \(probe)"
        )
    }

    /// How many elements carry `identifier` right now. One round trip.
    private func count(_ identifier: String) -> Int {
        all(identifier).count
    }

    /// Every element carrying `identifier`, whatever kind of element it is.
    ///
    /// Deliberately not scoped to a query category: the same constant addresses a
    /// navigation-bar item here and a menu item on the macOS twin.
    private func all(_ identifier: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: identifier)
    }

    /// The PRESSABLE elements carrying `identifier` — the controls themselves.
    ///
    /// **Scoped to one element type, and the scope is a measurement.** A SwiftUI
    /// navigation-bar item publishes the SAME control twice here — a wrapper and
    /// the control, element types `other` and `button`, both hittable and both
    /// enabled (`evidence/08-11-probe.swift`, and §2 of that plan's transcript).
    /// So an unscoped count answers 2 for ONE control, and "exactly one" over
    /// that population would be an invariant about the platform's tree shape
    /// rather than about this app. The control is the pressable one; 08-09's
    /// probe reached it on 17.5, 18.6 and 26.1 through this same population. The
    /// unscoped count is recorded beside it, and the type-agnostic clause that
    /// also refuses a SECOND control is ``isOneControl(span:largest:)`` — read
    /// the amendment there before trusting anything about those two frames.
    private func controls(_ identifier: String) -> XCUIElementQuery {
        app.buttons.matching(identifier: identifier)
    }

    /// How many pressable controls carry `identifier` right now.
    private func controlCount(_ identifier: String) -> Int {
        controls(identifier).count
    }

    /// Every frame occupied by an element carrying `identifier`.
    ///
    /// A bounded loop over a `count` already taken, never a wait. Evidence lines
    /// render these through `describeRect`, which is `LaunchLayoutSupport.swift:250`'s,
    /// so a frame reads the same here as everywhere else in this target.
    private func frames(_ identifier: String) -> [CGRect] {
        let query = all(identifier)
        let matched = query.count
        guard matched > 0 else { return [] }
        return (0 ..< matched).map { query.element(boundBy: $0).frame }
    }

    /// How far the union of every node's frame may exceed the largest single node
    /// before those nodes have stopped being ONE control, in points.
    ///
    /// One point, bounded from both sides by measurements rather than chosen.
    /// Below it: the frames this app publishes are not integers —
    /// `(352.3333333333333, 61.00000000000002, …)` on iOS 18.6 — so zero tolerance
    /// compares floating-point noise. Above it: the NARROWEST node measured for
    /// this control is 30 pt wide, so a tolerance thirty times smaller than the
    /// thing it detects cannot hide a second bar item.
    private static let frameTolerance: CGFloat = 1

    /// Do these nodes describe ONE control?
    ///
    /// **THE INVARIANT, AND IT IS THE SECOND ATTEMPT — AMENDED 2026-09-11.** The
    /// first version asserted that the matched elements occupy exactly one DISTINCT
    /// frame, on the strength of a measurement taken on iOS 18.6 where the wrapper
    /// and the button were byte-identical. That is a RUNTIME-SPECIFIC ACCIDENT.
    /// On iOS 26.1 SwiftUI publishes them 3 pt apart in x and 6 pt apart in width —
    /// `(319.0,24.0,36.0,36.0)` and `(322.0,24.0,30.0,36.0)` on a 375 pt window,
    /// `(346.0,66.0,36.0,36.0)` and `(349.0,66.0,30.0,36.0)` on an iPhone 17 Pro —
    /// so the old clause read one control as two and the suite exited 65 on an
    /// UNTOUCHED tree. Worse, plan 08-12 measured that it INVERTED: the
    /// contract-forbidden 88 pt box collapses the two frames onto one and turns the
    /// clause GREEN under the very regression it exists to refuse.
    ///
    /// What actually holds on every runtime measured is not sameness but
    /// CONTAINMENT: however many nodes the platform publishes, they all sit inside
    /// the bounds of ONE of them. So the union of every node's frame must be no
    /// bigger than the largest single node's frame. Two real controls anywhere
    /// apart on a bar produce a union far wider than either, and fail.
    ///
    ///     runtime   nodes   distinct frames   union == largest
    ///     17.5      2       1                 yes
    ///     18.6      2       1                 yes
    ///     26.1      2       2                 yes
    private static func isOneControl(span: CGRect, largest: CGRect) -> Bool {
        abs(span.minX - largest.minX) <= frameTolerance
            && abs(span.minY - largest.minY) <= frameTolerance
            && abs(span.maxX - largest.maxX) <= frameTolerance
            && abs(span.maxY - largest.maxY) <= frameTolerance
    }

    /// The first element carrying `identifier`.
    private func element(_ identifier: String) -> XCUIElement {
        all(identifier).firstMatch
    }

    /// One measured number, emitted twice — `print` for a local run, and an
    /// `XCTContext` activity, which is the channel that reaches the `.xcresult`.
    private func record(_ line: String) {
        print(line)
        XCTContext.runActivity(named: line) { _ in }
    }
}
