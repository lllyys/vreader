// Purpose: Tests for TXTChapterHighlightHelper — offset translation between
// global (DB) and chapter-local (display) coordinates.

import Testing
import Foundation
@testable import vreader

@Suite("TXTChapterHighlightHelper")
struct TXTChapterHighlightHelperTests {

    // MARK: - Fixtures

    /// Three chapters: [0..100), [100..250), [250..400)
    private static let chapters = [
        TXTChapter(index: 0, title: "Chapter 1", startByte: 0, endByte: 200, globalStartUTF16: 0, textLengthUTF16: 100),
        TXTChapter(index: 1, title: "Chapter 2", startByte: 200, endByte: 500, globalStartUTF16: 100, textLengthUTF16: 150),
        TXTChapter(index: 2, title: "Chapter 3", startByte: 500, endByte: 800, globalStartUTF16: 250, textLengthUTF16: 150),
    ]

    /// Builds a `PaintedHighlight`. Color defaults to yellow for the
    /// range-translation tests that don't exercise color.
    private static func ph(_ loc: Int, _ len: Int, color: String = "yellow") -> PaintedHighlight {
        PaintedHighlight(range: NSRange(location: loc, length: len), colorName: color)
    }

    // MARK: - highlightsForChapter

    @Test("highlights within chapter — returns correctly translated ranges")
    func testHighlightsWithinChapter() {
        // Highlight at global [110, 140) should map to local [10, 40) in chapter 2
        let result = TXTChapterHighlightHelper.highlightsForChapter(
            chapterIndex: 1,
            chapters: Self.chapters,
            persistedGlobalRanges: [Self.ph(110, 30)]
        )
        #expect(result.count == 1)
        #expect(result[0].range == NSRange(location: 10, length: 30))
    }

    @Test("highlight color is preserved through chapter translation")
    func testHighlightColorPreserved() {
        // Bug #208 / GH #776: chapter-local translation must keep each
        // highlight's color, not just its range.
        let result = TXTChapterHighlightHelper.highlightsForChapter(
            chapterIndex: 1,
            chapters: Self.chapters,
            persistedGlobalRanges: [Self.ph(110, 30, color: "pink")]
        )
        #expect(result.count == 1)
        #expect(result[0].colorName == "pink")
    }

    @Test("highlights outside chapter — returns empty")
    func testHighlightsOutsideChapter() {
        // Highlight at global [0, 50) is in chapter 1, not chapter 2
        let result = TXTChapterHighlightHelper.highlightsForChapter(
            chapterIndex: 1,
            chapters: Self.chapters,
            persistedGlobalRanges: [Self.ph(0, 50)]
        )
        #expect(result.isEmpty)
    }

    @Test("highlight spanning chapter boundary — clips to chapter bounds")
    func testHighlightSpanningChapterBoundary() {
        // Highlight at global [80, 130) spans chapters 1 and 2.
        // For chapter 1 [0..100): clipped to [80, 100) → local [80, 20len)
        // For chapter 2 [100..250): clipped to [100, 130) → local [0, 30)
        let globalRanges = [Self.ph(80, 50)]

        let ch1Result = TXTChapterHighlightHelper.highlightsForChapter(
            chapterIndex: 0,
            chapters: Self.chapters,
            persistedGlobalRanges: globalRanges
        )
        #expect(ch1Result.count == 1)
        #expect(ch1Result[0].range == NSRange(location: 80, length: 20))

        let ch2Result = TXTChapterHighlightHelper.highlightsForChapter(
            chapterIndex: 1,
            chapters: Self.chapters,
            persistedGlobalRanges: globalRanges
        )
        #expect(ch2Result.count == 1)
        #expect(ch2Result[0].range == NSRange(location: 0, length: 30))
    }

