// Purpose: Regression tests for bug #99 cause #1 — chunked reader's
// auto-clear timer must not start until the highlighted cell actually
// renders. Pre-fix: timer started immediately in applyHighlight, so a
// slow scroll could let the timer fire before the user saw the
// highlight. The state machine now tracks `pendingAutoClearForChunk`
// and defers timer start to `cellForRowAt`.

#if canImport(UIKit)
import Testing
import Foundation
import UIKit
@testable import vreader

@Suite("TXTChunkedHighlight — deferred auto-clear (bug #99 cause #1)")
@MainActor
struct TXTChunkedHighlightDeferredTimerTests {

    private func makeCoordinator() -> TXTChunkedReaderBridge.Coordinator {
        let coord = TXTChunkedReaderBridge.Coordinator(delegate: nil)
        coord.chunks = ["abcdefghij", "klmnopqrst"]  // 10 chars each (UTF-16)
        coord.chunkStartOffsets = [0, 10]
        return coord
    }

    @Test
    func temporaryHighlight_invisibleCell_defersTimer() {
        let coord = makeCoordinator()
        let tableView = UITableView()  // no cells visible

        // Highlight in chunk 1 (offsets 12–14 → chunk 1, local 2–4)
        coord.applyHighlight(NSRange(location: 12, length: 3), in: tableView, isTemporary: true)

        #expect(coord.activeHighlightChunkIndex == 1)
        #expect(coord.activeHighlightLocalRange == NSRange(location: 2, length: 3))
        #expect(coord.pendingAutoClearForChunk == 1, "timer must be deferred when cell isn't visible")
        #expect(coord.highlightClearTimer == nil, "timer must NOT start until cell renders")
    }

    @Test
    func nonTemporaryHighlight_invisibleCell_noTimerNoPending() {
        let coord = makeCoordinator()
        let tableView = UITableView()

        // Permanent highlight (e.g., user-created): never auto-clears.
        coord.applyHighlight(NSRange(location: 12, length: 3), in: tableView, isTemporary: false)

        #expect(coord.activeHighlightChunkIndex == 1, "active state still recorded")
        #expect(coord.pendingAutoClearForChunk == nil, "permanent highlights don't defer a timer")
        #expect(coord.highlightClearTimer == nil, "permanent highlights don't auto-clear")
    }

    @Test
    func clearHighlight_clearsBothTimerAndPending() {
        let coord = makeCoordinator()
        let tableView = UITableView()

        coord.applyHighlight(NSRange(location: 12, length: 3), in: tableView, isTemporary: true)
        #expect(coord.pendingAutoClearForChunk == 1)

        coord.clearHighlight(in: tableView)
        #expect(coord.pendingAutoClearForChunk == nil, "clearHighlight must wipe pending too")
        #expect(coord.highlightClearTimer == nil)
    }

    @Test
    func secondApplyHighlight_supersedes_firstPendingClear() {
        let coord = makeCoordinator()
        let tableView = UITableView()

        // First call: pending for chunk 1.
        coord.applyHighlight(NSRange(location: 12, length: 3), in: tableView, isTemporary: true)
        #expect(coord.pendingAutoClearForChunk == 1)

        // Second call to a different chunk overwrites pending.
        coord.applyHighlight(NSRange(location: 3, length: 4), in: tableView, isTemporary: true)
        #expect(coord.pendingAutoClearForChunk == 0, "newer applyHighlight must reset pending to its own chunk")
        #expect(coord.activeHighlightChunkIndex == 0)
    }

    @Test
    func startHighlightAutoClearTimer_createsTimer() {
        // Direct exercise of the extracted helper (used by both the
        // already-visible path and the becomes-visible path).
        let coord = makeCoordinator()
        let tableView = UITableView()
        coord.activeHighlightChunkIndex = 1
        coord.activeHighlightLocalRange = NSRange(location: 2, length: 3)

        #expect(coord.highlightClearTimer == nil)
        coord.startHighlightAutoClearTimer(in: tableView)
        #expect(coord.highlightClearTimer != nil, "startHighlightAutoClearTimer must create the timer")
        #expect(coord.highlightClearTimer?.isValid == true)

        coord.highlightClearTimer?.invalidate()
        coord.highlightClearTimer = nil
    }

    // MARK: - Codex round-1: cellForRowAt path tests + clear-fully-resets

    @Test
    func clearHighlight_fullyResetsActiveState() {
        // Codex round-1 finding: pre-fix, clearHighlight only reset
        // visible-cell visuals + timer, but left activeHighlight*
        // populated. An off-screen chunk's later cellForRowAt would
        // still see active != nil and redraw the cleared highlight.
        let coord = makeCoordinator()
        let tableView = UITableView()
        coord.applyHighlight(NSRange(location: 12, length: 3), in: tableView, isTemporary: true)
        #expect(coord.activeHighlightChunkIndex == 1)

        coord.clearHighlight(in: tableView)

        #expect(coord.activeHighlightChunkIndex == nil, "clearHighlight must nil active chunk index")
        #expect(coord.activeHighlightLocalRange == nil, "clearHighlight must nil active local range")
        #expect(coord.pendingAutoClearForChunk == nil)
        #expect(coord.highlightClearTimer == nil)
    }

    @Test
    func cellForRowAt_pendingChunkRender_startsTimer() {
        // The render-time path: applyHighlight defers timer (cell not
        // visible), then cellForRowAt fires for the matching chunk.
        // Timer must start, pending must clear.
        let coord = makeCoordinator()
        let tableView = UITableView()
        tableView.dataSource = coord
        tableView.delegate = coord
        tableView.register(
            TXTChunkedReaderBridge.ChunkedTextCell.self,
            forCellReuseIdentifier: TXTChunkedReaderBridge.ChunkedTextCell.reuseID
        )
        coord.applyHighlight(NSRange(location: 12, length: 3), in: tableView, isTemporary: true)
        #expect(coord.pendingAutoClearForChunk == 1)
        #expect(coord.highlightClearTimer == nil)

        // Manually invoke cellForRowAt for the pending chunk index.
        _ = coord.tableView(tableView, cellForRowAt: IndexPath(row: 1, section: 0))

        #expect(coord.pendingAutoClearForChunk == nil, "cellForRowAt for pending chunk must clear pending")
        #expect(coord.highlightClearTimer != nil, "cellForRowAt for pending chunk must start timer")

        coord.highlightClearTimer?.invalidate()
        coord.highlightClearTimer = nil
    }

    @Test
    func cellForRowAt_unrelatedChunk_doesNotStartTimer() {
        // Cells for non-pending chunks render during scroll too; they
        // must not accidentally start the timer.
        let coord = makeCoordinator()
        let tableView = UITableView()
        tableView.dataSource = coord
        tableView.delegate = coord
        tableView.register(
            TXTChunkedReaderBridge.ChunkedTextCell.self,
            forCellReuseIdentifier: TXTChunkedReaderBridge.ChunkedTextCell.reuseID
        )
        coord.applyHighlight(NSRange(location: 12, length: 3), in: tableView, isTemporary: true)
        #expect(coord.pendingAutoClearForChunk == 1)

        // Render the OTHER chunk (chunk 0).
        _ = coord.tableView(tableView, cellForRowAt: IndexPath(row: 0, section: 0))

        #expect(coord.pendingAutoClearForChunk == 1, "unrelated chunk render must not clear pending")
        #expect(coord.highlightClearTimer == nil, "unrelated chunk render must not start timer")
    }
}
#endif
