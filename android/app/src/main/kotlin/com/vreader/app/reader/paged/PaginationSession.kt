// Purpose: feature #138 WI-4 (#110 Phase 3, box E follow-up) — the SINGLE Mutex/worker OWNER of the
// windowed pagination lifecycle. It supersedes the split ownership the navigator + body previously
// had over the pagination token + Compose index state: the cursor, the sealed page-start list, the
// ONE LineMeasurer instance, and the PaginationToken/generation all live HERE, private, guarded by ONE
// Mutex; publication is on the caller's (main) coroutine as IMMUTABLE TxtPageIndex snapshots.
//
// Commands:
//   • openFromStart(...): start a fresh doc-start-forward pass, publish the first sealed window, then
//     run a coalesced BACKGROUND completion loop that measures ONE window per mutex acquire and
//     republishes as the sealed frontier advances. Supersedes any prior generation (reflow reuses it).
//   • ensureMeasuredThrough(sourceOffset): extend the sealed frontier past a beyond-frontier offset,
//     COALESCED with the background loop under the SAME mutex, ONE window per acquire (never a single
//     unbounded run); returns the snapshot in which pageContaining(offset) is exact.
//   • snapshot(): the latest published immutable snapshot (null before the first window / after a
//     fresh open resets it).
//   • supersede(): bump the generation + cancel the active token so a stale pass never publishes
//     (reflow / dispose).
//
// The Mutex + worker supersede/publish contract (Gate-2 R2 Medium 2 — made precise):
//   • PAGE/WINDOW-sized critical sections — the mutex is NEVER held for an unbounded full-book (or
//     through-offset) run. Both the background loop AND ensureMeasuredThrough measure ONE window per
//     acquire, then release; an on-demand extend interleaves at the next window boundary.
//   • Generation check IMMEDIATELY before EVERY publish — the active generation is re-read right before
//     the AtomicReference publish (after the lock releases); a superseded/reflowed generation drops the
//     publish and the callbacks. Generation + token are @Volatile so supersede() (synchronous, no
//     coroutine) is visible to the measuring loop.
//   • Snapshot via AtomicReference, published AFTER releasing the mutation lock; NO main-thread
//     callback (onSnapshot/onReveal) runs under the lock (no lock-order inversion). Callbacks fire on
//     the CALLER's coroutine context (the body's LaunchedEffect scope / main), NOT the worker — only
//     the measure passes hop to the worker/index dispatcher.
//   • ONE writer — the background loop + every ensureMeasuredThrough share the same Mutex; the ONE
//     LineMeasurer (inside the cursor's MeasureRun) is used only under the mutex, never concurrently.
//     Newly-sealed starts are collected LOCALLY per step and committed to the shared list only with
//     the advanced cursor (so a cancel mid-step never leaves the list ahead of the cursor).
//   • onReveal fires ONCE when the resume anchor's page is first sealed, carrying the resume SOURCE
//     OFFSET. Absent (anchor == 0 / near start) — the first published snapshot already contains it.
//
// @coordinates-with: TxtPaginator.kt (freshCursor / measurePages / measureThroughOffset — the
//   resumable core it drives), TxtPageIndex.kt (the immutable sealed-partial snapshots it publishes),
//   TxtPageNavigator.kt (WI-4 — delegates its lifecycle to this session), TxtReaderBody.kt (WI-5b —
//   binds onSnapshot/onReveal into Compose state).
package com.vreader.app.reader.paged

import androidx.compose.ui.text.TextStyle
import com.vreader.app.reader.TxtDocument
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.concurrent.atomic.AtomicReference
import kotlin.coroutines.CoroutineContext

