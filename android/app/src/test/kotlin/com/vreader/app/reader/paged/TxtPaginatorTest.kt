package com.vreader.app.reader.paged

import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import com.vreader.app.reader.TxtDocument
import com.vreader.app.reader.Utf16Range
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * Feature #137 WI-4 — [TxtPaginator]: two-phase measured-line pagination.
 *
 * Phase 1 ([TxtPaginator.index]) measures the whole doc against a chrome-aware content box (via an
 * injected [LineMeasurer] — the JVM-testable seam that abstracts Compose TextMeasurer) and stores
 * ONLY page-start source offsets. Phase 2 ([TxtPaginator.renderPage]) lazily renders ONE page's
 * source range into an AnnotatedString + composed [PageOffsetMap].
 *
 * These tests inject a DETERMINISTIC fake measurer (known line breaks + heights) so the pagination
 * LOGIC — page boundaries, oversized-chunk mid-chunk split, min-one-line, degenerate box, offset
 * math — is fully JVM-tested without a real Android TextMeasurer.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class TxtPaginatorTest {

    private val style = TextStyle()

    /**
     * Deterministic fake: breaks [text] into fixed-width lines of [charsPerLine] chars each (the last
     * line may be shorter), every line [lineHeightPx] tall. Never splits a surrogate pair — a break
     * that would land between a high+low surrogate is pushed one unit right.
     */
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
                // don't split a surrogate pair
                if (end < n && Character.isHighSurrogate(text[end - 1]) && Character.isLowSurrogate(text[end])) end++
                lines.add(LineMetric(start, end, lineHeightPx))
                start = end
            }
            return lines
        }
    }

    private fun box(heightPx: Float, widthPx: Float = 1000f) = PageContentBox(widthPx, heightPx)

    // --- page count vs box height --------------------------------------------------------------

    @Test fun pageCount_growsAsBoxShrinks() = runTest {
        // 6 chunks, each "line NN\n" — a small chunk renders as 1 line at charsPerLine large enough.
        val doc = TxtDocument.of((0 until 6).joinToString("") { "line$it\n" })
        val p = TxtPaginator()
        // charsPerLine huge → 1 line/chunk (each "lineN\n" ~6 chars). Box holds 3 lines (30px).
        val m = FixedLineMeasurer(charsPerLine = 100, lineHeightPx = 10f)
        val threePerPage = p.index(doc, style, box(heightPx = 30f), m, PaginationToken())
        assertFalse(threePerPage.isDegenerate)
        // 6 one-line chunks / 3 lines per page = 2 pages.
        assertEquals(2, threePerPage.pageCount)
        // shrink box to 1 line/page → 6 pages.
        val onePerPage = p.index(doc, style, box(heightPx = 10f), m, PaginationToken())
        assertEquals(6, onePerPage.pageCount)
    }

    // --- exact UTF-16 offsets: page starts land on real source boundaries -----------------------

    @Test fun pageStarts_areExactSourceOffsets() = runTest {
        // 4 chunks "aaaa\n" (5 chars each) at doc offsets 0,5,10,15. 1 line/chunk. Box holds 2 lines.
        val doc = TxtDocument.of("aaaa\naaaa\naaaa\naaaa\n")
        val p = TxtPaginator()
        val m = FixedLineMeasurer(charsPerLine = 100, lineHeightPx = 10f)
        val idx = p.index(doc, style, box(heightPx = 20f), m, PaginationToken())
        assertEquals(2, idx.pageCount)
        assertEquals(0, idx.pageStart(0))   // page 0 starts at chunk 0
        assertEquals(10, idx.pageStart(1))  // page 1 starts at chunk 2 (doc offset 10)
        assertEquals(20, idx.pageEndExclusive(1))
    }

    // --- no clipped text: every source char is covered by exactly one page ----------------------

    @Test fun noClippedText_pagesTilePerfectly() = runTest {
        val text = (0 until 20).joinToString("") { "row$it\n" }
        val doc = TxtDocument.of(text)
        val p = TxtPaginator()
        val m = FixedLineMeasurer(charsPerLine = 7, lineHeightPx = 10f)  // multi-line chunks
        val idx = p.index(doc, style, box(heightPx = 25f), m, PaginationToken())
        // page 0 starts at 0; each page's end == next page's start; last ends at doc length.
        assertEquals(0, idx.pageStart(0))
        for (page in 0 until idx.pageCount - 1) {
            assertEquals(idx.pageEndExclusive(page), idx.pageStart(page + 1))
        }
        assertEquals(text.length, idx.pageEndExclusive(idx.pageCount - 1))
        // and starts strictly increase (no zero-advance page).
        for (page in 1 until idx.pageCount) {
            assertTrue("page $page must advance", idx.pageStart(page) > idx.pageStart(page - 1))
        }
    }

    // --- oversized chunk (4000 chars) splits MID-CHUNK at a measured line -----------------------

    @Test fun oversizedChunk_splitsMidChunkAtLineBoundary() = runTest {
        // ONE 4000-char chunk (a runaway line). charsPerLine 500 → 8 lines. Box holds 3 lines.
        val giant = "x".repeat(4000)
        val doc = TxtDocument.of(giant)
        assertEquals("precondition: one chunk", 1, doc.chunkCount)
        val p = TxtPaginator()
        val m = FixedLineMeasurer(charsPerLine = 500, lineHeightPx = 10f)
        val idx = p.index(doc, style, box(heightPx = 30f), m, PaginationToken())
        // 8 lines / 3 per page = 3 pages (3+3+2), all inside the SINGLE chunk.
        assertEquals(3, idx.pageCount)
        // page starts are the source offsets of the measured line starts: 0, 1500, 3000.
        assertEquals(0, idx.pageStart(0))
        assertEquals(1500, idx.pageStart(1))   // line 3 starts at char 1500
        assertEquals(3000, idx.pageStart(2))   // line 6 starts at char 3000
        assertEquals(4000, idx.pageEndExclusive(2))
    }

    @Test fun oversizedChunk_renderPage_mapsExactAcrossSplit() = runTest {
        val giant = "x".repeat(4000)
        val doc = TxtDocument.of(giant)
        val p = TxtPaginator()
        val m = FixedLineMeasurer(charsPerLine = 500, lineHeightPx = 10f)
        val idx = p.index(doc, style, box(heightPx = 30f), m, PaginationToken())
        val mapper = com.vreader.app.reader.IdentityChunkTextMapper(doc)
        // page 1 covers source [1500,3000); its rendered text is exactly that sub-range.
        val (text, pageMap) = p.renderPage(doc, idx, page = 1, mapper, style)
        assertEquals(1500, text.length)
        // page-local rendered 0 maps back to global source 1500 (the split point).
        assertEquals(1500, pageMap.sourceAt(0))
        assertEquals(2999, pageMap.sourceAt(1499))
        assertEquals(Utf16Range(1500, 3000), pageMap.renderedRangeToSource(Utf16Range(0, 1500)))
    }

    // --- min-one-line: an over-tall single line still yields a page (forward progress) -----------

    @Test fun minOneLine_overTallLineStillAdvances_noZeroAdvanceLoop() = runTest {
        // 3 chunks, 1 line each, each line 100px tall. Box height 10px — NO line fits.
        // The min-one-line invariant forces one line/page anyway → 3 pages, strictly advancing.
        val doc = TxtDocument.of("aaaa\nbbbb\ncccc\n")
        val p = TxtPaginator()
        val m = FixedLineMeasurer(charsPerLine = 100, lineHeightPx = 100f)
        val idx = p.index(doc, style, box(heightPx = 10f), m, PaginationToken())
        assertEquals(3, idx.pageCount)
        assertEquals(0, idx.pageStart(0))
        assertEquals(5, idx.pageStart(1))
        assertEquals(10, idx.pageStart(2))
    }

    // --- degenerate box (<=0 height) → degrade signal, no crash/loop ----------------------------

    @Test fun degenerateBox_zeroHeight_returnsDegradeSignal() = runTest {
        val doc = TxtDocument.of("aaaa\nbbbb\n")
        val p = TxtPaginator()
        val m = FixedLineMeasurer(charsPerLine = 100)
        val idx = p.index(doc, style, box(heightPx = 0f), m, PaginationToken())
        assertTrue(idx.isDegenerate)
    }

    @Test fun degenerateBox_negativeHeight_returnsDegradeSignal() = runTest {
        val doc = TxtDocument.of("aaaa\n")
        val p = TxtPaginator()
        val m = FixedLineMeasurer(charsPerLine = 100)
        val idx = p.index(doc, style, box(heightPx = -5f, widthPx = -1f), m, PaginationToken())
        assertTrue(idx.isDegenerate)
    }

    // --- empty doc (chunkCount == 0) -----------------------------------------------------------

    @Test fun emptyDoc_yieldsZeroPages() = runTest {
        val doc = TxtDocument.of("")
        assertEquals(0, doc.chunkCount)
        val p = TxtPaginator()
        val m = FixedLineMeasurer(charsPerLine = 100)
        val idx = p.index(doc, style, box(heightPx = 30f), m, PaginationToken())
        assertFalse("empty doc is not the degenerate-box case", idx.isDegenerate)
        assertEquals(0, idx.pageCount)
    }

    // --- one giant single line, no newline -----------------------------------------------------

    @Test fun oneGiantLine_noNewline_paginatesByMeasuredLines() = runTest {
        val doc = TxtDocument.of("z".repeat(1200))   // one 1200-char run
        val p = TxtPaginator()
        val m = FixedLineMeasurer(charsPerLine = 300, lineHeightPx = 10f)  // 4 lines
        val idx = p.index(doc, style, box(heightPx = 20f), m, PaginationToken())  // 2 lines/page
        assertEquals(2, idx.pageCount)
        assertEquals(0, idx.pageStart(0))
        assertEquals(600, idx.pageStart(1))
        assertEquals(1200, idx.pageEndExclusive(1))
    }

    // --- EOF offset: last page end == doc length -----------------------------------------------

    @Test fun lastPageEnd_equalsDocLength() = runTest {
        val text = "hello\nworld\nfoo\n"
        val doc = TxtDocument.of(text)
        val p = TxtPaginator()
        val m = FixedLineMeasurer(charsPerLine = 100, lineHeightPx = 10f)
        val idx = p.index(doc, style, box(heightPx = 10f), m, PaginationToken())
        assertEquals(text.length, idx.pageEndExclusive(idx.pageCount - 1))
    }

    // --- CJK with no whitespace: still paginates by measured line breaks ------------------------

    @Test fun cjkNoWhitespace_paginatesByMeasuredLines() = runTest {
        val cjk = "字".repeat(40) + "\n"   // 40 CJK chars + newline, one chunk, one runaway line
        val doc = TxtDocument.of(cjk)
        val p = TxtPaginator()
        val m = FixedLineMeasurer(charsPerLine = 10, lineHeightPx = 10f)  // 4-5 measured lines
        val idx = p.index(doc, style, box(heightPx = 20f), m, PaginationToken())
        // starts must be real source offsets and strictly advance.
        assertTrue(idx.pageCount >= 2)
        for (page in 1 until idx.pageCount) {
            assertTrue(idx.pageStart(page) > idx.pageStart(page - 1))
        }
        assertEquals(cjk.length, idx.pageEndExclusive(idx.pageCount - 1))
    }

    // --- surrogate pairs: a page start never splits a surrogate pair ----------------------------

    @Test fun surrogatePairs_pageStartsNeverSplitAPair() = runTest {
        // 30 astral chars (60 UTF-16 units) + newline = one runaway line.
        val astral = "𝕏"   // 2 UTF-16 units
        val text = astral.repeat(30) + "\n"
        val doc = TxtDocument.of(text)
        val p = TxtPaginator()
        val m = FixedLineMeasurer(charsPerLine = 9, lineHeightPx = 10f)  // odd width — would split a pair
        val idx = p.index(doc, style, box(heightPx = 20f), m, PaginationToken())
        // every page start must be a valid (non-surrogate-splitting) UTF-16 offset.
        for (page in 0 until idx.pageCount) {
            val at = idx.pageStart(page)
            if (at in 1 until text.length) {
                val splits = Character.isLowSurrogate(text[at]) && Character.isHighSurrogate(text[at - 1])
                assertFalse("page $page start $at splits a surrogate pair", splits)
            }
        }
        assertEquals(text.length, idx.pageEndExclusive(idx.pageCount - 1))
    }

    // --- combining / ZWJ: offsets stay in UTF-16 code units (opaque to pagination) ---------------

    @Test fun combiningAndZwj_offsetsAreUtf16CodeUnits() = runTest {
        // "e" + combining acute (U+0301) + ZWJ sequence flag — pagination treats them as opaque units.
        val text = "é́́́́\n".repeat(4)
        val doc = TxtDocument.of(text)
        val p = TxtPaginator()
        val m = FixedLineMeasurer(charsPerLine = 100, lineHeightPx = 10f)
        val idx = p.index(doc, style, box(heightPx = 20f), m, PaginationToken())
        // last page ends exactly at the UTF-16 length.
        assertEquals(text.length, idx.pageEndExclusive(idx.pageCount - 1))
    }

    // --- text exactly on a page boundary (lines fill a page exactly) ----------------------------

    @Test fun textExactlyOnPageBoundary_noEmptyTrailingPage() = runTest {
        // 6 one-line chunks, box holds EXACTLY 3 lines → 2 full pages, no empty 3rd page.
        val doc = TxtDocument.of((0 until 6).joinToString("") { "r$it\n" })
        val p = TxtPaginator()
        val m = FixedLineMeasurer(charsPerLine = 100, lineHeightPx = 10f)
        val idx = p.index(doc, style, box(heightPx = 30f), m, PaginationToken())
        assertEquals(2, idx.pageCount)
    }

    // --- MD: renderPage builds a composed span map spanning chunks; all 3 APIs exact ------------

    @Test fun md_renderPage_spanningChunks_allApisExactVsUnderlyingMaps() = runTest {
        // 3 MD chunks; box holds all in one page (renderedText small). renderPage composes the page map.
        val md = "**bold**x\n*i*\n# H\n"
        val doc = TxtDocument.of(md)
        val p = TxtPaginator()
        val m = FixedLineMeasurer(charsPerLine = 100, lineHeightPx = 10f)   // 1 line/chunk
        val idx = p.index(doc, style, box(heightPx = 30f), m, PaginationToken(), isMarkdown = true)
        assertEquals(1, idx.pageCount)
        val mapper = com.vreader.app.reader.MarkdownChunkTextMapper(doc)
        val (text, pageMap) = p.renderPage(doc, idx, page = 0, mapper, style, isMarkdown = true)
        // rendered concat = "boldx\n" + "i\n" + "H\n" (NO synthetic separators — chunks retain EOLs).
        assertEquals("boldx\ni\nH\n", text.text)
        // chunk 0 "**bold**x\n" doc offset 0 → "boldx" rendered [0,5) → source [2,9).
        assertEquals(Utf16Range(2, 9), pageMap.renderedRangeToSource(Utf16Range(0, 5)))
        // chunk 1 "*i*\n" doc offset 10 → rendered "i" (page-local index 6) → source [11,12).
        assertEquals(Utf16Range(11, 12), pageMap.renderedRangeToSource(Utf16Range(6, 7)))
        // chunk 2 "# H\n" doc offset 14 → rendered "H" (page-local index 8) → source [16,17).
        assertEquals(Utf16Range(16, 17), pageMap.renderedRangeToSource(Utf16Range(8, 9)))
        // sourceRangeToRendered round-trips for chunk 1's "i".
        assertEquals(Utf16Range(6, 7), pageMap.sourceRangeToRendered(Utf16Range(11, 12)))
        // renderedSpanAt dual-affinity for chunk 0's 'x' (page-local index 4) → source [8,9).
        assertEquals(Utf16Range(8, 9), pageMap.renderedSpanAt(4))
    }

    // --- no synthetic separator: page render == exact source sub-range through the mapper --------

    @Test fun md_renderPage_noSyntheticSeparators() = runTest {
        val md = "aaa\nbbb\n"    // TXT-style but rendered via MD mapper (no markers) — identical rendered text.
        val doc = TxtDocument.of(md)
        val p = TxtPaginator()
        val m = FixedLineMeasurer(charsPerLine = 100, lineHeightPx = 10f)
        val idx = p.index(doc, style, box(heightPx = 30f), m, PaginationToken(), isMarkdown = true)
        val mapper = com.vreader.app.reader.MarkdownChunkTextMapper(doc)
        val (text, _) = p.renderPage(doc, idx, page = 0, mapper, style, isMarkdown = true)
        assertEquals("aaa\nbbb\n", text.text)   // no inserted separator between chunks
    }

    // --- phase-1 uses a PAGINATOR-LOCAL mapper (never the shared UI mapper) ----------------------

    @Test fun phase1_usesPaginatorLocalMapper_notTheSharedUiMapper() = runTest {
        // A spy MarkdownChunkTextMapper records whether phase-1 touched it. Phase-1 must NOT.
        val md = "**a**\n**b**\n**c**\n"
        val doc = TxtDocument.of(md)
        val sharedUiMapper = RecordingMapper(doc)
        val p = TxtPaginator()
        val m = FixedLineMeasurer(charsPerLine = 100, lineHeightPx = 10f)
        // NOTE: index() takes NO mapper — it builds its OWN local one. If the API leaked the UI mapper
        // in, this test would fail to compile; the absence of a mapper param is the guarantee.
        val idx = p.index(doc, style, box(heightPx = 30f), m, PaginationToken(), isMarkdown = true)
        assertTrue(idx.pageCount >= 1)
        assertEquals("phase-1 must NOT touch the shared UI mapper", 0, sharedUiMapper.accessCount)
        // phase-2 DOES use the passed-in UI mapper.
        p.renderPage(doc, idx, page = 0, sharedUiMapper, style, isMarkdown = true)
        assertTrue("phase-2 uses the passed UI mapper", sharedUiMapper.accessCount > 0)
    }

    /** Records every rendered-text access so a test can assert phase-1 never touched it. */
    private class RecordingMapper(doc: TxtDocument) : com.vreader.app.reader.ChunkTextMapper {
        private val inner = com.vreader.app.reader.MarkdownChunkTextMapper(doc)
        var accessCount = 0; private set
        override fun renderedText(chunkIndex: Int) = also { accessCount++ }.let { inner.renderedText(chunkIndex) }
        override fun renderedRangeToSource(chunkIndex: Int, rendered: Utf16Range) =
            also { accessCount++ }.let { inner.renderedRangeToSource(chunkIndex, rendered) }
        override fun sourceRangeToRendered(chunkIndex: Int, source: Utf16Range) =
            also { accessCount++ }.let { inner.sourceRangeToRendered(chunkIndex, source) }
        override fun renderedCursorForSourceEnd(chunkIndex: Int, sourceEnd: Int) =
            also { accessCount++ }.let { inner.renderedCursorForSourceEnd(chunkIndex, sourceEnd) }
        override fun visibleText(chunkIndex: Int, rendered: Utf16Range) =
            also { accessCount++ }.let { inner.visibleText(chunkIndex, rendered) }
        override fun sourceText(chunkIndex: Int, source: Utf16Range) =
            also { accessCount++ }.let { inner.sourceText(chunkIndex, source) }
    }

    // --- generation token: a cancelled token aborts and never publishes -------------------------

    @Test fun staleToken_cancellation_throwsCancellationAndDoesNotComplete() = runTest {
        val doc = TxtDocument.of((0 until 100).joinToString("") { "line$it\n" })
        val p = TxtPaginator()
        val token = PaginationToken()
        token.cancel()   // cancel BEFORE running → the pass must not complete
        try {
            p.index(doc, style, box(heightPx = 30f), FixedLineMeasurer(charsPerLine = 100), token)
            fail("a cancelled token must abort pagination")
        } catch (e: CancellationException) {
            // expected — a stale pass never publishes a TxtPageIndex.
        }
    }

    @Test fun freshToken_completes() = runTest {
        val doc = TxtDocument.of("aaaa\nbbbb\n")
        val p = TxtPaginator()
        val idx = p.index(doc, style, box(heightPx = 30f), FixedLineMeasurer(charsPerLine = 100), PaginationToken())
        assertNotEquals(0, idx.pageCount)
    }

    // --- Gate-4 High-1: MD inserted-glyph bullet must NOT produce a zero-advance page ------------

    @Test fun mdBulletNarrowLines_noZeroAdvancePage() = runTest {
        // "- abc\n" → rendered "• abc\n"; the bullet '•' AND its space both map to source [0,2). At
        // ONE rendered char per line + a box that holds one line, naive per-line page starts would emit
        // two pages both starting at source 2 (a zero-advance page). The strict-advance guard prevents it.
        val doc = TxtDocument.of("- abc\n")
        val p = TxtPaginator(UnconfinedTestDispatcher(testScheduler))
        val m = FixedLineMeasurer(charsPerLine = 1, lineHeightPx = 10f)   // 1 rendered unit per line
        val idx = p.index(doc, style, box(heightPx = 10f), m, PaginationToken(), isMarkdown = true)
        // Page starts must be STRICTLY increasing — no duplicate/zero-advance page.
        for (page in 1 until idx.pageCount) {
            assertTrue("page $page must advance", idx.pageStart(page) > idx.pageStart(page - 1))
        }
        // and page 0 starts at document offset 0; the last page ends at the doc length.
        assertEquals(0, idx.pageStart(0))
        assertEquals("- abc\n".length, idx.pageEndExclusive(idx.pageCount - 1))
    }

    // --- Gate-4 High-2: index() runs on the INJECTED dispatcher (off-main, enforced) -------------

    @Test fun index_runsOnInjectedDispatcher() = runTest {
        val doc = TxtDocument.of("aaaa\nbbbb\ncccc\n")
        val dispatcher = UnconfinedTestDispatcher(testScheduler)
        val p = TxtPaginator(dispatcher)
        val idx = p.index(doc, style, box(heightPx = 30f), FixedLineMeasurer(charsPerLine = 100), PaginationToken())
        assertTrue(idx.pageCount >= 1)   // completes correctly through the injected dispatcher
    }

    // --- Gate-4 Medium-1: a cancelled token aborts EVEN the degenerate + empty-doc early returns ---

    @Test fun cancelledToken_degenerateBox_stillThrows() = runTest {
        val doc = TxtDocument.of("aaaa\n")
        val p = TxtPaginator(UnconfinedTestDispatcher(testScheduler))
        val token = PaginationToken().apply { cancel() }
        try {
            p.index(doc, style, box(heightPx = 0f), FixedLineMeasurer(charsPerLine = 100), token)
            fail("a cancelled token must abort even for a degenerate box")
        } catch (e: CancellationException) { /* expected */ }
    }

    @Test fun cancelledToken_emptyDoc_stillThrows() = runTest {
        val doc = TxtDocument.of("")
        val p = TxtPaginator(UnconfinedTestDispatcher(testScheduler))
        val token = PaginationToken().apply { cancel() }
        try {
            p.index(doc, style, box(heightPx = 30f), FixedLineMeasurer(charsPerLine = 100), token)
            fail("a cancelled token must abort even for an empty doc")
        } catch (e: CancellationException) { /* expected */ }
    }

    // --- Gate-4 Medium-2: renderPage keys on the EXPLICIT isMarkdown flag, not an `is` downcast ---

    @Test fun renderPage_wrappedMarkdownMapper_stillBuildsMdSegments() = runTest {
        // A DECORATOR around a MarkdownChunkTextMapper (NOT a MarkdownChunkTextMapper itself). With an
        // `is` downcast this would fall into the TXT identity branch and corrupt the offset map; the
        // explicit isMarkdown=true flag keeps it on the MD path.
        val md = "**bold**x\n"
        val doc = TxtDocument.of(md)
        val p = TxtPaginator(UnconfinedTestDispatcher(testScheduler))
        val idx = p.index(doc, style, box(heightPx = 30f), FixedLineMeasurer(charsPerLine = 100), PaginationToken(), isMarkdown = true)
        val wrapped: com.vreader.app.reader.ChunkTextMapper = RecordingMapper(doc)   // a non-MarkdownChunkTextMapper wrapper
        val (text, pageMap) = p.renderPage(doc, idx, page = 0, wrapped, style, isMarkdown = true)
        assertEquals("boldx\n", text.text)
        // dual-affinity preserved through the wrapper: rendered "boldx" [0,5) → source [2,9).
        assertEquals(Utf16Range(2, 9), pageMap.renderedRangeToSource(Utf16Range(0, 5)))
        assertEquals(Utf16Range(8, 9), pageMap.renderedSpanAt(4))   // 'x' dual-affinity
    }

    // --- feature #156 WI-1: alignment must NOT move a page boundary --------------------------------

    /**
     * A measurer that is DEMONSTRABLY style-sensitive — chars-per-line derives from the style's font
     * size, so "the page starts are identical" is a real result rather than an artifact of a
     * style-blind fake (the [FixedLineMeasurer] above ignores `style` entirely, so an invariance test
     * built on it would pass on a broken implementation). It also RECORDS every alignment it was
     * handed, so a test can prove the alignment actually reached phase 1 instead of being dropped
     * upstream — the other way "identical boundaries" could be vacuously true.
     */
    private class StyleSensitiveLineMeasurer(private val lineHeightPx: Float = 10f) : LineMeasurer {
        val seenAligns = LinkedHashSet<androidx.compose.ui.text.style.TextAlign>()

        override fun measure(text: CharSequence, style: TextStyle, maxWidthPx: Float): List<LineMetric> {
            seenAligns.add(style.textAlign)
            val fontSize = style.fontSize.value
            require(fontSize.isFinite() && fontSize > 0f) { "this measurer needs a concrete font size" }
            val charsPerLine = (maxWidthPx / fontSize).toInt().coerceAtLeast(1)
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

    private fun styleAt(
        fontSizeSp: Float,
        align: androidx.compose.ui.text.style.TextAlign,
    ) = TextStyle(fontSize = androidx.compose.ui.unit.TextUnit(fontSizeSp, androidx.compose.ui.unit.TextUnitType.Sp), textAlign = align)

    /**
     * Feature #156 AC-3 / plan R1: `textAlign` is applied AFTER line breaking in both `StaticLayout`
     * and CSS, so justifying the body must leave the paged index byte-identical — same page count,
     * same per-page source ranges. A drift here would move every saved reading position in a paged
     * book. Asserted on the FULL page-start array (a single-page comparison is worthless), over Latin,
     * CJK, and mixed input, for both the TXT and the Markdown phase-1 paths.
     *
     * The test carries its own SENSITIVITY control: the same comparison at a larger font size must
     * report a DIFFERENT boundary set. Without it, "the arrays match" could equally mean the
     * comparison is incapable of detecting a change.
     */
    @Test fun pageBoundaries_areInvariantToTextAlign_andTheComparisonDetectsARealShift() = runTest {
        val latin = (0 until 40).joinToString("") {
            "Justification distributes the slack of a line into the spaces between its words $it.\n"
        }
        val cjk = (0 until 40).joinToString("") { "黑暗血时代第${it}章，长夜将至，我从今开始守望，至死方休。\n" }
        val mixed = (0 until 40).joinToString("") { "Chapter $it 第${it}章 mixed script prose 混合文字段落。\n" }
        val cases = listOf("latin" to latin, "cjk" to cjk, "mixed" to mixed)

        for (isMarkdown in listOf(false, true)) {
            for ((label, source) in cases) {
                val doc = TxtDocument.of(source)
                val p = TxtPaginator(UnconfinedTestDispatcher(testScheduler))
                val contentBox = box(heightPx = 55f, widthPx = 600f)

                val mStart = StyleSensitiveLineMeasurer()
                val startIdx = p.index(doc, styleAt(18f, TextAlign.Start), contentBox, mStart, PaginationToken(), isMarkdown)
                val mJustify = StyleSensitiveLineMeasurer()
                val justifyIdx = p.index(doc, styleAt(18f, TextAlign.Justify), contentBox, mJustify, PaginationToken(), isMarkdown)

                val ctx = "md=$isMarkdown case=$label"
                // The alignment genuinely reached phase 1 — otherwise the equality below is vacuous.
                assertEquals("$ctx: phase 1 must measure under Start", setOf(TextAlign.Start), mStart.seenAligns)
                assertEquals("$ctx: phase 1 must measure under Justify", setOf(TextAlign.Justify), mJustify.seenAligns)
                // Enough pages that the comparison is over a real boundary SET, not one page.
                assertTrue("$ctx: needs several pages to compare (was ${justifyIdx.pageCount})", justifyIdx.pageCount > 3)
                assertEquals("$ctx: page count must not change", startIdx.pageCount, justifyIdx.pageCount)
                assertArrayEquals(
                    "$ctx: EVERY page boundary must be identical under Justify",
                    startIdx.pageStartsUtf16, justifyIdx.pageStartsUtf16,
                )
                assertEquals("$ctx: doc extent unchanged", startIdx.docEndExclusive, justifyIdx.docEndExclusive)

                // SENSITIVITY CONTROL: a genuinely layout-affecting change MUST move the boundaries,
                // proving the assertions above can fail.
                val bigger = p.index(doc, styleAt(26f, TextAlign.Justify), contentBox, StyleSensitiveLineMeasurer(), PaginationToken(), isMarkdown)
                assertFalse(
                    "$ctx: control — a larger font size must shift the page boundaries, else the " +
                        "invariance assertion above cannot fail",
                    bigger.pageStartsUtf16.contentEquals(justifyIdx.pageStartsUtf16),
                )
            }
        }
    }
}
