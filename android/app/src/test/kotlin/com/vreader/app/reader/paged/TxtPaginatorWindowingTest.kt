package com.vreader.app.reader.paged

import androidx.compose.ui.text.TextStyle
import com.vreader.app.reader.TxtDocument
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * Feature #138 WI-3 — the WINDOWING ENTRY POINTS + SEAL DISCIPLINE of [TxtPaginator].
 *
 * WI-1 extracted the resumable core ([TxtPaginator.freshCursor] / [TxtPaginator.measurePages] /
 * [TxtPaginator.measureThroughOffset] driving [TxtPaginator.measureFrom]) and re-implemented
 * `index(...)` on it; WI-2 gave [TxtPageIndex] sealed-partial support. WI-3 proves the LOAD-BEARING
 * property those two enable: a doc-start-forward incremental pass — `freshCursor` + repeated
 * `measurePages`/`measureThroughOffset` until complete — produces a BYTE-IDENTICAL page-start
 * `IntArray` to today's whole-document `index(...)`, and the SEAL discipline is correct:
 *   • a page is emitted (sealed) only once its successor's start is known (+1-page lookahead);
 *   • the FINAL page seals at doc end;
 *   • an append NEVER mutates a previously-sealed page's `[start, end)`;
 *   • min-one-line forward progress holds across a window boundary, not just within one pass.
 *
 * The measurer + fixtures mirror [TxtPaginatorTest] / [TxtPaginatorResumableCoreTest] so the
 * windowing tests exercise the SAME tiling truth (never a fork). All JVM (deterministic fake
 * measurer, no Android TextMeasurer).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class TxtPaginatorWindowingTest {

    private val style = TextStyle()

    /** Same deterministic fake as the sibling suites: fixed-width lines, never splits a pair. */
    private class FixedLineMeasurer(
        private val charsPerLine: Int,
        private val lineHeightPx: Float = 10f,
    ) : LineMeasurer {
        override fun measure(text: CharSequence, style: TextStyle, maxWidthPx: Float): List<LineMetric> {
            if (text.isEmpty()) return listOf(LineMetric(0, 0, lineHeightPx))
            val lines = ArrayList<LineMetric>()
            var start = 0
            val n = text.length
            while (start < n) {
                var end = (start + charsPerLine).coerceAtMost(n)
                if (end < n && Character.isHighSurrogate(text[end - 1]) && Character.isLowSurrogate(text[end])) end++
                lines.add(LineMetric(start, end, lineHeightPx))
                start = end
            }
            return lines
        }
    }

    private fun box(heightPx: Float, widthPx: Float = 1000f) = PageContentBox(widthPx, heightPx)

    /** A doc/box/measurer scenario the windowing tests iterate over — the #138 WI-3 edge matrix. */
    private data class Scenario(
        val name: String,
        val text: String,
        val heightPx: Float,
        val charsPerLine: Int,
        val lineHeightPx: Float = 10f,
        val isMarkdown: Boolean = false,
    )

    /**
     * The load-bearing edge matrix: empty, one-line, an oversized >4000-char chunk forcing a
     * mid-chunk split, CJK-no-whitespace, surrogate pairs, and text landing exactly on a page
     * boundary — the shapes the append-equivalence property must hold for byte-for-byte.
     */
    private fun scenarios(): List<Scenario> = listOf(
        Scenario("empty", "", 30f, 100),
        Scenario("one-line", "hello world\n", 100f, 100),
        Scenario("oversized-4200-mid-chunk-split", "x".repeat(4200), 30f, 500),
        Scenario("cjk-no-whitespace", "字".repeat(120) + "\n", 20f, 10),
        Scenario("surrogate-pairs", "𝕏".repeat(90) + "\n", 20f, 9),
        Scenario("exactly-on-page-boundary", (0 until 12).joinToString("") { "r$it\n" }, 30f, 100),
        Scenario("multi-page-plain", (0 until 40).joinToString("") { "row$it\n" }, 25f, 7),
        Scenario("min-one-line-overtall", "aaaa\nbbbb\ncccc\ndddd\n", 10f, 100, lineHeightPx = 100f),
        Scenario("md-bullet-narrow", "- one\n- two\n- three\n", 10f, 2, isMarkdown = true),
    )

    /**
     * Drive the resumable core to COMPLETION with a chosen window size (1 page at a time when [window]
     * == 1), collecting every SEALED start via the emit callback. Returns the collected starts and the
     * final cursor. A guard aborts a non-converging drive.
     */
    private suspend fun driveToCompletion(
        p: TxtPaginator, doc: TxtDocument, boxPx: PageContentBox,
        m: LineMeasurer, isMarkdown: Boolean, window: Int,
    ): Pair<List<Int>, MeasureCursor> {
        val collected = ArrayList<Int>()
        var cursor = p.freshCursor(doc, style, boxPx, m, isMarkdown)
        val token = PaginationToken()
        var guard = 0
        while (!cursor.isComplete) {
            cursor = p.measurePages(cursor, additionalPages = window, token = token) { collected.add(it) }
            if (guard++ > 5_000_000) fail("measurePages did not converge (infinite loop guard)")
        }
        return collected to cursor
    }

    // === (1) windowing math: measurePages(freshCursor, K) seals first K pages; frontier == Kth end ===

    @Test fun measurePagesK_oneLinePerChunk_sealsExactlyKPages_frontierEqualsKthEnd() = runTest {
        // ONE line per chunk (newline-per-row) → each chunk carries at most one page break, so the
        // chunk-boundary stop coincides with the page-count stop: measurePages(K) seals EXACTLY K.
        val doc = TxtDocument.of((0 until 60).joinToString("") { "row$it\n" })
        val p = TxtPaginator(UnconfinedTestDispatcher(testScheduler))
        val m = FixedLineMeasurer(charsPerLine = 7, lineHeightPx = 10f)
        val boxPx = box(25f)   // ~2 lines per page → many pages
        val full = p.index(doc, style, boxPx, m, PaginationToken())
        assertTrue("precondition: enough pages for K windows", full.pageCount >= 8)

        for (k in 1..5) {
            val collected = ArrayList<Int>()
            var cursor = p.freshCursor(doc, style, boxPx, m, isMarkdown = false)
            cursor = p.measurePages(cursor, additionalPages = k, token = PaginationToken()) { collected.add(it) }
            // Exactly K pages sealed (each row-chunk carries <=1 break, so no over-seal), equalling
            // index()'s first K starts byte-for-byte.
            assertEquals("K=$k seals exactly K pages", k, collected.size)
            assertEquals("K=$k seals index()'s first K starts", full.pageStartsUtf16.take(k), collected)
            // The cursor frontier == the Kth page's end == index()'s page K start (== pageEndExclusive(K-1)).
            assertFalse("K=$k not complete", cursor.isComplete)
            assertEquals("frontier == Kth page end", full.pageStart(k), cursor.frontierSourceOffset)
        }
    }

    @Test fun measurePagesK_isLowerBound_notExactCap_forRunawayChunk() = runTest {
        // DOCUMENTED contract (Gate-4 WI-3 High-1): measureFrom stops at the next CHUNK boundary once
        // the page-count target is met. A single runaway (no-newline) chunk with MANY page breaks can
        // therefore seal MORE than K in one step — measurePages(K) is a LOWER-BOUND target, not a cap.
        // The page-start SEQUENCE is still byte-identical to index() (append equivalence unaffected);
        // only WHERE the pass pauses shifts to the chunk boundary.
        val doc = TxtDocument.of("z".repeat(3000))   // ONE chunk (< 4000 max), many measured lines
        val p = TxtPaginator(UnconfinedTestDispatcher(testScheduler))
        val m = FixedLineMeasurer(charsPerLine = 50, lineHeightPx = 10f)   // 60 measured lines
        val boxPx = box(20f)   // ~2 lines per page → the ONE chunk holds ~30 page breaks
        val full = p.index(doc, style, boxPx, m, PaginationToken())
        assertTrue("precondition: one runaway chunk → many pages", full.pageCount >= 10)
        assertEquals("precondition: exactly one chunk", 1, doc.chunkCount)

        val collected = ArrayList<Int>()
        var cursor = p.freshCursor(doc, style, boxPx, m, isMarkdown = false)
        // Request just 1 page — but the single chunk seals its whole page run before the boundary stop.
        cursor = p.measurePages(cursor, additionalPages = 1, token = PaginationToken()) { collected.add(it) }
        assertTrue("over-seals past K when one chunk carries many breaks", collected.size > 1)
        // Even over-sealed, the prefix is still index()'s exact starts (sequence unaffected).
        assertEquals("over-sealed prefix == index() prefix", full.pageStartsUtf16.take(collected.size).toList(), collected)
    }

    // === (2) the +1-page lookahead: sealing page 0 requires measuring INTO page 1 ===

    @Test fun sealingPage0_requiresMeasuringIntoPage1_endEqualsPage1Start() = runTest {
        val doc = TxtDocument.of((0 until 30).joinToString("") { "row$it\n" })
        val p = TxtPaginator(UnconfinedTestDispatcher(testScheduler))
        val m = FixedLineMeasurer(charsPerLine = 7, lineHeightPx = 10f)
        val boxPx = box(25f)
        val full = p.index(doc, style, boxPx, m, PaginationToken())
        assertTrue("precondition: multi-page", full.pageCount >= 3)

        val collected = ArrayList<Int>()
        var cursor = p.freshCursor(doc, style, boxPx, m, isMarkdown = false)
        cursor = p.measurePages(cursor, additionalPages = 1, token = PaginationToken()) { collected.add(it) }

        // Sealing page 0 emitted exactly page 0's start; page 1 has STARTED (currentPageStart advanced
        // past page 0) → page 0's exclusive end == page 1's start == the frontier. That advance is the
        // +1-page lookahead: page 0 cannot seal until page 1's start is discovered.
        assertEquals(listOf(full.pageStart(0)), collected)
        assertFalse("page 1 measured into (not complete)", cursor.isComplete)
        assertEquals("page 0's end == page 1's start", full.pageStart(1), cursor.frontierSourceOffset)
        // The pending (page 1) start is NOT itself sealed/emitted.
        assertFalse("page 1 start not yet sealed", collected.contains(full.pageStart(1)))
    }

    // === (3) the FINAL page seals at doc end ===

    @Test fun finalPage_sealsAtDocEnd_onEveryScenario() = runTest {
        for (s in scenarios()) {
            val doc = TxtDocument.of(s.text)
            val p = TxtPaginator(UnconfinedTestDispatcher(testScheduler))
            val m = FixedLineMeasurer(s.charsPerLine, s.lineHeightPx)
            val boxPx = box(s.heightPx)
            val (collected, cursor) = driveToCompletion(p, doc, boxPx, m, s.isMarkdown, window = 1)
            assertTrue("'${s.name}' completes", cursor.isComplete)
            // A complete pass's frontier is doc end; the last sealed page's exclusive end is doc end.
            assertEquals("'${s.name}' frontier == doc end", doc.text.length, cursor.frontierSourceOffset)
            if (collected.isNotEmpty()) {
                val full = p.index(doc, style, boxPx, m, PaginationToken(), s.isMarkdown)
                assertEquals(
                    "'${s.name}' last sealed page ends at doc end",
                    doc.text.length, full.pageEndExclusive(collected.size - 1),
                )
            } else {
                // Empty doc: no page ever sealed, complete at doc end (== 0).
                assertEquals("'${s.name}' empty doc end", 0, doc.text.length)
            }
        }
    }

    // === (4) APPEND EQUIVALENCE (LOAD-BEARING, Gate-2 R1 Critical 1) ===
    //     freshCursor + repeated measurePages/measureThroughOffset until complete == index(),
    //     byte-identical, AND frontierSourceOffset == docEndExclusive at completion.

    @Test fun appendEquivalence_onePageAtATime_equalsIndex_byteForByte() = runTest {
        for (s in scenarios()) {
            val doc = TxtDocument.of(s.text)
            val p = TxtPaginator(UnconfinedTestDispatcher(testScheduler))
            val m = FixedLineMeasurer(s.charsPerLine, s.lineHeightPx)
            val boxPx = box(s.heightPx)
            // index() MUST use the same isMarkdown as the drive — an MD scenario compares an MD drive
            // against an MD index (markers stripped identically), never a TXT index (Gate-4 WI-3 Med-3).
            val full = p.index(doc, style, boxPx, m, PaginationToken(), s.isMarkdown)
            val (collected, cursor) = driveToCompletion(p, doc, boxPx, m, s.isMarkdown, window = 1)
            assertEquals(
                "'${s.name}' one-page-at-a-time drive == index() starts byte-for-byte",
                full.pageStartsUtf16.toList(), collected,
            )
            // Page 0 (if any) is ALWAYS document start 0 — a shifted/off-by-one seal that emitted the
            // pending successor start instead of the sealed start would break this even where the
            // multiset happened to align.
            if (collected.isNotEmpty()) assertEquals("'${s.name}' page 0 starts at doc start", 0, collected[0])
            // Strictly increasing — no duplicate/backward seal from a mis-timed emit.
            for (i in 1 until collected.size) {
                assertTrue("'${s.name}' strictly increasing seals at $i", collected[i] > collected[i - 1])
            }
            assertEquals("'${s.name}' frontier == docEndExclusive at completion", doc.text.length, cursor.frontierSourceOffset)
            assertEquals("'${s.name}' full index's docEnd matches", doc.text.length, full.docEndExclusive)
        }
    }

    @Test fun appendEquivalence_variedWindowSizes_equalIndex() = runTest {
        // The SAME collected starts regardless of window granularity — the window only decides WHERE a
        // pass pauses, never the page-start SEQUENCE.
        for (s in scenarios()) {
            val doc = TxtDocument.of(s.text)
            val p = TxtPaginator(UnconfinedTestDispatcher(testScheduler))
            val m = FixedLineMeasurer(s.charsPerLine, s.lineHeightPx)
            val boxPx = box(s.heightPx)
            val full = p.index(doc, style, boxPx, m, PaginationToken(), s.isMarkdown).pageStartsUtf16.toList()
            for (window in listOf(1, 2, 3, 5, 17)) {
                val (collected, cursor) = driveToCompletion(p, doc, boxPx, m, s.isMarkdown, window)
                assertEquals("'${s.name}' window=$window == index()", full, collected)
                assertTrue("'${s.name}' window=$window completes", cursor.isComplete)
            }
        }
    }

    @Test fun appendEquivalence_mixedMeasurePagesAndThroughOffset_equalsIndex() = runTest {
        // A realistic session mixes both extend commands (first-window measurePages, then far-jump
        // measureThroughOffset, then background measurePages to completion). The union of sealed starts
        // still equals index() byte-for-byte with no dropped/duplicated page.
        val doc = TxtDocument.of((0 until 80).joinToString("") { "line$it\n" })
        val p = TxtPaginator(UnconfinedTestDispatcher(testScheduler))
        val m = FixedLineMeasurer(charsPerLine = 6, lineHeightPx = 10f)
        val boxPx = box(20f)
        val full = p.index(doc, style, boxPx, m, PaginationToken())
        assertTrue(full.pageCount >= 10)

        val collected = ArrayList<Int>()
        var cursor = p.freshCursor(doc, style, boxPx, m, isMarkdown = false)
        // First window.
        cursor = p.measurePages(cursor, additionalPages = TxtPaginator.DEFAULT_INITIAL_WINDOW_PAGES, token = PaginationToken()) { collected.add(it) }
        // Far jump: extend through an offset near the middle of the doc.
        val midOffset = full.pageStart(full.pageCount / 2)
        cursor = p.measureThroughOffset(cursor, targetOffset = midOffset, token = PaginationToken()) { collected.add(it) }
        // Background completion in DEFAULT_EXTEND_PAGES windows.
        while (!cursor.isComplete) {
            cursor = p.measurePages(cursor, additionalPages = TxtPaginator.DEFAULT_EXTEND_PAGES, token = PaginationToken()) { collected.add(it) }
        }
        assertEquals("mixed commands seal index()'s starts exactly", full.pageStartsUtf16.toList(), collected)
        assertEquals(doc.text.length, cursor.frontierSourceOffset)
        // No duplicate seal — the emitted list is strictly increasing.
        for (i in 1 until collected.size) {
            assertTrue("no duplicate/backward seal at $i", collected[i] > collected[i - 1])
        }
    }

    // === (5) SEALED INVARIANT (Gate-2 R1 High 3): an append never mutates a previously-emitted
    //     page's [start, end). We build the PARTIAL TxtPageIndex the session would publish at each
    //     window boundary and assert every already-sealed page's [start, end) is stable as the
    //     frontier grows. ===

    /** Build the sealed-partial [TxtPageIndex] a session would publish from a cursor + collected starts. */
    private fun partialIndex(collected: List<Int>, cursor: MeasureCursor): TxtPageIndex =
        TxtPageIndex(
            collected.toIntArray(),
            docEndExclusive = cursor.run.docEndExclusive,
            isComplete = cursor.isComplete,
            frontierSourceOffset = cursor.frontierSourceOffset,
        )

    @Test fun sealedInvariant_appendNeverMutatesAlreadySealedPageRange() = runTest {
        val doc = TxtDocument.of((0 until 70).joinToString("") { "row$it\n" })
        val p = TxtPaginator(UnconfinedTestDispatcher(testScheduler))
        val m = FixedLineMeasurer(charsPerLine = 7, lineHeightPx = 10f)
        val boxPx = box(25f)
        val full = p.index(doc, style, boxPx, m, PaginationToken())
        assertTrue(full.pageCount >= 8)

        val collected = ArrayList<Int>()
        var cursor = p.freshCursor(doc, style, boxPx, m, isMarkdown = false)
        val token = PaginationToken()

        // Snapshot every sealed page's [start, end) at each window boundary; a later append must never
        // change any range recorded earlier.
        val recorded = HashMap<Int, Pair<Int, Int>>()   // page index -> [start, end)
        var guard = 0
        while (!cursor.isComplete) {
            cursor = p.measurePages(cursor, additionalPages = 2, token = token) { collected.add(it) }
            val snapshot = partialIndex(collected, cursor)
            // Every published (sealed) page in this snapshot has a FINAL range.
            for (page in 0 until snapshot.pageCount) {
                val range = snapshot.pageStart(page) to snapshot.pageEndExclusive(page)
                val prior = recorded[page]
                if (prior != null) {
                    assertEquals("page $page start immutable across append", prior.first, range.first)
                    assertEquals("page $page end immutable across append", prior.second, range.second)
                } else {
                    recorded[page] = range
                }
            }
            if (guard++ > 1_000_000) fail("did not converge")
        }
        // Final: every sealed range equals index()'s corresponding [start, end).
        for (page in 0 until full.pageCount) {
            assertEquals("final page $page start == index()", full.pageStart(page), recorded[page]!!.first)
            assertEquals("final page $page end == index()", full.pageEndExclusive(page), recorded[page]!!.second)
        }
    }

    // === (6) extend-through-offset seals exactly enough to cover X; pageContaining(X) exact ===

    @Test fun measureThroughOffset_sealsExactlyEnoughToCoverX_pageContainingExact() = runTest {
        val doc = TxtDocument.of((0 until 60).joinToString("") { "row$it\n" })
        val p = TxtPaginator(UnconfinedTestDispatcher(testScheduler))
        val m = FixedLineMeasurer(charsPerLine = 7, lineHeightPx = 10f)
        val boxPx = box(25f)
        val full = p.index(doc, style, boxPx, m, PaginationToken())
        assertTrue(full.pageCount >= 8)

        // Sample several targets: page starts, mid-page offsets, and near-end.
        val targetPages = listOf(0, 1, 3, 5, full.pageCount / 2)
        for (tp in targetPages.distinct()) {
            val pageStart = full.pageStart(tp)
            val pageEnd = full.pageEndExclusive(tp)
            val midTarget = (pageStart + pageEnd) / 2   // an offset strictly inside page tp
            val collected = ArrayList<Int>()
            var cursor = p.freshCursor(doc, style, boxPx, m, isMarkdown = false)
            cursor = p.measureThroughOffset(cursor, targetOffset = midTarget, token = PaginationToken()) { collected.add(it) }

            // The published partial index must resolve pageContaining(midTarget) to page tp exactly.
            val snap = partialIndex(collected, cursor)
            assertEquals("pageContaining($midTarget) == $tp", tp, snap.pageContaining(midTarget))
            // Page tp is SEALED: it is a published page AND (unless the whole doc ended) its successor
            // started, so its [start, end) is final.
            assertTrue("page $tp published", snap.pageCount > tp)
            assertEquals("page $tp start exact", full.pageStart(tp), snap.pageStart(tp))
            assertEquals("page $tp end exact", full.pageEndExclusive(tp), snap.pageEndExclusive(tp))
            // Prefix equivalence with index() — no wrong start slipped in.
            for (i in collected.indices) assertEquals(full.pageStartsUtf16[i], collected[i])
            // "Exactly enough": we did not seal WILDLY past the target. The last sealed page is the
            // target page, OR at most one lookahead page beyond (its successor is the pending frontier).
            // The tight `<= tp + 2` bound holds here because this fixture is ONE line per chunk (each
            // row-chunk carries <=1 page break, so the chunk-boundary stop coincides with the coverage
            // stop). A runaway no-newline chunk could seal more in one step (documented lower-bound
            // behavior — see measurePagesK_isLowerBound_notExactCap_forRunawayChunk); the COVERAGE and
            // pageContaining(X) exactness above hold regardless.
            assertTrue(
                "sealed exactly enough to cover target (no over-run)",
                collected.size <= tp + 2,
            )
        }
    }

    // === (7) cancellation aborts a resumable pass mid-loop ===

    @Test fun cancellation_abortsResumablePassMidLoop() = runTest {
        val doc = TxtDocument.of((0 until 200).joinToString("") { "line$it\n" })
        val p = TxtPaginator(UnconfinedTestDispatcher(testScheduler))
        val m = FixedLineMeasurer(charsPerLine = 6, lineHeightPx = 10f)
        val boxPx = box(20f)

        // Seal a first window, then cancel the token and attempt a further extend: it aborts.
        val collected = ArrayList<Int>()
        var cursor = p.freshCursor(doc, style, boxPx, m, isMarkdown = false)
        val token = PaginationToken()
        cursor = p.measurePages(cursor, additionalPages = 3, token = token) { collected.add(it) }
        assertFalse("mid-book: not complete", cursor.isComplete)
        val sealedBeforeCancel = collected.size

        token.cancel()
        try {
            p.measurePages(cursor, additionalPages = 10, token = token) { collected.add(it) }
            fail("a cancelled token must abort a resumable extend")
        } catch (e: CancellationException) { /* expected */ }
        // The abort threw before sealing further pages (it aborts at the FIRST checkCancelled).
        assertEquals("no further seals after cancel", sealedBeforeCancel, collected.size)

        // measureThroughOffset is likewise abortable.
        try {
            p.measureThroughOffset(cursor, targetOffset = doc.text.length, token = token) { }
            fail("a cancelled token must abort measureThroughOffset")
        } catch (e: CancellationException) { /* expected */ }
    }

    @Test fun cancellation_midChunk_stopsFurtherStaleEmits() = runTest {
        // Gate-4 WI-3 High-2: a single runaway (no-newline) chunk carries MANY page breaks. If the token
        // is cancelled WHILE iterating that chunk's lines, no further stale starts may be emitted — the
        // per-line cancellation check aborts BEFORE the next tryStartPage. We cancel inside the emit
        // callback (after the first seal) and assert the abort throws with a bounded emit count.
        val doc = TxtDocument.of("z".repeat(3000))   // ONE chunk, ~60 measured lines → ~30 page breaks
        val p = TxtPaginator(UnconfinedTestDispatcher(testScheduler))
        val m = FixedLineMeasurer(charsPerLine = 50, lineHeightPx = 10f)
        val boxPx = box(20f)   // ~2 lines per page → the ONE chunk holds ~30 breaks
        val full = p.index(doc, style, boxPx, m, PaginationToken())
        assertTrue("precondition: one runaway chunk with many breaks", full.pageCount >= 10)
        assertEquals("precondition: exactly one chunk", 1, doc.chunkCount)

        val token = PaginationToken()
        val cursor = p.freshCursor(doc, style, boxPx, m, isMarkdown = false)
        val collected = ArrayList<Int>()
        try {
            // Ask for the whole chunk's worth of pages, but cancel after the very first seal.
            p.measurePages(cursor, additionalPages = full.pageCount, token = token) {
                collected.add(it)
                if (collected.size == 1) token.cancel()
            }
            fail("a token cancelled mid-chunk must abort the pass")
        } catch (e: CancellationException) { /* expected */ }
        // The per-line check aborted before sealing the whole runaway chunk — far fewer than pageCount.
        assertTrue("cancel mid-chunk sealed only a bounded prefix", collected.size < full.pageCount)
    }

    // === (8) min-one-line forward progress across a WINDOW boundary ===

    @Test fun minOneLine_forwardProgress_acrossWindowBoundary() = runTest {
        // Every line is taller than the box → each page holds exactly one (overflowing) line. Driven one
        // page at a time, every window still advances by >= 1 line (strictly-increasing starts, never a
        // zero-advance page) even though the pass PAUSES at each window boundary.
        val doc = TxtDocument.of((0 until 50).joinToString("") { "line-$it\n" })
        val p = TxtPaginator(UnconfinedTestDispatcher(testScheduler))
        val m = FixedLineMeasurer(charsPerLine = 100, lineHeightPx = 100f)   // 1 line/chunk, overtall
        val boxPx = box(10f)   // holds < 1 line → min-one-line kicks in on every page
        val full = p.index(doc, style, boxPx, m, PaginationToken())
        assertTrue("precondition: many min-one-line pages", full.pageCount >= 10)

        val (collected, cursor) = driveToCompletion(p, doc, boxPx, m, isMarkdown = false, window = 1)
        assertTrue(cursor.isComplete)
        assertEquals("min-one-line drive == index()", full.pageStartsUtf16.toList(), collected)
        // Strict forward progress across every window boundary — no zero-advance page.
        for (i in 1 until collected.size) {
            assertTrue("strict advance at window boundary $i", collected[i] > collected[i - 1])
        }
    }

    @Test fun minOneLine_oversizedChunk_midChunkSplit_acrossWindows() = runTest {
        // A single runaway line longer than DEFAULT_MAX_CHUNK_CHARS (4000) forces a mid-chunk split; a
        // narrow box makes many pages. Driven one page at a time, each window advances by >= 1 measured
        // line and the incremental starts equal index() byte-for-byte.
        val doc = TxtDocument.of("z".repeat(9000))
        val p = TxtPaginator(UnconfinedTestDispatcher(testScheduler))
        val m = FixedLineMeasurer(charsPerLine = 300, lineHeightPx = 10f)
        val boxPx = box(20f)   // ~2 measured lines per page
        val full = p.index(doc, style, boxPx, m, PaginationToken())
        assertTrue("precondition: multi-page from a split runaway line", full.pageCount >= 5)

        val (collected, cursor) = driveToCompletion(p, doc, boxPx, m, isMarkdown = false, window = 1)
        assertTrue(cursor.isComplete)
        assertEquals("oversized-split drive == index()", full.pageStartsUtf16.toList(), collected)
        for (i in 1 until collected.size) {
            assertTrue("strict advance across split window $i", collected[i] > collected[i - 1])
        }
        assertEquals(doc.text.length, cursor.frontierSourceOffset)
    }

    // === companion constants sanity (WI-3 added; consumed by the WI-4 session) ===

    @Test fun windowConstants_arePositive() {
        assertTrue("initial window >= 1", TxtPaginator.DEFAULT_INITIAL_WINDOW_PAGES >= 1)
        assertTrue("extend window >= 1", TxtPaginator.DEFAULT_EXTEND_PAGES >= 1)
    }
}
