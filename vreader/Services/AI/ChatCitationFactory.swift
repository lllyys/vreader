// Purpose: Computes the provenance-first "Drew on" citations for an AI Chat reply
// from the context that was assembled (Feature #86 WI-6). Pure + testable; the
// coordinator feeds the result through `ChatContextAssembler.assemble`, which then
// RETAINS only the citations whose content survived the budget clamp.
//
// Citations are scope-level (not fabricated chapter ordinals — the WI-2
// provenance-first decision): the scope's display name, one per active+non-empty
// source kind, and — for Whole book — a spoiler-aware whole-book span citation.
//
// @coordinates-with: ChatCitation.swift, ChatContextAssembler.swift,
//   ChatContextScope.swift, ChatSourceSelection.swift, WholeBookReducer.swift,
//   ChatCitationRow.swift (the UI)

import Foundation

enum ChatCitationFactory {

    /// Builds the citation set for a context assembled from `scope` + `sources`.
    ///
    /// - Parameters:
    ///   - counts: per-book annotation counts (a source kind only cites when it's
    ///     toggled ON *and* has items).
    ///   - wholeBookCoverage: present when `scope == .wholeBook` and a read produced
    ///     coverage — adds a spoiler-aware whole-book span citation.
    static func citations(
        scope: ChatContextScope,
        sources: ChatSourceSelection,
        counts: (notes: Int, highlights: Int, bookmarks: Int),
        wholeBookCoverage: WholeBookCoverage? = nil
    ) -> [ChatCitation] {
        var result: [ChatCitation] = []

        // The reading scope itself.
        result.append(ChatCitation(sourceKind: .scope, label: scope.displayName))

        // The reader's own marks — only kinds that are ON and actually have items.
        if sources.notes, counts.notes > 0 {
            result.append(ChatCitation(sourceKind: .note, label: "your notes"))
        }
        if sources.highlights, counts.highlights > 0 {
            result.append(ChatCitation(sourceKind: .highlight, label: "your highlights"))
        }
        if sources.bookmarks, counts.bookmarks > 0 {
            result.append(ChatCitation(sourceKind: .bookmark, label: "your bookmarks"))
        }

        // Whole book reads pages ahead of the reader → spoiler-aware (amber chip).
        if scope == .wholeBook, let coverage = wholeBookCoverage, !coverage.coveredSpans.isEmpty {
            result.append(ChatCitation(
                sourceKind: .wholeBookSpan,
                label: coverage.isComplete ? "the whole book" : "the book so far",
                spanUTF16: coverage.coveredSpans.first,
                aheadOfReader: true
            ))
        }
        return result
    }
}
