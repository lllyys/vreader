// Purpose: The process-lifetime, eagerly-started, idempotent cross-book search-index collector —
// feature #128 WI-5. Observes the library, extracts each indexable book's text (streaming to a
// bounded-memory staging buffer via WI-3's extractors), and atomically publishes it searchable via
// WI-4's SearchDao.publishBook. The Android analog of the iOS BackgroundIndexingCoordinator.
//
// Lifecycle (Gate-2 HIGH — binding, see plan §"Coordinator lifecycle"):
//  - ONE process-lifetime Job on the injected appScope, started exactly once by an idempotent
//    startSearchIndexing() (guarded by an AtomicBoolean); a second call is a no-op.
//  - collect (NOT collectLatest) of observeLibrary(), so an in-flight book index is never torn down
//    mid-write by the next library emission (deletion-during-index is handled by the staging FK
//    CASCADE + the bookExists publish guard, not by cancellation).
//  - ALL work serialized through a single Mutex on the injected ioDispatcher — one book indexes at a
//    time regardless of how fast the library Flow emits.
//
// Streaming + atomic publish (Gate-2 round-2/3 HIGH, see plan §"Streaming extraction & atomic
// publish"): the extractor STREAMS each finished section to a StagingSink that batches inserts into
// search_sections_staging (flush-and-drop → O(batch) memory for EPUB, computing indexedText via
// SearchTextNormalizer); on Success the sink.flushRemaining() drains the partial last batch, then a
// single short SearchDao.publishBook swaps staging→sections + writes the state row + backfills author
// atomically. A cancel leaves only invisible staging (rethrown, staging cleared first); a delete
// mid-index cascades the staging away and the bookExists guard no-ops the publish; an ordinary
// per-book failure is isolated and recorded as a retryable `failed` state (only if the book exists).
package com.vreader.app.search

import com.vreader.app.data.Book
import com.vreader.app.data.LibraryRepository
import com.vreader.app.data.SearchDao
import com.vreader.app.data.SearchIndexStateEntity
import com.vreader.app.data.SearchStagingEntity
import com.vreader.app.diagnostics.DiagnosticsCategory
import com.vreader.app.diagnostics.VLog
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.cancellation.CancellationException
import vreader.contracts.BookFormat

