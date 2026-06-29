// Purpose: feature #124 WI-3 — drives the TXT custom selection. Each visible chunk registers its
// TextLayoutResult + LayoutCoordinates; the controller converts a pointer (LazyColumn-local) → window
// space → the hit chunk's local space → rendered offset → SOURCE offset (TxtSourceOffsets), and resolves
// a word boundary at long-press. Selection is a SOURCE Utf16Range; the in-progress range renders as an
// accent wash. Kept off the Activity so the geometry is isolated; the Activity wires the gesture +
// popover + persistence.
package com.vreader.app.reader

import androidx.compose.runtime.Stable
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.text.TextLayoutResult
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

@Stable
class TxtSelectionController(
    private val doc: TxtDocument,
    // feature #125 — format-aware rendered↔source bridge. The chunk TextLayoutResults are built from the
    // RENDERED text, so getOffsetForPosition/getWordBoundary/getCursorRect speak rendered coords; the
    // mapper converts them to/from the SOURCE coords selections + highlights are stored in. TXT = identity.
    private val mapper: ChunkTextMapper,
) {
    private data class ChunkInfo(val layout: TextLayoutResult, val coords: LayoutCoordinates)
    /** A resolved hit: the chunk index/info + the chunk-local rendered offset + the absolute source offset. */
    private data class Hit(val chunkIndex: Int, val info: ChunkInfo, val rendered: Int, val source: Int)
    private val chunks = HashMap<Int, ChunkInfo>()
    private var lazyCoords: LayoutCoordinates? = null
    // the initial word selected at long-press — the FIXED anchor; drags extend relative to it (never drop it).
    private var anchorRange: Utf16Range? = null

    private val _selection = MutableStateFlow<Utf16Range?>(null)
    val selection: StateFlow<Utf16Range?> = _selection.asStateFlow()

    fun setLazyCoords(coords: LayoutCoordinates) { lazyCoords = coords }
    fun registerChunk(index: Int, layout: TextLayoutResult, coords: LayoutCoordinates) {
        chunks[index] = ChunkInfo(layout, coords)
    }
    fun unregisterChunk(index: Int) { chunks.remove(index) }

    /** Pointer (LazyColumn-local) → the hit chunk + chunk-local rendered offset + source offset. The hit
     *  chunk is used for BOTH the source mapping AND word-boundary lookup (avoids a chunk-boundary shift).
     *  [allowNearest]: for a DRAG, fall back to the nearest chunk when the point is past the text; for a
     *  TAP-to-edit, require the point to actually be inside a text chunk (else a margin tap could edit). */
    private fun hitAt(localPoint: Offset, allowNearest: Boolean = true): Hit? {
        val lz = lazyCoords ?: return null
        if (chunks.isEmpty()) return null
        val windowPoint = lz.localToWindow(localPoint)
        val hit = chunks.entries.firstOrNull { it.value.coords.boundsInWindow().contains(windowPoint) }
            ?: (if (allowNearest) chunks.entries.minByOrNull { verticalDistance(it.value.coords.boundsInWindow(), windowPoint) } else null)
            ?: return null
        val chunkLocal = hit.value.coords.windowToLocal(windowPoint)
        val rendered = hit.value.layout.getOffsetForPosition(chunkLocal).coerceIn(0, hit.value.layout.layoutInput.text.length)
        // rendered cursor → chunk-local source (empty rendered range maps to the source edge) → global source.
        val localSource = mapper.renderedRangeToSource(hit.key, Utf16Range(rendered, rendered)).startInclusive
        return Hit(hit.key, hit.value, rendered, doc.offsetForChunk(hit.key) + localSource)
    }

    /** Long-press: select the word under [localPoint] (word boundary in the HIT chunk, mapped to source). */
    fun beginAt(localPoint: Offset) {
        val hit = hitAt(localPoint) ?: return
        val word = hit.info.layout.getWordBoundary(hit.rendered)   // RENDERED coords in the hit chunk
        val base = doc.offsetForChunk(hit.chunkIndex)
        // rendered word → chunk-local source span → global source (markers stripped for MD).
        val src = mapper.renderedRangeToSource(hit.chunkIndex, Utf16Range(word.start, word.end))
        val start = base + src.startInclusive
        val end = base + src.endExclusive
        val range = if (end > start) Utf16Range(start, end) else Utf16Range(hit.source, (hit.source + 1).coerceAtMost(doc.text.length))
        anchorRange = range
        _selection.value = range
    }

    /** Drag: extend relative to the FIXED [anchorRange] (the initial word) — extending before it grows the
     *  start, after it grows the end, inside it keeps the word. The anchor word is never dropped. */
    fun extendTo(localPoint: Offset) {
        val anchor = anchorRange ?: return
        val off = (hitAt(localPoint) ?: return).source.coerceIn(0, doc.text.length)
        _selection.value = when {
            off <= anchor.startInclusive -> Utf16Range(off, anchor.endExclusive)
            off >= anchor.endExclusive -> Utf16Range(anchor.startInclusive, off)
            else -> anchor
        }
    }

    fun clear() { _selection.value = null; anchorRange = null }

    /** The current selection range, or null. */
    fun currentRange(): Utf16Range? = _selection.value

    /** Resolve a tap (LazyColumn-local) to a SOURCE offset, for hit-testing an existing highlight. Strict
     *  (no nearest-chunk fallback) so a tap in the margin/blank space doesn't edit a nearby highlight. */
    fun resolveSourceOffset(localPoint: Offset): Int? = hitAt(localPoint, allowNearest = false)?.source

    /** Convert a LazyColumn-local point to window coords (to anchor the edit popover at a tap). */
    fun toWindow(localPoint: Offset): Offset? = lazyCoords?.localToWindow(localPoint)

    /** Whether the current selection is a persist-worthy range (in-bounds, non-empty, surrogate-safe). */
    fun isCurrentSelectionValid(): Boolean = _selection.value?.let { TxtSelection.isValid(it, doc.text) } ?: false

    /** The VISIBLE (rendered) substring of the current selection — for the popover / copy / share / UI.
     *  For TXT this equals the source; for MD it's the marker-stripped rendered text the user sees. */
    fun selectedVisibleText(): String? {
        val r = _selection.value ?: return null
        if (r.isEmpty || r.endExclusive > doc.text.length) return null
        val sb = StringBuilder()
        for (cr in TxtSourceOffsets.chunkRanges(doc, r)) {
            sb.append(mapper.visibleText(cr.chunkIndex, mapper.sourceRangeToRendered(cr.chunkIndex, cr.local)))
        }
        return sb.toString().ifEmpty { null }
    }

    /** The SOURCE (markdown/raw) substring of the current selection — for the locator textQuote + anchor. */
    fun selectedSourceText(): String? {
        val r = _selection.value ?: return null
        if (r.isEmpty || r.endExclusive > doc.text.length) return null
        return doc.text.substring(r.startInclusive, r.endExclusive)
    }

    /** The in-progress selection projected onto [chunkIndex] as a chunk-local RENDERED range, for the
     *  accent wash (`getPathForRange` speaks rendered coords). Source→rendered via the mapper (MD). */
    fun selectionForChunk(chunkIndex: Int): Utf16Range? {
        val r = _selection.value ?: return null
        val localSource = TxtSourceOffsets.chunkRanges(doc, r).firstOrNull { it.chunkIndex == chunkIndex }?.local ?: return null
        return mapper.sourceRangeToRendered(chunkIndex, localSource)
    }

    /** The window-space point just below the selection's end, to anchor the popover. */
    fun selectionEndAnchorWindow(): Offset? {
        val r = _selection.value ?: return null
        val endChunk = doc.chunkForOffset((r.endExclusive - 1).coerceAtLeast(0)).coerceIn(0, doc.chunkCount - 1)
        val info = chunks[endChunk] ?: return null
        val base = doc.offsetForChunk(endChunk)
        // source end → chunk-local source → rendered cursor (end-affinity) for getCursorRect.
        val localSourceEnd = (r.endExclusive - base).coerceAtLeast(0)
        val renderedEnd = mapper.renderedCursorForSourceEnd(endChunk, localSourceEnd).coerceIn(0, info.layout.layoutInput.text.length)
        val rect = info.layout.getCursorRect(renderedEnd)
        return info.coords.localToWindow(Offset(rect.left, rect.bottom))
    }

    private fun verticalDistance(bounds: androidx.compose.ui.geometry.Rect, p: Offset): Float = when {
        p.y < bounds.top -> bounds.top - p.y
        p.y > bounds.bottom -> p.y - bounds.bottom
        else -> 0f
    }
}
