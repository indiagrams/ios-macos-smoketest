import XCTest

// THE STANDING CONTROL FOR THE CAPTURE GUARD'S *INPUT*. IT ASSERTS. (plan 08.6-03)
//
// WHAT CHANGED, AND WHY THE PREVIOUS HEADER PROMISED IT. Plan 08.6-01 shipped this file as a pure
// MEASUREMENT that asserted nothing on purpose — D-155's mechanism was chosen FROM its output, and
// a test that failed on absence would have been asserting the answer it existed to discover. Its
// own header then said, in as many words, that a reader who found it still assertion-free after
// plan 08.6-03 had landed had found a DEFECT rather than a design. 08.6-03 has landed, the
// mechanism is settled, and this is that replacement.
//
// THE MEASUREMENT IT IS BUILT ON — `RESULT mechanism=form-A`, evidence run 35047725894, UL-100,
// reproduced on the iOS Simulator (five runs) and on a hosted `macos-15` runner (four runs):
//
//   * A `TEST_RUNNER_`-prefixed variable EXPORTED INTO XCODEBUILD'S ENVIRONMENT — a step- or
//     job-level `env:` block — arrives in this process WITH THE PREFIX STRIPPED. The environment
//     gained EXACTLY ONE key, and it was the bare one.
//   * The SAME name written as a TRAILING ARGUMENT to `xcodebuild` does NOT arrive: it is consumed
//     as a build setting, and xcodebuild echoes it back under its command-line build-settings
//     block, which is what makes that spelling look like it worked.
//   * The BARE name in a step `env:` block does NOT arrive either. Plain shell inheritance does not
//     cross xcodebuild -> testmanagerd -> this bundle. The `TEST_RUNNER_` prefix is the carrier.
//
//   So the two spellings are DIFFERENT NAMES by design: a CI step sets
//   `TEST_RUNNER_CAPTURE_NON_STRICT`, and `CaptureFit.declarationVariable` reads the bare
//   `CAPTURE_NON_STRICT`. A guard reading the prefixed name sees nothing in every run, including
//   the run where the value arrived.
//
// WHICH CONTROL THIS IS, AND WHICH IT IS NOT. This case is the standing control for the guard's
// INPUT — that the declaration a CI step writes actually reaches the process the guard runs in.
// The controls for the guard's OUTPUT — the refusal firing red on a real 1024x768 display, and the
// declared cell still skipping green — are D-158's, and they are plan 08.6-07's on a hosted runner,
// because that is the machine which supplies the property. Neither substitutes for the other.
//
// HOW IT AVOIDS ASSERTING ITS OWN INPUT'S ABSENCE, WHICH WOULD BE A TAUTOLOGY. The arm to assert
// is chosen from a SECOND, independent pair of markers the invoking step sets, never from the
// subject variable itself:
//
//   TEST_RUNNER_CAPTURE_PROBE_SUBJECT   the variable name under test, e.g. CAPTURE_NON_STRICT
//   TEST_RUNNER_CAPTURE_PROBE_EXPECT    `present:<value>` or `absent`
//
// (both arrive here prefix-stripped, by the same mechanism, which is itself part of what a green
// run demonstrates). An "absent" arm therefore fails when the subject DID arrive, and a "present"
// arm fails when it did not — two different ways to be wrong, neither of which the test supplies
// to itself.
//
// AND WHY AN UNMARKED RUN SKIPS RATHER THAN FAILS. This class lives in the UI-test target, and
// B-01 measured FOUR paths that run that target's whole scheme — two of them the REQUIRED
// `app (macOS)` and `app (Tuist macOS)` contexts, which name no suite and simply run everything.
// An unconditional assertion here would turn those red on every pull request. An unmarked run has
// been given no question to answer, so it says so by name and skips; the skip message states
// exactly which two variables an invoking step must set, in the spelling that was measured to
// arrive.
//
// EVIDENCE CHANNEL: every line still goes through `driveHalfRecord(_:)`
// (`app/UITestSupport/TestRobot.swift:46`), which is both a `print` and an
// `XCTContext.runActivity`, plus one `XCTAttachment`. The macOS job's log swallows stdout
// (08.6-RESEARCH Pitfall 3), so a console-only value reads as "measured" and is unreadable from
// the artifact; values are pulled back out of the `.xcresult` with `xcrun xcresulttool`.
//
// SWIFT 5.9 / `SWIFT_STRICT_CONCURRENCY: minimal`, matching both UI-test targets.

