// Purpose: Shared DTOs for the in-book search subsystem — feature #133. Pure JVM (no Android deps).
// WI-3 introduces the raw-occurrence types the RawOffsetMatcher emits and the TXT/MD pagination cursor
// that threads an intra-chunk occurrence index so append-on-scroll paging is COMPLETE (round-3 Medium:
// a highly-repetitive chunk resumes across pages rather than truncating). WI-6 adds the FORMAT-NEUTRAL
// result DTOs (InBookHit / InBookGroup / InBookSearchPage / InBookSearchOutcome) that BOTH tracks project
// into — the EPUB engine's self-contained EpubInBookHit/EpubGroup and the TXT/MD FTS path are adapted by
// InBookSearchRepository into exactly these shapes so the ViewModel (WI-8) is format-agnostic. Keeping the
// DTOs together keeps the search DTO surface in one place.
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
// - InBookHit is format-neutral: EXACTLY ONE of canonicalLocator (TXT/MD scroll target) or
//   readiumLocatorJson (EPUB — an opaque, Readium-free handle the host resolves) is non-null; the pure-JVM
//   models file NEVER imports Readium (a live Readium Locator/iterator stays behind the EPUB engine seam,
//   referenced from a page's opaque nextCursor token, never inside this file).
package com.vreader.app.search

import vreader.contracts.Locator

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

/**
 * A single format-neutral in-book search hit. EXACTLY ONE locator field is non-null:
 * - [canonicalLocator] — a canonical [Locator] jump target for the FTS track (TXT/MD); the host scrolls to
 *   `charOffsetUTF16`.
 * - [readiumLocatorJson] — the EPUB hit's Readium `Locator` serialized to JSON (the app already round-trips
 *   Readium locators as JSON strings via `Locator.toJSON()` / `Locator.fromJSON`), so this pure-JVM file
 *   never references the Readium type; the host reconstructs it and calls `navigator.go`.
 *
 * [sectionTitle] is the chapter/section group key, [snippet] the display text, [matchRanges] the
 * inclusive highlight ranges within [snippet].
 */
data class InBookHit(
    val sectionTitle: String?,
    val canonicalLocator: Locator?,
    val readiumLocatorJson: String?,
    val snippet: String,
    val matchRanges: List<IntRange>,
)

/** A chapter/section group of [InBookHit]s (keyed by [title], in first-seen reading order). */
data class InBookGroup(
    val title: String?,
    val hits: List<InBookHit>,
)

/**
 * One page of in-book results (format-neutral): [groups] in reading/first-seen order, [moreAvailable] (an
 * append-on-scroll `loadMore` fetches the next page iff true), and the [nextCursor] to resume from
 * (non-null iff [moreAvailable]). The cursor is a [SearchCursor] — a [SearchCursor.Fts] threading the
 * intra-chunk `occurrenceIndex` for TXT/MD (round-3 completeness), or a [SearchCursor.Epub] whose opaque
 * `iteratorToken` the repository maps back to the live Readium engine cursor it holds per session.
 */
data class InBookSearchPage(
    val groups: List<InBookGroup>,
    val moreAvailable: Boolean,
    val nextCursor: SearchCursor?,
)

/**
 * The terminal outcome of an in-book search page request (format-neutral). Mirrors the EPUB engine's
 * outcome shape so the ViewModel (WI-8) maps a single sealed type to its UI state regardless of track:
 * - [Results] — a (possibly further-pageable) [InBookSearchPage].
 * - [NoResults] — the search ran and produced zero hits.
 * - [Unsupported] — the format has no in-book search (PDF/AZW3, or a non-searchable EPUB publication);
 *   the host hides the Search control, so this is a defensive terminal, never a user-facing state.
 * - [Error] — the underlying engine surfaced a failure ([message] is engine-neutral).
 */
sealed interface InBookSearchOutcome {
    /** The search produced [page]. */
    data class Results(val page: InBookSearchPage) : InBookSearchOutcome

    /** The search ran and produced zero hits. */
    data object NoResults : InBookSearchOutcome

    /** The format does not support in-book search. */
    data object Unsupported : InBookSearchOutcome

    /** The underlying engine failed; [message] is a stable, engine-neutral description. */
    data class Error(val message: String) : InBookSearchOutcome
}
