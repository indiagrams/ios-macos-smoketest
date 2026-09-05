// TimestampCodec — the engine half of APP-05, APP-06 and APP-07.
//
// WHY THIS FILE HOLDS NO CACHED DATE FORMATTER, AND NO STATIC STORAGE AT ALL
//
// Foundation's reference-type ISO 8601 formatting class, and its general
// date-formatting sibling, are deliberately never named in this file. That is
// enforced by grep, and the reason is measured rather than stylistic.
//
// Holding one of them in a `nonisolated let` under `-swift-version 6
// -strict-concurrency=complete` is an ERROR, not a warning:
//
//     error: let 'f' is not concurrency-safe because non-'Sendable' type
//     '…' may have shared mutable state [#MutableGlobalVariable]
//
// and the compiler's own two remediation notes are: annotate it `@MainActor`,
// or disable concurrency-safety checking with the unsafe-nonisolated
// annotation that APP-12 and ROADMAP criterion 5 forbid BY NAME. A codec that
// must not touch the main actor has neither option, so the question is settled
// by choosing an API that never raises it.
//
// `Date.ISO8601FormatStyle` and `Date.FormatStyle` are `Sendable` VALUE types.
// Measured on this tree: a `requireSendable` probe over `Date.ISO8601FormatStyle`,
// `Date.FormatStyle`, `TimeZone`, `Locale`, `Calendar` and `Date` compiles under
// Swift 6 with complete checking. So every style below is constructed INSIDE
// the call that uses it — they are cheap structs — and every zone arrives as a
// parameter. Nothing here is cached, nothing is ambient, and there is no
// `static` stored property in the file to be unsafe about.
//
// IT IS ALSO THE ONLY API THAT WORKS. The reference-type class's
// fractional-seconds handling is all-or-nothing, measured over the same nine
// inputs: its default options parse "2026-09-04T00:00:00Z" and return nil for
// "2026-09-04T00:00:00.123Z"; the internet-date-time-plus-fractional options do
// the exact reverse. Covering both needs TWO configured instances and a
// try-both fallback, and a try-both fallback is a place for the wrong branch to
// accept the wrong shape (T-06-28). One format style value covers both.
//
// TWO API SHAPES THAT COST TEN MINUTES EACH IF YOU GUESS
//
//   `Date.ISO8601FormatStyle.timeZone(_:)` takes a `TimeZoneSeparator`, NOT a
//   `TimeZone`; `Date.FormatStyle.timeZone(_:)` takes a `Symbol.TimeZone`, NOT
//   a `TimeZone`. In both cases the zone goes in the INITIALIZER.
//
// WHY EVERY SIGNATURE IS IN Double AND NOT Date
//
// Phase 7 criterion 3: any persisted date-like value must be a Double. Phase 6
// persists nothing, but carrying the instant as `timeIntervalSince1970` and
// building a `Date` only at render time makes Phase 7's work a one-line
// `set(_:forKey:)` with nothing to convert. Measured:
// `Date(timeIntervalSince1970: d.timeIntervalSince1970) == d` round-trips
// exactly.
//
// TOTALITY, AND THE ONE TRAP SITE IN THIS SUBJECT
//
// These unit bundles are HOST-BASED, so a Swift runtime trap does not fail a
// test — it kills the host, aborts the run and posts a crash dialog on the
// developer's desktop. Date arithmetic is where that happens: `Int(someDouble)`
// traps for a value outside `Int`'s range, and a non-finite Double handed to a
// date initializer is undefined territory nobody should explore in a shipping
// app. Every entry point below therefore rejects a non-finite input BEFORE any
// `Date` exists, and the integer rendering never converts to `Int` at all.

import Foundation

/// Unix epoch and ISO 8601 conversion, and the timezone list APP-07's picker
/// is populated from.
///
/// A caseless enum rather than a struct: there is no instance state and there
/// is nothing to construct — which is the same thing as saying there is no
/// cached formatting object, the property this whole file is arranged around.
enum TimestampCodec {
    // MARK: - Parsing

