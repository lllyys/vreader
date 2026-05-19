// Purpose: Feature #60 WI-6c / Feature #56 WI-8 — row identity for
// the reader More-menu popover (`ReaderMorePopover`). Centralising
// the row contract here keeps the design's layout (order, divider,
// labels, icons, toggle vs tap, state-driven sub-detail, accessibility
// ids, notification routing) testable without depending on SwiftUI
// render machinery — the same pattern `ReaderChromeButton` uses for
// the top/bottom chrome.
//
// Design source:
// `dev-docs/designs/vreader-fidelity-v1/project/vreader-more.jsx`
// + `design-notes/reader-search-and-more-menu.md` §2
// + `design-notes/feature-60-followups.md` §2.3 (bilingual row's
//   3-way Off / On / Unavailable presentation)
// + `design-notes/needs-design-issues.md` §#864 (per-chapter
//   re-translate row, conditional on `bilingualOn`).
//
// WI-8 update — Bilingual row returns: feature #56's design lands the
// 3-way `TrailingControl` (off-toggle / on-toggle / no-toggle when AI
// provider missing) and a conditional `reTranslateChapter` row that
// appears only when bilingual mode is on for the book. The
// previously-deferred state (`isToggle: Bool` + bilingualMode absent)
// is replaced by `TrailingControl` + a `visibleRows(for:bilingualOn:)`
// overload. The legacy `visibleRows(for:)` and `isToggle` accessors
// remain as backward-compat helpers for callers that don't yet care
// about bilingual state.
//
// Routing note: each row maps 1:1 to a `Notification.Name` the
// `ReaderMorePopover` posts and `ReaderContainerView` observes. The
// host-side effect each row triggers is modelled by
// `ReaderMoreMenuEffect` (feature #61 WI-3).

import Foundation

/// The bilingual presentation state of the active book, threaded into
/// the More-menu so the bilingual row can render its three designed
/// states (design §2.3) and the conditional re-translate row can
/// appear / disappear.
///
/// - `off` — AI is configured but bilingual mode is off for this book.
///   Toggle slot renders OFF; sub-detail prompts to enable.
/// - `on(targetLanguage:)` — bilingual mode is on for this book.
///   Toggle slot renders ON; sub-detail shows the `EN ↔ <target>`
///   language pair. The `reTranslateChapter` row appears in this state.
/// - `unavailable` — no AI provider is configured (or the feature
///   flag is off). The row renders with a chevron + "Configure AI
///   provider first" sub-detail and no toggle (design §2.3 — disabled
///   but not hidden, the iOS-standard "Settings → Cellular" pattern).
enum BilingualRowState: Equatable, Sendable {
    case off
    case on(targetLanguage: String)
    case unavailable
}

/// The trailing-edge control variant rendered for a row.
///
/// Replaces the prior `isToggle: Bool` accessor: bilingual mode's
/// `.unavailable` state ships a chevron (not a toggle), and the
/// reTranslate row is a tap row (chevron). A single enum keeps the
/// design's "toggle vs chevron vs nothing" tri-state honest.
enum TrailingControl: Equatable, Sendable {
    /// An inline iOS-style toggle switch. Payload is the on/off value.
    case toggle(Bool)
    /// A trailing chevron — the standard tap-row affordance.
    case chevron
    /// No trailing accessory. Currently unused by any row, but kept as
    /// a deliberate variant so the design's "no trailing control"
    /// possibility remains expressible without re-shaping the enum.
    case none
}

/// A row in the reader More-menu popover. `CaseIterable.allCases`
/// returns the rows in declared (top → bottom) order, matching
/// `vreader-more.jsx` + design §2.3 (bilingual row reinstated).
/// `ReaderMorePopover` renders them via
/// `ForEach(ReaderMoreMenuRow.allCases)`, inserting the hairline
/// divider after `dividerAfter`. The conditional `reTranslateChapter`
/// row is omitted by `visibleRows(for:bilingualOn:)` when bilingual
/// mode is off (#864).
enum ReaderMoreMenuRow: String, CaseIterable, Equatable {
    case readAloud
    case autoTurnPages
    case bilingual
    case reTranslateChapter
    case bookDetails
    case shareBook
    case exportAnnotations

