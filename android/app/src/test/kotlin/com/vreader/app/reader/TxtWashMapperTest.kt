package com.vreader.app.reader

import com.vreader.app.annotations.AnnotationColor
import com.vreader.app.annotations.HighlightRecord
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import vreader.contracts.Locator

/** Feature #124 WI-2 — [TxtWashMapper.washesByChunk] projects highlights onto per-chunk washes. */
class TxtWashMapperTest {
    private val doc = TxtDocument.of("AAAA\nBBBB\nCCCC\nDDDD\n", maxChunkChars = 6)
    private val key = "txt:${"a".repeat(64)}:20"

    private fun hl(start: Int, end: Int, color: AnnotationColor = AnnotationColor.yellow) = HighlightRecord(
        id = "h$start", bookKey = key, color = color, selectedText = "x", note = null,
        locator = Locator("a".repeat(64), 20L, "txt", charRangeStartUTF16 = start, charRangeEndUTF16 = end),
        anchor = null, createdAt = 1L, updatedAt = 1L,
    )

    @Test fun singleChunkHighlight_oneWash() {
        val base1 = doc.offsetForChunk(1)
        val map = TxtWashMapper.washesByChunk(doc, listOf(hl(base1 + 1, base1 + 3, AnnotationColor.pink)))
        assertEquals(setOf(1), map.keys)
        assertEquals(WashSpan(Utf16Range(1, 3), AnnotationColor.pink), map[1]!!.single())
    }

    @Test fun multiChunkHighlight_splitsAcrossChunks() {
        val start = doc.offsetForChunk(0) + 2
        val end = doc.offsetForChunk(2) + 2
        val map = TxtWashMapper.washesByChunk(doc, listOf(hl(start, end)))
        assertTrue("covers >= 2 chunks", map.keys.size >= 2)
        // reassembling the per-chunk locals back to source equals the original range
        var cursor = start
        for (ci in map.keys.sorted()) {
            val base = doc.offsetForChunk(ci)
            for (w in map[ci]!!) {
                assertEquals(cursor, base + w.local.startInclusive)
                cursor = base + w.local.endExclusive
            }
        }
        assertEquals(end, cursor)
    }

    @Test fun multipleHighlights_distinctChunks() {
        val b0 = doc.offsetForChunk(0); val b3 = doc.offsetForChunk(3)
        val map = TxtWashMapper.washesByChunk(doc, listOf(hl(b0, b0 + 2), hl(b3, b3 + 2)))
        assertTrue(map.containsKey(0) && map.containsKey(3))
    }

    @Test fun highlightWithoutCharRange_skipped() {
        val noRange = HighlightRecord("h", key, AnnotationColor.blue, "x", null, Locator("a".repeat(64), 20L, "txt", href = "c"), null, 1L, 1L)
        assertTrue(TxtWashMapper.washesByChunk(doc, listOf(noRange)).isEmpty())
    }
}
