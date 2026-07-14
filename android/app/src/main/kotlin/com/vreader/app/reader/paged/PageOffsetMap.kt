// Purpose: feature #137 WI-4 (#110 Phase 3, box E) — a page's rendered↔source bridge for the paged
// TXT/MD renderer, SPAN-preserving. It is a COMPOSITION of the page's constituent chunk maps
// (identity for TXT, MarkdownOffsetMap for MD), spliced by per-segment (renderedBase, srcBase)
// offsets, and it DELEGATES every query to the owning segment (adjusted by those bases). So the exact
// dual-affinity srcStart/srcEnd spans + both range-conversion directions the current selection/wash
// rely on are reproduced VERBATIM — just at PAGE scope (page-local rendered index ↔ GLOBAL source
// UTF-16). Resolves Gate-2 R2-Critical-1 (a single IntArray page map is too lossy for MD dual-affinity).
//
// Built LAZILY per rendered page (never full-book); one instance per rendered page.
//
// @coordinates-with: MarkdownOffsetMap.kt (the per-chunk conversions this delegates to),
//   TxtPaginator.kt (renderPage builds the segment list), TxtSelectionController.kt (WI-7a — paged
//   hitAt resolves pointer → page-local rendered → this map).
package com.vreader.app.reader.paged

import com.vreader.app.reader.MarkdownOffsetMap
import com.vreader.app.reader.Utf16Range

/**
 * One segment of a page: a contiguous run of page-local rendered chars `[renderedBase, renderedBase +
 * renderedLen)` that maps to ONE source chunk. For MD the segment owns a [MarkdownOffsetMap] (chunk-
 * local rendered↔source); for TXT [chunkMap] is null (identity — rendered == source at chunk scope).
 * [srcBase] is the chunk's document start source-UTF-16 offset (added to reach GLOBAL source coords).
 */
class PageSegment private constructor(
    private val chunkMap: MarkdownOffsetMap?,
    val renderedBase: Int,
    val srcBase: Int,
    val renderedLen: Int,
    /** Chunk-local rendered index this segment's page-local `renderedBase` corresponds to (0 for a
     *  whole-chunk segment; >0 for a mid-chunk split slice). Delegation adds this to reach the chunk map. */
    private val renderedStartInChunk: Int,
) {
    /** Page-local rendered index this segment covers: `[renderedBase, renderedEndExclusive)`. */
    val renderedEndExclusive: Int get() = renderedBase + renderedLen

    /** Chunk-local rendered index for a page-local [idx]. */
    private fun chunkLocal(idx: Int): Int = renderedStartInChunk + (idx - renderedBase)

    /** Page-local rendered [idx] (assumed in-segment) → GLOBAL source start offset (start-affinity). */
    fun sourceStartAt(idx: Int): Int {
        val local = chunkLocal(idx)
        return if (chunkMap == null) {
            srcBase + (idx - renderedBase).coerceIn(0, renderedLen)
        } else {
            srcBase + chunkMap.renderedRangeToSource(Utf16Range(local, local + 1)).startInclusive
        }
    }

    /** Page-local rendered [idx] (assumed in-segment) → GLOBAL source dual-affinity span. */
    fun sourceSpanAt(idx: Int): Utf16Range {
        return if (chunkMap == null) {
            val a = srcBase + (idx - renderedBase).coerceAtLeast(0)
            Utf16Range(a, a + 1)
        } else {
            val local = chunkLocal(idx)
            val s = chunkMap.renderedRangeToSource(Utf16Range(local, local + 1))
            Utf16Range(srcBase + s.startInclusive, srcBase + s.endExclusive)
        }
    }

    /** The GLOBAL source end past this segment's last rendered char (the segment's source extent). */
    fun sourceEndBound(): Int {
        if (renderedLen == 0) return srcBase
        return if (chunkMap == null) {
            srcBase + renderedLen
        } else {
            val last = renderedStartInChunk + renderedLen - 1
            srcBase + chunkMap.renderedRangeToSource(Utf16Range(last, last + 1)).endExclusive
        }
    }

    /** GLOBAL source range → this segment's page-local rendered range (marker-only → empty). */
    fun sourceRangeToRenderedLocal(globalSource: Utf16Range): Utf16Range {
        val a = globalSource.startInclusive - srcBase
        val b = globalSource.endExclusive - srcBase
        return if (chunkMap == null) {
            val la = a.coerceIn(0, renderedLen)
            val lb = b.coerceIn(la, renderedLen)
            Utf16Range(renderedBase + la, renderedBase + lb)
        } else {
            // Chunk map speaks chunk-local rendered; shift OUT by renderedStartInChunk, then to page-local.
            val local = chunkMap.sourceRangeToRendered(Utf16Range(a, b))
            val la = (local.startInclusive - renderedStartInChunk).coerceIn(0, renderedLen)
            val lb = (local.endExclusive - renderedStartInChunk).coerceIn(la, renderedLen)
            Utf16Range(renderedBase + la, renderedBase + lb)
        }
    }

    companion object {
        /** A TXT (identity) segment covering [renderedLen] rendered chars from source [srcBase]. */
        fun identity(renderedBase: Int, srcBase: Int, renderedLen: Int): PageSegment =
            PageSegment(null, renderedBase, srcBase, renderedLen.coerceAtLeast(0), renderedStartInChunk = 0)

        /** A whole-chunk MD segment wrapping [chunkMap]; [renderedLen] = the chunk's rendered length. */
        fun markdown(chunkMap: MarkdownOffsetMap, renderedBase: Int, srcBase: Int): PageSegment =
            PageSegment(chunkMap, renderedBase, srcBase, chunkMap.renderedText.length, renderedStartInChunk = 0)

        /**
         * A mid-chunk MD slice: page-local `[renderedBase, renderedBase+renderedLen)` maps to chunk-local
         * rendered `[renderedStartInChunk, renderedStartInChunk+renderedLen)` of [chunkMap]. [srcBase] is
         * the chunk's document start (delegation shifts to chunk-local then adds srcBase for global).
         */
        fun markdownSlice(
            chunkMap: MarkdownOffsetMap,
            renderedBase: Int,
            srcBase: Int,
            renderedStartInChunk: Int,
            renderedLen: Int,
        ): PageSegment =
            PageSegment(chunkMap, renderedBase, srcBase, renderedLen.coerceAtLeast(0), renderedStartInChunk)
    }
}

