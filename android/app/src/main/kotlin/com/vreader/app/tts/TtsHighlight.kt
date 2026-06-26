// Purpose: feature #121 WI-5 (#110 Phase 3) — pure mapping of a spoken sentence's RAW-text char span
// onto a TXT reader chunk's local span, for the in-reader highlight wash. A sentence may straddle
// chunk boundaries, so this intersects the spoken [charStart,charEnd) with a chunk's [start,end).
// JVM-testable (no Compose / Android).
package com.vreader.app.tts

object TtsHighlight {
    /**
     * The half-open local range `[start, end)` WITHIN a chunk spanning RAW offsets
     * `[chunkStart, chunkEnd)` to wash for the spoken `[charStart, charEnd)`, or null when the spoken
     * span doesn't intersect this chunk. Clamps defensively.
     */
    fun localSpan(chunkStart: Int, chunkEnd: Int, charStart: Int, charEnd: Int): IntRange? {
        if (chunkEnd <= chunkStart || charEnd <= charStart) return null
        val s = maxOf(charStart, chunkStart)
        val e = minOf(charEnd, chunkEnd)
        if (s >= e) return null
        return (s - chunkStart) until (e - chunkStart)
    }
}
