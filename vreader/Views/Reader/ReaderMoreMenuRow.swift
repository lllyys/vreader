// Purpose: Feature #60 WI-6c — row identity for the reader More-menu
// popover (`ReaderMorePopover`). Centralising the row contract here
// keeps the design's layout (order, divider, labels, icons, toggle vs
// tap, state-driven sub-detail, accessibility ids, notification
// routing) testable without depending on SwiftUI render machinery —
// the same pattern `ReaderChromeButton` uses for the top/bottom
// chrome.
//
// Design source:
// `dev-docs/designs/vreader-fidelity-v1/project/vreader-more.jsx`
// + `design-notes/reader-search-and-more-menu.md` §2.
//
// Scope note — Bilingual mode row omitted: `vreader-more.jsx` depicts
// six rows; WI-6c ships five. The "Bilingual mode" row is deferred
// because it has no backing surface — bilingual translation lives
// entirely in the AI assistant's translate tab (`AITranslationViewModel`
// + `TranslationResultCard`), invoked per selection; there is no persistent
// bilingual-mode toggle state. Rendering a fake toggle, or routing it
// as a tap row, would both diverge from the designed toggle (rule 51,
// self-designed UI). GH #790 tracks the backing feature + a design
// confirmation before the row returns.
//
// Routing note: each row maps 1:1 to a `Notification.Name` the
// `ReaderMorePopover` posts and `ReaderContainerView` observes. The
// host-side effect each row triggers is modelled by
// `ReaderMoreMenuEffect` (feature #61 WI-3).

import Foundation

/// A row in the reader More-menu popover. `CaseIterable.allCases`
/// returns the five rows in declared (top → bottom) order, matching
/// `vreader-more.jsx` minus the deferred Bilingual row (GH #790).
/// `ReaderMorePopover` renders them via
/// `ForEach(ReaderMoreMenuRow.allCases)`, inserting the hairline
/// divider after `dividerAfter`.
enum ReaderMoreMenuRow: String, CaseIterable, Equatable {
    case readAloud
    case autoTurnPages
    case bookDetails
    case shareBook
    case exportAnnotations

    /// The row after which the design draws its single hairline
    /// divider — splitting the reading-controls cluster (Read aloud /
    /// Auto-turn) from the book-action cluster (Book details / Share /
    /// Export). In the design the divider sits after Bilingual; with
    /// that row deferred (GH #790) it sits after Auto-turn — still the
    /// boundary between the two clusters.
    static let dividerAfter: ReaderMoreMenuRow = .autoTurnPages

