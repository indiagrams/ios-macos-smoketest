import XCTest

// WAVE-0 MEASUREMENT. ITS ENTIRE OUTPUT IS THE DELIVERABLE, AND IT ASSERTS NOTHING ON PURPOSE.
//
// WHAT IT MEASURES: whether a declaration variable handed to `xcodebuild test` reaches THIS
// process — the XCTest bundle process — in either of the two propagation forms plan 08.6-01 puts
// under test:
//   A. `xcodebuild test … TEST_RUNNER_CAPTURE_REQUIRED=1` — xcodebuild's documented test-runner
//      environment injection. The `TEST_RUNNER_` prefix is stripped on the way in, so a process
//      that receives form A sees `CAPTURE_REQUIRED`, NOT `TEST_RUNNER_CAPTURE_REQUIRED`.
//   B. `CAPTURE_REQUIRED=1 xcodebuild test …` — plain inheritance from the invoking shell through
//      xcodebuild → testmanagerd → this bundle. This is the form a GitHub Actions step `env:`
//      block produces, and it is the one 08.6-RESEARCH could not verify (Assumptions Log A1,
//      Open Question 1).
// Both names are read for both variables, so a run cannot confuse "arrived with the prefix
// stripped" with "arrived verbatim". `env_key_count` and `process` are recorded so the evidence
// proves WHICH process was read rather than asserting it.
//
// WHY THERE IS NO ASSERTION HERE: an absence is a legitimate measurement. D-155's guard mechanism
// is chosen FROM this output; a test that failed on absence would be asserting the answer it was
// built to discover, and would have destroyed the measurement it exists to take.
//
// THIS FILE IS SCHEDULED FOR REPLACEMENT. Plan 08.6-03 REPLACES this body with the asserting
// control for whichever form 08.6-01's `RESULT mechanism=` line records — that is, the guard's
// own control, which DOES assert. A reader who finds this file still assertion-free after 08.6-03
// has landed has found a DEFECT, not a design: a non-asserting test left in shipped test
// infrastructure is the R1-IN-02 shape this project has already paid for once (an upper bound
// that could not fail, because entries were deduplicated by title before it was applied), and
// R1-IN-02 stood for a whole phase because it read as a real gate.
//
// EVIDENCE CHANNEL: every line goes through `driveHalfRecord(_:)` (`app/UITestSupport/
// TestRobot.swift:46`), which is both a `print` and an `XCTContext.runActivity`, plus one
// `XCTAttachment`. 08.6-RESEARCH Pitfall 3 is exactly the trap of a bare `print` that never
// reaches the xcresult: the macOS job's log swallows stdout, so a console-only value would read
// as "measured" and be unreadable from the artifact. Plan 08.6-01 reads every value back out of
// the `.xcresult` with `xcrun xcresulttool`, never out of the console pipe.
//
// SWIFT 5.9 / `SWIFT_STRICT_CONCURRENCY: minimal`, matching both UI-test targets.

final class CaptureDeclarationProbe: XCTestCase {
    /// The four names under test. Both the bare and the `TEST_RUNNER_`-prefixed spelling of both
    /// candidate variables, so the evidence distinguishes "arrived, prefix stripped" from
    /// "arrived verbatim" from "did not arrive".
    private static let probedNames = [
        "CAPTURE_REQUIRED",
        "TEST_RUNNER_CAPTURE_REQUIRED",
        "CAPTURE_NON_STRICT",
        "TEST_RUNNER_CAPTURE_NON_STRICT",
    ]

    func testDeclarationSignalPropagation() {
        let environment = ProcessInfo.processInfo.environment
        var lines: [String] = []

        for name in Self.probedNames {
            let value = environment[name]
            let line = "declaration_probe name=\(name) "
                + "present=\(value == nil ? "no" : "yes") "
                + "value=\(value ?? "-")"
            driveHalfRecord(line)
            lines.append(line)
        }

        let countLine = "declaration_probe env_key_count=\(environment.count)"
        driveHalfRecord(countLine)
        lines.append(countLine)

        let processLine = "declaration_probe process=\(ProcessInfo.processInfo.processName)"
        driveHalfRecord(processLine)
        lines.append(processLine)

        let attachment = XCTAttachment(string: lines.joined(separator: "\n"))
        attachment.name = "capture-declaration-probe"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
