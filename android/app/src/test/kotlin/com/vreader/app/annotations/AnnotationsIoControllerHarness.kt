package com.vreader.app.annotations

import android.net.Uri
import com.vreader.app.imports.BoundedCallGate
import com.vreader.app.imports.inboundBlockingLane
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicInteger

/**
 * Feature #165 WI-4b — the hostile-provider rig for [AnnotationsIoController] (A-12).
 *
 * The whole suite rests on ONE property of these fakes: a parked call blocks **forever**. A fake
 * that eventually returns proves nothing at all — the controller would look correct even if it
 * simply waited for the provider, which is the defect this boundary exists to prevent. So every
 * park here is a [ParkLatch] the TEST releases explicitly, never a sleep and never a timeout.
 *
 * For the same reason [ParkingInputStream.close] / [ParkingOutputStream.close] deliberately do NOT
 * unpark the latch. Closing the fd is the gate's BEST-EFFORT lever (`onExpiry`); a test that let it
 * unpark would be asserting the best-effort behaviour while claiming to assert the guarantee, and
 * would stay green if the guarantee were removed.
 */
internal class ParkLatch {
    private val latch = CountDownLatch(1)
    private val entered = AtomicInteger(0)
    private val left = AtomicInteger(0)

    init {
        live.add(this)
    }

    /** True while at least one thread is still inside [park] — i.e. the provider has NOT returned. */
    val isParked: Boolean get() = entered.get() > left.get()

    val enteredCount: Int get() = entered.get()

    /** Blocks the calling thread until [release]. Uninterruptible by coroutine cancellation, which
     *  is exactly the real `ContentResolver` shape this stands in for. */
    fun park() {
        entered.incrementAndGet()
        try {
            latch.await()
        } finally {
            left.incrementAndGet()
        }
    }

    fun release() = latch.countDown()

    companion object {
        private val live = CopyOnWriteArrayList<ParkLatch>()

        /**
         * Releases every latch ever created, from `@AfterClass`.
         *
         * Needed because a `@Test(timeout = …)` that fires ABANDONS its thread: JUnit reports the
         * failure and moves on, but `@After` never runs, so the latch that thread is parked on is
         * never released and a non-daemon test thread keeps the JVM alive forever. Measured while
         * mutation-testing the unbounded-`query` variant: the suite reported its failures and then
         * hung until the 1200s watchdog killed it, leaving stale result XML. A removed bound must
         * read as a fast RED, not as an unexplained CI timeout.
         */
        fun releaseAll() = live.forEach { it.release() }
    }
}

/** An input stream that records its closes — the fd-leak probe. */
internal class TrackingInputStream(
    body: ByteArray = ByteArray(0),
    private val closeLatch: ParkLatch? = null,
) : InputStream() {
    private val delegate = ByteArrayInputStream(body)
    private val closes = AtomicInteger(0)

    val closeCount: Int get() = closes.get()

    override fun read(): Int = delegate.read()

    override fun read(b: ByteArray, off: Int, len: Int): Int = delegate.read(b, off, len)

    /** [closeLatch] models a provider that serves every byte and then parks on `close()`. */
    override fun close() {
        closes.incrementAndGet()
        closeLatch?.park()
    }
}

/** An input stream whose `read` never returns — and, optionally, whose `close` does not either. */
internal class ParkingInputStream(
    private val latch: ParkLatch,
    private val closeLatch: ParkLatch? = null,
) : InputStream() {
    private val closes = AtomicInteger(0)

    val closeCount: Int get() = closes.get()

    override fun read(): Int {
        latch.park()
        return -1
    }

    override fun read(b: ByteArray, off: Int, len: Int): Int {
        latch.park()
        return -1
    }

    /**
     * [closeLatch] is the case the Gate-4 audit surfaced: the gate runs `onExpiry` on the CALLER's
     * coroutine, so a best-effort close that itself parks would wedge the caller it was meant to
     * rescue.
     */
    override fun close() {
        closes.incrementAndGet()
        closeLatch?.park()
    }
}

/** An output stream that records what it received and how often it was closed. */
internal class TrackingOutputStream(
    private val closeLatch: ParkLatch? = null,
    private val throwOnClose: Boolean = false,
) : OutputStream() {
    private val sink = ByteArrayOutputStream()
    private val closes = AtomicInteger(0)

    val closeCount: Int get() = closes.get()

    fun text(): String = synchronized(sink) { sink.toString(Charsets.UTF_8.name()) }

    override fun write(b: Int) = synchronized(sink) { sink.write(b) }

    override fun write(b: ByteArray, off: Int, len: Int) = synchronized(sink) { sink.write(b, off, len) }

    /**
     * [closeLatch] models a destination that accepts every byte and then parks on `close()`;
     * [throwOnClose] models one that fails while committing them — for a SAF descriptor, `close()`
     * is where the write is finalized, so a throw there means the file was NOT saved.
     */
    override fun close() {
        closes.incrementAndGet()
        closeLatch?.park()
        if (throwOnClose) throw IOException("destination refused the commit")
    }
}

