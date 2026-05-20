// Purpose: Feature #60 WI-6 — slot/button enums consumed declaratively
// by the reader chrome views (`ReaderTopChrome`, `ReaderBottomChrome`).
// Centralising the slot identity here keeps the design contract
// (order, accessibility ids, accent slot) testable without depending
// on SwiftUI render machinery.
//
// Design source:
// `dev-docs/designs/vreader-fidelity-v1/project/vreader-reader.jsx`
// — `ReaderTopChrome` + `ReaderBottomChrome` layouts.

import Foundation

/// Slot identity in the top reader chrome. `title` is technically not
/// a button (it's a label), but it occupies a named slot in the layout
/// so the slot enum keeps the layout-order contract in one place.
///
/// Layout order, left → right, per the #760 design supplement
/// (`design-notes/reader-search-and-more-menu.md` §1) +
/// feature #56 WI-9 (`vreader-bilingual.jsx`):
/// `← Library  |  Title [↔ BilingualPill]  |  🔍 Search  📑 Bookmark  ⋯ More`.
/// WI-6a shipped this enum, WI-6b added `.search`, feature #56 WI-9
/// inserts `.bilingualPill` between `.title` and `.search` — sits
/// inline with the title block per design.
enum ReaderTopChromeSlot: String, CaseIterable, Equatable {
    case back
    case title
    /// Feature #56 WI-9 — `EN ↔ <target>` pill, present only when
    /// bilingual mode is on for the open book. The chrome's
    /// `shouldShowBilingualPill(...)` gates the render path.
    case bilingualPill
    case search
    case bookmark
    case more

    /// Accessibility identifier used by XCUITest + verify-cron
    /// snapshots. Stable contract — do not rename without updating
    /// every harness that looks them up. `readerSearchButton` keeps
    /// the identifier the legacy `ReaderChromeBar` already used for
    /// its search button, so no harness churn.
    var accessibilityIdentifier: String {
        switch self {
        case .back:          return "readerBackButton"
        case .title:         return "readerTitleLabel"
        case .bilingualPill: return "readerBilingualPill"
        case .search:        return "readerSearchButton"
        case .bookmark:      return "readerBookmarkButton"
        case .more:          return "readerMoreButton"
        }
    }
}

/// Button identity in the bottom reader chrome toolbar. The 4 buttons
/// match the design's `[Contents, Notes, Display, AI]` array (with AI
/// painted in the accent color as the "primary" action of the
/// toolbar).
enum ReaderBottomChromeButton: String, CaseIterable, Equatable {
    case contents
    case notes
    case display
    case ai

    /// Accessibility identifier used by XCUITest + verify-cron
    /// snapshots. Stable contract.
    var accessibilityIdentifier: String {
        switch self {
        case .contents: return "readerContentsButton"
        case .notes:    return "readerNotesButton"
        case .display:  return "readerDisplayButton"
        case .ai:       return "readerAIButton"
        }
    }

    /// Whether the button uses the theme's `accentColor` instead of
    /// `inkColor`. Design renders only one accent slot in the bottom
    /// toolbar — the AI action — so the rest stay on ink.
    var isAccent: Bool {
        self == .ai
    }
}