    @Test("multiple highlights — filters and translates correctly")
    func testMultipleHighlights() {
        // Mix of highlights: one in chapter 2, one outside, one spanning
        let globalRanges = [
            Self.ph(110, 10),  // fully in chapter 2
            Self.ph(300, 20),  // fully in chapter 3
            Self.ph(240, 30),  // spans chapters 2 and 3
        ]

        let ch2Result = TXTChapterHighlightHelper.highlightsForChapter(
            chapterIndex: 1,
            chapters: Self.chapters,
            persistedGlobalRanges: globalRanges
        )
        // First: [110,120) → local [10,10)
        // Second: [300,320) entirely in ch3 → skipped
        // Third: [240,270) spans ch2[100..250) → clipped [240,250) → local [140, 10)
        #expect(ch2Result.count == 2)
        #expect(ch2Result[0].range == NSRange(location: 10, length: 10))
        #expect(ch2Result[1].range == NSRange(location: 140, length: 10))
    }

    @Test("empty persisted ranges — returns empty")
    func testEmptyPersistedRanges() {
        let result = TXTChapterHighlightHelper.highlightsForChapter(
            chapterIndex: 0,
            chapters: Self.chapters,
            persistedGlobalRanges: []
        )
        #expect(result.isEmpty)
    }

    @Test("chapter index out of bounds — returns empty")
    func testChapterIndexOutOfBounds() {
        let result = TXTChapterHighlightHelper.highlightsForChapter(
            chapterIndex: 99,
            chapters: Self.chapters,
            persistedGlobalRanges: [Self.ph(10, 20)]
        )
        #expect(result.isEmpty)
    }

    @Test("empty chapters array — returns empty")
    func testEmptyChaptersArray() {
        let result = TXTChapterHighlightHelper.highlightsForChapter(
            chapterIndex: 0,
            chapters: [],
            persistedGlobalRanges: [Self.ph(0, 10)]
        )
        #expect(result.isEmpty)
    }

    @Test("chapter with zero text length — returns empty")
    func testZeroLengthChapter() {
        let chapters = [TXTChapter(index: 0, title: "Empty", startByte: 0, endByte: 0, globalStartUTF16: 0, textLengthUTF16: 0)]
        let result = TXTChapterHighlightHelper.highlightsForChapter(
            chapterIndex: 0,
            chapters: chapters,
            persistedGlobalRanges: [Self.ph(0, 10)]
        )
        #expect(result.isEmpty)
    }

    @Test("chapter with negative globalStartUTF16 — returns empty")
    func testNegativeGlobalStart() {
        let chapters = [TXTChapter(index: 0, title: "Bad", startByte: 0, endByte: 200, globalStartUTF16: -1, textLengthUTF16: 100)]
        let result = TXTChapterHighlightHelper.highlightsForChapter(
            chapterIndex: 0,
            chapters: chapters,
            persistedGlobalRanges: [Self.ph(0, 10)]
        )
        #expect(result.isEmpty)
    }

    @Test("highlight at exact chapter start boundary")
    func testHighlightAtExactStart() {
        // Highlight starting at exact start of chapter 2 (offset 100)
        let result = TXTChapterHighlightHelper.highlightsForChapter(
            chapterIndex: 1,
            chapters: Self.chapters,
            persistedGlobalRanges: [Self.ph(100, 10)]
        )
        #expect(result.count == 1)
        #expect(result[0].range == NSRange(location: 0, length: 10))
    }

    @Test("highlight at exact chapter end boundary — not included")
    func testHighlightAtExactEnd() {
        // Highlight starting at offset 250 (chapter 2 ends at 250)
        let result = TXTChapterHighlightHelper.highlightsForChapter(
            chapterIndex: 1,
            chapters: Self.chapters,
            persistedGlobalRanges: [Self.ph(250, 10)]
        )
        #expect(result.isEmpty)
    }

    // MARK: - toGlobalRange

    @Test("toGlobalRange — correct translation")
    func testToGlobalRange() {
        let localRange = NSRange(location: 10, length: 30)
        let result = TXTChapterHighlightHelper.toGlobalRange(
            localRange: localRange,
            chapterIndex: 1,
            chapters: Self.chapters
        )
        #expect(result == NSRange(location: 110, length: 30))
    }

    @Test("toGlobalRange — chapter index out of bounds returns nil")
    func testToGlobalRangeOutOfBounds() {
        let result = TXTChapterHighlightHelper.toGlobalRange(
            localRange: NSRange(location: 0, length: 10),
            chapterIndex: 99,
            chapters: Self.chapters
        )
        #expect(result == nil)
    }

