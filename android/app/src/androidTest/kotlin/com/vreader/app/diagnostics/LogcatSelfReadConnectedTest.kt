package com.vreader.app.diagnostics

import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.nio.charset.StandardCharsets
import java.util.Locale
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlin.coroutines.cancellation.CancellationException

/**
 * Feature #164 WI-1 — **THE FEASIBILITY GATE**, plus the OS-boundary behavior of
 * [LogcatDiagnosticsSource].
 *
 * Why this test decides the whole feature: the plan's supporting evidence (§2) was gathered
 * under `run-as`, whose SELinux domain is `runas_app` and which carries supplementary groups
 * `1007(log)` / `1011(adb)` that a real app process does NOT have. This test is the first
 * observation of the real `untrusted_app` domain — specifically whether it may `execute`
 * `/system/bin/logcat` (a `system_file`) and reach logd's reader socket. If it fails, WI-2…WI-9
 * are not worth building as planned and the plan's §2 go/no-go applies; the answer is NOT to
 * request `READ_LOGS`, add a `su`/shell path, or relax this test.
 *
 * Discipline notes baked into the assertions:
 * - **No vacuous pass.** "every returned entry has our uid" is trivially true of an empty
 *   list — the exact outcome the gate exists to detect. The gate therefore asserts that the
 *   nonce was FOUND, and separately proves the uid filter is live via a negative control
 *   (the same raw bytes parsed against a foreign uid must NOT contain the nonce).
 * - **Not timing-flaky.** `Log` -> logd -> reader is asynchronous, so the read POLLS to a
 *   5 s budget rather than reading once (#125/#133 flake precedent).
 * - **No shell indirection.** Everything here runs in the instrumented app process; no
 *   `run-as`, no `adb`, no `su`.
 *
 * Known limitation, recorded rather than hidden: an instrumented process is `debuggable`.
 * Parity on a NON-debuggable build is WI-9's acceptance item, not this one's.
 */
@RunWith(AndroidJUnit4::class)
class LogcatSelfReadConnectedTest {

    private companion object {
        const val GATE_TAG = "VRDIAG164"
        const val POLL_BUDGET_MS = 5_000L
        const val POLL_INTERVAL_MS = 150L
        const val RAW_READ_BUDGET_MS = 5_000L
        /** Scheduling slack on top of the source's OWN stated worst case. */
        const val SCHEDULING_SLACK_MS = 1_500L
        val WELL_FORMED_MARKER = Regex("^«v\\d+»")
    }

    // ------------------------------------------------------------ THE GATE

