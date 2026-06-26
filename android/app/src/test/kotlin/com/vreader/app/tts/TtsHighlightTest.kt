package com.vreader.app.tts

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Feature #121 WI-5 — TtsHighlight: spoken-span → chunk-local span mapping. */
class TtsHighlightTest {
    @Test fun spanFullyInsideChunk() {
        assertEquals(2 until 6, TtsHighlight.localSpan(chunkStart = 10, chunkEnd = 30, charStart = 12, charEnd = 16))
    }

    @Test fun spanStraddlesChunkStart() {
        // sentence [5,15) over chunk [10,30) → local [0,5)
        assertEquals(0 until 5, TtsHighlight.localSpan(10, 30, 5, 15))
    }

    @Test fun spanStraddlesChunkEnd() {
        // sentence [25,40) over chunk [10,30) → local [15,20)
        assertEquals(15 until 20, TtsHighlight.localSpan(10, 30, 25, 40))
    }

    @Test fun noIntersectionReturnsNull() {
        assertNull(TtsHighlight.localSpan(10, 30, 40, 50))
        assertNull(TtsHighlight.localSpan(10, 30, 0, 5))
    }

    @Test fun degenerateInputsReturnNull() {
        assertNull(TtsHighlight.localSpan(10, 10, 10, 12))   // empty chunk
        assertNull(TtsHighlight.localSpan(10, 30, 15, 15))   // empty span
    }
}
