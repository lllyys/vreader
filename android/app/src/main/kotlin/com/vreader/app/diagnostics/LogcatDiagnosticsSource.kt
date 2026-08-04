package com.vreader.app.diagnostics

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.Closeable
import java.io.InputStream
import java.io.InputStreamReader
import java.nio.charset.StandardCharsets
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlin.coroutines.cancellation.CancellationException

/**
 * Purpose: Feature #164 WI-1 — the OS boundary. Execs `logcat -d` from the app's own
 * process and hands its stdout to [LogcatLineParser].
 *
 * This class is the feature's load-bearing platform bet: a non-privileged app reading its
 * own log entries back. `READ_LOGS` is `signature|privileged` and is deliberately NOT
 * requested — the read either works for `untrusted_app` on its own uid, or the feature
 * degrades to the in-process ring buffer (WI-3). `LogcatSelfReadConnectedTest` is the gate
 * that decides which.
 *
 * Key decisions:
 * - **`Unavailable` and `Available(emptyList())` are never conflated**, because the composite
 *   source and the export header's `capture source:` line key off that distinction. The
 *   classification is deliberately NOT exit-code-only: `redirectErrorStream(true)` folds
 *   logcat's own diagnostics into stdout, so a denial that still exits 0 would otherwise be
 *   read as "quiet". The rule is a conjunction — **zero parsed own-uid rows AND a logcat
 *   diagnostic line in the output means Unavailable**; parsing even one of our own rows is
 *   positive proof the reader worked, and zero rows with no diagnostic is a genuinely quiet
 *   buffer.
 * - **The timeout is a watchdog that KILLS the child and closes the stream**, not a
 *   cancellation of a blocking read: `InputStream.read` ignores coroutine cancellation. The
 *   child is destroyed FIRST and the stream closed second, because killing the writer closes
 *   the pipe's far end and unblocks the reader even if our own `close()` were to stall — two
 *   independent ways out instead of one. The watchdog is a short-lived DAEMON THREAD rather
 *   than a coroutine child on purpose: as a structured child, a blocking cleanup call would
 *   stall `withContext` indefinitely, which is exactly the wedge a diagnostics path must
 *   never cause.
 * - **Cleanup has exactly ONE owner.** An [AtomicReference] state machine arbitrates
 *   `READING -> COMPLETED` (reader won) versus `READING -> TIMED_OUT` (watchdog won), so a
 *   read that finishes just as the watchdog fires is classified deterministically and is
 *   never both cleaned up twice and discarded.
 * - **The child is reaped on every exit path**, including an unexpected throw (outer
 *   `finally`). Cleanup is `destroy()` -> bounded wait -> `destroyForcibly()` -> bounded
 *   wait; an unconfirmed exit yields `null`, and **`null` is never treated as success on any
 *   path, truncated or not**. [CLEANUP_BUDGET_MS] bounds the cleanup WAITS; `close(2)` and
 *   `kill(2)` on a pipe fd are taken as non-blocking, and if a platform ever made them block
 *   it is the daemon watchdog — not the caller — that absorbs it.
 * - **`redirectErrorStream(true)` + a single reader.** Two pipes with one drain deadlocks as
 *   soon as the undrained one fills; folding stderr into stdout removes the second pipe.
 * - **`sinceMillis` is applied in Kotlin, not via logcat's `-t <time>`**, whose time format
 *   is format-sensitive and would make correctness depend on argv parsing we cannot test
 *   off-device.
 *
 * `recentEntries` never throws to signal a source failure. `CancellationException` is the one
 * exception that still propagates, as it must — cancelling the caller is not a source failure.
 *
 * @coordinates-with LogcatLineParser.kt, DiagnosticsLogSource.kt
 */
