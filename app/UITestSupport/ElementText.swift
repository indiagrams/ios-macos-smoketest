import XCTest

// READING TEXT OUT OF AN ELEMENT, ON BOTH PLATFORMS. NOTHING IN THIS FILE NAMES AN APPLICATION.
//
// This file and its companion `BlindReadGuards.swift` are compiled into BOTH UI-test targets and
// contain no identifier, no view name, no string and no type belonging to the application under
// test. Drop the directory into any SwiftUI project, list it in the two UI-test targets, and it
// works — that property is deliberate and is asserted by a grep, not by intention.
//
// THE MEASUREMENT THIS FILE EXISTS FOR, macOS 26.5.2 (Build 25F84), an out-of-process
// accessibility client reading the same API XCUITest reads, six shapes with two negative controls
// (`evidence/07-UITESTSUPPORT-ax-shapes.swift`, 2026-09-10):
//
//     shape                                   AXRole         AXValue    AXDescription  `.label`
//     a plain `Text`                          AXStaticText   content    nil            ""
//     a `Text` in a `List` row                AXStaticText   content    nil            ""
//     `Label(_:systemImage:)` in a `List`     AXStaticText   content    nil            ""
//     a `Text` + `.accessibilityAddTraits`    AXHeading      nil        content        reads
//       `(.isHeader)`
//     a container + `.accessibilityLabel`     AXGroup        nil        content        reads
//     a `NavigationLink`'s label              AXUnknown      nil        content        reads
//
// macOS publishes a plain SwiftUI `Text`'s content in **AXValue alone**. XCUITest's `.label` is
// built from AXDescription, falling back to AXTitle, and never reads AXValue. So on macOS
// `element.label` is a CONSTANT EMPTY STRING for the three commonest text shapes a SwiftUI author
// writes — for an element rendering the wrong string and for one rendering the right string alike.
// On iOS the same `Text` publishes its content AS its label, which is why a suite can be green on
// one platform for years while the other has never measured its subject.
//
// THE READ RULE IS `label` FIRST, THEN THE STRING `value`, AND THE ORDER IS LOAD-BEARING. Asking
// `label` first keeps iOS byte-identical, keeps every element that already answers answering the
// same thing, and reads through rather than going stale if a future macOS starts publishing an
// AXDescription for these shapes. The fallback is asked only when the first answer is empty, so
// this rule can never CHANGE a read — it can only turn a non-answer into an answer. That property
// is asserted by the probe cited above (its check 4) and is the reason adopting this file at an
// existing call site is not a behaviour change on iOS.
//
// THIS IS A RULE ABOUT READING, NOT ABOUT FINDING. Element MATCHING is a separate mechanism with
// separate inputs and it is NOT blind: on the same macOS run where `.label` read empty on three
// elements, the `matching(identifier:)` COUNT of those same three elements passed. Do not rewrite
// a working query on the strength of this file. `docs/UI-TESTING-ON-BOTH-PLATFORMS.md` states the
// distinction at length, including what about matching is measured and what is still open.
//
// SWIFT 5.9 / `SWIFT_STRICT_CONCURRENCY: minimal`, matching both UI-test targets. No concurrency
// of any kind is used here and no Swift 6 isolation syntax appears.

extension XCUIElement {
    /// What this element is RENDERING, in whichever attribute the running platform publishes it in.
    ///
    /// `label` first — iOS's idiom, and the branch every already-answering element keeps taking —
    /// then the element's own string `value`. Returns `""` when the platform publishes the text in
    /// neither, which is a real answer and not a failure: see ``assertReadable(_:_:file:line:)``
    /// for the guard that stops an empty read from being mistaken for a measurement.
    ///
    /// NOT A REPLACEMENT FOR `label` EVERYWHERE. An element whose `value` legitimately differs
    /// from its label — a text field holding typed text under a label naming the field, a slider,
    /// a stepper — is a case where the two attributes mean different things and the caller wants
    /// the specific one. This property is for the question "what does this element display", asked
    /// of an element that displays exactly one string.
    var renderedText: String {
        let visible = label
        if !visible.isEmpty {
            return visible
        }
        return (value as? String) ?? ""
    }
}

extension XCUIElementSnapshot {
    /// ``XCUIElement/renderedText``, for a node of a snapshotted tree.
    ///
    /// A whole-tree walk reads from snapshots rather than from live elements, and a snapshot walk
    /// that uses the live rule and a live read that uses the snapshot rule will disagree about the
    /// same element. Both spellings live here so that cannot happen silently.
    var renderedText: String {
        if !label.isEmpty {
            return label
        }
        return (value as? String) ?? ""
    }
}

extension XCUIElementQuery {
    /// Every matched element's ``XCUIElement/renderedText``, in query order.
    ///
    /// ONE `count` READ AND A BOUNDED LOOP, never a wait. A query's `count` is a single round trip
    /// where `waitForExistence` polls for a full second per call, and a whole-tree accessibility
    /// walk is a rate-sensitive operation: XCTest's automation support can emit thousands of log
    /// messages a second during one and take the application under test down with it (see
    /// `docs/UI-TESTING-ON-BOTH-PLATFORMS.md`). Prefer counts and bounded loops in a walk.
    ///
    /// An EMPTY result means the query matched nothing; an array of empty STRINGS means the query
    /// matched and the reads were blind. Those are opposite findings — pass the result through
    /// ``assertAllReadable(_:_:file:line:)`` rather than asserting on it directly.
    var renderedTexts: [String] {
        let matched = count
        guard matched > 0 else {
            return []
        }
        return (0 ..< matched).map { element(boundBy: $0).renderedText }
    }
}
