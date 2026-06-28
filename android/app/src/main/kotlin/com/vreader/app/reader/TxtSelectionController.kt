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
class TxtSelectionController(private val doc: TxtDocument) {
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
     *  chunk is used for BOTH the source mapping AND word-boundary lookup (avoids a chunk-boundary shift). */
    private fun hitAt(localPoint: Offset): Hit? {
        val lz = lazyCoords ?: return null
        if (chunks.isEmpty()) return null
        val windowPoint = lz.localToWindow(localPoint)
        val hit = chunks.entries.firstOrNull { it.value.coords.boundsInWindow().contains(windowPoint) }
            ?: chunks.entries.minByOrNull { verticalDistance(it.value.coords.boundsInWindow(), windowPoint) }
            ?: return null
        val chunkLocal = hit.value.coords.windowToLocal(windowPoint)
        val rendered = hit.value.layout.getOffsetForPosition(chunkLocal).coerceIn(0, hit.value.layout.layoutInput.text.length)
        return Hit(hit.key, hit.value, rendered, TxtSourceOffsets.sourceOffset(doc, hit.key, rendered))
    }

    /** Long-press: select the word under [localPoint] (word boundary in the HIT chunk, mapped to source). */
    fun beginAt(localPoint: Offset) {
        val hit = hitAt(localPoint) ?: return
        val word = hit.info.layout.getWordBoundary(hit.rendered)   // rendered coords in the hit chunk
        val base = doc.offsetForChunk(hit.chunkIndex)
        val start = base + word.start
        val end = base + word.end
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

    /** Whether the current selection is a persist-worthy range (in-bounds, non-empty, surrogate-safe). */
    fun isCurrentSelectionValid(): Boolean = _selection.value?.let { TxtSelection.isValid(it, doc.text) } ?: false

    /** The SOURCE substring of the current selection (for the popover's text / copy / share). */
    fun selectedText(): String? {
        val r = _selection.value ?: return null
        if (r.isEmpty || r.endExclusive > doc.text.length) return null
        return doc.text.substring(r.startInclusive, r.endExclusive)
    }

    /** The in-progress selection projected onto [chunkIndex] (chunk-local), for the accent wash. */
    fun selectionForChunk(chunkIndex: Int): Utf16Range? {
        val r = _selection.value ?: return null
        return TxtSourceOffsets.chunkRanges(doc, r).firstOrNull { it.chunkIndex == chunkIndex }?.local
    }

    /** The window-space point just below the selection's end, to anchor the popover. */
    fun selectionEndAnchorWindow(): Offset? {
        val r = _selection.value ?: return null
        val endChunk = doc.chunkForOffset((r.endExclusive - 1).coerceAtLeast(0)).coerceIn(0, doc.chunkCount - 1)
        val info = chunks[endChunk] ?: return null
        val base = doc.offsetForChunk(endChunk)
        val renderedEnd = (r.endExclusive - base).coerceIn(0, info.layout.layoutInput.text.length)
        val rect = info.layout.getCursorRect(renderedEnd)
        return info.coords.localToWindow(Offset(rect.left, rect.bottom))
    }

    private fun verticalDistance(bounds: androidx.compose.ui.geometry.Rect, p: Offset): Float = when {
        p.y < bounds.top -> bounds.top - p.y
        p.y > bounds.bottom -> p.y - bounds.bottom
        else -> 0f
    }
}
