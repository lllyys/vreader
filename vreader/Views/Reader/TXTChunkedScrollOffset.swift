// Purpose: Pure pixel→char mapping for the chunked TXT reader's scroll-position
// SAVE path (Bug #289). The chunked `UITableView` reports the reader's top
// reading position as a document-global UTF-16 offset; this is the geometry math
// lifted out of `TXTChunkedReaderBridge.Coordinator.reportScrollPosition` so the
// inset-handling can be unit-tested without a live table.
//
// Bug #289: the visible top of the table is at content-y
// `contentOffset.y + contentInset.top` (the Bug #179 Dynamic-Island inset shifts
// the content DOWN by `contentInset.top`). The SAVE must measure the char at that
// visible top — the same point the RESTORE's `scrollToRow(.top)` aligns to. The
// pre-fix code measured at `contentOffset.y` (omitting the inset), persisting a
// position ~`contentInset.top` px EARLIER each save → reopen drifts earlier.

import Foundation
import CoreGraphics

enum TXTChunkedScrollOffset {

    /// Document-global UTF-16 offset of the content at the table's VISIBLE top.
    ///
    /// - Parameters:
    ///   - contentOffsetY: `scrollView.contentOffset.y`.
    ///   - contentInsetTop: `tableView.contentInset.top` (the safe-area inset).
    ///   - cellOriginY: `rectForRow(at:).origin.y` of the first visible row.
    ///   - cellHeight: `rectForRow(at:).height` of that row.
    ///   - chunkStartOffset: `chunkStartOffsets[row]` — the chunk's global start.
    ///   - chunkUTF16Count: `chunks[row].utf16.count`.
    /// - Returns: `chunkStartOffset + intraOffset`, where `intraOffset` is the
    ///   fraction through the cell (at the visible top) × the chunk's UTF-16 length,
    ///   clamped to the cell. A non-positive cell height yields `chunkStartOffset`.
    static func topCharOffsetUTF16(
        contentOffsetY: CGFloat,
        contentInsetTop: CGFloat,
        cellOriginY: CGFloat,
        cellHeight: CGFloat,
        chunkStartOffset: Int,
        chunkUTF16Count: Int
    ) -> Int {
        guard cellHeight > 0 else { return chunkStartOffset }
        // Bug #289: the visible top is `contentOffset.y + contentInset.top` in
        // content coordinates — add the inset the pre-fix code dropped.
        let visibleTopY = contentOffsetY + contentInsetTop
        let scrolledPast = visibleTopY - cellOriginY
        let fraction = max(0, min(1, scrolledPast / cellHeight))
        let intraOffset = Int(fraction * CGFloat(max(0, chunkUTF16Count)))
        return chunkStartOffset + intraOffset
    }
}