    @Test
    fun feasibilityGate_appProcessReadsBackItsOwnLogcatLine() = runBlocking {
        val ownUid = android.os.Process.myUid()
        val nonce = "VRDIAG164-NONCE-${UUID.randomUUID()}"
        val sequenceId = 164L

        // Written IN THIS PROCESS, with a unique nonce, so a stale buffer entry from an
        // earlier run cannot produce a false PASS.
        Log.w(GATE_TAG, "${VLogMarker.encode(sequenceId)}$nonce")

        val source = LogcatDiagnosticsSource(ownUid = ownUid)
        var polls = 0
        var found: DiagnosticsLogEntry? = null
        var last: SourceResult? = null
        val deadline = System.nanoTime() + POLL_BUDGET_MS * 1_000_000
        while (System.nanoTime() < deadline) {
            polls++
            val result = source.recentEntries(limit = LogcatDiagnosticsSource.DEFAULT_MAX_LINES)
            last = result
            if (result is SourceResult.Available) {
                found = result.entries.firstOrNull { it.message.contains(nonce) }
                if (found != null) break
            }
            delay(POLL_INTERVAL_MS)
        }

        // --- raw observation: what the platform actually handed this process ---
        val raw = readRawLogcatInThisProcess()
        val rawNonceLine = raw.firstOrNull { it.contains(nonce) }
        val uidToken = rawNonceLine?.let { uidTokenOf(it) }
        val rendering = when {
            uidToken == null -> "unobserved"
            uidToken.toIntOrNull() != null -> "numeric"
            Regex("^u\\d+_a\\d+$").matches(uidToken) -> "symbolic"
            else -> "other"
        }
        val verdict = if (found != null) "PASS" else "FAIL"
        Log.w(
            GATE_TAG,
            "GATE-SUMMARY verdict=$verdict ownUid=$ownUid uidToken=$uidToken " +
                "rendering=$rendering polls=$polls rawLines=${raw.size} " +
                "lastResult=${last?.javaClass?.simpleName} " +
                "reason=${(last as? SourceResult.Unavailable)?.reason}"
        )

        // --- the gate itself ---
        assertTrue(
            "FEASIBILITY GATE FAILED — the source never became Available. last=$last. " +
                "This is the untrusted_app SELinux question the plan's §2 left open; " +
                "escalate on the §2 go/no-go rather than working around it.",
            last is SourceResult.Available,
        )
        assertNotNull(
            "FEASIBILITY GATE FAILED — logcat was readable but this process could not read " +
                "back its OWN line within ${POLL_BUDGET_MS}ms over $polls polls " +
                "(rawLinesSeen=${raw.size}, nonceVisibleInRawDump=${rawNonceLine != null}). " +
                "Escalate on the plan's §2 go/no-go.",
            found,
        )

        // The marker contract, end-to-end through the real platform:
        val entry = found!!
        assertEquals("the marker must be lifted into sequenceId", sequenceId, entry.sequenceId)
        assertEquals("the marker must be stripped from the message", nonce, entry.message)
        assertEquals(GATE_TAG, entry.category)
        assertEquals(DiagnosticsLevel.WARN, entry.level)

        // NEGATIVE CONTROL — proves the uid filter is genuinely applied rather than the row
        // merely surviving because the parser ignores the uid column. If this fails, the
        // "all entries carry our uid" property is vacuous.
        val foreign = LogcatLineParser.parse(raw.asSequence(), ownUid = ownUid + 1)
        assertTrue(
            "uid filtering is not live — our line survived a parse against a foreign uid",
            foreign.none { it.message.contains(nonce) },
        )

        // The device's OWN uid rendering must be one the parser accepts. Synthesised from the
        // token this device actually printed, so a device that prints `u0_a209` cannot pass by
        // accident on a numeric-only parser.
        assertNotNull(
            "the nonce line was not present in the raw dump — cannot confirm uid rendering",
            uidToken,
        )
        val synthetic = "2026-08-04 19:26:12.114 +0000  $uidToken  1  1 W $GATE_TAG: probe"
        assertEquals(
            "the parser must accept this device's uid rendering ($rendering: $uidToken)",
            1,
            LogcatLineParser.parse(sequenceOf(synthetic), ownUid).size,
        )

        // No entry that reaches the store may still carry a marker.
        val available = (last as SourceResult.Available).entries
        assertTrue(
            "a marker leaked through to the store",
            available.none { WELL_FORMED_MARKER.containsMatchIn(it.message) },
        )
    }

    // ------------------------------------------- Unavailable vs Available(empty)

    @Test
    fun missingBinary_reportsUnavailable_neverAvailable() = runBlocking {
        val source = LogcatDiagnosticsSource(
            ownUid = 10_209,
            exec = { ProcessBuilder(listOf("/system/bin/vrdiag-no-such-binary")).start() },
        )
        val result = source.recentEntries(limit = 100)
        assertTrue("a missing binary must be Unavailable, was $result", result is SourceResult.Unavailable)
    }

    @Test
    fun execThrowing_reportsUnavailable() = runBlocking {
        val source = LogcatDiagnosticsSource(
            ownUid = 10_209,
            exec = { throw IOException("denied") },
        )
        assertTrue(source.recentEntries(limit = 10) is SourceResult.Unavailable)
    }

    @Test
    fun nonZeroExit_reportsUnavailable_evenWithParsableOutput() = runBlocking {
        val stdout = "logcat: Unable to open log device: Permission denied\n" + ownLine("denied")
        val source = fakeSource(stdout, exitCode = 1)
        val result = source.recentEntries(limit = 100)
        assertTrue(
            "a failed logcat must not masquerade as a quiet one, was $result",
            result is SourceResult.Unavailable,
        )
    }

