// Purpose: feature #137 WI-5 (#110 Phase 3, box E) — the page-navigation state manager that sits
// between WI-4's TxtPaginator/TxtPageIndex and the (WI-6a) HorizontalPager. It is the ONLY holder of
// the "which page am I on" state + the reflow reconciliation logic, kept Compose-FREE so it is fully
// JVM-testable.
//
// Responsibilities:
//   • offset↔page convenience over the CURRENT immutable index (delegates to TxtPageIndex).
//   • reflow count-change reconciliation (Gate-2 R2-Medium-2): a settings/rotation change forces a
//     re-pagination; the navigator (1) CAPTURES the current source UTF-16 offset (from the current
//     page), (2) runs/awaits the NEW immutable TxtPageIndex via TxtPaginator.index (off-main, on the
//     injected dispatcher), cancellable with a monotonic PaginationToken so a stale pass never
//     publishes, and (3) CLAMPS the target page to newIndex.pageContaining(capturedOffset) — so font/
//     rotation reflow never transiently points at an invalid/wrong page (count grew OR shrank).
//   • a thin HorizontalPager state SEAM: `currentPage` (the pager's live page), `onPagerPageChanged`
//     (a user swipe reports back), and `pendingScrollTarget`/`consumePendingScrollTarget` (the page to
//     PROGRAMMATICALLY scroll the pager to after a reflow or an offset jump). The actual
//     rememberPagerState/HorizontalPager wiring is WI-6a; the navigator exposes the PURE state.
//   • generation tokens: a superseded reflow's token is cancelled and its result never publishes
//     (mirrors WI-4's TxtPaginator discipline).
//
// @coordinates-with: TxtPageIndex.kt (offset↔page delegation), TxtPaginator.kt (the index() pass this
//   drives + its PaginationToken/PageContentBox/LineMeasurer), TxtReaderBody.kt (WI-6a — binds
//   currentPage/pendingScrollTarget to a PagerState).
package com.vreader.app.reader.paged