    @Test("toGlobalRange — negative globalStartUTF16 returns nil")
    func testToGlobalRangeNegativeStart() {
        let chapters = [TXTChapter(index: 0, title: "Bad", startByte: 0, endByte: 200, globalStartUTF16: -1, textLengthUTF16: 100)]
        let result = TXTChapterHighlightHelper.toGlobalRange(
            localRange: NSRange(location: 0, length: 10),
            chapterIndex: 0,
            chapters: chapters
        )
        #expect(result == nil)
    }

    @Test("toGlobalRange — first chapter (offset 0)")
    func testToGlobalRangeFirstChapter() {
        let localRange = NSRange(location: 5, length: 20)
        let result = TXTChapterHighlightHelper.toGlobalRange(
            localRange: localRange,
            chapterIndex: 0,
            chapters: Self.chapters
        )
        #expect(result == NSRange(location: 5, length: 20))
    }

    // MARK: - toChapterLocalOffset

    @Test("toChapterLocalOffset — correct offset")
    func testToChapterLocalOffset() {
        let result = TXTChapterHighlightHelper.toChapterLocalOffset(
            globalUTF16: 130,
            chapterIndex: 1,
            chapters: Self.chapters
        )
        #expect(result == 30)
    }

    @Test("toChapterLocalOffset — offset at chapter start")
    func testToChapterLocalOffsetAtStart() {
        let result = TXTChapterHighlightHelper.toChapterLocalOffset(
            globalUTF16: 100,
            chapterIndex: 1,
            chapters: Self.chapters
        )
        #expect(result == 0)
    }

    @Test("toChapterLocalOffset — offset before chapter returns 0")
    func testToChapterLocalOffsetBeforeChapter() {
        let result = TXTChapterHighlightHelper.toChapterLocalOffset(
            globalUTF16: 50,
            chapterIndex: 1,
            chapters: Self.chapters
        )
        #expect(result == 0)
    }

    @Test("toChapterLocalOffset — chapter index out of bounds returns 0")
    func testToChapterLocalOffsetOutOfBounds() {
        let result = TXTChapterHighlightHelper.toChapterLocalOffset(
            globalUTF16: 130,
            chapterIndex: 99,
            chapters: Self.chapters
        )
        #expect(result == 0)
    }

    @Test("toChapterLocalOffset — negative globalStartUTF16 returns 0")
    func testToChapterLocalOffsetNegativeStart() {
        let chapters = [TXTChapter(index: 0, title: "Bad", startByte: 0, endByte: 200, globalStartUTF16: -1, textLengthUTF16: 100)]
        let result = TXTChapterHighlightHelper.toChapterLocalOffset(
            globalUTF16: 50,
            chapterIndex: 0,
            chapters: chapters
        )
        #expect(result == 0)
    }

    @Test("toChapterLocalOffset — empty chapters returns 0")
    func testToChapterLocalOffsetEmptyChapters() {
        let result = TXTChapterHighlightHelper.toChapterLocalOffset(
            globalUTF16: 50,
            chapterIndex: 0,
            chapters: []
        )
        #expect(result == 0)
    }

    // MARK: - lookupForChapter (Bug #202)

    /// `lookupForChapter` is the UUID-preserving sibling of `highlightsForChapter`.
    /// `chapterReaderContent` needs chapter-local lookup entries so the bridge's
    /// tap-on-highlight hit-test resolves to the right UUID in chapter mode.
    /// Previously, only `highlightsForChapter` (range-only) was passed through,
    /// leaving the bridge's lookup empty and causing chrome-toggle to win the tap.

    @Test("lookupForChapter — empty lookup returns empty")
    func testLookupForChapterEmpty() {
        let result = TXTChapterHighlightHelper.lookupForChapter(
            chapterIndex: 1,
            chapters: Self.chapters,
            globalLookup: []
        )
        #expect(result.isEmpty)
    }

    @Test("lookupForChapter — entry within chapter — preserves UUID and translates range")
    func testLookupForChapterWithinChapter() {
        let id = UUID()
        let global = [
            PersistedHighlightLookupEntry(id: id, range: NSRange(location: 110, length: 30))
        ]
        let result = TXTChapterHighlightHelper.lookupForChapter(
            chapterIndex: 1,
            chapters: Self.chapters,
            globalLookup: global
        )
        #expect(result.count == 1)
        #expect(result[0].id == id)
        #expect(result[0].range == NSRange(location: 10, length: 30))
    }

