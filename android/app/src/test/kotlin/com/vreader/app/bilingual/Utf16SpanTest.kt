// Purpose: feature #131 WI-1 — RED-first JVM tests for Utf16Span, the half-open
// UTF-16 span value type used by the bilingual interlinear pipeline.
package com.vreader.app.bilingual

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class Utf16SpanTest {

    @Test fun length_isEndMinusStart() {
        assertEquals(5, Utf16Span(3, 8).length)
        assertEquals(0, Utf16Span(4, 4).length)
    }

    @Test fun isEmpty_whenEndEqualsStart() {
        assertTrue(Utf16Span(4, 4).isEmpty)
        assertFalse(Utf16Span(4, 5).isEmpty)
    }

    @Test fun halfOpen_zeroLengthSpanIsAllowed() {
        // endExclusive == start is a valid (empty) span; require does NOT throw.
        val span = Utf16Span(0, 0)
        assertEquals(0, span.length)
        assertTrue(span.isEmpty)
    }

    @Test(expected = IllegalArgumentException::class)
    fun requireThrowsOnEndBeforeStart() {
        Utf16Span(8, 3)
    }

    @Test(expected = IllegalArgumentException::class)
    fun requireThrowsOnNegativeStart() {
        Utf16Span(-1, 2)
    }

    @Test fun substringRoundTrips() {
        val text = "Hello world"
        val span = Utf16Span(6, 11)
        assertEquals("world", text.substring(span.start, span.endExclusive))
    }
}
