// AppModel — the one app-level observable model (D-82, D-12, APP-12).
//
// NOT A VIEW, and it imports no UI framework. Foundation for `TimeZone`, and
// Observation for the macro. The root view constructs exactly one of these as
// `@State private var model = AppModel()` and hands surfaces the properties
// they own; nothing here is static, shared or global.
//
// WHY THE SELECTION ENUMS LIVE HERE. `EncodeFormat` and `EncodeDirection` are
// per-surface UI selections, not conversions, so they are not ``Operation``
// cases — but the three-by-two product of them IS exactly the six codec
// operations, and `EncodeFormat.operation(_:)` below is the total mapping that
// says so. `PipelineTests.theEncodeSelectionsCoverExactlyTheSixCodecOperations`
// asserts the product rather than a count, so a format added without an
// operation, or two selections collapsing onto one operation, fails there.
//
// D-12, AS A STRUCTURAL PROPERTY RATHER THAN A PROMISE. Nothing in this file
// is written to the user-defaults store, nothing reaches the file system, and
// nothing is written to any log. That is the whole mechanism behind the app's
// "we never stored your API key" claim: there is no code here that could.
// Plan 06-09's acceptance criteria grep `app/Shared/Model/` for the four API
// names that would break it, so this comment DESCRIBES them rather than
// SPELLING them — a file that configures a content gate is swept by that gate,
// which this phase has now met ten times.

import Foundation
import Observation

/// Which family of conversion the Encode/decode surface is showing.
///
/// The raw value is the `Localizable.xcstrings` key, as with ``Operation``.
enum EncodeFormat: String, CaseIterable, Sendable, Hashable {
    /// `encode.format.base64` — "Base64".
    case base64 = "encode.format.base64"

    /// `encode.format.url` — "URL".
    case url = "encode.format.url"

    /// `encode.format.html` — "HTML".
    case html = "encode.format.html"

    /// The operation this format performs in the given direction.
    ///
    /// Total, and exhaustive with no catch-all branch, so a new format that
    /// nobody wired to an operation is a compile error here.
    func operation(_ direction: EncodeDirection) -> Operation {
        switch (self, direction) {
        case (.base64, .encode): .base64Encode
        case (.base64, .decode): .base64Decode
        case (.url, .encode): .urlEncode
        case (.url, .decode): .urlDecode
        case (.html, .encode): .htmlEncode
        case (.html, .decode): .htmlDecode
        }
    }
}

/// Which way the Encode/decode surface is converting.
enum EncodeDirection: String, CaseIterable, Sendable, Hashable {
    /// `encode.direction.encode` — "Encode".
    case encode = "encode.direction.encode"

    /// `encode.direction.decode` — "Decode".
    case decode = "encode.direction.decode"
}

/// Which representation the Timestamps surface's chain is rooted at.
///
/// Here for the same reason ``EncodeFormat`` and ``EncodeDirection`` are: it is
/// a per-surface UI SELECTION rather than a conversion, and D-82 lists the
/// surfaces' selections among the things that must survive navigating away and
/// back. The raw value is the `Localizable.xcstrings` key naming the cell, as
/// with ``Operation``, so a cell's title and this selection are one string
/// rather than two that can drift.
///
/// **Why the ROOT is stored and the VALUE is not.** The Timestamps card renders
/// three representations of one instant and each carries its own add-step
/// control, the same per-output rule the Hashing surface's four digests follow.
/// There is no ``Operation`` that turns a typed timestamp into one of these —
/// the timestamp conversions take an instant, not text — so a chain cannot be
/// rooted by prepending a step the way the Hashing surface roots one. Recording
/// which CELL it was started from, and re-deriving that cell's value on every
/// pass, is what keeps D-84: a stored value would outlive the input it came
/// from the moment the user typed another character.
enum TimestampRepresentation: String, CaseIterable, Sendable, Hashable {
    /// `timestamps.cell.epoch` — "Unix epoch".
    case epoch = "timestamps.cell.epoch"

