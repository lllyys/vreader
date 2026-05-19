// Purpose: Unit tests for TXTChapterOffsetIndex — the chapter-awareness layer
// over the continuous-scroll TXT surface (Bug #180 re-scoped fix, WI-2).
//
// Tests live in vreaderTests/Services/TXT/ to mirror the source path.

import Testing
import Foundation
@testable import vreader

@Suite("TXTChapterOffsetIndex")
struct TXTChapterOffsetIndexTests {

    /// Builds a 3-chapter index: ch0 [0,100), ch1 [100,250), ch2 [250,400).
    private func threeChapterIndex() -> TXTChapterIndex {
        let chapters = [
            TXTChapter(index: 0, title: "One", startByte: 0, endByte: 100,
                       globalStartUTF16: 0, textLengthUTF16: 100),
            TXTChapter(index: 1, title: "Two", startByte: 100, endByte: 250,
                       globalStartUTF16: 100, textLengthUTF16: 150),
            TXTChapter(index: 2, title: "Three", startByte: 250, endByte: 400,
                       globalStartUTF16: 250, textLengthUTF16: 150),
        ]
        return TXTChapterIndex(
            chapters: chapters, totalBytes: 400, detectedEncoding: "UTF-8",
            totalTextLengthUTF16: 400
        )
    }

    @Test func buildPopulatesChaptersAndTotalLength() {
        let index = TXTChapterOffsetIndex.build(from: threeChapterIndex())
        #expect(index.chapters.count == 3)
        #expect(index.totalTextLengthUTF16 == 400)
    }

    @Test func chapterContainingAtOffsetZeroReturnsFirst() {
        let index = TXTChapterOffsetIndex.build(from: threeChapterIndex())
        #expect(index.chapterContaining(0) == 0)
    }

    @Test func chapterContainingAtExactChapterStarts() {
        let index = TXTChapterOffsetIndex.build(from: threeChapterIndex())
        #expect(index.chapterContaining(0) == 0)
        #expect(index.chapterContaining(100) == 1)
        #expect(index.chapterContaining(250) == 2)
    }

    @Test func chapterContainingMidChapter() {
        let index = TXTChapterOffsetIndex.build(from: threeChapterIndex())
        #expect(index.chapterContaining(50) == 0)
        #expect(index.chapterContaining(99) == 0)
        #expect(index.chapterContaining(175) == 1)
        #expect(index.chapterContaining(249) == 1)
        #expect(index.chapterContaining(399) == 2)
    }

    @Test func chapterContainingBeyondEndClampsToLast() {
        let index = TXTChapterOffsetIndex.build(from: threeChapterIndex())
        #expect(index.chapterContaining(400) == 2)
        #expect(index.chapterContaining(99999) == 2)
    }

    @Test func chapterContainingNegativeClampsToFirst() {
        let index = TXTChapterOffsetIndex.build(from: threeChapterIndex())
        #expect(index.chapterContaining(-1) == 0)
        #expect(index.chapterContaining(-9999) == 0)
    }

    @Test func chapterContainingSingleChapterAlwaysReturnsZero() {
        let single = TXTChapterIndex(
            chapters: [TXTChapter(index: 0, title: "Only", startByte: 0,
                                  endByte: 500, globalStartUTF16: 0,
                                  textLengthUTF16: 500)],
            totalBytes: 500, detectedEncoding: "UTF-8", totalTextLengthUTF16: 500
        )
        let index = TXTChapterOffsetIndex.build(from: single)
        #expect(index.chapterContaining(0) == 0)
        #expect(index.chapterContaining(250) == 0)
        #expect(index.chapterContaining(500) == 0)
        #expect(index.chapterContaining(99999) == 0)
    }

    @Test func chapterContainingEmptyIndexReturnsZero() {
        let empty = TXTChapterIndex(
            chapters: [], totalBytes: 0, detectedEncoding: "UTF-8",
            totalTextLengthUTF16: 0
        )
        let index = TXTChapterOffsetIndex.build(from: empty)
        // No chapters — degenerate but must not crash.
        #expect(index.chapterContaining(0) == 0)
        #expect(index.chapterContaining(100) == 0)
    }

