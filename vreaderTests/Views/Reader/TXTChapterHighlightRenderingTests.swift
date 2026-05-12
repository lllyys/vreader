// Purpose: Tests for TXTReaderContainerView.chapterLocalHighlightRanges — the
// WI-1 static seam that translates global highlight ranges to chapter-local for
// TXTTextViewBridge rendering.
//
// @coordinates-with: TXTReaderContainerView.swift, TXTChapterHighlightHelper.swift

import Testing
import Foundation
@testable import vreader

@Suite("TXTReaderContainerView - chapterLocalHighlightRanges (WI-1)")
struct TXTChapterHighlightRenderingTests {

    // MARK: - Fixtures

    /// Three chapters at globalStart [0, 1000, 2500].
    /// ch0: [0, 1000), ch1: [1000, 2500), ch2: [2500, 3000)
    private static let chapters3 = [
        TXTChapter(index: 0, title: "Ch0", startByte: 0, endByte: 1000,
                   globalStartUTF16: 0, textLengthUTF16: 1000),
        TXTChapter(index: 1, title: "Ch1", startByte: 1000, endByte: 2500,
                   globalStartUTF16: 1000, textLengthUTF16: 1500),
        TXTChapter(index: 2, title: "Ch2", startByte: 2500, endByte: 3000,
                   globalStartUTF16: 2500, textLengthUTF16: 500),
    ]

    /// Fixture for the straddling-boundary test: ch1 = [1500, 2500).
    /// ch0: [0, 1500), ch1: [1500, 2500), ch2: [2500, 3200)
    private static let chaptersStraddling = [
        TXTChapter(index: 0, title: "Ch0", startByte: 0, endByte: 1500,
                   globalStartUTF16: 0, textLengthUTF16: 1500),
        TXTChapter(index: 1, title: "Ch1", startByte: 1500, endByte: 2500,
                   globalStartUTF16: 1500, textLengthUTF16: 1000),
        TXTChapter(index: 2, title: "Ch2", startByte: 2500, endByte: 3200,
                   globalStartUTF16: 2500, textLengthUTF16: 700),
    ]

    // MARK: - Tests

    @Test("persisted highlights from other chapters are dropped; ch1 highlight translates correctly")
    func chapterModePassesTranslatedPersistedHighlights() {
        // ch1 = [1000, 2500); global [1100, 1200) → local [100, 200) for ch1.
        // global [2600, 2700) is in ch2, must be dropped.
        let (persisted, temp) = TXTReaderContainerView.chapterLocalHighlightRanges(
            persistedGlobalRanges: [
                NSRange(location: 1100, length: 100),
                NSRange(location: 2600, length: 100),
            ],
            tempGlobalRange: nil,
            chapterIndex: 1,
            chapters: Self.chapters3
        )
        #expect(persisted.count == 1)
        #expect(persisted.first == NSRange(location: 100, length: 100),
                "ch1 persisted highlight must translate from global [1100,1200) to local [100,200)")
        #expect(temp == nil)
    }

    @Test("temp highlight translates global to chapter-local for ch1")
    func chapterModePassesTranslatedTempHighlight() {
        // ch1 = [1000, 2500); global NSRange(1100, 100) → local NSRange(100, 100).
        let (persisted, temp) = TXTReaderContainerView.chapterLocalHighlightRanges(
            persistedGlobalRanges: [],
            tempGlobalRange: NSRange(location: 1100, length: 100),
            chapterIndex: 1,
            chapters: Self.chapters3
        )
        #expect(persisted.isEmpty)
        #expect(temp == NSRange(location: 100, length: 100),
                "temp highlight must translate from global [1100,1200) to local [100,200)")
    }

    @Test("highlights from ch0 are dropped when rendering ch2")
    func chapterModeDropsOutOfChapterHighlights() {
        // global [50, 150) is entirely in ch0 [0, 1000); ch2 = [2500, 3000) — must be empty.
        let (persisted, temp) = TXTReaderContainerView.chapterLocalHighlightRanges(
            persistedGlobalRanges: [NSRange(location: 50, length: 100)],
            tempGlobalRange: NSRange(location: 50, length: 100),
            chapterIndex: 2,
            chapters: Self.chapters3
        )
        #expect(persisted.isEmpty,
                "ch0 persisted highlight must be dropped for ch2 rendering")
        #expect(temp == nil,
                "ch0 temp highlight must be dropped for ch2 rendering")
    }

    @Test("straddling highlight clips to current chapter boundary (ch1 portion only)")
    func chapterModeClipsStraddlingBoundary() {
        // Using chaptersStraddling: ch1 = [1500, 2500).
        // global [2400, 2700) straddles ch1/ch2 boundary at 2500.
        // ch1 portion: [2400, 2500) = 100 units, local = 2400 - 1500 = 900 → NSRange(900, 100).
        let (persisted, _) = TXTReaderContainerView.chapterLocalHighlightRanges(
            persistedGlobalRanges: [NSRange(location: 2400, length: 300)],
            tempGlobalRange: nil,
            chapterIndex: 1,
            chapters: Self.chaptersStraddling
        )
        #expect(persisted.count == 1)
        #expect(persisted.first == NSRange(location: 900, length: 100),
                "straddling highlight must be clipped to ch1's portion (local [900, 1000))")
    }

    @Test("out-of-bounds chapterIndex (nil chapterIndex guard) returns empty/nil")
    func chapterModeNilHighlightWhenChapterIndexNil() {
        // chapterIndex 5 is out of bounds for chapters3 (only 3 chapters).
        // Represents the nil-chapterIndex guard path in chapterReaderContent.
        let (persisted, temp) = TXTReaderContainerView.chapterLocalHighlightRanges(
            persistedGlobalRanges: [NSRange(location: 1100, length: 100)],
            tempGlobalRange: NSRange(location: 1100, length: 100),
            chapterIndex: 5,
            chapters: Self.chapters3
        )
        #expect(persisted.isEmpty,
                "out-of-bounds chapterIndex must produce empty persisted list (guard path)")
        #expect(temp == nil,
                "out-of-bounds chapterIndex must produce nil temp range (guard path)")
    }
}
