// Purpose: Tests for TXTOffsetTranslator — verifies bidirectional UTF-16 offset
// translation between global and chapter-local coordinates, binary search correctness,
// boundary conditions, CJK text handling, and edge cases.
//
// @coordinates-with: TXTOffsetTranslator.swift, TXTChapterTypes.swift

import Testing
import Foundation
@testable import vreader

// MARK: - Fixtures

/// Creates chapters with pre-populated UTF-16 offsets.
/// Each chapter has `chapterLength` UTF-16 code units.
private func makeChapters(count: Int, chapterLength: Int = 100) -> [TXTChapter] {
    var result: [TXTChapter] = []
    for i in 0..<count {
        let ch = TXTChapter(
            index: i,
            title: "Chapter \(i + 1)",
            startByte: Int64(i * 200),
            endByte: Int64((i + 1) * 200),
            globalStartUTF16: i * chapterLength,
            textLengthUTF16: chapterLength
        )
        result.append(ch)
    }
    return result
}

// MARK: - Tests

@Suite("TXTOffsetTranslator")
struct TXTOffsetTranslatorTests {

    // MARK: - toLocal

    @Test("global offset 0 maps to chapter 0, local 0")
    func testToLocalOffsetZero() {
        let chapters = makeChapters(count: 3)
        let result = TXTOffsetTranslator.toLocal(globalUTF16: 0, chapters: chapters)
        #expect(result != nil)
        #expect(result?.chapterIndex == 0)
        #expect(result?.localOffsetUTF16 == 0)
    }

    @Test("global offset in middle of chapter 1 maps correctly")
    func testToLocalMiddleOfChapter() {
        let chapters = makeChapters(count: 3) // ch0: 0-99, ch1: 100-199, ch2: 200-299
        let result = TXTOffsetTranslator.toLocal(globalUTF16: 150, chapters: chapters)
        #expect(result != nil)
        #expect(result?.chapterIndex == 1)
        #expect(result?.localOffsetUTF16 == 50)
    }

    @Test("global offset at chapter boundary maps to next chapter, local 0")
    func testToLocalAtChapterBoundary() {
        let chapters = makeChapters(count: 3) // ch0: 0-99, ch1: 100-199, ch2: 200-299
        let result = TXTOffsetTranslator.toLocal(globalUTF16: 100, chapters: chapters)
        #expect(result != nil)
        #expect(result?.chapterIndex == 1)
        #expect(result?.localOffsetUTF16 == 0)
    }

    @Test("global offset beyond end returns nil")
    func testToLocalBeyondEnd() {
        let chapters = makeChapters(count: 3) // total UTF-16 length = 300
        let result = TXTOffsetTranslator.toLocal(globalUTF16: 300, chapters: chapters)
        #expect(result == nil)
    }

    @Test("negative global offset returns nil")
    func testToLocalNegative() {
        let chapters = makeChapters(count: 3)
        let result = TXTOffsetTranslator.toLocal(globalUTF16: -1, chapters: chapters)
        #expect(result == nil)
    }

    // MARK: - toGlobal round-trip

    @Test("toGlobal(toLocal(x)) == x for all valid offsets")
    func testToGlobalRoundTrip() {
        let chapters = makeChapters(count: 3, chapterLength: 100)
        let testOffsets = [0, 1, 50, 99, 100, 150, 199, 200, 250, 299]
        for offset in testOffsets {
            guard let local = TXTOffsetTranslator.toLocal(globalUTF16: offset, chapters: chapters) else {
                Issue.record("toLocal returned nil for offset \(offset)")
                continue
            }
            let global = TXTOffsetTranslator.toGlobal(
                chapterIndex: local.chapterIndex,
                localUTF16: local.localOffsetUTF16,
                chapters: chapters
            )
            #expect(global == offset, "Round-trip failed for offset \(offset)")
        }
    }

