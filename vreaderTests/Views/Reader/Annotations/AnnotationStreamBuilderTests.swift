// Purpose: Feature #62 WI-1 — pins the #860 unified-card count + filter
// semantics.
//
// `AnnotationStreamBuilder` is the pure (Foundation-only) home of the
// design's count math + filter logic: it folds the two fetched record
// kinds (`HighlightRecord` + `AnnotationRecord`) into a single
// chronological card stream and computes the four filter-chip counts.
// The committed #860 design (`vreader-notes-unified.jsx`) builds that
// stream + counts in JS; this type is the Swift home so it is
// unit-testable without a SwiftUI render path.
//
// Count semantics pinned to `vreader-notes-unified.jsx` lines 84-90:
//   all        = highlights.count + annotations.count
//   highlights = highlights.count
//   notes      = annotations.count
//                + highlights.filter { note non-empty }.count
//   bookmarks  = 0   (the Bookmarks chip in HighlightsSheet is empty —
//                      the real bookmark surface is TOCSheet)
//
// @coordinates-with: AnnotationStreamItem.swift, AnnotationStreamBuilder.swift,
//   HighlightRecord.swift, AnnotationRecord.swift

import Testing
import Foundation
@testable import vreader

@Suite("Feature #62 — AnnotationStreamBuilder (#860 count + filter semantics)")
struct AnnotationStreamBuilderTests {

    // MARK: - Fixtures
    //
    // Built on the shared `WI9TestHelpers` factories so the records are
    // valid through `LocatorFactory`. `highlightId` / `annotationId` are
    // overridable via a post-construction rebuild because the shared
    // helpers do not expose the id parameter.

