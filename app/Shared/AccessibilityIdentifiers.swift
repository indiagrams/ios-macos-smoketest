import Foundation

/// Stable identifiers for UI test queries.
///
/// **Why these exist.** UI tests should never match elements by their visible
/// text — the moment your app supports another language (or you tweak copy),
/// the test silently breaks. Use these constants in both your views and
/// your tests so the contract is explicit and refactor-safe.
///
/// **Adding an identifier.** Define a constant here, attach it to the view
/// via `.accessibilityIdentifier(AccessibilityIdentifiers.<name>)`, and
/// query it in tests via `app.staticTexts[AccessibilityIdentifiers.<name>]`
/// (or `.otherElements`, `.buttons`, `.images` etc. depending on the SwiftUI
/// element type backing it).
///
/// **Single source of truth.** This file is compiled into BOTH the main
/// app target (via `app/Shared/**`) AND the UI test target (via an
/// explicit `sources:` entry in project.yml / Project.swift). UI tests
/// run as a separate process and can't link the app binary, so the
/// standard `@testable import` pattern doesn't apply for them. Compiling
/// the one shared file into both targets preserves the single-source-of-
/// truth property — refactor here and both ends see it.
///
/// **Naming convention.** Dotted, with a **PascalCase feature scope**, one or
/// more **`lowerCamelCase` leaves**, and **no platform suffix**:
/// `Shell.tab.encode`, `Encode.output`, `Step.copy`. One identifier serves both
/// platforms, which is what lets a single sweep implementation run against the
/// iOS and macOS targets. This paragraph previously named a casing its own three
/// examples contradicted; 06-UI-SPEC.md resolved that in writing in favour of
/// what the examples showed, and this is that resolution.
///
/// **The product name is not a scope.** D-91 bans the product name written as
/// spaced prose from anything reaching a user or a reviewer, and the D-93 sweep
/// harvests identifiers as well as labels — so the app's own selectors must not
/// make it special-case the app's own name. The feature scopes are ``Shell``,
/// ``Encode``, ``Hashing``, ``Timestamps``, ``Step`` and ``Input``.
///
/// **Two-level leaves are flattened in Swift, not in the value.** `swiftlint`'s
/// `nesting` rule allows one level of type nesting, so a `tab` enum inside
/// ``Shell`` inside this enum is a `--strict` error (observed, not assumed).
/// The second level therefore lives in the constant NAME and in the VALUE —
/// `Shell.tabEncode` is `"Shell.tab.encode"` — because the value is what the
/// views attach and what the sweep queries, and it is the value the convention
/// above describes.
///
/// **Attach to leaf views only.** SwiftUI `Text`, `Button`, `Image`,
/// `TextField`, `Toggle` and `Picker` surface in XCUITest queries. Containers
/// (`VStack`, `HStack`, `ZStack`) without an explicit accessibility role do not
/// surface independently.
public enum AccessibilityIdentifiers {
    /// The navigation shell: three destinations, reached through a `TabView` on
    /// iOS and a `NavigationSplitView` sidebar on macOS (D-11, D-90).
    ///
    /// The two sets are separate because the two containers are separate views;
    /// the identifier still carries no platform suffix, because a suffix would
    /// mean the sweep had to know which platform it was running on.
    public enum Shell {
        /// The iOS tab item for the encode/decode destination.
        public static let tabEncode = "Shell.tab.encode"

        /// The iOS tab item for the hashing destination.
        public static let tabHashing = "Shell.tab.hashing"

        /// The iOS tab item for the timestamps destination.
        public static let tabTimestamps = "Shell.tab.timestamps"

        /// The macOS sidebar row for the encode/decode destination.
        public static let sidebarEncode = "Shell.sidebar.encode"

        /// The macOS sidebar row for the hashing destination.
        public static let sidebarHashing = "Shell.sidebar.hashing"

        /// The macOS sidebar row for the timestamps destination.
        public static let sidebarTimestamps = "Shell.sidebar.timestamps"
    }

    /// The encode/decode surface — a single in→out block (D-87).
    public enum Encode {
        /// The text field the user converts from.
        public static let input = "Encode.input"

        /// The character count beside the input.
        public static let inputCount = "Encode.inputCount"

        /// The button that fills the input with a worked value.
        public static let useExample = "Encode.useExample"

        /// The Base64 / URL / HTML segmented picker.
        public static let format = "Encode.format"

        /// The encode / decode segmented picker.
        public static let direction = "Encode.direction"

        /// The converted value.
        public static let output = "Encode.output"
    }

