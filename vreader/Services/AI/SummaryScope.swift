// Purpose: The breadth of text an AI summary covers — drives the
// AI Summarize tab's scope chips (Section / Chapter / Book so far)
// and feeds AIContextExtractor's scoped extraction.
//
// Key decisions:
// - String raw value gives a stable key for chip identity.
// - CaseIterable drives the chip ForEach in display order.
// - Equatable drives chip-selection comparison.
// - Sendable because it crosses into AIAssistantViewModel (@MainActor)
//   and the AIContextExtractor (Sendable struct).
//
// @coordinates-with: AIContextExtractor.swift, AIAssistantViewModel.swift,
//   AISummaryTabView.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx`

import Foundation

/// The breadth of text an AI summary covers. Drives `AIContextExtractor`.
///
/// `allCases` order is the chip-strip render order — `[.section,
/// .chapter, .bookSoFar]` — matching the committed design.
enum SummaryScope: String, CaseIterable, Sendable, Equatable {
    /// The current ~2500-char window around the reading position
    /// (today's behavior — what every summary used before #69).
    case section
    /// The TOC-chapter-bounded slice around the locator.
    case chapter
    /// A token-capped prefix from the book's start up to the locator.
    case bookSoFar

    /// The chip label shown in `SummaryView`. Matches the design strings
    /// in `vreader-panels.jsx` exactly.
    var displayName: String {
        switch self {
        case .section:   return "Section"
        case .chapter:   return "Chapter"
        case .bookSoFar: return "Book so far"
        }
    }
}
