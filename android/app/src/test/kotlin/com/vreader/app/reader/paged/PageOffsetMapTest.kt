package com.vreader.app.reader.paged

import com.vreader.app.reader.MarkdownOffsetMap
import com.vreader.app.reader.MarkdownRenderer
import com.vreader.app.reader.Utf16Range
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Feature #137 WI-4 — [PageOffsetMap]: the COMPOSED, span-preserving page-local rendered↔source map.
 *
 * It splices a page's constituent chunk maps (identity for TXT, [MarkdownOffsetMap] for MD) by
 * `(renderedBase, srcBase)` and DELEGATES every query to the owning segment, so the exact
 * dual-affinity spans + both range-conversion directions the current selection/wash rely on are
 * reproduced verbatim — just at PAGE scope (page-local rendered index → global source UTF-16).
 */
class PageOffsetMapTest {
    private fun r(a: Int, b: Int) = Utf16Range(a, b)

    /** An MD chunk's map, built through the same renderer the scroll body uses. */
    private fun mdMap(chunk: String) = MarkdownOffsetMap(MarkdownRenderer.renderWithMap(chunk))

    // --- Identity (TXT) segments ---------------------------------------------------------------

    @Test fun identity_singleSegment_isPassthroughAtSrcBase() {
        // A TXT page covering source [100, 106) = "hello\n" (rendered == source).
        val page = PageOffsetMap(
            listOf(PageSegment.identity(renderedBase = 0, srcBase = 100, renderedLen = 6)),
        )
        // page-local rendered 0 → source 100; rendered 5 → source 105.
        assertEquals(100, page.sourceAt(0))
        assertEquals(105, page.sourceAt(5))
        // rendered [0,5) ("hello") → source [100,105).
        assertEquals(r(100, 105), page.renderedRangeToSource(r(0, 5)))
        // source [100,105) → rendered [0,5).
        assertEquals(r(0, 5), page.sourceRangeToRendered(r(100, 105)))
        // dual-affinity span for rendered 2 → source [102,103).
        assertEquals(r(102, 103), page.renderedSpanAt(2))
    }

    @Test fun identity_multiSegment_pageSpansTwoTxtChunks() {
        // Page = two TXT chunks concatenated: chunk A source [10,13)="ab\n", chunk B source [13,16)="cd\n".
        // renderedBase runs 0,3; srcBase = each chunk's document start.
        val page = PageOffsetMap(
            listOf(
                PageSegment.identity(renderedBase = 0, srcBase = 10, renderedLen = 3),
                PageSegment.identity(renderedBase = 3, srcBase = 13, renderedLen = 3),
            ),
        )
        // page-local rendered 0..2 → source 10..12 ; rendered 3..5 → source 13..15.
        assertEquals(10, page.sourceAt(0))
        assertEquals(12, page.sourceAt(2))
        assertEquals(13, page.sourceAt(3))
        assertEquals(15, page.sourceAt(5))
        // a range spanning the segment boundary: rendered [1,5) → source [11,15).
        assertEquals(r(11, 15), page.renderedRangeToSource(r(1, 5)))
        // source [11,15) → rendered [1,5).
        assertEquals(r(1, 5), page.sourceRangeToRendered(r(11, 15)))
    }

    // --- Markdown segments: delegate to MarkdownOffsetMap, span-preserving ----------------------

    @Test fun markdown_singleSegment_reproducesChunkMapAtPageScope() {
        // chunk "**bold**x\n" → rendered "boldx\n"; document start = 200.
        val chunk = "**bold**x\n"
        val cm = mdMap(chunk)
        val page = PageOffsetMap(
            listOf(PageSegment.markdown(cm, renderedBase = 0, srcBase = 200)),
        )
        // rendered "boldx" [0,5) → chunk-local source [2,9) → global [202,209).
        assertEquals(r(202, 209), page.renderedRangeToSource(r(0, 5)))
        // "x" rendered [4,5) → chunk-local [8,9) → global [208,209).
        assertEquals(r(208, 209), page.renderedRangeToSource(r(4, 5)))
        // source "bold" chunk-local [2,6) = global [202,206) → rendered [0,4).
        assertEquals(r(0, 4), page.sourceRangeToRendered(r(202, 206)))
        // marker-only source: the opening "**" chunk-local [0,2) = global [200,202) → EMPTY rendered.
        assertEquals(0, page.sourceRangeToRendered(r(200, 202))?.length ?: 0)
    }

