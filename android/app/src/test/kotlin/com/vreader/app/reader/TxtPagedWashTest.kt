package com.vreader.app.reader

import com.vreader.app.annotations.AnnotationColor
import com.vreader.app.annotations.HighlightRecord
import com.vreader.app.reader.paged.PageOffsetMap
import com.vreader.app.reader.paged.PageSegment
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import vreader.contracts.Locator

/**
 * Feature #137 WI-7b — [TxtPagedWash.washesForPage] projects stored highlights onto a rendered PAGE as
 * page-LOCAL rendered [WashSpan]s via [PageOffsetMap.sourceRangeToRendered]. The page-scoped analog of
 * [TxtWashMapper.washesByChunk]: a highlight's SOURCE range → the page's rendered range (clamped to the
 * page's extent), so a page-boundary-spanning highlight washes on each covered page. Pure math — no
 * Compose. Mirrors the fixture style of [TxtWashMapperTest].
 */
class TxtPagedWashTest {
    private val key = "txt:${"a".repeat(64)}:200"

    private fun hl(start: Int, end: Int, color: AnnotationColor = AnnotationColor.yellow) = HighlightRecord(
        id = "h$start-$end", bookKey = key, color = color, selectedText = "x", note = null,
        locator = Locator("a".repeat(64), 200L, "txt", charRangeStartUTF16 = start, charRangeEndUTF16 = end),
        anchor = null, createdAt = 1L, updatedAt = 1L,
    )

    /** A TXT page: rendered-local [0, len) maps to GLOBAL source [srcBase, srcBase+len). */
    private fun txtPage(srcBase: Int, len: Int) =
        PageOffsetMap(listOf(PageSegment.identity(renderedBase = 0, srcBase = srcBase, renderedLen = len)))

    // ---- A highlight fully inside the page washes at the right rendered offsets ------------------------

    @Test fun highlightFullyOnPage_washesAtRenderedOffset() {
        // Page covers source [100,120). Highlight source [106,111) → rendered-local [6,11).
        val page = txtPage(srcBase = 100, len = 20)
        val spans = TxtPagedWash.washesForPage(page, listOf(hl(106, 111, AnnotationColor.pink)))
        assertEquals(listOf(WashSpan(Utf16Range(6, 11), AnnotationColor.pink)), spans)
    }

    // ---- A highlight spanning the page start clamps to the page's rendered start -----------------------

    @Test fun highlightStartingBeforePage_clampsToRenderedStart() {
        // Page covers source [100,120). Highlight source [90,105) starts BEFORE the page → clamps to the
        // page's rendered [0,5) (the first 5 rendered chars belong to source [100,105)).
        val page = txtPage(srcBase = 100, len = 20)
        val spans = TxtPagedWash.washesForPage(page, listOf(hl(90, 105)))
        assertEquals(1, spans.size)
        assertEquals(Utf16Range(0, 5), spans.single().local)
    }

    // ---- A highlight spanning the page end clamps to the page's rendered end ---------------------------

    @Test fun highlightEndingAfterPage_clampsToRenderedEnd() {
        // Page covers source [100,120). Highlight source [115,140) ends AFTER the page → clamps to the
        // page's rendered [15,20).
        val page = txtPage(srcBase = 100, len = 20)
        val spans = TxtPagedWash.washesForPage(page, listOf(hl(115, 140)))
        assertEquals(1, spans.size)
        assertEquals(Utf16Range(15, 20), spans.single().local)
    }

    // ---- A page-boundary-spanning highlight washes on BOTH covered pages, clamped per page -------------

    @Test fun pageBoundarySpanningHighlight_washesOnBothPages_clampedPerPage() {
        // Page 0 = source [100,120); page 1 = source [120,140). Highlight source [110,130) covers the tail
        // of page 0 and the head of page 1.
        val page0 = txtPage(srcBase = 100, len = 20)
        val page1 = txtPage(srcBase = 120, len = 20)
        val h = hl(110, 130)
        val s0 = TxtPagedWash.washesForPage(page0, listOf(h))
        val s1 = TxtPagedWash.washesForPage(page1, listOf(h))
        // page 0: rendered [10,20) (source [110,120)); page 1: rendered [0,10) (source [120,130)).
        assertEquals(Utf16Range(10, 20), s0.single().local)
        assertEquals(Utf16Range(0, 10), s1.single().local)
    }

