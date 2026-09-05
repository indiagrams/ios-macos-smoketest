import XCTest

// THE POPULATIONS THE D-93 SWEEP RUNS OVER, AND THE THREE IT DOES NOT. Companion to
// `VisibleStringSweep.swift`, split out because both files are `swiftlint --strict` and one file
// carrying the walk, the harvest and the frozen lists exceeds its length rules.
//
// `.continue-here.md`'s newest blocking lesson is *a correct check pointed at the wrong population*,
// so what is in the swept set and what is out of it is stated here, once, as code:
//
//   rendered         — what the APP draws. The only bucket the prose condition is asserted over.
//   chrome           — the application element's own name and a window's title. System chrome resolved
//                      from CFBundleDisplayName <- $(DISPLAY_NAME) <- app/Identity.xcconfig, already
//                      covered by criterion 7's tracked-file gate, and the one place the product name
//                      legitimately reaches the screen. On macOS the whole menu bar is here too.
//   systemData       — TimeZone.knownTimeZoneIdentifiers, ~600 entries of Foundation data (APP-07).
//   platformControl  — controls AppKit/UIKit supplies, notably the iOS software keyboard, which is
//                      part of the app's OWN element tree and therefore enters the harvest.
//
// Each is PRINTED AS A LABELLED COUNT by the sweep, never silently subtracted: the exemption table is
// a transfer of responsibility to criterion 7, not a hole, and a number moves when someone adds one.

/// Which population a harvested string belongs to. `systemData` is derived inside ``SweepHarvest``.
enum SweepBucket {
    case rendered, chrome, platformControl
}

/// The four populations, kept apart so an exemption is a number rather than a silent subtraction.
struct SweepHarvest {
    private(set) var rendered: [String] = []
    private(set) var chrome: [String] = []
    private(set) var systemData: [String] = []
    private(set) var platformControl: [String] = []

    mutating func add(_ string: String, to bucket: SweepBucket) {
        switch bucket {
        case .rendered:
            // The time-zone picker's closed state renders one `knownTimeZoneIdentifiers` entry.
            // Foundation data, not app prose — exempt, and counted.
            if SweepPopulation.timeZoneIdentifiers.contains(string) {
                systemData.append(string)
            } else {
                rendered.append(string)
            }
        case .chrome:
            chrome.append(string)
        case .platformControl:
            platformControl.append(string)
        }
    }
}

/// The classification rules, the fixtures and the frozen term list.
enum SweepPopulation {
    /// The bucket a node and everything under it belongs to.
    static func subtreeBucket(_ node: XCUIElementSnapshot, inherited: SweepBucket) -> SweepBucket {
        switch node.elementType {
        case .menuBar, .menuBarItem, .statusBar, .dockItem:
            .chrome
        case .keyboard, .key, .touchBar:
            .platformControl
        case .window where hostsKeyboard(node):
            // MEASURED, and the reason this clause exists rather than a list of strings: on iOS the
            // software keyboard lives in its own window of the APP'S OWN process, and that window also
            // carries the typing-prediction bar. Its candidates come from the runtime's language model,
            // so they differ between runtimes and between runs — nine of them were counted as
            // app-rendered strings on the first green run. Platform-supplied AND nondeterministic is
            // exactly the shape that turns a merge-blocking gate flaky, so the whole window is
            // exempted structurally, and counted.
            .platformControl
        default:
            inherited
        }
    }

    /// Whether any descendant of `node` is the software keyboard.
    private static func hostsKeyboard(_ node: XCUIElementSnapshot) -> Bool {
        node.children.contains { $0.elementType == .keyboard || hostsKeyboard($0) }
    }

    /// The bucket a node's OWN strings belong to, which is not always its subtree's.
    ///
    /// The application element's label is the display name and a window's title is the window title.
    /// Their DESCENDANTS are app content and stay in `rendered`; only the two nodes themselves are
    /// chrome. This is what keeps 06-01's measured macOS result — 114 strings of which ~110 were the
    /// menu bar — from being mistaken for a populated app.
    static func ownBucket(_ node: XCUIElementSnapshot, subtree: SweepBucket) -> SweepBucket {
        switch node.elementType {
        case .application, .window:
            .chrome
        default:
            subtree
        }
    }

