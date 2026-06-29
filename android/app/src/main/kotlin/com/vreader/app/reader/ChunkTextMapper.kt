// Purpose: feature #125 WI-2 — the format-aware chunk text + offset seam. One instance per open book;
// the SINGLE per-chunk render+cache owner so the body composable, the selection controller, and the
// highlight wash all read the same rendered text + the same offset map (no recompute, no downcast).
// All ranges are CHUNK-LOCAL UTF-16 (the caller adds the chunk's document start offset).
//
// TXT == IdentityChunkTextMapper (rendered == source, every conversion is identity). MD ==
// MarkdownChunkTextMapper (bridges rendered↔source via a lazily-computed, LRU-cached MarkdownOffsetMap
// per visible/highlighted chunk — never precomputed for all chunks).
//
// @coordinates-with: MarkdownOffsetMap.kt (the per-chunk conversions), TxtDocument.kt (the chunk source),
//   TxtReaderActivity.kt (#125 WI-3 builds the right impl from book.originalFormat), TxtSelectionController.kt
//   / TxtHighlightWash.kt (#125 WI-3 consumers).
package com.vreader.app.reader

import androidx.compose.ui.text.AnnotatedString

/** Format-aware chunk text + rendered↔source conversions. CHUNK-LOCAL coords. */
interface ChunkTextMapper {
    /** The text the body draws for [chunkIndex] (TXT: raw; MD: rendered AnnotatedString). */
    fun renderedText(chunkIndex: Int): AnnotatedString

    /** Rendered range → source range (chunk-local). */
    fun renderedRangeToSource(chunkIndex: Int, rendered: Utf16Range): Utf16Range

    /** Source range → rendered range (chunk-local, clamped; marker-only → empty). */
    fun sourceRangeToRendered(chunkIndex: Int, source: Utf16Range): Utf16Range

    /** Rendered cursor (end-affinity) for a source end — positions the popover anchor. */
    fun renderedCursorForSourceEnd(chunkIndex: Int, sourceEnd: Int): Int

    /** The VISIBLE (rendered) substring for copy/share/UI. */
    fun visibleText(chunkIndex: Int, rendered: Utf16Range): String

    /** The SOURCE (markdown) substring for the textQuote / anchor. */
    fun sourceText(chunkIndex: Int, source: Utf16Range): String
}

/** TXT: rendered == source, every conversion is identity — clamped to the chunk's `0..length`. */
class IdentityChunkTextMapper(private val doc: TxtDocument) : ChunkTextMapper {
    private fun chunk(chunkIndex: Int): String = doc.textForChunk(chunkIndex).toString()
    override fun renderedText(chunkIndex: Int): AnnotatedString = AnnotatedString(chunk(chunkIndex))
    override fun renderedRangeToSource(chunkIndex: Int, rendered: Utf16Range): Utf16Range = clampRange(chunkIndex, rendered)
    override fun sourceRangeToRendered(chunkIndex: Int, source: Utf16Range): Utf16Range = clampRange(chunkIndex, source)
    override fun renderedCursorForSourceEnd(chunkIndex: Int, sourceEnd: Int): Int =
        sourceEnd.coerceIn(0, doc.textForChunk(chunkIndex).length)
    override fun visibleText(chunkIndex: Int, rendered: Utf16Range): String = slice(chunk(chunkIndex), rendered)
    override fun sourceText(chunkIndex: Int, source: Utf16Range): String = slice(chunk(chunkIndex), source)
    /** Identity is in-bounds by definition; clamp to the chunk's `0..length` so a corrupt input can't escape. */
    private fun clampRange(chunkIndex: Int, r: Utf16Range): Utf16Range {
        val len = doc.textForChunk(chunkIndex).length
        val a = r.startInclusive.coerceIn(0, len)
        return Utf16Range(a, r.endExclusive.coerceIn(a, len))
    }
    private fun slice(s: String, r: Utf16Range): String {
        val a = r.startInclusive.coerceIn(0, s.length)
        return s.substring(a, r.endExclusive.coerceIn(a, s.length))
    }
}

/** MD: lazily computes + LRU-caches the per-chunk [MarkdownOffsetMap]; the single render+cache owner. */
class MarkdownChunkTextMapper(private val doc: TxtDocument, private val maxCached: Int = 24) : ChunkTextMapper {
    private val cache = object : LinkedHashMap<Int, MarkdownOffsetMap>(maxCached.coerceAtLeast(1), 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<Int, MarkdownOffsetMap>): Boolean = size > maxCached
    }

    private fun mapFor(chunkIndex: Int): MarkdownOffsetMap =
        cache.getOrPut(chunkIndex) { MarkdownOffsetMap(MarkdownRenderer.renderWithMap(doc.textForChunk(chunkIndex).toString())) }

    /** Test visibility into the LRU bound. */
    val cacheSize: Int get() = cache.size

    override fun renderedText(chunkIndex: Int): AnnotatedString = mapFor(chunkIndex).renderedText
    override fun renderedRangeToSource(chunkIndex: Int, rendered: Utf16Range): Utf16Range = mapFor(chunkIndex).renderedRangeToSource(rendered)
    override fun sourceRangeToRendered(chunkIndex: Int, source: Utf16Range): Utf16Range = mapFor(chunkIndex).sourceRangeToRendered(source)
    override fun renderedCursorForSourceEnd(chunkIndex: Int, sourceEnd: Int): Int = mapFor(chunkIndex).renderedCursorForSourceEnd(sourceEnd)
    override fun visibleText(chunkIndex: Int, rendered: Utf16Range): String {
        val t = mapFor(chunkIndex).renderedText.text
        val a = rendered.startInclusive.coerceIn(0, t.length)
        return t.substring(a, rendered.endExclusive.coerceIn(a, t.length))
    }
    override fun sourceText(chunkIndex: Int, source: Utf16Range): String {
        val s = doc.textForChunk(chunkIndex).toString()
        val a = source.startInclusive.coerceIn(0, s.length)
        return s.substring(a, source.endExclusive.coerceIn(a, s.length))
    }
}
