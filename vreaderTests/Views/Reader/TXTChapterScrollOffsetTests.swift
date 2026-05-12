// Purpose: Tests for TXTReaderContainerView static helpers — WI-2 of Feature #48.
// Covers:
//   chapterScrubberGlobalOffset  (Part 2a — scrubber normalisation)
//   chapterLocalScrollOffset     (Part 2b — bridge-edge containment + translation)
//   TXTTextViewBridge.shouldScroll (Part 2c — dedupe reset on source change)
//
// @coordinates-with: TXTReaderContainerView.swift, TXTChapterHighlightHelper.swift,
//   TXTTextViewBridge.swift

import Testing
import Foundation
@testable import vreader

@Suite("TXTReaderContainerView - WI-2 scroll translation")
struct TXTChapterScrollOffsetTests {

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

    // MARK: - Part 2a: scrubber global normalisation

    @Test("chapterScrubberGlobalOffset: seekValue=0.5 in ch1 globalStart=1000 length=200 → global 1100")
    func chapterScrubberWritesGlobalScrollOffset() {
        let chapter = TXTChapter(index: 1, title: "Ch1", startByte: 1000, endByte: 1200,
                                 globalStartUTF16: 1000, textLengthUTF16: 200)
        let result = TXTReaderContainerView.chapterScrubberGlobalOffset(
            seekValue: 0.5, chapter: chapter
        )
        #expect(result == 1100,
                "seekValue=0.5 × length=200 + globalStart=1000 must equal 1100")
    }

    // MARK: - Part 2b: bridge-edge containment + global→local translation

    @Test("chapterLocalScrollOffset: global within chapter 1 translates correctly")
    func chapterModeTranslatesScrollOffsetWithinChapter() {
        // ch1 = [1000, 2500); global 1150 → local 150
        let result = TXTReaderContainerView.chapterLocalScrollOffset(
            globalOffset: 1150,
            chapterIndex: 1,
            chapters: Self.chapters3
        )
        #expect(result == 150,
                "global 1150 in ch1 globalStart=1000 must translate to local 150")
    }

    @Test("chapterLocalScrollOffset: global in ch2 is nil for chapterIndex=1 (containment guard)")
    func chapterModeDropsScrollOffsetForOtherChapter() {
        // global 2700 is in ch2 [2500, 3000), not in ch1 [1000, 2500) → nil
        let result = TXTReaderContainerView.chapterLocalScrollOffset(
            globalOffset: 2700,
            chapterIndex: 1,
            chapters: Self.chapters3
        )
        #expect(result == nil,
                "global 2700 (ch2) must be dropped for chapterIndex=1 (containment fails)")
    }

    @Test("chapterLocalScrollOffset: empty chapters returns nil (continuous-mode guard path)")
    func continuousModePassesScrollOffsetUntranslated() {
        // Empty chapters = no chapter index; caller uses global offset verbatim.
        let result = TXTReaderContainerView.chapterLocalScrollOffset(
            globalOffset: 500,
            chapterIndex: 0,
            chapters: []
        )
        #expect(result == nil,
                "empty chapters must return nil — caller passes global offset to bridge directly")
    }

    @Test("chapterLocalScrollOffset: ch0 globalStart=0 is a no-op translation")
    func chapterModeZeroChapterGlobalStartIsNoOpTranslation() {
        // ch0 = [0, 1000); global 50 → local 50 (globalStart=0 means no shift)
        let result = TXTReaderContainerView.chapterLocalScrollOffset(
            globalOffset: 50,
            chapterIndex: 0,
            chapters: Self.chapters3
        )
        #expect(result == 50,
                "ch0 globalStart=0: translation must be identity — local equals global")
    }

    @Test("chapterScrubberGlobalOffset: seekValue=1.0 clamps to last valid index (chapterEnd-1)")
    func chapterScrubberSeekValue1ClampsToBound() {
        let chapter = TXTChapter(index: 0, title: "Ch0", startByte: 0, endByte: 1000,
                                 globalStartUTF16: 0, textLengthUTF16: 1000)
        let result = TXTReaderContainerView.chapterScrubberGlobalOffset(seekValue: 1.0, chapter: chapter)
        #expect(result == 999, "seekValue=1.0 must clamp to length-1 (999) to stay inside half-open interval")
    }

    @Test("chapterScrubberGlobalOffset: seekValue=0.0 returns globalStart")
    func chapterScrubberSeekValue0ReturnsStart() {
        let chapter = TXTChapter(index: 0, title: "Ch0", startByte: 0, endByte: 1000,
                                 globalStartUTF16: 500, textLengthUTF16: 1000)
        let result = TXTReaderContainerView.chapterScrubberGlobalOffset(seekValue: 0.0, chapter: chapter)
        #expect(result == 500, "seekValue=0.0 must return globalStart")
    }

    @Test("chapterScrubberGlobalOffset: zero-length chapter returns globalStart")
    func chapterScrubberZeroLengthReturnsStart() {
        let chapter = TXTChapter(index: 0, title: "Ch0", startByte: 0, endByte: 0,
                                 globalStartUTF16: 200, textLengthUTF16: 0)
        let result = TXTReaderContainerView.chapterScrubberGlobalOffset(seekValue: 0.5, chapter: chapter)
        #expect(result == 200, "zero-length chapter must return globalStart to avoid underflow")
    }

    @Test("chapterLocalScrollOffset: globalOffset == chapterEnd is nil (boundary is exclusive)")
    func chapterModeDropsOffsetAtExactChapterEnd() {
        // ch1 end = 1000 + 1500 = 2500; offset 2500 is ch2 start — not in ch1
        let result = TXTReaderContainerView.chapterLocalScrollOffset(
            globalOffset: 2500,
            chapterIndex: 1,
            chapters: Self.chapters3
        )
        #expect(result == nil, "globalOffset == chapterEnd must be nil (half-open interval)")
    }

    @Test("chapterLocalScrollOffset: globalOffset == chapterEnd-1 is valid (last unit in chapter)")
    func chapterModeAcceptsLastOffsetInChapter() {
        // ch1 end = 2500; offset 2499 is the last valid unit in ch1 → local 2499-1000 = 1499
        let result = TXTReaderContainerView.chapterLocalScrollOffset(
            globalOffset: 2499,
            chapterIndex: 1,
            chapters: Self.chapters3
        )
        #expect(result == 1499, "globalOffset == chapterEnd-1 must be accepted as local 1499")
    }

    // MARK: - Part 2c: bridge scroll-dedupe reset on source text change

    @Test("TXTTextViewBridge.shouldScroll: source change resets dedupe — same target scrolls again")
    func bridgeResetsScrollDedupeOnSourceTextChange() {
        // Same target (50), source changed → dedupe reset → should scroll
        #expect(
            TXTTextViewBridge.shouldScroll(to: 50, lastTarget: 50, sourceChanged: true) == true,
            "source change must clear dedupe: same target should scroll in a new chapter context"
        )
        // Same target (50), source NOT changed → deduped → should not scroll
        #expect(
            TXTTextViewBridge.shouldScroll(to: 50, lastTarget: 50, sourceChanged: false) == false,
            "without source change, same target must be deduped"
        )
        // Different target → should always scroll regardless of source change
        #expect(
            TXTTextViewBridge.shouldScroll(to: 100, lastTarget: 50, sourceChanged: false) == true,
            "different target must always trigger scroll"
        )
        // Nil target → never scrolls
        #expect(
            TXTTextViewBridge.shouldScroll(to: nil, lastTarget: 50, sourceChanged: true) == false,
            "nil scroll target must never scroll"
        )
        // Config-only change (font/theme): callers should pass sourceChanged=false for configChanged-only;
        // same target must be deduped so font-size changes don't jump user back to stale search target.
        #expect(
            TXTTextViewBridge.shouldScroll(to: 50, lastTarget: 50, sourceChanged: false) == false,
            "config-only change (sourceChanged=false) must not re-arm scroll for same target"
        )
    }
}
