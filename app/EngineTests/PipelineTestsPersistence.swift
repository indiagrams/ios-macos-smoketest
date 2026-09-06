// Persistence — APP-13, D-95, D-96, D-97, D-98, and AR-03 as an assertion.
//
// An `extension` of `PipelineTests` rather than a suite of its own, so that
// `-only-testing:AppMacOSTests/PipelineTests` selects these cases too. It is
// the fourth such extension (PipelineFoldTests, PipelineMutatorTests and
// PipelineTestsAppModel are the others) — the established route when a file
// approaches SwiftLint's 400-line budget, which `--strict` promotes from a
// warning threshold to the real limit.
//
// EVERY CASE BUILDS ITS OWN STORE, AND THE STANDARD DOMAIN IS NEVER NAMED.
// Both unit-test targets are host-based (`TEST_HOST` is set in `project.yml`
// and `Project.swift` alike), so the bundle loads into the shipping app and a
// test that wrote the standard domain would write the REAL app's settings on
// the developer's Mac and on every CI simulator, then leak into the next test
// and the next run (07-RESEARCH §12, the test-pollution row). Every case here
// goes through ``PipelineTests/withSettingsStore(_:)``, which builds two
// `UserDefaults(suiteName:)` stores around fresh `UUID`s — the one under test
// and an empty reference — and removes both persistent domains on the way out.
//
// THE REFERENCE STORE IS WHY NO FALLBACK IS COMPARED AGAINST A LITERAL. D-98's
// cases assert that an unresolvable value hydrates to the DECLARED default, and
// the declared default is whatever a model built on an empty store has. Reading
// the runner's own value instead — `TimeZone.current` being the tempting one —
// is exactly how CR-02 stayed green on this machine and on CI while the app was
// wrong.
//
// `AppModel` is `@MainActor`, so every case is `@MainActor`. These targets are
// Swift 6 with `-strict-concurrency=complete`, which means a case that got the
// isolation wrong fails to COMPILE rather than at run time.
//
// EVERY ASSERTION IS NON-TRAPPING, per the suite header: no array subscript, no
// force unwrap, `first`/`last`/`dropFirst` compared as Optionals. These bundles
// are host-based, so a Swift runtime trap kills the host, aborts the run and
// posts a crash dialog on the developer's desktop.

import Foundation
import Testing

extension PipelineTests {
    // MARK: - The per-test store

    /// The prefix every throwaway settings suite in this file is named under.
    ///
    /// Spelled once so a leaked domain is greppable in `defaults domains`
    /// output and attributable to this file.
    static let settingsSuitePrefix = "com.indiagram.shipkitpipes.settingstests."

    /// A zone that is neither the device's nor any other case's, so a value
    /// that survived by accident cannot be mistaken for one that round-tripped.
    static let persistedZoneIdentifier = "Asia/Kolkata"

    /// Runs `body` against a defaults suite nothing else shares, plus an empty
    /// reference suite, and removes both persistent domains afterwards.
    ///
    /// Swift Testing has no `tearDown`, so the teardown is a `defer` here
    /// rather than a suite hook — which also means it runs on the early-return
    /// path a recorded issue takes.
    @MainActor
    static func withSettingsStore(_ body: @MainActor (UserDefaults, String, UserDefaults) -> Void) {
        let name = "\(settingsSuitePrefix)\(UUID().uuidString)"
        let referenceName = "\(settingsSuitePrefix)reference.\(UUID().uuidString)"
        guard let store = UserDefaults(suiteName: name),
              let reference = UserDefaults(suiteName: referenceName)
        else {
            Issue.record("a per-test suite store could not be created (\(name) / \(referenceName))")
            return
        }
        defer {
            store.removePersistentDomain(forName: name)
            reference.removePersistentDomain(forName: referenceName)
        }
        body(store, name, reference)
    }

    // MARK: - D-95 — the persisted set is exactly five keys

    /// The membership of the persisted key set, compared as a SET.
    ///
    /// A sixth key is a widening of what this app writes to the user's disk,
    /// and that must fail a test rather than depend on a review comment. The
    /// expected side is spelled literally on purpose: deriving it from
    /// ``SettingsKey`` itself would make the assertion true by construction.
    @MainActor
    @Test
    func theSettingsKeysAreExactlyTheFiveD95Names() {
        let expected: Set = [
            "settings.selection",
            "settings.encodeFormat",
            "settings.encodeDirection",
            "settings.timestampsReadAs",
            "settings.timestampsTimeZone"
        ]
        let actual = Set(SettingsKey.allCases.map(\.rawValue))
        #expect(actual == expected, "the persisted key set is not D-95's five: \(actual.sorted())")
    }

