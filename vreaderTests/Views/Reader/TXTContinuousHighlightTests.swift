// Purpose: Tests for the feature-#48 highlight pipeline over the continuous-
// scroll TXT surface (Bug #180 re-scoped fix, WI-7). Verifies document-global
// highlight ranges survive the chunked bridge's chunk-local clip math —
// including ranges straddling a chapter (chunk) boundary — and that a
// highlight's chapter is derivable from its global start offset.
//
// Tests live in vreaderTests/Views/Reader/ to mirror the source path.

#if canImport(UIKit)
import Testing
import UIKit
import Foundation
@testable import vreader

@Suite("TXT continuous-scroll highlights")
@MainActor
struct TXTContinuousHighlightTests {

    /// A coordinator wired with 3 chunks: [0,100), [100,260), [260,400).
    private func makeCoordinator(persisted: [PaintedHighlight]) -> TXTChunkedReaderBridge.Coordinator {
        let coordinator = TXTChunkedReaderBridge.Coordinator(delegate: nil)
        coordinator.chunks = [
            String(repeating: "a", count: 100),
            String(repeating: "b", count: 160),
            String(repeating: "c", count: 140),
        ]
        coordinator.chunkStartOffsets = [0, 100, 260]
        coordinator.persistedHighlights = persisted
        return coordinator
    }

    @Test func documentGlobalHighlightInsideOneChunkTranslatesCorrectly() {
        // Global range [120,140) sits inside chunk 1 ([100,260)).
        let coordinator = makeCoordinator(persisted: [
            PaintedHighlight(range: NSRange(location: 120, length: 20),
                             colorName: "yellow")
        ])
        let (persisted, _) = coordinator.chunkLocalHighlightRanges(forChunk: 1)
        #expect(persisted.count == 1)
        // Chunk 1 starts at global 100 → local start 20.
        #expect(persisted[0].range.location == 20)
        #expect(persisted[0].range.length == 20)
        // Chunk 0 should see nothing.
        let (chunk0, _) = coordinator.chunkLocalHighlightRanges(forChunk: 0)
        #expect(chunk0.isEmpty)
    }

    @Test func highlightStraddlingChunkBoundarySurvivesAsTwoClippedRanges() {
        // Global range [90,150) straddles chunk-0/chunk-1 boundary at 100.
        // Each chunk's clip math must produce its own clipped slice; no loss.
        let coordinator = makeCoordinator(persisted: [
            PaintedHighlight(range: NSRange(location: 90, length: 60),
                             colorName: "yellow")
        ])
        let (chunk0, _) = coordinator.chunkLocalHighlightRanges(forChunk: 0)
        let (chunk1, _) = coordinator.chunkLocalHighlightRanges(forChunk: 1)
        // Chunk 0 ([0,100)): clipped to local [90,100) → start 90, length 10.
        #expect(chunk0.count == 1)
        #expect(chunk0[0].range.location == 90)
        #expect(chunk0[0].range.length == 10)
        // Chunk 1 ([100,260)): clipped to local [0,50) → start 0, length 50.
        #expect(chunk1.count == 1)
        #expect(chunk1[0].range.location == 0)
        #expect(chunk1[0].range.length == 50)
        // Total coverage = 10 + 50 = 60, the full original range — no loss.
        #expect(chunk0[0].range.length + chunk1[0].range.length == 60)
    }

    @Test func highlightColorIsPreservedThroughTranslation() {
        let coordinator = makeCoordinator(persisted: [
            PaintedHighlight(range: NSRange(location: 300, length: 10),
                             colorName: "green")
        ])
        let (persisted, _) = coordinator.chunkLocalHighlightRanges(forChunk: 2)
        #expect(persisted.count == 1)
        #expect(persisted[0].colorName == "green")
    }

    @Test func perHighlightChapterDerivedFromGlobalStart() {
        // 3 chapters: ch0 [0,100), ch1 [100,260), ch2 [260,400).
        let chapterIndex = TXTChapterIndex(
            chapters: [
                TXTChapter(index: 0, title: "One", startByte: 0, endByte: 100,
                           globalStartUTF16: 0, textLengthUTF16: 100),
                TXTChapter(index: 1, title: "Two", startByte: 100, endByte: 260,
                           globalStartUTF16: 100, textLengthUTF16: 160),
                TXTChapter(index: 2, title: "Three", startByte: 260, endByte: 400,
                           globalStartUTF16: 260, textLengthUTF16: 140),
            ],
            totalBytes: 400, detectedEncoding: "UTF-8", totalTextLengthUTF16: 400
        )
        let offsetIndex = TXTChapterOffsetIndex.build(from: chapterIndex)
        // A highlight starting at global 130 belongs to chapter 1.
        let highlight = NSRange(location: 130, length: 15)
        #expect(offsetIndex.chapterContaining(highlight.location) == 1)
        // A highlight starting at global 320 belongs to chapter 2.
        #expect(offsetIndex.chapterContaining(320) == 2)
        // A highlight starting at global 0 belongs to chapter 0.
        #expect(offsetIndex.chapterContaining(0) == 0)
    }

    @Test func continuousModeLocatorUsesGlobalTxtRangeBranch() {
        // WI-7: a selection in continuous mode reports document-global
        // offsets, so the locator is built with the global txtRange — not
        // the chapter-local txtChapterRange. Verify txtRange produces a
        // locator whose char range equals the global offsets passed in.
        let fp = DocumentFingerprint(
            contentSHA256: "highlight_continuous_sha_0000000000000000000000000000000000000000",
            fileByteCount: 1000, format: .txt
        )
        let locator = LocatorFactory.txtRange(
            fingerprint: fp,
            charRangeStartUTF16: 175,
            charRangeEndUTF16: 190
        )
        #expect(locator?.charRangeStartUTF16 == 175)
        #expect(locator?.charRangeEndUTF16 == 190)
        #expect(locator?.charOffsetUTF16 == 175)
    }
}
#endif