class SearchIndexCoordinator(
    private val repository: LibraryRepository,
    private val searchDao: SearchDao,
    /** Picks the extractor for a format; returns null for non-indexable formats (pdf/azw3). */
    private val extractorFor: (BookFormat) -> BookTextExtractor?,
    /** Process-lifetime scope (AppContainer.appScope). */
    private val scope: CoroutineScope,
    /** All DB + extraction work runs here (never hardcode Dispatchers.IO — rule 50 §1). */
    private val ioDispatcher: CoroutineDispatcher,
    /** Injectable clock for the state row's indexedAt (deterministic in tests). */
    private val now: () -> Long = System::currentTimeMillis,
    /** Staging flush granularity — bounded memory for EPUB (plan §"Streaming"). */
    private val batchSize: Int = DEFAULT_BATCH_SIZE,
) {
    /** Single-assignment guard so a second startSearchIndexing() cannot spawn a competing collector. */
    private val started = AtomicBoolean(false)

    /** Serializes ALL per-book work — one book indexes at a time regardless of Flow emission rate. */
    private val mutex = Mutex()

    @Volatile private var collectorJob: Job? = null

    /**
     * Eagerly starts the single library-observing collector. Idempotent: the first call launches the
     * collector; every later call is a no-op (returns the same running Job's presence). Safe to call
     * from VReaderApp.onCreate.
     */
    fun startSearchIndexing() {
        if (!started.compareAndSet(false, true)) return
        collectorJob = scope.launch(ioDispatcher) {
            // collect (NOT collectLatest): an in-flight index must run to completion; deletion
            // correctness comes from the staging FK CASCADE + bookExists guard, not cancellation.
            repository.observeLibrary().collect { books ->
                for (book in books) {
                    // Serialize each book through the mutex so overlapping emissions can't interleave.
                    mutex.withLock { indexIfEligible(book) }
                }
            }
        }
    }

    /** Extracts + publishes one book iff it is an indexable format with no settled/current state. */
    private suspend fun indexIfEligible(book: Book) {
        val extractor = extractorFor(book.originalFormat) ?: return   // pdf/azw3 → never indexable
        if (!isEligible(book.fingerprintKey)) return
        processBook(book, extractor)
    }

    /**
     * Eligible iff there is no state row, OR the row is at a stale indexerVersion, OR the row is a
     * retryable `failed`. A current `indexed`/`skipped_unsupported` row at this version is settled.
     */
    private suspend fun isEligible(bookKey: String): Boolean {
        val state = searchDao.indexState(bookKey) ?: return true
        if (state.indexerVersion != INDEXER_VERSION) return true
        return state.status == STATUS_FAILED
    }

    private suspend fun processBook(book: Book, extractor: BookTextExtractor) {
        val bookKey = book.fingerprintKey
        // Discard any leftover staging from a prior cancelled attempt before a fresh extract.
        searchDao.clearStaging(bookKey)
        val sink = StagingSink(bookKey)
        try {
            when (val result = extractor.extract(book, sink)) {
                is ExtractResult.Success -> {
                    sink.flushRemaining()   // drain the partial last batch (Gate-2 round-3 MEDIUM)
                    // ONE short atomic transaction: bookExists-guarded staging→sections swap + state
                    // + EPUB author backfill. A mid-index delete makes this a clean no-op.
                    searchDao.publishBook(
                        bookKey = bookKey,
                        state = SearchIndexStateEntity(bookKey, INDEXER_VERSION, now(), STATUS_INDEXED),
                        author = result.author,
                    )
                }
                is ExtractResult.Unsupported -> markTerminalState(bookKey, STATUS_SKIPPED_UNSUPPORTED)
                is ExtractResult.Failed -> markTerminalState(bookKey, STATUS_FAILED)
            }
        } catch (e: CancellationException) {
            // Cancellation must propagate (structured concurrency) — but clear the invisible staging
            // first so a cancelled attempt never leaks staging rows across runs. NonCancellable so the
            // suspend DELETE actually runs during cancellation (a plain suspend call would immediately
            // re-throw). No state row is written on this path (atomicity HIGH — the publish never ran).
            withContext(NonCancellable) { runCatching { searchDao.clearStaging(bookKey) } }
            throw e
        } catch (e: Throwable) {
            // Isolate an ordinary per-book failure: the collector keeps draining the rest. This mark
            // must NOT be able to throw (a FK failure from a concurrent delete escaping here would kill
            // the sole collector — Gate-4 follow-up), so markTerminalState swallows its own failures.
            markTerminalState(bookKey, STATUS_FAILED)
        }
    }

    /**
     * Record a terminal/retry state row (skipped_unsupported or failed) for a book, robustly against a
     * concurrent delete. Clears staging first, then writes the state row ONLY if the book still exists.
     * The bookExists→markIndexed pair is not one transaction (SearchDao has no such op and it is
     * off my write-set), so a delete landing BETWEEN the check and the write would make markIndexed
     * fail its FK constraint; that failure is caught and treated as a benign no-op — the book is gone,
     * there is nothing to record, and the collector must keep draining (Gate-4 follow-up: a mark
     * failure must never terminate the single lifetime collector). No exception ever escapes.
     */
    private suspend fun markTerminalState(bookKey: String, status: String) {
        runCatching {
            searchDao.clearStaging(bookKey)
            if (searchDao.bookExists(bookKey)) {
                searchDao.markIndexed(SearchIndexStateEntity(bookKey, INDEXER_VERSION, now(), status))
            }
        }.onFailure { e ->
            // A CancellationException must still propagate (structured concurrency) even from here.
            if (e is CancellationException) throw e
            // Any other failure (e.g. an FK-constraint loss to a concurrent delete) is a benign no-op
            // for collector availability, but log it so a persistent DB/programming fault is observable
            // (Gate-4 round-2 follow-up) rather than silently swallowed.
            VLog.w(
                DiagnosticsCategory.LIBRARY,
                TAG,
                "search-index terminal-state write for $bookKey ($status) failed; skipping",
                e,
            )
        }
    }

    /**
     * The bounded-memory staging sink: buffers emitted sections and flushes a batch to
     * search_sections_staging every [batchSize], then drops the buffer (flush-and-drop → at most one
     * batch of section text resident for EPUB). [flushRemaining] drains the tail exactly once after
     * Success. Each staged row's FTS `indexedText` is normalized + CJK-segmented here (BookTextSection
     * carries only raw text — plan §"Streaming").
     */
    private inner class StagingSink(private val bookKey: String) : SectionSink {
        private val buffer = ArrayList<SearchStagingEntity>(batchSize)

        override suspend fun emit(section: BookTextSection) {
            buffer.add(
                SearchStagingEntity(
                    bookKey = bookKey,
                    sectionIndex = section.sectionIndex,
                    chunkOrdinal = section.chunkOrdinal,
                    sectionTitle = section.title,
                    text = section.text,
                    indexedText = indexedTextOf(section.text),
                ),
            )
            if (buffer.size >= batchSize) flushBuffer()
        }

        override suspend fun flushRemaining() {
            if (buffer.isNotEmpty()) flushBuffer()
        }

        private suspend fun flushBuffer() {
            // Copy + clear FIRST so the resident buffer is dropped (bounded memory) even if the insert
            // itself is slow; the batch list is passed to Room, the buffer is reusable immediately.
            val batch = ArrayList(buffer)
            buffer.clear()
            searchDao.insertStagingBatch(batch)
        }
    }

    private fun indexedTextOf(raw: String): String =
        SearchTextNormalizer.segmentCJK(SearchTextNormalizer.normalize(raw))

    companion object {
        /**
         * Bump to force a full re-extract of every book (extractor-logic changes; content-addressed
         * identity means a book's text never changes for a fixed key, so this is the only re-index
         * trigger besides a `failed` retry).
         */
        const val INDEXER_VERSION: Int = 1

        const val DEFAULT_BATCH_SIZE: Int = 32

        private const val TAG = "SearchIndexCoordinator"

        private const val STATUS_INDEXED = "indexed"
        private const val STATUS_SKIPPED_UNSUPPORTED = "skipped_unsupported"
        private const val STATUS_FAILED = "failed"
    }
}
