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
 * Feature #138 WI-1 — the resumable measure core in [TxtPaginator].
 *
 * These tests lock the LOAD-BEARING determinism property of #138: an INCREMENTAL doc-start-forward
 * measure pass (via the internal [TxtPaginator.freshCursor] / [TxtPaginator.measurePages] /
 * [TxtPaginator.measureThroughOffset] resumable entry points) seals EXACTLY the same page starts,
 * in the same order, as the whole-document [TxtPaginator.index] pass — because the incremental
 * pass is the SAME tiling logic resumed from a cursor that descends from chunk 0, never a fork.
 *
 * The 43 pre-existing [TxtPaginatorTest] / [PageOffsetMapTest] / [TxtPageIndexTest] cases already
 * assert `index(...)` remains byte-identical after the WI-1 refactor (it is re-implemented ON the
 * core). This suite adds (a) an explicit index-vs-manual-full-drive equivalence for the tricky
 * shapes and (b) the incremental-prefix equivalence the later WIs (WI-4 session) depend on.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class TxtPaginatorResumableCoreTest {

    private val style = TextStyle()

    /** Same deterministic fake as [TxtPaginatorTest]: fixed-width lines, never splits a pair. */
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

    /**
     * Drive the resumable core to COMPLETION one page at a time (measurePages(1)) from a fresh
     * cursor, collecting every sealed start. This must equal `index(...)`'s starts EXACTLY —
     * incremental-from-chunk-0 == full pass. Returns the collected starts.
     */
    private suspend fun driveOnePageAtATime(
        p: TxtPaginator, doc: TxtDocument, boxPx: PageContentBox,
        m: LineMeasurer, isMarkdown: Boolean = false,
    ): List<Int> {
        val collected = ArrayList<Int>()
        var cursor = p.freshCursor(doc, style, boxPx, m, isMarkdown)
        val token = PaginationToken()
        var guard = 0
        while (!cursor.isComplete) {
            cursor = p.measurePages(cursor, additionalPages = 1, token = token) { start -> collected.add(start) }
            if (guard++ > 1_000_000) fail("measurePages did not converge (infinite loop guard)")
        }
        return collected
    }

    // --- byte-identical: index(...) == the one-page-at-a-time incremental drive -------------------

    @Test fun index_equals_incrementalDrive_onEveryScenario() = runTest {
        val dispatcher = UnconfinedTestDispatcher(testScheduler)
        data class Case(
            val name: String, val text: String, val heightPx: Float,
            val charsPerLine: Int, val lineHeightPx: Float = 10f, val isMarkdown: Boolean = false,
        )
        val cases = listOf(
            Case("empty", "", 30f, 100),
            Case("one-line", "hello\n", 30f, 100),
            Case("multi-page-plain", (0 until 20).joinToString("") { "row$it\n" }, 25f, 7),
            Case("oversized-4000-split", "x".repeat(4000), 30f, 500),
            Case("cjk-no-whitespace", "字".repeat(40) + "\n", 20f, 10),
            Case("surrogate-pairs", "𝕏".repeat(30) + "\n", 20f, 9),
            Case("exactly-on-boundary", (0 until 6).joinToString("") { "r$it\n" }, 30f, 100),
            Case("min-one-line-overtall", "aaaa\nbbbb\ncccc\n", 10f, 100, lineHeightPx = 100f),
            Case("one-giant-line-no-newline", "z".repeat(1200), 20f, 300),
            Case("md-bullet-narrow", "- abc\n", 10f, 1, isMarkdown = true),
        )
        for (c in cases) {
            val doc = TxtDocument.of(c.text)
            val p = TxtPaginator(dispatcher)
            val m = FixedLineMeasurer(c.charsPerLine, c.lineHeightPx)
            val full = p.index(doc, style, box(c.heightPx), m, PaginationToken(), c.isMarkdown)
            val incremental = driveOnePageAtATime(p, doc, box(c.heightPx), m, c.isMarkdown)
            assertEquals(
                "case '${c.name}': incremental starts must equal index() starts",
                full.pageStartsUtf16.toList(), incremental,
            )
        }
    }

    // --- measurePages(K) seals the same prefix as index(...) -------------------------------------

    @Test fun measurePages_sealsSamePrefixAsIndex() = runTest {
        val doc = TxtDocument.of((0 until 20).joinToString("") { "row$it\n" })
        val p = TxtPaginator(UnconfinedTestDispatcher(testScheduler))
        val m = FixedLineMeasurer(charsPerLine = 7, lineHeightPx = 10f)
        val boxPx = box(25f)
        val full = p.index(doc, style, boxPx, m, PaginationToken())
        assertTrue("precondition: multi-page", full.pageCount >= 3)

        // Seal the first 2 pages via the core; they must equal index()'s first 2 starts.
        val collected = ArrayList<Int>()
        var cursor = p.freshCursor(doc, style, boxPx, m, isMarkdown = false)
        cursor = p.measurePages(cursor, additionalPages = 2, token = PaginationToken()) { collected.add(it) }
        assertEquals(full.pageStartsUtf16[0], collected[0])
        assertEquals(full.pageStartsUtf16[1], collected[1])
        // The cursor is not complete yet (more pages remain) and its frontier advanced past page 1.
        assertFalse(cursor.isComplete)
        assertTrue(cursor.frontierSourceOffset > full.pageStartsUtf16[1])
    }

    // --- measureThroughOffset seals up to (and including the page containing) a target -----------

    @Test fun measureThroughOffset_sealsThroughTargetPage_matchingIndex() = runTest {
        val doc = TxtDocument.of((0 until 40).joinToString("") { "row$it\n" })
        val p = TxtPaginator(UnconfinedTestDispatcher(testScheduler))
        val m = FixedLineMeasurer(charsPerLine = 7, lineHeightPx = 10f)
        val boxPx = box(25f)
        val full = p.index(doc, style, boxPx, m, PaginationToken())
        assertTrue("precondition: many pages", full.pageCount >= 5)

        // Pick a target offset at page index 3's start.
        val targetPage = 3
        val target = full.pageStart(targetPage)
        val collected = ArrayList<Int>()
        var cursor = p.freshCursor(doc, style, boxPx, m, isMarkdown = false)
        cursor = p.measureThroughOffset(cursor, targetOffset = target, token = PaginationToken()) { collected.add(it) }

        // Every start sealed so far must match index()'s prefix.
        for (i in collected.indices) {
            assertEquals("start $i must match index()", full.pageStartsUtf16[i], collected[i])
        }
        // The sealed frontier must cover the target page: page 3's start is among the sealed starts.
        assertTrue("target page start must be sealed", collected.contains(full.pageStart(targetPage)))
    }

    // --- resuming from a saved cursor == continuing the same pass (no drift) ---------------------

    @Test fun resumingFromSavedCursor_matchesUninterruptedFullPass() = runTest {
        val doc = TxtDocument.of((0 until 30).joinToString("") { "line$it\n" })
        val p = TxtPaginator(UnconfinedTestDispatcher(testScheduler))
        val m = FixedLineMeasurer(charsPerLine = 6, lineHeightPx = 10f)
        val boxPx = box(20f)
        val full = p.index(doc, style, boxPx, m, PaginationToken())

        // Drive: 1 page, then 3 pages, then to completion — collected must equal the full starts.
        val collected = ArrayList<Int>()
        var cursor = p.freshCursor(doc, style, boxPx, m, isMarkdown = false)
        cursor = p.measurePages(cursor, additionalPages = 1, token = PaginationToken()) { collected.add(it) }
        cursor = p.measurePages(cursor, additionalPages = 3, token = PaginationToken()) { collected.add(it) }
        while (!cursor.isComplete) {
            cursor = p.measurePages(cursor, additionalPages = 5, token = PaginationToken()) { collected.add(it) }
        }
        assertEquals(full.pageStartsUtf16.toList(), collected)
        assertEquals(doc.text.length, cursor.frontierSourceOffset)  // frontier == doc end when complete
    }

    // --- a completed cursor is a no-op (idempotent) ---------------------------------------------

    @Test fun measuringPastCompletion_isNoOp() = runTest {
        val doc = TxtDocument.of("aaaa\nbbbb\n")
        val p = TxtPaginator(UnconfinedTestDispatcher(testScheduler))
        val m = FixedLineMeasurer(charsPerLine = 100, lineHeightPx = 10f)
        val boxPx = box(30f)
        var cursor = p.freshCursor(doc, style, boxPx, m, isMarkdown = false)
        // Drive to completion.
        while (!cursor.isComplete) {
            cursor = p.measurePages(cursor, additionalPages = 100, token = PaginationToken()) { }
        }
        assertTrue(cursor.isComplete)
        // Further measure calls emit NOTHING and leave the cursor complete.
        val extra = ArrayList<Int>()
        val after = p.measurePages(cursor, additionalPages = 10, token = PaginationToken()) { extra.add(it) }
        assertTrue(extra.isEmpty())
        assertTrue(after.isComplete)
        val after2 = p.measureThroughOffset(cursor, targetOffset = 9999, token = PaginationToken()) { extra.add(it) }
        assertTrue(extra.isEmpty())
        assertTrue(after2.isComplete)
    }

    // --- empty + degenerate docs via the core ---------------------------------------------------

    @Test fun emptyDoc_freshCursor_completesWithZeroStarts() = runTest {
        val doc = TxtDocument.of("")
        val p = TxtPaginator(UnconfinedTestDispatcher(testScheduler))
        val m = FixedLineMeasurer(charsPerLine = 100)
        var cursor = p.freshCursor(doc, style, box(30f), m, isMarkdown = false)
        val collected = ArrayList<Int>()
        cursor = p.measurePages(cursor, additionalPages = 10, token = PaginationToken()) { collected.add(it) }
        assertTrue("empty doc completes immediately", cursor.isComplete)
        assertTrue("empty doc seals no pages", collected.isEmpty())
    }

    @Test fun degenerateBox_freshCursor_completesWithZeroStarts() = runTest {
        val doc = TxtDocument.of("aaaa\nbbbb\n")
        val p = TxtPaginator(UnconfinedTestDispatcher(testScheduler))
        val m = FixedLineMeasurer(charsPerLine = 100)
        var cursor = p.freshCursor(doc, style, box(0f), m, isMarkdown = false)
        val collected = ArrayList<Int>()
        cursor = p.measurePages(cursor, additionalPages = 10, token = PaginationToken()) { collected.add(it) }
        assertTrue("degenerate box completes immediately", cursor.isComplete)
        assertTrue("degenerate box seals no pages", collected.isEmpty())
    }

    // --- cancellation aborts the incremental core too -------------------------------------------

    @Test fun cancelledToken_abortsMeasurePages() = runTest {
        val doc = TxtDocument.of((0 until 100).joinToString("") { "line$it\n" })
        val p = TxtPaginator(UnconfinedTestDispatcher(testScheduler))
        val m = FixedLineMeasurer(charsPerLine = 100)
        val cursor = p.freshCursor(doc, style, box(30f), m, isMarkdown = false)
        val token = PaginationToken().apply { cancel() }
        try {
            p.measurePages(cursor, additionalPages = 1, token = token) { }
            fail("a cancelled token must abort the incremental core")
        } catch (e: CancellationException) { /* expected */ }
    }

    // --- SEALED-PAGE model (Gate-2 R2 Medium 1 / audit r1 Critical): a page is emitted only once
    //     its exclusive end is FINAL — for a non-final page that means its successor's start is known;
    //     the final page seals at doc end. A page start is NEVER emitted before it is sealed. --------

    @Test fun sealedEmit_page0NotSealedUntilPage1StartKnown_plusOneLookahead() = runTest {
        // A 5-page doc. Sealing ONLY page 0 requires knowing page 1's start; measurePages(1) seals at
        // least page 0 and its emit is exactly page 0's start — never a not-yet-sealed frontier page.
        val doc = TxtDocument.of((0 until 30).joinToString("") { "row$it\n" })
        val p = TxtPaginator(UnconfinedTestDispatcher(testScheduler))
        val m = FixedLineMeasurer(charsPerLine = 7, lineHeightPx = 10f)
        val boxPx = box(25f)
        val full = p.index(doc, style, boxPx, m, PaginationToken())
        assertTrue(full.pageCount >= 3)

        val collected = ArrayList<Int>()
        var cursor = p.freshCursor(doc, style, boxPx, m, isMarkdown = false)
        cursor = p.measurePages(cursor, additionalPages = 1, token = PaginationToken()) { collected.add(it) }
        // At least page 0 sealed, and every emitted start equals index()'s value (sealed, not a
        // frontier). The pending page (currentPageStart, exposed as frontierSourceOffset) is the NEXT
        // start and is NOT among the emitted starts — the +1-page lookahead.
        assertTrue("page 0 sealed", collected.isNotEmpty())
        assertEquals(full.pageStart(0), collected[0])
        assertFalse("the pending frontier start is NOT emitted", collected.contains(cursor.frontierSourceOffset))
        // The frontier == the exclusive end of the last sealed page == the next sealed page's start.
        assertEquals(full.pageStart(collected.size), cursor.frontierSourceOffset)
    }

    @Test fun sealedEmit_onePageDoc_sealsOnlyAtDocEnd() = runTest {
        // A doc that fits in ONE page: page 0's start is 0, but it cannot seal until doc end (there is
        // no successor start). measurePages(1) must therefore drive to completion and emit exactly [0].
        val doc = TxtDocument.of("hello world\n")
        val p = TxtPaginator(UnconfinedTestDispatcher(testScheduler))
        val m = FixedLineMeasurer(charsPerLine = 100, lineHeightPx = 10f)
        val boxPx = box(100f)   // holds the single line comfortably
        val full = p.index(doc, style, boxPx, m, PaginationToken())
        assertEquals("precondition: exactly one page", 1, full.pageCount)

        val collected = ArrayList<Int>()
        var cursor = p.freshCursor(doc, style, boxPx, m, isMarkdown = false)
        cursor = p.measurePages(cursor, additionalPages = 1, token = PaginationToken()) { collected.add(it) }
        assertTrue("one-page doc completes to seal its only page", cursor.isComplete)
        assertEquals(listOf(0), collected)                       // exactly page 0, sealed at doc end
        assertEquals(doc.text.length, cursor.frontierSourceOffset)
    }

    @Test fun measureThroughOffset_exactPageBoundary_sealsPageContainingTarget() = runTest {
        // Target EXACTLY at a page boundary (a page start). The page CONTAINING that offset is the page
        // that STARTS there; it is sealed only once its successor starts — the offset's page is sealed.
        val doc = TxtDocument.of((0 until 40).joinToString("") { "row$it\n" })
        val p = TxtPaginator(UnconfinedTestDispatcher(testScheduler))
        val m = FixedLineMeasurer(charsPerLine = 7, lineHeightPx = 10f)
        val boxPx = box(25f)
        val full = p.index(doc, style, boxPx, m, PaginationToken())
        assertTrue(full.pageCount >= 5)

        val targetPage = 3
        val target = full.pageStart(targetPage)   // EXACTLY on page 3's boundary
        val collected = ArrayList<Int>()
        var cursor = p.freshCursor(doc, style, boxPx, m, isMarkdown = false)
        cursor = p.measureThroughOffset(cursor, targetOffset = target, token = PaginationToken()) { collected.add(it) }
        // Page 3 (the page whose [start, end) contains `target`) must be SEALED: its start is emitted,
        // AND the successor (page 4) has started (frontier past page 3's start) — so the range is final.
        assertTrue("page 3 start sealed", collected.contains(full.pageStart(targetPage)))
        if (!cursor.isComplete) {
            assertTrue("page 3 sealed (successor started)", cursor.frontierSourceOffset > target)
        }
        // Prefix equivalence with index().
        for (i in collected.indices) assertEquals(full.pageStartsUtf16[i], collected[i])
    }

    @Test fun measurePages_zeroOrNegative_isNoOp() = runTest {
        val doc = TxtDocument.of((0 until 10).joinToString("") { "row$it\n" })
        val p = TxtPaginator(UnconfinedTestDispatcher(testScheduler))
        val m = FixedLineMeasurer(charsPerLine = 7, lineHeightPx = 10f)
        val boxPx = box(25f)
        val cursor = p.freshCursor(doc, style, boxPx, m, isMarkdown = false)
        val collected = ArrayList<Int>()
        val after0 = p.measurePages(cursor, additionalPages = 0, token = PaginationToken()) { collected.add(it) }
        val afterNeg = p.measurePages(cursor, additionalPages = -5, token = PaginationToken()) { collected.add(it) }
        assertTrue("measurePages(0) emits nothing", collected.isEmpty())
        assertEquals("measurePages(0) does not advance the cursor", cursor, after0)
        assertEquals("measurePages(<0) does not advance the cursor", cursor, afterNeg)
        assertFalse(after0.isComplete)
    }

    @Test fun measureThroughOffset_negativeTarget_clampsToStart_sealsFirstPage() = runTest {
        // A negative offset clamps to 0: seal through the page containing offset 0 (page 0).
        val doc = TxtDocument.of((0 until 20).joinToString("") { "row$it\n" })
        val p = TxtPaginator(UnconfinedTestDispatcher(testScheduler))
        val m = FixedLineMeasurer(charsPerLine = 7, lineHeightPx = 10f)
        val boxPx = box(25f)
        val full = p.index(doc, style, boxPx, m, PaginationToken())
        val collected = ArrayList<Int>()
        var cursor = p.freshCursor(doc, style, boxPx, m, isMarkdown = false)
        cursor = p.measureThroughOffset(cursor, targetOffset = -100, token = PaginationToken()) { collected.add(it) }
        assertTrue("page 0 sealed after clamped negative target", collected.contains(full.pageStart(0)))
        assertEquals(full.pageStart(0), collected[0])
    }
}
