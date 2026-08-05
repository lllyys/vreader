// Purpose: feature #165 WI-4b — the CLEANUP half of the bounded SAF boundary: releasing a
// descriptor that an attacker-controlled provider may still be sitting inside. Split out of
// `AnnotationsIoController` so the boundary's five ordered steps stay readable in one pass and so
// the ownership rules below are reviewed on their own terms.
//
// Key decisions:
//  - THERE ARE TWO CLEANUP CHANNELS AND THEY ARE NOT INTERCHANGEABLE. `BoundedCallGate` runs
//    `dispose` on the ABANDONED JOB's own thread (when the parked call finally returns) and
//    `onExpiry` SYNCHRONOUSLY on the CALLER's coroutine (immediately before it returns `TimedOut`).
//    So a close belongs on the job's thread — blocking there delays nobody, and the ledger's charge
//    correctly persists while the fd is genuinely still held — while a close reached from `onExpiry`
//    MUST be dispatched, or it re-opens the very wedge the boundary exists to close (Gate-4 round 1,
//    Critical: the caller would sit in cleanup for a provider it had already given up on).
//  - THE DISPATCHED CHANNEL IS BOUNDED AND DISCARDS UNDER PRESSURE. A rescue close that parks holds
//    a thread that no ledger charges, so an unbounded pool accumulates them (Gate-4 round 2, High).
//    Past [SafCleanup.MAX_EXPIRY_CLOSES] the submission is dropped — legal precisely because this
//    channel is BEST-EFFORT and nothing may depend on it.
//  - WHICH MAKES `dispose` THE ONLY GUARANTEE. Because a dispatched rescue can be discarded, every
//    bounded call that can leave a descriptor behind carries a `dispose` that closes it directly
//    (Gate-4 round 3, High). `onExpiry` only makes the release happen SOONER.
//  - CLOSE-ONCE ACROSS ALL THREE PATHS. An attacker-supplied stream need not tolerate a second
//    `close()`; [CloseOnce] is what lets `onExpiry`, `dispose` and the ordinary close all aim at the
//    same descriptor safely. (`CountingGuardStream` already provides this on the import side.)
//
// @coordinates-with AnnotationsIoController (the only caller), BoundedCallGate + CountingGuardStream
//   (the shipped primitives whose hook semantics these rules are derived from).
package com.vreader.app.annotations

import com.vreader.app.imports.IncomingImportCoordinator
import com.vreader.app.imports.isFatal
import java.io.Closeable
import java.util.concurrent.SynchronousQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Close-once ownership for a descriptor three different paths may try to release: the best-effort
 * `onExpiry`, the guaranteed `dispose`, and the ordinary close.
 */
internal class CloseOnce(private val target: Closeable) : Closeable {
    private val closed = AtomicBoolean(false)

    override fun close() {
        if (closed.compareAndSet(false, true)) target.close()
    }
}

/**
 * Releasing descriptors held by calls the app has walked away from.
 *
 * An INSTANCE, not an object, because it owns a thread pool: production shares one
 * ([SafCleanup.SHARED], the analogue of the one app-wide gate), while a test gives its controller
 * its own so a suite that deliberately saturates the lane cannot silently starve the next test's.
 * That coupling is not hypothetical — it turned one wrong expectation into eight order-dependent
 * failures before the lane became injectable.
 */
internal class SafCleanup(val maxExpiryCloses: Int = DEFAULT_MAX_EXPIRY_CLOSES) {

    /**
     * Where a dispatched best-effort close runs: it can never delay a caller, and it is BOUNDED so
     * it cannot become its own exhaustion surface. Zero core threads over a `SynchronousQueue`
     * hands work to an idle thread or a new one up to [maxExpiryCloses]; past that the submission
     * is rejected and discarded without blocking or throwing at the submitter. DAEMON, so a parked
     * rescue can never hold the process open.
     */
    private val pool = ThreadPoolExecutor(
        0,
        maxExpiryCloses,
        KEEPALIVE_SECONDS,
        TimeUnit.SECONDS,
        SynchronousQueue(),
        { runnable -> Thread(runnable, EXPIRY_THREAD_NAME).apply { isDaemon = true } },
        ThreadPoolExecutor.DiscardPolicy(),
    )

    /** Threads this lane has alive — the bound, made observable so a test can hold it honest. */
    val laneThreadCount: Int get() = pool.poolSize

    /**
     * BEST-EFFORT, dispatched, never awaited — the only form legal from `onExpiry`, which runs on
     * the caller's coroutine. May be dropped when the lane is saturated; the `dispose` hook is what
     * guarantees the descriptor is eventually released.
     */
    fun releaseAfterExpiry(closeable: Closeable?) {
        if (closeable == null) return
        pool.execute { swallowingClose(closeable) }
    }

    companion object {
        /**
         * How many best-effort closes may be parked at once. One per abandonable call, so the
         * rescue path can never cost more threads than the ledger it serves.
         */
        val DEFAULT_MAX_EXPIRY_CLOSES = IncomingImportCoordinator.MAX_ABANDONED_CALLS

        /** The one production lane, beside the one production gate. */
        val SHARED = SafCleanup()

        const val EXPIRY_THREAD_NAME = "vreader-annot-expiry"

        private const val KEEPALIVE_SECONDS = 30L

        /**
         * Failure-tolerant close for a stream that need not close cleanly. A process-fatal error is
         * RETHROWN — swallowing it would hide real VM corruption behind "the import failed".
         */
        fun swallowingClose(closeable: Closeable) {
            try {
                closeable.close()
            } catch (t: Throwable) {
                if (t.isFatal()) throw t
            }
        }

        /**
         * `BoundedCallGate` wraps every `Throwable` — including the process-fatal ones — into
         * `BoundedCall.Failed`, so a caller that maps `Failed` to a file-level failure would
         * quietly relabel a broken VM as a bad file. Every `Failed` arm calls this first.
         */
        fun rethrowIfFatal(error: Throwable) {
            if (error.isFatal()) throw error
        }
    }
}
