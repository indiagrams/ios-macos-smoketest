import XCTest

/// macOS accessibility-tree reachability probe.
///
/// Answers Phase 6 RESEARCH Open Question 2 / the macOS half of D-93: does a macOS UI test
/// that calls `app.launch()` and `try app.snapshot()` — with no foreground-activation call
/// and no window query — return a *populated* accessibility tree on a headless GitHub
/// Actions runner?
///
/// Run via: **CI only.** `.github/workflows/pr.yml:309-323` (`test macOS (unsigned)`) runs
/// the full `App-macOS` scheme, whose Test action includes this target
/// (`app/project.yml:291-295`). Do not run the full macOS scheme on a developer Mac: an
/// unsigned `AppMacOSUITests-Runner` puts a Gatekeeper "damaged, move to Trash" dialog on
/// the desktop.
///
/// This file is a **probe**, not a gate. Its job is to be read out of a CI log. It
/// deliberately never raises an XCTest skip on a headless runner — a skip would answer this
/// question with silence, and the whole point of the probe is that a gate which has never
/// executed is an untested belief with CI syntax. It is superseded by
/// `VisibleStringSweep.swift` in plan 06-17, which should delete it.
@MainActor
final class HarvestProbeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// Launches the app, harvests every visible string from the accessibility tree, and
    /// prints the counts as greppable, unindented lines.
    ///
    /// The environment is recorded as an observable fact (`runner_headless=`) rather than
    /// branched on. `probe_reached_subject=` is asserted separately from, and before, any
    /// property of the harvested strings — so a run that never reached the app reads as a
    /// failure to reach it, not as a statement about what the app renders.
    func testAccessibilityTreeIsReachableOnThisRunner() throws {
        // Detection idiom copied from AppStoreScreenshotTests.swift:52-54. macOS XCUITest
        // spawns the runner via launchd, which scrubs CI and GITHUB_ACTIONS from the
        // environment, so the home directory is the only usable signal. The detection is
        // copied; the skip is not.
        let headless = NSHomeDirectory() == "/Users/runner"
        print("runner_headless=\(headless)")

        // No foreground-activation call and no app.windows query — those are exactly the two
        // calls the existing test's skip exists to avoid, and either one would make a red run
        // uninterpretable.
        app.launch()

        let root = try app.snapshot()
        var strings: [String] = []
        harvest(root, into: &strings)

        print("harvested_strings=\(strings.count)")
        print("harvested_distinct=\(Set(strings).count)")
        print("probe_reached_subject=\(!strings.isEmpty)")
        for harvested in strings.prefix(40) {
            print("harvested: \(harvested)")
        }

        // Assertion 1 — did the probe reach its subject at all?
        XCTAssertGreaterThan(
            strings.count,
            0,
            "the probe saw an empty accessibility tree — it did not reach the app"
        )

        // Assertion 2 — and only then, a property of what it saw. Non-empty is not the same
        // as readable: harvest() filters on isEmpty, so a tree of whitespace-only labels
        // would satisfy assertion 1 while carrying no legible string.
        let readable = strings.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        XCTAssertGreaterThan(
            readable.count,
            0,
            "the probe reached the app but every harvested string was whitespace"
        )

        // TEMPORARY, for exactly one CI run (plan 06-01 Task 2, second push).
        //
        // Run 33924732185 proved the probe executes on the runner and passes both
        // assertions -- and that NOT ONE of the print() lines above reached the
        // xcodebuild log. A macOS UI-test bundle is injected into
        // AppMacOSUITests-Runner.app, launched by testmanagerd; its stdout is not
        // connected to xcodebuild's pipe, so print() is invisible in CI. An XCTest
        // failure message, by contrast, travels over XCTest's own IPC and is
        // rendered by xcbeautify.
        //
        // The counts must be READ, not inferred from a green assertion, so they are
        // emitted here as a deliberate failure -- observed red once, then removed by
        // the next commit. Placed last, so a red run also proves both assertions
        // above passed first.
        let counters = "PROBE_COUNTERS runner_headless=\(headless)"
            + " harvested_strings=\(strings.count)"
            + " harvested_distinct=\(Set(strings).count)"
            + " probe_reached_subject=\(!strings.isEmpty)"
        let sample = strings.prefix(40).joined(separator: " | ")
        XCTFail("\(counters) sample=\(sample)")
    }

    /// Appends the non-empty `label`, `title`, `placeholderValue` and string `value` at
    /// `node`, then recurses over `node.children`.
    ///
    /// Reading `label` alone would be a correct check pointed at the wrong population: it
    /// misses every `TextField` prompt, which lands in `placeholderValue`, and every field's
    /// current text, which lands in `value`.
    private func harvest(_ node: XCUIElementSnapshot, into out: inout [String]) {
        let candidates = [
            node.label,
            node.title,
            node.placeholderValue ?? "",
            (node.value as? String) ?? ""
        ]
        out.append(contentsOf: candidates.filter { !$0.isEmpty })
        for child in node.children {
            harvest(child, into: &out)
        }
    }
}
