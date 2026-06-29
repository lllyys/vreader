package com.vreader.app.reader

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Feature #125 WI-2 — [ChunkTextMapper] (Identity for TXT, Markdown for MD). CHUNK-LOCAL coords;
 * the caller adds the chunk's document start offset.
 */
class ChunkTextMapperTest {
    private fun r(a: Int, b: Int) = Utf16Range(a, b)

    // --- Identity (TXT): every conversion is identity ------------------------------------------

    @Test fun identity_isPassthrough() {
        val doc = TxtDocument.of("hello\nworld\n")
        val m = IdentityChunkTextMapper(doc)
        assertEquals("hello\n", m.renderedText(0).text)
        assertEquals(r(0, 5), m.renderedRangeToSource(0, r(0, 5)))
        assertEquals(r(0, 5), m.sourceRangeToRendered(0, r(0, 5)))
        assertEquals(2, m.renderedCursorForSourceEnd(0, 2))
        assertEquals("hello", m.visibleText(0, r(0, 5)))
        assertEquals("hello", m.sourceText(0, r(0, 5)))
    }

    @Test fun identity_clampsOutOfBounds() {
        val doc = TxtDocument.of("hi\n")
        val m = IdentityChunkTextMapper(doc)
        assertEquals("hi\n", m.visibleText(0, r(0, 999)))
    }

    @Test fun identity_clampsRangeConversions() {
        // chunk 0 = "hi\n" (len 3). Identity conversions clamp out-of-range inputs to 0..len (WI-2 audit fix).
        val m = IdentityChunkTextMapper(TxtDocument.of("hi\n"))
        assertEquals(r(0, 3), m.sourceRangeToRendered(0, r(-2, 99)))
        assertEquals(r(0, 3), m.renderedRangeToSource(0, r(-2, 99)))
        assertEquals(3, m.renderedCursorForSourceEnd(0, 99))
        assertEquals(0, m.renderedCursorForSourceEnd(0, -5))
    }

    // --- Markdown (MD): conversions bridge rendered↔source -------------------------------------

    private fun mdDoc() = TxtDocument.of("# Title\n**bold**x\n- item\n")
    // chunk 0 = "# Title\n", chunk 1 = "**bold**x\n", chunk 2 = "- item\n"

    @Test fun markdown_rendersChunk() {
        val m = MarkdownChunkTextMapper(mdDoc())
        assertEquals("Title\n", m.renderedText(0).text)   // heading markers stripped
        assertEquals("boldx\n", m.renderedText(1).text)
        assertEquals("• item\n", m.renderedText(2).text)
    }

    @Test fun markdown_renderedToSource_chunkLocal() {
        val m = MarkdownChunkTextMapper(mdDoc())
        // chunk 1 "**bold**x\n" → rendered "boldx\n"; rendered [0,5) ("boldx") → source [2,9)
        assertEquals(r(2, 9), m.renderedRangeToSource(1, r(0, 5)))
        // just "x" (rendered [4,5)) → source [8,9)
        assertEquals(r(8, 9), m.renderedRangeToSource(1, r(4, 5)))
    }

    @Test fun markdown_sourceToRendered_markerOnlyEmpty() {
        val m = MarkdownChunkTextMapper(mdDoc())
        // chunk 1: the opening "**" (source [0,2)) maps to NO visible char → empty
        assertEquals(0, m.sourceRangeToRendered(1, r(0, 2)).length)
        // "bold" source [2,6) → rendered [0,4)
        assertEquals(r(0, 4), m.sourceRangeToRendered(1, r(2, 6)))
    }

    @Test fun markdown_visibleVsSource_differ() {
        val m = MarkdownChunkTextMapper(mdDoc())
        // selecting rendered "boldx" → VISIBLE "boldx", SOURCE span [2,9) = "bold**x" (the source the
        // textQuote anchor stores — includes the interior markers it spans).
        assertEquals("boldx", m.visibleText(1, r(0, 5)))
        assertEquals("bold**x", m.sourceText(1, r(2, 9)))
    }

    @Test fun markdown_roundTrip_rendered_source_rendered() {
        val m = MarkdownChunkTextMapper(mdDoc())
        val rendered = r(0, 5)
        val source = m.renderedRangeToSource(1, rendered)
        assertEquals(rendered, m.sourceRangeToRendered(1, source))
    }

    @Test fun markdown_cursorForSourceEnd_anchor() {
        val m = MarkdownChunkTextMapper(mdDoc())
        // chunk 1: source end 6 (end of "bold") → rendered cursor 4
        assertEquals(4, m.renderedCursorForSourceEnd(1, 6))
    }

    // --- LRU cache bound -----------------------------------------------------------------------

    @Test fun markdown_lru_boundsCacheSize() {
        val sb = StringBuilder()
        repeat(50) { sb.append("line $it\n") }
        val m = MarkdownChunkTextMapper(TxtDocument.of(sb.toString()), maxCached = 8)
        for (i in 0 until 50) m.renderedText(i)   // touch all 50 chunks
        assertTrue("LRU should bound the cache to maxCached, was ${m.cacheSize}", m.cacheSize <= 8)
    }

    @Test fun markdown_lru_recomputesEvicted() {
        val sb = StringBuilder()
        repeat(50) { sb.append("**b$it**\n") }
        val m = MarkdownChunkTextMapper(TxtDocument.of(sb.toString()), maxCached = 4)
        for (i in 0 until 50) m.renderedText(i)
        // chunk 0 was evicted; re-accessing it still returns the correct rendered text.
        assertEquals("b0\n", m.renderedText(0).text)
        assertTrue(m.cacheSize <= 4)
    }
}