    @Test("toGlobal with invalid chapter index returns nil")
    func testToGlobalInvalidChapter() {
        let chapters = makeChapters(count: 3)
        #expect(TXTOffsetTranslator.toGlobal(chapterIndex: -1, localUTF16: 0, chapters: chapters) == nil)
        #expect(TXTOffsetTranslator.toGlobal(chapterIndex: 3, localUTF16: 0, chapters: chapters) == nil)
    }

    @Test("toGlobal with local offset beyond chapter length returns nil")
    func testToGlobalLocalBeyondLength() {
        let chapters = makeChapters(count: 3, chapterLength: 100)
        // Terminal offset (== textLengthUTF16) is allowed per the audit fix
        // in `TXTOffsetTranslator.toGlobal` ("Allow terminal offset for
        // caret/position at chapter end") — used by callers placing the
        // cursor right after the last character.
        #expect(TXTOffsetTranslator.toGlobal(chapterIndex: 0, localUTF16: 100, chapters: chapters) == 100)
        // Strictly past the terminal offset is out of range.
        #expect(TXTOffsetTranslator.toGlobal(chapterIndex: 0, localUTF16: 101, chapters: chapters) == nil)
    }

    // MARK: - toLocalRange

    @Test("range within single chapter maps correctly")
    func testToLocalRangeWithinChapter() {
        let chapters = makeChapters(count: 3)
        let globalRange = NSRange(location: 110, length: 20) // within chapter 1 (100-199)
        let result = TXTOffsetTranslator.toLocalRange(globalRange: globalRange, chapters: chapters)
        #expect(result != nil)
        #expect(result?.chapterIndex == 1)
        #expect(result?.localRange.location == 10)
        #expect(result?.localRange.length == 20)
    }

    @Test("range crossing chapter boundary returns nil")
    func testToLocalRangeCrossChapter() {
        let chapters = makeChapters(count: 3)
        let globalRange = NSRange(location: 90, length: 20) // spans ch0 (90-99) and ch1 (100-109)
        let result = TXTOffsetTranslator.toLocalRange(globalRange: globalRange, chapters: chapters)
        #expect(result == nil)
    }

    @Test("zero-length range maps correctly")
    func testToLocalRangeZeroLength() {
        let chapters = makeChapters(count: 3)
        let globalRange = NSRange(location: 150, length: 0)
        let result = TXTOffsetTranslator.toLocalRange(globalRange: globalRange, chapters: chapters)
        #expect(result != nil)
        #expect(result?.chapterIndex == 1)
        #expect(result?.localRange.location == 50)
        #expect(result?.localRange.length == 0)
    }

    // MARK: - chapterContaining (binary search)

    @Test("binary search finds correct chapter for various offsets")
    func testChapterContainingBinarySearch() {
        let chapters = makeChapters(count: 10, chapterLength: 50) // total 500
        // First chapter
        #expect(TXTOffsetTranslator.chapterContaining(globalUTF16: 0, chapters: chapters) == 0)
        #expect(TXTOffsetTranslator.chapterContaining(globalUTF16: 49, chapters: chapters) == 0)
        // Second chapter
        #expect(TXTOffsetTranslator.chapterContaining(globalUTF16: 50, chapters: chapters) == 1)
        // Last chapter
        #expect(TXTOffsetTranslator.chapterContaining(globalUTF16: 450, chapters: chapters) == 9)
        #expect(TXTOffsetTranslator.chapterContaining(globalUTF16: 499, chapters: chapters) == 9)
        // Out of bounds
        #expect(TXTOffsetTranslator.chapterContaining(globalUTF16: 500, chapters: chapters) == nil)
        #expect(TXTOffsetTranslator.chapterContaining(globalUTF16: -1, chapters: chapters) == nil)
    }

    // MARK: - populateUTF16Offsets

