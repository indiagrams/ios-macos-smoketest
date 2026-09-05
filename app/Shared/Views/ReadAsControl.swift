// ReadAsControl — D-89's detection made an OBJECT ON THE SCREEN rather than a
// behaviour to reverse-engineer, plus APP-07's time-zone picker
// (06-UI-SPEC.md §"3. Timestamps").
//
// WHY THE DETECTION RESULT IS A CONTROL AND NOT A SENTENCE. `20260904` is a
// plausible Unix epoch AND a plausible calendar date, so any detector has to
// choose. D-89's answer is that the choice is shown as the SELECTION of a
// segmented picker the user can simply change: a wrong guess costs one tap
// instead of being a dead end, and the tests get a named element to assert
// instead of a behaviour to infer. `TimestampDetection.parse(_:as:)` reads the
// input under whatever segment is selected, independently of what the detector
// would have said — 06-08 asserts that independence, which is what makes this
// control real rather than decorative.
//
// THE DETECT BUTTON IS DISABLED, NEVER REMOVED. A disabled control is still in
// the accessibility tree, so keeping it costs plan 06-16's sweep nothing and
// gains it a string; removing it would take "Detect" out of the harvest exactly
// when the user has not overridden anything, which is the app's opening state.
// Plan 06-16's walk step 9 taps it.
//
// THE CAPTION IS UNCONDITIONAL. One string, one branch, always harvestable —
// the same reason the diagnostic strip is a fixed part of the card rather than
// a container that pops in and out.
//
// THE ZONE PICKER'S OPTIONS ARE SYSTEM DATA. `TimeZone.knownTimeZoneIdentifiers`
// is Foundation's table, not this app's prose, and the UI-SPEC names it a
// counted exemption from the D-93 sweep rather than a silent subtraction. Its
// CLOSED state renders the selected identifier, which is app-visible text and
// is harvested normally.

import SwiftUI

// MARK: - The three segments' strings

extension ReadAs {
    /// The `Localizable.xcstrings` key naming this segment.
    ///
    /// The engine deliberately knows nothing about localization — ``ReadAs``'s
    /// raw values are case names, not user-facing text — so the mapping lives
    /// here, in the view layer, where the catalog does.
    var stringKey: String {
        switch self {
        case .unixEpoch: "timestamps.readAs.epoch"
        case .iso8601: "timestamps.readAs.iso8601"
        case .localTime: "timestamps.readAs.localTime"
        }
    }
}

/// The valid-state diagnostic: `timestamps.diagnostic.valid` — "Read as %@." —
/// with the selected segment's own name substituted.
///
/// **Five detection results reconcile onto three segments, and the strip names
/// the SEGMENT.** `TimestampDetection` distinguishes epoch seconds from epoch
/// milliseconds and extended ISO 8601 from the basic-format date; the picker
/// has three segments because those five collapse onto three ways of READING
/// the input, and `segment(for:)` is that collapse. The UI-SPEC's mockup
/// sketches the unit inside this sentence ("Unix epoch (seconds)"), but its own
/// string inventory — the normative list, which says every string the app
/// renders is in it — carries no key for either unit, and minting unapproved
/// user-visible text is the call plan 06-12 already declined once on this same
/// surface family. The unit is not lost: a 13-digit input read as milliseconds
/// renders its seconds value in the epoch cell, where the reinterpretation is
/// visible as the number itself rather than as a claim about it.
func readAsDiagnostic(_ readAs: ReadAs) -> String {
    String(
        format: NSLocalizedString("timestamps.diagnostic.valid", comment: ""),
        locale: .current,
        localizedSentence(key: readAs.stringKey)
    )
}

// MARK: - The controls

/// The "Read as" segmented picker, its Detect button and the caption below.
struct ReadAsControl: View {
    /// The app-level model. The selection is its property, not this view's —
    /// D-82 names it among the things that must survive navigating away and
    /// back, and on macOS a detail swap would discard view-local state.
    @Bindable var model: AppModel

    /// What the detector says about the current input. Shown as the selection
    /// while the user has made no choice of their own.
    let detected: ReadAs

    /// Reads through to the detector's answer and writes the user's choice.
    ///
    /// A projection rather than a stored selection, so there is no second copy
    /// of the detection result to go stale when the input changes.
    private var selection: Binding<ReadAs> {
        Binding(
            get: { model.timestampsReadAs ?? detected },
            set: { model.timestampsReadAs = $0 }
        )
    }

    /// The labelled control row, then the always-present caption.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            PickerRow(label: "timestamps.picker.readAs") {
                HStack(spacing: Spacing.sm) {
                    ReadAsPicker(selection: selection)
                    DetectButton(model: model)
                }
            }
            Text("timestamps.readAs.caption")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// The three segments themselves.
///
/// Segmented rather than a pull-down, for the reason `FormatPicker` records:
/// every option's label is permanently in the accessibility tree, so plan
/// 06-16's sweep sees all three without having to open anything.
struct ReadAsPicker: View {
    /// The effective segment, reading through to detection.
    @Binding var selection: ReadAs

    /// One segment per case, titled by its own catalog key.
    var body: some View {
        Picker("timestamps.picker.readAs", selection: $selection) {
            ForEach(ReadAs.allCases, id: \.self) { readAs in
                Text(LocalizedStringKey(readAs.stringKey)).tag(readAs)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityIdentifier(AccessibilityIdentifiers.Timestamps.readAs)
    }
}

/// Restores automatic detection.
///
/// Disabled — and still present, and still in the accessibility tree — while
/// detection is already driving the selection, because there is then nothing
/// for it to restore. See the file header.
struct DetectButton: View {
    /// The app-level model. Clearing its choice is the whole action.
    @Bindable var model: AppModel

    /// A button that puts the selection back under the detector's control.
    var body: some View {
        Button("timestamps.detect") {
            model.timestampsReadAs = nil
        }
        .buttonStyle(.borderless)
        .disabled(!model.isReadAsOverridden)
        .accessibilityIdentifier(AccessibilityIdentifiers.Timestamps.detect)
    }
}

/// The zone every representation is rendered in (APP-07).
///
/// Defaults to the device's own zone, which is what makes the "Date and time"
/// cell the local-time representation with nothing touched — see
/// ``TimestampRepresentation/render(_:in:)`` for why there is no fourth cell.
struct TimeZonePicker: View {
    /// The app-level model. D-82 names the selected zone by name.
    @Bindable var model: AppModel

    /// The selection as an identifier, which is what the option rows are.
    ///
    /// A zone that no longer resolves falls back to the device's rather than
    /// leaving the picker on a value nothing can render.
    private var identifier: Binding<String> {
        Binding(
            get: { model.timestampsTimeZone.identifier },
            set: { model.timestampsTimeZone = TimeZone(identifier: $0) ?? TimestampCodec.defaultTimeZone }
        )
    }

    /// A pull-down over the system's zone table, sorted and de-duplicated by
    /// `TimestampCodec.pickerOrder` — a repeated identifier would collide as a
    /// `ForEach` id.
    var body: some View {
        Picker("timestamps.picker.timeZone", selection: identifier) {
            ForEach(TimestampCodec.timeZoneIdentifiers, id: \.self) { zone in
                Text(verbatim: zone).tag(zone)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .accessibilityIdentifier(AccessibilityIdentifiers.Timestamps.timeZone)
    }
}
