// Purpose: Tests for ChapterProgressCalculator — book-level progress from
// chapter index and scroll position.

import Testing
import Foundation
@testable import vreader

// MARK: - Fixtures

private let threeChapterIndex = TXTChapterIndex(chapters: [
    TXTChapter(index: 0, title: "Chapter 1", startByte: 0, endByte: 1000),
    TXTChapter(index: 1, title: "Chapter 2", startByte: 1000, endByte: 2000),
    TXTChapter(index: 2, title: "Chapter 3", startByte: 2000, endByte: 3000),
], totalBytes: 3000, detectedEncoding: "UTF-8")

private let singleChapterIndex = TXTChapterIndex(chapters: [
    TXTChapter(index: 0, title: "Only Chapter", startByte: 0, endByte: 5000),
], totalBytes: 5000, detectedEncoding: "UTF-8")

private let emptyTitleIndex = TXTChapterIndex(chapters: [
    TXTChapter(index: 0, title: "Chapter 1", startByte: 0, endByte: 1000),
    TXTChapter(index: 1, title: "", startByte: 1000, endByte: 2000),
    TXTChapter(index: 2, title: "Chapter 3", startByte: 2000, endByte: 3000),
], totalBytes: 3000, detectedEncoding: "UTF-8")

private let emptyIndex = TXTChapterIndex(chapters: [], totalBytes: 0, detectedEncoding: "UTF-8")

// MARK: - bookProgress

@Suite("ChapterProgressCalculator - bookProgress")
struct BookProgressTests {

    @Test("first chapter, beginning → 0.0")
    func firstChapterBeginning() {
        let result = ChapterProgressCalculator.bookProgress(
            currentChapterIdx: 0, scrollFraction: 0.0, totalChapters: 3
        )
        #expect(result == 0.0)
    }

    @Test("first chapter, halfway → 1/6")
    func firstChapterHalfway() {
        let result = ChapterProgressCalculator.bookProgress(
            currentChapterIdx: 0, scrollFraction: 0.5, totalChapters: 3
        )
        #expect(result != nil)
        let expected = 0.5 / 3.0
        #expect(abs(result! - expected) < 0.001)
    }

    @Test("second chapter, beginning → 1/3")
    func secondChapterBeginning() {
        let result = ChapterProgressCalculator.bookProgress(
            currentChapterIdx: 1, scrollFraction: 0.0, totalChapters: 3
        )
        #expect(result != nil)
        let expected = 1.0 / 3.0
        #expect(abs(result! - expected) < 0.001)
    }

    @Test("last chapter, end → 1.0")
    func lastChapterEnd() {
        let result = ChapterProgressCalculator.bookProgress(
            currentChapterIdx: 2, scrollFraction: 1.0, totalChapters: 3
        )
        #expect(result == 1.0)
    }

    @Test("single chapter, beginning → 0.0")
    func singleChapterBeginning() {
        let result = ChapterProgressCalculator.bookProgress(
            currentChapterIdx: 0, scrollFraction: 0.0, totalChapters: 1
        )
        #expect(result == 0.0)
    }

    @Test("single chapter, end → 1.0")
    func singleChapterEnd() {
        let result = ChapterProgressCalculator.bookProgress(
            currentChapterIdx: 0, scrollFraction: 1.0, totalChapters: 1
        )
        #expect(result == 1.0)
    }

    @Test("zero chapters → nil")
    func zeroChapters() {
        let result = ChapterProgressCalculator.bookProgress(
            currentChapterIdx: 0, scrollFraction: 0.5, totalChapters: 0
        )
        #expect(result == nil)
    }

    @Test("negative chapter index → nil")
    func negativeChapterIndex() {
        let result = ChapterProgressCalculator.bookProgress(
            currentChapterIdx: -1, scrollFraction: 0.5, totalChapters: 3
        )
        #expect(result == nil)
    }

    @Test("chapter index beyond total → nil")
    func chapterIndexBeyondTotal() {
        let result = ChapterProgressCalculator.bookProgress(
            currentChapterIdx: 5, scrollFraction: 0.5, totalChapters: 3
        )
        #expect(result == nil)
    }

    @Test("scrollFraction > 1 is clamped")
    func scrollFractionOverOne() {
        let result = ChapterProgressCalculator.bookProgress(
            currentChapterIdx: 0, scrollFraction: 2.0, totalChapters: 3
        )
        #expect(result != nil)
        // Clamped to 1.0: (0 + 1.0) / 3.0 = 0.333...
        let expected = 1.0 / 3.0
        #expect(abs(result! - expected) < 0.001)
    }

    @Test("scrollFraction < 0 is clamped to 0")
    func scrollFractionNegative() {
        let result = ChapterProgressCalculator.bookProgress(
            currentChapterIdx: 1, scrollFraction: -0.5, totalChapters: 3
        )
        #expect(result != nil)
        // Clamped to 0: (1 + 0) / 3.0 = 0.333...
        let expected = 1.0 / 3.0
        #expect(abs(result! - expected) < 0.001)
    }

    @Test("large chapter count works correctly")
    func largeChapterCount() {
        let result = ChapterProgressCalculator.bookProgress(
            currentChapterIdx: 499, scrollFraction: 0.5, totalChapters: 1000
        )
        #expect(result != nil)
        let expected = 499.5 / 1000.0
        #expect(abs(result! - expected) < 0.001)
    }

    @Test("result always in 0...1 range")
    func resultInRange() {
        for idx in 0..<10 {
            for fraction in stride(from: 0.0, through: 1.0, by: 0.1) {
                let result = ChapterProgressCalculator.bookProgress(
                    currentChapterIdx: idx, scrollFraction: fraction, totalChapters: 10
                )
                if let result {
                    #expect(result >= 0.0)
                    #expect(result <= 1.0)
                }
            }
        }
    }
}

