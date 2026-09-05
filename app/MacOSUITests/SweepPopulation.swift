import XCTest

// THE POPULATIONS THE D-93 SWEEP RUNS OVER, AND THE THREE IT DOES NOT — macOS twin of
// `app/UITests/SweepPopulation.swift`. Two files rather than one shared one because the two UI-test
// targets are two separate bundles; `app/project.yml` gives each of them its own `- path:` sweep and
// only `Shared/AccessibilityIdentifiers.swift` is listed into both.
//
// THE macOS POPULATION IS MOSTLY NOT THE APP, AND THAT IS MEASURED, NOT FEARED. Plan 06-01 harvested
// 114 strings from a four-element placeholder screen on a GitHub Actions runner and about 110 of them
// were the menu bar — several of those (`Log Out Anka`, `AnkaGuestAddons.pkg`) artifacts of the CI
// provider's VM image that exist on no developer Mac. A sweep asserting over the whole tree would be
// asserting on the runner's naming. `subtreeBucket` below is the counted exclusion that fixes it: the
// menu bar is chrome in its entirety, the app's own content is not, and both are numbers.
//
//   rendered         — what the APP draws. The only bucket the prose condition is asserted over.
//   chrome           — the application element's own name, a window's title, and the WHOLE menu bar.
//                      Resolved from CFBundleDisplayName <- $(DISPLAY_NAME) <- app/Identity.xcconfig,
//                      already covered by criterion 7's tracked-file gate, and the one place the
//                      product name legitimately reaches the screen. 06-01 measured that BOTH
//                      spellings appear — the display name in the menu bar and the product name as
//                      the process name — so the exemption is by SUBTREE, which covers both without
//                      naming either.
//   systemData       — TimeZone.knownTimeZoneIdentifiers, Foundation data (APP-07).
//   platformControl  — controls AppKit supplies. Empty on this platform in practice, and printed
//                      anyway: a zero that is printed is a number that can move.
//
// The UI-SPEC's exemption table lists the application menu bar under chrome and the standard Edit
// menu under platform controls. In the tree they are one subtree, so this file resolves the overlap
// in writing rather than leaving it to be discovered: the whole menu bar counts as chrome, and every
// chrome string is reported individually as well as counted, so nothing is dropped either way.

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
            // Carried across from the iOS twin deliberately rather than deleted as unreachable. On iOS
            // this is load-bearing — the software keyboard lives in its own window of the app's own
            // process and its typing-prediction bar is nondeterministic. On macOS it should never fire,
            // and `platform_control_strings=` printing a zero is how that is stated as an observation
            // rather than assumed by the clause's absence.
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

    // `(format segment, text)`. The direction picker is on decode for all of these — encoding cannot
    // fail, so every error sentence the encode surface owns is reachable only in the other direction.
    // NO FIXTURE CONSTANTS HERE, AND THAT IS THE MEASURED DIFFERENCE FROM THE iOS TWIN. The iOS walk
    // types five inputs to reach the error sentences; this one does not type at all. What a headless
    // GitHub Actions runner does with `typeText` is UNMEASURED — 06-01 measured launch and snapshot,
    // and `ShellTests` measures clicking, and neither of them measures typing. A walk step that might
    // silently not happen is the population failure this phase exists to stop, and a walk step that
    // hard-fails on the only machine that runs it is a gate that is red forever. The macOS half
    // therefore reaches its error states by CLICKING the direction picker, and says so.

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