    @Test func globalStartForEachChapter() {
        let index = TXTChapterOffsetIndex.build(from: threeChapterIndex())
        #expect(index.globalStart(ofChapter: 0) == 0)
        #expect(index.globalStart(ofChapter: 1) == 100)
        #expect(index.globalStart(ofChapter: 2) == 250)
    }

    @Test func globalStartOutOfBoundsReturnsSafeDefault() {
        let index = TXTChapterOffsetIndex.build(from: threeChapterIndex())
        #expect(index.globalStart(ofChapter: -1) == 0)
        #expect(index.globalStart(ofChapter: 99) == 0)
    }

    @Test func chapterLengthForEachChapter() {
        let index = TXTChapterOffsetIndex.build(from: threeChapterIndex())
        #expect(index.chapterLength(0) == 100)
        #expect(index.chapterLength(1) == 150)
        #expect(index.chapterLength(2) == 150)
    }

    @Test func chapterLengthOutOfBoundsReturnsZero() {
        let index = TXTChapterOffsetIndex.build(from: threeChapterIndex())
        #expect(index.chapterLength(-1) == 0)
        #expect(index.chapterLength(99) == 0)
    }

    @Test func chapterLocalFractionAtChapterStartIsZero() {
        let index = TXTChapterOffsetIndex.build(from: threeChapterIndex())
        let r0 = index.chapterLocalFraction(globalUTF16: 0)
        #expect(r0.chapterIdx == 0)
        #expect(r0.fraction == 0.0)
        let r1 = index.chapterLocalFraction(globalUTF16: 100)
        #expect(r1.chapterIdx == 1)
        #expect(r1.fraction == 0.0)
    }

    @Test func chapterLocalFractionNearChapterEndApproachesOne() {
        let index = TXTChapterOffsetIndex.build(from: threeChapterIndex())
        // ch0 length 100; offset 99 → 0.99
        let r = index.chapterLocalFraction(globalUTF16: 99)
        #expect(r.chapterIdx == 0)
        #expect(abs(r.fraction - 0.99) < 0.0001)
    }

    @Test func chapterLocalFractionMonotonicWithinChapter() {
        let index = TXTChapterOffsetIndex.build(from: threeChapterIndex())
        // ch1 spans [100,250) length 150.
        let a = index.chapterLocalFraction(globalUTF16: 100).fraction
        let b = index.chapterLocalFraction(globalUTF16: 175).fraction
        let c = index.chapterLocalFraction(globalUTF16: 249).fraction
        #expect(a < b)
        #expect(b < c)
    }

    @Test func chapterLocalFractionClampedZeroLengthChapter() {
        let zeroLen = TXTChapterIndex(
            chapters: [TXTChapter(index: 0, title: "Empty", startByte: 0,
                                  endByte: 0, globalStartUTF16: 0,
                                  textLengthUTF16: 0)],
            totalBytes: 0, detectedEncoding: "UTF-8", totalTextLengthUTF16: 0
        )
        let index = TXTChapterOffsetIndex.build(from: zeroLen)
        let r = index.chapterLocalFraction(globalUTF16: 0)
        #expect(r.chapterIdx == 0)
        #expect(r.fraction == 0.0)
    }

    @Test func binarySearchCorrectnessOnLargeIndex() {
        // 1000 synthetic chapters, each 100 UTF-16 units long.
        var chapters: [TXTChapter] = []
        for i in 0..<1000 {
            chapters.append(TXTChapter(
                index: i, title: "Ch\(i)",
                startByte: Int64(i * 100), endByte: Int64((i + 1) * 100),
                globalStartUTF16: i * 100, textLengthUTF16: 100
            ))
        }
        let big = TXTChapterIndex(
            chapters: chapters, totalBytes: 100_000,
            detectedEncoding: "UTF-8", totalTextLengthUTF16: 100_000
        )
        let index = TXTChapterOffsetIndex.build(from: big)
        // Spot-check arbitrary offsets.
        #expect(index.chapterContaining(0) == 0)
        #expect(index.chapterContaining(50) == 0)
        #expect(index.chapterContaining(100) == 1)
        #expect(index.chapterContaining(49_950) == 499)
        #expect(index.chapterContaining(99_999) == 999)
        #expect(index.chapterContaining(100_000) == 999)
    }
}
