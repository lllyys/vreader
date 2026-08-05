// Purpose: feature #155 WI-4 (plan D6/D8/D9) — the ONE process-wide inbound-import queue,
// plus [BoundedCallGate], the bounded-execution primitive that closes D8's OPEN GAP.
//
// Pipeline: ImportActivity resolves + opens each URI while its read grant is alive and hands
// over one [IncomingItem] per URI -> this coordinator's single queue -> ONE long-lived worker
// -> BookImporter -> exactly one [IncomingImportOutcome] per input item.
//
// Key decisions:
//   * ONE QUEUE, ONE WORKER. Sequencing and the in-flight cap must hold ACROSS concurrent
//     ImportActivity instances (two files shared back to back, split screen). A per-call loop
//     would bound one caller and nothing else.
//   * THE ENVELOPE EXISTS SO FAILURES HAVE A ROUTE. Resolution and opening fail inside
//     ImportActivity (it owns the grant); if this queue accepted only successes,
//     Unsupported/Unreadable/TooLarge could never reach [outcomes]. PreResolved items travel
//     the SAME queue, so every input URI yields exactly one outcome, in input order.
//   * THE COORDINATOR OWNS EVERY STREAM and closes it on EVERY path — success, unsupported,
//     too large, timeout, exception, refused by the cap, and still-queued at shutdown.
//   * TWO TIMEOUT TIERS, NEVER CONFLATED (D8). GUARANTEED: each copy runs as an independent
//     job awaited under a hard bound, so the worker advances and returns the item's permit
//     unconditionally on expiry. BEST-EFFORT: a progress watchdog closes the fd, which usually
//     releases a provider-backed pipe and is guaranteed for nothing.
//   * BLOCKING WORK RUNS IN A PRIVATE LANE, NEVER ON Dispatchers.IO. A provider that parks
//     forever must not consume one of the app's shared IO workers — 64 of those are all the
//     app has, and starving them would take the whole app down with the import. The lane is
//     elastic, so a parked thread never denies a fresh import; the number of simultaneously
//     parked calls is bounded instead by [BoundedCallGate]'s abandoned-call ceiling.
//   * OUTCOMES GO THROUGH A GENEROUSLY-BOUNDED CHANNEL, never a non-replaying SharedFlow: an
//     outcome raised before MainActivity collects (cold start / rotation) must survive (D9).
//     The bound is >12x a full inbound batch, so one-outcome-per-input holds for every realistic
//     case; past it delivery degrades explicitly rather than either suspending the worker or
//     letting an exported entry point grow memory without limit.
//
// Known limitation: `wasAlreadyPresent` is a heuristic — see its KDoc. The exact signal needs
// BookImporter to report it, which is outside this WI's write-set.
//
// @coordinates-with: IncomingBookResolver + ImportActivity (WI-5: acquires a slot, opens the
//   stream, builds the item), BookImporter.importStream, VReaderApp.AppContainer
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
    /**
     * [wasAlreadyPresent] is a HEURISTIC, not a fact: it reports whether this book's
     * content-addressed artifact was already on disk before the copy started. The canonical
     * key only exists after BookImporter has hashed the bytes, by which point its upsert has
     * already run, so a row lookup can no longer answer the question. It is therefore wrong
     * when an artifact was orphaned by an earlier DB failure (false positive), when a row's
     * artifact was deleted out from under it (false negative), when another import creates
     * the artifact in between (false positive), and when the directory listing fails (false
     * negative). Nothing consumes it yet; an exact signal needs BookImporter to return it.
     */
    data class Imported(val key: String, val format: BookFormat, val wasAlreadyPresent: Boolean) :
        IncomingImportOutcome

    data class Unsupported(val displayName: String) : IncomingImportOutcome

    /** The provider refused to open the document at all. */
    data object Unreadable : IncomingImportOutcome

    data object TooLarge : IncomingImportOutcome

    data object Failed : IncomingImportOutcome
}