    private func makeHighlight(
        id: UUID? = nil,
        selectedText: String = "a passage",
        note: String? = nil,
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> HighlightRecord {
        let base = makeHighlightRecord(selectedText: selectedText, note: note, createdAt: createdAt)
        guard let id else { return base }
        return HighlightRecord(
            highlightId: id, locator: base.locator, anchor: base.anchor,
            profileKey: base.profileKey, selectedText: base.selectedText,
            color: base.color, note: base.note,
            createdAt: base.createdAt, updatedAt: base.updatedAt
        )
    }

    private func makeAnnotation(
        id: UUID? = nil,
        content: String = "a standalone note",
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> AnnotationRecord {
        let base = makeAnnotationRecord(content: content, createdAt: createdAt)
        guard let id else { return base }
        return AnnotationRecord(
            annotationId: id, locator: base.locator,
            profileKey: base.profileKey, content: base.content,
            createdAt: base.createdAt, updatedAt: base.updatedAt
        )
    }

    /// 3 highlights (1 carrying a note) + 2 standalone annotations.
    private func mixedSeed() -> (highlights: [HighlightRecord], annotations: [AnnotationRecord]) {
        let highlights = [
            makeHighlight(selectedText: "h1", note: nil),
            makeHighlight(selectedText: "h2", note: "this one has a note"),
            makeHighlight(selectedText: "h3", note: nil),
        ]
        let annotations = [
            makeAnnotation(content: "s1"),
            makeAnnotation(content: "s2"),
        ]
        return (highlights, annotations)
    }

    // MARK: - counts (the #860 semantics)

    @Test("counts: mixed seed — all/highlights/notes/bookmarks")
    func countsMixedSeed() {
        let seed = mixedSeed()
        let counts = AnnotationStreamBuilder.counts(
            highlights: seed.highlights,
            annotations: seed.annotations
        )
        #expect(counts[.all] == 5)          // 3 highlights + 2 standalones
        #expect(counts[.highlights] == 3)   // highlight records
        #expect(counts[.notes] == 3)        // 2 standalone + 1 annotated highlight
        #expect(counts[.bookmarks] == 0)    // hard 0 — design contract
    }

    @Test("counts: empty inputs are all zero")
    func countsEmptyInputs() {
        let counts = AnnotationStreamBuilder.counts(highlights: [], annotations: [])
        #expect(counts[.all] == 0)
        #expect(counts[.highlights] == 0)
        #expect(counts[.notes] == 0)
        #expect(counts[.bookmarks] == 0)
    }

    @Test("counts: a highlight with an empty-string note is NOT a note")
    func countsEmptyStringNoteNotCounted() {
        // The design's `h.note` truthiness check: an empty string is
        // falsy, so it is not a note. Swift: `note?.isEmpty == false`.
        let highlights = [
            makeHighlight(note: ""),       // empty string — not a note
            makeHighlight(note: "real"),   // a note
        ]
        let counts = AnnotationStreamBuilder.counts(highlights: highlights, annotations: [])
        #expect(counts[.highlights] == 2)
        #expect(counts[.notes] == 1)       // only the "real"-note highlight
    }

    @Test("counts + stream: large set — no fixed cap on either path")
    func countsLargeSet() {
        // 500 standalone annotations + 500 highlights of which 250 carry
        // a note — guards both the count math AND stream() against a
        // fixed cap / truncation bug (plan §5 large-set edge).
        let highlights = (0..<500).map { i in
            makeHighlight(note: i < 250 ? "note \(i)" : nil)
        }
        let annotations = (0..<500).map { _ in makeAnnotation() }
        let counts = AnnotationStreamBuilder.counts(highlights: highlights, annotations: annotations)
        #expect(counts[.all] == 1000)
        #expect(counts[.highlights] == 500)
        #expect(counts[.notes] == 750)   // 500 standalone + 250 annotated highlights

        // stream() must not cap either — the .all union and a filtered
        // stream both return their full record count.
        #expect(
            AnnotationStreamBuilder.stream(
                highlights: highlights, annotations: annotations, filter: .all
            ).count == 1000
        )
        #expect(
            AnnotationStreamBuilder.stream(
                highlights: highlights, annotations: annotations, filter: .highlights
            ).count == 500
        )
        #expect(
            AnnotationStreamBuilder.stream(
                highlights: highlights, annotations: annotations, filter: .notes
            ).count == 750
        )
    }

    @Test("counts: CJK note text classifies correctly (byte-agnostic)")
    func countsCJKNoteText() {
        let highlights = [makeHighlight(note: "这是一条笔记")]   // CJK note
        let annotations = [makeAnnotation(content: "独立笔记内容")]  // CJK standalone
        let counts = AnnotationStreamBuilder.counts(highlights: highlights, annotations: annotations)
        #expect(counts[.highlights] == 1)
        #expect(counts[.notes] == 2)   // CJK highlight-note + CJK standalone
    }

    // MARK: - stream — filtering

    @Test("stream(.highlights) returns only highlight items")
    func streamHighlightsFilter() {
        let seed = mixedSeed()
        let stream = AnnotationStreamBuilder.stream(
            highlights: seed.highlights, annotations: seed.annotations, filter: .highlights
        )
        #expect(stream.count == 3)
        for item in stream {
            if case .highlight = item { } else {
                Issue.record("stream(.highlights) yielded a non-highlight item")
            }
        }
    }

    @Test("stream(.notes) returns standalone notes + annotated highlights")
    func streamNotesFilter() {
        let seed = mixedSeed()
        let stream = AnnotationStreamBuilder.stream(
            highlights: seed.highlights, annotations: seed.annotations, filter: .notes
        )
        // 2 standalone + 1 annotated highlight = 3.
        #expect(stream.count == 3)
        // The annotated highlight stays a `.highlight` item — NOT
        // mis-cast to `.standalone`.
        let highlightItems = stream.filter { if case .highlight = $0 { return true } else { return false } }
        let standaloneItems = stream.filter { if case .standalone = $0 { return true } else { return false } }
        #expect(highlightItems.count == 1)
        #expect(standaloneItems.count == 2)
    }

    @Test("stream(.all) returns every record, interleaved")
    func streamAllFilter() {
        let seed = mixedSeed()
        let stream = AnnotationStreamBuilder.stream(
            highlights: seed.highlights, annotations: seed.annotations, filter: .all
        )
        #expect(stream.count == 5)
    }

    @Test("stream(.all) is newest-first by createdAt")
    func streamAllNewestFirst() {
        // Explicit createdAt values so the sort order is asserted, not
        // assumed.
        let oldest = makeHighlight(selectedText: "oldest", createdAt: Date(timeIntervalSince1970: 1_000))
        let middle = makeAnnotation(content: "middle", createdAt: Date(timeIntervalSince1970: 2_000))
        let newest = makeHighlight(selectedText: "newest", createdAt: Date(timeIntervalSince1970: 3_000))
        let stream = AnnotationStreamBuilder.stream(
            highlights: [oldest, newest], annotations: [middle], filter: .all
        )
        #expect(stream.count == 3)
        #expect(stream[0].createdAt == Date(timeIntervalSince1970: 3_000))
        #expect(stream[1].createdAt == Date(timeIntervalSince1970: 2_000))
        #expect(stream[2].createdAt == Date(timeIntervalSince1970: 1_000))
    }

    @Test("stream(.bookmarks) is empty")
    func streamBookmarksFilter() {
        let seed = mixedSeed()
        let stream = AnnotationStreamBuilder.stream(
            highlights: seed.highlights, annotations: seed.annotations, filter: .bookmarks
        )
        #expect(stream.isEmpty)
    }

    @Test("stream: empty inputs yield an empty stream for every filter")
    func streamEmptyInputs() {
        for filter in HighlightsSheetFilter.allCases {
            let stream = AnnotationStreamBuilder.stream(
                highlights: [], annotations: [], filter: filter
            )
            #expect(stream.isEmpty)
        }
    }

    @Test("stream(.notes) excludes a highlight with an empty-string note")
    func streamNotesExcludesEmptyStringNote() {
        let emptyNote = makeHighlight(selectedText: "empty", note: "")
        let realNote = makeHighlight(selectedText: "real", note: "kept")
        let stream = AnnotationStreamBuilder.stream(
            highlights: [emptyNote, realNote], annotations: [], filter: .notes
        )
        #expect(stream.count == 1)
        #expect(stream.first?.id == realNote.id)
    }

    @Test("stream(.all): tie-break on equal createdAt is by id, not source order")
    func streamAllTieBreakDeterministic() {
        // Three records sharing one timestamp. The tie-break must be the
        // id's uuidString ascending — A < B < C — REGARDLESS of the
        // order the records arrive in. Two seeds with reversed input
        // must both produce [A, B, C], proving the order is id-driven,
        // not incidental source ordering.
        let sameTime = Date(timeIntervalSince1970: 5_000)
        let idA = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
        let idB = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
        let idC = UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!
        let hA = makeHighlight(id: idA, createdAt: sameTime)
        let aB = makeAnnotation(id: idB, createdAt: sameTime)
        let hC = makeHighlight(id: idC, createdAt: sameTime)

        // Seed 1 — natural order.
        let forward = AnnotationStreamBuilder.stream(
            highlights: [hA, hC], annotations: [aB], filter: .all
        )
        #expect(forward.map(\.id) == [idA, idB, idC])

        // Seed 2 — reversed input arrays. Same id-ascending result.
        let reversed = AnnotationStreamBuilder.stream(
            highlights: [hC, hA], annotations: [aB], filter: .all
        )
        #expect(reversed.map(\.id) == [idA, idB, idC])
        #expect(forward.map(\.id) == reversed.map(\.id))
    }

    @Test("AnnotationStreamItem.kindRank — highlight ranks before standalone")
    func streamItemKindRank() {
        // The final tie-break in stream() — distinct ranks give a total
        // order even when a highlight and a standalone collide on
        // createdAt + id.
        #expect(AnnotationStreamItem.highlight(makeHighlight()).kindRank
                < AnnotationStreamItem.standalone(makeAnnotation()).kindRank)
    }

    // MARK: - AnnotationStreamItem

    @Test("AnnotationStreamItem id projects the underlying record id")
    func streamItemId() {
        let hid = UUID()
        let aid = UUID()
        let h = AnnotationStreamItem.highlight(makeHighlight(id: hid))
        let a = AnnotationStreamItem.standalone(makeAnnotation(id: aid))
        #expect(h.id == hid)
        #expect(a.id == aid)
    }

    @Test("AnnotationStreamItem.isNote — standalone is always a note")
    func streamItemStandaloneIsNote() {
        let a = AnnotationStreamItem.standalone(makeAnnotation())
        #expect(a.isNote)
    }

    @Test("AnnotationStreamItem.isNote — a highlight is a note iff its note is non-empty")
    func streamItemHighlightIsNote() {
        #expect(AnnotationStreamItem.highlight(makeHighlight(note: "yes")).isNote)
        #expect(!AnnotationStreamItem.highlight(makeHighlight(note: nil)).isNote)
        #expect(!AnnotationStreamItem.highlight(makeHighlight(note: "")).isNote)
    }

    @Test("AnnotationStreamItem createdAt projects the record timestamp")
    func streamItemCreatedAt() {
        let date = Date(timeIntervalSince1970: 9_999)
        let h = AnnotationStreamItem.highlight(makeHighlight(createdAt: date))
        let a = AnnotationStreamItem.standalone(makeAnnotation(createdAt: date))
        #expect(h.createdAt == date)
        #expect(a.createdAt == date)
    }
}
