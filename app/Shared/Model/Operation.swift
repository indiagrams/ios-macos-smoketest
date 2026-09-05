// Operation — the chainable operations the add-step control offers (D-80,
// D-81, APP-08).
//
// TEN operations, in the order 06-UI-SPEC.md's "Add-step menu" table lists
// them. That table is the observable artifact and it lists ten `op.*` keys;
// the prose in the same section says "the eight text→text operations". The
// table wins, for the same reason the UI-SPEC itself gave when it resolved
// its `AccessibilityIdentifiers` header against its own examples.
//
// A NAME THAT SHADOWS FOUNDATION, DELIBERATELY. `Foundation.Operation` is
// NSOperation. A type declared in this module wins over one imported from
// Foundation, so every reference in this app resolves here; anything that
// genuinely wanted the Foundation class would have to spell it
// `Foundation.Operation`, and nothing in this app does — D-83 rules out the
// concurrency machinery NSOperation exists for. The shadowing is asserted
// rather than assumed: `PipelineTests.theModelTypesAreSendableAndCross…`
// passes this type to a helper that only accepts a Sendable type, and
// `Foundation.Operation` is a non-Sendable class, so that call compiles only
// while the local enum is the one that resolves.
//
// This file is compiled into the two app targets and into BOTH unit-test
// targets, by the `sources:` entries for Shared/Model in app/project.yml and
// app/Project.swift.

/// One text→text conversion a step can perform.
///
/// The raw value **is** the `Localizable.xcstrings` key that names the
/// operation, so plan 06-10's string catalog and plan 06-11's add-step menu
/// render from one list rather than from two that can drift apart. The menu
/// item title and the resulting card's header are the same string because
/// they are the same key.
///
/// `CaseIterable` in **menu order**: the six codec operations first, then the
/// four digests. The UI's two sections — `menu.section.encodeDecode` and
/// `menu.section.hashing` — are contiguous slices of ``allCases``, so a
/// reordering here scrambles the menu and `PipelineTests` fails rather than
/// the mistake being found by looking at a screenshot.
///
/// **The Timestamps conversions are not chainable in Phase 6.** They take an
/// *instant*, not text, so there is no `Operation` for them and the add-step
/// menu has two sections rather than three. 06-UI-SPEC.md left this to the
/// planner and the plan decided it here. The menu gains a third section only
/// if a later phase decides an ISO 8601 string is text enough to chain, at
/// which point cases are appended and the count assertions move with them.
///
/// `Sendable` and `Hashable` are free: the raw value is a `String`.
enum Operation: String, CaseIterable, Sendable, Hashable {
    /// `op.base64.encode` — "Base64 encode".
    case base64Encode = "op.base64.encode"

    /// `op.base64.decode` — "Base64 decode". The one codec operation whose
    /// failures carry both a character and a position.
    case base64Decode = "op.base64.decode"

    /// `op.url.encode` — "URL encode".
    case urlEncode = "op.url.encode"

    /// `op.url.decode` — "URL decode".
    case urlDecode = "op.url.decode"

    /// `op.html.encode` — "HTML encode".
    case htmlEncode = "op.html.encode"

    /// `op.html.decode` — "HTML decode".
    case htmlDecode = "op.html.decode"

    /// `op.hash.md5` — "MD5". Cannot fail; see ``DigestCodec``.
    case md5 = "op.hash.md5"

    /// `op.hash.sha1` — "SHA-1". Cannot fail.
    case sha1 = "op.hash.sha1"

    /// `op.hash.sha256` — "SHA-256". Cannot fail.
    case sha256 = "op.hash.sha256"

    /// `op.hash.sha512` — "SHA-512". Cannot fail.
    case sha512 = "op.hash.sha512"
}
