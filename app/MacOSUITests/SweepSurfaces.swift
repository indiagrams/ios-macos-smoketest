import XCTest

// THE THREE SURFACE WALKS — steps 2 through 9 of the D-93 walk, exactly as they were, moved out
// of `VisibleStringSweep.swift` for the reason `SweepPopulation.swift:3..5` gives for the first
// split and `SweepDriver.swift` for the second: `file_length` is 400 lines and under
// `swiftlint --strict` that limit is an ERROR. MEASURED at the commit that added walk steps
// 11-14: the unsplit iOS file came to 465 lines and the macOS one to 505.
//
// NOTHING BELOW CHANGED WHEN IT MOVED — the steps, their order and every assertion are byte for
// byte what they were, minus the `private` a cross-file extension cannot carry. THE WALK
// SKELETON AND STEPS 11-14 STAYED in `VisibleStringSweep.swift`, so the file named after the
// gate still holds the gate, the order of the fourteen steps and the four this phase appended.
//
// C-25 BOUNDS WHAT THIS PROVES: Swift 5.9 / minimal concurrency, like every file in this target.

extension VisibleStringSweep {
    /// The encode/decode surface — the only one with an input-validation failure, and the only one
    /// whose error states this walk can reach, because it reaches them by CLICKING the direction
    /// picker rather than by typing. The worked value is not valid Base64 and its `&` opens an HTML
    /// entity that is never closed, so decode gives two of the app's error sentences for free.
    func encodeSurface(into out: inout SweepHarvest) throws {
        press(element(Ident.Encode.useExample), "the Encode worked-value button")
        try snap(into: &out)

        for index in 0 ..< 3 {
            press(segment(Ident.Encode.format, index), "the format picker's segment \(index)")
            try snap(into: &out)
        }
        press(segment(Ident.Encode.direction, 1), "the direction picker's decode segment")
        for index in 0 ..< 3 {
            press(segment(Ident.Encode.format, index), "the format picker's segment \(index)")
            try snap(into: &out)
        }
        for fixture in SweepPopulation.encodeFixtures {
            replaceInput(Ident.Encode.input, with: fixture.text)
            for format in fixture.formats {
                press(segment(Ident.Encode.format, format), "the format picker's segment \(format)")
                try snap(into: &out)
            }
        }

        clearInput(Ident.Encode.input, revealing: Ident.Encode.useExample)
        press(segment(Ident.Encode.direction, 0), "the direction picker's encode segment")
        press(segment(Ident.Encode.format, 0), "the format picker's first segment")
        press(element(Ident.Encode.useExample), "the Encode worked-value button")

        try chainAndBlock(into: &out)
    }

    /// Copy, open the menu, choose an operation, then drive the appended card to blocked.
    ///
    /// Menu items are in the accessibility tree ONLY WHILE THE MENU IS OPEN, which is why the menu is
    /// opened and harvested before an item is chosen. The order after that is deliberate and is not
    /// the one the walk table reads at first glance: a step whose output is an error has its add-step
    /// control `.disabled(true)` by the State Contract, so the card is appended while the pipeline is
    /// VALID and the failure is installed afterwards. That is what puts the blocked sentence on screen.
    func chainAndBlock(into out: inout SweepHarvest) throws {
        press(control(Ident.Step.copy, 0), "the first copy control")
        try snap(into: &out)

        press(control(Ident.Step.addStep, 0), "the first add-step control")
        try snap(into: &out)

        // The SEEDED card's value carries the surface's own constant; only APPENDED cards use the
        // shared `Step.output`. Measured from the running tree, not assumed.
        let source = element(Ident.Encode.output).label
        press(control(Ident.Step.addStepMenu, 0), "the add-step menu's first item")

        // ROADMAP criterion 8 / APP-08, asserted as its CONJUNCTION rather than as the existence of a
        // view type: the control is on screen, it was used, and the appended card renders the CHAINED
        // result. The first menu item is `Operation.allCases.first`, whose expected value this process
        // computes for itself — no app code is linked to produce it.
        let chained = control(Ident.Step.output, 0)
        XCTAssertTrue(chained.waitForExistence(timeout: 15), "the add-step menu appended no card")
        XCTAssertEqual(
            chained.label,
            Data(source.utf8).base64EncodedString(),
            "app08_chained_macos=failed — the appended step did not render the chained result of \"\(source)\""
        )
        try snap(into: &out)
        XCTContext.runActivity(named: "app08_chained_macos=ok") { _ in }

        press(segment(Ident.Encode.direction, 1), "the direction picker's decode segment")
        XCTAssertTrue(
            element(Ident.Step.blocked).waitForExistence(timeout: 15),
            "an appended step below a failing one is not blocked"
        )
        try snap(into: &out)
        press(segment(Ident.Encode.direction, 0), "the direction picker's encode segment")
    }

    /// Hashing. **It has no input-validation failure** — any `String` has a UTF-8 encoding and every
    /// encoding has a digest — so there is no error fixture here and a later reader should not go
    /// looking for a hashing error string. Its only non-output state is *blocked*, which is reachable
    /// on an appended card and is harvested on the encode surface above.
    func hashingSurface(into out: inout SweepHarvest) throws {
        press(element(Ident.Hashing.useExample), "the Hashing worked-value button")
        try snap(into: &out)

        press(control(Ident.Step.copy, 0), "the first digest's copy control")
        try snap(into: &out)

        press(control(Ident.Step.addStep, 0), "the first digest's add-step control")
        try snap(into: &out)
        press(control(Ident.Step.addStepMenu, 0), "the add-step menu's first item")
        try appendedCard(into: &out)
    }

    /// Timestamps: the picker's three options, the caption, the Detect title and the cell titles.
    func timestampsSurface(into out: inout SweepHarvest) throws {
        press(element(Ident.Timestamps.useExample), "the Timestamps worked-value button")
        try snap(into: &out)

        for index in 0 ..< 3 {
            press(segment(Ident.Timestamps.readAs, index), "the read-as picker's segment \(index)")
            try snap(into: &out)
        }
        press(element(Ident.Timestamps.detect), "the detect control")
        try snap(into: &out)

        for fixture in SweepPopulation.timestampFixtures {
            replaceInput(Ident.Timestamps.input, with: fixture)
            try snap(into: &out)
        }
        clearInput(Ident.Timestamps.input, revealing: Ident.Timestamps.useExample)
        press(element(Ident.Timestamps.useExample), "the Timestamps worked-value button")

        press(control(Ident.Step.copy, 0), "the first representation's copy control")
        try snap(into: &out)
        press(control(Ident.Step.addStep, 0), "the first representation's add-step control")
        try snap(into: &out)
        press(control(Ident.Step.addStepMenu, 0), "the add-step menu's first item")
        try appendedCard(into: &out)
    }

    /// Waits for the card the add-step menu appended, THEN harvests it. Measured on the iOS twin: the
    /// snapshot taken straight after the menu tap caught the card unrendered on one runtime and
    /// rendered on another, and a population that depends on a race is the wrong population.
    func appendedCard(into out: inout SweepHarvest) throws {
        XCTAssertTrue(control(Ident.Step.output, 0).waitForExistence(timeout: 15), "the menu appended no card")
        try snap(into: &out)
    }
}
