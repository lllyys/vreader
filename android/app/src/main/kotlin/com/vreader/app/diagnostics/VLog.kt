package com.vreader.app.diagnostics

import android.util.Log
import java.io.PrintWriter
import java.io.StringWriter
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference
import kotlin.random.Random

/**
 * Purpose: Feature #164 WI-3 — the ONE logging facade for vreader's own Android code. Every
 * deliberate log call goes through here; nothing else in `app/src/main` may reference
 * `android.util.Log` (enforced by `scripts/__tests__/check-android-log-containment.sh`).
 *
 * Each call does exactly two things:
 * 1. records into the installed [RingBufferDiagnosticsSource] (the capture floor), and
 * 2. forwards to `android.util.Log` (so logcat, `adb`, and bug reports are unchanged in
 *    substance — the plan's §10 backward-compat guarantee).
 *
 * Key decisions:
 * - **The logcat TAG becomes the category, not the class** (`"Reader"`, not `"FoliateBridge"`).
 *   Deliberate and breaking for developers: it is what lets logcat-sourced and ring-sourced
 *   entries share one category vocabulary, which is what the designed chip row is built on. The
 *   class name is preserved as a `[ClassName]` prefix on the message, so grep-by-class still
 *   works. `adb logcat -s FoliateBridge` must become `adb logcat -s Reader`.
 * - **`origin` is an explicit parameter, not derived from the stack.** Walking
 *   `Throwable().stackTrace` to name the caller looks tidier and is wrong in the places that
 *   matter: a call from a lambda or an anonymous `object :` yields a synthetic frame
 *   (`FoliateBridge$attach$2`), a call from a top-level function yields `BookShareIntentKt`, and
 *   R8 renaming would degrade the prefix to `a`. Each migrated site already had a `TAG` constant
 *   with exactly the right string; passing it is deterministic, greppable, and minification-proof.
 *   This is a documented widening of the plan's §4.1 signature.
 * - **Forwarding is UNCONDITIONAL; recording is not.** Before `install()` there is nowhere to
 *   record, but there is still somewhere to log — and silently swallowing entries logged during
 *   app start-up would be a regression against today's behavior, not a neutral no-op.
 * - **The sequence id is stamped as a LEADING marker** ([VLogMarker]) on the forwarded message
 *   only. logd truncates the tail, so a leading token survives; the ring's copy never carries it,
 *   and WI-1's parser strips it, so no marker can reach the viewer or the export.
 * - **The id is namespaced by a per-LAUNCH nonce, not a bare counter** (Gate-4 High). logd retains
 *   entries across process launches — that prior-launch trail is the one thing the platform log
 *   offers that the ring cannot. A counter restarting at 1 every launch would hand the *current*
 *   process's first entries the same ids the *previous* launch already wrote to logcat, and the
 *   composite (which prefers the ring on a collision) would then DROP exactly those pre-crash
 *   breadcrumbs. So the id is `nonce | counter`: the high [NONCE_BITS] carry a random per-launch
 *   value, the low [COUNTER_BITS] an atomic counter. Monotonic within a launch (the nonce is
 *   fixed), and ~1-in-2-million to repeat across two launches instead of guaranteed to.
 * - **A `Throwable` is rendered INTO the message** rather than handed to `Log`'s throwable
 *   overload. Both representations must be byte-identical or the composite would surface two
 *   different-looking copies of one event; passing it to `Log` as well would print the trace twice.
 *
 * @coordinates-with RingBufferDiagnosticsSource.kt, DiagnosticsCategory.kt, DiagnosticsLogEntry.kt
 *   (VLogMarker), LogcatLineParser.kt
 */
object VLog {

    @Volatile
    private var sink: RingBufferDiagnosticsSource? = null

    @Volatile
    private var clock: () -> Long = System::currentTimeMillis

    /**
     * A nonce and ITS OWN counter, swapped as one immutable unit (Gate-4 round-2 High). Holding
     * them as two independent fields (`@Volatile` nonce + shared `AtomicLong`) made the pair
     * non-atomic: an `emit` could read the old nonce, be descheduled while `install` reset the
     * counter, and then issue `oldNonce|1` — a duplicate of an id the old generation already used,
     * which the composite would silently collapse into one entry. Each generation owning its own
     * counter makes that interleaving unrepresentable.
     */
    private class Generation(val nonce: Long) {
        val counter = AtomicLong(0L)
    }

