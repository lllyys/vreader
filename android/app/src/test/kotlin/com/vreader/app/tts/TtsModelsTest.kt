package com.vreader.app.tts

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Feature #121 WI-1 — TtsUtterance id encode/parse robustness (stale/hostile callback ids). */
class TtsModelsTest {
    @Test fun roundTripsValidId() {
        assertEquals("3:7", TtsUtterance(3, 7, "x").utteranceId)
        assertEquals(3L to 7, TtsUtterance.parse("3:7"))
    }

    @Test fun rejectsMalformedIds() {
        assertNull(TtsUtterance.parse(null))
        assertNull(TtsUtterance.parse(""))
        assertNull(TtsUtterance.parse("1"))
        assertNull(TtsUtterance.parse("1:2:3"))
        assertNull(TtsUtterance.parse("a:b"))
        assertNull(TtsUtterance.parse("-1:2"))   // negative generation
        assertNull(TtsUtterance.parse("1:-2"))   // negative index
    }
}