    /// The canonical (static) divider anchor — the row after which
    /// the design draws its single hairline divider when the
    /// conditional `reTranslateChapter` row is hidden. Design §2.3
    /// places the divider between the bilingual cluster (Read aloud /
    /// Auto-turn / Bilingual) and the book-action cluster (Book
    /// details / Share / Export).
    ///
    /// When `reTranslateChapter` is visible (#864 — bilingual on),
    /// the runtime anchor slides one row down to `.reTranslateChapter`
    /// — see `dividerAnchor(in:)`. `ReaderMorePopover` consults the
    /// dynamic helper so the divider always trails the last visible
    /// row of the bilingual cluster.
    static let dividerAfter: ReaderMoreMenuRow = .bilingual

    /// The runtime divider anchor — the LAST visible row of the
    /// bilingual cluster (Bilingual / Re-translate). Returns
    /// `.bilingual` when the re-translate row is hidden; returns
    /// `.reTranslateChapter` when both rows are present.
    ///
    /// Defensive fallback: when neither bilingual-cluster row is in
    /// `rows` (a future capability filter that hides both — not
    /// expected in production today since `.bilingual` is currently
    /// never gated, but possible), the anchor falls back to the
    /// nearest visible row preceding the bilingual cluster's
    /// declared position. This keeps the divider visible — it always
    /// trails a row that IS rendered — and preserves the
    /// between-clusters semantic. Returns `nil` only when `rows`
    /// is empty, in which case the popover renders no rows anyway.
    static func dividerAnchor(in rows: [ReaderMoreMenuRow]) -> ReaderMoreMenuRow? {
        if rows.contains(.reTranslateChapter) { return .reTranslateChapter }
        if rows.contains(.bilingual)          { return .bilingual }
        // Defensive: prefer the row immediately preceding the
        // bilingual cluster's declared position, then walk back, then
        // walk forward into the book-action cluster as a last resort.
        let preferredFallbacks: [ReaderMoreMenuRow] = [
            .autoTurnPages, .readAloud,
            .bookDetails, .shareBook, .exportAnnotations
        ]
        return preferredFallbacks.first(where: rows.contains)
    }

    /// Notification posted on tap. `ReaderContainerView` observes all
    /// rows and runs the matching action. The popover does not thread
    /// closures — posting keeps it composable in one place.
    var notification: Notification.Name {
        switch self {
        case .readAloud:           return .readerMoreReadAloud
        case .autoTurnPages:       return .readerMoreToggleAutoTurn
        case .bilingual:           return .readerMoreBilingual
        case .reTranslateChapter:  return .readerMoreReTranslateChapter
        case .bookDetails:         return .readerMoreBookDetails
        case .shareBook:           return .readerMoreShareBook
        case .exportAnnotations:   return .readerMoreExportAnnotations
        }
    }

    /// The inverse of `notification` — resolves the row that posted a
    /// given More-menu notification, or `nil` for an unrelated name.
    /// `ReaderMoreMenuActionObservers` uses this to map an observed
    /// notification back to its row in one funnel.
    init?(notification: Notification.Name) {
        guard let match = Self.allCases.first(where: { $0.notification == notification }) else {
            return nil
        }
        self = match
    }

    // MARK: - Capability gating

    /// The rows `ReaderMorePopover` should render for a book whose
    /// reader engine advertises `capabilities`, with `bilingualOn`
    /// driving the conditional `reTranslateChapter` row.
    ///
    /// The `Read aloud` row is gated on the active format's `.tts`
    /// capability: it renders only for formats whose reader engine
    /// advertises `.tts`. The gate originated with bug #176 / GH #602.
    ///
    /// The `reTranslateChapter` row is gated on `bilingualOn` —
    /// design §#864: "the row is conditional on `bilingualOn === true`
    /// — when bilingual is off there's nothing to re-translate, so
    /// the row is absent rather than disabled."
    ///
    /// The `bilingual` row itself is **never** gated — design §2.3:
    /// "the unavailable state is not hidden, because invisibility
    /// hurts discoverability".
    ///
    /// Declared (top → bottom) order is preserved — `ReaderMorePopover`
    /// draws its hairline divider after the runtime
    /// `dividerAnchor(in:)`, so the filter must not reorder.
    ///
    /// - Parameters:
    ///   - capabilities: the active format's capability set, or
    ///     `nil` for callers that don't supply one (previews / older
    ///     tests / legacy call sites). A `nil` set yields every
    ///     non-conditional row.
    ///   - bilingualOn: whether bilingual mode is on for this book.
    ///     The default (`false`) preserves the WI-6c contract for
    ///     callers that haven't been updated.
    /// - Returns: the rows to render, in declared order.
    static func visibleRows(
        for capabilities: FormatCapabilities?,
        bilingualOn: Bool = false
    ) -> [ReaderMoreMenuRow] {
        allCases.filter { $0.isVisible(for: capabilities, bilingualOn: bilingualOn) }
    }

