// Purpose: feature #137 WI-6a (#110 Phase 3, box E) — the PRODUCTION LineMeasurer: the real wrapper of
// WI-4's line-measurement seam over Compose's TextMeasurer / TextLayoutResult line metrics. Phase-1
// pagination (TxtPaginator.index, off-main) calls measure(text, style, maxWidthPx) to lay a chunk's
// rendered text out at the content-box width and read back its wrapped LINES (each line's char range +
// laid-out height) so a page is cut at the last line that fits.
//
// DETERMINISM CONTRACT (Gate-2 R3 / plan §Pagination-phase-1): this measurer MUST be constructed from
// the SAME FontFamily.Resolver + Density + LayoutDirection the UI (phase-2 render + the scroll body)
// uses, so phase-1's line breaks are byte-identical to what phase-2 draws — otherwise a page boundary
// computed off-main would not match the rendered page (clipped/overflowing text). The host builds ONE
// instance per open from the composition's LocalFontFamilyResolver / LocalDensity / LocalLayoutDirection
// and threads it through both phase-1 (index) and reflow.
//
// THREAD SAFETY: Compose's TextMeasurer is documented safe to call off the main thread (it caches
// internally with its own synchronization); phase-1 runs it on Dispatchers.Default. It never touches the
// shared UI ChunkTextMapper — it only lays out the ALREADY-rendered CharSequence the paginator hands it.
//
// @coordinates-with: TxtPaginator.kt (the LineMeasurer seam + LineMetric it consumes), TxtReaderBody.kt
//   (WI-6a — constructs this from the composition's resolver/density/direction), ReaderTextStyles.kt
//   (the same bodyTextStyle both phases lay out).
package com.vreader.app.reader.paged

import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.Constraints

/**
 * The production [LineMeasurer] — lays [text] out through [textMeasurer] at [maxWidthPx] under [style]
 * and returns one [LineMetric] per WRAPPED line (its char range in the measured text + its laid-out
 * height in px). Overflow/soft-wrap is NOT clipped (`maxLines` unbounded, `softWrap` on) so EVERY
 * wrapped line is reported — the paginator, not the measurer, decides where a page cuts.
 *
 * [textMeasurer], [style] shaping inputs (family resolver / density / direction baked into
 * [textMeasurer]) MUST match the phase-2 render path for deterministic breaks (see file header).
 */
class ComposeLineMeasurer(private val textMeasurer: TextMeasurer) : LineMeasurer {

    override fun measure(text: CharSequence, style: TextStyle, maxWidthPx: Float): List<LineMetric> {
        // A degenerate width would make Compose throw / return nonsense — the paginator already guards a
        // degenerate box, but be defensive: no usable width → no lines (the paginator's min-one-line
        // path still guarantees forward progress on a genuine box).
        val widthCeil = maxWidthPx.toInt()
        if (widthCeil <= 0) return emptyList()

        val layout = textMeasurer.measure(
            text = if (text is AnnotatedString) text else AnnotatedString(text.toString()),
            style = style,
            softWrap = true,
            // Unbounded height + max width: report ALL wrapped lines, clip NONE. maxLines is left at its
            // default (Int.MAX_VALUE) so an over-tall chunk still yields every line for the paginator.
            constraints = Constraints(maxWidth = widthCeil),
        )
        val lineCount = layout.lineCount
        if (lineCount == 0) return emptyList()

        val metrics = ArrayList<LineMetric>(lineCount)
        for (line in 0 until lineCount) {
            val start = layout.getLineStart(line)
            // visibleEnd=false → the true end offset (incl. the trailing line break char) so the reported
            // ranges TILE the measured text with no dropped chars (page-tiling depends on this).
            val end = layout.getLineEnd(line, visibleEnd = false)
            val heightPx = layout.getLineBottom(line) - layout.getLineTop(line)
            metrics.add(LineMetric(start, end, heightPx))
        }
        return metrics
    }
}