// MARK: - nextChapterTitle

@Suite("ChapterProgressCalculator - nextChapterTitle")
struct NextChapterTitleTests {

    @Test("first chapter → second chapter title")
    func firstChapter() {
        let result = ChapterProgressCalculator.nextChapterTitle(
            currentChapterIdx: 0, chapterIndex: threeChapterIndex
        )
        #expect(result == "Chapter 2")
    }

    @Test("last chapter → nil")
    func lastChapter() {
        let result = ChapterProgressCalculator.nextChapterTitle(
            currentChapterIdx: 2, chapterIndex: threeChapterIndex
        )
        #expect(result == nil)
    }

    @Test("single chapter → nil")
    func singleChapter() {
        let result = ChapterProgressCalculator.nextChapterTitle(
            currentChapterIdx: 0, chapterIndex: singleChapterIndex
        )
        #expect(result == nil)
    }

    @Test("empty chapter index → nil")
    func emptyChapterIndex() {
        let result = ChapterProgressCalculator.nextChapterTitle(
            currentChapterIdx: 0, chapterIndex: emptyIndex
        )
        #expect(result == nil)
    }

    @Test("next chapter has empty title → nil")
    func emptyTitle() {
        let result = ChapterProgressCalculator.nextChapterTitle(
            currentChapterIdx: 0, chapterIndex: emptyTitleIndex
        )
        #expect(result == nil)
    }

    @Test("negative index → returns first chapter title")
    func negativeIndex() {
        let result = ChapterProgressCalculator.nextChapterTitle(
            currentChapterIdx: -1, chapterIndex: threeChapterIndex
        )
        #expect(result == "Chapter 1")
    }

    @Test("out of bounds index → nil")
    func outOfBoundsIndex() {
        let result = ChapterProgressCalculator.nextChapterTitle(
            currentChapterIdx: 10, chapterIndex: threeChapterIndex
        )
        #expect(result == nil)
    }
}

// MARK: - previousChapterTitle

@Suite("ChapterProgressCalculator - previousChapterTitle")
struct PreviousChapterTitleTests {

    @Test("first chapter → nil")
    func firstChapter() {
        let result = ChapterProgressCalculator.previousChapterTitle(
            currentChapterIdx: 0, chapterIndex: threeChapterIndex
        )
        #expect(result == nil)
    }

    @Test("second chapter → first chapter title")
    func secondChapter() {
        let result = ChapterProgressCalculator.previousChapterTitle(
            currentChapterIdx: 1, chapterIndex: threeChapterIndex
        )
        #expect(result == "Chapter 1")
    }

    @Test("last chapter → penultimate chapter title")
    func lastChapter() {
        let result = ChapterProgressCalculator.previousChapterTitle(
            currentChapterIdx: 2, chapterIndex: threeChapterIndex
        )
        #expect(result == "Chapter 2")
    }

    @Test("single chapter → nil")
    func singleChapter() {
        let result = ChapterProgressCalculator.previousChapterTitle(
            currentChapterIdx: 0, chapterIndex: singleChapterIndex
        )
        #expect(result == nil)
    }

    @Test("empty chapter index → nil")
    func emptyChapterIndex() {
        let result = ChapterProgressCalculator.previousChapterTitle(
            currentChapterIdx: 0, chapterIndex: emptyIndex
        )
        #expect(result == nil)
    }

    @Test("previous chapter has empty title → nil")
    func emptyTitle() {
        let result = ChapterProgressCalculator.previousChapterTitle(
            currentChapterIdx: 2, chapterIndex: emptyTitleIndex
        )
        #expect(result == nil)
    }
}

// MARK: - TXTChapterIndex

@Suite("TXTChapterIndex - Data Model")
struct TXTChapterIndexTests {

    @Test("count returns number of chapters")
    func count() {
        #expect(threeChapterIndex.count == 3)
        #expect(singleChapterIndex.count == 1)
        #expect(emptyIndex.count == 0)
    }

    @Test("isEmpty for empty index")
    func isEmpty() {
        #expect(emptyIndex.isEmpty == true)
        #expect(threeChapterIndex.isEmpty == false)
    }

    @Test("title at valid index")
    func titleAtValidIndex() {
        #expect(threeChapterIndex.title(at: 0) == "Chapter 1")
        #expect(threeChapterIndex.title(at: 2) == "Chapter 3")
    }

    @Test("title at invalid index")
    func titleAtInvalidIndex() {
        #expect(threeChapterIndex.title(at: -1) == nil)
        #expect(threeChapterIndex.title(at: 5) == nil)
        #expect(emptyIndex.title(at: 0) == nil)
    }

    @Test("equatable conformance")
    func equatable() {
        let a = TXTChapterIndex(chapters: [
            TXTChapter(index: 0, title: "Ch1", startByte: 0, endByte: 100)
        ], totalBytes: 100, detectedEncoding: "UTF-8")
        let b = TXTChapterIndex(chapters: [
            TXTChapter(index: 0, title: "Ch1", startByte: 0, endByte: 100)
        ], totalBytes: 100, detectedEncoding: "UTF-8")
        let c = TXTChapterIndex(chapters: [
            TXTChapter(index: 0, title: "Ch2", startByte: 0, endByte: 100)
        ], totalBytes: 100, detectedEncoding: "UTF-8")
        #expect(a == b)
        #expect(a != c)
    }

    @Test("codable round-trip")
    func codable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(threeChapterIndex)
        let decoded = try decoder.decode(TXTChapterIndex.self, from: data)
        #expect(decoded == threeChapterIndex)
    }
}
