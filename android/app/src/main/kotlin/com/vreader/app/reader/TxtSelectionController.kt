// Purpose: feature #124 WI-3 — drives the TXT custom selection. Each visible chunk registers its
// TextLayoutResult + LayoutCoordinates; the controller converts a pointer (LazyColumn-local) → window
// space → the hit chunk's local space → rendered offset → SOURCE offset (TxtSourceOffsets), and resolves
// a word boundary at long-press. Selection is a SOURCE Utf16Range; the in-progress range renders as an
// accent wash. Kept off the Activity so the geometry is isolated; the Activity wires the gesture +
// popover + persistence.
//
// feature #137 WI-7a — the PAGED analog. In paged mode the body registers each VISIBLE page's
// TextLayoutResult + LayoutCoordinates + its per-page PageOffsetMap (registerPage). A pointer then
// resolves against the page-scoped registry: page-local rendered offset → GLOBAL source via the page's
// PageOffsetMap (renderedRangeToSource for the word boundary; renderedSpanAt for the cursor span),
// NEVER the chunk registry / offsetForChunk. The page's PageOffsetMap already speaks GLOBAL source coords
// (page-local rendered ↔ document source UTF-16), so no chunk-base add is needed. The SAME source
// Utf16Range the scroll path yields is produced, so persistence/popover/copy are byte-shared. Which
// registry a hit uses is decided per-call by which mode is active (any page registered ⇒ paged), so the
// scroll path stays byte-identical when no page is registered.
//
// @coordinates-with: paged/PageOffsetMap.kt (WI-4 — the page's dual-affinity rendered↔source bridge this
//   consumes at page scope), TxtReaderBody.kt (TxtPagedBody registers/unregisters pages + drives the
//   long-press-drag gesture), TxtSourceOffsets.kt / ChunkTextMapper.kt (the shared source-range consumers).
package com.vreader.app.reader

