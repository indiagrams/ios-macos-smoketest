// SettingsKey — the complete, enumerable set of keys this app persists
// (D-95, D-96, D-97, APP-13).
//
// Its own file for the reason PipelineTests is split across four: AppModel.swift
// crossed SwiftLint's 400-line budget when the persistence seam landed, and
// `--strict` promotes that warning threshold to the real limit. The budget is
// not loosened. The split is also the honest one — this type is the POPULATION
// two separate checks iterate, and AppModel is the thing that reads and writes
// it, so they are two responsibilities rather than one long file.
//
// Not a view, no UI framework, nothing imported at all: the raw values are
// plain strings and the conformances are stdlib.

/// The complete set of keys this app persists (D-95, D-96, D-97).
///
/// **One enumerable population, declared in one place.** `allCases` is what
/// D-96's `Date` ban and criterion 4's "and nothing it does not" both iterate.
/// The two SwiftUI property wrappers that read and write the settings store
/// per view are rejected by D-97 and neither appears anywhere in this app. The
/// first would define that population as "whatever any view happens to
/// declare", which is the *correct check pointed at the wrong population*
/// anti-pattern pre-built; the second is additionally scene-scoped and
/// system-managed, which would make criterion 3 stop being assertable. Their
/// names are not spelled here for the reason the file header gives, and
/// because 07-05's own acceptance gate greps this file for them.
///
/// **D-96's type-system half.** Every value written under one of these keys is
/// a `String` — three `String`-backed enum raw values and a time-zone
/// identifier — and ``AppModel/write(_:forKey:)`` takes `String?` and nothing
/// else. So "no persisted key ever holds a `Date`" is a fact about the write
/// path's types before it is a runtime assertion. The runtime assertion in
/// `PipelineTests.noPersistedKeyEverHoldsADate` is the belt to those braces,
/// and it exists because a clause with no subject is precisely what this
/// project refuses to let pass vacuously.
///
/// The raw values carry a `settings.` prefix so that the launch-argument domain
/// — which outranks the persistent one — can pin any of them from a UI test
/// without touching disk (07-RESEARCH §7.4).
enum SettingsKey: String, CaseIterable, Sendable {
    /// The last-used surface, as a ``Destination`` raw value.
    case selection = "settings.selection"

    /// The Encode/decode family, as an ``EncodeFormat`` raw value.
    case encodeFormat = "settings.encodeFormat"

    /// The Encode/decode direction, as an ``EncodeDirection`` raw value.
    case encodeDirection = "settings.encodeDirection"

    /// The Timestamps "Read as" override, as a `ReadAs` raw value. The key is
    /// REMOVED rather than written when the user has made no override: the
    /// absence of a choice is not one of the three formats (D-89).
    case timestampsReadAs = "settings.timestampsReadAs"

    /// The Timestamps zone, as a `TimeZone` identifier.
    case timestampsTimeZone = "settings.timestampsTimeZone"
}
