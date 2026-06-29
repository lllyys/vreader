// Purpose: feature #125 WI-2 — per-rendered-char source-span map for ONE MD line-chunk. Wraps the
// MarkdownRenderer.renderWithMap output (srcStart/srcEnd) and converts CHUNK-LOCAL rendered ranges ↔
// CHUNK-LOCAL markdown-source ranges. The caller adds the chunk's document start offset to reach the
// global source coords highlights are stored in. Pure JVM (unit-testable).
//
// Dual-affinity: a stripped marker between two visible runs keeps their distinct source positions
// (`**bold**x` → rendered "boldx", where 'x' maps to source 8 not 6). marker-only source ranges
// (the `**`) collapse to an EMPTY rendered range (the wash draws nothing there).
//
// @coordinates-with: MarkdownRenderer.kt (produces MarkdownRendered), ChunkTextMapper.kt (owns the
//   per-chunk maps + global/local translation), TxtHighlightWash.kt (#125 WI-3 projects source→rendered).
package com.vreader.app.reader

import androidx.compose.ui.text.AnnotatedString

/** Rendered↔source conversions for one MD chunk's [MarkdownRendered]. All coords are CHUNK-LOCAL UTF-16. */
class MarkdownOffsetMap(private val rendered: MarkdownRendered) {
    val renderedText: AnnotatedString get() = rendered.text
    private val n: Int get() = rendered.text.length
    private val srcStart get() = rendered.srcStart
    private val srcEnd get() = rendered.srcEnd

    /** The source-end past the last rendered char (the chunk's mapped source extent), or 0 if empty. */
    private fun sourceEndBound(): Int = if (n == 0) 0 else srcEnd[n - 1]

    /**
     * Rendered `[a, b)` → source `[srcStart[a], srcEnd[b-1])`. Clamped to rendered-cursor space `0..n`
     * FIRST, so a wholly out-of-range range collapses correctly: a degenerate/empty range (after
     * clamping `b <= a`) maps to an empty source range at cursor `a`'s source edge (`srcStart[a]`, or
     * the source-end bound past the last char when `a == n`).
     */
    fun renderedRangeToSource(r: Utf16Range): Utf16Range {
        if (n == 0) return Utf16Range(0, 0)
        val a = r.startInclusive.coerceIn(0, n)
        val b = r.endExclusive.coerceIn(0, n)
        if (b <= a) {
            val at = if (a < n) srcStart[a] else sourceEndBound()
            return Utf16Range(at, at)
        }
        return Utf16Range(srcStart[a], srcEnd[b - 1])
    }

    /**
     * Source `[s0, s1)` → rendered, clamped + affinity-correct: rendered start = the first rendered char
     * whose source overlaps the range (`srcEnd[r] > s0`); rendered end = one past the last whose source
     * begins before the range end (`srcStart[r] < s1`). A marker-only source range (no rendered char
     * overlaps) collapses to EMPTY.
     */
    fun sourceRangeToRendered(s: Utf16Range): Utf16Range {
        if (n == 0 || s.isEmpty) return Utf16Range(0, 0)
        val start = renderedCursorForSourceStart(s.startInclusive)
        val end = renderedCursorForSourceEnd(s.endExclusive)
        return if (end > start) Utf16Range(start, end) else Utf16Range(start.coerceAtMost(n), start.coerceAtMost(n))
    }

    /** First rendered char whose source extends past [sourceStart] (start-affinity), or n. */
    fun renderedCursorForSourceStart(sourceStart: Int): Int {
        for (r in 0 until n) if (srcEnd[r] > sourceStart) return r
        return n
    }

    /** One past the last rendered char whose source begins before [sourceEnd] (end-affinity), or 0. */
    fun renderedCursorForSourceEnd(sourceEnd: Int): Int {
        for (r in n - 1 downTo 0) if (srcStart[r] < sourceEnd) return r + 1
        return 0
    }
}
