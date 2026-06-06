// Purpose: Tests for the chunked TXT reader's #74 locate-bloom mapping
// (Bug #322 / GH #1542). The chunked bridge previously had NO bloom on a
// navigate that lands on a persisted highlight (only the non-chunked path
// bloomed). This suite covers the pure decision the chunked trigger relies on:
// given a matched document-global highlight range + the chunk start offsets,
// resolve the (chunkIndex, chunk-local NSRange) for the cell whose
// `playLandingBloom` should fire — mirroring the non-chunked
// `TXTTextViewBridge.landingTrigger` + chunk-offset math.
//
// @coordinates-with: TXTChunkedReaderBridge.swift, TXTTextViewBridge.swift,
//   HighlightableTextView.swift

#if canImport(UIKit)
import Testing
import UIKit
import Foundation
@testable import vreader

@Suite("TXTChunkedReaderBridge locate bloom (Bug #322)")
@MainActor
struct TXTChunkedReaderBridgeBloomTests {

    // MARK: - Pure mapping: matched global range → (chunkIndex, chunk-local range)

    @Test func bloomTarget_chunk0_returnsLocalRangeUnshifted() {
        // chunk 0 starts at global 0, so a global [10,5) range stays [10,5).
        let target = TXTChunkedReaderBridge.landingBloomTarget(
            matchedRange: NSRange(location: 10, length: 5),
            chunkStartOffsets: [0, 100, 250]
        )
        #expect(target?.chunkIndex == 0)
        #expect(target?.chunkLocalRange == NSRange(location: 10, length: 5))
    }

    @Test func bloomTarget_laterChunk_shiftsByChunkStart() {
        // global [120,7) falls in chunk 1 (start 100) → local [20,7).
        let target = TXTChunkedReaderBridge.landingBloomTarget(
            matchedRange: NSRange(location: 120, length: 7),
            chunkStartOffsets: [0, 100, 250]
        )
        #expect(target?.chunkIndex == 1)
        #expect(target?.chunkLocalRange == NSRange(location: 20, length: 7))
    }

    @Test func bloomTarget_atChunkBoundary_resolvesToOwningChunk() {
        // global [250,4) is exactly at chunk 2's start → local [0,4).
        let target = TXTChunkedReaderBridge.landingBloomTarget(
            matchedRange: NSRange(location: 250, length: 4),
            chunkStartOffsets: [0, 100, 250]
        )
        #expect(target?.chunkIndex == 2)
        #expect(target?.chunkLocalRange == NSRange(location: 0, length: 4))
    }

    @Test func bloomTarget_emptyOffsets_returnsNil() {
        #expect(
            TXTChunkedReaderBridge.landingBloomTarget(
                matchedRange: NSRange(location: 0, length: 5),
                chunkStartOffsets: []
            ) == nil
        )
    }

    @Test func bloomTarget_zeroLengthRange_returnsNil() {
        #expect(
            TXTChunkedReaderBridge.landingBloomTarget(
                matchedRange: NSRange(location: 10, length: 0),
                chunkStartOffsets: [0, 100]
            ) == nil
        )
    }

    // MARK: - End-to-end gate: only a persisted-range match blooms

    @Test func landingTrigger_thenBloomTarget_matchBloomsCorrectChunk() {
        // A Notes/Highlights row tap: nav range exactly equals a persisted
        // highlight in chunk 1 → trigger fires + maps to (1, local).
        let persisted = [
            PaintedHighlight(range: NSRange(location: 130, length: 6), colorName: "green")
        ]
        let navRange = NSRange(location: 130, length: 6)
        let matched = TXTTextViewBridge.landingTrigger(
            highlightRange: navRange, persisted: persisted
        )
        #expect(matched?.colorName == "green")
        let target = TXTChunkedReaderBridge.landingBloomTarget(
            matchedRange: matched!.range, chunkStartOffsets: [0, 100, 250]
        )
        #expect(target?.chunkIndex == 1)
        #expect(target?.chunkLocalRange == NSRange(location: 30, length: 6))
    }

    @Test func landingTrigger_searchHit_noBloom() {
        // A search hit (range matches no persisted highlight) → no trigger,
        // so the chunked path schedules no bloom (parity with non-chunked).
        let persisted = [
            PaintedHighlight(range: NSRange(location: 130, length: 6), colorName: "green")
        ]
        let matched = TXTTextViewBridge.landingTrigger(
            highlightRange: NSRange(location: 131, length: 6), persisted: persisted
        )
        #expect(matched == nil)
    }
}
#endif