    // ---- A highlight entirely outside the page produces no wash ----------------------------------------

    @Test fun highlightEntirelyOffPage_producesNoWash() {
        val page = txtPage(srcBase = 100, len = 20)
        assertTrue("before the page → no wash", TxtPagedWash.washesForPage(page, listOf(hl(0, 50))).isEmpty())
        assertTrue("after the page → no wash", TxtPagedWash.washesForPage(page, listOf(hl(200, 250))).isEmpty())
    }

    // ---- Multiple highlights on one page each produce a wash -------------------------------------------

    @Test fun multipleHighlights_eachWashed() {
        val page = txtPage(srcBase = 100, len = 20)
        val spans = TxtPagedWash.washesForPage(
            page,
            listOf(hl(101, 104, AnnotationColor.blue), hl(110, 115, AnnotationColor.green)),
        )
        assertEquals(2, spans.size)
        assertTrue(spans.contains(WashSpan(Utf16Range(1, 4), AnnotationColor.blue)))
        assertTrue(spans.contains(WashSpan(Utf16Range(10, 15), AnnotationColor.green)))
    }

    // ---- A highlight without a char range is skipped ---------------------------------------------------

    @Test fun highlightWithoutCharRange_skipped() {
        val page = txtPage(srcBase = 100, len = 20)
        val noRange = HighlightRecord(
            "h", key, AnnotationColor.blue, "x", null,
            Locator("a".repeat(64), 200L, "txt", href = "c"), null, 1L, 1L,
        )
        assertTrue(TxtPagedWash.washesForPage(page, listOf(noRange)).isEmpty())
    }

    // ---- An inverted / empty char range is skipped -----------------------------------------------------

    @Test fun invertedOrEmptyRange_skipped() {
        val page = txtPage(srcBase = 100, len = 20)
        assertTrue("empty range", TxtPagedWash.washesForPage(page, listOf(hl(105, 105))).isEmpty())
        assertTrue("inverted range", TxtPagedWash.washesForPage(page, listOf(hl(110, 105))).isEmpty())
    }

    // ---- MD: a marker-only source slice collapses to empty (draws nothing) -----------------------------

    @Test fun mdPage_markerOnlyHighlight_producesNoWash() {
        // "**bold**\n" renders to "bold\n". A highlight over source [0,2) (the leading "**" markers only)
        // maps to an EMPTY rendered range → no wash.
        val chunk = "**bold**\n"
        val cm = MarkdownOffsetMap(MarkdownRenderer.renderWithMap(chunk))
        val page = PageOffsetMap(listOf(PageSegment.markdown(cm, renderedBase = 0, srcBase = 0)))
        val spans = TxtPagedWash.washesForPage(page, listOf(hl(0, 2)))
        assertTrue("marker-only source slice draws nothing", spans.isEmpty())
    }

    // ---- MD: a real word highlight washes the rendered word (dual-affinity) -----------------------------

    @Test fun mdPage_wordHighlight_washesRenderedWord() {
        // "**bold**\n" renders to "bold\n". Source [2,6) = "bold" (inside the markers) → rendered [0,4).
        val chunk = "**bold**\n"
        val cm = MarkdownOffsetMap(MarkdownRenderer.renderWithMap(chunk))
        val page = PageOffsetMap(listOf(PageSegment.markdown(cm, renderedBase = 0, srcBase = 0)))
        val spans = TxtPagedWash.washesForPage(page, listOf(hl(2, 6)))
        assertEquals(1, spans.size)
        assertEquals(Utf16Range(0, 4), spans.single().local)
    }
}
