package com.vreader.app.reader

import com.vreader.app.annotations.AnnotationColor
import com.vreader.app.annotations.HighlightRecord
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import vreader.contracts.Locator

/**
 * Feature #125 WI-3 — a stored MD highlight is anchored in SOURCE coords, but the wash must draw the
 * RENDERED range (`getPathForRange` speaks rendered offsets). `TxtWashMapper.washesByChunk` + a
 * `MarkdownChunkTextMapper` projects source→rendered, so markers are excluded and a marker-only
 * highlight washes nothing.
 */
class MdHighlightWashTest {
    // chunk 0 = "# Title\n" (src [0,8)); chunk 1 = "**bold**x\n" (src [8,18))
    private val doc = TxtDocument.of("# Title\n**bold**x\n")
    private val mapper = MarkdownChunkTextMapper(doc)
    private val key = "md:${"a".repeat(64)}:18"

    private fun hl(start: Int, end: Int) = HighlightRecord(
        id = "h$start", bookKey = key, color = AnnotationColor.yellow, selectedText = "bold", note = null,
        locator = Locator("a".repeat(64), 18L, "md", charRangeStartUTF16 = start, charRangeEndUTF16 = end),
        anchor = null, createdAt = 1L, updatedAt = 1L,
    )

    @Test fun boldHighlight_washesRenderedRangeNotSource() {
        // "bold" source span: chunk 1 base 8, source [10,14). Rendered "boldx\n" → "bold" is rendered [0,4).
        val map = TxtWashMapper.washesByChunk(doc, listOf(hl(10, 14)), mapper)
        assertEquals(setOf(1), map.keys)
        assertEquals(WashSpan(Utf16Range(0, 4), AnnotationColor.yellow), map[1]!!.single())
    }

    @Test fun headingHighlight_washesStrippedPrefix() {
        // "Title" source: chunk 0 "# Title\n", "Title" is source [2,7). Rendered "Title\n" → rendered [0,5).
        val map = TxtWashMapper.washesByChunk(doc, listOf(hl(2, 7)), mapper)
        assertEquals(WashSpan(Utf16Range(0, 5), AnnotationColor.yellow), map[0]!!.single())
    }

    @Test fun markerOnlyHighlight_washesNothing() {
        // The opening "**" of chunk 1 is source [8,10) — overlaps no visible char → no wash.
        val map = TxtWashMapper.washesByChunk(doc, listOf(hl(8, 10)), mapper)
        assertTrue("a marker-only highlight draws nothing", map[1].isNullOrEmpty())
    }

    @Test fun identityMapper_unchangedForTxt() {
        // Same highlight through the identity mapper (TXT) washes the SOURCE range verbatim (regression).
        val txt = TxtDocument.of("# Title\n**bold**x\n")
        val map = TxtWashMapper.washesByChunk(txt, listOf(hl(10, 14)), IdentityChunkTextMapper(txt))
        assertEquals(WashSpan(Utf16Range(2, 6), AnnotationColor.yellow), map[1]!!.single())
    }
}
