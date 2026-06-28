// Purpose: feature #124 WI-1 — pure source↔chunk offset math for TXT highlighting. For TXT the rendered
// text equals the source, so a chunk-local rendered offset maps to a source offset by adding the chunk's
// base; a source range splits into the per-chunk (half-open) ranges it spans, for wash rendering.
package com.vreader.app.reader

/** A source range projected onto one chunk: the chunk index + the chunk-LOCAL half-open range. */
data class ChunkRange(val chunkIndex: Int, val local: Utf16Range)

object TxtSourceOffsets {
    /** Chunk-local rendered offset → absolute source UTF-16 offset (TXT identity: render == source). */
    fun sourceOffset(doc: TxtDocument, chunkIndex: Int, offsetInChunk: Int): Int =
        doc.offsetForChunk(chunkIndex) + offsetInChunk

    /**
     * Split a half-open SOURCE [range] into the per-chunk LOCAL ranges it covers. Each entry's `local`
     * is in that chunk's coordinate space (`0 .. chunkLength`). Chunks not overlapping the range are
     * omitted; an empty/degenerate slice in a chunk is skipped.
     */
    fun chunkRanges(doc: TxtDocument, range: Utf16Range): List<ChunkRange> {
        if (range.isEmpty || doc.chunkCount == 0) return emptyList()
        val out = ArrayList<ChunkRange>()
        var i = doc.chunkForOffset(range.startInclusive).coerceIn(0, doc.chunkCount - 1)
        while (i < doc.chunkCount) {
            val base = doc.offsetForChunk(i)
            if (base >= range.endExclusive) break          // past the range
            val len = doc.textForChunk(i).length
            val chunkStart = base
            val chunkEnd = base + len
            val s = maxOf(range.startInclusive, chunkStart) - base
            val e = minOf(range.endExclusive, chunkEnd) - base
            if (e > s) out.add(ChunkRange(i, Utf16Range(s, e)))
            i++
        }
        return out
    }
}
