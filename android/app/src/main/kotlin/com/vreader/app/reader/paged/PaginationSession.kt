// Purpose: feature #138 WI-4 (#110 Phase 3, box E follow-up) — the SINGLE Mutex/worker OWNER of the
// windowed pagination lifecycle. It supersedes the split ownership the navigator + body previously
// had over the pagination token + Compose index state: the cursor, the sealed page-start list, the
// ONE LineMeasurer instance, and the PaginationToken/generation all live HERE, private, guarded by ONE
// Mutex; publication is on the caller's (main) coroutine as IMMUTABLE TxtPageIndex snapshots.
//
// Commands:
//   • openFromStart(...): start a fresh doc-start-forward pass, publish the first sealed window, then
//     launch a coalesced BACKGROUND completion loop that measures ONE window per mutex acquire and
//     republishes as the sealed frontier advances. Supersedes any prior generation (reflow reuses it).
//   • ensureMeasuredThrough(sourceOffset): extend the sealed frontier past a beyond-frontier offset,
//     COALESCED with the background loop under the SAME mutex; returns the snapshot in which
//     pageContaining(offset) is exact.
//   • snapshot(): the latest published immutable snapshot (null before the first window).
//   • supersede(): bump the generation + cancel the active token so a stale pass never publishes
//     (reflow / dispose).
//
// The Mutex + worker supersede/publish contract (Gate-2 R2 Medium 2 — made precise):
//   • PAGE/WINDOW-sized critical sections — the mutex is NEVER held for an unbounded full-book run.
//     The background loop measures ONE window per acquire, then releases and re-acquires; an on-demand
//     ensureMeasuredThrough interleaves at the next window boundary (coalesced, still single-writer).
//   • Generation check IMMEDIATELY before EVERY publish — a superseded/reflowed generation drops the
//     publish and exits the loop.
//   • Snapshot via AtomicReference, published AFTER releasing the mutation lock; NO main-thread
//     callback (onSnapshot/onReveal) runs under the lock (no lock-order inversion).
//   • ONE writer — the background loop + every ensureMeasuredThrough share the same Mutex; the ONE
//     LineMeasurer (inside the cursor's MeasureRun) is used only under the mutex, never concurrently.
//   • onReveal fires ONCE when the resume anchor's page is first sealed, carrying the resume SOURCE
//     OFFSET. Absent (anchor == 0 / near start) — the first snapshot already contains it.
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
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.util.concurrent.atomic.AtomicReference

/**
 * The single owner of the incremental windowed-pagination lifecycle over a [TxtPaginator].
 *
 * @param paginator the resumable-core paginator whose freshCursor/measurePages/measureThroughOffset
 *   entry points this session drives (WI-1/2/3).
 * @param worker the dispatcher the BACKGROUND completion loop runs on (default [Dispatchers.Default]).
 *   The measure passes themselves also hop to the paginator's own index dispatcher; in tests both are
 *   the same test dispatcher so timing is deterministic.
 * @param initialWindowPages the target page count the FIRST window seals before publishing (lower
 *   bound — see [TxtPaginator.DEFAULT_INITIAL_WINDOW_PAGES]).
 * @param extendPages the target page count each background-completion / on-demand step seals per mutex
 *   acquire (the window granularity that bounds the critical section — see
 *   [TxtPaginator.DEFAULT_EXTEND_PAGES]).
 */