class LogcatDiagnosticsSource(
    private val ownUid: Int = android.os.Process.myUid(),
    private val maxLines: Int = DEFAULT_MAX_LINES,
    private val maxBytes: Int = DEFAULT_MAX_BYTES,
    private val processTimeoutMs: Long = DEFAULT_TIMEOUT_MS,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
    private val exec: (List<String>) -> Process = {
        ProcessBuilder(it).redirectErrorStream(true).start()
    },
) : DiagnosticsLogSource {

    override suspend fun recentEntries(sinceMillis: Long?, limit: Int): SourceResult =
        withContext(ioDispatcher) {
            val process = try {
                exec(command(maxLines))
            } catch (t: Throwable) {
                return@withContext SourceResult.Unavailable(
                    "logcat could not be started: ${t.javaClass.simpleName}: ${t.message}"
                )
            }
            val reaped = AtomicBoolean(false)
            try {
                collect(process, reaped, sinceMillis, limit)
            } catch (cancellation: CancellationException) {
                throw cancellation // cancelling the caller is not a source failure
            } catch (t: Throwable) {
                // The "never throws" half of the contract, enforced at the boundary rather
                // than trusted to every internal call site.
                SourceResult.Unavailable(
                    "logcat read failed unexpectedly: ${t.javaClass.simpleName}: ${t.message}"
                )
            } finally {
                // No exit path — including an unexpected throw — may leave a child behind.
                if (reaped.compareAndSet(false, true)) reap(process, force = true)
            }
        }

    private fun collect(
        process: Process,
        reaped: AtomicBoolean,
        sinceMillis: Long?,
        limit: Int,
    ): SourceResult {
        val stream = try {
            process.inputStream
        } catch (t: Throwable) {
            return SourceResult.Unavailable("logcat stdout unavailable: ${t.javaClass.simpleName}")
        }

        val state = AtomicReference(ReadState.READING)
        val finished = CountDownLatch(1)
        val watchdog = Thread({
            if (!finished.await(processTimeoutMs, TimeUnit.MILLISECONDS)) {
                // Only the CAS winner cleans up, so a read that completed microseconds ago is
                // never torn down underneath a valid result.
                if (state.compareAndSet(ReadState.READING, ReadState.TIMED_OUT)) {
                    runCatching { process.destroy() } // kill first: unblocks the reader itself
                    closeQuietly(stream)
                }
            }
        }, WATCHDOG_THREAD_NAME).apply { isDaemon = true; start() }

        var readFailure: Throwable? = null
        val drained = try {
            readBounded(stream)
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (t: Throwable) {
            readFailure = t
            Drained(emptyList(), truncated = false)
        } finally {
            val weOwnCleanup = state.compareAndSet(ReadState.READING, ReadState.COMPLETED)
            finished.countDown()
            // ONLY the CAS winner closes. If the watchdog won, the close belongs to its daemon
            // thread and a stall there costs us nothing; the caller never re-closes a stream it
            // does not own. On our own path the pipe is already at EOF, where close cannot block.
            if (weOwnCleanup) closeQuietly(stream)
            runCatching { watchdog.join(WATCHDOG_JOIN_BUDGET_MS) }
        }

        reaped.set(true)
        if (state.get() == ReadState.TIMED_OUT) {
            reap(process, force = true)
            return SourceResult.Unavailable("logcat timed out after ${processTimeoutMs}ms")
        }
        if (readFailure != null) {
            reap(process, force = true)
            return SourceResult.Unavailable(
                "logcat read failed: ${readFailure.javaClass.simpleName}: ${readFailure.message}"
            )
        }

        // A truncated read means logcat produced MORE than we asked for, which is itself
        // positive evidence the reader works — so we ignore a CONFIRMED non-zero status there
        // (we killed it mid-write). An UNCONFIRMED reap is never success on either path.
        val exitCode = reap(process, force = drained.truncated)
        if (exitCode == null) {
            return SourceResult.Unavailable("logcat could not be confirmed reaped")
        }
        if (!drained.truncated && exitCode != 0) {
            return SourceResult.Unavailable("logcat exited with $exitCode")
        }

        val parsed = LogcatLineParser.parse(drained.lines.asSequence(), ownUid)
        if (parsed.isEmpty()) {
            val diagnostic = drained.lines.firstOrNull(::isLogcatDiagnostic)
            if (diagnostic != null) {
                return SourceResult.Unavailable("logcat reported a read failure: $diagnostic")
            }
        }

        var entries = parsed
        if (sinceMillis != null) entries = entries.filter { it.timeMillis >= sinceMillis }
        val cap = limit.coerceAtLeast(0)
        if (entries.size > cap) entries = entries.takeLast(cap)
        return SourceResult.Available(entries)
    }

    /**
     * Retains at most [maxLines] lines and [maxBytes] encoded bytes — a HARD bound: a line
     * that would cross the budget is not retained at all (so a single oversized line cannot
     * blow past it). `truncated` means we stopped on our own bound rather than at EOF.
     *
     * Deliberately does NOT close the stream (hence no `use`): closing belongs to whichever
     * of reader/watchdog wins the cleanup CAS, so a `close()` that stalled could never be
     * executed on the caller's thread against a stream it does not own.
     */
    private fun readBounded(stream: InputStream): Drained {
        val lines = ArrayList<String>(minOf(maxLines, INITIAL_CAPACITY))
        var bytes = 0L
        var truncated = false
        val reader = BufferedReader(InputStreamReader(stream, StandardCharsets.UTF_8))
        while (true) {
            val line = reader.readLine() ?: break
            val lineBytes = line.toByteArray(StandardCharsets.UTF_8).size + 1
            if (lines.size >= maxLines || bytes + lineBytes > maxBytes) {
                truncated = true
                break
            }
            bytes += lineBytes
            lines.add(line)
        }
        return Drained(lines, truncated)
    }

    /**
     * `destroy()` -> bounded wait -> `destroyForcibly()` -> bounded wait. Returns the child's
     * exit status, or `null` when termination could not be CONFIRMED within
     * [CLEANUP_BUDGET_MS]; `null` is never treated as success. Bounded by construction — this
     * runs on a UI-adjacent call path and may not block indefinitely, so an unreapable child
     * is reported rather than waited on forever.
     */
    private fun reap(process: Process, force: Boolean): Int? {
        if (force) runCatching { process.destroy() }
        awaitExit(process)?.let { return it }
        runCatching { process.destroyForcibly() }
        return awaitExit(process)
    }

    private fun awaitExit(process: Process): Int? = try {
        if (process.waitFor(REAP_BUDGET_MS, TimeUnit.MILLISECONDS)) process.exitValue() else null
    } catch (t: Throwable) {
        null
    }

    private fun closeQuietly(closeable: Closeable) {
        runCatching { closeable.close() }
    }

    private fun isLogcatDiagnostic(line: String): Boolean =
        LOGCAT_DIAGNOSTIC.containsMatchIn(line.removeSuffix("\r"))

    private data class Drained(val lines: List<String>, val truncated: Boolean)

    /** Who owns cleanup: whoever moves the state out of [READING] first. */
    private enum class ReadState { READING, COMPLETED, TIMED_OUT }

    companion object {
        const val DEFAULT_MAX_LINES: Int = 5_000
        const val DEFAULT_MAX_BYTES: Int = 2 * 1024 * 1024
        const val DEFAULT_TIMEOUT_MS: Long = 5_000

        private const val REAP_BUDGET_MS: Long = 1_000
        private const val WATCHDOG_JOIN_BUDGET_MS: Long = 500
        private const val INITIAL_CAPACITY: Int = 1_024
        private const val WATCHDOG_THREAD_NAME: String = "vreader-diag-logcat-watchdog"

        /**
         * Worst-case cleanup WAIT time after the read budget expires: the watchdog join plus
         * two bounded reap waits. Part of the contract so callers (and the connected test) can
         * assert a real upper bound instead of an arbitrary slack.
         *
         * It bounds the waits, not the syscalls: `close(2)` on a pipe fd and `kill(2)` on a
         * child are taken as non-blocking. That assumption is load-bearing and is why the
         * watchdog destroys the child BEFORE closing the stream — the kill alone unblocks the
         * reader, so a stalled `close()` would strand only the daemon watchdog, never the
         * caller.
         */
        const val CLEANUP_BUDGET_MS: Long = 2 * REAP_BUDGET_MS + WATCHDOG_JOIN_BUDGET_MS

        /**
         * logcat's own failure diagnostics, which `redirectErrorStream` folds into stdout.
         * Matched only at line start, and only consulted when ZERO own-uid rows parsed — so a
         * stack-trace continuation quoting one of these strings cannot mark a working source
         * as dead.
         */
        private val LOGCAT_DIAGNOSTIC = Regex(
            """^(logcat:\s|Unable to open log device|couldn't get logger list|""" +
                """logcat read failure|read: unexpected length|Failed to (open|connect))""",
            RegexOption.IGNORE_CASE,
        )

        /**
         * The exact argv. `-v uid` adds the uid column the parser filters on; `-v year -v UTC`
         * make the timestamp self-describing (absolute, offset-carrying) instead of `MM-DD` in
         * the device's local zone.
         *
         * Exposed so the connected gate drives the SAME command it asserts about.
         */
        fun command(maxLines: Int = DEFAULT_MAX_LINES): List<String> = listOf(
            "logcat", "-d",
            "-v", "uid",
            "-v", "threadtime",
            "-v", "year",
            "-v", "UTC",
            "-t", maxLines.toString(),
        )
    }
}
