// Purpose: feature #155 WI-4 (plan D6/D8/D9) — the ONE process-wide inbound-import queue,
// plus [BoundedCallGate], the bounded-execution primitive that closes D8's OPEN GAP.
//
// Pipeline: ImportActivity resolves + opens each URI while its read grant is alive and
// hands over an [IncomingItem] per URI -> this coordinator's single queue -> ONE long-lived
// worker -> BookImporter -> exactly one [IncomingImportOutcome] per input item.
//
// Key decisions:
//   * ONE QUEUE, ONE WORKER. Sequencing and the in-flight cap must hold ACROSS concurrent
//     ImportActivity instances (two files shared back to back, split screen). A per-call
//     loop would bound one caller and nothing else.
//   * THE ENVELOPE EXISTS SO FAILURES HAVE A ROUTE. Resolution and opening fail inside
//     ImportActivity (it owns the grant); if this queue accepted only successes,
//     Unsupported/Unreadable/TooLarge could never reach [outcomes]. PreResolved items are
//     relayed in order, so every input URI yields exactly one outcome wherever it failed.
//   * THE COORDINATOR OWNS EVERY STREAM and closes it on EVERY path — success, unsupported,
//     too large, timeout, exception, and items refused by the in-flight cap.
//   * TWO TIMEOUT TIERS, NEVER CONFLATED (D8). GUARANTEED: each copy runs as an independent
//     job awaited under a hard bound, so the worker advances and returns the item's permit
//     unconditionally on expiry — a pathological provider costs at most one leaked thread,
//     never a stalled queue. BEST-EFFORT: a progress watchdog closes the fd, which usually
//     releases a provider-backed pipe and is guaranteed for nothing.
//   * OUTCOMES GO THROUGH A BUFFERED CHANNEL, not a non-replaying SharedFlow, so an outcome
//     raised before MainActivity collects (cold start / rotation) is still delivered (D9).
//
// Known limitation: `wasAlreadyPresent` is derived from the artifact directory rather than
// `repository.findBook(key)`. The canonical key only exists AFTER BookImporter has hashed
// the bytes, by which time its upsert has already run, so a post-hoc row lookup would
// always answer "present". The content-addressed artifact name is the one pre-import
// signal this file can read without changing BookImporter's contract.
//
// @coordinates-with: IncomingBookResolver + ImportActivity (WI-5: acquires a permit, opens
//   the stream, builds the item), BookImporter.importStream, VReaderApp.AppContainer
package com.vreader.app.imports

import com.vreader.app.data.Book
import com.vreader.app.data.BookImporter
import com.vreader.app.data.ImportException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExecutorCoroutineDispatcher
import kotlinx.coroutines.Job
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.async
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import vreader.contracts.BookFormat
import java.io.File
import java.io.FilterInputStream
import java.io.IOException
import java.io.InputStream
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference
import kotlin.coroutines.cancellation.CancellationException
import kotlin.time.Duration
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.seconds

/** What happened to ONE inbound URI. Exactly one is emitted per enqueued item. */
sealed interface IncomingImportOutcome {
    data class Imported(val key: String, val format: BookFormat, val wasAlreadyPresent: Boolean) :
        IncomingImportOutcome

    data class Unsupported(val displayName: String) : IncomingImportOutcome

    /** The provider refused to open the document at all. */
    data object Unreadable : IncomingImportOutcome

    data object TooLarge : IncomingImportOutcome

    data object Failed : IncomingImportOutcome
}

/** One inbound URI's work: either an opened document, or a failure that already happened. */
sealed interface IncomingItem {
    data class Ready(val pending: PendingImport) : IncomingItem

    /** Resolution/open already failed in ImportActivity; the coordinator just relays it. */
    data class PreResolved(val outcome: IncomingImportOutcome) : IncomingItem
}

/** The import seam, so a test can drive the coordinator without a Room database. */
fun interface ImportStreamPort {
    suspend fun importStream(
        sourceUri: String,
        displayName: String,
        input: InputStream,
        format: BookFormat,
    ): Book
}

/** The result of a [BoundedCallGate.call]. [TimedOut] means the CALLER gave up, not that the call ended. */
sealed interface BoundedCall<out T> {
    data class Completed<out T>(val value: T) : BoundedCall<T>

    data class Failed(val error: Throwable) : BoundedCall<Nothing>

