// Purpose: feature #138 WI-1 (#110 box E follow-up) — the immutable, resumable measure cursor for
// TxtPaginator's incremental doc-start-forward pagination.
//
// It captures the ENTIRE sequential page-break state of TxtPaginator's phase-1 measure loop at a
// CHUNK boundary, so a windowed / on-demand pass can pause after sealing a bounded number of pages
// (or reaching a target source offset) and later RESUME producing the byte-identical page-start
// sequence the whole-document `index(...)` pass would have produced. The determinism property is
// load-bearing: an incremental-from-chunk-0 run to completion == today's `index(...)` (WI-1 test).
//
// A cursor is ONLY ever advanced forward from chunk 0 — never seeded at an arbitrary anchor (the
// sequential carry `carryHeight`/`carryHasLine` is a true invariant only at chunk 0). It is
// `internal` — the public API is TxtPaginator's `index(...)` (WI-1) and PaginationSession's commands
// (WI-4), never a raw cursor.
//
// @coordinates-with: TxtPaginator.kt (creates + advances it via freshCursor / measurePages /
//   measureThroughOffset via the internal MeasureRun; owns the tiling logic in ONE place).
package com.vreader.app.reader.paged

import androidx.compose.ui.text.TextStyle

/**
 * The immutable per-run context a resumable measure pass carries so `measurePages` /
 * `measureThroughOffset` need only a cursor (not the document/style/box re-threaded per call). It
 * holds the ONE paginator-local mapper instance for the whole pass (never the shared UI mapper) so
 * every window measures against the same LRU. Held BY the cursor; the same instance flows through
 * every advanced copy of a single pass.
 */
internal class MeasureRun(
    val document: com.vreader.app.reader.TxtDocument,
    val style: TextStyle,
    val contentBox: PageContentBox,
    val measurer: LineMeasurer,
    val mapper: LocalChunkOffsetMapper,
    val docEndExclusive: Int,
)

/**
 * An immutable snapshot of an in-progress incremental measure pass. Each resumable call returns a
 * NEW advanced copy — the cursor is never mutated in place, so a caller may hold prior snapshots
 * safely.
 *
 * @property run the per-run context (document, style, box, measurer, local mapper). The same
 *   instance across every advanced copy of one pass.
 * @property nextChunk the index of the NEXT chunk to measure (0 for a fresh cursor;
 *   `document.chunkCount` when the pass has consumed every chunk).
 * @property carryHeight the height (px) already accumulated on the in-progress (unsealed) frontier
 *   page — the sequential `currentPageHeight` of the whole-doc loop, saved at the chunk boundary.
 * @property carryHasLine whether the in-progress frontier page has at least one line yet — the
 *   sequential `pageHasLine`. False only before the doc's very first line is measured.
 * @property currentPageStart the source-UTF-16 start offset of the in-progress (NOT-yet-sealed)
 *   frontier page, or -1 before the doc's first line. A page is SEALED — emitted via the `emit`
 *   callback — only once its SUCCESSOR's start is discovered (so its exclusive end is final); the
 *   FINAL page seals at doc end. This field IS the strict-advance guard's reference (a candidate
 *   that does not advance past it stays on the current page) — identical to the whole-doc loop's
 *   `starts.last()` at every point.
 * @property lastSealedStart the source-UTF-16 start of the most recently SEALED (emitted) page, or
 *   -1 before any page seals. `lastSealedStart < currentPageStart` whenever a page is pending.
 * @property frontierSourceOffset the source-UTF-16 offset of the last-KNOWN page start that is NOT
 *   yet a published (sealed) page start — the FRONTIER MARKER (== [currentPageStart] while a page
 *   is pending; == `document.text.length` once [isComplete]). It is the exclusive end of the last
 *   sealed page. NOT itself in the published page-start list.
 * @property isComplete true once every chunk has been measured and the final in-progress page has
 *   been sealed at doc end (or the doc is empty / the box is degenerate — either yields a
 *   completed cursor that seals no pages). A completed cursor is idempotent: further measure calls
 *   emit nothing and return an equal cursor.
 * @property emittedAnyStart whether any page start (sealed OR pending) has been begun — the
 *   whole-doc loop's `starts.size == 0` fallback ("no page ever started → the whole doc is one
 *   page at offset 0") fires at completion iff this is still false with a non-empty doc.
 */
internal data class MeasureCursor(
    val run: MeasureRun,
    val nextChunk: Int,
    val carryHeight: Float,
    val carryHasLine: Boolean,
    val currentPageStart: Int,
    val lastSealedStart: Int,
    val frontierSourceOffset: Int,
    val isComplete: Boolean,
    val emittedAnyStart: Boolean,
)