    /// The instant `s` denotes, as seconds since 1970, or why it is not an
    /// extended-format ISO 8601 date and time.
    ///
    /// - Important: **The parser is the authority, and it is measurably more
    ///   lenient than a hand-written validator would be.** Two forms parse
    ///   here that a scan requiring two seconds digits and an uppercase zone
    ///   designator would reject:
    ///
    ///       "2026-09-04T00:00:0Z"   -> 1788480000   (single-digit seconds)
    ///       "2026-09-04T00:00:00z"  -> 1788480000   (lowercase designator)
    ///
    ///   Both are measured on this tree; the lowercase one is not in the phase
    ///   research and was found by re-measuring. This is the same authority
    ///   question the Base64 and percent-encoding families answered, and it
    ///   gets the same answer: the divergence is ASSERTED rather than
    ///   reconciled, in `TimestampTests`. Plan 06-08's positional scan
    ///   accepts both, and four more of the same kind that re-measuring found:
    ///   single-digit minutes, hours, days and months all parse too.
    /// - Important: **TWO STYLES ARE TRIED, AND THAT IS NOT OPTIONAL — the
    ///   phase research is wrong here, because it measured one OS.** The claim
    ///   that a single format style covers both fractional and non-fractional
    ///   seconds is TRUE from iOS 26 on and FALSE on everything below it.
    ///   Measured on four runtimes:
    ///
    ///                    "…T00:00:00Z"   "…T00:00:00.123Z"
    ///       iOS 17.5     plain only      fractional only
    ///       iOS 18.6     plain only      fractional only
    ///       iOS 26.1     both            both
    ///       macOS 26.5.2 both            both
    ///
    ///   On this app's deployment floor the value-type style is exactly as
    ///   all-or-nothing as the reference-type class it was chosen over, so a
    ///   single style would silently refuse every fractional timestamp on iOS
    ///   17 and 18 while accepting it on 26 — a user-visible difference by OS
    ///   version, which is the one thing this app's codecs exist to prevent.
    ///
    ///   T-06-28 warns that a try-both fallback is a place for the wrong
    ///   branch to accept the wrong shape. It cannot be, here, and that is
    ///   ASSERTED rather than argued: the two styles are complementary below
    ///   iOS 26 and identical from 26 on, so the order is unobservable. See
    ///   `theTwoStylesNeverDisagreeAboutAnInstant`.
    /// - Note: Offsets with and without a colon both parse (`+05:30` and
    ///   `-0800`). A missing zone designator, a date with no time,
    ///   basic-format `20260904`, a space in place of the `T`, and month 13
    ///   all fail — on all four runtimes, and both styles refuse each of them.
    /// - Important: **THE SCAN IS CONSULTED FIRST, AND IT IS THE AUTHORITY.**
    ///   The parse throws `NSCocoaErrorDomain` code 2048 with no position in
    ///   it and D-85 requires both a reason and a position, so
    ///   `TimestampDetection.classifyISO8601(_:)` runs before either style and
    ///   its verdict is what this function returns. Two consequences, both
    ///   asserted rather than argued:
    ///
    ///   - Every failure a caller sees names an expected token and a 1-based
    ///     Character position. There is no position-free fallback left in this
    ///     engine.
    ///   - This function is now measurably STRICTER than the raw format style,
    ///     in exactly three ways, and that is deliberate. The raw style parses
    ///     `"2026-09-04T00:00:00Zhello world"` (everything after the zone
    ///     designator is ignored), `"…T00:80:00Z"` (minute 80, silently
    ///     normalised to 01:20) and `"…T00:00:00GMT"`. Converting any of those
    ///     would be the "quietly wrong answer" half of criterion 1. See
    ///     `DetectionContractTests`, which asserts all three against the raw
    ///     style so the divergence is a measurement rather than a claim.
    ///
    ///   The contract that holds is one-directional, the same shape
    ///   `Base64Codec` states: `classifyISO8601(s) == nil` implies one of the
    ///   two styles below parses `s`. **The converse is false**, and it is
    ///   counted by a generated mutation sweep rather than asserted.
    /// - Note: Total. The only failure paths are the scan's verdict and the
    ///   final `guard`, and no value produced here is used in arithmetic.
    /// - Parameter s: Untrusted input of arbitrary length and encoding.
    /// - Returns: `.success` with seconds since 1970, or `.failure`.
    nonisolated static func parseISO8601(_ s: String) -> Result<Double, ConversionFailure> {
        if let failure = TimestampDetection.classifyISO8601(s) {
            return .failure(failure)
        }
        if let instant = try? Date.ISO8601FormatStyle().parse(s) {
            return .success(instant.timeIntervalSince1970)
        }
        if let instant = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(s) {
            return .success(instant.timeIntervalSince1970)
        }
        // Unreachable while the one-directional contract holds — which is
        // asserted over the shared corpus AND over a generated mutation sweep,
        // rather than asserted here where it could not fail. The branch still
        // needs a value, and the honest one names the end of the input.
        return .failure(.expectedCharacter("a valid ISO 8601 date and time",
                                           position: characterPosition(utf8Offset: s.utf8.count, in: s)))
    }

