// AppModel — the one app-level observable model (D-82, D-12, APP-12).
//
// NOT A VIEW, and it imports no UI framework. Foundation for `TimeZone`, and
// Observation for the macro. The root view constructs exactly one of these, as
// a single `@State`-owned property, and hands surfaces the properties they own;
// nothing here is static, shared or global. Plan 06-13 asserts that "exactly
// one" by grepping `app/Shared/` for the initialiser expression, so this
// paragraph DESCRIBES it and no longer spells it — the fifteenth time this
// phase has met a file that configures a content gate being swept by it, and
// the second time the offending text was prose that had been correct until the
// gate existed.
//
// WHY THE SELECTION ENUMS LIVE HERE. `EncodeFormat` and `EncodeDirection` are
// per-surface UI selections, not conversions, so they are not ``Operation``
// cases — but the three-by-two product of them IS exactly the six codec
// operations, and `EncodeFormat.operation(_:)` below is the total mapping that
// says so. `PipelineTests.theEncodeSelectionsCoverExactlyTheSixCodecOperations`
// asserts the product rather than a count, so a format added without an
// operation, or two selections collapsing onto one operation, fails there.
//
// D-12 AND AR-03, NARROWED BY APP-13 AND STILL STRUCTURAL. This paragraph used
// to say that nothing here is written to the persistent settings store. As of
// Phase 7 that is false and the claim is REWRITTEN rather than appended to:
// this file writes exactly five keys — the last-used surface and four control
// values — enumerated once by ``SettingsKey`` and by nothing else. What is
// still true, and is the whole mechanism behind the app's "we never stored your
// API key" claim, is everything that is NOT written: no input, no output, no
// pipeline shape, nothing to the file system, nothing to any log. There is no
// code here that could.
// `PipelineTests.nothingOutsideTheSettingsKeysIsEverPersisted` asserts the
// narrowed claim over the store's own persistent domain instead of restating
// it, which is what keeps this paragraph from going stale the way its
// predecessor did.
//
// THE STORAGE API'S NAME IS STILL NOT SPELLED IN THIS COMMENT, and the reason
// has changed. Measured 2026-09-05: plan 06-09's acceptance-criteria grep of
// `app/Shared/Model/` does not run in `test/`, `tools/`, `ci/`,
// `.github/workflows/` or `lefthook.yml` — it was a plan-time check and it is
// gone. What DOES run is `test/privacy_manifest_test.rb`, whose forward
// direction sweeps this exact file for that name and must be satisfied by the
// CODE below rather than by prose. It strips comments before counting, so a
// mention up here would be invisible to it today; keeping the name out of the
// comment costs nothing and removes this file's dependence on that stripper
// staying correct. The gate's own subject file, `PrivacyInfo.xcprivacy`, was
// de-spelled in the same commit for the same reason.

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
/// **D-12, as narrowed by APP-13.** Every property the SURFACES read and write
/// is still a value type held in memory and nothing else: no cache, no
/// formatter, no singleton. Two things changed in Phase 7 and both are stated
/// rather than glossed. There is now exactly one reference-type stored
/// property, ``AppModel/defaults``, and it is the persistence seam itself; and
/// five of the value-type properties are durable across a quit rather than
/// dying with the process. The pipelines, their inputs and their outputs are
/// not among the five and still go when the process goes.
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
    // MARK: - The one persistence seam (D-97)

    /// The store the five settings are written to and hydrated from.
    ///
    /// **An injected INSTANCE and not a static** — 07-RESEARCH §7.2 shape B,
    /// type-checked at `arm64-apple-macos14.0` under `-swift-version 6
    /// -strict-concurrency=complete` with zero diagnostics. Shape A, the
    /// obvious `nonisolated static let store = …standard`, is three hard errors
    /// inside a `@MainActor @Observable final class`, the first of them *"static
    /// property 'store' is not concurrency-safe because non-'Sendable' type
    /// … may have shared mutable state"*. The compiler's own note suggests
    /// `@MainActor`; the internet suggests the unsafe-nonisolated annotation.
    /// **That annotation and the unchecked conformance are both banned by
    /// `PROJECT.md`, by ROADMAP Phase 6 criterion 5 and by APP-12, and
    /// `test/app_offline_test.rb` O7 scans comment-stripped Swift for both on
    /// every PR.** Isolating the property through the class raises none of it.
    /// `app/Shared/Engine/TimestampCodec.swift:3..27` is the shipped file that
    /// met the identical error and recorded the same conclusion.
    ///
    /// Injection is not only about the compiler. Both unit-test bundles are
    /// host-based (`TEST_HOST` is set in both generator manifests), so a test
    /// that reached the standard domain would write the shipping app's REAL
    /// settings on the developer's Mac and on every CI simulator, and leak into
    /// the next test and the next run. Every case in
    /// `PipelineTestsPersistence.swift` points this at a throwaway suite.
    private let defaults: UserDefaults

    /// Builds the model and restores what the last launch left (APP-13, D-95).
    ///
    /// The parameter is DEFAULTED, so `RootView`'s single construction site
    /// compiles unchanged and plan 06-13's "constructed exactly once" grep —
    /// which looks for the bare initialiser expression — still finds exactly
    /// one occurrence.
    ///
    /// **Hydration ordering, decided rather than discovered.** ``hydrate()``
    /// runs after every stored property is initialised, so each assignment it
    /// makes DOES fire that property's `didSet` and writes the value straight
    /// back. That is accepted rather than worked around: the write is
    /// idempotent, and it reaches only keys that already resolved — an absent,
    /// unresolvable or wrong-typed key produces no assignment at all, so a
    /// fresh store stays empty and a corrupt value is left exactly as found for
    /// the D-98 cases to observe. An `isHydrating` flag would buy nothing but a
    /// second piece of mutable state on an `@Observable` class.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hydrate()
    }

    // MARK: - Per-surface state (D-82)

    /// The Encode/decode surface's pipeline.
    var encode = Pipeline()

    /// The Hashing surface's pipeline.
    var hashing = Pipeline()

    /// The Timestamps surface's pipeline.
    var timestamps = Pipeline()

    // MARK: - The five persisted settings (D-95)

    /// The last-used surface, restored on the next launch (APP-13).
    ///
    /// **It lives here and not in `RootView`'s `@State`** (D-97). The reason is
    /// the enumerable population: D-96's ban and criterion 4's "and nothing it
    /// does not" both need to iterate every persisted key, and a per-view
    /// storage wrapper would define that population as whatever a view happened
    /// to declare. Plan 07-07 binds the two shells to this property; until then
    /// it is written and restored but not yet read by a container, which is why
    /// this plan claims no requirement complete.
    var selection: Destination = .encode {
        didSet { write(selection.rawValue, forKey: .selection) }
    }

    /// Which conversion family the Encode/decode surface is showing.
    var encodeFormat: EncodeFormat = .base64 {
        didSet { write(encodeFormat.rawValue, forKey: .encodeFormat) }
    }

    /// Which way the Encode/decode surface is converting.
    var encodeDirection: EncodeDirection = .encode {
        didSet { write(encodeDirection.rawValue, forKey: .encodeDirection) }
    }

    /// The user's "Read as" override, or `nil` to use auto-detection (D-89).
    ///
    /// Optional rather than a fourth ``ReadAs`` case: "read whatever detection
    /// says" is not one of the three formats, it is the absence of a choice.
    /// The absence persists AS an absence — the key is removed, not written
    /// with a sentinel — so a cleared override does not come back next launch.
    var timestampsReadAs: ReadAs? {
        didSet { write(timestampsReadAs?.rawValue, forKey: .timestampsReadAs) }
    }

    /// The zone the Timestamps surface renders in. Defaults to the device's.
    var timestampsTimeZone: TimeZone = .current {
        didSet { write(timestampsTimeZone.identifier, forKey: .timestampsTimeZone) }
    }

    // MARK: - Per-launch state that is deliberately NOT persisted

    /// Which representation cell the Timestamps chain is rooted at, or `nil`
    /// while nothing has been chained. See ``TimestampRepresentation``.
    ///
    /// Not a ``SettingsKey``. It is part of a chain in progress, and D-95 keeps
    /// pipeline shape out of the store along with every input and output.
    var timestampsChainRoot: TimestampRepresentation?

    /// Whether the user has overridden detection, which is what drives the
    /// Detect control's disabled state on the Timestamps surface.
    var isReadAsOverridden: Bool {
        timestampsReadAs != nil
    }

    // MARK: - The write path and the read path

    /// Writes one setting, or REMOVES the key when the setting is an absence.
    ///
    /// **The parameter is `String?` and deliberately not generic.** A
    /// `some LosslessStringConvertible` seam would compile and would widen the
    /// write path to types this app has decided not to persist; `String?` is
    /// D-96's type-system half spelled as a signature, and it is the reason
    /// "no persisted key ever holds a `Date`" is a property of the code rather
    /// than only of a test. Every caller passes an enum raw value or a
    /// time-zone identifier, all of which are already `String`.
    ///
    /// The key is a ``SettingsKey`` and never a bare string, so a key that is
    /// written but absent from `allCases` is not expressible.
    private func write(_ value: String?, forKey key: SettingsKey) {
        if let value {
            defaults.set(value, forKey: key.rawValue)
        } else {
            defaults.removeObject(forKey: key.rawValue)
        }
    }

    /// Restores the five settings, discarding anything that does not resolve.
    ///
    /// **D-98.** The store is attacker-or-corruption-influenced input on the
    /// next launch and it outlives the code that wrote it, so every read goes
    /// through a FAILABLE initialiser and the declared default is kept when it
    /// returns `nil`. An unknown destination, a bogus zone identifier, a
    /// wrong-typed value and a corrupt array-valued key therefore all resolve
    /// to a default — never to a crash, and never to a blank control. That last
    /// clause is CR-02's exact class, which persistence would otherwise have
    /// made permanent instead of merely surviving until quit.
    ///
    /// Note what does the rejecting. `string(forKey:)` returns `nil` for an
    /// array-valued key but COERCES an `Int` to its decimal string — `42` comes
    /// back as `"42"`, measured in 07-RESEARCH §7.4 — so for a wrong-typed
    /// value it is the failable initialiser underneath, and never the read,
    /// that refuses it.
    private func hydrate() {
        if let value = restored(.selection, Destination.init(rawValue:)) {
            selection = value
        }
        if let value = restored(.encodeFormat, EncodeFormat.init(rawValue:)) {
            encodeFormat = value
        }
        if let value = restored(.encodeDirection, EncodeDirection.init(rawValue:)) {
            encodeDirection = value
        }
        if let value = restored(.timestampsReadAs, ReadAs.init(rawValue:)) {
            timestampsReadAs = value
        }
        if let value = restored(.timestampsTimeZone, TimeZone.init(identifier:)) {
            timestampsTimeZone = value
        }
    }

    /// The stored text for `key`, put through `make`, or `nil` when either the
    /// read or the resolution declines it.
    ///
    /// Passing the FAILABLE INITIALISER itself, rather than a resolved value,
    /// is what makes "the declared default is kept" one rule applied five times
    /// instead of five separately-written branches that could each drift. There
    /// is deliberately no `else` anywhere: a value that does not resolve leaves
    /// the property at the default it was declared with, and leaves the stored
    /// text exactly as found.
    private func restored<Value>(_ key: SettingsKey, _ make: (String) -> Value?) -> Value? {
        defaults.string(forKey: key.rawValue).flatMap(make)
    }

    // MARK: - Previews

    /// A fresh model for SwiftUI previews, and for nothing that ships.
    ///
    /// **One instance serves a launch** (D-82), constructed by the root view,
    /// and plan 06-13 asserts by grep that the initialiser is written at exactly
    /// that one site in `app/Shared/`. Previews need a model too, so they reach
    /// it through this factory instead of spelling a second construction that
    /// the grep could not tell apart from a real one. The expression the grep
    /// looks for is deliberately not written anywhere in this file: a file that
    /// configures a content gate is swept by that gate.
    ///
    /// **The store is a throwaway suite** as of Phase 7. With hydration in the
    /// initialiser, a preview built against the default parameter would read —
    /// and, the first time a canvas moved a control, write — the shipped app's
    /// real settings on the developer's Mac. The `??` branch is unreachable:
    /// `UserDefaults(suiteName:)` fails only for `nil`, the app's own bundle
    /// identifier and the global domain, and this constant is none of the
    /// three.
    static var preview: AppModel {
        AppModel(defaults: UserDefaults(suiteName: previewSuiteName) ?? .standard)
    }

    /// The suite name ``preview`` uses. Distinct from the app's bundle
    /// identifier, so previews and the shipped app never share a domain.
    private static let previewSuiteName = "com.indiagram.shipkitpipes.previews"
}