    // MARK: - D-95 / APP-13 — the round trip

    /// Every setting written by one model is read back by the next one built
    /// against the same store.
    ///
    /// The non-emptiness assertion before the loop is not decoration: an
    /// iteration over an empty collection asserts nothing and prints success,
    /// and this repository has shipped that defect.
    @MainActor
    @Test
    func everySettingSurvivesIntoASecondModelOnTheSameStore() {
        Self.withSettingsStore { store, _, _ in
            #expect(SettingsKey.allCases.isEmpty == false, "an empty key set would make every loop below vacuous")

            let zone = TimeZone(identifier: Self.persistedZoneIdentifier)
            #expect(zone != nil, "the fixture zone identifier is not one this platform knows")

            let first = AppModel(defaults: store)
            first.selection = .hashing
            first.encodeFormat = .html
            first.encodeDirection = .decode
            first.timestampsReadAs = .iso8601
            if let zone {
                first.timestampsTimeZone = zone
            }

            for key in SettingsKey.allCases {
                #expect(store.object(forKey: key.rawValue) != nil, "nothing was persisted for \(key.rawValue)")
            }

            let second = AppModel(defaults: store)
            #expect(second.selection == .hashing, "the last-used surface did not survive")
            #expect(second.encodeFormat == .html, "the encode format did not survive")
            #expect(second.encodeDirection == .decode, "the encode direction did not survive")
            #expect(second.timestampsReadAs == .iso8601, "the read-as override did not survive")
            #expect(second.timestampsTimeZone.identifier == Self.persistedZoneIdentifier, "the zone did not survive")
        }
    }

    /// The absence of a choice is a value too: clearing the read-as override
    /// must not resurrect the previous one on the next launch.
    @MainActor
    @Test
    func clearingTheReadAsOverrideSurvivesAsAnAbsence() {
        Self.withSettingsStore { store, _, _ in
            let first = AppModel(defaults: store)
            first.timestampsReadAs = .localTime
            first.timestampsReadAs = nil
            let second = AppModel(defaults: store)
            #expect(second.timestampsReadAs == nil, "a cleared override came back")
            #expect(second.isReadAsOverridden == false, "the Detect control would render disabled on a cold launch")
        }
    }

    // MARK: - D-96 — no persisted key ever holds a Date

    /// The runtime half of D-96. The type-system half is that every persisted
    /// value is a `String` by construction; this is the belt to those braces.
    ///
    /// The message names the offending key, because a bare non-zero exit does
    /// not distinguish the ban firing from the suite falling over.
    @MainActor
    @Test
    func noPersistedKeyEverHoldsADate() {
        Self.withSettingsStore { store, _, _ in
            #expect(SettingsKey.allCases.isEmpty == false, "an empty key set would make the ban below vacuous")

            let model = AppModel(defaults: store)
            model.selection = .timestamps
            model.encodeFormat = .url
            model.encodeDirection = .decode
            model.timestampsReadAs = .unixEpoch
            if let zone = TimeZone(identifier: Self.persistedZoneIdentifier) {
                model.timestampsTimeZone = zone
            }

            for key in SettingsKey.allCases {
                let stored = store.object(forKey: key.rawValue)
                let isDate = stored is Date || stored is NSDate
                #expect(isDate == false, "D-96: the persisted key \(key.rawValue) holds a Date")
            }
        }
    }

    // MARK: - D-98 — an unresolvable persisted value is discarded

    /// A destination raw value matching no case hydrates to the declared
    /// default, and the model's selection is always one of the three.
    @MainActor
    @Test
    func anUnknownDestinationHydratesToTheDeclaredDefault() {
        Self.withSettingsStore { store, _, reference in
            store.set("shell.destination.nope", forKey: SettingsKey.selection.rawValue)
            let model = AppModel(defaults: store)
            let clean = AppModel(defaults: reference)
            #expect(Destination.allCases.contains(model.selection), "the selection matches no option — CR-02's class, made permanent")
            #expect(model.selection == clean.selection, "the fallback is not the declared default")
        }
    }