    /// `(format segment, text)`. The direction picker is on decode for all of these — encoding cannot
    /// fail, so every error sentence the encode surface owns is reachable only in the other direction.
    /// Typed ONCE each, then read under every format listed — typing is the expensive half of the
    /// walk and a format change costs one tap.
    static let encodeFixtures: [(text: String, formats: [Int])] = [
        ("&%zz!", [0, 1, 2]), ("aGVsbG8", [0]), ("a=GVsbG8=", [0]), ("&nosuch;", [2]), ("%FF%FE", [1])
    ]

    /// Inputs the timestamps surface cannot read, so its own failure sentences enter the tree.
    static let timestampFixtures = ["12x4", "999999999999999999"]

    /// `TimeZone.knownTimeZoneIdentifiers` — Foundation data, exempt and counted as `system_data`.
    static let timeZoneIdentifiers = Set(TimeZone.knownTimeZoneIdentifiers)

    /// Lower-cased with every space removed, so a name written with or without spaces compares equal.
    static func squash(_ string: String) -> String {
        string.lowercased().filter { !$0.isWhitespace }
    }

    /// The prose terms, ASSEMBLED AT RUN TIME rather than spelled (D-92).
    ///
    /// `app/` is tracked and swept by the gate plan 06-15 extended, so a term written out here would
    /// satisfy the very predicate it defines and would move that gate's own counts.
    /// `.continue-here.md`'s "a file that configures a content gate is also swept by that gate" is one
    /// of its blocking rows and has landed fifteen times in this project;
    /// `tools/check-contamination.rb` assembles its list the same way and
    /// `test/docs_structure_test.rb:698-700` did it first. ACCEPTED COST, stated rather than
    /// discovered: a reader cannot see the list by reading this file. Run it, or read the frozen list
    /// in `.planning/phases/06-app-foundation-conversion-tools/evidence/06-16-sweep.txt`.
    ///
    /// The shape mirrors that gate's `PROSE_STRICT_TERMS` — qualifier-plus-subject PHRASES rather than
    /// bare nouns, because 06-15 measured every bare noun occurring legitimately in this app's own
    /// vocabulary (a Greek letter in the HTML entity table; a date format pattern; SwiftUI prompt
    /// text; and the worked-value button the UI-SPEC defends as a noun describing the INPUT) — plus
    /// the wording that claims software is unfinished, and the two template identities written with
    /// either separator, which is the UL-044 shape no identifier-keyed gate could see.
    static let proseTerms: [String] = {
        let qualifiers = [
            ["d", "e", "m", "o"], ["b", "e", "t", "a"], ["t", "r", "i", "a", "l"],
            ["s", "a", "m", "p", "l", "e"], ["e", "x", "a", "m", "p", "l", "e"],
            ["t", "e", "m", "p", "l", "a", "t", "e"],
            ["p", "l", "a", "c", "e", "h", "o", "l", "d", "e", "r"]
        ].map { $0.joined() }
        let subjects = [["a", "p", "p"], ["v", "e", "r", "s", "i", "o", "n"], ["b", "u", "i", "l", "d"]]
            .map { $0.joined() }
        let standalone = [
            [["c", "o", "m", "i", "n", "g"], ["s", "o", "o", "n"]],
            [["n", "o", "t"], ["i", "m", "p", "l", "e", "m", "e", "n", "t", "e", "d"]],
            [["l", "o", "r", "e", "m"], ["i", "p", "s", "u", "m"]],
            [["r", "e", "n", "a", "m", "e"], ["m", "e"]]
        ].map { words in words.map { $0.joined() }.joined(separator: " ") }
        let pairs = [
            [["s", "m", "o", "k", "e"], ["a", "p", "p"]],
            [["h", "e", "l", "l", "o"], ["a", "p", "p"]],
            [["s", "m", "o", "k", "e"], ["t", "e", "s", "t"]]
        ]
        let narrow = pairs.flatMap { words -> [String] in
            [" ", "-"].map { words[0].joined() + $0 + words[1].joined() }
        }
        return qualifiers.flatMap { qualifier in subjects.map { "\(qualifier) \($0)" } } + standalone + narrow
    }()
}