    @Test
    fun cleanRunWithNoMatchingRows_reportsAvailableEmpty() = runBlocking {
        val stdout = buildString {
            append("--------- beginning of main\n")
            append(foreignLine("not ours"))
            append(foreignLine("also not ours"))
        }
        val result = fakeSource(stdout, exitCode = 0).recentEntries(limit = 100)
        assertEquals(
            "a clean run with no matching rows is Available(empty), never Unavailable",
            SourceResult.Available(emptyList<DiagnosticsLogEntry>()),
            result,
        )
    }

    @Test
    fun cleanRunWithMatchingRows_reportsAvailableEntries() = runBlocking {
        val result = fakeSource(ownLine("hello"), exitCode = 0).recentEntries(limit = 100)
        result as SourceResult.Available
        assertEquals(listOf("hello"), result.entries.map { it.message })
    }

    @Test
    fun deniedLogcatThatStillExitsZero_reportsUnavailable() = runBlocking {
        // The hole an exit-code-only classifier leaves wide open: redirectErrorStream folds
        // logcat's own diagnostics into stdout, so a denial that exits 0 would be read as a
        // quiet buffer and would silently degrade the whole feature with NO error.
        listOf(
            "logcat: Unable to open log device '/dev/log/main': Permission denied",
            "Unable to open log device '/dev/log/main': Permission denied",
            "couldn't get logger list",
            "logcat read failure",
        ).forEach { diagnostic ->
            val result = fakeSource("$diagnostic\n", exitCode = 0).recentEntries(limit = 100)
            assertTrue(
                "a zero-exit denial must be Unavailable, was $result for: $diagnostic",
                result is SourceResult.Unavailable,
            )
        }
    }

    @Test
    fun aDiagnosticAlongsideOurOwnRowsStillCountsAsAvailable() = runBlocking {
        // Parsing even one of our own rows is positive proof the reader worked, so a stray
        // diagnostic line must not flip a working source to dead.
        val stdout = "logcat: something noisy\n" + ownLine("hello")
        val result = fakeSource(stdout, exitCode = 0).recentEntries(limit = 100)
        result as SourceResult.Available
        assertEquals(listOf("hello"), result.entries.map { it.message })
    }

    @Test
    fun truncatedReadWithOnlyForeignRows_reportsAvailableEmpty() = runBlocking {
        // A truncated read means logcat produced MORE than we asked for — positive evidence
        // the reader works — so "none of it was ours" is genuinely Available(empty), not a
        // denial. Its exit status is meaningless because we killed it mid-write.
        val stdout = (1..500).joinToString("") { foreignLine("theirs-$it") }
        val result = fakeSource(stdout, exitCode = 0, maxLines = 10).recentEntries(limit = 100)
        assertEquals(SourceResult.Available(emptyList<DiagnosticsLogEntry>()), result)
    }

    // ----------------------------------------------------- timeout / reap path

    @Test
    fun timeout_closesStream_escalatesToDestroyForcibly_reapsAndLeavesNoReader() = runBlocking {
        val stream = BlockingInputStream()
        val process = FakeProcess(stream, exitCode = 143, aliveUntilKilled = true, ignoreDestroy = true)
        val timeoutMs = 700L
        val source = LogcatDiagnosticsSource(
            ownUid = 10_209,
            processTimeoutMs = timeoutMs,
            exec = { process },
        )

        val startedAt = System.nanoTime()
        val result = source.recentEntries(limit = 100)
        val elapsedMs = (System.nanoTime() - startedAt) / 1_000_000

        assertTrue("a timeout must be Unavailable, was $result", result is SourceResult.Unavailable)
        // Asserted against the source's OWN stated worst case, not an arbitrary slack.
        val bound = timeoutMs + LogcatDiagnosticsSource.CLEANUP_BUDGET_MS + SCHEDULING_SLACK_MS
        assertTrue(
            "the call must return within its stated bound even when the child ignores " +
                "destroy() (elapsed=${elapsedMs}ms, bound=${bound}ms)",
            elapsedMs <= bound,
        )
        assertTrue("the stream must be closed to unblock the reader", stream.closed.get())
        assertTrue("destroy() must be attempted", process.destroyCalls.get() >= 1)
        assertTrue(
            "destroyForcibly() must be invoked when the child ignored destroy()",
            process.destroyForciblyCalls.get() >= 1,
        )
        assertTrue("the child must always be reaped", process.waitForCalls.get() >= 1)
        assertEquals(
            "no reader may be left blocked on the child's pipe",
            0,
            stream.blockedReaders.get(),
        )
    }

