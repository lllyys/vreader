// Purpose: feature #124 WI-1 — given a tapped source offset, find which stored highlight (if any) it
// falls in. Overlap precedence: the NEWEST highlight (max createdAt) wins, so a recolor/re-highlight on
// top is what a tap edits. Pure (operates on HighlightRecord locator charRange fields).
package com.vreader.app.reader

import com.vreader.app.annotations.HighlightRecord

object TxtHighlightHitTester {
    /** The highlight whose half-open `[charRangeStartUTF16, charRangeEndUTF16)` contains [sourceOffset],
     *  newest-first on overlap; null if none. Highlights without a TXT char range are ignored. */
    fun highlightAt(sourceOffset: Int, highlights: List<HighlightRecord>): HighlightRecord? =
        highlights
            .filter { h ->
                val s = h.locator.charRangeStartUTF16
                val e = h.locator.charRangeEndUTF16
                s != null && e != null && sourceOffset >= s && sourceOffset < e
            }
            .maxByOrNull { it.createdAt }
}