    private val generation = AtomicReference(Generation(randomLaunchNonce()))

    /**
     * Wire the capture floor. Called once from `VReaderApp.onCreate`.
     *
     * [launchNonce] exists so a test can simulate two process launches deterministically; leave it
     * defaulted in production, where a fresh random value per launch is the whole point.
     */
    fun install(
        sink: RingBufferDiagnosticsSource,
        clock: () -> Long = System::currentTimeMillis,
        launchNonce: Long = randomLaunchNonce(),
    ) {
        this.clock = clock
        // A new nonce IS a new id space, so it arrives with a counter of its own rather than
        // resetting a shared one. This is also what makes a two-launch test faithful inside one
        // JVM: without the restart the second "launch" would keep counting up and could never
        // collide, so the test would pass against the very defect it exists to catch.
        generation.set(Generation(launchNonce and NONCE_MASK))
        this.sink = sink
    }

    /** Test-only: return to the uninstalled state so a global object cannot leak across tests. */
    internal fun uninstall() {
        sink = null
        clock = System::currentTimeMillis
    }

    /** Never 0 — a zero nonce would make this launch indistinguishable from a bare counter. */
    private fun randomLaunchNonce(): Long = Random.nextLong(1L, NONCE_MASK + 1L)

    fun d(category: DiagnosticsCategory, origin: String, message: String) =
        emit(DiagnosticsLevel.DEBUG, category, origin, message, null)

    fun i(category: DiagnosticsCategory, origin: String, message: String) =
        emit(DiagnosticsLevel.INFO, category, origin, message, null)

    fun w(category: DiagnosticsCategory, origin: String, message: String, t: Throwable? = null) =
        emit(DiagnosticsLevel.WARN, category, origin, message, t)

    fun e(category: DiagnosticsCategory, origin: String, message: String, t: Throwable? = null) =
        emit(DiagnosticsLevel.ERROR, category, origin, message, t)

    // ------------------------------------------------------------------ internals

    private fun emit(
        level: DiagnosticsLevel,
        category: DiagnosticsCategory,
        origin: String,
        message: String,
        t: Throwable?,
    ) {
        val sequenceId = nextSequenceId()
        val body = buildString {
            append('[').append(origin).append("] ").append(message)
            if (t != null) append('\n').append(stackTraceOf(t))
        }
        sink?.record(level, category.tag, body, clock(), sequenceId)
        forward(level, category.tag, VLogMarker.encode(sequenceId) + body)
    }

    /**
     * `ASSERT` is unreachable from the public API above and is mapped to `Log.e` rather than
     * `Log.wtf` on purpose — `wtf` can be configured to terminate the process, which is not a
     * behavior a diagnostics facade should be able to trigger.
     */
    private fun forward(level: DiagnosticsLevel, tag: String, payload: String) {
        when (level) {
            DiagnosticsLevel.VERBOSE -> Log.v(tag, payload)
            DiagnosticsLevel.DEBUG -> Log.d(tag, payload)
            DiagnosticsLevel.INFO -> Log.i(tag, payload)
            DiagnosticsLevel.WARN -> Log.w(tag, payload)
            DiagnosticsLevel.ERROR, DiagnosticsLevel.ASSERT -> Log.e(tag, payload)
        }
    }

    /** ONE snapshot of the generation, so nonce and counter can never come from different ones. */
    private fun nextSequenceId(): Long {
        val current = generation.get()
        return (current.nonce shl COUNTER_BITS) or (current.counter.incrementAndGet() and COUNTER_MASK)
    }

    private fun stackTraceOf(t: Throwable): String {
        val writer = StringWriter()
        PrintWriter(writer).use { t.printStackTrace(it) }
        return writer.toString().trimEnd()
    }

    /**
     * 21 nonce bits + 42 counter bits = 63, so every id is a positive `Long` and renders as a
     * decimal the WI-1 marker regex (`«v(\d+)»`) accepts unchanged. 2^42 entries in one launch is
     * unreachable, so the counter cannot wrap into a neighbouring nonce's namespace.
     */
    internal const val COUNTER_BITS: Int = 42
    internal const val NONCE_BITS: Int = 21
    private const val COUNTER_MASK: Long = (1L shl COUNTER_BITS) - 1L
    private const val NONCE_MASK: Long = (1L shl NONCE_BITS) - 1L
}
