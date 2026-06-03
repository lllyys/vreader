// Feature #86 WI-2: the pure foundation types for the Chat context bar —
// ChatContextScope, ChatSourceSelection, ChatCitation, ChatAnnotationContext
// (the annotation serializer), and ChatContextAssembler (the context funnel).
// No UI, no VM wiring — those are WI-3+.

import Testing
import Foundation
@testable import vreader

// MARK: - Record builders

private let wi2FP = DocumentFingerprint(
    contentSHA256: String(repeating: "c", count: 64),
    fileByteCount: 2048, format: .txt
)

private func loc(_ offset: Int) -> Locator {
    LocatorFactory.txtPosition(fingerprint: wi2FP, charOffsetUTF16: offset)!
}

private func highlight(
    _ text: String, note: String? = nil, color: String = "yellow",
    at offset: Int = 0, created: TimeInterval = 0
) -> HighlightRecord {
    HighlightRecord(
        highlightId: UUID(), locator: loc(offset), anchor: nil,
        profileKey: "\(wi2FP.canonicalKey):\(offset)", selectedText: text,
        color: color, note: note,
        createdAt: Date(timeIntervalSince1970: created),
        updatedAt: Date(timeIntervalSince1970: created)
    )
}

private func bookmark(
    _ title: String?, at offset: Int = 0, created: TimeInterval = 0
) -> BookmarkRecord {
    BookmarkRecord(
        bookmarkId: UUID(), locator: loc(offset),
        profileKey: "\(wi2FP.canonicalKey):\(offset)", title: title,
        createdAt: Date(timeIntervalSince1970: created),
        updatedAt: Date(timeIntervalSince1970: created)
    )
}

private func note(
    _ content: String, at offset: Int = 0, created: TimeInterval = 0
) -> AnnotationRecord {
    AnnotationRecord(
        annotationId: UUID(), locator: loc(offset),
        profileKey: "\(wi2FP.canonicalKey):\(offset)", content: content,
        createdAt: Date(timeIntervalSince1970: created),
        updatedAt: Date(timeIntervalSince1970: created)
    )
}

// MARK: - ChatContextScope

@Suite("ChatContextScope (Feature #86 WI-2)")
struct ChatContextScopeTests {

    @Test func defaultScope_isChapter_matchingWI1() {
        #expect(ChatContextScope.defaultScope == .chapter)
    }

    @Test func summaryScope_mapsFirstThree_wholeBookIsNil() {
        #expect(ChatContextScope.section.summaryScope == .section)
        #expect(ChatContextScope.chapter.summaryScope == .chapter)
        #expect(ChatContextScope.bookSoFar.summaryScope == .bookSoFar)
        #expect(ChatContextScope.wholeBook.summaryScope == nil)
    }

    @Test func onDemand_andSpoilerAware_onlyWholeBook() {
        for scope in ChatContextScope.allCases where scope != .wholeBook {
            #expect(!scope.isOnDemand)
            #expect(!scope.spoilerAware)
        }
        #expect(ChatContextScope.wholeBook.isOnDemand)
        #expect(ChatContextScope.wholeBook.spoilerAware)
    }

    @Test func displayNames_matchDesign() {
        #expect(ChatContextScope.section.displayName == "Section")
        #expect(ChatContextScope.chapter.displayName == "Chapter")
        #expect(ChatContextScope.bookSoFar.displayName == "Book so far")
        #expect(ChatContextScope.wholeBook.displayName == "Whole book")
    }

    @Test func allCases_renderOrderMatchesMenu() {
        #expect(ChatContextScope.allCases == [.section, .chapter, .bookSoFar, .wholeBook])
    }
}

// MARK: - ChatSourceSelection

@Suite("ChatSourceSelection (Feature #86 WI-2)")
struct ChatSourceSelectionTests {

    @Test func defaultSelection_notesAndHighlightsOn_bookmarksOff() {
        let d = ChatSourceSelection.default
        #expect(d.notes)
        #expect(d.highlights)
        #expect(!d.bookmarks)
        #expect(d.activeCount == 2)
        #expect(!d.allOff)
    }

