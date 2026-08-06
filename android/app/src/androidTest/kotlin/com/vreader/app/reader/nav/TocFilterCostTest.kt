package com.vreader.app.reader.nav

import android.os.SystemClock
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.data.Book
import com.vreader.app.reader.TxtDecoder
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.FixMethodOrder
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.MethodSorters
import vreader.contracts.BookFormat
import vreader.contracts.Identity
import java.io.File
import java.security.MessageDigest

/**
 * Feature #141 WI-1 — **on-target cost measurement for the Contents filter**, moved up from WI-6 by
 * plan §6 so WI-4 knows BEFORE it wires anything whether it must build the off-thread corpus fold.
 *
 * Three separately budgeted costs (plan §6). They are measured here on the target because this repo
 * has a recorded ~100× desktop-to-device miss (#139: 46–102 ms on a desktop JVM, 8.3–11.4 s on the
 * emulator), and #138's lesson that a perf test which can silently fall back to a synthetic fixture
 * measures nothing:
 *
 * | Cost | When it is paid | Budget |
 * | --- | --- | --- |
 * | **A** — the NOT-filtering path | every Contents open + every composition | ≤ [FRAME_BUDGET_MS] |
 * | **B** — the corpus fold, 1 859 titles | ONCE, at the first query that can match | ≤ [CORPUS_FOLD_BUDGET_MS] |
 * | **C** — one keystroke's filter pass | every keystroke | ≤ [FRAME_BUDGET_MS] |
 *
 * **Cost B is the one that matters.** §5.2's `lazy(NONE)` defers it INTO the first keystroke, on the
 * composition thread. A debounce cannot fix it — a debounce delays the fold, it does not make it
 * cheaper. Both the COLD first pass (the production shape: a fold happens once per book, with
 * whatever JIT state the app happens to have) and the best of repeated passes are reported, and the
 * budget is asserted against BOTH so a pass cannot be bought with warm-up the user never gets.
 *
 * **Cost A's scope in THIS WI.** The filter's half of cost A — "the blank branch touches no corpus
 * and materialises no per-row object" — is measured here. The other half, that the SHEET still
 * composes no more rows than today, belongs to WI-4's `TocContentsLargeTocTest` counters: nothing is
 * wired into the sheet yet, so there is no composition to count.
 *
 * **Fixture — real book first; the fallback is FAILURE, not synthesis.** Identity is pinned by
 * SHA-256 over the pushed bytes plus the decoded character count and the provider's chapter count.
 * `connectedAndroidTest` wipes `/sdcard/Android/data/<pkg>/` at run end, so the book must be
 * re-pushed EVERY run (#138's durable lesson):
 *
 * ```
 * adb -s emulator-5554 shell mkdir -p /sdcard/Android/data/com.vreader.app/files
 * adb -s emulator-5554 push test-books/books/txt/黑暗血时代.txt \
 *     /sdcard/Android/data/com.vreader.app/files/perf-cjk.txt
 * ```
 *
 * Numbers land on logcat (`adb logcat -d -s WI141-COST:I`), read retrospectively AFTER the run —
 * never streamed alongside it, and never drive the emulator while instrumentation is in flight
 * (rules 49/52). Run ONE class per connected invocation.
 */
