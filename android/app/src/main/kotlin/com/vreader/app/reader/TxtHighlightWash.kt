// Purpose: feature #124 WI-2 — render stored TXT highlights as colored washes. `TxtWashMapper` (pure)
// projects each highlight's SOURCE range onto the per-chunk LOCAL ranges it spans; `drawWashes` paints
// them BEHIND the text via `TextLayoutResult.getPathForRange` (NOT `SpanStyle(background=)`, which
// doesn't compose for overlapping ranges — Gate-2). The wash color is the AnnotationColor's translucent
// ARGB (`washHex`); read-aloud stays on top (it's a separate span on the AnnotatedString).
package com.vreader.app.reader

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.text.TextLayoutResult
import com.vreader.app.annotations.AnnotationColor
import com.vreader.app.annotations.HighlightRecord

/** A highlight slice within one chunk: the chunk-LOCAL half-open range + its color. */
data class WashSpan(val local: Utf16Range, val color: AnnotationColor)

object TxtWashMapper {
    /** Project every highlight's `[charRangeStartUTF16, charRangeEndUTF16)` onto the chunks it spans. */
    fun washesByChunk(doc: TxtDocument, highlights: List<HighlightRecord>): Map<Int, List<WashSpan>> {
        val map = HashMap<Int, MutableList<WashSpan>>()
        for (h in highlights) {
            val s = h.locator.charRangeStartUTF16 ?: continue
            val e = h.locator.charRangeEndUTF16 ?: continue
            if (e <= s) continue
            for (cr in TxtSourceOffsets.chunkRanges(doc, Utf16Range(s, e))) {
                map.getOrPut(cr.chunkIndex) { mutableListOf() }.add(WashSpan(cr.local, h.color))
            }
        }
        return map
    }
}

/** Paint [washes] behind a chunk's text using its [layout]. Call from `Modifier.drawBehind`. */
fun DrawScope.drawWashes(layout: TextLayoutResult, washes: List<WashSpan>) {
    for (w in washes) {
        if (w.local.endExclusive <= w.local.startInclusive) continue
        val end = w.local.endExclusive.coerceAtMost(layout.layoutInput.text.length)
        val start = w.local.startInclusive.coerceIn(0, end)
        if (end <= start) continue
        drawPath(layout.getPathForRange(start, end), color = Color(android.graphics.Color.parseColor(w.color.washHex)))
    }
}
