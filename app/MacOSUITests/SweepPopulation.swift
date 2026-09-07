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
    // THE FIXTURES ARE HERE BECAUSE TYPING ON A HEADLESS RUNNER WAS MEASURED, NOT ASSUMED. This file
    // first shipped with no fixtures at all and said so: 06-01 measured launch and snapshot,
    // `ShellTests` measures clicking, and neither measured `typeText`, so the walk reached its error
    // states by clicking the direction picker instead. Run 33960384969, job `app (macOS)`, then
    // measured it directly — `TYPING_PROBE typed=zz observed=zz` on a runner with
    // `runner_headless=true` — and a population gap that is known to be closable is not one to leave
    // open. The lists below are the iOS twin's, verbatim.

    /// Typed ONCE each, then read under every format listed — typing is the expensive half of the
    /// walk and a format change costs one click.
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

// MARK: - The strings Phase 7 added, and where each of them is judged

/// One string this phase added: the catalog key that owns it, the value the catalog holds, and how
/// a RENDERED instance of it is recognised in the harvest.
///
/// KEYED BY THE CATALOG KEY, NOT BY THE SENTENCE. The key is the identity — `Localizable.xcstrings`
/// is where the string is defined, `StringCatalogTests` asserts the key resolves to the sentence,
/// and this file asserts that the sentence reaches a screen. Three files, one key, no fourth place
/// where a sentence could be edited without the others noticing.
///
/// THIS IS NOT A QUERY BY VISIBLE TEXT. The house rule forbids ADDRESSING an element by the words
/// it shows, because a query by text asserts on the very strings under test. Reading the harvested
/// SET afterwards and asking whether a rendered string matches is the sweep's own shape — its
/// prose condition already does exactly this, over the same set, in the other direction.
struct SweptString {
    /// The `Localizable.xcstrings` key.
    let key: String

    /// The catalog's own value, carried so this file can be read without opening the catalog, and
    /// so a failure message can say what was looked for rather than only that nothing matched.
    let catalogValue: String

    /// An ANCHORED pattern a rendered instance matches. Anchored because the argument-taking rows
    /// render a different sentence at every stack length, and an unanchored fragment would be
    /// satisfied by a longer string that merely contains it — `Step 2` is a prefix of
    /// `Step 2 of 3, Base64 encode`, and treating one as evidence for the other is the wrong
    /// population wearing a match.
    let pattern: String

    /// `nil` when the harvest can see this string. Otherwise the NAMED reason it cannot, and the
    /// site that covers it instead. Never an absence: a string that leaves the population leaves it
    /// with a reason and a printed count, so the number moves when somebody adds one.
    let exemption: String?
}

extension SweepPopulation {
    /// The eight strings 07-UI-SPEC §"Copywriting Contract — delta" adds, all eight, in its order.
    ///
    /// SIX ARE HARVESTABLE AND TWO ARE NOT, AND THAT SPLIT IS MEASURED RATHER THAN ASSUMED. The two
    /// announcements are posted through `AccessibilityNotification.Announcement`, which delivers a
    /// sentence to assistive technology and puts NO element in the accessibility tree — so the four
    /// properties the harvest collects at every node cannot see them, on either platform, at any
    /// stack length. Measured on iOS 17.5 and 18.6 on 2026-09-06 by running the fourteen-step walk
    /// and filtering the harvested set for both patterns: `matches=0` for each, while the other six
    /// matched. The counts are PRINTED on every run, so if a future runtime does surface them the
    /// number moves rather than the exemption quietly becoming permanent.
    ///
    /// NO NEW EXEMPTION IS ADDED TO THE THREE BUCKETS. `chrome`, `systemData` and `platformControl`
    /// are unchanged; these two strings are not exempted FROM the swept set, they are unreachable
    /// BY it, and they are covered where they can be: `StringCatalogTests` asserts the moved
    /// announcement's argument order and the removed announcement's plural discrimination at three
    /// counts, which is a stronger statement about them than "it appeared somewhere on a screen".
    static let phase7Strings: [SweptString] = [
        SweptString(
            key: "step.position",
            catalogValue: "Step %lld",
            pattern: "^Step [0-9]+$",
            exemption: nil
        ),
        SweptString(
            key: "step.root",
            catalogValue: "This step starts the pipeline.",
            pattern: "^This step starts the pipeline\\.$",
            exemption: nil
        ),
        SweptString(
            key: "step.moveUp",
            catalogValue: "Move step up",
            pattern: "^Move step up$",
            exemption: nil
        ),
        SweptString(
            key: "step.moveDown",
            catalogValue: "Move step down",
            pattern: "^Move step down$",
            exemption: nil
        ),
        SweptString(
            key: "step.remove",
            catalogValue: "Remove step",
            pattern: "^Remove step$",
            exemption: nil
        ),
        SweptString(
            key: "step.card.label",
            catalogValue: "Step %lld of %lld, %@",
            pattern: "^Step [0-9]+ of [0-9]+, .+$",
            exemption: nil
        ),
        SweptString(
            key: "step.announce.moved",
            catalogValue: "Moved to position %lld of %lld.",
            pattern: "^Moved to position [0-9]+ of [0-9]+\\.$",
            exemption: "posted as an accessibility announcement, which puts no element in the tree; "
                + "covered by StringCatalogTests.argumentTakingStepKeysSubstituteInOrder"
        ),
        SweptString(
            key: "step.announce.removed",
            catalogValue: "Step removed. %lld step remains. / Step removed. %lld steps remain.",
            pattern: "^Step removed\\. [0-9]+ steps? remains?\\.$",
            exemption: "posted as an accessibility announcement, which puts no element in the tree; "
                + "covered by StringCatalogTests.removalAnnouncementSelectsTheSingularOnlyAtOne"
        )
    ]

    /// How many harvested strings match `expected`'s pattern.
    ///
    /// `range(of:options:.regularExpression)` rather than `NSRegularExpression`: one call, no
    /// throwing initialiser to swallow, and a malformed pattern answers `nil` for every string,
    /// which reads as `matches=0` and fails the assertion above rather than passing silently.
    static func matches(_ expected: SweptString, in harvested: Set<String>) -> [String] {
        harvested.filter { $0.range(of: expected.pattern, options: .regularExpression) != nil }.sorted()
    }
}