import androidx.compose.ui.text.TextStyle
import com.vreader.app.reader.TxtDocument
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * Plain page-navigation state over a [TxtPaginator]. Construct with the same paginator the host
 * uses; call [reconcileAfterReflow] on every re-pagination trigger.
 *
 * Compose-independent by design: the navigation LOGIC (offset↔page delegation, the generation guard,
 * the clamp-to-`pageContaining` reconciliation, and the pager seam) uses no Compose runtime and is
 * JVM-testable without one. The single Compose reference is the `TextStyle` parameter threaded
 * straight through [reconcileAfterReflow] to [TxtPaginator.index] (WI-4's read-only signature
 * requires it for line measurement); it is never inspected here, and tests construct a trivial
 * `TextStyle()` with no Compose runtime. No `PagerState`/`HorizontalPager`/Compose-state holder
 * leaks in — the WI-6a host owns those and binds them to [currentPage]/[pendingScrollTarget].
 *
 * NOT thread-safe by design — every mutator (setIndex/onPagerPageChanged/jumpToOffset/
 * reconcileAfterReflow and the reflow's publish continuation) runs on the UI thread / test scheduler,
 * exactly like a Compose `@Observable` state holder. [TxtPaginator.index]'s whole-doc MEASURE pass
 * runs off-main on the injected dispatcher; only the tiny publish step touches navigator state.
 */
class TxtPageNavigator(private val paginator: TxtPaginator) {

    /** The current immutable boundary index, or null before the first pagination completes. */
    var index: TxtPageIndex? = null
        private set

    /** The pager's current page (0-based). Stays valid (clamped) across a reflow. */
    var currentPage: Int = 0
        private set

    /**
     * The page the pager should be PROGRAMMATICALLY scrolled to (a reflow clamp or an offset jump),
     * or null when there is nothing pending. WI-6a's `LaunchedEffect` reads it via
     * [consumePendingScrollTarget] and animates/snaps the `PagerState`. A user swipe
     * ([onPagerPageChanged]) must NOT set this (it would fight the pager).
     */
    var pendingScrollTarget: Int? = null
        private set

    /** True when the current index is the degrade-to-scroll signal (degenerate content box). */
    val isDegenerate: Boolean get() = index?.isDegenerate == true

    /** The generation token of the in-flight reflow pass (for tests / cancel-on-supersede). */
    var activeToken: PaginationToken? = null
        private set

    /** Monotonic reflow generation — the newest pass wins; an older publish is dropped. */
    private var generation: Long = 0

    // --- direct index install (bootstrap-from-a-known-index / tests) ---------------------------

    /**
     * Install [newIndex] directly WITHOUT re-measuring — used when the host already holds an index
     * (e.g. a restore-from-saved-state path). Clamps [currentPage] into the new index; does NOT
     * touch [pendingScrollTarget].
     */
    fun setIndex(newIndex: TxtPageIndex) {
        index = newIndex
        currentPage = clampPage(currentPage, newIndex)
    }

    // --- offset↔page convenience over the current index ----------------------------------------

    /** The page containing source UTF-16 [sourceOffsetUtf16] (0 if there is no index yet). */
    fun pageContaining(sourceOffsetUtf16: Int): Int =
        index?.pageContaining(sourceOffsetUtf16) ?: 0

    /** The source UTF-16 start offset of [page] (0 if there is no index yet). */
    fun pageStart(page: Int): Int = index?.pageStart(page) ?: 0

    /** The source UTF-16 start offset of the CURRENT page — the value a save/restore path persists. */
    fun currentSourceOffset(): Int = pageStart(currentPage)

    // --- pager seam ----------------------------------------------------------------------------

    /**
     * A user swipe (pager-driven) changed the visible page to [page]. Updates [currentPage] ONLY —
     * it must NOT set [pendingScrollTarget] (issuing a scroll target here would fight the pager the
     * user is already driving).
     */
    fun onPagerPageChanged(page: Int) {
        currentPage = clampPage(page, index)
    }

    /**
     * Programmatically move to the page containing source [sourceOffsetUtf16] (a bookmark / search /
     * scrubber jump). Sets [currentPage] AND queues a [pendingScrollTarget] for the pager.
     */
    fun jumpToOffset(sourceOffsetUtf16: Int) {
        val target = pageContaining(sourceOffsetUtf16)
        currentPage = target
        pendingScrollTarget = target
    }

    /** Read-and-clear the pending programmatic scroll target (null when nothing is pending). */
    fun consumePendingScrollTarget(): Int? {
        val t = pendingScrollTarget
        pendingScrollTarget = null
        return t
    }

    // --- reflow count-change reconciliation ----------------------------------------------------

    /**
     * Re-paginate [document] against [contentBox] and reconcile the pager position across the
     * page-count change (Gate-2 R2-Medium-2):
     *  1. CAPTURE the current source offset (the current page's start) BEFORE the new pass — so the
     *     resume anchor is the layout-independent source offset, not a page number that the new
     *     pagination invalidates.
     *  2. Cancel any in-flight reflow's token (a superseded pass never publishes) and launch the new
     *     [TxtPaginator.index] pass on [scope] (its whole-doc measure runs on the paginator's injected
     *     dispatcher, off-main).
     *  3. On completion, if this pass is STILL the newest generation, publish the new index and CLAMP
     *     [currentPage]/[pendingScrollTarget] to `newIndex.pageContaining(capturedOffset)`. A degenerate
     *     or empty new index degrades safely — `pageContaining` returns 0, no crash.
     *
     * A [CancellationException] from a pass THIS navigator superseded (its token was cancelled or a
     * newer generation started) is swallowed — that pass is intentionally dead. A cancellation from
     * ANY OTHER source (parent scope/job cancelled) is RE-THROWN so structured concurrency is honored
     * and a genuine cancel is never masked as normal completion.
     */
    fun reconcileAfterReflow(
        document: TxtDocument,
        style: TextStyle,
        contentBox: PageContentBox,
        measurer: LineMeasurer,
        isMarkdown: Boolean,
        scope: CoroutineScope,
    ) {
        // 1. Capture the resume anchor as a source offset (layout-independent) BEFORE re-measuring.
        val capturedOffset = currentSourceOffset()

        // 2. Supersede any in-flight pass — cancel its token so a stale result never publishes.
        activeToken?.cancel()
        val myGeneration = ++generation
        val token = PaginationToken()
        activeToken = token

        scope.launch {
            val newIndex = try {
                paginator.index(document, style, contentBox, measurer, token, isMarkdown)
            } catch (e: CancellationException) {
                // Only swallow OUR OWN supersession (token cancelled or a newer generation started);
                // clear the stale active-token pointer if it still points at this dead pass. Any
                // other cancellation (parent scope/job) is genuine — rethrow it.
                // Clear the stale active-token pointer BEFORE either branch — this pass is dead
                // regardless of whether the cancel was our supersession or a parent-scope cancel, so
                // `activeToken` must never keep pointing at a no-longer-running pass.
                if (activeToken === token) activeToken = null
                if (token.isCancelled || myGeneration != generation) return@launch
                throw e   // genuine parent/job cancellation — honor structured concurrency.
            }
            // 3. Publish ONLY if this is still the newest generation (guards against an out-of-order
            //    completion that the token-cancel alone might race).
            if (myGeneration != generation) {
                if (activeToken === token) activeToken = null
                return@launch
            }
            publishReflow(newIndex, capturedOffset, token)
        }
    }

    /** Publish a completed reflow pass: install the new index + clamp the position to the anchor. */
    private fun publishReflow(newIndex: TxtPageIndex, capturedOffset: Int, token: PaginationToken) {
        index = newIndex
        if (activeToken === token) activeToken = null
        // Clamp to the page containing the captured source offset — count grown OR shrank, degenerate
        // or empty (pageContaining returns 0 for a zero-page index — safe degrade, no crash).
        val target = newIndex.pageContaining(capturedOffset)
        currentPage = target
        pendingScrollTarget = target
    }

    // --- helpers -------------------------------------------------------------------------------

    /** Clamp [page] into [idx]'s valid page range; 0 for a null/empty index. */
    private fun clampPage(page: Int, idx: TxtPageIndex?): Int {
        val count = idx?.pageCount ?: 0
        if (count <= 0) return 0
        return page.coerceIn(0, count - 1)
    }
}