    @Test
    fun aChildThatIgnoresEvenDestroyForcibly_stillReturnsWithinTheStatedBound() = runBlocking {
        // destroyForcibly() is asynchronous — invoking it is not proof the child died. A
        // bounded API must report the unconfirmed reap rather than block forever waiting.
        val stream = BlockingInputStream()
        val process = FakeProcess(
            stream,
            exitCode = 143,
            aliveUntilKilled = true,
            ignoreDestroy = true,
            ignoreDestroyForcibly = true,
        )
        val timeoutMs = 500L
        val source = LogcatDiagnosticsSource(
            ownUid = 10_209,
            processTimeoutMs = timeoutMs,
            exec = { process },
        )

        val startedAt = System.nanoTime()
        val result = source.recentEntries(limit = 100)
        val elapsedMs = (System.nanoTime() - startedAt) / 1_000_000

        assertTrue("an unreapable child must be Unavailable, was $result", result is SourceResult.Unavailable)
        val bound = timeoutMs + LogcatDiagnosticsSource.CLEANUP_BUDGET_MS + SCHEDULING_SLACK_MS
        assertTrue(
            "the call must not block on an unreapable child (elapsed=${elapsedMs}ms, bound=${bound}ms)",
            elapsedMs <= bound,
        )
        assertTrue("destroyForcibly() must still be attempted", process.destroyForciblyCalls.get() >= 1)
        assertEquals("no reader may be left blocked", 0, stream.blockedReaders.get())
    }

    @Test
    fun aStalledCloseCannotWedgeTheCaller_becauseTheKillUnblocksTheReader() = runBlocking {
        // The watchdog destroys the child BEFORE closing the stream precisely so there are two
        // independent ways to unblock the reader. Here close() hangs forever; only the kill
        // can free us, so this test fails if the ordering is ever reversed.
        val stream = KillUnblockedInputStream()
        val process = FakeProcess(
            stream,
            exitCode = 143,
            aliveUntilKilled = true,
            onDestroy = { stream.releaseAsIfWriterDied() },
        )
        val timeoutMs = 500L
        val source = LogcatDiagnosticsSource(
            ownUid = 10_209,
            processTimeoutMs = timeoutMs,
            exec = { process },
        )

        val startedAt = System.nanoTime()
        val result = source.recentEntries(limit = 100)
        val elapsedMs = (System.nanoTime() - startedAt) / 1_000_000

        assertTrue("a timeout must be Unavailable, was $result", result is SourceResult.Unavailable)
        val bound = timeoutMs + LogcatDiagnosticsSource.CLEANUP_BUDGET_MS + SCHEDULING_SLACK_MS
        assertTrue(
            "a stalled close() must not wedge the caller (elapsed=${elapsedMs}ms, bound=${bound}ms)",
            elapsedMs <= bound,
        )
        assertEquals("no reader may be left blocked", 0, stream.blockedReaders.get())
    }

    @Test
    fun cancellationPropagatesRatherThanBecomingUnavailable() = runBlocking {
        // "Never throws" means never throws a SOURCE FAILURE. Cancelling the caller is not a
        // source failure, and swallowing it into Unavailable would hide a cancelled scope.
        val fromExec = LogcatDiagnosticsSource(
            ownUid = 10_209,
            exec = { throw CancellationException("cancelled during exec") },
        )
        var thrown: Throwable? = null
        try {
            fromExec.recentEntries(limit = 10)
        } catch (t: Throwable) {
            thrown = t
        }
        assertTrue("cancellation from exec must propagate, got $thrown", thrown is CancellationException)

        val fromStream = LogcatDiagnosticsSource(
            ownUid = 10_209,
            exec = { CancellingStreamProcess() },
        )
        thrown = null
        try {
            fromStream.recentEntries(limit = 10)
        } catch (t: Throwable) {
            thrown = t
        }
        assertTrue(
            "cancellation from getInputStream must propagate, got $thrown",
            thrown is CancellationException,
        )
    }