    @Test("lookupForChapter — preserves hasNote through chapter clipping (Bug #295)")
    func testLookupForChapterPreservesHasNote() {
        let notedID = UUID()
        let notelessID = UUID()
        let global = [
            PersistedHighlightLookupEntry(id: notedID, range: NSRange(location: 110, length: 20), hasNote: true),
            PersistedHighlightLookupEntry(id: notelessID, range: NSRange(location: 140, length: 20), hasNote: false),
        ]
        let result = TXTChapterHighlightHelper.lookupForChapter(
            chapterIndex: 1,
            chapters: Self.chapters,
            globalLookup: global
        )
        #expect(result.first(where: { $0.id == notedID })?.hasNote == true)
        #expect(result.first(where: { $0.id == notelessID })?.hasNote == false)
    }

    @Test("lookupForChapter — entries outside chapter are filtered out")
    func testLookupForChapterFiltersOutsideEntries() {
        let inside = PersistedHighlightLookupEntry(id: UUID(), range: NSRange(location: 110, length: 20))
        let before = PersistedHighlightLookupEntry(id: UUID(), range: NSRange(location: 0, length: 50))
        let after = PersistedHighlightLookupEntry(id: UUID(), range: NSRange(location: 260, length: 30))
        let result = TXTChapterHighlightHelper.lookupForChapter(
            chapterIndex: 1,
            chapters: Self.chapters,
            globalLookup: [before, inside, after]
        )
        #expect(result.count == 1)
        #expect(result[0].id == inside.id)
    }

    @Test("lookupForChapter — entry spanning chapter boundary is clipped to chapter")
    func testLookupForChapterClipsSpanningEntry() {
        let id = UUID()
        // Global [80, 130) spans chapter 1 [0..100) and chapter 2 [100..250).
        let global = [
            PersistedHighlightLookupEntry(id: id, range: NSRange(location: 80, length: 50))
        ]
        // For chapter 1: clipped to [80, 100) → local [80, 20len)
        let ch1 = TXTChapterHighlightHelper.lookupForChapter(
            chapterIndex: 0,
            chapters: Self.chapters,
            globalLookup: global
        )
        #expect(ch1.count == 1)
        #expect(ch1[0].id == id)
        #expect(ch1[0].range == NSRange(location: 80, length: 20))
        // For chapter 2: clipped to [100, 130) → local [0, 30len)
        let ch2 = TXTChapterHighlightHelper.lookupForChapter(
            chapterIndex: 1,
            chapters: Self.chapters,
            globalLookup: global
        )
        #expect(ch2.count == 1)
        #expect(ch2[0].id == id)
        #expect(ch2[0].range == NSRange(location: 0, length: 30))
    }

    @Test("lookupForChapter — chapter index out of bounds returns empty")
    func testLookupForChapterOutOfBounds() {
        let global = [
            PersistedHighlightLookupEntry(id: UUID(), range: NSRange(location: 10, length: 20))
        ]
        let result = TXTChapterHighlightHelper.lookupForChapter(
            chapterIndex: 99,
            chapters: Self.chapters,
            globalLookup: global
        )
        #expect(result.isEmpty)
    }

    @Test("lookupForChapter — multiple entries inside same chapter preserve order and UUIDs")
    func testLookupForChapterMultipleEntriesPreserveOrder() {
        let id1 = UUID()
        let id2 = UUID()
        // Both in chapter 2 [100..250)
        let global = [
            PersistedHighlightLookupEntry(id: id1, range: NSRange(location: 110, length: 20)),
            PersistedHighlightLookupEntry(id: id2, range: NSRange(location: 200, length: 30)),
        ]
        let result = TXTChapterHighlightHelper.lookupForChapter(
            chapterIndex: 1,
            chapters: Self.chapters,
            globalLookup: global
        )
        #expect(result.count == 2)
        #expect(result[0].id == id1)
        #expect(result[0].range == NSRange(location: 10, length: 20))
        #expect(result[1].id == id2)
        #expect(result[1].range == NSRange(location: 100, length: 30))
    }
}