/** An output stream that accepts the open promptly and then never returns from `write`. */
internal class ParkingOutputStream(
    private val latch: ParkLatch,
    private val closeLatch: ParkLatch? = null,
) : OutputStream() {
    private val closes = AtomicInteger(0)

    val closeCount: Int get() = closes.get()

    override fun write(b: Int) = latch.park()

    override fun write(b: ByteArray, off: Int, len: Int) = latch.park()

    /** [closeLatch]: the best-effort rescue close parks too. See [ParkingInputStream.close]. */
    override fun close() {
        closes.incrementAndGet()
        closeLatch?.park()
    }
}

/**
 * A [SafDocumentPort] that can park in any one of its three entry points, and can hand back a
 * stream AFTER the caller's deadline has already passed — the late-result shape whose only owner
 * is the gate's `dispose` hook.
 */
internal class FakeSafPort : SafDocumentPort {

    enum class Site { NONE, METADATA, OPEN_INPUT, OPEN_OUTPUT }

    val latch = ParkLatch()

    var parkAt: Site = Site.NONE
    var meta: SafMetadata = SafMetadata(displayName = "notes.json", declaredSize = null)
    var failWith: Throwable? = null

    /** Produces the stream `openInput` hands back; return null to model a provider refusal. */
    var inputFactory: () -> InputStream? = { TrackingInputStream() }

    /** Produces the stream `openOutput` hands back; return null to model a provider refusal. */
    var outputFactory: () -> OutputStream? = { TrackingOutputStream() }

    private val metadataCalls = AtomicInteger(0)
    private val openInputCalls = AtomicInteger(0)
    private val openOutputCalls = AtomicInteger(0)

    val metadataCallCount: Int get() = metadataCalls.get()
    val openInputCallCount: Int get() = openInputCalls.get()
    val openOutputCallCount: Int get() = openOutputCalls.get()

    /** Every stream this port actually produced, in order — including one produced off-deadline. */
    val produced = CopyOnWriteArrayList<Any>()

    /**
     * Runs just before a call returns. The lever for the mid-flight cases: a provider can change
     * the world (exhaust the shared ledger, say) between two of the controller's steps, which is
     * the only way to reach the re-checks that sit BETWEEN provider calls.
     */
    var onCall: (Site) -> Unit = {}

    override fun queryMetadata(uri: Uri): SafMetadata {
        metadataCalls.incrementAndGet()
        if (parkAt == Site.METADATA) latch.park()
        failWith?.let { throw it }
        onCall(Site.METADATA)
        return meta
    }

    override fun openInput(uri: Uri): InputStream? {
        openInputCalls.incrementAndGet()
        if (parkAt == Site.OPEN_INPUT) latch.park()
        failWith?.let { throw it }
        onCall(Site.OPEN_INPUT)
        return inputFactory()?.also { produced.add(it) }
    }

    override fun openOutput(uri: Uri): OutputStream? {
        openOutputCalls.incrementAndGet()
        if (parkAt == Site.OPEN_OUTPUT) latch.park()
        failWith?.let { throw it }
        onCall(Site.OPEN_OUTPUT)
        return outputFactory()?.also { produced.add(it) }
    }
}

/**
 * One controller wired the way production wires it, except for the provider seam.
 *
 * [gate] is created ONCE here and handed to the controller — the app-wide ledger, injected. Several
 * assertions read THIS instance's `abandonedCalls`, so a controller that constructed its own gate
 * would leave it at zero and redden them.
 */
internal class ControllerRig(timeoutMillis: Long = TIMEOUT_MILLIS) {

    private val lane = inboundBlockingLane()
    private val scope = CoroutineScope(SupervisorJob() + lane)

    val gate = BoundedCallGate(scope, lane)
    val port = FakeSafPort()
    val store = ApplierHarness()
    val writer = AnnotationsExportWriter(store.repo)

    /**
     * The real reader by default. Swap it to observe what the boundary HANDS the reader — the
     * controller reads this property at call time, so a swap after construction still applies.
     */
    var parser: AnnotationsParser = AnnotationsParser(AnnotationsImportReader::parse)

    /**
     * THIS rig's own rescue lane, never the production singleton: a test that deliberately
     * saturates the lane must not starve the next test's rescue closes. Sharing it once turned a
     * single wrong expectation into eight order-dependent failures.
     */
    val cleanup = SafCleanup()

    val controller = AnnotationsIoController(
        saf = port,
        writer = writer,
        applier = store.applier,
        gate = gate,
        timeoutMillis = timeoutMillis,
        parser = { input, fileName, bookKey, bookTitle, existing ->
            parser.parse(input, fileName, bookKey, bookTitle, existing)
        },
        cleanup = cleanup,
    )

    val uri: Uri = Uri.parse("content://com.example.hostile/document/1")

    /** Blocks up to [millis] for [condition]; returns whether it became true. */
    fun awaitUntil(millis: Long = 5_000L, condition: () -> Boolean): Boolean {
        val deadline = System.nanoTime() + millis * 1_000_000L
        while (System.nanoTime() < deadline) {
            if (condition()) return true
            Thread.sleep(5L)
        }
        return condition()
    }

    fun close() {
        port.latch.release()
        store.close()
        scope.cancel()
    }

    companion object {
        /** Short on purpose: every park test waits this out for real, on a real dispatcher. */
        const val TIMEOUT_MILLIS = 150L
    }
}