    @Test
    fun anUnexpectedFailureStillReapsTheChild() = runBlocking {
        // The outer finally is the belt-and-braces guarantee: even a throw from inside the
        // read path may not leave a logcat child behind.
        val process = FakeProcess(
            ThrowingInputStream(),
            exitCode = 0,
            aliveUntilKilled = true,
        )
        val result = LogcatDiagnosticsSource(ownUid = 10_209, exec = { process })
            .recentEntries(limit = 10)
        assertTrue("a read failure must be Unavailable, was $result", result is SourceResult.Unavailable)
        assertTrue("the child must be reaped", process.waitForCalls.get() >= 1)
        assertTrue("the child must not be left alive", !process.isAlive)
    }

    // --------------------------------------------------------- bounds + limit

    @Test
    fun neverRetainsMoreThanMaxLines() = runBlocking {
        val stdout = (1..500).joinToString("") { ownLine("line-$it") }
        val result = fakeSource(stdout, exitCode = 0, maxLines = 10).recentEntries(limit = 10_000)
        result as SourceResult.Available
        assertTrue("retained ${result.entries.size} entries for maxLines=10", result.entries.size <= 10)
    }

    @Test
    fun neverRetainsMoreThanMaxBytesOfRawInput() = runBlocking {
        // Accounted on the RAW retained line, not on the parsed message: a message-only sum
        // excludes the timestamp/uid/pid/tid/tag columns and so could not detect an overrun.
        val raw = ownLine("x".repeat(200))
        val rawLineBytes = raw.toByteArray(StandardCharsets.UTF_8).size
        val stdout = raw.repeat(500)
        val maxBytes = 4_096
        val result = fakeSource(stdout, exitCode = 0, maxBytes = maxBytes).recentEntries(limit = 10_000)
        result as SourceResult.Available
        val retained = result.entries.size * rawLineBytes
        assertTrue(
            "retained $retained raw bytes (${result.entries.size} lines x $rawLineBytes) for maxBytes=$maxBytes",
            retained <= maxBytes,
        )
        assertTrue("a bounded read is still a successful read", result.entries.isNotEmpty())
    }

    @Test
    fun aSingleLineLargerThanTheWholeBudgetIsNotRetained() = runBlocking {
        // The bound is HARD: the line that would cross it is not retained at all, so one
        // oversized line cannot blow past maxBytes.
        val result = fakeSource(ownLine("hello"), exitCode = 0, maxBytes = 10).recentEntries(limit = 100)
        assertEquals(SourceResult.Available(emptyList<DiagnosticsLogEntry>()), result)
    }

    @Test
    fun limitKeepsTheNewestEntries() = runBlocking {
        val stdout = (1..20).joinToString("") { ownLine("line-$it", millis = 12 + it) }
        val result = fakeSource(stdout, exitCode = 0).recentEntries(limit = 3)
        result as SourceResult.Available
        assertEquals(listOf("line-18", "line-19", "line-20"), result.entries.map { it.message })
    }

    @Test
    fun sinceMillisFiltersOlderEntries() = runBlocking {
        val stdout = (1..5).joinToString("") { ownLine("line-$it", millis = 100 + it) }
        val all = fakeSource(stdout, exitCode = 0).recentEntries(limit = 100)
        all as SourceResult.Available
        val cutoff = all.entries[2].timeMillis
        val since = fakeSource(stdout, exitCode = 0).recentEntries(sinceMillis = cutoff, limit = 100)
        since as SourceResult.Available
        assertEquals(listOf("line-3", "line-4", "line-5"), since.entries.map { it.message })
    }

    @Test
    fun zeroLimitYieldsNoEntriesWithoutFailing() = runBlocking {
        val result = fakeSource(ownLine("hello"), exitCode = 0).recentEntries(limit = 0)
        assertEquals(SourceResult.Available(emptyList<DiagnosticsLogEntry>()), result)
    }

    // ------------------------------------------------------------- dispatcher