    @Test fun markdown_renderedSpanAt_dualAffinity_matchesChunkMap() {
        // "**bold**x\n": rendered index 4 is 'x', whose SOURCE span is chunk-local [8,9) (dual-affinity —
        // the stripped "**" between 'd' and 'x' does NOT collapse their distinct source positions).
        val chunk = "**bold**x\n"
        val cm = mdMap(chunk)
        val page = PageOffsetMap(listOf(PageSegment.markdown(cm, renderedBase = 0, srcBase = 50)))
        // source "**bold**x\n": 'b'=2,'o'=3,'l'=4,'d'=5. 'd' is rendered index 3 → chunk-local [5,6) → global [55,56).
        assertEquals(r(55, 56), page.renderedSpanAt(3))
        // 'x' is rendered index 4 → source chunk-local [8,9) → global [58,59) (NOT [56,57)).
        assertEquals(r(58, 59), page.renderedSpanAt(4))
    }

    @Test fun markdown_multiSegment_pageSpansTwoMdChunks_allThreeApisExact() {
        // A page spanning two MD chunks, each mapped exactly against its own MarkdownOffsetMap.
        // chunk A "*i*\n" → rendered "i\n" (len 2); doc start 0.
        // chunk B "# H\n" → rendered "H\n" (len 2); doc start 4.
        val a = "*i*\n"; val b = "# H\n"
        val cmA = mdMap(a); val cmB = mdMap(b)
        val page = PageOffsetMap(
            listOf(
                PageSegment.markdown(cmA, renderedBase = 0, srcBase = 0),
                PageSegment.markdown(cmB, renderedBase = 2, srcBase = 4),
            ),
        )
        // Segment A: rendered "i" (page-local [0,1)) → chunk-local [1,2) → global [1,2).
        assertEquals(r(1, 2), page.renderedRangeToSource(r(0, 1)))
        // Segment B: rendered "H" (page-local [2,3)) → chunk-local [2,3) → global [6,7).
        assertEquals(r(6, 7), page.renderedRangeToSource(r(2, 3)))
        // sourceRangeToRendered against each underlying map, page-shifted.
        assertEquals(r(0, 1), page.sourceRangeToRendered(r(1, 2)))   // A "i"
        assertEquals(r(2, 3), page.sourceRangeToRendered(r(6, 7)))   // B "H"
        // renderedSpanAt matches the chunk map for both segments.
        assertEquals(cmA.renderedRangeToSource(r(0, 1)).let { r(it.startInclusive, it.endExclusive) },
            page.renderedSpanAt(0))          // A char 0 span, global == chunk-local (srcBase 0)
        assertEquals(r(6, 7), page.renderedSpanAt(2))  // B char 0 ('H') span, global
    }

    // --- Cross-check the delegate matches the raw chunk map for EVERY rendered index -------------

    @Test fun markdown_everyRenderedIndex_matchesRawChunkMap() {
        val chunk = "**bold**x `code`\n"
        val cm = mdMap(chunk)
        val srcBase = 1000
        val page = PageOffsetMap(listOf(PageSegment.markdown(cm, renderedBase = 0, srcBase = srcBase)))
        val renderedLen = cm.renderedText.length
        for (i in 0 until renderedLen) {
            val chunkSpan = cm.renderedRangeToSource(r(i, i + 1))
            val expected = r(chunkSpan.startInclusive + srcBase, chunkSpan.endExclusive + srcBase)
            assertEquals("renderedSpanAt($i)", expected, page.renderedSpanAt(i))
            assertEquals("sourceAt($i)", chunkSpan.startInclusive + srcBase, page.sourceAt(i))
        }
    }

    // --- Surrogate pairs (CJK astral) ----------------------------------------------------------

    @Test fun surrogatePair_identity_offsetsAreUtf16CodeUnits() {
        // "𝕏\n" is a surrogate pair (2 UTF-16 units) + newline. TXT identity.
        val page = PageOffsetMap(listOf(PageSegment.identity(renderedBase = 0, srcBase = 20, renderedLen = 3)))
        // rendered 0 (high surrogate) → source 20; rendered 1 (low surrogate) → source 21.
        assertEquals(20, page.sourceAt(0))
        assertEquals(21, page.sourceAt(1))
        assertEquals(r(20, 22), page.renderedRangeToSource(r(0, 2)))   // the whole pair
    }

    // --- Empty page ----------------------------------------------------------------------------

    @Test fun emptyPage_noSegments_collapsesSafely() {
        val page = PageOffsetMap(emptyList())
        assertEquals(0, page.sourceAt(0))
        assertEquals(0, page.renderedRangeToSource(r(0, 5)).length)
        assertEquals(0, page.sourceRangeToRendered(r(0, 5))?.length ?: 0)
    }

    // --- Out-of-range page-local rendered indices clamp, never throw -----------------------------

    @Test fun outOfRange_clampsWithoutThrow() {
        val page = PageOffsetMap(listOf(PageSegment.identity(renderedBase = 0, srcBase = 5, renderedLen = 3)))
        // rendered index past the end → clamps to the source-end bound.
        assertTrue(page.sourceAt(999) >= 5)
        // an entirely out-of-range rendered range collapses (empty), no exception.
        val src = page.renderedRangeToSource(r(50, 60))
        assertTrue(src.length == 0)
    }
}
