// Purpose: The breadth of book text the in-reader AI Chat tab reads — drives
// the Chat context-bar scope chip + scope menu (Section / Chapter / Book so far
// / Whole book). The Chat equivalent of `SummaryScope` (which drives the
// Summarize tab), but Chat adds a 4th on-demand `.wholeBook` case, so it can NOT
// reuse `SummaryScope` (whose `CaseIterable` drives the 3-chip Summarize strip).
//
// Key decisions:
// - The first three cases map 1:1 onto `SummaryScope` (`summaryScope`), so the
//   shared `AIContextExtractor`/`SummaryScopeResolver` machinery is reused.
// - `.wholeBook` is on-demand (retrieved, not a synchronous slice) and the only
//   spoiler-aware scope (it can reference pages ahead of the reader).
// - `defaultScope == .chapter` matches shipped Feature #86 WI-1.
//
// @coordinates-with: SummaryScope.swift, ChatContextAssembler.swift,
//   ChatContextBar.swift (WI-3),
//   `dev-docs/designs/vreader-fidelity-v1/project/design-notes/chat-ai-scope-sources.md`

import Foundation

/// The breadth of book text the AI Chat tab reads. Feature #86 WI-2+.
///
/// `allCases` order is the scope-menu render order — `[.section, .chapter,
/// .bookSoFar, .wholeBook]` — matching the committed #1455 design.
enum ChatContextScope: String, CaseIterable, Sendable, Equatable {
    /// The current ~2500-char window around the reading position.
    case section
    /// The TOC-chapter-bounded slice around the locator (== shipped WI-1).
    case chapter
    /// A token-capped prefix from the book's start up to the locator.
    case bookSoFar
    /// The entire book, including pages ahead — retrieved on demand.
    case wholeBook

    /// The matching `SummaryScope` for the three bounded scopes, reusing
    /// `AIContextExtractor`. `.wholeBook` has no synchronous equivalent → `nil`.
    var summaryScope: SummaryScope? {
        switch self {
        case .section:   return .section
        case .chapter:   return .chapter
        case .bookSoFar: return .bookSoFar
        case .wholeBook: return nil
        }
    }

    /// `.wholeBook` is the only scope that reads on demand (a retrieval), not a
    /// synchronous slice of already-loaded text.
    var isOnDemand: Bool { self == .wholeBook }

    /// `.wholeBook` is the only scope that can reference pages ahead of the
    /// reader, so it is the only one that can surface spoilers. Every other
    /// scope is spoiler-safe by construction (it only reads what's been read).
    var spoilerAware: Bool { self == .wholeBook }

    /// The chip / menu label. Matches the design strings exactly.
    var displayName: String {
        switch self {
        case .section:   return "Section"
        case .chapter:   return "Chapter"
        case .bookSoFar: return "Book so far"
        case .wholeBook: return "Whole book"
        }
    }

    /// The default scope — `.chapter`, matching shipped Feature #86 WI-1.
    static var defaultScope: ChatContextScope { .chapter }
}