    @Test
    fun runsEntirelyOnTheInjectedIoDispatcher() = runBlocking {
        val executor = Executors.newSingleThreadExecutor { r ->
            Thread(r, "vrdiag-io-probe").apply { isDaemon = true }
        }
        try {
            val dispatcher = executor.asCoroutineDispatcher()
            val execThread = arrayOfNulls<String>(1)
            val readThread = arrayOfNulls<String>(1)
            val stream = ThreadRecordingInputStream(ownLine("hello").toByteArray(), readThread)
            val source = LogcatDiagnosticsSource(
                ownUid = 10_209,
                ioDispatcher = dispatcher,
                exec = {
                    execThread[0] = Thread.currentThread().name
                    FakeProcess(stream, exitCode = 0, aliveUntilKilled = false)
                },
            )
            val result = source.recentEntries(limit = 10)
            assertTrue(result is SourceResult.Available)
            assertEquals("exec must run on the injected dispatcher", "vrdiag-io-probe", execThread[0])
            assertEquals("the blocking read must run on the injected dispatcher", "vrdiag-io-probe", readThread[0])
        } finally {
            executor.shutdownNow()
        }
    }

    // ----------------------------------------------------------------- helpers

    private fun fakeSource(
        stdout: String,
        exitCode: Int,
        maxLines: Int = LogcatDiagnosticsSource.DEFAULT_MAX_LINES,
        maxBytes: Int = LogcatDiagnosticsSource.DEFAULT_MAX_BYTES,
    ) = LogcatDiagnosticsSource(
        ownUid = 10_209,
        maxLines = maxLines,
        maxBytes = maxBytes,
        exec = {
            FakeProcess(
                ByteArrayInputStream(stdout.toByteArray(StandardCharsets.UTF_8)),
                exitCode = exitCode,
                aliveUntilKilled = false,
            )
        },
    )

    private fun ownLine(message: String, millis: Int = 114) = String.format(
        Locale.ROOT,
        "2026-08-04 19:26:%02d.%03d +0000  10209  3312  3312 W Probe: %s\n",
        millis / 1000 % 60,
        millis % 1000,
        message,
    )

    private fun foreignLine(message: String) =
        "2026-08-04 19:26:12.114 +0000  1000  572  718 W System: $message\n"

    /**
     * Runs the SAME argv the source runs, in this process, and returns raw stdout lines.
     *
     * The read is BOUNDED by its own watchdog. An unbounded `readLines()` followed by a timed
     * `waitFor` is not a timeout at all: if the pipe stalls, the wait is never reached and the
     * nominal 5 s gate hangs forever after the real source has already answered.
     */
    private fun readRawLogcatInThisProcess(): List<String> {
        val process = try {
            ProcessBuilder(LogcatDiagnosticsSource.command()).redirectErrorStream(true).start()
        } catch (t: Throwable) {
            return emptyList()
        }
        return try {
            val stream = process.inputStream
            val finished = CountDownLatch(1)
            val watchdog = Thread({
                if (!finished.await(RAW_READ_BUDGET_MS, TimeUnit.MILLISECONDS)) {
                    // Kill FIRST: that closes the pipe's far end and unblocks readLines() even
                    // if our own close() were to stall. A close-then-kill watchdog can never
                    // reach the kill, which is not a timeout at all.
                    runCatching { process.destroyForcibly() }
                    runCatching { stream.close() }
                }
            }).apply { isDaemon = true; start() }
            try {
                stream.bufferedReader(StandardCharsets.UTF_8).use { it.readLines() }
            } catch (t: Throwable) {
                emptyList()
            } finally {
                finished.countDown()
                runCatching { watchdog.join(500) }
            }
        } catch (t: Throwable) {
            emptyList()
        } finally {
            // Outer finally: the child is reaped however we leave, including on a throw.
            runCatching { process.destroyForcibly() }
            runCatching { process.waitFor(2, TimeUnit.SECONDS) }
        }
    }

    /** The 4th whitespace-delimited column of a `-v uid -v threadtime -v year` line. */
    private fun uidTokenOf(line: String): String? =
        line.trim().split(Regex("\\s+")).getOrNull(3)

    // ------------------------------------------------------------ test doubles

