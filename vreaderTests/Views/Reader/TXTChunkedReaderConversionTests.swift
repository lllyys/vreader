// Purpose: Tests the per-chunk Simplified/Traditional conversion helper used by
// the scroll-layout / continuous chaptered TXT reader (TXTChunkedReaderBridge).
// Bug #1230 / GH #1230: conversion was applied only on the paged path; the
// default scroll path rendered raw text. This pins the pure helper that the
// Coordinator's `attributedString(forChunk:)` now calls.
//
// Invariant under test: the RENDERED chunk text is converted, but UTF-16 length
// is preserved for BMP CJK (1:1) — so chunkStartOffsets / position math stay in
// source coordinates (mirrors the paged path's "offsetMap discarded" precedent).

import Testing
import Foundation
@testable import vreader

@Suite("TXTChunkedReaderConversion")
struct TXTChunkedReaderConversionTests {

    @Test func simpToTrad_convertsRenderedText() {
        // 国学书 (Simplified) → 國學書 (Traditional) — same pairs as SimpTradTransformTests.
        let rendered = TXTChunkedReaderBridge.renderedChunkText(
            "国学书", conversion: .simpToTrad
        )
        #expect(rendered == "國學書")
    }

    @Test func tradToSimp_convertsRenderedText() {
        let rendered = TXTChunkedReaderBridge.renderedChunkText(
            "國學書", conversion: .tradToSimp
        )
        #expect(rendered == "国学书")
    }

    @Test func none_returnsRawUnchanged() {
        let raw = "国学书"
        let rendered = TXTChunkedReaderBridge.renderedChunkText(raw, conversion: .none)
        #expect(rendered == raw)
    }

    @Test func utf16Length_preservedForBMPCJK() {
        // Offset-invariant guarantee: BMP CJK is 1:1 UTF-16, so converting the
        // rendered text must NOT change UTF-16 length (chunk offsets stay valid).
        let raw = "这是一段中文测试文本国学书"
        let rendered = TXTChunkedReaderBridge.renderedChunkText(raw, conversion: .simpToTrad)
        #expect(raw.utf16.count == rendered.utf16.count)
    }

    @Test func emptyString_returnsEmpty() {
        #expect(TXTChunkedReaderBridge.renderedChunkText("", conversion: .simpToTrad) == "")
        #expect(TXTChunkedReaderBridge.renderedChunkText("", conversion: .none) == "")
    }
}
