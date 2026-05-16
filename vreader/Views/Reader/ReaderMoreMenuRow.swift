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
// Routing note: each row maps 1:1 to a `Notification.Name` the
// `ReaderMorePopover` posts and `ReaderContainerView` observes. Two
// rows route to interim/adjacent destinations because their designed
// destination is not yet a committed design:
//   - `.bilingualMode` — the design draws a toggle, but inline
//     bilingual rendering has no backing state; it routes to the AI
//     assistant's translate tab (the existing bilingual surface), so
//     it renders as a tap row, not a toggle.
//   - `.bookDetails` — the Book Details sheet is undesigned (design
//     note §4 defers it; GH #789 tracks it). It routes to the reader
//     settings panel — the design prototype's own interim punt
//     (`vreader-more.jsx` / `vreader-reader.jsx`:
//     `onAction('details') → onOpenSettings`).

import Foundation

/// A row in the reader More-menu popover. `CaseIterable.allCases`
/// returns the six rows in declared (top → bottom) order, matching
/// `vreader-more.jsx`. `ReaderMorePopover` renders them via
/// `ForEach(ReaderMoreMenuRow.allCases)`, inserting the hairline
/// divider after `dividerAfter`.
enum ReaderMoreMenuRow: String, CaseIterable, Equatable {
    case readAloud
    case autoTurnPages
    case bilingualMode
    case bookDetails
    case shareBook
    case exportAnnotations

    /// The row after which the design draws its single hairline
    /// divider — splitting the reading-controls cluster (Read aloud /
    /// Auto-turn / Bilingual) from the book-action cluster (Book
    /// details / Share / Export).
    static let dividerAfter: ReaderMoreMenuRow = .bilingualMode

    /// Notification posted on tap. `ReaderContainerView` observes all
    /// six and runs the matching action. The popover does not thread
    /// closures — posting keeps it composable in one place.
    var notification: Notification.Name {
        switch self {
        case .readAloud:         return .readerMoreReadAloud
        case .autoTurnPages:     return .readerMoreToggleAutoTurn
        case .bilingualMode:     return .readerMoreBilingual
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

    /// Whether the row renders an inline iOS-style toggle switch
    /// instead of a chevron. Only `autoTurnPages` is a real toggle —
    /// it has backing state (`ReaderSettingsStore.autoPageTurn`). The
    /// design also draws Bilingual as a toggle, but bilingual
    /// rendering lives entirely in the AI translate panel with no
    /// settings-level on/off state; WI-6c routes Bilingual to that
    /// existing surface as a tap row rather than fabricating a toggle.
    var isToggle: Bool {
        self == .autoTurnPages
    }

    /// User-facing primary label. Matches the design bundle text.
    var label: String {
        switch self {
        case .readAloud:         return "Read aloud"
        case .autoTurnPages:     return "Auto-turn pages"
        case .bilingualMode:     return "Bilingual mode"
        case .bookDetails:       return "Book details"
        case .shareBook:         return "Share book"
        case .exportAnnotations: return "Export annotations"
        }
    }

    /// SF Symbol rendered in the row's leading icon chip. Mapped to
    /// the design's icon family: Volume → `speaker.wave.2`, Timer →
    /// `timer`, Translate → `character.book.closed`, Info →
    /// `info.circle`, Share → `square.and.arrow.up`, Download →
    /// `arrow.down.doc`.
    var systemImage: String {
        switch self {
        case .readAloud:         return "speaker.wave.2"
        case .autoTurnPages:     return "timer"
        case .bilingualMode:     return "character.book.closed"
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
        case .bilingualMode:     return "readerMoreBilingual"
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
        case .bilingualMode:
            return "Translate inline"
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
        case .bilingualMode, .bookDetails, .shareBook, .exportAnnotations:
            return false
        }
    }
}
