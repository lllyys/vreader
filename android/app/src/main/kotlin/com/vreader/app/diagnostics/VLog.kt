package com.vreader.app.diagnostics

import android.util.Log
import java.io.PrintWriter
import java.io.StringWriter
import java.util.concurrent.atomic.AtomicLong

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

    private val sequence = AtomicLong(0L)

    /** Wire the capture floor. Called once from `VReaderApp.onCreate`. */
    fun install(sink: RingBufferDiagnosticsSource, clock: () -> Long = System::currentTimeMillis) {
        this.clock = clock
        this.sink = sink
    }

    /** Test-only: return to the uninstalled state so a global object cannot leak across tests. */
    internal fun uninstall() {
        sink = null
        clock = System::currentTimeMillis
    }

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
        val sequenceId = sequence.incrementAndGet()
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

    private fun stackTraceOf(t: Throwable): String {
        val writer = StringWriter()
        PrintWriter(writer).use { t.printStackTrace(it) }
        return writer.toString().trimEnd()
    }
}