    /// Notification posted on tap. `ReaderContainerView` observes all
    /// five and runs the matching action. The popover does not thread
    /// closures — posting keeps it composable in one place.
    var notification: Notification.Name {
        switch self {
        case .readAloud:         return .readerMoreReadAloud
        case .autoTurnPages:     return .readerMoreToggleAutoTurn
        case .bookDetails:       return .readerMoreBookDetails
        case .shareBook:         return .readerMoreShareBook
        case .exportAnnotations: return .readerMoreExportAnnotations
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
    /// reader engine advertises `capabilities`.
    ///
    /// Bug #176 / GH #602 (REOPENED): the `Read aloud` row is a no-op
    /// for formats that lack `.tts` (AZW3 / MOBI route through
    /// Foliate-js, and `FormatCapabilities.capabilities(for: .azw3)`
    /// excludes `.tts` because the AVSpeechSynthesizer pipeline has no
    /// azw3/mobi text-extraction path). The original fix removed `.tts`
    /// from the capability set, but WI-6c's popover re-surfaced the row
    /// unconditionally — this filter re-applies the gate so the no-op
    /// affordance never appears.
    ///
    /// Declared (top → bottom) order is preserved — `ReaderMorePopover`
    /// draws its hairline divider after `dividerAfter` by index, so the
    /// filter must not reorder. `dividerAfter` (`.autoTurnPages`) has
    /// no capability requirement, so the divider anchor always
    /// survives.
    ///
    /// - Parameter capabilities: the active format's capability set, or
    ///   `nil` for callers that don't supply one (previews / older
    ///   tests / legacy call sites). A `nil` set yields every row —
    ///   the same permissive default as the bug #156 auto-page-turn
    ///   and bug #158 reading-mode gates.
    /// - Returns: the rows to render, in declared order.
    static func visibleRows(
        for capabilities: FormatCapabilities?
    ) -> [ReaderMoreMenuRow] {
        allCases.filter { $0.isVisible(for: capabilities) }
    }

    /// Whether this row should be rendered for a book whose reader
    /// engine advertises `capabilities`. Only `.readAloud` is gated
    /// (on `.tts`); every other row is always visible. A `nil`
    /// capability set keeps the row (backward compat — see
    /// `visibleRows(for:)`).
    func isVisible(for capabilities: FormatCapabilities?) -> Bool {
        switch self {
        case .readAloud:
            guard let caps = capabilities else { return true }
            return caps.contains(.tts)
        case .autoTurnPages, .bookDetails, .shareBook, .exportAnnotations:
            return true
        }
    }

    /// Whether the row renders an inline iOS-style toggle switch
    /// instead of a chevron. Only `autoTurnPages` is a toggle — it has
    /// backing state (`ReaderSettingsStore.autoPageTurn`). (The design
    /// also draws Bilingual as a toggle, but that row is deferred —
    /// see the file header + GH #790.)
    var isToggle: Bool {
        self == .autoTurnPages
    }

    /// User-facing primary label. Matches the design bundle text.
    var label: String {
        switch self {
        case .readAloud:         return "Read aloud"
        case .autoTurnPages:     return "Auto-turn pages"
        case .bookDetails:       return "Book details"
        case .shareBook:         return "Share book"
        case .exportAnnotations: return "Export annotations"
        }
    }

    /// SF Symbol rendered in the row's leading icon chip. Mapped to
    /// the design's icon family: Volume → `speaker.wave.2`, Timer →
    /// `timer`, Info → `info.circle`, Share → `square.and.arrow.up`,
    /// Download → `arrow.down.doc`.
    var systemImage: String {
        switch self {
        case .readAloud:         return "speaker.wave.2"
        case .autoTurnPages:     return "timer"
        case .bookDetails:       return "info.circle"
        case .shareBook:         return "square.and.arrow.up"
        case .exportAnnotations: return "arrow.down.doc"
        }
    }

    /// Stable accessibility identifier for XCUITest + verify-cron
    /// snapshots. Stable contract — do not rename without updating
    /// every harness.
    var accessibilityIdentifier: String {
        switch self {
        case .readAloud:         return "readerMoreReadAloud"
        case .autoTurnPages:     return "readerMoreAutoTurn"
        case .bookDetails:       return "readerMoreBookDetails"
        case .shareBook:         return "readerMoreShareBook"
        case .exportAnnotations: return "readerMoreExportAnnotations"
        }
    }

    // MARK: - State-driven secondary text

    /// Secondary (sub-detail) line shown under the label, or `nil`
    /// when the row has none. Mirrors the design's `Row sub={...}`
    /// expressions in `vreader-more.jsx`, which update with reader
    /// state.
    ///
    /// - Parameters:
    ///   - ttsPlaying: whether read-aloud is currently speaking.
    ///   - autoTurnOn: whether auto-page-turn is enabled.
    ///   - autoTurnInterval: the auto-turn interval in seconds. Used
    ///     only when `autoTurnOn` is true; rendered as a whole-second
    ///     integer clamped to the design's 1...60 range.
    func subDetail(
        ttsPlaying: Bool, autoTurnOn: Bool, autoTurnInterval: Double
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
    /// row. Only the two stateful rows can be active.
    func isActive(ttsPlaying: Bool, autoTurnOn: Bool) -> Bool {
        switch self {
        case .readAloud:     return ttsPlaying
        case .autoTurnPages: return autoTurnOn
        case .bookDetails, .shareBook, .exportAnnotations:
            return false
        }
    }
}