    /// Whether this row should be rendered for a book whose reader
    /// engine advertises `capabilities`, given the bilingual on/off
    /// state. `.readAloud` is gated on `.tts`; `.reTranslateChapter`
    /// is gated on `bilingualOn`; every other row is always visible.
    /// A `nil` capability set keeps the row (backward compat — see
    /// `visibleRows(for:bilingualOn:)`).
    func isVisible(for capabilities: FormatCapabilities?, bilingualOn: Bool = false) -> Bool {
        switch self {
        case .readAloud:
            guard let caps = capabilities else { return true }
            return caps.contains(.tts)
        case .reTranslateChapter:
            return bilingualOn
        case .autoTurnPages, .bilingual, .bookDetails, .shareBook, .exportAnnotations:
            return true
        }
    }

    /// Legacy 2-state accessor — true iff the row is rendered as an
    /// inline iOS-style toggle. Preserved for the original WI-6c
    /// callers that haven't migrated to `trailingControl(_:)`. The
    /// bilingual row's 3-way presentation (off-toggle / on-toggle /
    /// no-toggle-unavailable) means this accessor reports `true` only
    /// for `.autoTurnPages` — the bilingual row is queried via
    /// `trailingControl(_:)` instead.
    var isToggle: Bool {
        self == .autoTurnPages
    }

    /// Resolve the trailing-edge accessory variant for this row given
    /// the active reader state. The bilingual row's `.unavailable`
    /// state renders no toggle (design §2.3); its `.off` / `.on`
    /// states render the toggle in the matching position.
    /// `.autoTurnPages` keeps its single backing toggle. Every other
    /// row renders a tap-row chevron.
    ///
    /// - Parameters:
    ///   - bilingualState: the active book's bilingual presentation
    ///     state. Only consulted for the bilingual row.
    ///   - autoTurnOn: the auto-turn toggle's backing value.
    func trailingControl(
        bilingualState: BilingualRowState,
        autoTurnOn: Bool
    ) -> TrailingControl {
        switch self {
        case .autoTurnPages:
            return .toggle(autoTurnOn)
        case .bilingual:
            switch bilingualState {
            case .off:
                return .toggle(false)
            case .on:
                return .toggle(true)
            case .unavailable:
                // Design §2.3: no toggle in the unavailable state.
                // Render the standard tap-row chevron so the row
                // signals "tap to configure" — the iOS-standard
                // "Settings → Cellular when no SIM" pattern.
                return .chevron
            }
        case .readAloud, .reTranslateChapter, .bookDetails, .shareBook, .exportAnnotations:
            return .chevron
        }
    }

    /// User-facing primary label. Matches the design bundle text.
    var label: String {
        switch self {
        case .readAloud:           return "Read aloud"
        case .autoTurnPages:       return "Auto-turn pages"
        case .bilingual:           return "Bilingual mode"
        case .reTranslateChapter:  return "Re-translate chapter"
        case .bookDetails:         return "Book details"
        case .shareBook:           return "Share book"
        case .exportAnnotations:   return "Export annotations"
        }
    }

    /// SF Symbol rendered in the row's leading icon chip. Mapped to
    /// the design's icon family: Volume → `speaker.wave.2`, Timer →
    /// `timer`, Translate → `character.book.closed` (bilingual) and
    /// `arrow.triangle.2.circlepath` (re-translate), Info →
    /// `info.circle`, Share → `square.and.arrow.up`, Download →
    /// `arrow.down.doc`.
    var systemImage: String {
        switch self {
        case .readAloud:           return "speaker.wave.2"
        case .autoTurnPages:       return "timer"
        case .bilingual:           return "character.book.closed"
        case .reTranslateChapter:  return "arrow.triangle.2.circlepath"
        case .bookDetails:         return "info.circle"
        case .shareBook:           return "square.and.arrow.up"
        case .exportAnnotations:   return "arrow.down.doc"
        }
    }