    // MARK: - Rendering

    /// `epochSeconds` written as extended-format ISO 8601 in `timeZone`.
    ///
    /// - Important: **The offset carries a colon** — `2026-09-03T17:00:00-07:00`,
    ///   not `-0700`. The style's default is the colon-free form, which mixes a
    ///   BASIC-format offset into an otherwise extended-format string; RFC 3339
    ///   requires the colon and the corpus's own inputs are written with it.
    ///   Asserted literally in `TimestampTests` so this and the string
    ///   inventory cannot drift, and recorded as `iso_offset_separator=colon`
    ///   in the plan evidence, which is the form plan 06-13's cell renders.
    /// - Important: **A fraction the user typed survives; a whole second does
    ///   not grow one.** The style is asked for fractional seconds only when
    ///   the instant actually has a fraction, so `1788480000` renders as
    ///   `2026-09-04T00:00:00Z` while `1788480000.123` renders as
    ///   `2026-09-04T00:00:00.123Z`. Always dropping the fraction would be the
    ///   quiet data loss the Base64 codec refuses for the same reason, and it
    ///   would break the round-trip property: measured, the fraction renders to
    ///   three digits, so the largest round-trip error over this corpus is
    ///   0.0009 s and the suite's tolerance is 0.001 s.
    /// - Note: Total. A non-finite input returns the empty string BEFORE a
    ///   `Date` is constructed — see the file header. The empty string is what
    ///   the view layer already shows as the empty-state string the UI-SPEC's
    ///   inventory assigns to the Timestamps output cells. Named rather than
    ///   spelled on purpose: plan 06-08 polices this file with a `grep -c`
    ///   that must return 0 and whose second alternative is that key's last
    ///   component, so writing the key out would turn a gate red against a
    ///   string that has nothing to do with the retired fallback it exists to
    ///   police — the ninth time this phase has met a content gate sweeping
    ///   something it did not mean.
    /// - Parameters:
    ///   - epochSeconds: Seconds since 1970.
    ///   - timeZone: The zone to render in. APP-07's picker supplies it;
    ///     nothing here reads an ambient zone.
    nonisolated static func renderISO8601(_ epochSeconds: Double, timeZone: TimeZone) -> String {
        guard epochSeconds.isFinite else { return "" }
        let hasFraction = epochSeconds != epochSeconds.rounded(.down)
        let style = Date.ISO8601FormatStyle(includingFractionalSeconds: hasFraction, timeZone: timeZone)
            .timeZoneSeparator(.colon)
        return style.format(Date(timeIntervalSince1970: epochSeconds))
    }

