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
 * - **The timeout is a watchdog that CLOSES the stream**, not a cancellation of a blocking
 *   read: `InputStream.read` ignores coroutine cancellation, and closing the stream is the
 *   only thing that unblocks it. The watchdog is a short-lived DAEMON THREAD rather than a
 *   coroutine child on purpose — as a structured child, a `close()`/`destroy()` that blocked
 *   would stall `withContext` indefinitely, which is exactly the wedge a diagnostics path
 *   must never cause.
 * - **The child is reaped on every exit path**, including an unexpected throw (outer
 *   `finally`). Cleanup is `destroy()` -> bounded wait -> `destroyForcibly()` -> bounded
 *   wait; an unconfirmed exit yields `null`, and `null` is never treated as success. The
 *   total worst-case wall clock is [processTimeoutMs] + [CLEANUP_BUDGET_MS] — stated here
 *   and asserted by the connected test rather than left vague.
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

        val timedOut = AtomicBoolean(false)
        val finished = CountDownLatch(1)
        val watchdog = Thread({
            if (!finished.await(processTimeoutMs, TimeUnit.MILLISECONDS)) {
                timedOut.set(true)
                closeQuietly(stream)
                runCatching { process.destroy() }
            }
        }, WATCHDOG_THREAD_NAME).apply { isDaemon = true; start() }

        var readFailure: Throwable? = null
        val drained = try {
            readBounded(stream)
        } catch (t: Throwable) {
            readFailure = t
            Drained(emptyList(), truncated = false)
        } finally {
            finished.countDown()
            // Bounded: a watchdog stuck in a blocking close() must not become our problem.
            watchdog.join(WATCHDOG_JOIN_BUDGET_MS)
            closeQuietly(stream)
        }

        reaped.set(true)
        if (timedOut.get()) {
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
        // positive evidence the reader works — but we killed it mid-write, so its exit status
        // is meaningless and is not consulted.
        val exitCode = reap(process, force = drained.truncated)
        if (!drained.truncated && exitCode != 0) {
            return SourceResult.Unavailable("logcat exited with ${exitCode ?: "no status"}")
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
     */
    private fun readBounded(stream: InputStream): Drained {
        val lines = ArrayList<String>(minOf(maxLines, INITIAL_CAPACITY))
        var bytes = 0L
        var truncated = false
        BufferedReader(InputStreamReader(stream, StandardCharsets.UTF_8)).use { reader ->
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

    companion object {
        const val DEFAULT_MAX_LINES: Int = 5_000
        const val DEFAULT_MAX_BYTES: Int = 2 * 1024 * 1024
        const val DEFAULT_TIMEOUT_MS: Long = 5_000

        private const val REAP_BUDGET_MS: Long = 1_000
        private const val WATCHDOG_JOIN_BUDGET_MS: Long = 500
        private const val INITIAL_CAPACITY: Int = 1_024
        private const val WATCHDOG_THREAD_NAME: String = "vreader-diag-logcat-watchdog"

        /**
         * Worst-case cleanup wall clock after the read budget expires: two bounded reap waits
         * plus the watchdog join. Part of the contract so callers (and the connected test) can
         * assert a real upper bound instead of an arbitrary slack.
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