/**
 * ONE in-flight admission, reserved BEFORE a stream is opened and released exactly once at the
 * item's terminal outcome.
 *
 * A token rather than a bare `release()` call because the permit has an OWNER: ImportActivity
 * holds it from before `resolveAndOpen` until either a [IncomingItem.Ready] reaches `enqueue`
 * (ownership transfers to the coordinator) or any other exit releases it. Releasing is
 * IDEMPOTENT, so the natural `try { … } finally { slot.release() }` around a transfer cannot
 * hand a second permit back and silently raise the cap for every other caller.
 */
class ImportSlot internal constructor(private val onRelease: () -> Unit) {
    private val released = AtomicBoolean(false)

    fun release() {
        if (released.compareAndSet(false, true)) onRelease()
    }
}

/** One inbound URI's work: either an opened document, or a failure that already happened. */
sealed interface IncomingItem {
    /** [slot] transfers to the coordinator, which releases it at the terminal outcome. */
    data class Ready(val pending: PendingImport, val slot: ImportSlot) : IncomingItem

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
 * The guarantee is about the caller: on expiry it returns [BoundedCall.TimedOut] and proceeds
 * UNCONDITIONALLY, whether or not the call ever finishes. The price is one parked thread per
 * abandoned call, and TWO things keep that price bounded:
 *
 *  * [blockingLane] is a PRIVATE elastic pool, never `Dispatchers.IO` — the caller must pin
 *    the callee's own dispatcher to it too, or the block simply relocates itself back onto the
 *    shared pool and starves unrelated app IO (Gate-4 round 1, Critical).
 *  * [abandonedCalls] counts calls the caller walked away from and has not seen finish. Admission
 *    consults it, so an attacker cannot recycle a fast-returning permit into an unbounded pile of
 *    parked reads. It self-heals: the count drops the moment a call finally returns.
 *
 * This is NOT the "caller-local executor + timeout" the plan rejected: that one hangs silently
 * once its fixed pool fills. Here the queue never stalls, refusal is immediate and visible as a
 * failure outcome, and capacity comes back on its own.
 *
 * A late result is DISPOSED, never leaked: [dispose] closes whatever the abandoned call
 * eventually produced. An InputStream nobody owns is an fd leak on an exported entry point.
 */
class BoundedCallGate(
    private val scope: CoroutineScope,
    private val blockingLane: CoroutineDispatcher,
    private val contextFactory: (String) -> CoroutineDispatcher = { blockingLane },
) {
    private val abandoned = AtomicInteger(0)

    /** Calls the caller abandoned and has not observed finishing — parked threads + fds. */
    val abandonedCalls: Int get() = abandoned.get()

    /**
     * Runs [block] as an independent job and waits at most [timeoutMillis] for it.
     *
     * [onExpiry] is the BEST-EFFORT lever (e.g. close the fd) — it may or may not release the
     * parked call, and correctness never depends on it. [dispose] releases a result that
     * arrives after the caller has already moved on.
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
        val givenUp = AtomicBoolean(false)
        // A child of [scope], NOT of the awaiting coroutine: abandoning the await must not
        // cancel the job (cancelling it would not unpark a blocking read anyway), while
        // cancelling appScope must.
        val job = scope.async(dispatcher) {
            val value = block()
            produced.set(value)
            // The caller may have given up meanwhile — then this value is ours to dispose.
            // `getAndSet` makes exactly one side win the race.
            if (givenUp.get()) disposeOnce(produced, dispose)
            value
        }
        job.invokeOnCompletion {
            // Never close the shared lane; only a per-call dispatcher a caller injected.
            if (dispatcher !== blockingLane) (dispatcher as? ExecutorCoroutineDispatcher)?.close()
        }

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
            giveUp(job, givenUp, produced, dispose)
            runCatching { onExpiry() }
            return BoundedCall.TimedOut
        } finally {
            // The caller itself was cancelled (appScope torn down) after `await` had already
            // produced a value — the documented "returning a closeable from a cancellable
            // wait" hole. Nothing else would ever close it.
            if (!settled) giveUp(job, givenUp, produced, dispose)
        }
    }

    private fun <T> giveUp(
        job: Job,
        givenUp: AtomicBoolean,
        produced: AtomicReference<T?>,
        dispose: (T) -> Unit,
    ) {
        if (!givenUp.compareAndSet(false, true)) return
        abandoned.incrementAndGet()
        // Self-healing: whenever the parked call finally returns (or the scope dies), the
        // thread + fd are back and admission recovers.
        job.invokeOnCompletion { abandoned.decrementAndGet() }
        disposeOnce(produced, dispose)
    }

    private fun <T> disposeOnce(produced: AtomicReference<T?>, dispose: (T) -> Unit) {
        produced.getAndSet(null)?.let { runCatching { dispose(it) } }
    }
}

private val laneThreads = AtomicLong(0)

/**
 * The private lane for every blocking call made on behalf of an untrusted provider: the
 * resolver's cursor query / open / probe read, and the inbound copy.
 *
 * ELASTIC (a cached pool) on purpose — a thread parked forever in a provider read must never
 * deny a fresh import, which is what a fixed pool would do. Daemon threads, so a parked one
 * never keeps the process (or a test JVM) alive.
 */
internal fun inboundBlockingLane(): CoroutineDispatcher =
    Executors.newCachedThreadPool { runnable ->
        Thread(runnable, "vreader-inbound-${laneThreads.incrementAndGet()}").apply { isDaemon = true }
    }.asCoroutineDispatcher()

/** A private single thread, for a caller that wants one call isolated from every other. */
internal fun dedicatedThreadDispatcher(name: String): CoroutineDispatcher =
    Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "vreader-$name-${laneThreads.incrementAndGet()}").apply { isDaemon = true }
    }.asCoroutineDispatcher()

