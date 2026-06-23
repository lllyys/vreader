package com.vreader.app.ai

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import java.io.ByteArrayInputStream

/** Feature #118 WI-2 — the bounded SSE framer: event boundaries, comments, multi-data, bounds. */
class SseEventReaderTest {
    private fun events(s: String) = SseEventReader.events(ByteArrayInputStream(s.toByteArray())).toList()

    @Test fun framesEvents_skipsComments_joinsMultiData() {
        val sse = ": keepalive\n" +
            "event: content_block_delta\n" +
            "data: line1\n" +
            "data: line2\n" +
            "\n" +
            "data: solo\n\n"
        val evs = events(sse)
        assertEquals(2, evs.size)
        assertEquals("content_block_delta", evs[0].event)
        assertEquals("line1\nline2", evs[0].data)  // multiple data: lines joined with \n
        assertEquals("solo", evs[1].data)
    }

    @Test fun finalEvent_withoutTrailingBlank() {
        val evs = events("data: {\"x\":1}")  // no trailing blank line
        assertEquals(1, evs.size)
        assertEquals("{\"x\":1}", evs[0].data)
    }

    @Test fun stripsCarriageReturns() {
        val evs = events("data: a\r\n\r\n")
        assertEquals("a", evs[0].data)
    }

    @Test fun overlongLine_throwsBounded() {
        val huge = "data: " + "x".repeat(SseEventReader.MAX_LINE_BYTES + 10)  // no newline → unbounded line
        val ex = assertThrows(AiError.Stream::class.java) {
            SseEventReader.events(ByteArrayInputStream(huge.toByteArray())).toList()
        }
        assertEquals(true, ex.message!!.contains("line"))
    }

    @Test fun emptyStream_yieldsNothing() {
        assertEquals(0, events("").size)
    }
}