/**
 * The single owner of the incremental windowed-pagination lifecycle over a [TxtPaginator].
 *
 * @param paginator the resumable-core paginator whose freshCursor/measurePages/measureThroughOffset
 *   entry points this session drives (WI-1/2/3). Those passes hop to the paginator's own index
 *   dispatcher; this session adds no extra dispatcher hop, so the CALLER's coroutine context (main)
 *   is where onSnapshot/onReveal run.
 * @param worker retained for API stability / future off-main scheduling of the completion loop; the
 *   measure passes already run on the paginator's index dispatcher, so callbacks fire on the caller.
 * @param initialWindowPages the target page count the FIRST window seals before publishing (lower
 *   bound — see [TxtPaginator.DEFAULT_INITIAL_WINDOW_PAGES]).
 * @param extendPages the target page count each background-completion / on-demand step seals per mutex
 *   acquire (the window granularity that bounds the critical section — see
 *   [TxtPaginator.DEFAULT_EXTEND_PAGES]).
 */
class PaginationSession(
    private val paginator: TxtPaginator,
    @Suppress("unused") private val worker: CoroutineDispatcher = Dispatchers.Default,
    private val initialWindowPages: Int = TxtPaginator.DEFAULT_INITIAL_WINDOW_PAGES,
    private val extendPages: Int = TxtPaginator.DEFAULT_EXTEND_PAGES,
) {
    /** Serializes ALL slice mutation (background loop + every ensureMeasuredThrough) → single writer. */
    private val mutex = Mutex()

    /** True while [mutex] is held — a TEST probe proving no main callback runs under the lock. */
    private val lockHeld = AtomicReference(false)

    /** The latest published immutable snapshot (null before the first window / after a fresh open). */
    private val published = AtomicReference<TxtPageIndex?>(null)

    // --- mutation state — cursor/sealedStarts/docEnd touched ONLY under [mutex]; generation + token
    //     are @Volatile so supersede() (synchronous) is visible to the in-flight measuring loop. ------
    private var cursor: MeasureCursor? = null
    private var sealedStarts: MutableList<Int> = ArrayList()
    private var docEndExclusive: Int = 0
    @Volatile private var generation: Long = 0
    @Volatile private var activeToken: PaginationToken? = null
    private var revealFired: Boolean = false

    /** The latest published immutable sealed snapshot (or null before the first window). */
    fun snapshot(): TxtPageIndex? = published.get()

    /** TEST-only: is the mutation lock currently held? Proves callbacks fire lock-RELEASED. */
    fun isMutationLockHeldForTest(): Boolean = lockHeld.get()

    /**
     * Start a fresh doc-start-forward pass; publish the first sealed window; run the background
     * completion loop (measuring ONE window per mutex acquire) to the full index. Supersedes any prior
     * generation. [onSnapshot] is invoked on the CALLER's coroutine (the body's LaunchedEffect scope)
     * for each republish; [onReveal] fires ONCE with [resumeAnchorOffset] when that anchor's page first
     * seals (absent when the first published snapshot already contains it — anchor == 0 / near start).
     * Neither callback ever runs under the mutation lock or on the worker dispatcher.
     */
    suspend fun openFromStart(
        document: TxtDocument,
        style: TextStyle,
        contentBox: PageContentBox,
        measurer: LineMeasurer,
        isMarkdown: Boolean,
        resumeAnchorOffset: Int,
        onSnapshot: (TxtPageIndex) -> Unit,
        onReveal: (revealOffset: Int) -> Unit,
    ) {
        val callerContext = currentCoroutineContext()
        // Supersede any prior generation, then seed a fresh cursor. Clearing `published` here means a
        // reused session's reveal-gate + snapshot() never leak the prior generation.
        val myGeneration: Long
        mutex.withLock {
            lockHeld.set(true)
            try {
                activeToken?.cancel()
                myGeneration = ++generation
                val token = PaginationToken()
                activeToken = token
                cursor = paginator.freshCursor(document, style, contentBox, measurer, isMarkdown)
                sealedStarts = ArrayList()
                docEndExclusive = document.text.length
                revealFired = false
                published.set(null)   // a fresh open has no prior snapshot for this generation
            } finally {
                lockHeld.set(false)
            }
        }

        // Drive the incremental completion — ONE bounded window per acquire; publish + callbacks after
        // the lock releases, on the caller's context, guarded by a fresh generation re-check.
        driveToCompletion(
            firstWindow = initialWindowPages, myGeneration = myGeneration,
            resumeAnchorOffset = resumeAnchorOffset, callerContext = callerContext,
            onSnapshot = onSnapshot, onReveal = onReveal,
        )
    }

    /**
     * Extend the sealed frontier to cover [sourceOffset] (measure forward if it is beyond the current
     * frontier), COALESCED with the background loop under the SAME mutex, ONE WINDOW per acquire (never
     * a single unbounded through-offset run — so a deep jump never monopolizes the single writer), and
     * return the snapshot in which `pageContaining(offset)` is exact. If the offset is already sealed
     * (or the pass is complete), no additional measuring happens. Interleaves at window boundaries.
     */
    suspend fun ensureMeasuredThrough(sourceOffset: Int): TxtPageIndex {
        val target = sourceOffset.coerceAtLeast(0)
        while (true) {
            // ONE bounded window's worth of measuring under the mutex; publish AFTER the lock releases.
            val step = mutex.withLock {
                lockHeld.set(true)
                try {
                    val c = cursor ?: return@withLock ExtendStep(published.get(), publish = false, gen = generation, done = true)
                    if (c.isComplete || isOffsetSealed(c, target)) {
                        return@withLock ExtendStep(buildSnapshot(c), publish = false, gen = generation, done = true)
                    }
                    val token = activeToken ?: return@withLock ExtendStep(buildSnapshot(c), publish = false, gen = generation, done = true)
                    val myGeneration = generation
                    // Bounded step: seal AT MOST one extend-window forward (or until the target is
                    // covered / doc end). measurePages stops at the window boundary — never full book.
                    val localStarts = ArrayList<Int>()
                    val advanced = paginator.measurePages(c, extendPages, token) { localStarts.add(it) }
                    // Commit the newly-sealed starts + advanced cursor ATOMICALLY (a cancel would have
                    // thrown out of measurePages before this line, so the list never runs ahead of the
                    // cursor). Only when still the newest generation.
                    if (myGeneration != generation) {
                        return@withLock ExtendStep(published.get(), publish = false, gen = myGeneration, done = true)
                    }
                    sealedStarts.addAll(localStarts)
                    cursor = advanced
                    val covered = advanced.isComplete || isOffsetSealed(advanced, target)
                    ExtendStep(buildSnapshot(advanced), publish = true, gen = myGeneration, done = covered)
                } finally {
                    lockHeld.set(false)
                }
            }
            // Publish AFTER releasing the lock, re-checking the generation IMMEDIATELY before the store
            // so a supersede/reflow in the gap drops it.
            if (step.publish && step.snapshot != null && step.gen == generation) published.set(step.snapshot)
            if (step.done) return step.snapshot ?: published.get() ?: buildEmptySnapshot()
        }
    }

    /** One [ensureMeasuredThrough] window step: the snapshot, whether to publish, its generation, done. */
    private data class ExtendStep(val snapshot: TxtPageIndex?, val publish: Boolean, val gen: Long, val done: Boolean)

    /**
     * Supersede: cancel the active generation's token AND bump the generation so no stale pass (the
     * in-flight background loop or a mid-flight extend) publishes. Used on reflow (before a fresh
     * [openFromStart]) and on dispose. Synchronous — the loop re-reads the @Volatile generation/token
     * (visible immediately) before every measure step and every publish.
     */
    fun supersede() {
        activeToken?.cancel()
        activeToken = null
        generation++
    }

    // --- the coalesced background completion loop ----------------------------------------------

    /**
     * Drive the pass to completion one bounded window per mutex acquire, publishing (lock-released, on
     * [callerContext]) after each seal, until complete OR this generation is superseded. The first step
     * uses [firstWindow] pages; subsequent steps use [extendPages]. onReveal fires once when the anchor
     * page first seals.
     */
    private suspend fun driveToCompletion(
        firstWindow: Int,
        myGeneration: Long,
        resumeAnchorOffset: Int,
        callerContext: CoroutineContext,
        onSnapshot: (TxtPageIndex) -> Unit,
        onReveal: (revealOffset: Int) -> Unit,
    ) {
        var windowPages = firstWindow
        while (true) {
            val step = mutex.withLock {
                lockHeld.set(true)
                try {
                    if (myGeneration != generation) return@withLock null   // superseded → stop
                    val c = cursor ?: return@withLock null
                    val token = activeToken ?: return@withLock null
                    if (c.isComplete) return@withLock StepResult(buildSnapshot(c), complete = true, revealNow = false)
                    val localStarts = ArrayList<Int>()
                    val advanced = try {
                        paginator.measurePages(c, windowPages, token) { localStarts.add(it) }
                    } catch (e: CancellationException) {
                        // Our own supersession cancelled the token → drop out of the loop; a genuine
                        // parent-scope cancel is rethrown (structured concurrency honored). No partial
                        // commit — localStarts is discarded, sealedStarts/cursor stay consistent.
                        if (token.isCancelled || myGeneration != generation) return@withLock null
                        throw e
                    }
                    // Commit the newly-sealed starts + advanced cursor ATOMICALLY, only when still newest.
                    if (myGeneration != generation) return@withLock null
                    sealedStarts.addAll(localStarts)
                    cursor = advanced
                    val revealNow = !revealFired &&
                        resumeAnchorOffset > 0 &&
                        isOffsetSealed(advanced, resumeAnchorOffset) &&
                        // NOT the first published snapshot of THIS generation: if the very first window
                        // already covers the anchor, the body has it — no deep-resume auto-scroll.
                        published.get() != null
                    if (revealNow) revealFired = true
                    StepResult(buildSnapshot(advanced), complete = advanced.isComplete, revealNow = revealNow)
                } finally {
                    lockHeld.set(false)
                }
            } ?: break

            // Publish + callbacks — LOCK RELEASED, on the caller's context, generation re-checked
            // IMMEDIATELY before the publish so a supersede/reflow in the gap drops it.
            if (myGeneration != generation) break
            published.set(step.snapshot)
            onSnapshot(step.snapshot)
            if (step.revealNow) onReveal(resumeAnchorOffset)

            if (step.complete) break
            windowPages = extendPages
        }
    }

    // --- helpers -------------------------------------------------------------------------------

    /** One background/on-demand step's result: the snapshot to publish + terminal + reveal flags. */
    private data class StepResult(val snapshot: TxtPageIndex, val complete: Boolean, val revealNow: Boolean)

    /** Build the immutable sealed-partial [TxtPageIndex] from the current sealed starts + cursor. */
    private fun buildSnapshot(c: MeasureCursor): TxtPageIndex {
        // A degenerate box yields a completed cursor with zero sealed pages AND a degenerate content
        // box — surface the degrade signal so the host degrades to scroll (invariant 6).
        if (c.run.contentBox.isDegenerate) return TxtPageIndex.degenerate()
        return TxtPageIndex(
            sealedStarts.toIntArray(),
            docEndExclusive = docEndExclusive,
            isComplete = c.isComplete,
            frontierSourceOffset = c.frontierSourceOffset,
        )
    }

    private fun buildEmptySnapshot(): TxtPageIndex =
        TxtPageIndex(IntArray(0), docEndExclusive = docEndExclusive, isComplete = true)

    /**
     * True when [offset] is within a SEALED page's `[start, end)` in [c] — i.e. a sealed page start
     * `<= offset` exists AND the frontier (== the next pending page's start, or doc end when complete)
     * is `> offset`. A beyond-frontier offset is NOT sealed and needs a measure step. An offset AT/past
     * doc end on a COMPLETE cursor counts as sealed (it clamps to the last page).
     */
    private fun isOffsetSealed(c: MeasureCursor, offset: Int): Boolean {
        if (sealedStarts.isEmpty()) return false
        val clamped = offset.coerceAtLeast(0)
        val frontier = c.frontierSourceOffset
        if (c.isComplete) return sealedStarts.first() <= clamped   // complete → the whole doc is sealed
        return sealedStarts.first() <= clamped && clamped < frontier
    }
}
