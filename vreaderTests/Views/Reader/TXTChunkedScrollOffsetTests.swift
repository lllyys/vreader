// Purpose: Tests for TXTChunkedScrollOffset — the pixel→char mapping for the
// chunked TXT reader's SAVE path. The headline case is Bug #289: the saved offset
// must be measured at the table's VISIBLE top (`contentOffset.y + contentInset.top`),
// the same point RESTORE's `scrollToRow(.top)` aligns to — NOT at `contentOffset.y`,
// which is `contentInset.top` px earlier and drifted the position earlier each save.

import Testing
import CoreGraphics
import UIKit
@testable import vreader

@Suite("TXTChunkedScrollOffset")
struct TXTChunkedScrollOffsetTests {

    // MARK: - Bug #312: glyphTopY computes a real-width layout, not per-char stacking

    /// The snap-to-top glyph y MUST be computed at the real text-column width, not
    /// the degenerate ~0 width that stacks one char per line and overscrolls a TOC
    /// jump to the end of the chunk (the overshoot that landed chapter 8 on chapter
    /// 12 during device verification). At a real width a deep offset is a handful of
    /// rows down; at a 1-char-wide column it is ~N rows down — the assertion is that
    /// the real-width result is dramatically smaller.
    @MainActor @Test func glyphTopY_realWidth_doesNotStackPerLine() {
        let attr = NSAttributedString(
            string: String(repeating: "字", count: 200),
            attributes: [.font: UIFont.systemFont(ofSize: 18)]
        )
        let wide = TXTChunkedReaderBridge.Coordinator.glyphTopY(
            forChunk: attr, localOffset: 120, textWidth: 320)!
        let degenerate = TXTChunkedReaderBridge.Coordinator.glyphTopY(
            forChunk: attr, localOffset: 120, textWidth: 18)! // ~1 CJK glyph per line
        #expect(wide >= 0)
        #expect(wide < degenerate / 4)
    }

    /// The first character of the chunk sits at the top (y == 0), so a chapter whose
    /// title begins the chunk pins exactly to the top edge.
    @MainActor @Test func glyphTopY_firstChar_isAtTop() {
        let attr = NSAttributedString(
            string: "第八章　八楼的高手\n正文……",
            attributes: [.font: UIFont.systemFont(ofSize: 18)]
        )
        let y = TXTChunkedReaderBridge.Coordinator.glyphTopY(
            forChunk: attr, localOffset: 0, textWidth: 320)!
        #expect(y == 0)
    }

    /// Guards: empty string and non-positive width return nil (caller leaves the
    /// chunk top aligned rather than crashing or misplacing).
    @MainActor @Test func glyphTopY_emptyOrZeroWidth_returnsNil() {
        let empty = NSAttributedString(string: "")
        #expect(TXTChunkedReaderBridge.Coordinator.glyphTopY(forChunk: empty, localOffset: 0, textWidth: 320) == nil)
        let attr = NSAttributedString(string: "abc", attributes: [.font: UIFont.systemFont(ofSize: 18)])
        #expect(TXTChunkedReaderBridge.Coordinator.glyphTopY(forChunk: attr, localOffset: 0, textWidth: 0) == nil)
    }

    // MARK: - Bug #289: inset is included in the measured visible top

    @Test("offset is measured at the visible top (contentOffset + inset), not contentOffset")
    func includesContentInsetTop() {
        // Reader scrolled so the visible top (below the 59pt inset) shows content
        // at content-y 500 in a 1000pt cell of 2000 UTF-16 units. Then
        // contentOffset.y = 500 - 59 = 441. The saved char offset must be the one
        // at content-y 500 → fraction 0.5 → 1000, NOT the pre-fix content-y 441.
        let offset = TXTChunkedScrollOffset.topCharOffsetUTF16(
            contentOffsetY: 441, contentInsetTop: 59,
            cellOriginY: 0, cellHeight: 1000,
            chunkStartOffset: 0, chunkUTF16Count: 2000)
        #expect(offset == 1000)
        // Pre-fix (inset dropped) would have returned 882 — the early-drift bug.
    }

    @Test("with zero inset the result is the plain contentOffset mapping")
    func zeroInsetUnchanged() {
        let offset = TXTChunkedScrollOffset.topCharOffsetUTF16(
            contentOffsetY: 500, contentInsetTop: 0,
            cellOriginY: 0, cellHeight: 1000,
            chunkStartOffset: 0, chunkUTF16Count: 2000)
        #expect(offset == 1000)
    }

    @Test("resting at the very top of a chunk yields the chunk start")
    func atChunkTop() {
        // At rest the table sits at contentOffset.y = -inset; the visible top is
        // then content-y 0 = the cell origin → intra-offset 0.
        let offset = TXTChunkedScrollOffset.topCharOffsetUTF16(
            contentOffsetY: -59, contentInsetTop: 59,
            cellOriginY: 0, cellHeight: 1000,
            chunkStartOffset: 4000, chunkUTF16Count: 2000)
        #expect(offset == 4000)
    }

    // MARK: - edges

    @Test("chunkStartOffset is added to the intra-offset")
    func addsChunkStart() {
        let offset = TXTChunkedScrollOffset.topCharOffsetUTF16(
            contentOffsetY: 441, contentInsetTop: 59,
            cellOriginY: 0, cellHeight: 1000,
            chunkStartOffset: 10_000, chunkUTF16Count: 2000)
        #expect(offset == 11_000)
    }

    @Test("fraction clamps to 1 past the cell bottom")
    func clampsHigh() {
        let offset = TXTChunkedScrollOffset.topCharOffsetUTF16(
            contentOffsetY: 5000, contentInsetTop: 59,
            cellOriginY: 0, cellHeight: 1000,
            chunkStartOffset: 0, chunkUTF16Count: 2000)
        #expect(offset == 2000)
    }

    @Test("fraction clamps to 0 above the cell top")
    func clampsLow() {
        let offset = TXTChunkedScrollOffset.topCharOffsetUTF16(
            contentOffsetY: -500, contentInsetTop: 59,
            cellOriginY: 100, cellHeight: 1000,
            chunkStartOffset: 7, chunkUTF16Count: 2000)
        #expect(offset == 7)
    }

    @Test("zero / negative cell height yields the chunk start (no NaN)")
    func zeroCellHeight() {
        #expect(TXTChunkedScrollOffset.topCharOffsetUTF16(
            contentOffsetY: 441, contentInsetTop: 59,
            cellOriginY: 0, cellHeight: 0,
            chunkStartOffset: 33, chunkUTF16Count: 2000) == 33)
    }

    @Test("a cell with origin below the viewport maps correctly")
    func cellOriginOffset() {
        // visible top = 1200 + 59 = 1259; cell starts at 1000, 1000pt tall →
        // scrolledPast 259 → fraction 0.259 → 518 (of 2000) → +chunkStart 800.
        let offset = TXTChunkedScrollOffset.topCharOffsetUTF16(
            contentOffsetY: 1200, contentInsetTop: 59,
            cellOriginY: 1000, cellHeight: 1000,
            chunkStartOffset: 800, chunkUTF16Count: 2000)
        #expect(offset == 800 + Int(0.259 * 2000))
    }
}
