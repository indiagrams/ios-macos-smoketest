import CoreGraphics
import Foundation

// THE CAPTURE DECLARATION, AND THE ONE DECISION A SHORT DISPLAY FORCES (D-154, D-155, plan 08.6-03).
//
// WHY THIS EXISTS
//
//   Until 2026-09-15 a display too short to hold the capture window produced an `XCTSkip`, full
//   stop. That answer is correct for a CI cell and CATASTROPHIC for a capture run, and the suite
//   could not tell the two apart:
//
//     `ci/take-screenshots.sh:187` calls `ci/extract-mac-screenshots.sh`, whose `rm` at `:53`
//     DELETES the eight `fastlane/Mac_screenshots/en-US/macos-*.png` tiles BEFORE it discovers
//     whether the run produced any attachment at all — its "no attachments found" exit is at
//     `:156`, a hundred lines LATER. Those tiles are untracked and gitignored (`.gitignore:68`),
//     so there is no blob to restore them from. A SKIP therefore deletes the previous set, puts
//     nothing in its place, and the run exits 0.
//
//   So the default answer on a short display is now REFUSE, and a skip has to be asked for. The
//   polarity is deliberate and is the safe one: a red is recoverable and a deleted untracked tile
//   is not, so a NEW invocation path that declares nothing goes loudly red rather than quietly
//   reaching the delete.
//
// WHAT IS PERMITTED TO ASK FOR A SKIP, AND WHY THAT IS NOT A HOLE
//
//   Only a FORK-OWNED invocation boundary that provably CANNOT reach
//   `ci/extract-mac-screenshots.sh:53` — i.e. one that calls `xcodebuild` directly and never
//   `ci/take-screenshots.sh`. Those cells run on hosted macOS runners whose visible frame is
//   1024x768 (run 34978692666, D-137), where skipping IS the correct answer, and a permanently red
//   cell is how a real red stops being read (D-154). The declaration is never set on the capture
//   path, so the one path that CAN reach the delete keeps the strict default. B-01 later measured
//   that there are FOUR such invocation paths and not the two D-155 originally recorded, two of
//   them running this suite by SCHEME INCLUSION without ever naming it;
//   `test/capture_suite_invokers_test.rb` is the gate that fails when that number changes again.
//
// THE TRAP THIS FILE IS BUILT AROUND: THE TWO NAMES ARE DIFFERENT NAMES
//
//   A GitHub Actions step SETS `TEST_RUNNER_CAPTURE_NON_STRICT` in its `env:` block; this process
//   READS the bare `CAPTURE_NON_STRICT`. `xcodebuild` strips the `TEST_RUNNER_` prefix in transit,
//   and that prefix is what carries the value across xcodebuild -> testmanagerd -> the test
//   bundle. Measured on BOTH machines — five runs on the iOS Simulator and four on a hosted
//   `macos-15` runner, run 35047725894, UL-100 — the bundle's environment gained EXACTLY ONE key
//   and it was the BARE one, while the prefixed spelling was ABSENT in every run INCLUDING the run
//   where the value arrived. Two spellings that do NOT work, each measured absent twice: the same
//   name appended to the `xcodebuild` command line (consumed as a BUILD SETTING), and the bare
//   name alone in a step `env:` block (plain shell inheritance does not reach the bundle process).
//   A guard reading the prefixed name would see nothing, forever, and would look like it worked.
//
// WHY THE DECISION IS A PURE FUNCTION, AND WHY THIS FILE IMPORTS NO XCTest
//
//   A guard only ever observed green is not known to test anything (D-158, UL-077), and every
//   interesting input here — a 1024x768 display, an unparseable requirement — is one the
//   developer's Mac cannot supply. Taking the environment and the screen size as PARAMETERS makes
//   all five rows exercisable without a runner, which is exactly what
//   `evidence/08.6-03-decision-harness.swift` does: it compiles THIS FILE, unmodified, next to a
//   `main` that drives the five rows. That only keeps working while this file imports nothing but
//   Foundation and CoreGraphics. Do not reach for XCTest, `ProcessInfo`, `NSScreen` or any app
//   type in here — the caller supplies all three inputs, and the harness stops testing shipped
//   code the moment it cannot compile this file on its own.
//
//   This is also why the decision is NOT in `ScreenshotContract.swift`, which plan 08.6-03 named
//   as its sink: that file is at 367 lines after this plan's `assertHeadInFrame` move and imports
//   XCTest, so it could take neither the volume (standing rule 15's 400-line `--strict` budget,
//   UL-056) nor the no-XCTest constraint. Both generators GLOB this directory
//   (`app/project.yml` `- path: MacOSUITests`, `app/Project.swift` `"MacOSUITests/**"`), so a new
//   file here needs no manifest edit. `ScreenshotContract.swift` carries the prose cross-reference.

enum CaptureFit {
    /// What `AppStoreScreenshotTests.setUpWithError` does about the display it found. `skip` and
    /// `refuse` both carry the whole reason string, because the MESSAGE is the deliverable in both
    /// directions: a skip nobody can attribute and a refusal that does not say what it prevented
    /// are equally useless six months later.
    enum Decision: Equatable {
        case proceed
        case skip(String)
        case refuse(String)
    }