    @Test func activeCount_countsToggledKinds() {
        #expect(ChatSourceSelection(notes: true, highlights: true, bookmarks: true).activeCount == 3)
        #expect(ChatSourceSelection(notes: true, highlights: false, bookmarks: false).activeCount == 1)
    }

    @Test func allOff_whenNothingSelected() {
        let off = ChatSourceSelection(notes: false, highlights: false, bookmarks: false)
        #expect(off.allOff)
        #expect(off.activeCount == 0)
    }
}

// MARK: - ChatCitation

@Suite("ChatCitation (Feature #86 WI-2)")
struct ChatCitationTests {

    @Test func provenanceFields_defaultToNil_notFabricated() {
        let c = ChatCitation(sourceKind: .scope, label: "Chapter")
        #expect(c.locator == nil)        // EPUB no-offset → no anchor
        #expect(c.spanUTF16 == nil)
        #expect(c.sequence == nil)        // never a fabricated ordinal
        #expect(!c.aheadOfReader)
    }

    @Test func aheadOfReader_flagsWholeBookSpoiler() {
        let c = ChatCitation(
            sourceKind: .wholeBookSpan, label: "Ch. 7",
            spanUTF16: 1000...2000, sequence: 7, aheadOfReader: true
        )
        #expect(c.aheadOfReader)
        #expect(c.spanUTF16 == 1000...2000)
        #expect(c.sequence == 7)
    }

    @Test func equatable_byValueIgnoringId() {
        let a = ChatCitation(id: UUID(), sourceKind: .note, label: "your note")
        let b = ChatCitation(id: UUID(), sourceKind: .note, label: "your note")
        // Distinct ids → not equal (Identifiable carries identity).
        #expect(a != b)
    }
}

// MARK: - ChatAnnotationContext

@Suite("ChatAnnotationContext (Feature #86 WI-2)")
struct ChatAnnotationContextTests {

    @Test func counts_notesAreStandalonePlusAnnotatedHighlights() {
        let annotations = [note("standalone A"), note("standalone B")]
        let highlights = [
            highlight("h1", note: "a note"),       // annotated → counts as a note
            highlight("h2", note: "   "),          // whitespace note → NOT a note
            highlight("h3"),                       // no note
        ]
        let bookmarks = [bookmark("bm1")]
        let c = ChatAnnotationContext.counts(
            annotations: annotations, highlights: highlights, bookmarks: bookmarks
        )
        #expect(c.notes == 3)        // 2 standalone + 1 annotated highlight
        #expect(c.highlights == 3)
        #expect(c.bookmarks == 1)
    }

    @Test func serialize_allOff_isEmpty() {
        let out = ChatAnnotationContext.serialize(
            annotations: [note("n")], highlights: [highlight("h")], bookmarks: [bookmark("b")],
            selection: ChatSourceSelection(notes: false, highlights: false, bookmarks: false),
            maxUTF16: 10_000
        )
        #expect(out.isEmpty)
    }

    @Test func serialize_selectsOnlyToggledKinds() {
        let out = ChatAnnotationContext.serialize(
            annotations: [note("my note")],
            highlights: [highlight("highlighted phrase")],
            bookmarks: [bookmark("my bookmark")],
            selection: ChatSourceSelection(notes: true, highlights: false, bookmarks: false),
            maxUTF16: 10_000
        )
        #expect(out.contains("my note"))
        #expect(!out.contains("highlighted phrase"))
        #expect(!out.contains("my bookmark"))
        #expect(out.contains("[Your notes & marks]"))
    }

    @Test func serialize_notesIncludeAnnotatedHighlightNotes() {
        let out = ChatAnnotationContext.serialize(
            annotations: [],
            highlights: [highlight("phrase", note: "the reader's words")],
            bookmarks: [],
            selection: ChatSourceSelection(notes: true, highlights: false, bookmarks: false),
            maxUTF16: 10_000
        )
        #expect(out.contains("the reader's words"))
    }

