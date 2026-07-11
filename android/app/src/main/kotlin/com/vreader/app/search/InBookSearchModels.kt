// Purpose: Shared DTOs for the in-book search subsystem — feature #133. Pure JVM (no Android deps).
// WI-3 introduces the raw-occurrence types the RawOffsetMatcher emits and the TXT/MD pagination cursor
// that threads an intra-chunk occurrence index so append-on-scroll paging is COMPLETE (round-3 Medium:
// a highly-repetitive chunk resumes across pages rather than truncating). Later WIs (WI-4/6/8) extend
// this file with the hit/group/page/UI-state DTOs; keeping them together keeps the search DTO surface
// in one place.
//
// Key decisions:
// - A RawOccurrence carries RAW UTF-16 offsets into the UN-folded chunk text (a half-open span
//   [startUtf16, endUtf16)). A length-changing fold at COMPARISON time (NFKC full-width→half, ß→ss,
//   combining-mark strip) must NEVER shift these offsets — they always index the original source.
// - occurrenceIndex is the 0-based position of the occurrence in the chunk's deterministic
//   start-ordered enumeration. It is STABLE across paged calls, so a resume lands on the exact next
//   occurrence — the round-3 completeness contract.
// - RawOccurrenceSlice.nextOccurrenceIndex == null means the chunk is exhausted; non-null is the
//   resume point (the occurrenceIndex to pass as fromOccurrenceIndex on the next page).
// - SearchCursor.Fts carries occurrenceIndex so a partially-consumed chunk RESUMES rather than being
//   skipped by the DAO's strict `>` cursor (the repository re-fetches it inclusively via chunkAtOrAfter).
package com.vreader.app.search

/**
 * A single located occurrence of a query in a chunk's RAW text: a half-open UTF-16 span
 * `[startUtf16, endUtf16)` into the UN-folded source, tagged with its 0-based position
 * [occurrenceIndex] in the chunk's deterministic start-ordered enumeration.
 *
 * The span is always RAW (the offsets index the original chunk text, never a normalized/segmented or
 * whitespace-collapsed projection); a length-changing normalization fold applied during matching does
 * NOT shift it. A span boundary never lands inside a UTF-16 surrogate pair (the matcher iterates by
 * code point).
 */
data class RawOccurrence(
    val startUtf16: Int,
    val endUtf16: Int,
    val occurrenceIndex: Int,
)

/**
 * A per-PAGE window of a chunk's occurrences plus the resume point. [occurrences] is the slice
 * `[fromOccurrenceIndex, fromOccurrenceIndex + emitted)` in start order; [nextOccurrenceIndex] is the
 * occurrenceIndex of the first UN-emitted occurrence past this slice, or `null` when the chunk is fully
 * consumed. `maxThisPage` is a per-page window bound, NOT a per-chunk truncation — every occurrence is
 * retrievable across successive pages by threading [nextOccurrenceIndex] back in as fromOccurrenceIndex.
 */
data class RawOccurrenceSlice(
    val occurrences: List<RawOccurrence>,
    val nextOccurrenceIndex: Int?,
)

/**
 * A paging cursor for in-book search. Sealed by format track: [Fts] for TXT/MD (the #128 FTS index),
 * [Epub] for the Readium engine (WI-5). Exactly one variant per search session.
 */
sealed interface SearchCursor {
    /**
     * The TXT/MD FTS cursor. `(sectionIndex, chunkOrdinal, id)` locates the chunk in reading order;
     * [occurrenceIndex] is the next UN-emitted occurrence WITHIN that chunk, so a partially-consumed
     * repetitive chunk RESUMES rather than being skipped (round-3 completeness). When a chunk is fully
     * consumed the repository advances to the next chunk and resets [occurrenceIndex] to 0.
     */
    data class Fts(
        val sectionIndex: Int,
        val chunkOrdinal: Int,
        val id: Long,
        val occurrenceIndex: Int,
    ) : SearchCursor

    /** The EPUB cursor — an opaque token for the live Readium SearchIterator held per session (WI-5). */
    data class Epub(val iteratorToken: String) : SearchCursor
}