    /// A time-zone identifier the platform rejects hydrates to the declared
    /// default.
    ///
    /// Driven by INJECTION into the store, and the expected value comes from a
    /// model built on the empty reference store rather than from the runner's
    /// own zone — see the file header.
    @MainActor
    @Test
    func aBogusTimeZoneIdentifierHydratesToTheDeclaredDefault() {
        Self.withSettingsStore { store, _, reference in
            #expect(TimeZone(identifier: "Mars/Olympus") == nil, "the fixture identifier is one this platform accepts")
            store.set("Mars/Olympus", forKey: SettingsKey.timestampsTimeZone.rawValue)
            let model = AppModel(defaults: store)
            #expect(model.timestampsTimeZone.identifier.isEmpty == false, "a blank zone is a blank control, which D-98 forbids")
            let clean = AppModel(defaults: reference)
            #expect(model.timestampsTimeZone == clean.timestampsTimeZone, "the fallback is not the declared default")
        }
    }

    /// A wrong-typed value, asserted through the FAILABLE INITIALISER.
    ///
    /// `string(forKey:)` COERCES an `Int` to a `String` — `42` comes back as
    /// `"42"`, measured in 07-RESEARCH §7.4 — so a case expecting the read to
    /// return `nil` passes for the wrong reason and would pass on a broken app.
    /// The thing that actually rejects the value is `Destination(rawValue:)`.
    @MainActor
    @Test
    func aWrongTypedSelectionIsRejectedByTheFailableInitialiser() {
        Self.withSettingsStore { store, _, reference in
            store.set(42, forKey: SettingsKey.selection.rawValue)
            let raw = store.string(forKey: SettingsKey.selection.rawValue)
            #expect(raw == "42", "the coercion 07-RESEARCH measured has changed; re-measure before trusting this case")
            #expect(Destination(rawValue: raw ?? "") == nil, "the failable initialiser accepted a wrong-typed value")
            let model = AppModel(defaults: store)
            let clean = AppModel(defaults: reference)
            #expect(model.selection == clean.selection, "a wrong-typed value reached the model")
        }
    }

    /// A store whose value for every key is an array rather than a string.
    /// Hydration keeps the declared defaults and does not trap.
    @MainActor
    @Test
    func aCorruptArrayValuedStoreHydratesToTheDeclaredDefaults() {
        Self.withSettingsStore { store, _, reference in
            for key in SettingsKey.allCases {
                store.set(["a", "b"], forKey: key.rawValue)
            }
            let model = AppModel(defaults: store)
            let clean = AppModel(defaults: reference)
            #expect(model.selection == clean.selection, "a corrupt destination reached the model")
            #expect(model.encodeFormat == clean.encodeFormat, "a corrupt format reached the model")
            #expect(model.encodeDirection == clean.encodeDirection, "a corrupt direction reached the model")
            #expect(model.timestampsReadAs == clean.timestampsReadAs, "a corrupt read-as reached the model")
            #expect(model.timestampsTimeZone == clean.timestampsTimeZone, "a corrupt zone reached the model")
        }
    }

    // MARK: - D-95 / D-12 / AR-03 — and nothing it does not

    /// After every surface has been given a pipeline, an input and an
    /// evaluation, the store holds no key outside ``SettingsKey/allCases`` and
    /// no persisted value contains the pasted text.
    ///
    /// This is AR-03 — "pasted secrets are never persisted" — as an assertion
    /// rather than a promise.
    @MainActor
    @Test
    func nothingOutsideTheSettingsKeysIsEverPersisted() {
        Self.withSettingsStore { store, name, _ in
            let secret = "sk-live-do-not-persist-me"
            let model = AppModel(defaults: store)
            model.selection = .hashing

            model.encode.input = secret
            model.encode.steps = Self.steps(.base64Encode)
            _ = model.encode.evaluate()
            model.hashing.input = secret
            model.hashing.steps = Self.steps(.sha256)
            _ = model.hashing.evaluate()
            model.timestamps.input = secret
            model.timestamps.steps = Self.steps(.md5)
            _ = model.timestamps.evaluate()

            guard let domain = store.persistentDomain(forName: name) else {
                Issue.record("the suite's persistent domain could not be read, so this case looked at nothing")
                return
            }
            #expect(domain.keys.contains(SettingsKey.selection.rawValue), "the one setting written is absent, so the sweep is vacuous")

            let allowed = Set(SettingsKey.allCases.map(\.rawValue))
            let extra = Set(domain.keys).subtracting(allowed)
            #expect(extra.isEmpty, "keys outside the persisted set reached the user's disk: \(extra.sorted())")

            for (key, value) in domain {
                #expect(String(describing: value).contains(secret) == false, "the pasted input reached the store under \(key)")
            }
        }
    }
}
