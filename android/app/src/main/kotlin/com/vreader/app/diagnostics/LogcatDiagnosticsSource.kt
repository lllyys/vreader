package com.vreader.app.diagnostics

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.Closeable
import java.io.InputStream
import java.io.InputStreamReader
import java.nio.charset.StandardCharsets
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
 * - **`Unavailable` and `Available(emptyList())` are never conflated.** Exec failure, a
 *   missing binary, a failed read, a non-zero exit, or a timeout is
 *   [SourceResult.Unavailable]; a clean run that simply matched no rows is
 *   `Available(emptyList())`. The composite source and the export header's
 *   `capture source:` line both key off that distinction, so blurring it would let a
 *   denied platform masquerade as a quiet one.
 * - **The timeout is a watchdog that CLOSES the stream**, not a cancellation of a blocking
 *   read. `InputStream.read` ignores coroutine cancellation; closing the stream is the only
 *   thing that unblocks it. The watchdog therefore closes, `destroy()`s, escalates to
 *   `destroyForcibly()` when the child ignored that, and always reaps with `waitFor` — a
 *   bare `destroy()` can leave a `logcat` child, or a reader blocked on its pipe, alive.
 * - **`redirectErrorStream(true)` + a single reader.** Two pipes with one drain deadlocks
 *   as soon as the undrained one fills; folding stderr into stdout removes the second pipe.
 * - **`sinceMillis` is applied in Kotlin, not via logcat's `-t <time>`**, whose time format
 *   is format-sensitive and would make correctness depend on argv parsing we cannot test
 *   off-device.
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

            val stream = try {
                process.inputStream
            } catch (t: Throwable) {
                reap(process, force = true)
                return@withContext SourceResult.Unavailable(
                    "logcat stdout unavailable: ${t.javaClass.simpleName}"
                )
            }

            // The watchdog runs on a DIFFERENT dispatcher on purpose: this coroutine's thread
            // is about to block inside read(), so a same-thread timer could never fire.
            val timedOut = AtomicBoolean(false)
            val watchdog = launch(Dispatchers.Default) {
                delay(processTimeoutMs)
                timedOut.set(true)
                closeQuietly(stream)
                runCatching { process.destroy() }
            }

            var readFailure: Throwable? = null
            val drained = try {
                readBounded(stream)
            } catch (t: Throwable) {
                readFailure = t
                Drained(emptyList(), truncated = false)
            } finally {
                watchdog.cancel()
                closeQuietly(stream)
            }

            if (timedOut.get()) {
                reap(process, force = true)
                return@withContext SourceResult.Unavailable(
                    "logcat timed out after ${processTimeoutMs}ms"
                )
            }
            if (readFailure != null) {
                reap(process, force = true)
                return@withContext SourceResult.Unavailable(
                    "logcat read failed: ${readFailure.javaClass.simpleName}: ${readFailure.message}"
                )
            }

            val exitCode = reap(process, force = drained.truncated)
            if (!drained.truncated && exitCode != 0) {
                return@withContext SourceResult.Unavailable(
                    "logcat exited with ${exitCode ?: "no status"}"
                )
            }

            var entries = LogcatLineParser.parse(drained.lines.asSequence(), ownUid)
            if (sinceMillis != null) entries = entries.filter { it.timeMillis >= sinceMillis }
            val cap = limit.coerceAtLeast(0)
            if (entries.size > cap) entries = entries.takeLast(cap)
            SourceResult.Available(entries)
        }

    /**
     * Retains at most [maxLines] lines / [maxBytes] decoded bytes.
     *
     * `truncated` means we stopped on our own bound rather than at EOF, which is detected by
     * a further line actually existing (that probe line is read and DISCARDED — the bound is
     * on what we retain, i.e. on memory). The caller must not trust the child's exit status
     * on a truncated read, because it is about to be killed mid-write.
     */
    private fun readBounded(stream: InputStream): Drained {
        val lines = ArrayList<String>(minOf(maxLines, INITIAL_CAPACITY))
        var bytes = 0L
        var truncated = false
        BufferedReader(InputStreamReader(stream, StandardCharsets.UTF_8)).use { reader ->
            while (true) {
                val line = reader.readLine() ?: break
                if (lines.size >= maxLines || bytes >= maxBytes) {
                    truncated = true
                    break
                }
                bytes += line.toByteArray(StandardCharsets.UTF_8).size + 1
                lines.add(line)
            }
        }
        return Drained(lines, truncated)
    }

    /**
     * Always leaves the child reaped. Returns its exit status, or `null` when none could be
     * established (forced kill, interrupted wait) — `null` is never treated as success.
     */
    private fun reap(process: Process, force: Boolean): Int? = try {
        if (force) runCatching { process.destroy() }
        if (process.waitFor(REAP_BUDGET_MS, TimeUnit.MILLISECONDS)) {
            process.exitValue()
        } else {
            runCatching { process.destroyForcibly() }
            if (process.waitFor(REAP_BUDGET_MS, TimeUnit.MILLISECONDS)) process.exitValue() else null
        }
    } catch (t: Throwable) {
        runCatching { process.destroyForcibly() }
        null
    }

    private fun closeQuietly(closeable: Closeable) {
        runCatching { closeable.close() }
    }

    private data class Drained(val lines: List<String>, val truncated: Boolean)

    companion object {
        const val DEFAULT_MAX_LINES: Int = 5_000
        const val DEFAULT_MAX_BYTES: Int = 2 * 1024 * 1024
        const val DEFAULT_TIMEOUT_MS: Long = 5_000

        /** How long a reap may take before we escalate to `destroyForcibly`. */
        private const val REAP_BUDGET_MS: Long = 1_000
        private const val INITIAL_CAPACITY: Int = 1_024

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