    /// `epochSeconds` written as an integer Unix epoch.
    ///
    /// - Important: **Floors, and does not truncate toward zero.** Measured:
    ///   the ISO rendering above floors — `-0.5` renders as
    ///   `1969-12-31T23:59:59Z` — and the two cells sit side by side in the
    ///   same card, so they must agree about which second an instant is in.
    ///   Truncating toward zero would show `0` beside a time in 1969.
    /// - Important: **No locale, no grouping separator, no `Int` conversion.**
    ///   A locale-aware integer rendering of this same number produces
    ///   Arabic-Indic digits under an Arabic locale, which breaks copy-paste
    ///   silently; `TimestampTests` asserts the two differ, which is what gives
    ///   the plain-digits assertion teeth. `Int(someDouble)` TRAPS outside
    ///   `Int`'s range, and this bundle is host-based, so the conversion is not
    ///   made at all — `%.0f` over an already-floored value renders every
    ///   finite magnitude exactly and adds no rounding of its own.
    /// - Note: Total. Non-finite returns the empty string.
    nonisolated static func renderEpochSeconds(_ epochSeconds: Double) -> String {
        guard epochSeconds.isFinite else { return "" }
        return String(format: "%.0f", epochSeconds.rounded(.down))
    }

    /// `epochSeconds` written as a human date and time in `timeZone`.
    ///
    /// - Warning: **LOCALE- AND REGION-DEPENDENT OUTPUT. No test and no UI
    ///   test may assert its literal text.** The UI spec's mockup shows this
    ///   instant one way and the machine the phase research ran on renders it
    ///   another; both are correct for their region. What can honestly be
    ///   asserted is that the string is non-empty, that it carries the
    ///   four-digit year, and that it DIFFERS between two zones — which is the
    ///   assertion that proves the zone argument is used at all. A UI test
    ///   reaches this cell by the `Timestamps.cell.dateTime` accessibility
    ///   identifier, never by matching its text.
    /// - Note: The D-93 prose sweep is unaffected by this string. That sweep
    ///   fails on PROSE TERMS, and a formatted date contains none.
    /// - Note: The zone goes in the INITIALIZER. `Date.FormatStyle.timeZone(_:)`
    ///   takes a `Symbol.TimeZone` and will not accept a `TimeZone`.
    /// - Note: Total. Non-finite returns the empty string, before any `Date`
    ///   is constructed.
    nonisolated static func renderDateTime(_ epochSeconds: Double, timeZone: TimeZone) -> String {
        guard epochSeconds.isFinite else { return "" }
        return Date(timeIntervalSince1970: epochSeconds)
            .formatted(Date.FormatStyle(date: .long, time: .shortened, timeZone: timeZone))
    }

    // MARK: - Timezone selection (APP-07)

    /// Every timezone the picker offers, in the order it offers them.
    ///
    /// - Note: Computed on each access rather than stored. It is a few hundred
    ///   strings and this is not on a keystroke path; a stored `static` would
    ///   be the one piece of shared mutable state in a file whose whole point
    ///   is not having any.
    nonisolated static var timeZoneIdentifiers: [String] {
        pickerOrder(TimeZone.knownTimeZoneIdentifiers)
    }

    /// RED STEP (plan 06-20, CR-02): the option list the picker is populated
    /// from, as it behaved at 929ba9c — the selection is ignored. Replaced in
    /// the next commit.
    nonisolated static func timeZoneIdentifiers(including _: String) -> [String] {
        timeZoneIdentifiers
    }

    /// `identifiers` in the order and shape a picker needs: ascending, and
    /// with no identifier appearing twice.
    ///
    /// - Important: This is a separate function TAKING ITS INPUT so that the
    ///   ordering guarantee has an assertion that can fail. Measured on this
    ///   tree, `TimeZone.knownTimeZoneIdentifiers` ALREADY arrives sorted and
    ///   already free of duplicates, so a test written only against the live
    ///   array passes whether or not this function sorts anything — a control
    ///   that cannot fire, which this phase has now shipped once and caught
    ///   twice. `TimestampTests` drives a scrambled, duplicated input through
    ///   here instead, and separately asserts that ``timeZoneIdentifiers`` is
    ///   this function applied to the live array.
    /// - Note: The duplicate removal is a correctness requirement, not tidying:
    ///   a repeated identifier collides as a `ForEach` id.
    nonisolated static func pickerOrder(_ identifiers: [String]) -> [String] {
        Array(Set(identifiers)).sorted()
    }

    /// The zone the picker starts on: the device's own (APP-07).
    nonisolated static var defaultTimeZone: TimeZone {
        .current
    }
}