    /// The name THIS PROCESS reads. Bare, because `xcodebuild` strips the `TEST_RUNNER_` prefix.
    static let declarationVariable = "CAPTURE_NON_STRICT"

    /// The name a CI step SETS. Prefixed, in a step- or job-level `env:` block — never as a
    /// trailing argument to `xcodebuild`, which is consumed as a build setting and never arrives.
    static let declarationVariableAsSet = "TEST_RUNNER_CAPTURE_NON_STRICT"

    /// The only value that turns the safe default off: exactly `"1"`, nothing else. That is this
    /// repository's existing boolean convention (`bin/uitest-destination.sh:39`,
    /// `HOMEBREW_NO_AUTO_UPDATE: "1"`), and the narrowness is the point — `"0"`, `"true"`, `"yes"`,
    /// `""` and any typo all mean REFUSE. An unrecognised value is not a quiet opt-out (T-08.6-11).
    static let declarationValue = "1"

    /// Does this run say it is a NON-CAPTURE run — one that cannot reach
    /// `ci/extract-mac-screenshots.sh:53`'s `rm`, and for which skipping is the correct answer?
    static func declaresNonCapture(_ environment: [String: String]) -> Bool {
        environment[declarationVariable] == declarationValue
    }

    /// THE DECISION. Pure: same inputs, same answer, and no process state read anywhere inside it.
    ///
    /// - Parameter visible: the screen's visible frame SIZE, or `nil` when no screen could be read.
    /// - Parameter requested: the point size the capture window is forced to, as `"WIDTHxHEIGHT"`.
    /// - Parameter environment: the test bundle process's environment.
    ///
    /// Five rows, and the last two are the ones a later reader is most likely to get wrong:
    ///   1. fits, nothing declared           -> `proceed`
    ///   2. too short, nothing declared      -> `refuse`. This is the row that protects the tiles.
    ///   3. too short, non-capture declared  -> `skip`, green. The hosted runner's right answer.
    ///   4. fits, non-capture declared       -> `proceed`. A declaration is PERMISSION to skip a
    ///      display that cannot hold the window; it is never an INSTRUCTION to skip one that can.
    ///   5. `requested` unparseable          -> the same answer as "too short". An unreadable
    ///      requirement is not a licence to delete: whether the window fits is then UNKNOWN, and a
    ///      run that can reach the `rm` must stop rather than guess.
    static func captureDeclaration(visible: CGSize?,
                                   requested: String,
                                   environment: [String: String]) -> Decision {
        let visibleText = visible.map { "\($0.width)x\($0.height)" } ?? "none"
        let parts = requested.split(separator: "x").compactMap { Double($0) }
        if parts.count == 2, let visible, visible.width >= parts[0], visible.height >= parts[1] {
            return .proceed
        }
        let cause: String
        if parts.count != 2 {
            cause = "the requested capture window size \"\(requested)\" could not be read as a "
                + "WIDTHxHEIGHT point pair, so whether it fits the visible frame (\(visibleText)) "
                + "is UNKNOWN"
        } else if visible == nil {
            cause = "no screen could be read, so whether the \(requested)-point capture window "
                + "fits is UNKNOWN"
        } else {
            cause = "the screen's visible frame (\(visibleText) points) cannot contain the "
                + "\(requested)-point capture window, so every shot would overflow the screen"
        }
        if declaresNonCapture(environment) {
            return .skip(cause + " (run 34978692666, D-137) — and this run DECLARED itself a "
                + "non-capture run via \(declarationVariable)=\(declarationValue), so a skip is "
                + "the correct answer here: it invokes xcodebuild directly and cannot reach "
                + "ci/extract-mac-screenshots.sh")
        }
        return .refuse("REFUSING to run the capture suite rather than skipping it: \(cause). "
            + "A skip here does NOT quietly produce nothing — ci/take-screenshots.sh:187 goes on "
            + "to ci/extract-mac-screenshots.sh, whose rm at :53 DELETES the existing "
            + "fastlane/Mac_screenshots/en-US/macos-*.png tiles BEFORE it discovers there are no "
            + "attachments (:156), and those tiles are untracked and gitignored, so nothing "
            + "restores them. If this run genuinely cannot reach that rm — it calls xcodebuild "
            + "directly and never ci/take-screenshots.sh — declare it by setting "
            + "\(declarationVariableAsSet)=\(declarationValue) in the step's env: block (NOT as a "
            + "trailing xcodebuild argument: that spelling is consumed as a build setting and was "
            + "measured never to arrive) and this becomes a green skip. D-154, D-155.")
    }
}

/// Thrown by `setUpWithError` AFTER it has recorded the refusal with `XCTFail`, so the suite stops
/// instead of continuing into the capture. `continueAfterFailure` is true in that suite, which is
/// why a bare `XCTFail` would not be enough on its own.
enum CaptureFitRefusal: Error {
    case displayCannotHoldCaptureWindow(String)
}