    @Test("populateUTF16Offsets sets correct cumulative offsets")
    func testPopulateUTF16Offsets() throws {
        var chapters = [
            TXTChapter(index: 0, title: "Ch1", startByte: 0, endByte: 100),
            TXTChapter(index: 1, title: "Ch2", startByte: 100, endByte: 200),
            TXTChapter(index: 2, title: "Ch3", startByte: 200, endByte: 300),
        ]
        // Loader returns fixed-length strings
        let texts = ["Hello", "World!!", "OK"]
        try TXTOffsetTranslator.populateUTF16Offsets(chapters: &chapters) { ch in
            texts[ch.index]
        }

        // "Hello" = 5 UTF-16 units
        #expect(chapters[0].globalStartUTF16 == 0)
        #expect(chapters[0].textLengthUTF16 == 5)
        // "World!!" = 7 UTF-16 units
        #expect(chapters[1].globalStartUTF16 == 5)
        #expect(chapters[1].textLengthUTF16 == 7)
        // "OK" = 2 UTF-16 units
        #expect(chapters[2].globalStartUTF16 == 12)
        #expect(chapters[2].textLengthUTF16 == 2)
    }

    @Test("populateUTF16Offsets handles CJK text correctly")
    func testPopulateWithCJKText() throws {
        var chapters = [
            TXTChapter(index: 0, title: "Ch1", startByte: 0, endByte: 100),
            TXTChapter(index: 1, title: "Ch2", startByte: 100, endByte: 200),
        ]
        // CJK: most are 1 UTF-16 unit, but some emoji/rare CJK are 2 (surrogate pair)
        // U+1F600 (grinning face) = 2 UTF-16 units (surrogate pair)
        // U+4E16 (世) = 1 UTF-16 unit
        let texts = ["世界你好", "Hello\u{1F600}"]  // 4 CJK = 4 UTF-16, "Hello" + emoji = 5+2=7
        try TXTOffsetTranslator.populateUTF16Offsets(chapters: &chapters) { ch in
            texts[ch.index]
        }

        #expect(chapters[0].globalStartUTF16 == 0)
        #expect(chapters[0].textLengthUTF16 == 4) // 世界你好 = 4 UTF-16
        #expect(chapters[1].globalStartUTF16 == 4)
        #expect(chapters[1].textLengthUTF16 == 7) // Hello + U+1F600 = 5 + 2 = 7
    }

    // MARK: - Empty / Single chapter edge cases

    @Test("all methods return nil for empty chapter list")
    func testEmptyChapters() {
        let empty: [TXTChapter] = []
        #expect(TXTOffsetTranslator.toLocal(globalUTF16: 0, chapters: empty) == nil)
        #expect(TXTOffsetTranslator.toGlobal(chapterIndex: 0, localUTF16: 0, chapters: empty) == nil)
        #expect(TXTOffsetTranslator.toLocalRange(globalRange: NSRange(location: 0, length: 1), chapters: empty) == nil)
        #expect(TXTOffsetTranslator.chapterContaining(globalUTF16: 0, chapters: empty) == nil)
    }

    @Test("single chapter — all valid offsets map to chapter 0")
    func testSingleChapter() {
        let chapters = makeChapters(count: 1, chapterLength: 50)
        // Start
        #expect(TXTOffsetTranslator.chapterContaining(globalUTF16: 0, chapters: chapters) == 0)
        // Middle
        #expect(TXTOffsetTranslator.chapterContaining(globalUTF16: 25, chapters: chapters) == 0)
        // Last valid
        #expect(TXTOffsetTranslator.chapterContaining(globalUTF16: 49, chapters: chapters) == 0)
        // One past end
        #expect(TXTOffsetTranslator.chapterContaining(globalUTF16: 50, chapters: chapters) == nil)

        let local = TXTOffsetTranslator.toLocal(globalUTF16: 25, chapters: chapters)
        #expect(local?.chapterIndex == 0)
        #expect(local?.localOffsetUTF16 == 25)
    }
}