    @Test func serialize_empty_whenNothingMatches() {
        let out = ChatAnnotationContext.serialize(
            annotations: [], highlights: [], bookmarks: [],
            selection: .default, maxUTF16: 10_000
        )
        #expect(out.isEmpty)
    }

    @Test func serialize_budgetCap_clampsUTF16() {
        let big = note(String(repeating: "字", count: 5000))   // 5000 UTF-16 units
        let out = ChatAnnotationContext.serialize(
            annotations: [big], highlights: [], bookmarks: [],
            selection: ChatSourceSelection(notes: true, highlights: false, bookmarks: false),
            maxUTF16: 200
        )
        #expect(out.utf16.count <= 200)
    }

    @Test func serialize_newestFirst() {
        let out = ChatAnnotationContext.serialize(
            annotations: [note("older", created: 100), note("newer", created: 200)],
            highlights: [], bookmarks: [],
            selection: ChatSourceSelection(notes: true, highlights: false, bookmarks: false),
            maxUTF16: 10_000
        )
        let newerIdx = out.range(of: "newer")!.lowerBound
        let olderIdx = out.range(of: "older")!.lowerBound
        #expect(newerIdx < olderIdx)
    }

    @Test func serialize_prefixesLocatorLabel() {
        let out = ChatAnnotationContext.serialize(
            annotations: [note("my note", at: 1500)],
            highlights: [highlight("a phrase", at: 42)],
            bookmarks: [bookmark("bm", at: 7)],
            selection: .init(notes: true, highlights: true, bookmarks: true),
            maxUTF16: 10_000
        )
        #expect(out.contains("[@1500] my note"))     // TXT note → "@offset"
        #expect(out.contains("[@42] \"a phrase\""))   // highlight quoted, labeled
        #expect(out.contains("[@7] bm"))
    }

    @Test func locatorLabel_perFormat() {
        let txt = LocatorFactory.txtPosition(fingerprint: wi2FP, charOffsetUTF16: 99)!
        #expect(ChatAnnotationContext.locatorLabel(txt) == "@99")
    }

    /// Gate-4 Low: the serializer's clamp keeps output within budget for ZWJ text.
    @Test func serialize_clampStaysWithinBudget_forZWJText() {
        let family = "👨‍👩‍👧‍👦"   // one ZWJ grapheme, 11 UTF-16 units
        let out = ChatAnnotationContext.serialize(
            annotations: [note(String(repeating: family, count: 20))],
            highlights: [], bookmarks: [],
            selection: ChatSourceSelection(notes: true, highlights: false, bookmarks: false),
            maxUTF16: 40
        )
        #expect(out.utf16.count <= 40)
    }
}

// MARK: - UTF16Clamp (the shared grapheme-safe clamp)

@Suite("UTF16Clamp (Feature #86 WI-2)")
struct UTF16ClampTests {

    /// Proves the clamp never splits a ZWJ grapheme cluster: the result is an
    /// EXACT prefix of whole family-emoji repetitions, not a partial cluster.
    @Test func clamp_neverSplitsZWJGrapheme() {
        let family = "👨‍👩‍👧‍👦"   // 11 UTF-16 units, ONE Character
        let s = String(repeating: family, count: 5)   // 55 UTF-16 units
        // 25 fits two whole families (22 units), not three (33).
        let out = UTF16Clamp.clamp(s, maxUTF16: 25)
        #expect(out == String(repeating: family, count: 2))   // exact whole-cluster prefix
        #expect(out.count == 2)                                // 2 Characters, no partial cluster
        #expect(out.utf16.count <= 25)
    }

    /// Proves the clamp never splits a surrogate pair (single BMP-pair emoji).
    @Test func clamp_neverSplitsSurrogatePair() {
        let apple = "🍎"                               // 2 UTF-16 units, one scalar
        let s = String(repeating: apple, count: 10)    // 20 units
        // 5 is an ODD budget that bisects a pair → must snap DOWN to 2 apples (4).
        let out = UTF16Clamp.clamp(s, maxUTF16: 5)
        #expect(out == String(repeating: apple, count: 2))
        #expect(!out.unicodeScalars.contains("\u{FFFD}"))
    }

