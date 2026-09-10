import XCTest

// EVERY UI TEST STATES ITS OWN LAUNCH STATE, BECAUSE PERSISTENCE MADE LAUNCH STATE A SHARED
// RESOURCE. Before 07-05 the app had no durable state and every launch was identical. Now
// `AppModel.selection` and four other settings survive termination, so a test that leaves the
// app on Hashing changes the NEXT test's launch state — in the same run, and across runs on
// the same simulator, and in whichever order the runner happened to pick. 07-RESEARCH Pitfall 6
// names this; criterion 5's "no prior interaction" clause is the thing it would silently
// falsify, since a green run would then be evidence about test ORDERING rather than about the app.
//
// THE MECHANISM IS `NSArgumentDomain`, AND IT WRITES NOTHING TO DISK. `UserDefaults` reads the
// process's own arguments automatically, with no shipped code to enable it, and that domain
// OUTRANKS the persistent one. Measured on a real binary that had just written a different value
// to disk (07-RESEARCH §7.4): `./probe` answered `persisted=hashing`, and
// `./probe -settings.selection shell.destination.encode` answered `encode` from the same store.
// So a pinned test neither needs the app deleted between cases nor a reset control added to
// shipped code — and it leaves no residue for the next case, which a disk write would.
//
// CORRECTED 2026-09-06, AFTER 07-11 MEASURED IT THREE WAYS. The sentence above is preserved and
// it is true of the ARGUMENT DOMAIN and FALSE OF THE APP. `AppModel.hydrate()` runs inside
// `init`; `RootView` declares `@State private var model = AppModel()`, whose initialiser
// expression is re-evaluated on EVERY render pass; and each throwaway model reads the
// HIGHEST-RANKING defaults domain and writes what it read straight back out through `didSet`.
// With a pin in place that highest-ranking domain is `NSArgumentDomain`, so every re-render
// writes the PINNED value into the app's own persistent store, over whatever the user has since
// chosen. Measured on iOS 17.5 (07-11, `evidence/07-11-launch-layout.txt`), reading the app's own
// plist: pinned + a tab tap to Timestamps + 8 s alive answered `encode`; pinned + the same tap +
// terminate answered `encode`; the SAME tap after an UNPINNED launch answered `timestamps`.
//
// TWO CONSEQUENCES, BOTH LOAD-BEARING. A pinned launch DOES leave residue — in the persistent
// domain, written by the app rather than by the pin. And a `LaunchState`-pinned launch CANNOT
// prove a persistence claim at all: it silently reverts the very change such a test is about, so
// the test measures the pin and reports it as the app. Criterion 3's relaunch case in
// `LaunchLayoutTests` therefore pins NOTHING on either launch and drives instead, which
// `onlySurface(_:)` below already names as the stronger of the two guarantees. The underlying
// `@State` re-evaluation is NOT a defect this note authorises anyone to go fix: changing it is a
// design change, and it is recorded here so the next reader knows the shape rather than
// rediscovering it from a green run that measured nothing.
//
// THE SHIPPED PRECEDENT IS `app/Shared/App.swift:5..23`, `-UITestColorScheme`, reused rather than
// re-argued: real users never pass these, so they are a no-op outside a UI test.
//
// TWO FILES, NOT ONE SHARED ONE. `app/MacOSUITests/LaunchState.swift` is this file's twin, for the
// reason the `ShellTests` pair already follows: the two platforms have two different containers,
// so the tests that consume this differ even where the pinning does not. The two are kept honest
// by a gate that compares the extracted key SETS rather than by anyone reading both.
//
// THE VALUES ARE LITERALS, AND THAT IS FORCED. UI test targets compile exactly one file out of
// `app/Shared/` — `AccessibilityIdentifiers.swift`, listed twice in `app/project.yml` — and run in
// a separate process that cannot link the app binary, so `Destination`, `EncodeFormat`,
// `EncodeDirection` and `ReadAs` are all out of reach here. Their raw values are therefore spelled
// by hand below, and `evidence/07-07-verify-launchstate.rb` reads the app's own enums and asserts
// that every literal in this file still resolves against one of them.
//
// SWIFT 5.9, LIKE EVERY FILE IN THIS TARGET (C-25). `SWIFT_VERSION: "5.9"` /
// `SWIFT_STRICT_CONCURRENCY: minimal`, pinned because fastlane's `SnapshotHelper.swift` predates
// Swift 6. No Swift 6 isolation syntax appears here and no concurrency of any kind is used.

/// The launch state a UI test pins, as `NSArgumentDomain` arguments.
///
/// A pinning is a flat `[String]` of alternating key and value, exactly the shape
/// `XCUIApplication.launchArguments` takes. Compose it with `+=` rather than `=` so a pinning and
/// the appearance argument the visible-string sweep already passes can coexist on one launch.
enum LaunchState {
    // MARK: - The five keys, one per SettingsKey raw value

    /// `SettingsKey.selection` — the last-used surface (APP-13).
    static let selectionKey = "-settings.selection"

    /// `SettingsKey.encodeFormat` — which conversion family Encode/decode is showing.
    static let encodeFormatKey = "-settings.encodeFormat"

    /// `SettingsKey.encodeDirection` — which way Encode/decode is converting.
    static let encodeDirectionKey = "-settings.encodeDirection"

    /// `SettingsKey.timestampsReadAs` — the user's "Read as" override.
    static let timestampsReadAsKey = "-settings.timestampsReadAs"

