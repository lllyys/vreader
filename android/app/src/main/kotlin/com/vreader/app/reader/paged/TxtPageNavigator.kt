// Purpose: feature #137 WI-5 (#110 Phase 3, box E) — the page-navigation state manager that sits
// between the TxtPaginator/TxtPageIndex layer and the HorizontalPager. It is the ONLY holder of the
// "which page am I on" state, kept Compose-FREE so it is fully JVM-testable.
//
// Feature #138 WI-4 DELEGATES the pagination LIFECYCLE to PaginationSession — the navigator no longer
// owns the pagination token / whole-doc index() pass. The SESSION owns the cursor + sealed list +
// token/generation + publication; the navigator drives the session and mirrors its published
// (possibly PARTIAL, growing) snapshots into its pager-position state.
//
// Responsibilities:
//   • offset↔page convenience over the CURRENT immutable index (delegates to TxtPageIndex).
//   • reflow reconciliation (Gate-2 R2-Medium-2): a settings/rotation change re-opens WINDOWED
//     pagination; the navigator (1) CAPTURES the current source UTF-16 offset, (2) delegates to
//     PaginationSession.openFromStart from that captured offset (which supersedes any in-flight pass
//     via its generation token so a stale pass never publishes), and (3) on EVERY published snapshot
//     CLAMPS currentPage/pendingScrollTarget to snapshot.pageContaining(capturedOffset) — so font/
//     rotation reflow lands on the captured offset's page as soon as it seals (count grew OR shrank).
//   • async source-offset jump (WI-4): jumpToOffset(offset, session) — within the sealed region it is
//     the synchronous path; BEYOND the frontier it session.ensureMeasuredThrough(offset) first (off-
//     main, coalesced), installs the extended snapshot, THEN resolves the page. The jump is EVENTUAL
//     for a beyond-frontier offset.
//   • a thin HorizontalPager state SEAM: `currentPage` (the pager's live page), `onPagerPageChanged`
//     (a user swipe reports back), and `pendingScrollTarget`/`consumePendingScrollTarget` (the page to
//     PROGRAMMATICALLY scroll the pager to after a reflow or an offset jump). The navigator exposes the
//     PURE state; the WI-5b host binds them to a PagerState.
//
// @coordinates-with: TxtPageIndex.kt (offset↔page delegation), TxtPaginator.kt (the paginator the
//   session drives + its PageContentBox/LineMeasurer), PaginationSession.kt (WI-4 — the lifecycle
//   owner this navigator delegates to), TxtReaderBody.kt (WI-5b — binds currentPage/pendingScrollTarget
//   to a PagerState).
package com.vreader.app.reader.paged

