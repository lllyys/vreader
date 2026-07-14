package com.vreader.app.reader

import android.os.Debug
import android.os.SystemClock
import android.util.Log
import androidx.compose.material3.LocalTextStyle
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFontFamilyResolver
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.reader.paged.ComposeLineMeasurer
import com.vreader.app.reader.paged.LineMeasurer
import com.vreader.app.reader.paged.PageContentBox
import com.vreader.app.reader.paged.PaginationToken
import com.vreader.app.reader.paged.TxtPageIndex
import com.vreader.app.reader.settings.ReaderSettings
import com.vreader.app.reader.settings.bodyTextStyle
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * Feature #137 WI-11 (final acceptance) — the 14 MB CJK phase-1 pagination perf benchmark.
 *
 * Measures + REPORTS the two numbers the plan (§Pagination-strategy "Perf bound", §Risks-3/5) calls
 * for on the real 14 MB CJK book: the open→first-page (phase-1 `TxtPaginator.index`) wall-clock latency
 * (median of 3 runs via `SystemClock.elapsedRealtime`) and the peak memory during phase-1
 * (`Debug.MemoryInfo` PSS + the `Runtime` used-heap delta around the run). The numbers are LOGGED (tag
 * `WI11-PERF`) so the Gate-5b evidence file can cite them verbatim.
 *
 * The assertions are deliberately NON-BLOCKING sanity bounds only (completes without OOM/crash, under a
 * GENEROUS ceiling): the plan pre-authorizes RECORDING the numbers, and a high latency is a DOCUMENTED
 * windowed-measurement follow-up — NOT a test failure. So this does not gate on a tight threshold; it
 * proves phase-1 terminates on a real 14 MB CJK doc and yields a real multi-thousand-page index, then
 * publishes the measurements.
 *
 * Real-book-first (AGENTS.md): reads the real `test-books/books/txt/黑暗血时代.txt` (14 059 220 bytes)
 * pushed to the app-owned scoped-storage dir `getExternalFilesDir(null)/perf-cjk.txt` (readable by the
 * app UID with no runtime permission on API 35). If that file is genuinely absent/unreadable, it falls
 * back to a DETERMINISTIC synthetic ~14 MB CJK corpus (a repeated real-CJK paragraph, NOT random) and
 * the log line records `book=synthetic`. Which path ran is asserted + logged.
 *
 * Phase-1 is driven with the EXACT production shaping inputs (TxtReaderBody:169-184): a real
 * `ComposeLineMeasurer(TextMeasurer(resolver, density, direction))` captured from a live composition,
 * `LocalTextStyle.current.merge(bodyTextStyle())`, and a chrome-aware `PageContentBox` (the device
 * screen minus the #129 default margins) — so the measured latency reflects the real measure pass, not
 * a toy one. Run ONE class per connected invocation (MEMORY #129/#133).
 */
@RunWith(AndroidJUnit4::class)
class TxtPaginatorPerfBenchmark {

    @get:Rule val compose = createComposeRule()

    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()

    private companion object {
        const val TAG = "WI11-PERF"
        // Generous, non-flaky ceiling: phase-1 measures the whole 14 MB doc ONCE off-main. This proves it
        // TERMINATES (no infinite loop / OOM), NOT a tight latency SLA — the plan (§Perf-bound, §Risks-5)
        // pre-authorizes RECORDING the real number and filing a windowed-measurement follow-up if it is high,
        // and explicitly says do NOT hard-fail on a tight latency threshold. The REAL 14MB CJK book measured
        // ~85 s/run on this emulator (vs ~1.2 s synthetic), so the ceiling is set well above that (180 s) to
        // prove termination WITHOUT hard-failing the recorded real number — exactly the plan's intent.
        const val MAX_RUN_MS = 180_000L
        const val RUNS = 3
        // A real target char count for the synthetic fallback so it exercises the same scale as the real book
        // (CJK ≈ 3 bytes/char UTF-8; ~4.7M CJK chars ≈ 14 MB UTF-8, comparable to the real book's byte size).
        const val SYNTHETIC_TARGET_CHARS = 4_700_000
        // The real book's exact byte size — used to VALIDATE that a pushed perf-cjk.txt is the genuine book
        // (not a truncated/stale/unrelated file that would produce false "real-book" evidence; Gate-4 M3).
        const val REAL_BOOK_BYTES = 14_059_220L
        const val REAL_BOOK_BYTES_TOLERANCE = 1_000L   // decode is byte-exact; allow a tiny margin only.
    }

    /** Read the real 14 MB CJK book from the app's scoped external files dir; null if absent OR if the file's
     *  byte size is not the genuine book (Gate-4 M3 — never label a truncated/unrelated file as `real`). */
    private fun readRealBookOrNull(): String? {
        val dir = instrumentation.targetContext.getExternalFilesDir(null) ?: return null
        val f = File(dir, "perf-cjk.txt")
        if (!f.exists() || !f.canRead()) return null
        // Identity check: the pushed file must be the exact real book (14,059,220 bytes ± tiny margin), else
        // fall through to the deterministic synthetic — a 1.1MB truncated file must NOT be logged as `real`.
        if (kotlin.math.abs(f.length() - REAL_BOOK_BYTES) > REAL_BOOK_BYTES_TOLERANCE) {
            Log.w(TAG, "perf-cjk.txt size ${f.length()} != expected $REAL_BOOK_BYTES → treating as NOT the real book")
            return null
        }
        return try {
            TxtDecoder.decode(f).text
        } catch (t: Throwable) {
            Log.w(TAG, "real book decode failed, falling back to synthetic", t)
            null
        }
    }

    /** A DETERMINISTIC ~14 MB CJK corpus (a repeated real-Chinese paragraph, not random) for the fallback. */
    private fun syntheticCjk(): String {
        // A representative CJK paragraph with full-width punctuation + a line break (chunk boundary).
        val para = "黑暗血时代的黎明降临，末世的钟声在城市上空回荡。幸存者们在废墟中挣扎，" +
            "寻找着微弱的希望之光。异变的生物在阴影里游荡，每一次呼吸都可能是最后一次。\n"
        val sb = StringBuilder(SYNTHETIC_TARGET_CHARS + para.length)
        while (sb.length < SYNTHETIC_TARGET_CHARS) sb.append(para)
        return sb.toString()
    }

    @Test
    fun phase1_index_14mbCjk_latencyAndMemory_recorded() {
        // --- source: real book first, synthetic fallback (documented) ---
        val real = readRealBookOrNull()
        val usedReal = real != null
        val text = real ?: syntheticCjk()
        val byteCountUtf8 = text.toByteArray(Charsets.UTF_8).size
        val document = TxtDocument.of(text)
        assertTrue("the corpus must be non-trivial (>1M chars)", text.length > 1_000_000)
        assertTrue("the document must have chunks", document.chunkCount > 0)

        // --- production shaping inputs captured from a live composition ---
        var measurer: LineMeasurer? = null
        var style: TextStyle? = null
        var contentBox: PageContentBox? = null
        val defaults = ReaderSettings()   // #129 defaults (18sp / 1.5 / 20dp margin)
        compose.setContent {
            val density = LocalDensity.current
            val fontResolver = LocalFontFamilyResolver.current
            val layoutDirection = LocalLayoutDirection.current
            // EXACT production style: the Material LocalTextStyle merged with the #129 bodyTextStyle
            // (TxtReaderBody:178) so measured line breaks match what the page would render.
            val effective = LocalTextStyle.current.merge(defaults.bodyTextStyle())
            // A chrome-aware content box: the device screen minus the #129 default margins (horizontal
            // = marginDp on each side; vertical = 16dp top+bottom — TxtReaderBody:221-222/273-274).
            val cfg = androidx.compose.ui.platform.LocalConfiguration.current
            val screenWpx = with(density) { cfg.screenWidthDp.dp.toPx() }
            val screenHpx = with(density) { cfg.screenHeightDp.dp.toPx() }
            val marginPx = with(density) { defaults.marginDp.dp.toPx() }
            val vPadPx = with(density) { 16.dp.toPx() }
            measurer = ComposeLineMeasurer(TextMeasurer(fontResolver, density, layoutDirection))
            style = effective
            contentBox = PageContentBox(
                widthPx = (screenWpx - 2 * marginPx).coerceAtLeast(1f),
                heightPx = (screenHpx - 2 * vPadPx).coerceAtLeast(1f),
            )
        }
        compose.waitUntil(10_000) { measurer != null && style != null && contentBox != null }
        val m = measurer!!
        val st = style!!
        val box = contentBox!!
        assertFalse("content box must not be degenerate on a real screen", box.isDegenerate)

        // --- warm run (JIT / class-load / TextMeasurer cache) — not counted in the median ---
        val warmIndex = runIndex(document, st, box, m)
        assertTrue("phase-1 must yield a multi-page index (>1 page) on a 14MB doc", warmIndex.pageCount > 1)

        // --- measured runs: median latency + PEAK memory sampled DURING each pass (Gate-4 High-1) ---
        // A background sampler polls used-heap + PSS every ~20ms WHILE index() runs, so the reported peak is
        // the true in-pass peak (temporary allocations that peak-and-reclaim during pagination are captured),
        // not a post-return retained-heap snapshot.
        val runtime = Runtime.getRuntime()
        val samples = LongArray(RUNS)
        var peakUsedHeapBytes = 0L
        var peakPssKb = 0
        var pageCount = 0
        for (i in 0 until RUNS) {
            System.gc()
            Thread.sleep(50)   // let GC settle before the used-heap baseline (not a sync primitive)
            val baseUsed = runtime.totalMemory() - runtime.freeMemory()
            val sampler = MemorySampler(runtime, baseUsed)
            val samplerThread = Thread(sampler, "wi11-perf-sampler-$i").apply { isDaemon = true; start() }
            val t0 = SystemClock.elapsedRealtime()
            val idx = runIndex(document, st, box, m)
            val elapsed = SystemClock.elapsedRealtime() - t0
            sampler.stop()
            samplerThread.join(2_000)

            samples[i] = elapsed
            peakUsedHeapBytes = maxOf(peakUsedHeapBytes, sampler.peakUsedDeltaBytes)
            peakPssKb = maxOf(peakPssKb, sampler.peakPssKb)
            pageCount = idx.pageCount
            assertTrue("run $i must finish under the generous ceiling ($elapsed ms)", elapsed < MAX_RUN_MS)
            Log.i(
                TAG,
                "run=$i latency_ms=$elapsed peakUsedHeapDelta_mb=${sampler.peakUsedDeltaBytes / 1_048_576} " +
                    "peakPss_mb=${sampler.peakPssKb / 1024} samples=${sampler.sampleCount} pages=${idx.pageCount}",
            )
        }
        samples.sort()
        val medianMs = samples[RUNS / 2]
        val peakUsedHeapMb = peakUsedHeapBytes / 1_048_576
        val peakPssMb = peakPssKb / 1024

        // The single verbatim summary line copied into the Gate-5b evidence file. peak_used_heap / peak_pss are
        // the IN-PASS peaks (sampled during index(), not post-return).
        Log.i(
            TAG,
            "SUMMARY book=${if (usedReal) "real:黑暗血时代.txt" else "synthetic"} bytes_utf8=$byteCountUtf8 " +
                "chars_utf16=${text.length} chunks=${document.chunkCount} pages=$pageCount " +
                "phase1_median_ms=$medianMs runs=${samples.toList()} " +
                "peak_used_heap_mb=$peakUsedHeapMb peak_pss_mb=$peakPssMb content_box=${box.widthPx.toInt()}x${box.heightPx.toInt()}",
        )

        // --- NON-BLOCKING sanity bounds only (NOT a latency SLA — high latency is a documented follow-up) ---
        assertTrue("median latency must be strictly positive", medianMs > 0)
        assertTrue("median latency under the generous ceiling ($medianMs ms)", medianMs < MAX_RUN_MS)
        assertTrue("phase-1 produced a real multi-page index (>1 page) on a 14MB doc", pageCount > 1)
        assertTrue("peak PSS must be a plausible positive reading", peakPssMb > 0)
    }

    /**
     * Polls the in-pass memory peak on a background thread while phase-1 runs on the caller's thread. Records
     * the max used-heap DELTA (over the pre-run baseline) and the max total PSS seen during the pass, so a
     * transient allocation spike that is reclaimed before index() returns is still captured (Gate-4 High-1).
     */
    private class MemorySampler(
        private val runtime: Runtime,
        private val baseUsedBytes: Long,
    ) : Runnable {
        @Volatile private var running = true
        @Volatile var peakUsedDeltaBytes = 0L; private set
        @Volatile var peakPssKb = 0; private set
        @Volatile var sampleCount = 0; private set

        fun stop() { running = false }

        override fun run() {
            while (running) {
                val usedDelta = ((runtime.totalMemory() - runtime.freeMemory()) - baseUsedBytes).coerceAtLeast(0L)
                if (usedDelta > peakUsedDeltaBytes) peakUsedDeltaBytes = usedDelta
                val pssKb = Debug.MemoryInfo().also { Debug.getMemoryInfo(it) }.totalPss
                if (pssKb > peakPssKb) peakPssKb = pssKb
                sampleCount++
                try { Thread.sleep(20) } catch (e: InterruptedException) { break }
            }
            // one final sample at stop so a fast pass still records ≥1 reading.
            val usedDelta = ((runtime.totalMemory() - runtime.freeMemory()) - baseUsedBytes).coerceAtLeast(0L)
            if (usedDelta > peakUsedDeltaBytes) peakUsedDeltaBytes = usedDelta
            val pssKb = Debug.MemoryInfo().also { Debug.getMemoryInfo(it) }.totalPss
            if (pssKb > peakPssKb) peakPssKb = pssKb
            sampleCount++
        }
    }

    /** One phase-1 index pass with a fresh token (the open→first-page boundary measurement). */
    private fun runIndex(
        document: TxtDocument,
        style: TextStyle,
        box: PageContentBox,
        measurer: LineMeasurer,
    ): TxtPageIndex = runBlocking {
        // isMarkdown=false: the real book + synthetic corpus are plain TXT (raw glyphs, no marker stripping).
        com.vreader.app.reader.paged.TxtPaginator().index(document, style, box, measurer, PaginationToken(), isMarkdown = false)
    }
}