    data object TimedOut : BoundedCall<Nothing>
}

/**
 * Puts a HARD upper bound on how long the CALLER waits — the only bound that holds for
 * `ContentResolver.query` / `openInputStream` / a blocking `InputStream.read`, which are
 * synchronous and uninterruptible. `withContext(Dispatchers.IO)` relocates such a block
 * without bounding it, and coroutine cancellation cannot interrupt it: the caller unwinds
 * while the thread stays parked (plan D8's OPEN GAP, verified at IncomingBookResolver.kt).
 *
 * The guarantee is about the caller: on expiry it returns [BoundedCall.TimedOut] and
 * proceeds UNCONDITIONALLY, whether or not the call ever finishes. The price is at most
 * ONE leaked thread per abandoned call — strictly better than the rejected alternative (a
 * caller-local executor + timeout), which trades a visible hang for a poisoned fixed pool:
 * once every worker is parked, imports are denied forever. Here the caller releases its own
 * admission permit when IT gives up, so leaked threads can never wedge the gate.
 *
 * A late result is DISPOSED, never leaked: [dispose] closes whatever the abandoned call
 * eventually produced. An InputStream nobody owns is an fd leak on an exported entry point.
 */
class BoundedCallGate(
    private val scope: CoroutineScope,
    private val contextFactory: (String) -> CoroutineDispatcher = ::dedicatedThreadDispatcher,
) {
    /**
     * Runs [block] as an independent job and waits at most [timeoutMillis] for it.
     *
     * [onExpiry] is the BEST-EFFORT lever (e.g. close the fd) — it may or may not release
     * the parked call, and correctness never depends on it. [dispose] releases a result
     * that arrives after the caller has already moved on.
     */
    suspend fun <T> call(
        timeoutMillis: Long,
        name: String = "bounded-call",
        dispose: (T) -> Unit = {},
        onExpiry: () -> Unit = {},
        block: suspend () -> T,
    ): BoundedCall<T> {
        val dispatcher = contextFactory(name)
        val produced = AtomicReference<T?>(null)
        val abandoned = AtomicBoolean(false)
        // A child of [scope], NOT of the awaiting coroutine: abandoning the await must not
        // cancel the job (cancelling it would not unpark a blocking read anyway), and
        // cancelling appScope must.
        val job = scope.async(dispatcher) {
            val value = block()
            produced.set(value)
            // The caller may have given up in the meantime — then this value is ours to
            // dispose. `getAndSet` makes exactly one side win the race.
            if (abandoned.get()) disposeOnce(produced, dispose)
            value
        }
        job.invokeOnCompletion { (dispatcher as? ExecutorCoroutineDispatcher)?.close() }

        var settled = false
        try {
            val result = withTimeoutOrNull(timeoutMillis) {
                // Cancellation must NOT be swallowed here: a swallowed
                // TimeoutCancellationException would make withTimeoutOrNull unreliable.
                try {
                    Result.success(job.await())
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Throwable) {
                    Result.failure(e)
                }
            }
            if (result != null) {
                settled = true
                produced.set(null)          // ownership passes to the caller
                return result.fold({ BoundedCall.Completed(it) }, { BoundedCall.Failed(it) })
            }
            settled = true
            abandoned.set(true)
            runCatching { onExpiry() }
            disposeOnce(produced, dispose)
            return BoundedCall.TimedOut
        } finally {
            // The caller itself was cancelled (appScope torn down) after `await` had
            // already produced a value — the documented "returning a closeable from a
            // cancellable wait" hole. Nothing else would ever close it.
            if (!settled) {
                abandoned.set(true)
                disposeOnce(produced, dispose)
            }
        }
    }

    private fun <T> disposeOnce(produced: AtomicReference<T?>, dispose: (T) -> Unit) {
        produced.getAndSet(null)?.let { runCatching { dispose(it) } }
    }
}

private val dedicatedThreads = AtomicLong(0)

/**
 * A private single thread per call. Daemon, so a thread parked forever in a provider read
 * never keeps the process (or a test JVM) alive, and never occupies a slot in a shared pool.
 */
internal fun dedicatedThreadDispatcher(name: String): CoroutineDispatcher =
    Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "vreader-$name-${dedicatedThreads.incrementAndGet()}").apply { isDaemon = true }
    }.asCoroutineDispatcher()

