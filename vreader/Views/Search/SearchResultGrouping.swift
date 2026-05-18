// Purpose: Feature #63 WI-2 — pure grouping logic behind the re-skinned
// grouped search results list. The design groups in-book search
// results "by chapter" (`vreader-search.jsx`); production
// `SearchResult` carries a single pre-formatted `sourceContext`
// location string (chapter-ish for EPUB, "Page N" for PDF, "Section N"
// for TXT/MD — see `SearchService.formatSourceContext`). Plan §3: the
// re-skin groups by that existing string — zero data-model change,
// keeping #63 a true behavior-preserving re-skin.
//
// Key decisions:
// - Pure value types + a stateless namespace — no SwiftUI dependency,
//   fully unit-testable without rendering.
// - **First-encountered order is preserved.** Groups appear in the
//   order their context is first seen in the result page, and results
//   within a group keep their arrival order — FTS5 hits for one
//   chapter need not be physically contiguous, but the rendered list
//   must stay stable and ordered. A plain `Dictionary` group-by would
//   lose this; the accumulator below keeps an explicit order list.
// - Empty `sourceContext` (a unit the resolver could not name) falls
//   back to a neutral display title so the list always has a header.
//
// @coordinates-with: SearchResultsGroupedList.swift,
//   SearchResult (SearchService.swift),
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-search.jsx`

import Foundation

/// One group of search results sharing a `sourceContext` location.
struct SearchResultGroup: Identifiable, Equatable {
    /// The shared `sourceContext` string — may be empty when the
    /// resolver could not name the source unit.
    let context: String
    /// The results in this group, in their original document order.
    let results: [SearchResult]

    /// Stable identifier for SwiftUI `List` / `ForEach` diffing — the
    /// context string uniquely identifies a group within one result set.
    var id: String { context }

    /// Neutral header shown when `context` is empty (plan risk §1 —
    /// format-neutral copy, not chapter-specific).
    static let unknownLocationTitle = "Location"

    /// The header text the grouped list renders — the `sourceContext`
    /// verbatim, or the neutral fallback when it is empty.
    var displayTitle: String {
        context.isEmpty ? Self.unknownLocationTitle : context
    }
}

/// Stateless grouping of a search result page by `sourceContext`.
enum SearchResultGrouping {

    /// Groups `results` by their `sourceContext`, preserving the
    /// first-encountered order of contexts and the arrival order of
    /// results within each context.
    static func group(_ results: [SearchResult]) -> [SearchResultGroup] {
        var order: [String] = []
        var buckets: [String: [SearchResult]] = [:]

        for result in results {
            let key = result.sourceContext
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = []
            }
            buckets[key]?.append(result)
        }

        return order.map { key in
            SearchResultGroup(context: key, results: buckets[key] ?? [])
        }
    }

    /// Total number of results across every group — the design's
    /// "{N} matches in {M} sections" count.
    static func totalMatchCount(_ groups: [SearchResultGroup]) -> Int {
        groups.reduce(0) { $0 + $1.results.count }
    }
}