/**
 * Errors that mean the VM itself is compromised. Everything else an attacker-supplied stream
 * can raise is contained per item; these are rethrown, because swallowing them would hide real
 * process corruption behind a "one import failed" toast.
 */
internal fun Throwable.isFatal(): Boolean =
    this is VirtualMachineError || this is ThreadDeath || this is LinkageError

/** Thrown by [CountingGuardStream] past the byte cap; mapped to [IncomingImportOutcome.TooLarge]. */
internal class ImportSizeCapExceeded(limit: Long) : IOException("import exceeded $limit bytes")

/**
 * The POST-OPEN size backstop (D8). ImportActivity rejects a declared oversize before opening;
 * this covers what a cursor cannot: an absent size, a lying size, and a stream that never ends.
 * Also carries the progress counter the stall watchdog reads.
 *
 * CLOSE-ONCE. Three owners can reach the source — BookImporter's `input.use`, the watchdog's
 * [abort], and the coordinator's own `finally` — and an attacker-supplied stream is not obliged
 * to tolerate a second `close()`.
 */
internal class CountingGuardStream(source: InputStream, private val maxBytes: Long) :
    FilterInputStream(source) {

    private val counted = AtomicLong(0)
    private val closed = AtomicBoolean(false)

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

    override fun close() {
        if (closed.compareAndSet(false, true)) `in`.close()
    }

    private fun countOrThrow(n: Long) {
        if (counted.addAndGet(n) > maxBytes) throw ImportSizeCapExceeded(maxBytes)
    }

    /** Best-effort release of a parked read: close the fd from another coroutine. */
    fun abort() {
        runCatching { close() }
    }
}

/**
 * The process-wide inbound-import queue.
 *
 * Takes ownership of every [PendingImport.stream]. `enqueue` is called from ImportActivity's
 * `lifecycleScope` but every copy runs on [appScope], so a finished activity never cancels an
 * in-flight import while a torn-down app does.
 */