/** Thrown by [CountingGuardStream] past the byte cap; mapped to [IncomingImportOutcome.TooLarge]. */
internal class ImportSizeCapExceeded(limit: Long) : IOException("import exceeded $limit bytes")

/**
 * The POST-OPEN size backstop (D8). ImportActivity rejects a declared oversize before
 * opening; this covers the cases a cursor cannot: an absent size, a lying size, and a
 * stream that never ends. Also carries the progress counter the stall watchdog reads.
 */
internal class CountingGuardStream(source: InputStream, private val maxBytes: Long) :
    FilterInputStream(source) {

    private val counted = AtomicLong(0)

    val bytesRead: Long get() = counted.get()

    override fun read(): Int {
        val b = `in`.read()
        if (b >= 0) countOrThrow(1)
        return b
    }

    override fun read(b: ByteArray, off: Int, len: Int): Int {
        val n = `in`.read(b, off, len)
        if (n > 0) countOrThrow(n.toLong())
        return n
    }

    private fun countOrThrow(n: Long) {
        if (counted.addAndGet(n) > maxBytes) throw ImportSizeCapExceeded(maxBytes)
    }

    /** Best-effort release of a parked read: close the fd from another coroutine. */
    fun abort() {
        runCatching { `in`.close() }
    }
}

/**
 * The process-wide inbound-import queue.
 *
 * Takes ownership of every [PendingImport.stream]. `enqueue` is called from
 * ImportActivity's `lifecycleScope` but every copy runs on [appScope], so a finished
 * activity never cancels an in-flight import while a torn-down app does.
 */
