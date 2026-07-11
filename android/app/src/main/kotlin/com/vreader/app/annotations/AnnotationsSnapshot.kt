// Purpose: feature #132 WI-6b — the value types the review sheet (WI-4) and annotation
// backup restore (WI-8) consume across the repository boundary (rule 50 §2: value types,
// never Room entities). `AnnotationsSnapshot` is the sheet's deterministic non-Flow open;
// `RestoreAnnotationsReport`/`KindCounts` is the per-kind applied/skipped/failed result the
// restore seam returns (surfaced to the restore-result UI).
package com.vreader.app.annotations

/** A one-shot snapshot of a book's highlights + notes for the review sheet's non-Flow open
 *  (complements the observable `highlights(bookKey)`/`notes(bookKey)` Flows). Deterministically
 *  sorted; corrupt rows are already dropped (mapped via `toRecordOrNull`). */
data class AnnotationsSnapshot(
    val highlights: List<HighlightRecord>,
    val notes: List<NoteRecord>,
)

/** Per-kind restore outcome: `applied` (freshly inserted), `skipped` (out-of-scope book OR an
 *  already-present UUID / same-anchor duplicate — the idempotency signal), `failed` (locator
 *  parse or bookKey-mismatch — never inserted, poisoning the boundary is worse than dropping). */
data class KindCounts(val applied: Int, val skipped: Int, val failed: Int)

/** The result of a UUID-preserving transactional annotation restore
 *  ([AnnotationsRepository.restoreAnnotations]) — one [KindCounts] per kind. */
data class RestoreAnnotationsReport(
    val highlights: KindCounts,
    val notes: KindCounts,
    val bookmarks: KindCounts,
)