class IncomingImportCoordinator internal constructor(
    private val importStream: ImportStreamPort,
    private val booksDir: File,
    private val appScope: CoroutineScope,
    blockingLane: CoroutineDispatcher,
    private val importTimeoutMillis: Long = IMPORT_TIMEOUT.inWholeMilliseconds,
    private val stallTimeoutMillis: Long = STALL_TIMEOUT.inWholeMilliseconds,
    private val maxImportBytes: Long = MAX_IMPORT_BYTES,
    copyContextFactory: (String) -> CoroutineDispatcher = { blockingLane },
) {
    /**
     * [importer] MUST be pinned to [blockingLane] (`BookImporter(booksDir, repository, lane)`),
     * not to `Dispatchers.IO`: `importStream` switches dispatchers internally, so an importer
     * built with the default would park the untrusted read on a shared IO worker no matter what
     * this coordinator does.
     */
    constructor(
        importer: BookImporter,
        booksDir: File,
        appScope: CoroutineScope,
        blockingLane: CoroutineDispatcher,
    ) : this(
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
        blockingLane = blockingLane,
    )

    /**
     * The bounded-execution primitive WI-5 wraps `peek` / `resolveAndOpen` in, so a hostile
     * provider cannot hold an inbound slot forever (D8's OPEN GAP). Exposed here because the
     * guarantee and the admission accounting are one design, not two.
     */
    val boundedCalls: BoundedCallGate = BoundedCallGate(appScope, blockingLane, copyContextFactory)

    // UNLIMITED as a CHANNEL so `enqueue` can never suspend a caller that is finishing, and so a
    // Ready item — which owns an open fd — is never silently dropped by a buffer policy. Depth is
    // bounded by [queueDepth] instead: Ready items by MAX_IN_FLIGHT, PreResolved envelopes (which
    // hold no slot, and so were the one unbounded input left) by MAX_PENDING_ITEMS.
    private val queue = Channel<IncomingItem>(Channel.UNLIMITED)

    /** Items sitting in [queue] awaiting the worker — the bound the channel itself does not give. */
    private val queueDepth = AtomicInteger(0)

    internal val pendingItems: Int get() = queueDepth.get()

    // Written with `trySend`, so emitting can never suspend the ONE worker — a buffer that made
    // the worker wait for a collector would wedge every later import.
    //
    // The capacity is a REAL bound, spelled out, with DROP_LATEST: an exported entry point can
    // be launched in a loop, and neither this channel nor the input queue is otherwise bounded
    // (PreResolved items hold no slot), so an unlimited buffer is a memory-exhaustion surface
    // (Gate-4 round 2, High). MAX_PENDING_OUTCOMES is >12x a full inbound batch, so the
    // one-outcome-per-input contract holds for every realistic cold start; past it the contract
    // degrades EXPLICITLY to "the oldest MAX_PENDING_OUTCOMES are delivered". That costs at most
    // an advisory failure toast — library state is unaffected either way (D9's accepted Low) —
    // and it is the only degradation that keeps both liveness and memory bounded.
    //
    // The capacity is also spelled out because `Channel(Channel.BUFFERED, <non-SUSPEND policy>)`
    // does NOT mean "64 with that policy": it builds a ConflatedBufferedChannel of capacity ONE,
    // which silently reduces a whole batch to its last outcome. (Caught by test, not by review.)
    private val outcomeChannel =
        Channel<IncomingImportOutcome>(MAX_PENDING_OUTCOMES, BufferOverflow.DROP_LATEST)

    val outcomes: Flow<IncomingImportOutcome> = outcomeChannel.receiveAsFlow()

    private fun emit(outcome: IncomingImportOutcome) {
        outcomeChannel.trySend(outcome)
    }

    /** Slots (queued + running) held process-wide; reserved by WI-5 BEFORE it opens a stream. */
    private val outstanding = AtomicInteger(0)

    /** Ready items this coordinator currently owns — the queue-side view of the same cap. */
    private val owned = AtomicInteger(0)

    internal val outstandingSlots: Int get() = outstanding.get()

    init {
        val worker = appScope.launch {
            for (item in queue) {
                queueDepth.decrementAndGet()
                // One item's failure must never kill the ONE worker and wedge every later
                // import — including an Error thrown by an attacker-supplied stream's close().
                try {
                    process(item)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Throwable) {
                    if (e.isFatal()) throw e
                    emit(IncomingImportOutcome.Failed)
                }
            }
        }
        // When the worker dies (appScope cancelled), admission stops and every still-queued
        // stream is released. Without this, a torn-down scope strands open fds and holds their
        // slots forever (Gate-4 round 1, High).
        worker.invokeOnCompletion { shutdown() }
    }

    /**
     * Reserves one of [MAX_IN_FLIGHT] in-flight slots, or returns null when the app is at
     * capacity. WI-5 calls this BEFORE opening a stream — the cap must bound open file
     * descriptors, and by the time the coordinator sees an item the descriptor already exists.
     *
     * Usage (WI-5): reserve AFTER the own-authority guard and BEFORE `peek`; hold under
     * `try { … } finally { if (!transferred) slot.release() }`; ownership passes to the
     * coordinator if and only if a [IncomingItem.Ready] carrying this slot reaches [enqueue].
     * A refused reservation is `PreResolved(Failed)` with nothing opened.
     */
    fun acquireSlot(): ImportSlot? {
        // Parked calls hold a thread + an fd each; without this, a hostile provider could
        // convert recycled slots into an unbounded pile of them.
        //
        // This is a THRESHOLD, not a strict ceiling, and the difference is deliberate: it is
        // read separately from the slot CAS, so up to [MAX_IN_FLIGHT] already-admitted items can
        // still convert after the last check. The provable worst case is therefore
        // MAX_ABANDONED_CALLS + MAX_IN_FLIGHT parked calls (Gate-4 round 2, Medium — the earlier
        // "strict 20" claim was false). Folding both into ONE budget would make it strict, and
        // was rejected: 20 permanently-stuck providers would then deny every future import,
        // which is exactly the silent-denial failure D8 rejected the caller-local pool for.
        if (boundedCalls.abandonedCalls >= MAX_ABANDONED_CALLS) return null
        while (true) {
            val n = outstanding.get()
            if (n >= MAX_IN_FLIGHT) return null
            if (outstanding.compareAndSet(n, n + 1)) {
                return ImportSlot { outstanding.decrementAndGet() }
            }
        }
    }

    /**
     * Appends [items] to the process-wide queue, taking ownership of every stream. Never
     * suspends and never throws, so a caller that is finishing cannot be blocked by import work.
     *
     * EVERY item leaves here owing exactly one outcome, and the queue itself NEVER drops: an item
     * is either accepted (the worker owes its outcome) or handled INLINE right here (its outcome
     * is emitted immediately). That is what makes one-outcome-per-input-URI hold by construction
     * rather than by care — a queue that may drop is in permanent tension with the contract
     * (Gate-4 round 4, High). The one remaining, documented degradation is the delivery buffer's
     * own bound; see [outcomeChannel].
     *
     * Inline handling costs input ORDER for that item under overload, never the outcome itself —
     * the same trade the over-cap [reject] path has always made.
     */
    fun enqueue(items: List<IncomingItem>) {
        for (item in items) {
            val ready = item as? IncomingItem.Ready
            // A PreResolved failure normally goes through the SAME queue, not straight to the
            // delivery channel: relaying it early would reorder it ahead of the Ready items it
            // was interleaved with, and the contract is one outcome per input IN INPUT ORDER.
            if (ready != null) {
                // Defence in depth behind the slots: a caller that enqueued without one must
                // still not be able to grow the queue past the cap.
                if (!tryOwn()) {
                    reject(ready)
                    continue
                }
                // A Ready item is never refused for DEPTH — it is separately capped at
                // MAX_IN_FLIGHT and owns an open fd that must not be handled inline — so it is
                // admitted unconditionally and merely counted. Worst-case depth is therefore
                // MAX_PENDING_ITEMS + MAX_IN_FLIGHT.
                queueDepth.incrementAndGet()
            } else if (!tryReserveDepth()) {
                // Overload from a hostile launch loop: the exported entry point can be started
                // faster than one worker drains, and a PreResolved envelope takes no slot, so
                // this is the input the depth bound exists for. It holds no fd and no library
                // state, so it is handled INLINE — its own outcome, not a substituted failure.
                emit((item as IncomingItem.PreResolved).outcome)
                continue
            }
            if (queue.trySend(item).isFailure) {         // only after shutdown
                queueDepth.decrementAndGet()
                if (ready != null) {
                    owned.decrementAndGet()
                    reject(ready)
                } else {
                    emit((item as IncomingItem.PreResolved).outcome)
                }
            }
        }
    }

    /**
     * Reserves one queue slot, or refuses at [MAX_PENDING_ITEMS].
     *
     * A CAS loop, NOT `get()`-then-`increment`: `enqueue` is reachable from an exported activity,
     * so concurrent callers are the EXPECTED case, and a check separated from its increment lets
     * every one of them pass while below the cap and collectively push past it (Gate-4 round 4,
     * High). Released on all three paths the counter is decremented: worker receive, failed
     * post-shutdown send, and the shutdown drain.
     */
    private fun tryReserveDepth(): Boolean {
        while (true) {
            val n = queueDepth.get()
            if (n >= MAX_PENDING_ITEMS) return false
            if (queueDepth.compareAndSet(n, n + 1)) return true
        }
    }

    private suspend fun process(item: IncomingItem) {
        when (item) {
            is IncomingItem.PreResolved -> emit(item.outcome)
            is IncomingItem.Ready -> try {
                emit(runImport(item.pending))
            } finally {
                // Runs on EVERY exit incl. cancellation: the slot is released when the WORKER
                // is done with the item, never when a leaked thread finally dies.
                owned.decrementAndGet()
                item.slot.release()
            }
        }
    }

    private suspend fun runImport(pending: PendingImport): IncomingImportOutcome {
        val guard = CountingGuardStream(pending.stream, maxImportBytes)
        // The pre-import snapshot behind the `wasAlreadyPresent` heuristic (see its KDoc):
        // BookImporter names the stored file from the canonical key, so "this artifact already
        // existed" is the closest signal available before the key is known.
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
     * usually makes a provider-backed pipe's parked read throw. It is guaranteed for no stream
     * shape, which is why liveness never depends on it. It cannot race a successful copy: the
     * deadline only elapses while the item is still in flight, and the worker cancels this the
     * moment the call returns.
     *
     * It deliberately does NOT interrupt the reading thread: the read runs on the shared
     * inbound lane, and a stale interrupt flag on a pooled thread would leak into whatever task
     * that thread runs next.
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

    /** Closes the refused item's stream, gives its slot back, and still emits its outcome. */
    private fun reject(item: IncomingItem.Ready) {
        closeQuietly(item.pending.stream)
        item.slot.release()
        emit(IncomingImportOutcome.Failed)
    }

    private fun tryOwn(): Boolean {
        while (true) {
            val n = owned.get()
            if (n >= MAX_IN_FLIGHT) return false
            if (owned.compareAndSet(n, n + 1)) return true
        }
    }

    /**
     * Stops admission and releases every item the dead worker will never process.
     *
     * Each item is isolated: this runs inside a completion handler, so one hostile stream
     * throwing from `close()` must not abort the drain and strand every item behind it
     * (Gate-4 round 2, High). The slot is released in a `finally` for the same reason.
     */
    private fun shutdown() {
        queue.close()
        while (true) {
            val item = queue.tryReceive().getOrNull() ?: return
            queueDepth.decrementAndGet()
            releaseDrained(item)
        }
    }

    /** Isolated per item: one hostile stream throwing from `close()` must not abort the drain
     *  and strand everything behind it. */
    private fun releaseDrained(item: IncomingItem) {
        when (item) {
            is IncomingItem.Ready -> try {
                owned.decrementAndGet()
                reject(item)
            } finally {
                item.slot.release()
            }
            is IncomingItem.PreResolved -> emit(item.outcome)
        }
    }

    /** The provider is attacker-controlled, so the throwable set is not knowable: anything
     *  unrecognised is [IncomingImportOutcome.Failed] rather than an escaping exception that
     *  would produce ZERO outcomes for that URI. */
    private fun failureOutcome(error: Throwable, displayName: String): IncomingImportOutcome {
        val chain = generateSequence(error) { it.cause }.take(MAX_CAUSE_DEPTH).toList()
        return when {
            chain.any { it is ImportSizeCapExceeded } -> IncomingImportOutcome.TooLarge
            chain.any { it is ImportException.UnsupportedFormat } ->
                IncomingImportOutcome.Unsupported(displayName)
            else -> IncomingImportOutcome.Failed
        }
    }

    /**
     * Contains everything a provider's `close()` can throw — including a
     * `CancellationException`, which from a NON-SUSPENDING cleanup path is just another
     * throwable an attacker-supplied stream chose to raise, NOT this coroutine being cancelled.
     * Rethrowing it here would replace the item's outcome, propagate out of the single worker
     * and wedge the queue (Gate-4 round 2, High). Only genuinely process-fatal errors pass
     * through: hiding those would obscure real VM corruption, and the process is going down
     * regardless.
     */
    private fun closeQuietly(stream: InputStream) {
        try {
            stream.close()
        } catch (e: Throwable) {
            if (e.isFatal()) throw e
            // Otherwise nothing actionable: the fd is the provider's to release.
        }
    }

    companion object {
        /** 512 MiB — clears the largest real fixtures with headroom. */
        const val MAX_IMPORT_BYTES = 512L * 1024 * 1024

        /** PROCESS-WIDE in-flight cap (queued + running), distinct from ImportActivity's per-intent MAX_BATCH. */
        const val MAX_IN_FLIGHT = 20

        /** Admission threshold on calls the app has walked away from that are still parked (one
         *  thread + one fd each) — see [acquireSlot] for why it is a threshold rather than a
         *  strict ceiling, and for the provable worst case. Separate from [MAX_IN_FLIGHT] so a
         *  handful of stuck providers cannot deny ordinary imports, and self-healing, so denial
         *  lasts only as long as the stall does. */
        const val MAX_ABANDONED_CALLS = 20

        /** Undelivered outcomes retained while nothing is collecting — see [outcomeChannel]. */
        const val MAX_PENDING_OUTCOMES = 256

        /** Admission bound on items awaiting the worker: it refuses PreResolved envelopes, which
         *  hold no slot and are otherwise unbounded. Ready items are admitted unconditionally
         *  (separately capped at [MAX_IN_FLIGHT]), so the provable worst-case depth is
         *  `MAX_PENDING_ITEMS + MAX_IN_FLIGHT`. A refused envelope is handled inline, never
         *  dropped — see [enqueue]. */
        const val MAX_PENDING_ITEMS = 256

        val IMPORT_TIMEOUT: Duration = 5.minutes
        val STALL_TIMEOUT: Duration = 60.seconds

        /** WI-5's bound for `peek` / `resolveAndOpen` through [boundedCalls]: a cursor query
         *  plus one 4 KiB probe read, generous for a cloud-backed provider, far below the
         *  copy's budget because nothing has been transferred yet. */
        val RESOLVE_TIMEOUT: Duration = 30.seconds

        /**
         * Deletes `import-*.part` leftovers older than [olderThanMillis] in [booksDir] — a crash
         * mid-copy is the only thing that leaves one (BookImporter's `finally` deletes its own
         * temp otherwise).
         *
         * Called EXACTLY ONCE from AppContainer's constructor, so it cannot run twice and cannot
         * race a live import: nothing can have reached the importer yet. The age gate is the
         * second, independent guarantee — a file younger than an hour is never touched even if
         * the ordering argument were ever violated.
         *
         * A companion function, not just the instance method, so the container can sweep WITHOUT
         * forcing the coordinator (and through it Room) onto the startup path.
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

        private const val STALE_TEMP_MILLIS = 60L * 60 * 1000
        private const val TEMP_PREFIX = "import-"
        private const val TEMP_SUFFIX = ".part"
        private const val MAX_CAUSE_DEPTH = 8
    }

    /** Deletes `import-*.part` leftovers older than [olderThanMillis] from this coordinator's
     *  books directory. See the companion overload for the ordering contract. */
    fun sweepStaleTempFiles(olderThanMillis: Long = STALE_TEMP_MILLIS) =
        sweepStaleTempFiles(booksDir, olderThanMillis)
}
