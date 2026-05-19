// Purpose: Tests for the continuous-scroll additions to TXTChunkedReaderBridge
// (Bug #180 re-scoped fix, WI-4) — the document-global-offset → chunk-index
// resolution that backs `restoreGlobalOffset` and `scrollToGlobalOffset`, plus
// regression guards that the new optional params default safely.
//
// Tests live in vreaderTests/Views/Reader/ to mirror the source path.

#if canImport(UIKit)
import Testing
import UIKit
import Foundation
@testable import vreader

@Suite("TXTChunkedReaderBridge continuous-scroll restore")
@MainActor
struct TXTChunkedReaderBridgeRestoreTests {

    // 3 chunks: [0,100), [100,260), [260,400).
    private let offsets = [0, 100, 260]
    private let chunkLengths = [100, 160, 140]

    @Test func chunkIndexForGlobalOffsetAtChunkStarts() {
        #expect(TXTChunkedReaderBridge.chunkIndex(forGlobalOffset: 0, chunkStartOffsets: offsets) == 0)
        #expect(TXTChunkedReaderBridge.chunkIndex(forGlobalOffset: 100, chunkStartOffsets: offsets) == 1)
        #expect(TXTChunkedReaderBridge.chunkIndex(forGlobalOffset: 260, chunkStartOffsets: offsets) == 2)
    }

    @Test func chunkIndexForGlobalOffsetMidChunk() {
        #expect(TXTChunkedReaderBridge.chunkIndex(forGlobalOffset: 50, chunkStartOffsets: offsets) == 0)
        #expect(TXTChunkedReaderBridge.chunkIndex(forGlobalOffset: 99, chunkStartOffsets: offsets) == 0)
        #expect(TXTChunkedReaderBridge.chunkIndex(forGlobalOffset: 175, chunkStartOffsets: offsets) == 1)
        #expect(TXTChunkedReaderBridge.chunkIndex(forGlobalOffset: 399, chunkStartOffsets: offsets) == 2)
    }

    @Test func chunkIndexForGlobalOffsetBeyondEndClampsToLast() {
        #expect(TXTChunkedReaderBridge.chunkIndex(forGlobalOffset: 400, chunkStartOffsets: offsets) == 2)
        #expect(TXTChunkedReaderBridge.chunkIndex(forGlobalOffset: 99_999, chunkStartOffsets: offsets) == 2)
    }

    @Test func chunkIndexForGlobalOffsetNegativeClampsToFirst() {
        #expect(TXTChunkedReaderBridge.chunkIndex(forGlobalOffset: -1, chunkStartOffsets: offsets) == 0)
    }

    @Test func chunkIndexForGlobalOffsetEmptyOffsetsReturnsNil() {
        #expect(TXTChunkedReaderBridge.chunkIndex(forGlobalOffset: 50, chunkStartOffsets: []) == nil)
    }

    @Test func intraChunkFractionAtChunkStartIsZero() {
        // Offset exactly at chunk-1 start → fraction 0 within chunk 1.
        let f = TXTChunkedReaderBridge.intraChunkFraction(
            forGlobalOffset: 100, chunkIndex: 1,
            chunkStartOffsets: offsets, chunkUTF16Lengths: chunkLengths
        )
        #expect(f == 0.0)
    }

    @Test func intraChunkFractionMidChunk() {
        // Chunk 1 spans [100,260), length 160; offset 180 → (180-100)/160 = 0.5.
        let f = TXTChunkedReaderBridge.intraChunkFraction(
            forGlobalOffset: 180, chunkIndex: 1,
            chunkStartOffsets: offsets, chunkUTF16Lengths: chunkLengths
        )
        #expect(abs(f - 0.5) < 0.0001)
    }

    @Test func intraChunkFractionZeroLengthChunkIsZero() {
        let f = TXTChunkedReaderBridge.intraChunkFraction(
            forGlobalOffset: 100, chunkIndex: 0,
            chunkStartOffsets: [0], chunkUTF16Lengths: [0]
        )
        #expect(f == 0.0)
    }

    @Test func bridgeDefaultsLeaveContinuousParamsNil() {
        // Regression guard: a large-file caller that does NOT pass the new
        // continuous params must see them default to nil.
        let bridge = TXTChunkedReaderBridge(
            chunks: ["abc"],
            config: TXTViewConfig(),
            delegate: nil,
            chunkStartOffsets: [0]
        )
        #expect(bridge.chapterOffsetIndex == nil)
        #expect(bridge.restoreGlobalOffset == nil)
    }

    @Test func bridgeAcceptsContinuousParams() {
        let chapterIndex = TXTChapterIndex(
            chapters: [TXTChapter(index: 0, title: "One", startByte: 0,
                                  endByte: 50, globalStartUTF16: 0,
                                  textLengthUTF16: 50)],
            totalBytes: 50, detectedEncoding: "UTF-8", totalTextLengthUTF16: 50
        )
        let offsetIndex = TXTChapterOffsetIndex.build(from: chapterIndex)
        let bridge = TXTChunkedReaderBridge(
            chunks: ["chunk text"],
            config: TXTViewConfig(),
            delegate: nil,
            chunkStartOffsets: [0],
            chapterOffsetIndex: offsetIndex,
            restoreGlobalOffset: 42
        )
        #expect(bridge.chapterOffsetIndex == offsetIndex)
        #expect(bridge.restoreGlobalOffset == 42)
    }
}
#endif