class IncomingImportCoordinator internal constructor(
    private val importStream: ImportStreamPort,
    private val booksDir: File,
    private val appScope: CoroutineScope,
    private val importTimeoutMillis: Long = IMPORT_TIMEOUT.inWholeMilliseconds,
    private val stallTimeoutMillis: Long = STALL_TIMEOUT.inWholeMilliseconds,
    private val maxImportBytes: Long = MAX_IMPORT_BYTES,
    copyContextFactory: (String) -> CoroutineDispatcher = ::dedicatedThreadDispatcher,
) {
    constructor(importer: BookImporter, booksDir: File, appScope: CoroutineScope) : this(
        importStream = ImportStreamPort { sourceUri, displayName, input, format ->
            importer.importStream(
                sourceUri = sourceUri,
                displayName = displayName,
                input = input,
                format = format,
            )
        },
        booksDir = booksDir,
        appScope = appScope,
    )

    /**
     * The bounded-execution primitive WI-5 wraps `peek` / `resolveAndOpen` in, so a hostile
     * provider cannot hold an inbound permit forever (D8's OPEN GAP). Exposed here because
     * the guarantee and the permit accounting are one design, not two.
     */
    val boundedCalls: BoundedCallGate = BoundedCallGate(appScope, copyContextFactory)

    /** UNLIMITED so `enqueue` never suspends the caller; admission is bounded by permits. */
    private val queue = Channel<IncomingItem>(Channel.UNLIMITED)

    // A buffered Channel, not a non-replaying SharedFlow: an outcome raised before
    // MainActivity collects (cold start / rotation) must survive (D9, the shipped
    // LibraryEvent precedent). DROP_OLDEST + trySend because QUEUE LIVENESS OUTRANKS an
    // advisory toast: with no collector and a full buffer, `send` would suspend the ONE
    // worker and wedge every later import.
    //
    // The capacity is SPELLED OUT. `Channel(Channel.BUFFERED, DROP_OLDEST)` does NOT mean
    // "64 with drop-oldest" — with a non-SUSPEND overflow policy that factory builds a
    // ConflatedBufferedChannel of capacity ONE, which would silently reduce a whole batch
    // to its last outcome. (Caught by the ordering tests, not by review.)
    private val outcomeChannel =
        Channel<IncomingImportOutcome>(OUTCOME_BUFFER, BufferOverflow.DROP_OLDEST)

    val outcomes: Flow<IncomingImportOutcome> = outcomeChannel.receiveAsFlow()

    /** Permits (queued + running) held process-wide; acquired by WI-5 BEFORE it opens a stream. */
    private val outstanding = AtomicInteger(0)

    /** Ready items this coordinator currently owns — the queue-side view of the same cap. */
    private val owned = AtomicInteger(0)

    internal val outstandingSlots: Int get() = outstanding.get()

    init {
        appScope.launch {
            for (item in queue) process(item)
        }
    }

    /**
     * Reserves one of [MAX_IN_FLIGHT] in-flight slots. WI-5 calls this BEFORE opening a
     * stream — the cap must bound open file descriptors, and by the time the coordinator
     * sees an item the descriptor already exists.
     */
    fun tryAcquireSlot(): Boolean {
        while (true) {
            val n = outstanding.get()
            if (n >= MAX_IN_FLIGHT) return false
            if (outstanding.compareAndSet(n, n + 1)) return true
        }
    }

    /** Returns a permit. Never goes negative: a double release is a caller bug, not extra capacity. */
    fun releaseSlot() {
        while (true) {
            val n = outstanding.get()
            if (n <= 0) return
            if (outstanding.compareAndSet(n, n - 1)) return
        }
    }

    /**
     * Appends [items] to the process-wide queue, taking ownership of every stream. Never
     * suspends and never throws, so a caller that is finishing cannot be blocked by import work.
     */
    fun enqueue(items: List<IncomingItem>) {
        for (item in items) {
            val ready = item as? IncomingItem.Ready
            // A PreResolved failure goes through the SAME queue, not straight to the
            // channel: relaying it early would reorder it ahead of the Ready items it was
            // interleaved with, and the contract is one outcome per input IN INPUT ORDER.
            if (ready != null && !tryOwn()) {
                // Defence in depth behind the permits: a caller that enqueued without one
                // must still not be able to grow the queue past the cap.
                reject(ready)
                continue
            }
            if (queue.trySend(item).isFailure) {
                if (ready != null) {
                    owned.decrementAndGet()
                    reject(ready)
                } else {
                    outcomeChannel.trySend((item as IncomingItem.PreResolved).outcome)
                }
            }
        }
    }

    /** Closes the refused item's stream, gives its permit back, and still emits its outcome. */
    private fun reject(item: IncomingItem.Ready) {
        closeQuietly(item.pending.stream)
        releaseSlot()
        outcomeChannel.trySend(IncomingImportOutcome.Failed)
    }

    private fun tryOwn(): Boolean {
        while (true) {
            val n = owned.get()
            if (n >= MAX_IN_FLIGHT) return false
            if (owned.compareAndSet(n, n + 1)) return true
        }
    }

    /** Deletes `import-*.part` leftovers older than [olderThanMillis] from this coordinator's
     *  books directory. See the companion overload for the ordering contract. */
    fun sweepStaleTempFiles(olderThanMillis: Long = STALE_TEMP_MILLIS) =
        sweepStaleTempFiles(booksDir, olderThanMillis)

    private suspend fun process(item: IncomingItem) {
        when (item) {
            is IncomingItem.PreResolved -> outcomeChannel.trySend(item.outcome)
            is IncomingItem.Ready -> try {
                outcomeChannel.trySend(runImport(item.pending))
            } finally {
                // Runs on EVERY exit incl. cancellation: the permit is released when the
                // WORKER is done with the item, never when a leaked thread finally dies.
                owned.decrementAndGet()
                releaseSlot()
            }
        }
    }

    private suspend fun runImport(pending: PendingImport): IncomingImportOutcome {
        val guard = CountingGuardStream(pending.stream, maxImportBytes)
        // The pre-import snapshot: BookImporter names the stored file from the canonical
        // key, so "this artifact already existed" is the honest duplicate signal available
        // before the key is known (see the file header's known limitation).
        val artifactsBefore = booksDir.list()?.toSet().orEmpty()
        val finished = AtomicBoolean(false)
        val watchdog = watchForStall(guard, finished)
        try {
            val call = boundedCalls.call(
                timeoutMillis = importTimeoutMillis,
                name = "import",
                onExpiry = { guard.abort() },
            ) {
                importStream.importStream(
                    sourceUri = pending.sourceUri,
                    displayName = pending.displayName,
                    input = guard,
                    format = pending.format,
                )
            }
            return when (call) {
                is BoundedCall.Completed -> IncomingImportOutcome.Imported(
                    key = call.value.fingerprintKey,
                    format = call.value.originalFormat,
                    wasAlreadyPresent = call.value.localFilePath
                        ?.let { File(it).name in artifactsBefore } ?: false,
                )
                is BoundedCall.Failed -> failureOutcome(call.error, pending.displayName)
                BoundedCall.TimedOut -> IncomingImportOutcome.Failed
            }
        } finally {
            finished.set(true)
            watchdog.cancel()
            closeQuietly(guard)
        }
    }

    /**
     * BEST-EFFORT (D8): closes the fd after [stallTimeoutMillis] with zero progress, which
     * usually makes a provider-backed pipe's parked read throw. It is guaranteed for no
     * stream shape, which is why liveness never depends on it. It cannot race a successful
     * copy: the deadline only elapses while the item is still in flight, and the worker
     * cancels this the moment the call returns.
     */
    private fun watchForStall(guard: CountingGuardStream, finished: AtomicBoolean): Job =
        appScope.launch {
            var last = guard.bytesRead
            while (true) {
                delay(stallTimeoutMillis)
                if (finished.get()) return@launch
                val now = guard.bytesRead
                if (now == last) {
                    guard.abort()
                    return@launch
                }
                last = now
            }
        }

    /** The provider is attacker-controlled, so the throwable set is not knowable: anything
     *  unrecognised is [IncomingImportOutcome.Failed] rather than an escaping exception
     *  that would produce ZERO outcomes for that URI. */
    private fun failureOutcome(error: Throwable, displayName: String): IncomingImportOutcome {
        val chain = generateSequence(error) { it.cause }.take(MAX_CAUSE_DEPTH).toList()
        return when {
            chain.any { it is ImportSizeCapExceeded } -> IncomingImportOutcome.TooLarge
            chain.any { it is ImportException.UnsupportedFormat } ->
                IncomingImportOutcome.Unsupported(displayName)
            else -> IncomingImportOutcome.Failed
        }
    }

    private fun closeQuietly(stream: InputStream) {
        try {
            stream.close()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // A provider that fails to release is not something the caller can act on.
        }
    }

    companion object {
        /** 512 MiB — clears the largest real fixtures with headroom. */
        const val MAX_IMPORT_BYTES = 512L * 1024 * 1024

        /** PROCESS-WIDE in-flight cap (queued + running), distinct from ImportActivity's per-intent MAX_BATCH. */
        const val MAX_IN_FLIGHT = 20

        val IMPORT_TIMEOUT: Duration = 5.minutes
        val STALL_TIMEOUT: Duration = 60.seconds

        /** WI-5's bound for `peek` / `resolveAndOpen` through [boundedCalls]: a cursor query
         *  plus one 4 KiB probe read, generous for a cloud-backed provider, far below the
         *  copy's budget because nothing has been transferred yet. */
        val RESOLVE_TIMEOUT: Duration = 30.seconds

        /**
         * Deletes `import-*.part` leftovers older than [olderThanMillis] in [booksDir] — a
         * crash mid-copy is the only thing that leaves one (BookImporter's `finally` deletes
         * its own temp otherwise).
         *
         * Called EXACTLY ONCE from AppContainer's constructor, so it cannot run twice and
         * cannot race a live import: nothing can have reached the importer yet. The age gate
         * is the second, independent guarantee — a file younger than an hour is never
         * touched even if the ordering argument were ever violated.
         *
         * A companion function, not just the instance method, so the container can sweep
         * WITHOUT forcing the coordinator (and through it Room) onto the startup path.
         */
        fun sweepStaleTempFiles(booksDir: File, olderThanMillis: Long = STALE_TEMP_MILLIS) {
            val cutoff = System.currentTimeMillis() - olderThanMillis
            val files = booksDir.listFiles() ?: return
            for (file in files) {
                if (!file.isFile) continue
                if (!file.name.startsWith(TEMP_PREFIX) || !file.name.endsWith(TEMP_SUFFIX)) continue
                // A zero mtime means "unknown", which is not evidence of staleness.
                if (file.lastModified() in 1 until cutoff) runCatching { file.delete() }
            }
        }

        /** Outcome-channel capacity: ≥ 3x [MAX_IN_FLIGHT], so no realistic batch of
         *  successes AND pre-resolved failures can overflow before a collector attaches. */
        private const val OUTCOME_BUFFER = 64

        private const val STALE_TEMP_MILLIS = 60L * 60 * 1000
        private const val TEMP_PREFIX = "import-"
        private const val TEMP_SUFFIX = ".part"
        private const val MAX_CAUSE_DEPTH = 8
    }
}