final class CaptureDeclarationProbe: XCTestCase {
    /// The four names RECORDED on every run. Both the bare and the `TEST_RUNNER_`-prefixed spelling
    /// of both candidate variables, so the record distinguishes "arrived, prefix stripped" from
    /// "arrived verbatim" from "did not arrive". Recording is not asserting: the assertion below is
    /// about the ONE name the invoking step nominated.
    private static let probedNames = [
        "CAPTURE_REQUIRED",
        "TEST_RUNNER_CAPTURE_REQUIRED",
        "CAPTURE_NON_STRICT",
        "TEST_RUNNER_CAPTURE_NON_STRICT",
    ]

    /// The markers naming the question. Read prefix-stripped, like everything else that arrives.
    private static let subjectMarker = "CAPTURE_PROBE_SUBJECT"
    private static let expectMarker = "CAPTURE_PROBE_EXPECT"

    func testDeclarationSignalPropagation() throws {
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

        let subject = environment[Self.subjectMarker]
        let expectation = environment[Self.expectMarker]
        let verdictLine = "declaration_probe subject=\(subject ?? "-") expect=\(expectation ?? "-")"
        driveHalfRecord(verdictLine)
        lines.append(verdictLine)

        let attachment = XCTAttachment(string: lines.joined(separator: "\n"))
        attachment.name = "capture-declaration-probe"
        attachment.lifetime = .keepAlways
        add(attachment)

        guard let subject, let expectation else {
            throw XCTSkip(
                "this run nominated no declaration to check, so there is no question to answer "
                    + "here. An invoking step asserts one by setting BOTH "
                    + "TEST_RUNNER_\(Self.subjectMarker)=<VARIABLE_NAME> and "
                    + "TEST_RUNNER_\(Self.expectMarker)=present:<value> (or =absent) in its own "
                    + "env: block — the exported, TEST_RUNNER_-prefixed spelling, NOT a trailing "
                    + "xcodebuild argument, which is consumed as a build setting and was measured "
                    + "never to arrive (run 35047725894, UL-100). A full-scheme run that names no "
                    + "suite reaches this case with no markers and is expected to land here"
            )
        }

        assertDeclaration(subject: subject, expectation: expectation, environment: environment)
    }

    /// The assertion itself, split out only because `testDeclarationSignalPropagation` is at
    /// SwiftLint's 50-line function-body limit once the recording above is counted. No logic moved:
    /// the caller decides there IS a question, this decides whether it was answered correctly.
    private func assertDeclaration(subject: String,
                                   expectation: String,
                                   environment: [String: String]) {
        let actual = environment[subject]
        if expectation == "absent" {
            XCTAssertNil(actual, "the invoking step declared that \(subject) would NOT reach this "
                + "process, and it did — value \(actual ?? "-"). Either the propagation form under "
                + "test does carry it after all, or something else in the environment is setting "
                + "it; both make this run's measurement unusable rather than merely surprising")
        } else if let value = expectation.split(separator: ":", maxSplits: 1).last.map(String.init),
                  expectation.hasPrefix("present:") {
            XCTAssertEqual(actual, value, "the invoking step set \(subject) to \(value) via the "
                + "exported TEST_RUNNER_ spelling and this process read \(actual ?? "nothing"). "
                + "That propagation is what the capture guard's declaration depends on: if it "
                + "stops working, CaptureFit.declaresNonCapture answers false for a run that DID "
                + "declare, and a hosted-runner cell that should skip green refuses instead")
        } else {
            XCTFail("\(Self.expectMarker)=\(expectation) is not one of `absent` or "
                + "`present:<value>` — this run asked a question this case cannot answer, and "
                + "silently passing it would be worse than saying so")
        }
    }
}