    /// `SettingsKey.timestampsTimeZone` — the zone the Timestamps surface renders in.
    static let timestampsTimeZoneKey = "-settings.timestampsTimeZone"

    // MARK: - The three destinations, by `Destination` raw value

    /// `Destination.encode`.
    static let encodeDestination = "shell.destination.encode"

    /// `Destination.hashing`.
    static let hashingDestination = "shell.destination.hashing"

    /// `Destination.timestamps`.
    static let timestampsDestination = "shell.destination.timestamps"

    // MARK: - The rest of the pinned state, chosen to be boring and stable

    /// `EncodeFormat.base64`, the app's own declared default.
    static let base64Format = "encode.format.base64"

    /// `EncodeDirection.encode`, the app's own declared default.
    static let forwardDirection = "encode.direction.encode"

    /// `ReadAs.unixEpoch`. The raw values of that enum are its CASE NAMES and are not catalog
    /// keys — the visible strings live in the view layer, which the engine must not import.
    static let epochReadAs = "unixEpoch"

    /// A zone with no daylight-saving rule and no locale, so a pinned Timestamps assertion reads
    /// the same on a developer's Mac in Los Angeles and on a GitHub runner in UTC.
    static let fixedTimeZone = "UTC"

    // MARK: - A complete pinning

    /// All five settings pinned at once, with the destination chosen by the caller.
    ///
    /// **All five, and a subset needs a reason.** Pinning only the key a test happens to assert on
    /// leaves the other four reading whatever the previous case persisted, which is the same
    /// order-dependence in a smaller box. The population this pins is `SettingsKey.allCases`, and
    /// the gate that guards it counts the keys rather than trusting this sentence.
    ///
    /// The one admissible reason for a subset is a test that DRIVES the unpinned keys itself, which
    /// is a stronger guarantee than pinning them; ``onlySurface(_:)`` exists for exactly that case
    /// and states the reason at its own call sites.
    static func showing(_ destination: String) -> [String] {
        [
            selectionKey, destination,
            encodeFormatKey, base64Format,
            encodeDirectionKey, forwardDirection,
            timestampsReadAsKey, epochReadAs,
            timestampsTimeZoneKey, fixedTimeZone
        ]
    }

    /// The launch SURFACE alone, and deliberately none of the other four keys.
    ///
    /// **Only for a test whose population must stay maximal.** The visible-string sweep harvests
    /// every string the app renders and asserts a FLOOR on the distinct count; pinning a setting
    /// can only ever REMOVE renderings from that population, so the sweep pins the minimum it
    /// needs to reach its subject — which surface opens — and nothing else. It then drives the
    /// other four itself: both directions, all three encode formats, all three read-as segments
    /// and the detect control, harvesting after each, which covers those keys more completely than
    /// a pin would. `timestampsTimeZone` is the one key nothing drives, and it is left exactly as
    /// 06-16 measured the floor against.
    static func onlySurface(_ destination: String) -> [String] {
        [selectionKey, destination]
    }

    // MARK: - D-98's four corruption cases, each one launch argument

    /// A destination raw value no case of `Destination` carries.
    ///
    /// Drives the failable-initialiser fallback: the read succeeds, `Destination(rawValue:)`
    /// returns nil, and `hydrate()` keeps the declared default.
    static let destinationThatDoesNotResolve = [selectionKey, "shell.destination.nope"]

    /// A time-zone identifier the system rejects.
    ///
    /// `TimeZone(identifier: "Mars/Olympus")` returns nil [measured], so the `?? .current`
    /// fallback in the model has a real subject rather than a hypothetical one.
    static let timeZoneTheSystemRejects = [timestampsTimeZoneKey, "Mars/Olympus"]

    /// An integer where a string belongs.
    ///
    /// **The expectation this pinning drives is NOT that the read returns nil.** The argument
    /// domain parses `42` as a number, and `string(forKey:)` COERCES it back to `"42"` — measured,
    /// 07-RESEARCH §7.4 and Pitfall 7. So a test asserting `string(forKey:) == nil` for this
    /// pinning passes for the wrong reason and would keep passing on a broken app. Assert through
    /// the failable enum initialiser instead: `"42"` is not a `Destination` raw value, so the
    /// observable outcome is the declared default, and that is what a test must measure.
    static let integerWhereAStringBelongs = [selectionKey, "42"]

    /// An old-style-plist array where a string belongs.
    ///
    /// The argument domain parses `(a,b)` into an `NSArray`, and unlike the integer case
    /// `string(forKey:)` really does answer nil here — the two wrong-type cases fail differently
    /// and both are pinned so neither can be assumed from the other.
    static let plistArrayWhereAStringBelongs = [selectionKey, "(a,b)"]
}

/// Launching with a pinned state, which is the only way this suite launches.
extension XCUIApplication {
    /// Pin all five settings, then launch.
    ///
    /// Arguments are APPENDED, so a caller that has already set `-UITestColorScheme` keeps it.
    func launchPinned(showing destination: String) {
        launchArguments += LaunchState.showing(destination)
        launch()
    }

    /// Pin the launch surface only, then launch. See ``LaunchState/onlySurface(_:)`` for when this
    /// is the right call and when it is not.
    func launchPinned(onlySurface destination: String) {
        launchArguments += LaunchState.onlySurface(destination)
        launch()
    }
}