import androidx.compose.runtime.Stable
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.text.TextLayoutResult
import com.vreader.app.reader.paged.PageOffsetMap
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

    // feature #137 WI-7a — the PAGED registry. Each visible page publishes its own TextLayoutResult (from
    // the page's rendered AnnotatedString), its LayoutCoordinates, and its per-page PageOffsetMap. The map
    // speaks page-local rendered ↔ GLOBAL source, so a paged hit needs NO chunk-base add.
    private data class PageInfo(val layout: TextLayoutResult, val coords: LayoutCoordinates, val map: PageOffsetMap)
    /** A resolved paged hit: the page + its info + the page-local rendered offset + the GLOBAL source offset. */
    private data class PagedHit(val page: Int, val info: PageInfo, val rendered: Int, val source: Int)
    private val pages = HashMap<Int, PageInfo>()
    private var lazyCoords: LayoutCoordinates? = null
    // the initial word selected at long-press — the FIXED anchor; drags extend relative to it (never drop it).
    private var anchorRange: Utf16Range? = null
    // feature #131 WI-8 — the WINDOW-space bounds of the interlinear TRANSLATION slots currently
    // laid out. Populated additively by the bilingual body; a long-press whose pointer lands inside one
    // is CONSUMED (no selection begun) instead of routing to hitAt's nearest-source-chunk fallback
    // (:47–53). Empty when bilingual is off → the disabled selection path is byte-identical.
    private var excludedBounds: List<androidx.compose.ui.geometry.Rect> = emptyList()

    private val _selection = MutableStateFlow<Utf16Range?>(null)
    val selection: StateFlow<Utf16Range?> = _selection.asStateFlow()

    fun setLazyCoords(coords: LayoutCoordinates) { lazyCoords = coords }
    fun registerChunk(index: Int, layout: TextLayoutResult, coords: LayoutCoordinates) {
        chunks[index] = ChunkInfo(layout, coords)
    }
    fun unregisterChunk(index: Int) { chunks.remove(index) }

    /** feature #137 WI-7a — register (or replace) a VISIBLE [page]'s rendered layout + coords + the page's
     *  [map] (page-local rendered ↔ GLOBAL source). Called on page render; call [unregisterPage] when the
     *  page leaves the pager window (or re-renders under a new layout) so a stale off-screen
     *  TextLayoutResult is never consulted. Any registered page switches the controller to the paged hit
     *  path (see [isPaged]); the scroll chunk registry is untouched. */
    fun registerPage(page: Int, layout: TextLayoutResult, coords: LayoutCoordinates, map: PageOffsetMap) {
        pages[page] = PageInfo(layout, coords, map)
    }
    fun unregisterPage(page: Int) { pages.remove(page) }

    /** Whether the controller is currently resolving hits against the PAGED registry (any page registered).
     *  When false the scroll chunk path is used byte-identically. */
    private val isPaged: Boolean get() = pages.isNotEmpty()

    /** feature #131 WI-8 — set the WINDOW-space bounds of the currently laid-out interlinear
     *  translation slots (the bilingual body publishes these on layout). A long-press whose
     *  pointer falls inside any of these is a no-op (translation is never selectable, and the
     *  nearest-source-chunk fallback in [hitAt] is bypassed). Pass an empty list to clear
     *  (bilingual off / no translations visible). */
    fun setExcludedBounds(bounds: List<androidx.compose.ui.geometry.Rect>) { excludedBounds = bounds }

    /** feature #131 WI-8 — whether the pointer at [localPoint] (LazyColumn-local) lands inside a
     *  registered translation-slot's window bounds. */
    private fun isInExcludedBounds(localPoint: Offset): Boolean {
        if (excludedBounds.isEmpty()) return false
        val lz = lazyCoords ?: return false
        val windowPoint = lz.localToWindow(localPoint)
        return excludedBounds.any { it.contains(windowPoint) }
    }

    /**
     * feature #131 WI-8 — whether source chunk [index]'s REGISTERED `Text` bounds intersect the
     * LazyColumn viewport (used by the host's TTS auto-scroll guard, which can no longer trust
     * item-index visibility now that an item holds a source `Text` + a taller translation child).
     * A chunk whose `LayoutCoordinates` is absent / detached / pre-layout counts as NOT visible
     * (round-6 Low — the safe default: the host then scrolls the source into view). Returns false
     * when the lazy coords themselves are unavailable (pre-first-layout).
     */
    fun isSourceChunkInViewport(index: Int): Boolean {
        val lz = lazyCoords ?: return false
        if (!lz.isAttached) return false
        val info = chunks[index] ?: return false
        val coords = info.coords
        if (!coords.isAttached) return false
        val viewport = lz.boundsInWindow()
        val chunkBounds = coords.boundsInWindow()
        // A zero-area intersection (edge-touch) is NOT visible; require real vertical overlap.
        return chunkBounds.bottom > viewport.top && chunkBounds.top < viewport.bottom
    }

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

    /** feature #137 WI-7a — the PAGED analog of [hitAt]. Pointer ([localPoint], in the registered lazy/pager
     *  coords) → the hit page + page-local rendered offset + GLOBAL source. The page's PageOffsetMap already
     *  speaks GLOBAL source, so NO offsetForChunk add. [allowNearest]: a DRAG falls back to the nearest
     *  page's bounds when the point is past the text; a TAP-to-edit requires a real page hit.
     *
     *  Only ATTACHED pages are consulted (Gate-4 Medium: a detached layout can linger in the registry
     *  between eviction and onDispose — reading its bounds is stale/throws). The nearest fallback uses the
     *  FULL-RECTANGLE distance (not vertical-only): HorizontalPager pages share the same vertical band, so a
     *  vertical-only distance is 0 for every page and picks an arbitrary map. Ties break toward the page
     *  whose x-band contains the pointer, then the lowest page index — deterministic (Gate-4 High). */
    private fun hitAtPaged(localPoint: Offset, allowNearest: Boolean = true): PagedHit? {
        val lz = lazyCoords ?: return null
        if (!lz.isAttached || pages.isEmpty()) return null
        val windowPoint = lz.localToWindow(localPoint)
        val attached = pages.entries.filter { it.value.coords.isAttached }
        if (attached.isEmpty()) return null
        val hit = attached.firstOrNull { it.value.coords.boundsInWindow().contains(windowPoint) }
            ?: (if (allowNearest) {
                attached.minWithOrNull(
                    compareBy(
                        { rectDistance(it.value.coords.boundsInWindow(), windowPoint) },
                        // prefer the page whose x-band contains the pointer (0 = contained), then lowest index.
                        { if (windowPoint.x in it.value.coords.boundsInWindow().left..it.value.coords.boundsInWindow().right) 0 else 1 },
                        { it.key },
                    ),
                )
            } else null)
            ?: return null
        val pageLocal = hit.value.coords.windowToLocal(windowPoint)
        val rendered = hit.value.layout.getOffsetForPosition(pageLocal).coerceIn(0, hit.value.layout.layoutInput.text.length)
        // page-local rendered cursor → GLOBAL source (empty rendered range maps to the source edge).
        val source = hit.value.map.renderedRangeToSource(Utf16Range(rendered, rendered)).startInclusive
        return PagedHit(hit.key, hit.value, rendered, source)
    }

    /** Long-press: select the word under [localPoint] (word boundary in the HIT chunk/page, mapped to
     *  source). In PAGED mode ([isPaged]) the word boundary is resolved in the hit PAGE's rendered layout
     *  and mapped to GLOBAL source via the page's PageOffsetMap. A long-press whose pointer lands inside an
     *  interlinear translation slot ([setExcludedBounds]) is a NO-OP — the translation is never selectable,
     *  and the nearest-source fallback is bypassed. */
    fun beginAt(localPoint: Offset) {
        if (isInExcludedBounds(localPoint)) return
        if (isPaged) { beginAtPaged(localPoint); return }
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

    /** feature #137 WI-7a — the paged word-select. The word boundary is a RENDERED range in the hit page's
     *  layout; the page's PageOffsetMap converts it to a GLOBAL source span (markers stripped for MD, exactly
     *  as scroll mode does via the chunk mapper). Degenerate (marker-only) → the single-char cursor span. */
    private fun beginAtPaged(localPoint: Offset) {
        val hit = hitAtPaged(localPoint) ?: return
        val word = hit.info.layout.getWordBoundary(hit.rendered)   // RENDERED coords in the hit page
        // rendered word → GLOBAL source span (both range directions handled by the page map).
        val src = hit.info.map.renderedRangeToSource(Utf16Range(word.start, word.end))
        val start = src.startInclusive
        val end = src.endExclusive
        val range = if (end > start) Utf16Range(start, end) else Utf16Range(hit.source, (hit.source + 1).coerceAtMost(doc.text.length))
        anchorRange = range
        _selection.value = range
    }

    /** Drag: extend relative to the FIXED [anchorRange] (the initial word) — extending before it grows the
     *  start, after it grows the end, inside it keeps the word. The anchor word is never dropped. Paged mode
     *  resolves the drag pointer through the page registry (still a GLOBAL source offset), so the anchor math
     *  is identical. */
    fun extendTo(localPoint: Offset) {
        val anchor = anchorRange ?: return
        val off = (if (isPaged) hitAtPaged(localPoint)?.source else hitAt(localPoint)?.source)
            ?.coerceIn(0, doc.text.length) ?: return
        _selection.value = when {
            off <= anchor.startInclusive -> Utf16Range(off, anchor.endExclusive)
            off >= anchor.endExclusive -> Utf16Range(anchor.startInclusive, off)
            else -> anchor
        }
    }

    fun clear() { _selection.value = null; anchorRange = null }

    /** The current selection range, or null. */
    fun currentRange(): Utf16Range? = _selection.value

    /** Resolve a tap (LazyColumn-/page-local) to a SOURCE offset, for hit-testing an existing highlight.
     *  Strict (no nearest fallback) so a tap in the margin/blank space doesn't edit a nearby highlight. In
     *  PAGED mode the tap resolves against the page registry (still a GLOBAL source offset). */
    fun resolveSourceOffset(localPoint: Offset): Int? =
        if (isPaged) hitAtPaged(localPoint, allowNearest = false)?.source
        else hitAt(localPoint, allowNearest = false)?.source

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

    /** The window-space point just below the selection's end, to anchor the popover. In PAGED mode the end
     *  is resolved on the registered page that OWNS the end-source offset (via the page map's source→rendered
     *  round-trip), then getCursorRect on that page's layout. */
    fun selectionEndAnchorWindow(): Offset? {
        val r = _selection.value ?: return null
        if (isPaged) return selectionEndAnchorWindowPaged(r)
        val endChunk = doc.chunkForOffset((r.endExclusive - 1).coerceAtLeast(0)).coerceIn(0, doc.chunkCount - 1)
        val info = chunks[endChunk] ?: return null
        val base = doc.offsetForChunk(endChunk)
        // source end → chunk-local source → rendered cursor (end-affinity) for getCursorRect.
        val localSourceEnd = (r.endExclusive - base).coerceAtLeast(0)
        val renderedEnd = mapper.renderedCursorForSourceEnd(endChunk, localSourceEnd).coerceIn(0, info.layout.layoutInput.text.length)
        val rect = info.layout.getCursorRect(renderedEnd)
        return info.coords.localToWindow(Offset(rect.left, rect.bottom))
    }

    /** feature #137 WI-7a — the paged popover anchor. The selection can span pages; anchor on the registered
     *  page that actually OWNS the end-source offset (its source span contains `endExclusive - 1`). Returns
     *  NULL when no laid-out page owns the end (Gate-4 Medium: mapping the end through an UNRELATED page
     *  collapses it to that page's start/end → a false anchor; a null caller keeps the popover at its prior
     *  clamp / hidden rather than misplacing it). */
    private fun selectionEndAnchorWindowPaged(r: Utf16Range): Offset? {
        val endSource = (r.endExclusive - 1).coerceAtLeast(0)
        val info = pageOwning(endSource)?.value ?: return null
        if (!info.coords.isAttached) return null
        // source end → page-local rendered (end-affinity end) for the cursor.
        val renderedRange = info.map.sourceRangeToRendered(Utf16Range(endSource, r.endExclusive))
        val renderedEnd = (renderedRange?.endExclusive ?: 0).coerceIn(0, info.layout.layoutInput.text.length)
        val rect = info.layout.getCursorRect(renderedEnd)
        return info.coords.localToWindow(Offset(rect.left, rect.bottom))
    }

    /** The registered (attached) page whose source span contains [source] (round-trip:
     *  source→rendered→source-span actually covers [source]); null when no laid-out page owns it. */
    private fun pageOwning(source: Int): Map.Entry<Int, PageInfo>? =
        pages.entries.firstOrNull { entry ->
            if (!entry.value.coords.isAttached) return@firstOrNull false
            val rendered = entry.value.map.sourceRangeToRendered(Utf16Range(source, source + 1))
                ?: return@firstOrNull false
            if (rendered.isEmpty && rendered.startInclusive >= entry.value.layout.layoutInput.text.length) return@firstOrNull false
            val span = entry.value.map.renderedSpanAt(rendered.startInclusive.coerceAtLeast(0))
            source in span.startInclusive until span.endExclusive
        }

    private fun verticalDistance(bounds: androidx.compose.ui.geometry.Rect, p: Offset): Float = when {
        p.y < bounds.top -> bounds.top - p.y
        p.y > bounds.bottom -> p.y - bounds.bottom
        else -> 0f
    }

    /** feature #137 WI-7a — the FULL-RECTANGLE gap from [p] to [bounds] (0 per axis when inside), squared to
     *  avoid a sqrt; used for the paged nearest-page fallback so pages sharing a vertical band are ordered by
     *  their real distance (not an always-0 vertical-only distance). */
    private fun rectDistance(bounds: androidx.compose.ui.geometry.Rect, p: Offset): Float {
        val dx = when {
            p.x < bounds.left -> bounds.left - p.x
            p.x > bounds.right -> p.x - bounds.right
            else -> 0f
        }
        val dy = verticalDistance(bounds, p)
        return dx * dx + dy * dy
    }
}
