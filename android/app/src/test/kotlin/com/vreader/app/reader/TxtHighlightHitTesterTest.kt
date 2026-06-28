package com.vreader.app.reader

import com.vreader.app.annotations.AnnotationColor
import com.vreader.app.annotations.HighlightRecord
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import vreader.contracts.Locator

/** Feature #124 WI-1 — [TxtHighlightHitTester]: tapped source offset → highlight, newest wins. */
class TxtHighlightHitTesterTest {
    private val key = "txt:${"a".repeat(64)}:100"

    private fun hl(id: String, start: Int, end: Int, createdAt: Long) = HighlightRecord(
        id = id, bookKey = key, color = AnnotationColor.yellow, selectedText = "x", note = null,
        locator = Locator("a".repeat(64), 100L, "txt", charRangeStartUTF16 = start, charRangeEndUTF16 = end),
        anchor = null, createdAt = createdAt, updatedAt = createdAt,
    )

    @Test fun hit_insideRange() {
        val h = hl("h1", 10, 20, 1L)
        assertEquals("h1", TxtHighlightHitTester.highlightAt(15, listOf(h))?.id)
        assertEquals("inclusive start", "h1", TxtHighlightHitTester.highlightAt(10, listOf(h))?.id)
    }

    @Test fun miss_outsideRange_andExclusiveEnd() {
        val h = hl("h1", 10, 20, 1L)
        assertNull(TxtHighlightHitTester.highlightAt(20, listOf(h)))   // end is exclusive
        assertNull(TxtHighlightHitTester.highlightAt(9, listOf(h)))
        assertNull(TxtHighlightHitTester.highlightAt(5, emptyList()))
    }

    @Test fun overlap_newestWins() {
        val older = hl("old", 10, 30, 1L)
        val newer = hl("new", 15, 25, 9L)
        assertEquals("new", TxtHighlightHitTester.highlightAt(20, listOf(older, newer))?.id)
    }

    @Test fun ignoresHighlightsWithoutCharRange() {
        val noRange = HighlightRecord(
            "h2", key, AnnotationColor.blue, "x", null,
            Locator("a".repeat(64), 100L, "txt", href = "c"), null, 1L, 1L,
        )
        assertNull(TxtHighlightHitTester.highlightAt(5, listOf(noRange)))
    }
}
