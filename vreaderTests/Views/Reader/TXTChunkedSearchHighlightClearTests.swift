// Purpose: Regression tests for bug #232 / GH #960 — the chunked TXT bridge
// (`TXTChunkedReaderBridge`, the `UITableView` renderer for large /
// continuous-chaptered TXT) must clear a temporary search/navigation highlight
// on a NEW SEARCH (`.searchHighlightClear` notification) and on a USER-DRIVEN
// SCROLL, matching the non-chunked `TXTTextViewBridgeCoordinator`.
//
// Pre-fix: `TXTChunkedReaderBridge.Coordinator.init` was bare
// (`self.delegate = delegate` only) — no `.searchHighlightClear` observer; its
// `scrollViewDidScroll` / `scrollViewDidEndDecelerating` only reported scroll
// position. The temporary highlight cleared ONLY via the 3 s auto-clear timer.
//
// @coordinates-with TXTChunkedReaderBridge.swift, TXTChunkedHighlightHelper.swift,
//   TXTTextViewBridgeCoordinator.swift (sister non-chunked path),
//   SearchViewModel.swift, ReaderNotifications.swift

#if canImport(UIKit)
import Testing
import Foundation
import UIKit
@testable import vreader

@Suite("TXTChunkedSearchHighlightClear — bug #232 / GH #960")
@MainActor
struct TXTChunkedSearchHighlightClearTests {

    /// Two 10-char chunks (UTF-16): chunk 0 = offsets 0–9, chunk 1 = 10–19.
    private func makeCoordinator() -> TXTChunkedReaderBridge.Coordinator {
        let coord = TXTChunkedReaderBridge.Coordinator(delegate: nil)
        coord.chunks = ["abcdefghij", "klmnopqrst"]
        coord.chunkStartOffsets = [0, 10]
        return coord
    }

    /// Applies a temporary highlight to chunk 1 (global 12–14 → chunk-local 2–4)
    /// against a bare table view (no visible cell → deferred timer path).
    private func applyTemporaryHighlight(
        _ coord: TXTChunkedReaderBridge.Coordinator, in tableView: UITableView
    ) {
        coord.applyHighlight(NSRange(location: 12, length: 3), in: tableView, isTemporary: true)
    }

    // MARK: - New search (.searchHighlightClear notification)