import androidx.compose.ui.text.TextStyle
import com.vreader.app.reader.TxtDocument
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * Plain page-navigation state over a [TxtPaginator], with its pagination LIFECYCLE delegated to a
 * [PaginationSession]. Construct with the same paginator the session uses; call
 * [reconcileAfterReflow] on every re-pagination trigger (passing the session).
 *
 * Compose-independent by design: the navigation LOGIC (offset↔page delegation, the clamp-to-
 * `pageContaining` reconciliation, and the pager seam) uses no Compose runtime and is JVM-testable
 * without one. The single Compose reference is the `TextStyle` parameter threaded straight through to
 * [PaginationSession.openFromStart] (for line measurement); it is never inspected here, and tests
 * construct a trivial `TextStyle()`. No `PagerState`/`HorizontalPager`/Compose-state holder leaks in —
 * the WI-5b host owns those and binds them to [currentPage]/[pendingScrollTarget].
 *
 * NOT thread-safe by design — every mutator (setIndex/onPagerPageChanged/jumpToOffset/
 * reconcileAfterReflow and the session's publish continuation) runs on the UI thread / test scheduler,
 * exactly like a Compose `@Observable` state holder. The SESSION owns the off-main measure passes +
 * the token/generation; the navigator's snapshot-mirroring step touches navigator state only.
 */
class TxtPageNavigator(private val paginator: TxtPaginator) {

    /** The current immutable boundary index, or null before the first window publishes. */
    var index: TxtPageIndex? = null
        private set

    /** The pager's current page (0-based). Stays valid (clamped) across a reflow / append. */
    var currentPage: Int = 0
        private set

    /**
     * The page the pager should be PROGRAMMATICALLY scrolled to (a reflow clamp or an offset jump),
     * or null when there is nothing pending. The WI-5b `LaunchedEffect` reads it via
     * [consumePendingScrollTarget] and animates/snaps the `PagerState`. A user swipe
     * ([onPagerPageChanged]) must NOT set this (it would fight the pager).
     */
    var pendingScrollTarget: Int? = null
        private set

    /** True when the current index is the degrade-to-scroll signal (degenerate content box). */
    val isDegenerate: Boolean get() = index?.isDegenerate == true

    /** True once the session has published a COMPLETE (whole-book) index — the body can observe it. */
    val isComplete: Boolean get() = index?.isComplete ?: false

    /**
     * The generation token of the in-flight LEGACY-reflow pass (the whole-doc [reconcileAfterReflow]
     * overload that does NOT take a session — retained for backward compat). The WINDOWED overload owns
     * its token inside the [PaginationSession]; this field is null on that path.
     */
    var activeToken: PaginationToken? = null
        private set

    /** Monotonic legacy-reflow generation — the newest whole-doc pass wins; an older publish is dropped. */
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
     * Programmatically move to the page containing source [sourceOffsetUtf16] over the CURRENT index
     * (the synchronous, within-sealed-region path — a bookmark / search / scrubber jump). Sets
     * [currentPage] AND queues a [pendingScrollTarget]. For a beyond-frontier offset on a PARTIAL index
     * the caller MUST use the [jumpToOffset]`(offset, session)` overload so the frontier is extended
     * first; this overload clamps to the last sealed page as a fallback.
     */
    fun jumpToOffset(sourceOffsetUtf16: Int) {
        val target = pageContaining(sourceOffsetUtf16)
        currentPage = target
        pendingScrollTarget = target
    }

    /**
     * Programmatically move to the page containing source [sourceOffsetUtf16] (a bookmark / search /
     * scrubber / TTS jump), delegating any beyond-frontier extension to [session]. Within the SEALED
     * region it is the synchronous path (no measuring). BEYOND the frontier (a PARTIAL index whose
     * frontier is `<= offset`) it calls [PaginationSession.ensureMeasuredThrough] first (off-main,
     * coalesced with the background loop), INSTALLS the extended snapshot, THEN resolves the page —
     * the jump is EVENTUAL for a beyond-frontier offset. Sets [currentPage] AND queues a
     * [pendingScrollTarget] for the pager.
     */
    suspend fun jumpToOffset(sourceOffsetUtf16: Int, session: PaginationSession) {
        val current = index
        // Beyond the sealed frontier of a PARTIAL index → extend then install before resolving.
        if (current != null && !current.isComplete && sourceOffsetUtf16 >= current.frontierSourceOffset) {
            val extended = session.ensureMeasuredThrough(sourceOffsetUtf16)
            index = extended
        }
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

    // --- reflow reconciliation ------------------------------------------------------------------

    /**
     * LEGACY whole-doc reflow (retained for backward compat; superseded by the [session]-taking
     * overload which windows the pass). Re-paginate [document] against [contentBox] with a single
     * blocking [TxtPaginator.index] pass and clamp the position to the captured source offset. Owns its
     * own [PaginationToken]/[generation] (the windowed overload delegates those to the session).
     *
     * A [CancellationException] from a pass THIS navigator superseded (token cancelled or a newer
     * generation started) is swallowed. A cancellation from ANY OTHER source (parent scope/job) is
     * RE-THROWN so structured concurrency is honored.
     */
    fun reconcileAfterReflow(
        document: TxtDocument,
        style: TextStyle,
        contentBox: PageContentBox,
        measurer: LineMeasurer,
        isMarkdown: Boolean,
        scope: CoroutineScope,
    ) {
        val capturedOffset = currentSourceOffset()
        activeToken?.cancel()
        val myGeneration = ++generation
        val token = PaginationToken()
        activeToken = token

        scope.launch {
            val newIndex = try {
                paginator.index(document, style, contentBox, measurer, token, isMarkdown)
            } catch (e: CancellationException) {
                if (activeToken === token) activeToken = null
                if (token.isCancelled || myGeneration != generation) return@launch
                throw e
            }
            if (myGeneration != generation) {
                if (activeToken === token) activeToken = null
                return@launch
            }
            publishReflow(newIndex, capturedOffset, token)
        }
    }

    /** Publish a completed LEGACY reflow pass: install the new index + clamp the position to the anchor. */
    private fun publishReflow(newIndex: TxtPageIndex, capturedOffset: Int, token: PaginationToken) {
        index = newIndex
        if (activeToken === token) activeToken = null
        val target = newIndex.pageContaining(capturedOffset)
        currentPage = target
        pendingScrollTarget = target
    }

    /**
     * Re-open WINDOWED pagination of [document] against [contentBox] and reconcile the pager position
     * across the page-count change (Gate-2 R2-Medium-2), DELEGATING the lifecycle to [session]:
     *  1. CAPTURE the current source offset (the current page's start) BEFORE the new pass — so the
     *     resume anchor is the layout-independent source offset, not a page number the new pagination
     *     invalidates.
     *  2. Delegate to [PaginationSession.openFromStart] on [scope] from that captured offset. The
     *     session supersedes any in-flight pass via its generation token (a stale pass never publishes),
     *     publishes the first sealed window fast, then background-completes.
     *  3. On EVERY published snapshot, install it and CLAMP [currentPage]/[pendingScrollTarget] to
     *     `snapshot.pageContaining(capturedOffset)` — so as pages append (count grows) the position
     *     lands on the captured offset's page as soon as it seals. A degenerate or empty snapshot
     *     degrades safely — `pageContaining` returns 0, no crash.
     *
     * [onSnapshot] is an OPTIONAL caller observer (e.g. the WI-5b body mirroring the growing count into
     * Compose state); it runs after the navigator's own state update, lock-released.
     */
    fun reconcileAfterReflow(
        document: TxtDocument,
        style: TextStyle,
        contentBox: PageContentBox,
        measurer: LineMeasurer,
        isMarkdown: Boolean,
        scope: CoroutineScope,
        session: PaginationSession,
        onSnapshot: (TxtPageIndex) -> Unit = {},
    ) {
        // 1. Capture the resume anchor as a source offset (layout-independent) BEFORE re-measuring.
        val capturedOffset = currentSourceOffset()

        // 2/3. Delegate to the session; each published snapshot clamps the position to the anchor.
        scope.launch {
            session.openFromStart(
                document = document, style = style, contentBox = contentBox, measurer = measurer,
                isMarkdown = isMarkdown, resumeAnchorOffset = capturedOffset,
                onSnapshot = { snapshot ->
                    installReflowSnapshot(snapshot, capturedOffset)
                    onSnapshot(snapshot)
                },
                onReveal = { /* the deep-resume auto-scroll decision belongs to the body (WI-5b) */ },
            )
        }
    }

    /**
     * Install a session snapshot during a reflow: set the index + clamp the position to the anchor.
     * Issue a [pendingScrollTarget] ONLY once the captured offset is actually SEALED (within the
     * snapshot's frontier), OR the snapshot is complete — so a PARTIAL snapshot whose frontier is short
     * of the captured offset does NOT enqueue a scroll to a clamped (wrong, transient) last-sealed page
     * (the pager would visibly chase the growing frontier). `currentPage` still clamps so the index
     * stays consistent; the real scroll lands once the anchor's page is known.
     */
    private fun installReflowSnapshot(newIndex: TxtPageIndex, capturedOffset: Int) {
        index = newIndex
        // Clamp to the page containing the captured source offset — count grown OR shrank, degenerate
        // or empty (pageContaining returns 0 for a zero-page index — safe degrade, no crash).
        val target = newIndex.pageContaining(capturedOffset)
        currentPage = target
        // Only queue a programmatic scroll when the captured offset is genuinely covered — never to a
        // clamped last-sealed page while the frontier is still short of the anchor.
        val anchorSealed = newIndex.isComplete ||
            (newIndex.pageCount > 0 && capturedOffset.coerceAtLeast(0) < newIndex.frontierSourceOffset)
        if (anchorSealed) pendingScrollTarget = target
    }

    // --- helpers -------------------------------------------------------------------------------

    /** Clamp [page] into [idx]'s valid page range; 0 for a null/empty index. */
    private fun clampPage(page: Int, idx: TxtPageIndex?): Int {
        val count = idx?.pageCount ?: 0
        if (count <= 0) return 0
        return page.coerceIn(0, count - 1)
    }
}
