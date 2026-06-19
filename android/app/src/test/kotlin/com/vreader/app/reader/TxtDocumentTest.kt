package com.vreader.app.reader

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * TxtDocument range-based chunking + UTF-16-offset addressing (feature #111 WI-1).
 * Offsets index the RAW decoded string (no line-ending normalization) so
 * charOffsetUTF16 stays exact for resume.
 */
class TxtDocumentTest {
    private fun TxtDocument.roundTrip(): String =
        (0 until chunkCount).joinToString("") { textForChunk(it).toString() }

    @Test fun mixedLineEndings_preservedAndChunked() {
        val text = "a\r\nb\nc\rd"   // CRLF, LF, CR, then no terminator
        val doc = TxtDocument.of(text)
        assertEquals(4, doc.chunkCount)
        assertEquals("a\r\n", doc.textForChunk(0).toString())
        assertEquals("b\n", doc.textForChunk(1).toString())
        assertEquals("c\r", doc.textForChunk(2).toString())
        assertEquals("d", doc.textForChunk(3).toString())
        assertEquals("round-trips byte-for-byte", text, doc.roundTrip())
        assertEquals(3, doc.offsetForChunk(1))
        assertEquals(5, doc.offsetForChunk(2))
    }

    @Test fun offsetForChunk_chunkForOffset_roundTrip() {
        val doc = TxtDocument.of("line1\nline2\nline3\nlast")
        for (i in 0 until doc.chunkCount) {
            assertEquals(i, doc.chunkForOffset(doc.offsetForChunk(i)))
        }
        // An offset inside a chunk resolves to that chunk.
        assertEquals(1, doc.chunkForOffset(doc.offsetForChunk(1) + 2))
    }

    @Test fun eofClamp_andNegative() {
        val doc = TxtDocument.of("a\nb\nc")
        assertEquals(doc.chunkCount - 1, doc.chunkForOffset(10_000))   // past EOF
        assertEquals(0, doc.chunkForOffset(-50))                       // before start
    }

    @Test fun surrogatePairs_neverSplitMidPair() {
        // A long line of emojis (each a surrogate pair) far exceeding the chunk bound.
        val emoji = "😀"   // U+1F600, one surrogate pair (2 UTF-16 units)
        val text = emoji.repeat(5_000)   // 10,000 UTF-16 units, no line breaks
        val doc = TxtDocument.of(text, maxChunkChars = 1000)
        assertTrue("a huge line is hard-split", doc.chunkCount > 1)
        assertEquals("round-trips exactly", text, doc.roundTrip())
        // No chunk boundary lands on a low surrogate (which would split a pair).
        for (i in 0 until doc.chunkCount) {
            val start = doc.offsetForChunk(i)
            assertFalse("chunk start $start is mid-surrogate-pair", text[start].isLowSurrogate())
        }
    }

    @Test fun noNewline_hardSplitByMaxChunk() {
        val text = "x".repeat(10_000)
        val doc = TxtDocument.of(text, maxChunkChars = 4000)
        assertTrue(doc.chunkCount >= 3)
        assertEquals(text, doc.roundTrip())
    }

    @Test fun emptyDocument_isInert() {
        val doc = TxtDocument.of("")
        assertEquals(0, doc.chunkCount)
        assertEquals(0, doc.offsetForChunk(0))
        assertEquals(0, doc.chunkForOffset(5))
        assertEquals("", doc.textForChunk(0).toString())
    }

    @Test fun singleLine_noTerminator_isOneChunk() {
        val doc = TxtDocument.of("just one line")
        assertEquals(1, doc.chunkCount)
        assertEquals("just one line", doc.textForChunk(0).toString())
    }
}