@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class TocFilterCostTest {

    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()

    private companion object {
        const val TAG = "WI141-COST"

        /** The pushed real 14 MB CJK novel, pinned by content digest. */
        const val REAL_BOOK_FILE = "perf-cjk.txt"
        const val REAL_BOOK_BYTES = 14_059_220L
        const val REAL_BOOK_SHA256 = "04d60f6d93256c0d82f714ad1237a57ca88dcd469fb37bef231af062c543cfe4"
        const val EXPECTED_CHARS_UTF16 = 7_029_609
        const val EXPECTED_ENTRIES = 1_859

        /** Plan §6, cost B. Held, not discovered — the plan set it before this class existed. */
        const val CORPUS_FOLD_BUDGET_MS = 120L

        /** Plan §6, costs A and C: half a 60 Hz frame, because both are paid per composition. */
        const val FRAME_BUDGET_MS = 8L

        /** How many independent COLD folds are timed. Each builds a brand-new corpus. */
        const val FOLD_PASSES = 5

        /** A LazyColumn's visible window — cost A is paid for these rows only. */
        const val VISIBLE_WINDOW = 12

        /** Keystrokes replayed for cost C, each a prefix the previous one grows into. */
        val KEYSTROKES = listOf("第", "第十", "第十一", "第十一章", "黎", "黎明")
    }

    private fun report(line: String) = Log.i(TAG, line)

    // ---- fixture (real book; requireNotNull, never a synthetic fallback) --------------------------

    private fun requireRealBookFile(): File {
        val dir = requireNotNull(instrumentation.targetContext.getExternalFilesDir(null)) {
            "no external files dir on this device"
        }
        val file = File(dir, REAL_BOOK_FILE)
        require(file.exists() && file.canRead()) {
            "WI-1's cost measurement requires the REAL 14 MB CJK book at " +
                "getExternalFilesDir(null)/$REAL_BOOK_FILE. Push it before EVERY run: adb push " +
                "test-books/books/txt/黑暗血时代.txt " +
                "/sdcard/Android/data/com.vreader.app/files/$REAL_BOOK_FILE"
        }
        return file
    }

    /**
     * The real book's TOC, built by the SHIPPED [TxtMdTocProvider] — not by a hand-rolled scan, so
     * the titles this class folds are byte-for-byte the titles the Contents sheet will show.
     *
     * The byte size is a cheap early diagnostic; the digest is the identity check, because a
     * same-sized stand-in would sail straight through a size comparison.
     */
    private fun requireRealBookEntries(): List<TocEntry> {
        val file = requireRealBookFile()
        assertEquals("the pushed fixture must be the real book's size", REAL_BOOK_BYTES, file.length())
        val bytes = file.readBytes()
        val sha = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
        assertEquals("the pushed fixture must BE 黑暗血时代.txt (content digest)", REAL_BOOK_SHA256, sha)

        val text = TxtDecoder.decode(bytes).text
        assertEquals("the decoded book must be the plan's corpus", EXPECTED_CHARS_UTF16, text.length)

        val book = Book(
            fingerprintKey = Identity.canonicalKey("txt", sha, REAL_BOOK_BYTES),
            title = "黑暗血时代",
            originalFormat = BookFormat.txt,
            contentSHA256 = sha,
            fileByteCount = REAL_BOOK_BYTES,
            addedAt = 0L,
        )
        val entries = runBlocking {
            TxtMdTocProvider(text, book, BookFormat.txt, Dispatchers.Default).toc()
        }
        assertEquals(
            "the shipped provider must yield the plan's 1 859-entry corpus on the real book",
            EXPECTED_ENTRIES, entries.size,
        )
        return entries
    }

    // ---- 1. cost A — the not-filtering path ---------------------------------------------------------

    /**
     * **Cost A.** Opening Contents and scrolling it must cost what it costs today: a per-visible-row
     * title normalization and nothing else.
     *
     * Two claims, one structural and one timed. The structural one is the stronger: the blank branch
     * returns the [TocFilterResult.Unfiltered] SINGLETON without reading the corpus `Lazy` at all, so
     * no title outside the visible window is ever normalized. Plan §6 records that this cost has
     * re-entered through this branch three times, each time one edit after it was removed.
     */
    @Test
    fun costA_notFilteringPathTouchesNoCorpusAndOnlyTheVisibleWindow() {
        val entries = requireRealBookEntries()
        val corpus = lazy { TocFoldedToc.of(entries) }

        // Warm-up: JIT the same shapes the timed region runs, on rows outside the measured window.
        repeat(VISIBLE_WINDOW) { TocTitleFilter.plainRowText(entries[EXPECTED_ENTRIES - 1 - it]) }
        TocTitleFilter.filter("", "", corpus)

        val t0 = SystemClock.elapsedRealtimeNanos()
        val result = TocTitleFilter.filter(trimmedQuery = "", foldedQuery = "", foldedToc = corpus)
        val titles = ArrayList<String>(VISIBLE_WINDOW)
        for (i in 0 until VISIBLE_WINDOW) titles.add(TocTitleFilter.plainRowText(entries[i]).title)
        val ms = (SystemClock.elapsedRealtimeNanos() - t0) / 1_000_000.0

        report("COST-A entries=${entries.size} window=$VISIBLE_WINDOW ms=%.3f budget_ms=$FRAME_BUDGET_MS".format(ms))
        report("COST-A first_row_title=${titles.first()} corpus_forced=${corpus.isInitialized()}")

        assertTrue("the blank branch must return the singleton", result === TocFilterResult.Unfiltered)
        assertFalse(
            "opening Contents must NOT force the corpus fold — that is cost B, deferred to the " +
                "first query that can match",
            corpus.isInitialized(),
        )
        assertEquals("every visible row must render a title", VISIBLE_WINDOW, titles.size)
        assertTrue("a visible window's titles must be non-empty", titles.all { it.isNotEmpty() })
        assertTrue(
            "the not-filtering path cost ${"%.3f".format(ms)}ms for $VISIBLE_WINDOW rows against a " +
                "${FRAME_BUDGET_MS}ms budget",
            ms <= FRAME_BUDGET_MS,
        )
    }

    // ---- 2. cost B — the corpus fold (THE risk) ------------------------------------------------------

    /**
     * **Cost B — the one >100 ms-class risk in the feature.** Fold all 1 859 real titles, [FOLD_PASSES]
     * times, each into a BRAND-NEW corpus (the production shape: one fold per book, never reused).
     *
     * Both statistics are asserted. The COLD first pass is what a user actually pays at the first
     * keystroke of a session; the MINIMUM is the statistic most generous to the implementation, which
     * is what makes a failure decisive rather than a claim about emulator load. A budget that only
     * held for the warm case would be measuring a state the user never reaches.
     *
     * The corpus is also checked for CORRECTNESS in the same method: a fold that got fast by folding
     * fewer titles, or by folding them wrongly, is not a pass — and a latency budget alone would not
     * notice.
     */
    @Test
    fun costB_corpusFoldMeetsBudgetOnTheRealBook() {
        val entries = requireRealBookEntries()

        val timings = LongArray(FOLD_PASSES)
        var last: TocFoldedToc? = null
        for (pass in 0 until FOLD_PASSES) {
            System.gc()
            Thread.sleep(120)
            val t0 = SystemClock.elapsedRealtime()
            val corpus = TocFoldedToc.of(entries)
            timings[pass] = SystemClock.elapsedRealtime() - t0
            last = corpus
            report("COST-B pass=${pass + 1}/$FOLD_PASSES ms=${timings[pass]} budget_ms=$CORPUS_FOLD_BUDGET_MS")
        }
        val cold = timings.first()
        val best = timings.min()
        report("COST-B-SUMMARY cold_ms=$cold best_ms=$best all_ms=${timings.joinToString(",")} " +
            "entries=${entries.size} budget_ms=$CORPUS_FOLD_BUDGET_MS")

        val corpus = requireNotNull(last)
        assertEquals("the corpus must cover every entry", EXPECTED_ENTRIES, corpus.size)
        // Correctness, not just speed: a real chapter query must find real rows, and every surviving
        // index must be in range and strictly ascending.
        val hits = corpus.filter(TocTitleFilter.foldQuery("第一章"))
        assertTrue("第一章 must survive the filter on this book", hits.isNotEmpty())
        for (i in hits.indices) {
            assertTrue("index out of range", hits[i] in entries.indices)
            if (i > 0) assertTrue("indices must be strictly ascending", hits[i] > hits[i - 1])
        }

        assertTrue(
            "the COLD corpus fold took ${cold}ms against a ${CORPUS_FOLD_BUDGET_MS}ms budget — this " +
                "is what the user pays at the first keystroke, on the composition thread. Over " +
                "budget means WI-4 must build plan §6's off-thread fold; it does NOT mean the " +
                "budget moves",
            cold <= CORPUS_FOLD_BUDGET_MS,
        )
        assertTrue(
            "the best of $FOLD_PASSES corpus folds took ${best}ms against a ${CORPUS_FOLD_BUDGET_MS}ms budget",
            best <= CORPUS_FOLD_BUDGET_MS,
        )
    }

    // ---- 3. cost C — one keystroke ------------------------------------------------------------------

    /**
     * **Cost C.** With the corpus already folded, one keystroke must cost at most half a frame: fold
     * the query, then one `indexOf` per pre-folded title.
     *
     * Each keystroke in [KEYSTROKES] is timed separately and the WORST is asserted, because the user
     * feels the worst one, not the average. `第` is deliberately in the list: it matches essentially
     * every row on this book, so the result array is at its largest.
     */
    @Test
    fun costC_perKeystrokePassMeetsBudgetOnTheRealBook() {
        val entries = requireRealBookEntries()
        val corpus = TocFoldedToc.of(entries)
        val ready = lazyOf(corpus)

        // Warm-up on queries the timed region does not measure.
        listOf("章", "前", "x").forEach {
            TocTitleFilter.filter(it, TocTitleFilter.foldQuery(it), ready)
        }

        var worstMs = 0.0
        var worstQuery = ""
        KEYSTROKES.forEach { query ->
            val t0 = SystemClock.elapsedRealtimeNanos()
            val result = TocTitleFilter.filter(query, TocTitleFilter.foldQuery(query), ready)
            val ms = (SystemClock.elapsedRealtimeNanos() - t0) / 1_000_000.0
            val hits = (result as TocFilterResult.Matched).indices.size
            report("COST-C query=$query hits=$hits ms=%.3f budget_ms=$FRAME_BUDGET_MS".format(ms))
            if (ms > worstMs) {
                worstMs = ms
                worstQuery = query
            }
        }
        report("COST-C-SUMMARY worst_query=$worstQuery worst_ms=%.3f budget_ms=$FRAME_BUDGET_MS".format(worstMs))

        // A pass that got fast by matching nothing is not a pass.
        val broad = TocTitleFilter.filter("第", TocTitleFilter.foldQuery("第"), ready)
        assertTrue("第 must match the overwhelming majority of this book's chapters",
            (broad as TocFilterResult.Matched).indices.size > EXPECTED_ENTRIES / 2)
        val none = TocTitleFilter.filter("zzzz", TocTitleFilter.foldQuery("zzzz"), ready)
        assertArrayEquals(IntArray(0), (none as TocFilterResult.Matched).indices)

        assertTrue(
            "the worst keystroke ('$worstQuery') cost ${"%.3f".format(worstMs)}ms against a " +
                "${FRAME_BUDGET_MS}ms budget over ${entries.size} pre-folded titles",
            worstMs <= FRAME_BUDGET_MS,
        )
    }
}