    private class FakeProcess(
        private val stdout: InputStream,
        private val exitCode: Int,
        aliveUntilKilled: Boolean,
        private val ignoreDestroy: Boolean = false,
        private val ignoreDestroyForcibly: Boolean = false,
        private val onDestroy: () -> Unit = {},
    ) : Process() {
        val destroyCalls = AtomicInteger()
        val destroyForciblyCalls = AtomicInteger()
        val waitForCalls = AtomicInteger()
        private val dead = CountDownLatch(if (aliveUntilKilled) 1 else 0)

        override fun getOutputStream(): OutputStream = ByteArrayOutputStream()
        override fun getInputStream(): InputStream = stdout
        override fun getErrorStream(): InputStream = ByteArrayInputStream(ByteArray(0))

        override fun waitFor(): Int {
            waitForCalls.incrementAndGet()
            dead.await(30, TimeUnit.SECONDS)
            return exitCode
        }

        override fun waitFor(timeout: Long, unit: TimeUnit): Boolean {
            waitForCalls.incrementAndGet()
            return dead.await(timeout, unit)
        }

        override fun exitValue(): Int {
            if (dead.count > 0L) throw IllegalThreadStateException("still running")
            return exitCode
        }

        /** Deliberately a no-op when [ignoreDestroy] — the child that forces the escalation. */
        override fun destroy() {
            destroyCalls.incrementAndGet()
            onDestroy()
            if (!ignoreDestroy) dead.countDown()
        }

        /** Deliberately a no-op when [ignoreDestroyForcibly] — the unreapable child. */
        override fun destroyForcibly(): Process {
            destroyForciblyCalls.incrementAndGet()
            if (!ignoreDestroyForcibly) dead.countDown()
            return this
        }

        override fun isAlive(): Boolean = dead.count > 0L
    }

    /** Blocks every read until closed — the shape a wedged `logcat` child presents. */
    private class BlockingInputStream : InputStream() {
        val closed = AtomicBoolean(false)
        val blockedReaders = AtomicInteger()
        private val gate = CountDownLatch(1)

        override fun read(): Int {
            blockedReaders.incrementAndGet()
            try {
                gate.await(30, TimeUnit.SECONDS)
            } finally {
                blockedReaders.decrementAndGet()
            }
            if (closed.get()) throw IOException("stream closed")
            return -1
        }

        override fun close() {
            closed.set(true)
            gate.countDown()
        }
    }

    /**
     * A reader that ONLY the child's death can unblock: `close()` hangs forever, exactly the
     * pathological case the destroy-before-close ordering exists to survive.
     */
    private class KillUnblockedInputStream : InputStream() {
        val blockedReaders = AtomicInteger()
        private val writerDied = CountDownLatch(1)

        fun releaseAsIfWriterDied() = writerDied.countDown()

        override fun read(): Int {
            blockedReaders.incrementAndGet()
            try {
                writerDied.await(30, TimeUnit.SECONDS)
            } finally {
                blockedReaders.decrementAndGet()
            }
            return -1 // the writer is gone: EOF, exactly as a killed child's pipe behaves
        }

        override fun close() {
            // Never returns — a close() that cannot rescue the reader.
            CountDownLatch(1).await(30, TimeUnit.SECONDS)
        }
    }

    /** Cancels at stream acquisition — the second of the two swallow-cancellation sites. */
    private class CancellingStreamProcess : Process() {
        override fun getOutputStream(): OutputStream = ByteArrayOutputStream()
        override fun getInputStream(): InputStream = throw CancellationException("cancelled")
        override fun getErrorStream(): InputStream = ByteArrayInputStream(ByteArray(0))
        override fun waitFor(): Int = 0
        override fun waitFor(timeout: Long, unit: TimeUnit): Boolean = true
        override fun exitValue(): Int = 0
        override fun destroy() = Unit
        override fun isAlive(): Boolean = false
    }

    /** Fails the read outright — the "unexpected failure" path the outer finally must survive. */
    private class ThrowingInputStream : InputStream() {
        override fun read(): Int = throw IOException("pipe exploded")
    }

    private class ThreadRecordingInputStream(
        bytes: ByteArray,
        private val sink: Array<String?>,
    ) : InputStream() {
        private val delegate = ByteArrayInputStream(bytes)
        override fun read(): Int {
            if (sink[0] == null) sink[0] = Thread.currentThread().name
            return delegate.read()
        }
    }
}