    @Test func clamp_underBudget_isUnchanged() {
        #expect(UTF16Clamp.clamp("hello", maxUTF16: 100) == "hello")
    }

    @Test func clamp_zeroOrNegativeBudget_isEmpty() {
        #expect(UTF16Clamp.clamp("hello", maxUTF16: 0).isEmpty)
        #expect(UTF16Clamp.clamp("hello", maxUTF16: -3).isEmpty)
    }
}

// MARK: - ChatContextAssembler

@Suite("ChatContextAssembler (Feature #86 WI-2)")
struct ChatContextAssemblerTests {

    @Test func assemble_scopeThenAnnotationBlock() {
        let a = ChatContextAssembler.assemble(
            scopeText: "chapter text here",
            annotationBlock: "[Your notes & marks]\nNotes:\n- a", citations: [],
            maxUTF16: 10_000
        )
        let scopeIdx = a.bookContext.range(of: "chapter text")!.lowerBound
        let blockIdx = a.bookContext.range(of: "Your notes")!.lowerBound
        #expect(scopeIdx < blockIdx)
    }

    @Test func assemble_emptyAnnotationBlock_isJustScope() {
        let a = ChatContextAssembler.assemble(
            scopeText: "scope only",
            annotationBlock: "", citations: [], maxUTF16: 10_000
        )
        #expect(a.bookContext == "scope only")
    }

    @Test func assemble_passesCitationsThrough_whenAllSurvive() {
        let cites = [ChatCitation(sourceKind: .scope, label: "Chapter")]
        let a = ChatContextAssembler.assemble(
            scopeText: "t", annotationBlock: "", citations: cites,
            maxUTF16: 10_000
        )
        #expect(a.citations == cites)
    }

    @Test func assemble_budgetCap_clamps() {
        let a = ChatContextAssembler.assemble(
            scopeText: String(repeating: "字", count: 5000),
            annotationBlock: "tail", citations: [], maxUTF16: 300
        )
        #expect(a.bookContext.utf16.count <= 300)
    }

    @Test func assemble_zeroBudget_isEmpty_clearsCitations() {
        let cites = [ChatCitation(sourceKind: .scope, label: "Section")]
        let a = ChatContextAssembler.assemble(
            scopeText: "x", annotationBlock: "y", citations: cites,
            maxUTF16: 0
        )
        #expect(a.bookContext.isEmpty)
        #expect(a.citations.isEmpty)   // Gate-4 High: empty context → no provenance
    }

    /// Gate-4 High: when the clamp trims the annotation block away, the
    /// annotation-derived citations are dropped (the scope citation survives).
    @Test func assemble_clampTrimsBlock_dropsAnnotationCitations() {
        let cites = [
            ChatCitation(sourceKind: .scope, label: "Chapter"),
            ChatCitation(sourceKind: .note, label: "your note"),
            ChatCitation(sourceKind: .highlight, label: "a highlight"),
        ]
        // Budget fits the scope text but cuts into the annotation block.
        let a = ChatContextAssembler.assemble(
            scopeText: String(repeating: "字", count: 100),
            annotationBlock: "[Your notes & marks]\nNotes:\n- " + String(repeating: "x", count: 500),
            citations: cites, maxUTF16: 100
        )
        #expect(a.citations.map(\.sourceKind) == [.scope])
    }

    /// When the whole block fits, annotation citations are retained.
    @Test func assemble_blockFits_retainsAnnotationCitations() {
        let cites = [
            ChatCitation(sourceKind: .scope, label: "Chapter"),
            ChatCitation(sourceKind: .note, label: "your note"),
        ]
        let a = ChatContextAssembler.assemble(
            scopeText: "short scope",
            annotationBlock: "[Your notes & marks]\nNotes:\n- a short note",
            citations: cites, maxUTF16: 10_000
        )
        #expect(a.citations.count == 2)
    }
}