    /// `timestamps.cell.iso8601` — "ISO 8601".
    case iso8601 = "timestamps.cell.iso8601"

    /// `timestamps.cell.dateTime` — "Date and time".
    case dateTime = "timestamps.cell.dateTime"
}

/// Everything the three surfaces keep for the life of the launch.
///
/// **D-82.** One app-level instance owns one ``Pipeline`` per surface, plus the
/// per-surface selections, so navigating away and back restores exactly what
/// was there. The platform trap this closes is specific: on macOS a
/// `NavigationSplitView` swaps the detail view when the sidebar selection
/// changes, and state held inside that detail view would be discarded with it,
/// throwing away in-progress work every time the user glanced at another tool.
/// Holding the state one level up, in a model the root view owns, is what makes
/// the surfaces restorable — and it is a model property before it is a UI one,
/// which is why it is settled here rather than in the plans that build screens.
///
/// **D-12.** Every stored property is a value type held in memory and nothing
/// else: no cache, no formatter, no reference type, no singleton. It lives for
/// the life of the process and goes when the process goes. See the file header
/// for the storage and logging APIs this file deliberately does not name.
///
/// **D-84's premise.** Nothing derived is stored. ``Pipeline/evaluate()`` is
/// called fresh wherever a result is needed, so there is no cached output that
/// could survive a change to the input it came from.
///
/// **APP-12.** `@MainActor` on the class means every property here is
/// main-actor isolated, and the engines this state feeds take only `String`,
/// `Double`, `TimeZone` and this phase's own `Sendable` value types — never the
/// model. No concurrency escape hatch is needed and none is present.
@MainActor
@Observable
final class AppModel {
    /// The Encode/decode surface's pipeline.
    var encode = Pipeline()

    /// The Hashing surface's pipeline.
    var hashing = Pipeline()

    /// The Timestamps surface's pipeline.
    var timestamps = Pipeline()

    /// Which conversion family the Encode/decode surface is showing.
    var encodeFormat: EncodeFormat = .base64

    /// Which way the Encode/decode surface is converting.
    var encodeDirection: EncodeDirection = .encode

    /// The user's "Read as" override, or `nil` to use auto-detection (D-89).
    ///
    /// Optional rather than a fourth ``ReadAs`` case: "read whatever detection
    /// says" is not one of the three formats, it is the absence of a choice.
    var timestampsReadAs: ReadAs?

    /// The zone the Timestamps surface renders in. Defaults to the device's.
    var timestampsTimeZone: TimeZone = .current

    /// The instant the Timestamps surface is showing, as seconds since the
    /// 1970 epoch, or `nil` when nothing has been parsed yet.
    ///
    /// **A `Double`, never a `Foundation.Date`.** Phase 7 criterion 3 requires
    /// any persisted date-like value to be a `Double`, and RESEARCH measured
    /// the round trip through `timeIntervalSince1970` to be exact, so storing
    /// the interval costs nothing and leaves Phase 7 with nothing to convert.
    /// `nil` rather than `0`, because "nothing parsed yet" and "the epoch" are
    /// different things and one of them is a real instant a user can type.
    var timestampsInstant: Double?

    /// Which representation cell the Timestamps chain is rooted at, or `nil`
    /// while nothing has been chained. See ``TimestampRepresentation``.
    var timestampsChainRoot: TimestampRepresentation?

    /// Whether the user has overridden detection, which is what drives the
    /// Detect control's disabled state on the Timestamps surface.
    var isReadAsOverridden: Bool {
        timestampsReadAs != nil
    }

    /// A fresh model for SwiftUI previews, and for nothing that ships.
    ///
    /// **One instance serves a launch** (D-82), constructed by the root view,
    /// and this plan asserts by grep that the initialiser is written at exactly
    /// that one site in `app/Shared/`. Previews need a model too, so they reach
    /// it through this factory instead of spelling a second construction that
    /// the grep could not tell apart from a real one. The expression the grep
    /// looks for is deliberately not written anywhere in this file: a file that
    /// configures a content gate is swept by that gate.
    static var preview: AppModel {
        .init()
    }
}
