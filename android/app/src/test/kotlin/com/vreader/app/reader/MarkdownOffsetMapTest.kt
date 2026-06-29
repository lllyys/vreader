package com.vreader.app.reader

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Feature #125 WI-2 — [MarkdownOffsetMap] chunk-local rendered↔source conversions over the WI-1
 * per-rendered-char source spans. All coords are CHUNK-LOCAL UTF-16 (the caller adds the chunk's
 * document start offset). Goldens mirror the plan's worked examples.
 */
class MarkdownOffsetMapTest {
    private fun map(chunk: String) = MarkdownOffsetMap(MarkdownRenderer.renderWithMap(chunk))
    private fun r(a: Int, b: Int) = Utf16Range(a, b)

    // --- renderedRangeToSource -----------------------------------------------------------------

    @Test fun bold_renderedToSource_excludesMarkers() {
        // "**bold**" → "bold"; rendered [0,4) → source [2,6)
        assertEquals(r(2, 6), map("**bold**").renderedRangeToSource(r(0, 4)))
    }

    @Test fun boldThenChar_renderedToSource_distinct() {
        // "**bold**x" → "boldx"; rendered [4,5) ("x") → source [8,9); rendered [0,4) → [2,6)
        val m = map("**bold**x")
        assertEquals(r(8, 9), m.renderedRangeToSource(r(4, 5)))
        assertEquals(r(2, 6), m.renderedRangeToSource(r(0, 4)))
        assertEquals(r(2, 9), m.renderedRangeToSource(r(0, 5))) // "boldx" → source [2,9)
    }

    @Test fun heading_renderedToSource_pastPrefix() {
        // "# H" → "H"; rendered [0,1) → source [2,3)
        assertEquals(r(2, 3), map("# H").renderedRangeToSource(r(0, 1)))
    }

    @Test fun code_renderedToSource_dropsBackticks() {
        // "`c`x" → "cx"; rendered [0,1) ("c") → source [1,2); rendered [0,2) → [1,4)
        val m = map("`c`x")
        assertEquals(r(1, 2), m.renderedRangeToSource(r(0, 1)))
        assertEquals(r(1, 4), m.renderedRangeToSource(r(0, 2)))
    }

    @Test fun escape_renderedToSource_spansTwoSource() {
        // "\*x" → "*x"; rendered [0,1) ("*") → source [0,2)
        assertEquals(r(0, 2), map("\\*x").renderedRangeToSource(r(0, 1)))
    }

    @Test fun emptyRendered_mapsToEmptySource() {
        // empty rendered range → empty source at the start char's source-start
        val m = map("**bold**")
        val out = m.renderedRangeToSource(r(2, 2))
        assertEquals(0, out.length)
        assertEquals(4, out.startInclusive) // srcStart[2] == 4
    }

    // --- sourceRangeToRendered (clamped, affinity, marker-only → empty) -------------------------

    @Test fun source_x_toRendered() {
        // "**bold**x"; source [8,9) ("x") → rendered [4,5)
        assertEquals(r(4, 5), map("**bold**x").sourceRangeToRendered(r(8, 9)))
    }

    @Test fun source_bold_toRendered() {
        // "**bold**"; source [2,6) ("bold") → rendered [0,4)
        assertEquals(r(0, 4), map("**bold**").sourceRangeToRendered(r(2, 6)))
    }

    @Test fun source_markerOnly_collapsesToEmpty() {
        // "**bold**"; source [0,2) (the opening "**") overlaps NO visible char → empty rendered
        val out = map("**bold**").sourceRangeToRendered(r(0, 2))
        assertEquals("marker-only source draws nothing", 0, out.length)
    }

    @Test fun source_trailingMarker_collapsesToEmpty() {
        // "**bold**"; source [6,8) (the closing "**") → empty rendered
        assertEquals(0, map("**bold**").sourceRangeToRendered(r(6, 8)).length)
    }

    @Test fun source_spanningMarker_clampsToVisible() {
        // "**bold**x"; source [6,9) (closing "**" + "x") → rendered [4,5) (just "x", markers clipped)
        assertEquals(r(4, 5), map("**bold**x").sourceRangeToRendered(r(6, 9)))
    }

    @Test fun source_roundTrip_bold() {
        // rendered → source → rendered is stable for a visible range
        val m = map("**bold**x")
        val rendered = r(0, 5)
        val source = m.renderedRangeToSource(rendered)
        assertEquals(rendered, m.sourceRangeToRendered(source))
    }

    // --- renderedCursorForSourceEnd (popover anchor, end-affinity) ------------------------------

    @Test fun cursorForSourceEnd_atSelectionEnd() {
        // "**bold**x"; source end 6 (end of "bold") → rendered cursor 4 (one past 'd')
        assertEquals(4, map("**bold**x").renderedCursorForSourceEnd(6))
        // source end 9 (end of "x") → rendered cursor 5
        assertEquals(5, map("**bold**x").renderedCursorForSourceEnd(9))
    }

    // --- bullet + CJK + empty chunk ------------------------------------------------------------

    @Test fun bullet_sourceToRendered() {
        // "- item" → "• item"; source [2,6) ("item") → rendered [2,6)
        assertEquals(r(2, 6), map("- item").sourceRangeToRendered(r(2, 6)))
        // source [0,2) (the "- " marker) → the bullet glyphs "• " → rendered [0,2)
        assertEquals(r(0, 2), map("- item").sourceRangeToRendered(r(0, 2)))
    }

    @Test fun cjk_surrogate_offsetsCorrect() {
        // "**𝄞x**" — 𝄞 is a surrogate pair (2 UTF-16 units). rendered "𝄞x".
        val m = map("**𝄞x**")
        // rendered [0,2) is the surrogate pair → source [2,4)
        assertEquals(r(2, 4), m.renderedRangeToSource(r(0, 2)))
    }

    @Test fun emptyChunk_safe() {
        val m = map("")
        assertEquals(r(0, 0), m.sourceRangeToRendered(r(0, 5)))
        assertEquals(0, m.renderedCursorForSourceEnd(3))
    }

    @Test fun renderedRangeToSource_outOfRange_collapsesAtEnd() {
        // "**bold**" → "bold" (n=4). A wholly-past-end rendered range collapses empty at the source end,
        // NOT to the last char's span (WI-2 audit fix).
        val m = map("**bold**")
        val pastEnd = m.renderedRangeToSource(r(9, 10))
        assertEquals(0, pastEnd.length)
        assertEquals(6, pastEnd.startInclusive) // sourceEndBound() == srcEnd[3] == 6
        // A negative range clamps to the start side, not the last char.
        val negative = m.renderedRangeToSource(r(-5, -4))
        assertEquals(0, negative.length)
        assertEquals(2, negative.startInclusive) // srcStart[0] == 2
    }
}