    @Test
    func newSearch_clearsTemporaryHighlight() {
        let coord = makeCoordinator()
        let tableView = UITableView()
        coord.tableView = tableView
        applyTemporaryHighlight(coord, in: tableView)
        #expect(coord.activeHighlightChunkIndex == 1, "precondition: temporary highlight applied")

        // SearchViewModel posts this on a new query (SearchViewModel.swift:109).
        NotificationCenter.default.post(name: .searchHighlightClear, object: nil)

        #expect(coord.activeHighlightChunkIndex == nil,
                "a new search must clear the chunked temporary highlight's active chunk index")
        #expect(coord.activeHighlightLocalRange == nil,
                "a new search must clear the chunked temporary highlight's active local range")
        #expect(coord.highlightClearTimer == nil,
                "a new search must invalidate the pending auto-clear timer")
        #expect(coord.pendingAutoClearForChunk == nil,
                "a new search must clear the deferred-timer flag")
    }

    @Test
    func newSearch_nilsLastHighlightRange_noStaleRepaint() {
        // Bug #154 / GH #443 lockstep contract: the coordinator's
        // `lastHighlightRange` must also clear, otherwise the next
        // `updateUIView` highlight-diff would see no change and skip the
        // re-paint of a (correctly) re-applied highlight.
        let coord = makeCoordinator()
        let tableView = UITableView()
        coord.tableView = tableView
        applyTemporaryHighlight(coord, in: tableView)
        coord.lastHighlightRange = NSRange(location: 12, length: 3)

        NotificationCenter.default.post(name: .searchHighlightClear, object: nil)

        #expect(coord.lastHighlightRange == nil,
                "a new search must reset lastHighlightRange so the model and coordinator clear in lockstep")
    }

    @Test
    func newSearch_firesOnTemporaryHighlightClearedOnce() {
        // Mirrors the non-chunked `coordinatorFiresClearCallbackOnSearchHighlightClear`.
        let coord = makeCoordinator()
        let tableView = UITableView()
        coord.tableView = tableView
        applyTemporaryHighlight(coord, in: tableView)
        var clearCallbackFireCount = 0
        coord.onTemporaryHighlightCleared = { clearCallbackFireCount += 1 }

        NotificationCenter.default.post(name: .searchHighlightClear, object: nil)

        #expect(clearCallbackFireCount == 1,
                "clearing the chunked temporary highlight on a new search must notify the container exactly once")
    }

    @Test
    func newSearch_noHighlight_doesNotFireCallback() {
        // A stray `.searchHighlightClear` when nothing is showing must be a
        // no-op — no redundant `uiState.highlightRange` nil.
        let coord = makeCoordinator()
        let tableView = UITableView()
        coord.tableView = tableView
        var clearCallbackFireCount = 0
        coord.onTemporaryHighlightCleared = { clearCallbackFireCount += 1 }

        NotificationCenter.default.post(name: .searchHighlightClear, object: nil)

        #expect(clearCallbackFireCount == 0,
                "no highlight showing — a new search must not fire the model-clear callback")
        #expect(coord.activeHighlightChunkIndex == nil)
    }

    @Test
    func newSearch_idempotent_acrossRepeatedNotifications() {
        let coord = makeCoordinator()
        let tableView = UITableView()
        coord.tableView = tableView
        applyTemporaryHighlight(coord, in: tableView)
        var clearCallbackFireCount = 0
        coord.onTemporaryHighlightCleared = { clearCallbackFireCount += 1 }

        NotificationCenter.default.post(name: .searchHighlightClear, object: nil)
        NotificationCenter.default.post(name: .searchHighlightClear, object: nil)

        #expect(coord.activeHighlightChunkIndex == nil)
        #expect(clearCallbackFireCount == 1,
                "the second .searchHighlightClear has nothing to clear — callback fires once total")
    }

    // MARK: - New search must NOT clear a persistent (user-created) highlight

    @Test
    func newSearch_preservesPersistentHighlight() {
        // A user-created (non-temporary) highlight must survive a new search —
        // only the temporary search/navigation highlight clears.
        let coord = makeCoordinator()
        let tableView = UITableView()
        coord.tableView = tableView
        coord.applyHighlight(NSRange(location: 12, length: 3), in: tableView, isTemporary: false)
        #expect(coord.activeHighlightChunkIndex == 1, "precondition: persistent highlight applied")
        var clearCallbackFireCount = 0
        coord.onTemporaryHighlightCleared = { clearCallbackFireCount += 1 }

        NotificationCenter.default.post(name: .searchHighlightClear, object: nil)

        #expect(coord.activeHighlightChunkIndex == 1,
                "a new search must NOT clear a persistent user-created highlight")
        #expect(clearCallbackFireCount == 0,
                "a persistent highlight is not a temporary one — the model-clear callback must not fire")
    }

    // MARK: - User-driven scroll

    @Test
    func userScroll_clearsTemporaryHighlight() {
        let coord = makeCoordinator()
        let tableView = UITableView()
        coord.tableView = tableView
        applyTemporaryHighlight(coord, in: tableView)
        #expect(coord.activeHighlightChunkIndex == 1)

        // A user-driven scroll: a table view that is being dragged.
        coord.clearTemporaryHighlightIfNeeded(scrollView: DraggingScrollView())

        #expect(coord.activeHighlightChunkIndex == nil,
                "a user-driven scroll must clear the chunked temporary highlight")
        #expect(coord.highlightClearTimer == nil)
    }

    @Test
    func userScroll_firesOnTemporaryHighlightCleared() {
        let coord = makeCoordinator()
        let tableView = UITableView()
        coord.tableView = tableView
        applyTemporaryHighlight(coord, in: tableView)
        var clearCallbackFireCount = 0
        coord.onTemporaryHighlightCleared = { clearCallbackFireCount += 1 }

        coord.clearTemporaryHighlightIfNeeded(scrollView: DraggingScrollView())

        #expect(clearCallbackFireCount == 1,
                "a user-driven scroll clearing the chunked temporary highlight must notify the container once")
    }

    @Test
    func programmaticScroll_preservesTemporaryHighlight() {
        // Bug #99's canonical signal: a programmatic scroll (and the late
        // layout-driven callbacks it dispatches) has isTracking / isDragging /
        // isDecelerating all false — it must NOT clear the highlight.
        let coord = makeCoordinator()
        let tableView = UITableView()
        coord.tableView = tableView
        applyTemporaryHighlight(coord, in: tableView)
        #expect(coord.activeHighlightChunkIndex == 1)

        // An idle scroll view — the shape of a programmatic-scroll layout callback.
        coord.clearTemporaryHighlightIfNeeded(scrollView: UIScrollView())

        #expect(coord.activeHighlightChunkIndex == 1,
                "a programmatic scroll must NOT clear the chunked temporary highlight")
    }

    @Test
    func userScroll_preservesPersistentHighlight() {
        let coord = makeCoordinator()
        let tableView = UITableView()
        coord.tableView = tableView
        coord.applyHighlight(NSRange(location: 12, length: 3), in: tableView, isTemporary: false)
        #expect(coord.activeHighlightChunkIndex == 1)

        coord.clearTemporaryHighlightIfNeeded(scrollView: DraggingScrollView())

        #expect(coord.activeHighlightChunkIndex == 1,
                "a user scroll must NOT clear a persistent user-created highlight")
    }

    @Test
    func userScroll_noHighlight_doesNotFireCallback() {
        let coord = makeCoordinator()
        let tableView = UITableView()
        coord.tableView = tableView
        var clearCallbackFireCount = 0
        coord.onTemporaryHighlightCleared = { clearCallbackFireCount += 1 }

        coord.clearTemporaryHighlightIfNeeded(scrollView: DraggingScrollView())

        #expect(clearCallbackFireCount == 0,
                "no highlight showing — a user scroll must not fire the model-clear callback")
    }

    @Test
    func scrollViewDidScroll_userDriven_clearsTemporaryHighlight() {
        // End-to-end through the actual UIScrollViewDelegate callback the
        // table view dispatches — confirms the delegate path is wired, not
        // just the helper.
        let coord = makeCoordinator()
        let tableView = UITableView()
        coord.tableView = tableView
        applyTemporaryHighlight(coord, in: tableView)
        #expect(coord.activeHighlightChunkIndex == 1)

        coord.scrollViewDidScroll(DraggingScrollView())

        #expect(coord.activeHighlightChunkIndex == nil,
                "scrollViewDidScroll for a user-driven scroll must clear the chunked temporary highlight")
    }
}

/// A `UIScrollView` whose `isDragging` reports `true`, so the chunked
/// coordinator's user-scroll guard treats a callback against it as a
/// user-driven scroll. `isDragging` has no public setter, so a subclass
/// override is the only way to fixture this without a live touch sequence.
private final class DraggingScrollView: UIScrollView {
    override var isDragging: Bool { true }
}
#endif