class PaginationSession(
    private val paginator: TxtPaginator,
    private val worker: CoroutineDispatcher = Dispatchers.Default,
    private val initialWindowPages: Int = TxtPaginator.DEFAULT_INITIAL_WINDOW_PAGES,
    private val extendPages: Int = TxtPaginator.DEFAULT_EXTEND_PAGES,
) {
    /** Serializes ALL slice mutation (background loop + every ensureMeasuredThrough) → single writer. */
    private val mutex = Mutex()

    /** True while [mutex] is held — a TEST probe proving no main callback runs under the lock. */
    private val lockHeld = AtomicReference(false)

    /** The latest published immutable snapshot (null before the first window). */
    private val published = AtomicReference<TxtPageIndex?>(null)

    // --- mutation state — ONLY ever touched under [mutex] ---------------------------------------
    private var cursor: MeasureCursor? = null
    private var sealedStarts: MutableList<Int> = ArrayList()
    private var docEndExclusive: Int = 0
    private var generation: Long = 0
    private var activeToken: PaginationToken? = null
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
     * seals (absent when the first snapshot already contains it — anchor == 0 / near start). Neither
     * callback ever runs under the mutation lock.
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
        // Supersede any prior generation, then seed a fresh cursor. All state setup is under the mutex.
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
            } finally {
                lockHeld.set(false)
            }
        }

        // Drive the incremental completion. Each iteration is ONE bounded window under the mutex; the
        // publish (and its callbacks) happen AFTER the lock releases. A generation change (supersede /
        // a newer openFromStart) drops the publish and exits.
        driveToCompletion(
            firstWindow = initialWindowPages, myGeneration = myGeneration,
            resumeAnchorOffset = resumeAnchorOffset, onSnapshot = onSnapshot, onReveal = onReveal,
        )
    }

    /**
     * Extend the sealed frontier to cover [sourceOffset] (measure forward if it is beyond the current
     * frontier), COALESCED with the background loop under the SAME mutex, and return the snapshot in
     * which `pageContaining(offset)` is exact. If the offset is already sealed (or the pass is complete),
     * no additional measuring happens — the current snapshot is returned. Interleaves at a window
     * boundary; never blocks for a full-book run.
     */
    suspend fun ensureMeasuredThrough(sourceOffset: Int): TxtPageIndex {
        // ONE bounded critical section: measure forward through the target (or no-op if already sealed).
        val (snap, published) = mutex.withLock {
            lockHeld.set(true)
            try {
                val c = cursor ?: return@withLock (this.published.get() to false)
                val myGeneration = generation
                val token = activeToken
                if (c.isComplete || isOffsetSealed(c, sourceOffset)) {
                    // Already covered — return the current published snapshot without re-measuring.
                    return@withLock (buildSnapshot(c) to false)
                }
                if (token == null) return@withLock (buildSnapshot(c) to false)
                val advanced = paginator.measureThroughOffset(c, sourceOffset, token) { sealedStarts.add(it) }
                cursor = advanced
                // Only build/publish if this pass is still the newest generation (generation check
                // immediately before publishing — a supersede that raced in drops it).
                if (myGeneration != generation) return@withLock (this.published.get() to false)
                val snapshot = buildSnapshot(advanced)
                Pair(snapshot, true)
            } finally {
                lockHeld.set(false)
            }
        }
        // Publish the snapshot AFTER releasing the lock (no callback under the lock).
        if (published && snap != null) this.published.set(snap)
        return snap ?: this.published.get() ?: buildEmptySnapshot()
    }

    /**
     * Supersede: cancel the active generation's token AND bump the generation so no stale pass (the
     * in-flight background loop or a mid-flight extend) publishes. Used on reflow (before a fresh
     * [openFromStart]) and on dispose.
     */
    fun supersede() {
        // No coroutine — a plain synchronous bump. The background loop re-reads `generation` before
        // every publish and its token before every measure step, so both observe the supersession.
        activeToken?.cancel()
        activeToken = null
        generation++
    }

    // --- the coalesced background completion loop ----------------------------------------------

    /**
     * Drive the pass to completion one bounded window per mutex acquire, publishing (lock-released)
     * after each seal, until complete OR this generation is superseded. The first step uses
     * [firstWindow] pages; subsequent steps use [extendPages]. onReveal fires once when the anchor page
     * first seals.
     */
    private suspend fun driveToCompletion(
        firstWindow: Int,
        myGeneration: Long,
        resumeAnchorOffset: Int,
        onSnapshot: (TxtPageIndex) -> Unit,
        onReveal: (revealOffset: Int) -> Unit,
    ) = withContext(worker) {
        var windowPages = firstWindow
        while (true) {
            // ONE bounded window under the mutex; publish AFTER the lock releases.
            val step = mutex.withLock {
                lockHeld.set(true)
                try {
                    // A newer generation (supersede / a fresh openFromStart) took over → stop.
                    if (myGeneration != generation) return@withLock null
                    val c = cursor ?: return@withLock null
                    val token = activeToken ?: return@withLock null
                    if (c.isComplete) {
                        // Already complete (e.g. empty/one-page doc, or a prior step finished it) —
                        // publish the terminal snapshot ONCE more so callers observe completion.
                        return@withLock StepResult(buildSnapshot(c), complete = true, revealNow = false)
                    }
                    val advanced = try {
                        paginator.measurePages(c, windowPages, token) { sealedStarts.add(it) }
                    } catch (e: CancellationException) {
                        // Our own supersession cancelled the token — drop out of the loop; a genuine
                        // parent-scope cancel is rethrown (structured concurrency honored).
                        if (token.isCancelled || myGeneration != generation) return@withLock null
                        throw e
                    }
                    cursor = advanced
                    // Generation check IMMEDIATELY before building/publishing — a supersede that raced
                    // in during the measure step drops this publish.
                    if (myGeneration != generation) return@withLock null
                    val snapshot = buildSnapshot(advanced)
                    // Reveal fires once, when the anchor's page is first sealed (and it wasn't already
                    // in the FIRST snapshot — that near-start case never fires; the body has it already).
                    val revealNow = !revealFired &&
                        resumeAnchorOffset > 0 &&
                        isOffsetSealed(advanced, resumeAnchorOffset) &&
                        // NOT the first published snapshot: if the very first window already covers the
                        // anchor, the body has it — no deep-resume auto-scroll needed.
                        published.get() != null
                    if (revealNow) revealFired = true
                    StepResult(snapshot, complete = advanced.isComplete, revealNow = revealNow)
                } finally {
                    lockHeld.set(false)
                }
            } ?: break   // null step = superseded / no cursor → stop the loop.

            // Publish + callbacks — LOCK RELEASED. Publish before invoking onSnapshot so a callback that
            // reads snapshot() sees the just-published value.
            published.set(step.snapshot)
            onSnapshot(step.snapshot)
            if (step.revealNow) onReveal(resumeAnchorOffset)

            if (step.complete) break
            windowPages = extendPages
        }
    }

    // --- helpers (all called under [mutex]) ----------------------------------------------------

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
     * is `> offset`. A beyond-frontier offset is NOT sealed and needs a measure step.
     */
    private fun isOffsetSealed(c: MeasureCursor, offset: Int): Boolean {
        if (sealedStarts.isEmpty()) return false
        val clamped = offset.coerceAtLeast(0)
        // The last sealed page's exclusive end is the frontier; a complete cursor's frontier is doc end.
        val frontier = c.frontierSourceOffset
        return sealedStarts.first() <= clamped && clamped < frontier
    }
}
