// Purpose: feature #156 WI-3 — the geometry + live-CSS helpers shared by Azw3DomProbe and
// Azw3JustifyConnectedTest. Split out of the probe to keep each file near the repo's ~300-line guidance.
//
// Two things live here, both of which exist because a naive version of them made a measurement lie:
//  - line-box merging, which must preserve DOCUMENT order (a positional sort interleaves CSS columns);
//  - column clustering, without which a "raggedness collapse" figure measures the column pitch instead.
package com.vreader.app.reader

import org.json.JSONArray
import org.json.JSONObject

/** One merged line box of a measured element: its horizontal extent in the section document. */
data class LineBox(val left: Double, val right: Double, val top: Double)

/**
 * Merge a probe's raw client rects into LINE BOXES, **in document order**.
 *
 * `Range.getClientRects()` emits one rect per inline fragment, so a line containing an `<em>` yields
 * several. Consecutive rects on the SAME rounded `top` whose left continues the previous right (within
 * 2px) belong to one line. The 2px tolerance deliberately cannot bridge a COLUMN gap — foliate paginates
 * with multi-column layout, and column gaps are tens of px — so lines in different columns stay distinct
 * rather than being fused into one absurdly wide "line".
 *
 * **Document order is preserved on purpose; do NOT sort by (top, left).** In a multi-column layout every
 * column restarts at the same `top`, so a positional sort INTERLEAVES the columns — which silently makes
 * "the last element" some mid-paragraph line instead of the paragraph's final one. That matters because
 * the final line is precisely the line justification must leave alone, and an earlier revision of this
 * helper sorted, then excluded the wrong line from the justifiable set.
 */
fun lineBoxes(p: JSONObject): List<LineBox> {
    val raw: JSONArray = p.optJSONArray("rects") ?: return emptyList()
    val rects = (0 until raw.length()).mapNotNull { i ->
        raw.optJSONArray(i)?.let { Triple(it.optDouble(0), it.optDouble(1), it.optDouble(2)) }
    }
    val out = mutableListOf<LineBox>()
    for ((left, right, top) in rects) {
        val prev = out.lastOrNull()
        if (prev != null && Math.round(prev.top) == Math.round(top) && left <= prev.right + 2.0) {
            out[out.size - 1] = prev.copy(right = maxOf(prev.right, right))
        } else {
            out.add(LineBox(left, right, top))
        }
    }
    return out
}

/**
 * Assign each line box a COLUMN index by clustering their left edges.
 *
 * Foliate paginates with CSS multi-column, so a single paragraph's lines are spread across two or three
 * columns whose right edges are hundreds of px apart. A raggedness/collapse figure computed across all
 * of them measures the column pitch, not the alignment — the spread stays ~775px whether the text is
 * justified or not. Columns are separated by hundreds of px while a first-line `text-indent` shifts a
 * left edge by only tens, so a 60px tolerance splits columns without splitting an indented first line
 * off its own column.
 */
fun columnIndices(lines: List<LineBox>, tolerancePx: Double = 60.0): List<Int> {
    val lefts = lines.map { it.left }.distinct().sorted()
    val clusters = mutableListOf<MutableList<Double>>()
    for (l in lefts) {
        val last = clusters.lastOrNull()
        if (last != null && l - last.last() <= tolerancePx) last.add(l) else clusters.add(mutableListOf(l))
    }
    return lines.map { line -> clusters.indexOfFirst { c -> c.any { it == line.left } } }
}

/**
 * The vreader display-CSS blob **as it is actually live in the document**, picked out of the section's
 * `<style>` elements by a signature only our blob carries.
 *
 * Gate-4 round 1, High: the control arm was previously rebuilt from `ReaderSettings().foliateDisplayCss()`,
 * which is the production CSS **only if the persisted display settings happen to be the defaults**. With
 * any non-default font size / margin / line-height / family, the "remove one justify rule" control would
 * have ALSO changed the type metrics — and since those change line breaking, the index-wise line
 * comparison between the two arms would have been comparing different layouts while reporting a
 * justification delta. Reading the live blob removes the assumption entirely.
 */
fun liveVreaderCss(probe: JSONObject): String {
    val list = probe.optJSONArray("styleList")
        ?: throw AssertionError("the probe returned no style elements — cannot reconstruct the live CSS")
    val candidates = (0 until list.length()).map { list.optString(it) }
        .filter { it.contains("body * { font-family:") && it.contains("!important") }
    if (candidates.size != 1) {
        throw AssertionError(
            "expected exactly ONE injected vreader style blob in the section document, found " +
                "${candidates.size} of ${list.length()} style elements — the control arm must be derived " +
                "from the live production CSS, not guessed",
        )
    }
    return candidates.single()
}