/**
 * A page's rendered↔source bridge. Coords: rendered = PAGE-LOCAL UTF-16 (index into the page's
 * concatenated rendered AnnotatedString); source = GLOBAL document source UTF-16.
 */
class PageOffsetMap(private val segments: List<PageSegment>) {

    /** Total page-local rendered length = the last segment's exclusive end (0 if empty). */
    private val renderedLength: Int get() = segments.lastOrNull()?.renderedEndExclusive ?: 0

    /** GLOBAL source end past the page's last rendered char (0 if empty). */
    private fun sourceEndBound(): Int = segments.lastOrNull()?.sourceEndBound() ?: 0

    /** The segment owning page-local rendered [idx], or null if [idx] is out of range. */
    private fun segmentFor(idx: Int): PageSegment? =
        segments.firstOrNull { idx >= it.renderedBase && idx < it.renderedEndExclusive }

    /** Page-local rendered [renderedIdx] → GLOBAL source start (start-affinity). Clamps out-of-range. */
    fun sourceAt(renderedIdx: Int): Int {
        if (segments.isEmpty()) return 0
        val clamped = renderedIdx.coerceIn(0, renderedLength)
        if (clamped >= renderedLength) return sourceEndBound()
        return segmentFor(clamped)?.sourceStartAt(clamped) ?: sourceEndBound()
    }

    /**
     * Page-local rendered `[a, b)` → GLOBAL source `[sourceAt(a), end-affinity source of b-1)`.
     * Clamped to `0..renderedLength` first; a degenerate/empty range collapses to an empty source
     * range at `a`'s source edge (mirrors [MarkdownOffsetMap.renderedRangeToSource]).
     */
    fun renderedRangeToSource(r: Utf16Range): Utf16Range {
        if (segments.isEmpty()) return Utf16Range(0, 0)
        val a = r.startInclusive.coerceIn(0, renderedLength)
        val b = r.endExclusive.coerceIn(0, renderedLength)
        if (b <= a) {
            val at = if (a < renderedLength) sourceAt(a) else sourceEndBound()
            return Utf16Range(at, at)
        }
        val start = sourceAt(a)
        val endSeg = segmentFor(b - 1)
        val end = endSeg?.sourceSpanAt(b - 1)?.endExclusive ?: sourceEndBound()
        return Utf16Range(start, end)
    }

    /**
     * GLOBAL source `[s0, s1)` → PAGE-LOCAL rendered, span-preserving + affinity-correct, delegated
     * to the owning segment(s). A range wholly in the markers between segments collapses to EMPTY.
     */
    fun sourceRangeToRendered(srcRange: Utf16Range): Utf16Range? {
        if (segments.isEmpty() || srcRange.isEmpty) return Utf16Range(0, 0)
        // Segments overlapping the source range, in order.
        val overlapping = segments.filter {
            it.srcBase < srcRange.endExclusive && it.sourceEndBound() > srcRange.startInclusive
        }
        if (overlapping.isEmpty()) {
            // No rendered char overlaps → collapse to an empty range at the boundary cursor.
            val cursor = segments.firstOrNull { it.srcBase >= srcRange.startInclusive }?.renderedBase
                ?: renderedLength
            return Utf16Range(cursor, cursor)
        }
        var start = Int.MAX_VALUE
        var end = Int.MIN_VALUE
        for (seg in overlapping) {
            val local = seg.sourceRangeToRenderedLocal(srcRange)
            if (local.length > 0 || (local.startInclusive in seg.renderedBase..seg.renderedEndExclusive)) {
                if (local.length > 0) {
                    start = minOf(start, local.startInclusive)
                    end = maxOf(end, local.endExclusive)
                }
            }
        }
        if (end <= start) {
            // Every overlapping segment collapsed (marker-only source) → empty range at the cursor.
            val cursor = overlapping.first().sourceRangeToRenderedLocal(srcRange).startInclusive
            return Utf16Range(cursor, cursor)
        }
        return Utf16Range(start, end)
    }

    /** Page-local rendered [renderedIdx] → GLOBAL source dual-affinity span (srcStart..srcEnd). */
    fun renderedSpanAt(renderedIdx: Int): Utf16Range {
        if (segments.isEmpty()) return Utf16Range(0, 0)
        val clamped = renderedIdx.coerceIn(0, (renderedLength - 1).coerceAtLeast(0))
        val seg = segmentFor(clamped) ?: return Utf16Range(sourceEndBound(), sourceEndBound())
        return seg.sourceSpanAt(clamped)
    }
}
