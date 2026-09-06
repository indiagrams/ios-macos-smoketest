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
    /// Steps 2-8 on the encode/decode surface, the only one with an input-validation failure.
    func encodeSurface(into out: inout SweepHarvest) throws {
        press(element(Ident.Encode.useExample), "the Encode worked-value button")
        try snap(into: &out)

        for index in 0 ..< 3 { // step 3: three headers
            press(segment(Ident.Encode.format, index), "the format picker's segment \(index)")
            try snap(into: &out)
        }
        press(segment(Ident.Encode.direction, 1), "the direction picker's decode segment")
        for index in 0 ..< 3 { // step 4: the other three
            press(segment(Ident.Encode.format, index), "the format picker's segment \(index)")
            try snap(into: &out)
        }

        for fixture in SweepPopulation.encodeFixtures { // step 5: the error strings
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

    /// Steps 6-8: copy, open the menu, choose an operation, then drive the appended card to blocked.
    ///
    /// Menu items are in the accessibility tree ONLY WHILE THE MENU IS OPEN, which is why step 7 opens
    /// it and harvests before step 8 chooses. The order inside step 8 is deliberate and is not the one
    /// the walk table reads at first glance: a step whose output is an error has its add-step control
    /// `.disabled(true)` by the State Contract, so the card is appended while the pipeline is VALID and
    /// the error fixture is installed afterwards. That is what puts the blocked sentence on screen.
    func chainAndBlock(into out: inout SweepHarvest) throws {
        press(control(Ident.Step.copy, 0), "the first copy control")
        try snap(into: &out)

        press(control(Ident.Step.addStep, 0), "the first add-step control")
        try snap(into: &out)

        // The SEEDED card's value carries the surface's own constant (`Encode.output`); only APPENDED
        // cards use the shared `Step.output`. Measured from the running tree, not assumed.
        let source = element(Ident.Encode.output).label
        press(control(Ident.Step.addStepMenu, 0), "the add-step menu's first item")
        try snap(into: &out)

        // ROADMAP criterion 8 / APP-08, asserted as its CONJUNCTION rather than as the existence of a
        // view type: the control is on screen, it was used, and the appended card renders the chained
        // result. The first menu item is `Operation.allCases.first`, whose expected value this process
        // computes for itself — no app code is linked to produce it.
        let chained = control(Ident.Step.output, 0)
        XCTAssertTrue(chained.waitForExistence(timeout: 15), "the add-step menu appended no card")
        XCTAssertEqual(
            chained.label,
            Data(source.utf8).base64EncodedString(),
            "the appended step did not render the chained result of \"\(source)\""
        )
        print("app08_chained_ios=ok")
        // Harvested AFTER the wait, not before it: the snapshot taken straight after the menu tap
        // caught the appended card unrendered on 17.5 and rendered on 26.1, so the chained value was in
        // the population on one runtime and not the other. A population that depends on a race is the
        // wrong population.
        try snap(into: &out)

        press(segment(Ident.Encode.direction, 1), "the direction picker's decode segment")
        let blocked = element(Ident.Step.blocked)
        XCTAssertTrue(blocked.waitForExistence(timeout: 15), "an appended step below a failing one is not blocked")
        try snap(into: &out)
        press(segment(Ident.Encode.direction, 0), "the direction picker's encode segment")
    }

    /// Step 9 on hashing. **Hashing has no input-validation failure** — any `String` has a UTF-8
    /// encoding and every encoding has a digest — so there is no error fixture here and a later reader
    /// should not go looking for a hashing error string. Its only non-output state is *blocked*, which
    /// is reachable on an appended card and is therefore harvested on the encode surface above.
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

    /// Step 9 on timestamps: the picker's three options, the caption, the Detect title and the cells.
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

    /// Waits for the card the add-step menu appended, THEN harvests it.
    func appendedCard(into out: inout SweepHarvest) throws {
        XCTAssertTrue(control(Ident.Step.output, 0).waitForExistence(timeout: 15), "the menu appended no card")
        try snap(into: &out)
    }
}
