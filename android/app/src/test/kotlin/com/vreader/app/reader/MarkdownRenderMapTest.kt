package com.vreader.app.reader

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

/** Feature #125 WI-1 — [MarkdownRenderer.renderWithMap] per-rendered-char source spans. */
class MarkdownRenderMapTest {
    private fun map(chunk: String) = MarkdownRenderer.renderWithMap(chunk)

    @Test fun render_delegatesTo_renderWithMap() {
        for (s in listOf("plain", "# H", "- item", "**bold**", "*i*", "`c`", "a\\*b", "***x***", "_u_")) {
            assertEquals("render() byte-identical for [$s]", MarkdownRenderer.render(s), map(s).text)
        }
    }

    @Test fun plain_isIdentity() {
        val m = map("abc")
        assertEquals("abc", m.text.text)
        assertArrayEquals(intArrayOf(0, 1, 2), m.srcStart)
        assertArrayEquals(intArrayOf(1, 2, 3), m.srcEnd)
    }

    @Test fun bold_spansExcludeMarkers() {
        // "**bold**" → rendered "bold"; srcStart=[2,3,4,5], srcEnd=[3,4,5,6]
        val m = map("**bold**")
        assertEquals("bold", m.text.text)
        assertArrayEquals(intArrayOf(2, 3, 4, 5), m.srcStart)
        assertArrayEquals(intArrayOf(3, 4, 5, 6), m.srcEnd)
    }

    @Test fun boldThenChar_distinctSourcePositions() {
        // "**bold**x" → rendered "boldx"; the 'x' at rendered idx 4 came from source 8.
        val m = map("**bold**x")
        assertEquals("boldx", m.text.text)
        assertArrayEquals(intArrayOf(2, 3, 4, 5, 8), m.srcStart)
        assertArrayEquals(intArrayOf(3, 4, 5, 6, 9), m.srcEnd)
    }

    @Test fun heading_textOnly_mapsPastPrefix() {
        // "# H" → rendered "H" from source index 2.
        val m = map("# H")
        assertEquals("H", m.text.text)
        assertArrayEquals(intArrayOf(2), m.srcStart)
        assertArrayEquals(intArrayOf(3), m.srcEnd)
    }

    @Test fun bullet_insertedGlyphsMapToMarker_textExcludesIt() {
        // "- item" → rendered "• item"; "• " → source [0,2); "item" → source [2,6)
        val m = map("- item")
        assertEquals("• item", m.text.text)
        // glyph 0 '•' and glyph 1 ' ' both map to [0,2); then 'i','t','e','m' → 2,3,4,5
        assertArrayEquals(intArrayOf(0, 0, 2, 3, 4, 5), m.srcStart)
        assertArrayEquals(intArrayOf(2, 2, 3, 4, 5, 6), m.srcEnd)
    }

    @Test fun escape_rendersOneChar_spanningTwoSource() {
        // "\*x" → rendered "*x"; '*' from source [0,2) (backslash+star), 'x' from [2,3)
        val m = map("\\*x")
        assertEquals("*x", m.text.text)
        assertArrayEquals(intArrayOf(0, 2), m.srcStart)
        assertArrayEquals(intArrayOf(2, 3), m.srcEnd)
    }

    @Test fun code_dropsBackticks() {
        // "`c`x" → rendered "cx"; 'c' from source 1, 'x' from source 3
        val m = map("`c`x")
        assertEquals("cx", m.text.text)
        assertArrayEquals(intArrayOf(1, 3), m.srcStart)
        assertArrayEquals(intArrayOf(2, 4), m.srcEnd)
    }

    @Test fun eol_mapped() {
        val m = map("ab\n")
        assertEquals("ab\n", m.text.text)
        assertArrayEquals(intArrayOf(0, 1, 2), m.srcStart)
        assertArrayEquals(intArrayOf(1, 2, 3), m.srcEnd)
    }

    @Test fun unmatchedMarker_literal() {
        val m = map("a*b")
        assertEquals("a*b", m.text.text)
        assertArrayEquals(intArrayOf(0, 1, 2), m.srcStart)
    }
}
