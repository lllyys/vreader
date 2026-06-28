// Purpose: feature #122 WI-2 (#110 Phase 3) — a minimal TXT progress provider. The TXT reader has
// chunks (not chapters) and no progress model; reading-stats' "time left in book" needs a 0..1
// fraction. Pure: the top-visible char offset over the document's total length. No "left in chapter"
// for TXT (no chapter index).
package com.vreader.app.reader

object TxtProgress {
    /** Reading progress 0..1 = [firstVisibleCharOffset] / [textLength] (clamped). 0 for empty text. */
    fun fraction(firstVisibleCharOffset: Int, textLength: Int): Float {
        if (textLength <= 0) return 0f
        return (firstVisibleCharOffset.toFloat() / textLength).coerceIn(0f, 1f)
    }
}