    /// Stable accessibility identifier for XCUITest + verify-cron
    /// snapshots. Stable contract — do not rename without updating
    /// every harness.
    var accessibilityIdentifier: String {
        switch self {
        case .readAloud:           return "readerMoreReadAloud"
        case .autoTurnPages:       return "readerMoreAutoTurn"
        case .bilingual:           return "readerMoreBilingual"
        case .reTranslateChapter:  return "readerMoreReTranslateChapter"
        case .bookDetails:         return "readerMoreBookDetails"
        case .shareBook:           return "readerMoreShareBook"
        case .exportAnnotations:   return "readerMoreExportAnnotations"
        }
    }

    // MARK: - State-driven secondary text

    /// Secondary (sub-detail) line shown under the label, or `nil`
    /// when the row has none. Mirrors the design's `Row sub={...}`
    /// expressions in `vreader-more.jsx` + design §2.3, which update
    /// with reader state.
    ///
    /// - Parameters:
    ///   - ttsPlaying: whether read-aloud is currently speaking.
    ///   - autoTurnOn: whether auto-page-turn is enabled.
    ///   - autoTurnInterval: the auto-turn interval in seconds. Used
    ///     only when `autoTurnOn` is true; rendered as a whole-second
    ///     integer clamped to the design's 1...60 range.
    ///   - bilingualState: the bilingual presentation state. Drives
    ///     the bilingual row's three-state sub-detail. Defaults to
    ///     `.off` for legacy callers.
    func subDetail(
        ttsPlaying: Bool,
        autoTurnOn: Bool,
        autoTurnInterval: Double,
        bilingualState: BilingualRowState = .off
    ) -> String? {
        switch self {
        case .readAloud:
            return ttsPlaying
                ? "Playing \u{00b7} System voice"
                : "Start text-to-speech"
        case .autoTurnPages:
            guard autoTurnOn else { return "Off" }
            let clamped = min(60, max(1, autoTurnInterval.rounded()))
            return "Every \(Int(clamped))s"
        case .bilingual:
            switch bilingualState {
            case .off:
                return "Translate inline"
            case .on(let target):
                // Design §2.3: "English ↔ Chinese (or current target)".
                // The source language is the book's source — for the
                // generic design label we use "English" as the canonical
                // placeholder; the actual source language is the same
                // input the bilingual VM uses (BILINGUAL_LANGS), but the
                // More-menu sub-detail is the design-prescribed bidi
                // pair regardless. Future refinement may thread the
                // detected source language; the design copy doesn't.
                //
                // Defensive: a drifted persisted target (empty /
                // whitespace-only) would render "English ↔ " with
                // trailing whitespace. Trim the target; when empty,
                // fall back to a safe generic "On" label rather than
                // producing malformed copy. Production callers (the
                // bilingual VM) always carry a `BILINGUAL_LANGS`
                // value, but per-book JSON drift / future migrations
                // remain plausible.
                let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { return "On" }
                return "English \u{2194} \(trimmed)"
            case .unavailable:
                return "Configure AI provider first"
            }
        case .reTranslateChapter:
            // The idle copy from #864. Running / complete / error
            // sub-states belong to a downstream view model (WI-12),
            // not the pure row contract.
            return "Re-translate this chapter"
        case .bookDetails:
            return nil
        case .shareBook:
            return nil
        case .exportAnnotations:
            return "Markdown \u{00b7} JSON \u{00b7} VReader JSON"
        }
    }

    /// Whether the row is in its accent-tinted "active" state — the
    /// design lifts the icon chip to an accent tint for an active
    /// row. The stateful rows are Read aloud, Auto-turn, and the
    /// bilingual row's `.on` state. The `.unavailable` bilingual
    /// state is NOT active (it's the muted state). Re-translate is
    /// never active — it's a tap row.
    ///
    /// - Parameters:
    ///   - ttsPlaying: whether read-aloud is currently speaking.
    ///   - autoTurnOn: whether auto-page-turn is enabled.
    ///   - bilingualState: the bilingual presentation state. Defaults
    ///     to `.off` for legacy callers.
    func isActive(
        ttsPlaying: Bool,
        autoTurnOn: Bool,
        bilingualState: BilingualRowState = .off
    ) -> Bool {
        switch self {
        case .readAloud:     return ttsPlaying
        case .autoTurnPages: return autoTurnOn
        case .bilingual:
            if case .on = bilingualState { return true }
            return false
        case .reTranslateChapter, .bookDetails, .shareBook, .exportAnnotations:
            return false
        }
    }
}