    /// The hashing surface — four digests of one input, at once (D-87).
    public enum Hashing {
        /// The text field the digests are taken over.
        public static let input = "Hashing.input"

        /// The button that fills the input with a worked value.
        public static let useExample = "Hashing.useExample"

        /// The MD5 digest row's value.
        public static let digestMD5 = "Hashing.digest.md5"

        /// The SHA-1 digest row's value.
        public static let digestSHA1 = "Hashing.digest.sha1"

        /// The SHA-256 digest row's value.
        public static let digestSHA256 = "Hashing.digest.sha256"

        /// The SHA-512 digest row's value.
        public static let digestSHA512 = "Hashing.digest.sha512"
    }

    /// The timestamps surface — one instant, several representations side by
    /// side (D-87).
    public enum Timestamps {
        /// The text field carrying the timestamp or date.
        public static let input = "Timestamps.input"

        /// The button that fills the input with a worked value.
        public static let useExample = "Timestamps.useExample"

        /// The picker choosing how the input is read.
        public static let readAs = "Timestamps.readAs"

        /// The control that sets ``readAs`` from the input's shape.
        public static let detect = "Timestamps.detect"

        /// The time-zone picker.
        public static let timeZone = "Timestamps.timeZone"

        /// The Unix-epoch representation cell.
        public static let cellEpoch = "Timestamps.cell.epoch"

        /// The ISO 8601 representation cell.
        public static let cellISO8601 = "Timestamps.cell.iso8601"

        /// The date-and-time representation cell.
        public static let cellDateTime = "Timestamps.cell.dateTime"
    }

    /// The one input block all three surfaces share — see
    /// `app/Shared/Views/InputArea.swift`.
    ///
    /// **A scope of its own rather than a member of the three surface scopes,
    /// and that is the whole point.** The three surface scopes each mint an
    /// `input` and a `useExample` because those elements are PER SURFACE: there
    /// are three text fields on screen over the course of a walk and a query has
    /// to say which one it means. The control below is not per surface. There is
    /// exactly one software keyboard, the toolbar hangs off it rather than off
    /// any surface, and only the focused field can have raised it — so a
    /// per-surface constant here would mint three selectors for one element and
    /// leave a test free to pick the wrong one.
    ///
    /// Added by plan 06-19 to close GAP-06-01.
    public enum Input {
        /// The control on the iOS keyboard toolbar that resigns first responder.
        ///
        /// iOS only. macOS has no software keyboard, the modifier that installs
        /// this is compiled out there, and nothing on that platform queries it.
        public static let done = "Input.done"
    }

    /// The step card and its output accessory — the repeated unit of the whole
    /// UI (D-80).
    ///
    /// **These are attached to REPEATED elements, and that is deliberate.**
    /// XCUITest resolves a repeated identifier by index —
    /// `app.buttons.matching(identifier: <the copy constant>).element(boundBy: n)`
    /// — which is the right shape for a stack that grows in Phase 7. Do NOT
    /// mint per-instance identifiers by appending an ordinal to any constant
    /// below: a per-instance scheme breaks the moment Phase 7 reorders the
    /// stack, and it would make every query depend on how many cards happened
    /// to exist when the test was written.
    ///
    /// Note that ``AccessibilityIdentifiers/Step`` deliberately shares its name
    /// with the model's `Step` value type. They never collide in practice
    /// because the model type has none of these members, so an unqualified
    /// reference is a compile error rather than a silently wrong selector.
    public enum Step {
        /// The card itself.
        public static let card = "Step.card"

        /// The card's header — the operation name.
        public static let header = "Step.header"

        /// The card's output value.
        public static let output = "Step.output"

        /// The always-present diagnostic strip beneath the body.
        public static let diagnostic = "Step.diagnostic"

        /// The copy control in an output's trailing accessory.
        public static let copy = "Step.copy"

        /// The add-step control in an output's trailing accessory — one per
        /// OUTPUT, not one per card, which is what makes APP-08 unambiguous on
        /// a surface that renders four outputs.
        public static let addStep = "Step.addStep"

        /// Each ITEM the add-step control's menu presents, resolved by index
        /// like the other repeated constants here. Attached to the items rather
        /// than to the menu because plan 06-13 measured that a `Menu` presents
        /// items carrying no identifier when one is applied to the container
        /// around them.
        public static let addStepMenu = "Step.addStepMenu"

        /// The sentence a step shows when an earlier step in its pipeline
        /// failed (D-84). Never blank, and never a stale value.
        public static let blocked = "Step.blocked"
    }
}
