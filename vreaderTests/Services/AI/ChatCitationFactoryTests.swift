// Feature #86 WI-6: ChatCitationFactory — the provenance "Drew on" citations from
// (scope, sources, counts, whole-book coverage), and ChatMessage carrying them.

import Testing
import Foundation
@testable import vreader

@Suite("ChatCitationFactory (Feature #86 WI-6)")
struct ChatCitationFactoryTests {

    private let allCounts = (notes: 3, highlights: 5, bookmarks: 2)

    @Test func always_includesTheScopeCitation() {
        let c = ChatCitationFactory.citations(
            scope: .chapter, sources: ChatSourceSelection(notes: false, highlights: false, bookmarks: false),
            counts: (0, 0, 0)
        )
        #expect(c.count == 1)
        #expect(c.first?.sourceKind == .scope)
        #expect(c.first?.label == "Chapter")
    }

    @Test func sourceCitations_onlyWhenOnAndNonEmpty() {
        // Notes on + has items → cited; highlights on but 0 → not; bookmarks off → not.
        let c = ChatCitationFactory.citations(
            scope: .chapter,
            sources: ChatSourceSelection(notes: true, highlights: true, bookmarks: false),
            counts: (notes: 4, highlights: 0, bookmarks: 9)
        )
        let kinds = c.map(\.sourceKind)
        #expect(kinds.contains(.note))         // on + 4 items
        #expect(!kinds.contains(.highlight))   // on but 0 items
        #expect(!kinds.contains(.bookmark))    // off
    }

    @Test func allSourcesOn_withItems_citesEach() {
        let c = ChatCitationFactory.citations(
            scope: .section, sources: .init(notes: true, highlights: true, bookmarks: true),
            counts: allCounts
        )
        let kinds = Set(c.map(\.sourceKind))
        #expect(kinds == [.scope, .note, .highlight, .bookmark])
    }

    @Test func wholeBook_addsSpoilerAwareSpanCitation() {
        let coverage = WholeBookCoverage(coveredSpans: [0...999], totalUTF16: 1000, droppedSpans: [])
        let c = ChatCitationFactory.citations(
            scope: .wholeBook, sources: .init(notes: false, highlights: false, bookmarks: false),
            counts: (0, 0, 0), wholeBookCoverage: coverage
        )
        let span = c.first { $0.sourceKind == .wholeBookSpan }
        #expect(span != nil)
        #expect(span?.aheadOfReader == true)       // whole-book reads pages ahead → spoiler
        #expect(span?.label == "the whole book")   // complete coverage
    }

    @Test func wholeBook_partialCoverage_labelsBookSoFar() {
        let coverage = WholeBookCoverage(coveredSpans: [0...499], totalUTF16: 1000, droppedSpans: [500...999])
        let c = ChatCitationFactory.citations(
            scope: .wholeBook, sources: .default, counts: allCounts, wholeBookCoverage: coverage
        )
        #expect(c.first { $0.sourceKind == .wholeBookSpan }?.label == "the book so far")
    }

    @Test func nonWholeBook_noSpanCitation_evenWithCoverage() {
        let coverage = WholeBookCoverage(coveredSpans: [0...999], totalUTF16: 1000, droppedSpans: [])
        let c = ChatCitationFactory.citations(
            scope: .chapter, sources: .default, counts: allCounts, wholeBookCoverage: coverage
        )
        #expect(!c.contains { $0.sourceKind == .wholeBookSpan })
    }

    @Test func chatMessage_carriesCitations() {
        let cites = [ChatCitation(sourceKind: .scope, label: "Chapter")]
        let msg = ChatMessage(role: .assistant, content: "hi", citations: cites)
        #expect(msg.citations == cites)
        // Default is empty (backward-compatible).
        #expect(ChatMessage(role: .user, content: "q").citations.isEmpty)
    }
}
