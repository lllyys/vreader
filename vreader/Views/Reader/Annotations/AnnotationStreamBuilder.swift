// Purpose: Feature #62 WI-1 — the pure builder for `HighlightsSheet`'s
// unified card stream + filter-chip counts.
//
// The committed #860 design (`vreader-notes-unified.jsx`) folds the two
// fetched record kinds into one chronological stream and computes the
// four filter-chip counts in JS. This type is the Swift home of that
// logic so it is unit-testable without a SwiftUI render path — the same
// pure-design-data pattern `SheetSectionContract` / `LibraryCardTokens`
// use.
//
// Count semantics, pinned to `vreader-notes-unified.jsx` lines 84-90:
//   all        = highlights.count + annotations.count
//   highlights = highlights.count
//   notes      = annotations.count
//                + highlights.filter { note non-empty }.count
//   bookmarks  = 0  — the Bookmarks chip in HighlightsSheet is empty
//                     (the real bookmark surface is TOCSheet's
//                     Bookmarks tab).
//
// @coordinates-with: AnnotationStreamItem.swift, AnnotationsSheetRoute.swift,
//   HighlightsSheet.swift, AnnotationStreamBuilderTests.swift

import Foundation

/// Pure builder — input the two fetched record arrays, output the
/// filtered + chronologically-sorted stream and the four filter-chip
/// counts. No SwiftUI.
enum AnnotationStreamBuilder {

    /// Builds the filtered card stream, newest-first by `createdAt`.
    ///
    /// - `.all` — the union of every highlight + standalone note.
    /// - `.highlights` — only `HighlightRecord` items.
    /// - `.notes` — standalone notes PLUS highlights that carry a
    ///   non-empty note (the #860 "notes are notes regardless of
    ///   anchor" semantics).
    /// - `.bookmarks` — always empty (the Bookmarks surface is
    ///   `TOCSheet`'s Bookmarks tab).
    ///
    /// Ties on equal `createdAt` are broken by the record `id` so the
    /// order is deterministic.
    static func stream(
        highlights: [HighlightRecord],
        annotations: [AnnotationRecord],
        filter: HighlightsSheetFilter
    ) -> [AnnotationStreamItem] {
        let items: [AnnotationStreamItem]
        switch filter {
        case .all:
            items = highlights.map(AnnotationStreamItem.highlight)
                + annotations.map(AnnotationStreamItem.standalone)
        case .highlights:
            items = highlights.map(AnnotationStreamItem.highlight)
        case .notes:
            let annotatedHighlights = highlights
                .filter { $0.note?.isEmpty == false }
                .map(AnnotationStreamItem.highlight)
            items = annotations.map(AnnotationStreamItem.standalone)
                + annotatedHighlights
        case .bookmarks:
            return []
        }
        return items.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt   // newest-first
            }
            // Tie-break: id, then kind — a total order even in the
            // pathological case where a highlight and a standalone note
            // share both timestamp and UUID.
            if lhs.id != rhs.id {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.kindRank < rhs.kindRank
        }
    }

    /// Computes the four filter-chip counts per the #860 design
    /// semantics. The `.bookmarks` count is a hard `0`.
    static func counts(
        highlights: [HighlightRecord],
        annotations: [AnnotationRecord]
    ) -> [HighlightsSheetFilter: Int] {
        let annotatedHighlightCount = highlights
            .filter { $0.note?.isEmpty == false }
            .count
        return [
            .all:        highlights.count + annotations.count,
            .highlights: highlights.count,
            .notes:      annotations.count + annotatedHighlightCount,
            .bookmarks:  0,
        ]
    }
}
