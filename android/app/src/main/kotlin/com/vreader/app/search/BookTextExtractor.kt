// Purpose: The book text-extraction seam for library search indexing — feature #128 WI-3.
// Extraction STREAMS each finished section to a SectionSink (never returns a materialized List), so
// EPUB extraction is bounded-memory (O(batch)): the coordinator's sink flushes batches to the
// staging table and drops them, keeping at most one batch resident. The whole-book author is the one
// datum that cannot stream (book-level metadata read up front), so it rides on Success. A typed
// Unsupported / Failed result (not an exception or an empty stream) lets the coordinator record the
// right search_index_state.status (WI-5).
package com.vreader.app.search

import com.vreader.app.data.Book

/** One extracted, chunk-sized section streamed to a [SectionSink]. */
data class BookTextSection(
    /** Per-book reading-order/section index — chapter attribution + first-hit tie-break. */
    val sectionIndex: Int,
    /** UNIQUE monotonic ordinal within a book (a running per-chunk counter) — deterministic first hit. */
    val chunkOrdinal: Int,
    /** Chapter label for the snippet attribution; null for TXT/MD (and no-TOC EPUB sections). */
    val title: String?,
    /** RAW display text of this chunk (the snippet source). */
    val text: String,
)

/**
 * The streaming sink the extractor emits each finished section to. The coordinator's implementation
 * writes to the staging table in batches; tests use a collecting fake.
 */
interface SectionSink {
    /** Emit one finished section. The sink may buffer into a batch. */
    suspend fun emit(section: BookTextSection)

    /**
     * Flush any buffered-but-unwritten sections. The coordinator calls this exactly once after
     * `extract()` returns [ExtractResult.Success] and BEFORE publish, so a book with fewer sections
     * than one batch (or a non-multiple tail) still persists every section.
     */
    suspend fun flushRemaining()
}

/** The typed outcome of an extract — distinguishes streamed success, unsupported, and failure. */
sealed interface ExtractResult {
    /** All sections were streamed to the sink; [author] is the only whole-book datum (for backfill). */
    data class Success(val author: String?) : ExtractResult

    /** No text is extractable (e.g. EPUB with no content service, no local file). Metadata-only book. */
    data object Unsupported : ExtractResult

    /** A transient/retryable failure ([reason] for logging); the coordinator records a `failed` state. */
    data class Failed(val reason: String) : ExtractResult
}

/** Extracts a book's text, streaming each section to a [SectionSink]. NEVER accumulates the whole book. */
interface BookTextExtractor {
    /**
     * Streams each finished section to [sink] as it is produced. Returns [ExtractResult.Success] after
     * the last section, or [ExtractResult.Unsupported] / [ExtractResult.Failed] without emitting.
     */
    suspend fun extract(book: Book, sink: SectionSink): ExtractResult
}
