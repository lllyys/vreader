package com.vreader.app.reader

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Feature #124 WI-1 — [TxtSourceOffsets] source↔chunk math. */
class TxtSourceOffsetsTest {
    // small maxChunkChars to force several chunks (line-grouped under the cap).
    private val doc = TxtDocument.of("AAAA\nBBBB\nCCCC\nDDDD\n", maxChunkChars = 6)

    @Test fun sourceOffset_addsChunkBase() {
        val base2 = doc.offsetForChunk(2)
        assertEquals(base2 + 3, TxtSourceOffsets.sourceOffset(doc, 2, 3))
    }

    @Test fun chunkRanges_singleChunk() {
        val base1 = doc.offsetForChunk(1)
        val ranges = TxtSourceOffsets.chunkRanges(doc, Utf16Range(base1 + 1, base1 + 3))
        assertEquals(1, ranges.size)
        assertEquals(1, ranges[0].chunkIndex)
        assertEquals(Utf16Range(1, 3), ranges[0].local)
    }

    @Test fun chunkRanges_spansChunks_reassemblesToSourceRange() {
        val start = doc.offsetForChunk(0) + 2
        val end = doc.offsetForChunk(2) + 2
        val range = Utf16Range(start, end)
        val parts = TxtSourceOffsets.chunkRanges(doc, range)
        assertTrue("spans >= 2 chunks", parts.size >= 2)
        // each local range maps back into source; the union is contiguous + equals [start, end)
        var cursor = start
        for (p in parts) {
            val base = doc.offsetForChunk(p.chunkIndex)
            assertEquals("contiguous", cursor, base + p.local.startInclusive)
            assertTrue("local within chunk", p.local.endExclusive <= doc.textForChunk(p.chunkIndex).length)
            cursor = base + p.local.endExclusive
        }
        assertEquals("union ends at range end", end, cursor)
    }

    @Test fun chunkRanges_emptyRange_isEmpty() {
        assertTrue(TxtSourceOffsets.chunkRanges(doc, Utf16Range(3, 3)).isEmpty())
    }
}
