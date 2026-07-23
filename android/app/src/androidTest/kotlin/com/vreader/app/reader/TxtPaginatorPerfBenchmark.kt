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
import com.vreader.app.reader.paged.PaginationSession
import com.vreader.app.reader.paged.PaginationToken
import com.vreader.app.reader.paged.TxtPageIndex
import com.vreader.app.reader.paged.TxtPaginator
import com.vreader.app.reader.settings.ReaderSettings
import com.vreader.app.reader.settings.bodyTextStyle
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
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

        // --- feature #138 WI-6 (windowed acceptance) constants -----------------------------------
        // Open-to-first-page (the FIRST sealed-window publish from PaginationSession.openFromStart) is the
        // ONE latency #138 bounds: it seals only DEFAULT_INITIAL_WINDOW_PAGES (3) pages, so it is
        // INDEPENDENT of the 30 695-page total (plan §WI-6 acceptance, lines 753-761). This is the whole
        // thesis — a cold open of a 14 MB book shows page 1 in well under a phone-tap's worth of time
        // regardless of book size. The test ASSERTS this < 2 s TARGET (the measured value is ~3 ms, so the
        // stated acceptance target IS the gate — Gate-4 High-2 — not a looser ceiling that could false-green).
        const val FIRST_PAGE_TARGET_MS = 2_000L
        // The #137 non-windowed index() count on emulator-5554 with the #129 defaults (WI-11 evidence). The
        // windowed FULL completion must reproduce it EXACTLY AND be byte-for-byte identical to index() — the
        // environment-independent parity assertion is the real correctness proof; this count is the
        // this-emulator expected value the plan names.
        const val EXPECTED_REAL_PAGE_COUNT = 30_695
        // Peak PSS bound. #137 measured 296 MB total PSS for the FULL index; the windowed pass retains the
        // SAME page-start IntArray (no extra structure), so peak PSS stays the same order (three real-book
        // runs measured 276 / 278 / 290 MB — total PSS is inherently GC/allocation-noisy). The plan asks for
        // ≤ ~300 MB; the test ASSERTS that TARGET (Gate-4 High-2), cleared by every observed run. This is a
        // manually-run connected acceptance gate (not CI), so the ~10 MB headroom is acceptable.
        const val PSS_TARGET_MB = 300
        // The far-jump target — ~90% into the document (bookmark / find / TTS / scrubber into an unmeasured
        // region). The test asserts it EVENTUALLY lands exactly and RECORDS the extend latency; it does NOT
        // hard-fail on a UX budget (Gate-2 R1 High 4: the bound is frontier→target distance, not a UX SLA).
        const val FAR_JUMP_FRACTION = 0.9
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

        // --- production shaping inputs captured from a live composition (ONE setContent per test) ---
        val (m, st, box) = captureShaping()

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

    // --- feature #138 WI-6: windowed / incremental pagination acceptance ---------------------------

    /**
     * Feature #138 WI-6 (windowed acceptance) — **open-to-first-page** on the REAL 14 MB CJK book.
     *
     * The ONE latency #138 bounds is the FIRST sealed-window publish of [PaginationSession.openFromStart]:
     * it seals only [TxtPaginator.DEFAULT_INITIAL_WINDOW_PAGES] pages, so it is INDEPENDENT of the
     * 30 695-page total. This is the entire thesis of the feature — a cold open of a 14 MB book shows
     * page 1 in well under 3 s (target < 2 s), where #137's whole-doc phase-1 took ~96 s.
     *
     * The same run drives the session to FULL completion in the background and asserts the completed
     * windowed index is **byte-for-byte identical** to #137's non-windowed [TxtPaginator.index] (the
     * environment-independent correctness proof) AND reproduces the this-emulator page count
     * ([EXPECTED_REAL_PAGE_COUNT], real book only). Peak PSS is sampled DURING the whole pass and gated
     * at a non-flaky ceiling with the real number RECORDED for the evidence file.
     *
     * Real-book REQUIRED (Gate-4 High-1): unlike the #137 dev-benchmark above (which keeps a synthetic
     * fallback for CI-safety), this is the Gate-5b ACCEPTANCE gate — a synthetic fallback would make the
     * "real 14 MB / 30,695-page" acceptance HOLLOW, so the real byte-size-validated book is mandatory
     * (push `perf-cjk.txt` before the run — see the evidence file's Commands). Run ONE class per connected
     * invocation (MEMORY #129/#133).
     */
    @Test
    fun wi6_openToFirstPage_and_fullIndexParity_14mbCjk() {
        // ACCEPTANCE REQUIRES the genuine 14,059,220-byte CJK book (no synthetic fallback here — Gate-4 High-1).
        val text = requireNotNull(readRealBookOrNull()) {
            "WI-6 acceptance requires the real 14 MB CJK book at perf-cjk.txt " +
                "($REAL_BOOK_BYTES bytes) — push it to the app's external files dir before the run"
        }
        val byteCountUtf8 = text.toByteArray(Charsets.UTF_8).size
        val document = TxtDocument.of(text)
        assertTrue("the corpus must be non-trivial (>1M chars)", text.length > 1_000_000)
        assertTrue("the document must have chunks", document.chunkCount > 0)

        val (m, st, box) = captureShaping()

        // --- COLD open-to-first-page: measure openFromStart → the FIRST published snapshot. No warm-up:
        //     a fresh open IS cold in production, so the cold first-window latency is the honest number.
        //     Peak PSS is sampled on a background thread while the WHOLE pass (first window + background
        //     completion) runs, so a transient allocation spike is captured (Gate-4 High-1, #137 pattern). ---
        val session = PaginationSession(
            TxtPaginator(),
            initialWindowPages = TxtPaginator.DEFAULT_INITIAL_WINDOW_PAGES,
            extendPages = TxtPaginator.DEFAULT_EXTEND_PAGES,
        )
        val runtime = Runtime.getRuntime()
        System.gc()
        Thread.sleep(50)   // let GC settle before the used-heap baseline (not a sync primitive)
        val baseUsed = runtime.totalMemory() - runtime.freeMemory()
        val sampler = MemorySampler(runtime, baseUsed)
        val samplerThread = Thread(sampler, "wi6-perf-sampler").apply { isDaemon = true; start() }

        var firstPageMs = -1L
        var firstWindowPages = 0
        var snapshots = 0
        var finalSnap: TxtPageIndex? = null
        val t0 = SystemClock.elapsedRealtime()
        runBlocking {
            session.openFromStart(
                document = document, style = st, contentBox = box, measurer = m, isMarkdown = false,
                resumeAnchorOffset = 0,
                onSnapshot = { snap ->
                    if (firstPageMs < 0) {
                        firstPageMs = SystemClock.elapsedRealtime() - t0
                        firstWindowPages = snap.pageCount
                    }
                    snapshots++
                    finalSnap = snap
                },
                onReveal = { /* anchor 0 → contained in the first window; no deep-resume reveal */ },
            )
        }
        val fullCompletionMs = SystemClock.elapsedRealtime() - t0
        sampler.stop()
        samplerThread.join(2_000)
        val peakPssMb = sampler.peakPssKb / 1024
        val peakUsedHeapMb = sampler.peakUsedDeltaBytes / 1_048_576

        val windowed = finalSnap!!
        assertTrue("openFromStart must publish at least one window", snapshots > 0)
        assertTrue("the completed windowed index must cover the whole doc", windowed.isComplete)
        // The first window seals AT LEAST the initial-window target (measurePages is a LOWER-bound that
        // may overshoot to a chunk boundary) — directly asserts the #138 initial-window boundary, not a
        // vacuous ≥1. `< windowed.pageCount` proves the first publish is genuinely PARTIAL (real windowing).
        assertTrue(
            "first window ($firstWindowPages) must seal ≥ the initial-window target " +
                "(${TxtPaginator.DEFAULT_INITIAL_WINDOW_PAGES})",
            firstWindowPages >= TxtPaginator.DEFAULT_INITIAL_WINDOW_PAGES,
        )
        assertTrue("first window must not exceed the whole book", firstWindowPages < windowed.pageCount)

        // --- correctness cross-check: the completed windowed full index == #137's non-windowed index() ---
        // This is the environment-INDEPENDENT proof (holds on real AND synthetic): byte-for-byte identical
        // page-start offsets prove windowing changed WHERE measuring pauses, never the resulting boundaries.
        val nonWindowed = runIndex(document, st, box, m)
        assertEquals(
            "windowed full index page count == #137 index() page count",
            nonWindowed.pageCount, windowed.pageCount,
        )
        assertArrayEquals(
            "windowed full index page-starts BYTE-IDENTICAL to #137 index()",
            nonWindowed.pageStartsUtf16, windowed.pageStartsUtf16,
        )
        assertEquals(
            "docEndExclusive identical to #137 index()",
            nonWindowed.docEndExclusive, windowed.docEndExclusive,
        )

        // --- the verbatim SUMMARY line copied into the Gate-5b evidence file (asserted below) ---
        Log.i(
            TAG,
            "WI6-SUMMARY book=real:黑暗血时代.txt bytes_utf8=$byteCountUtf8 " +
                "chars_utf16=${text.length} chunks=${document.chunkCount} pages=${windowed.pageCount} " +
                "first_page_ms=$firstPageMs first_window_pages=$firstWindowPages " +
                "first_page_target_met(<${FIRST_PAGE_TARGET_MS}ms)=${firstPageMs < FIRST_PAGE_TARGET_MS} " +
                "full_completion_ms=$fullCompletionMs snapshots=$snapshots " +
                "peak_pss_mb=$peakPssMb peak_used_heap_mb=$peakUsedHeapMb pss_target_met(<=${PSS_TARGET_MB}mb)=${peakPssMb <= PSS_TARGET_MB} " +
                "parity_vs_137_index=byte-identical content_box=${box.widthPx.toInt()}x${box.heightPx.toInt()}",
        )

        // --- assertions: gate on the STATED acceptance TARGETS (Gate-4 High-2), not a looser ceiling ---
        assertTrue("open-to-first-page must be measured (>0)", firstPageMs > 0)
        assertTrue(
            "open-to-first-page ($firstPageMs ms) must meet the < ${FIRST_PAGE_TARGET_MS}ms acceptance TARGET, " +
                "independent of the ${windowed.pageCount}-page total",
            firstPageMs < FIRST_PAGE_TARGET_MS,
        )
        assertTrue("peak PSS ($peakPssMb MB) must be a plausible positive reading", peakPssMb > 0)
        assertTrue(
            "peak PSS ($peakPssMb MB) must meet the ≤ ${PSS_TARGET_MB}MB acceptance TARGET (#137 measured ~296MB)",
            peakPssMb <= PSS_TARGET_MB,
        )
        // The real book is REQUIRED (above), so the exact this-emulator (#137 WI-11) count is unconditional;
        // the environment-independent assertArrayEquals parity above is the portable correctness proof.
        assertEquals(
            "real-book windowed full index == #137 WI-11 page count",
            EXPECTED_REAL_PAGE_COUNT, windowed.pageCount,
        )
    }

    /**
     * Feature #138 WI-6 — **far-jump honesty**. A bookmark / find / TTS / scrubber into an UNMEASURED
     * region (~90% into the 14 MB doc) EVENTUALLY resolves to the exact page via
     * [PaginationSession.ensureMeasuredThrough], while the reader stays on the current page (no freeze,
     * no loading UI). The test RECORDS the extend latency and asserts EVENTUAL exact landing; it does
     * NOT hard-fail on a UX budget — the bound is frontier→target document distance, not a fixed SLA
     * (Gate-2 R1 High 4).
     *
     * Realism: the far-jump is issued right after the FIRST window seals, while the background completion
     * loop is still running — exactly the production race (they coalesce under the session's single
     * mutex). The recorded latency is the honest wall-clock until the jump target is sealed.
     */
    @Test
    fun wi6_farJumpTo90Percent_eventuallyLands_recordsLatency() {
        // ACCEPTANCE REQUIRES the genuine 14 MB CJK book (no synthetic fallback — Gate-4 High-1).
        val text = requireNotNull(readRealBookOrNull()) {
            "WI-6 far-jump acceptance requires the real 14 MB CJK book at perf-cjk.txt " +
                "($REAL_BOOK_BYTES bytes) — push it to the app's external files dir before the run"
        }
        val document = TxtDocument.of(text)
        assertTrue("the corpus must be non-trivial (>1M chars)", text.length > 1_000_000)

        val (m, st, box) = captureShaping()
        val session = PaginationSession(
            TxtPaginator(),
            initialWindowPages = TxtPaginator.DEFAULT_INITIAL_WINDOW_PAGES,
            extendPages = TxtPaginator.DEFAULT_EXTEND_PAGES,
        )
        val targetOffset = (document.text.length * FAR_JUMP_FRACTION).toInt()

        runBlocking {
            val firstPublished = CompletableDeferred<TxtPageIndex>()
            // Open in a CHILD coroutine so the background completion loop keeps running while we jump.
            val bg = launch {
                session.openFromStart(
                    document = document, style = st, contentBox = box, measurer = m, isMarkdown = false,
                    resumeAnchorOffset = 0,
                    onSnapshot = { snap -> if (!firstPublished.isCompleted) firstPublished.complete(snap) },
                    onReveal = { },
                )
            }
            val firstWindow = firstPublished.await()
            // The target must be BEYOND the first sealed window for this to be a real unmeasured-region jump.
            val frontierAtJump = firstWindow.frontierSourceOffset
            assertTrue(
                "far-jump target ($targetOffset) must be beyond the first window's frontier ($frontierAtJump)",
                targetOffset > frontierAtJump,
            )

            val j0 = SystemClock.elapsedRealtime()
            val landed = session.ensureMeasuredThrough(targetOffset)
            val extendMs = SystemClock.elapsedRealtime() - j0

            // DIRECT proof the on-demand extend actually SEALED THROUGH the target (not merely a clamp):
            // for an incomplete index the sealed frontier must now be strictly PAST the jump target. This
            // makes the eventual-landing proof self-evident and robust to any future pageContaining change.
            assertTrue(
                "far-jump must seal the frontier past the target (complete=${landed.isComplete} " +
                    "frontier=${landed.frontierSourceOffset} target=$targetOffset)",
                landed.isComplete || landed.frontierSourceOffset > targetOffset,
            )
            // EVENTUAL exact landing: the target offset is inside the resolved page's [start, end). This is
            // asserted UNCONDITIONALLY (Gate-4 Medium) — the range check is valid whether the index is
            // partial or complete (a complete index holds ALL boundaries, so pageContaining still returns the
            // genuine containing page), so it is never short-circuited to a vacuous pass by isComplete.
            val page = landed.pageContaining(targetOffset)
            val landedStart = landed.pageStart(page)
            val landedEnd = landed.pageEndExclusive(page)
            bg.cancelAndJoin()   // stop the background loop BEFORE reusing the measurer for the ground-truth index

            // Ground-truth parity for the JUMP TARGET (Gate-4 Medium): the far-jump must land on the SAME
            // page a non-windowed index() would, with identical [start, end). This proves EXACT parity for the
            // jumped-to offset, not merely "some covered index returned". The measurer is free now (bg joined).
            val truth = runIndex(document, st, box, m)
            val truthPage = truth.pageContaining(targetOffset)
            Log.i(
                TAG,
                "WI6-FARJUMP book=real:黑暗血时代.txt " +
                    "target_offset=$targetOffset frontier_at_jump=$frontierAtJump extend_ms=$extendMs " +
                    "landed_page=$page landed_range=[$landedStart,$landedEnd) truth_page=$truthPage " +
                    "sealed_pages=${landed.pageCount} complete=${landed.isComplete}",
            )
            assertTrue(
                "far-jump to ~90% ($targetOffset) must land on the EXACT containing page " +
                    "(page=$page range=[$landedStart,$landedEnd))",
                landedStart <= targetOffset && targetOffset < landedEnd,
            )
            assertEquals(
                "far-jump landed page == non-windowed index() page for the target",
                truthPage, page,
            )
            assertEquals(
                "far-jump landed page START == non-windowed index() start for the target",
                truth.pageStart(truthPage), landedStart,
            )
            assertEquals(
                "far-jump landed page END == non-windowed index() end for the target",
                truth.pageEndExclusive(truthPage), landedEnd,
            )
        }
    }

    /**
     * Capture the EXACT production shaping inputs from a live composition — a real
     * [ComposeLineMeasurer] over a [TextMeasurer], the #129 body style, and a chrome-aware
     * [PageContentBox] (device screen minus the #129 default margins). `compose.setContent` may be
     * called only ONCE per test (MEMORY #134), so each @Test captures its own.
     */
    private fun captureShaping(): Shaping {
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
        val box = contentBox!!
        assertFalse("content box must not be degenerate on a real screen", box.isDegenerate)
        return Shaping(measurer!!, style!!, box)
    }

    /** The production shaping inputs a phase-1 / windowed pass needs (captured from a live composition). */
    private data class Shaping(val measurer: LineMeasurer, val style: TextStyle, val box: PageContentBox)

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
