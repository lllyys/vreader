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

@Suite("ChatContextAssembler per-section retention (Feature #86 WI-6)")
struct ChatContextAssemblerSectionRetentionTests {

    /// Gate-4 WI-6: a partial clamp that keeps the Notes section but cuts the
    /// Bookmarks section retains the note citation and drops only the bookmark
    /// citation — not all-or-nothing.
    @Test func partialClamp_retainsSurvivingSectionsOnly() {
        let block = "[Your notes & marks]\nNotes:\n- mynote\n\n"
            + String(repeating: "x", count: 200)
            + "\n\nBookmarks:\n- mybm"
        let cites = [
            ChatCitation(sourceKind: .scope, label: "Chapter"),
            ChatCitation(sourceKind: .note, label: "your notes"),
            ChatCitation(sourceKind: .bookmark, label: "your bookmarks"),
        ]
        let a = ChatContextAssembler.assemble(
            scopeText: "s", annotationBlock: block, citations: cites, maxUTF16: 60
        )
        #expect(a.bookContext.contains("Notes:"))          // notes section survived
        #expect(!a.bookContext.contains("Bookmarks:"))     // bookmarks clamped off
        let kinds = a.citations.map(\.sourceKind)
        #expect(kinds.contains(.scope))                    // scope always kept
        #expect(kinds.contains(.note))                     // its section survived → kept
        #expect(!kinds.contains(.bookmark))                // its section cut → dropped
    }

    /// Gate-4 WI-6 round-3: a clamp that leaves only the section HEADER + bullet
    /// marker but NO item content drops the citation (the first item must survive,
    /// not merely the header — closes the `contains(header)` false positive).
    @Test func headerSurvivesButItemCut_dropsCitation() {
        let block = "[Your notes & marks]\nNotes:\n- mynote"
        // The combined prefix exactly through the first bullet marker "- " — no
        // item content fits.
        let prefixThroughMarker = "s\n\n[Your notes & marks]\nNotes:\n- "
        let cites = [
            ChatCitation(sourceKind: .scope, label: "Chapter"),
            ChatCitation(sourceKind: .note, label: "your notes"),
        ]
        let a = ChatContextAssembler.assemble(
            scopeText: "s", annotationBlock: block, citations: cites,
            maxUTF16: prefixThroughMarker.utf16.count
        )
        #expect(!a.citations.map(\.sourceKind).contains(.note))   // no item content → dropped
        #expect(a.citations.map(\.sourceKind).contains(.scope))   // scope still kept
    }

    /// Scope text that EXACTLY matches the section line shape (`\nNotes:\n- …`)
    /// must NOT false-retain a citation — retention searches only the annotation
    /// block, never the scope text.
    @Test func headerLineShapeInScopeContent_doesNotFalseRetain() {
        let a = ChatContextAssembler.assemble(
            scopeText: "A passage.\nNotes:\n- a fake bullet in the prose.\nThe end.",
            annotationBlock: "",   // NO real annotation block
            citations: [ChatCitation(sourceKind: .note, label: "your notes")],
            maxUTF16: 10_000
        )
        #expect(!a.citations.contains { $0.sourceKind == .note })   // prose match doesn't count
    }
}
