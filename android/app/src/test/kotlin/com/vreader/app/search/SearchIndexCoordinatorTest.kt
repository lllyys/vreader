package com.vreader.app.search

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.vreader.app.data.Book
import com.vreader.app.data.BookEntity
import com.vreader.app.data.LibraryRepository
import com.vreader.app.data.SearchDao
import com.vreader.app.data.SearchIndexStateEntity
import com.vreader.app.data.VReaderDatabase
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import vreader.contracts.BookFormat

/**
 * Feature #128 WI-5 — [SearchIndexCoordinator] against a real in-memory v7 Room DB (so FK cascade,
 * FTS visibility, and the atomic publish are exercised for real) plus deterministic fake streaming
 * extractors. Covers: indexes epub/txt/md, skips pdf/azw3; null-content (Unsupported) →
 * `skipped_unsupported`; skips already-indexed; stale `indexerVersion` → reindex; `failed` → retried;
 * author only-if-null; cancellation mid-extraction leaves staging + NO current state row + NO author
 * clobber; DELETE mid-extraction → cascaded staging + `bookExists` no-op, no FK failure, no orphan
 * state row; partial last batch flushed (1, N-1, N, N+1); bounded EPUB memory (batched flush);
 * corrupt-book isolation; single-collector idempotency.
 */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
class SearchIndexCoordinatorTest {

    private lateinit var db: VReaderDatabase
    private lateinit var searchDao: SearchDao
    private lateinit var repository: LibraryRepository
    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private fun keyFor(sha: Char, format: String = "epub") = "$format:${sha.toString().repeat(64)}:2048"
    private val bookA = keyFor('a')
    private val bookB = keyFor('b')

    @Before fun setUp() {
        db = Room.inMemoryDatabaseBuilder(context, VReaderDatabase::class.java)
            .allowMainThreadQueries().build()
        searchDao = db.searchDao()
        repository = LibraryRepository(db.bookDao(), db.readingPositionDao())
    }

    @After fun tearDown() = db.close()

    // --- seeding -------------------------------------------------------------------------------

    private suspend fun seedBook(key: String, format: String, author: String? = null) {
        db.bookDao().upsert(
            BookEntity(
                fingerprintKey = key, title = "T", originalFormat = format,
                contentSHA256 = key.substringAfter(':').substringBefore(':'),
                fileByteCount = 2048L, localFilePath = "/does/not/matter", sourceUri = null,
                addedAt = 1L, lastOpenedAt = null, author = author,
            ),
        )
    }

    /** A collecting fake sink is not needed — the coordinator owns the real staging sink; the fake
     *  EXTRACTOR drives it by emitting sections through the sink the coordinator passes. */
    private class FakeExtractor(
        private val sections: List<BookTextSection>,
        private val result: ExtractResult,
        /** Optional gate the extractor awaits AFTER emitting all sections but BEFORE returning, so a
         *  test can interleave a cancel/delete between staging and publish. */
        private val gateAfterEmit: CompletableDeferred<Unit>? = null,
        /** If set, throw this (e.g. a CancellationException or RuntimeException) after emitting. */
        private val throwAfterEmit: Throwable? = null,
    ) : BookTextExtractor {
        override suspend fun extract(book: Book, sink: SectionSink): ExtractResult {
            for (s in sections) sink.emit(s)
            gateAfterEmit?.await()
            throwAfterEmit?.let { throw it }
            return result
        }
    }

    private fun sectionsOf(count: Int, base: String = "widget"): List<BookTextSection> =
        (0 until count).map { BookTextSection(sectionIndex = it, chunkOrdinal = it, title = null, text = "$base number $it appears") }

    private fun buildCoordinator(
        scope: CoroutineScope,
        dispatcher: kotlinx.coroutines.CoroutineDispatcher,
        extractorFor: (BookFormat) -> BookTextExtractor?,
        now: () -> Long = { 1000L },
        batchSize: Int = 32,
    ) = SearchIndexCoordinator(
        repository = repository,
        searchDao = searchDao,
        extractorFor = extractorFor,
        scope = scope,
        ioDispatcher = dispatcher,
        now = now,
        batchSize = batchSize,
    )

    // --- indexes the three text formats; skips the two metadata-only formats --------------------

    @Test fun indexesEpubTxtMd_skipsPdfAzw3() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        seedBook(bookA, "epub")
        seedBook(keyFor('b', "txt"), "txt")
        seedBook(keyFor('c', "md"), "md")
        seedBook(keyFor('d', "pdf"), "pdf")
        seedBook(keyFor('e', "azw3"), "azw3")

        val coordinator = buildCoordinator(
            scope = this,
            dispatcher = dispatcher,
            extractorFor = { fmt ->
                when (fmt) {
                    BookFormat.epub, BookFormat.txt, BookFormat.md ->
                        FakeExtractor(sectionsOf(2), ExtractResult.Success(author = null))
                    else -> null
                }
            },
        )
        coordinator.startSearchIndexing()
        advanceUntilIdle()

        assertEquals("epub indexed", "indexed", searchDao.indexState(bookA)?.status)
        assertEquals("txt indexed", "indexed", searchDao.indexState(keyFor('b', "txt"))?.status)
        assertEquals("md indexed", "indexed", searchDao.indexState(keyFor('c', "md"))?.status)
        assertNull("pdf never gets a state row", searchDao.indexState(keyFor('d', "pdf")))
        assertNull("azw3 never gets a state row", searchDao.indexState(keyFor('e', "azw3")))
        assertNotNull("published epub is MATCHable", searchDao.firstMatchingSection(bookA, "widget"))
        this.coroutineContext[Job]!!.cancelChildren()
    }

    // --- null-content EPUB → skipped_unsupported (SETTLED, no sections) --------------------------

    @Test fun unsupportedBook_recordsSkippedUnsupported() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        seedBook(bookA, "epub")
        val coordinator = buildCoordinator(
            scope = this, dispatcher = dispatcher,
            extractorFor = { FakeExtractor(emptyList(), ExtractResult.Unsupported) },
        )
        coordinator.startSearchIndexing()
        advanceUntilIdle()

        assertEquals("skipped_unsupported settled state", "skipped_unsupported", searchDao.indexState(bookA)?.status)
        assertTrue("no sections for an unsupported book", searchDao.sectionsFor(bookA).isEmpty())
        assertTrue("staging cleared for an unsupported book", searchDao.stagingFor(bookA).isEmpty())
        this.coroutineContext[Job]!!.cancelChildren()
    }

    // --- already-indexed at the current version is NOT re-extracted ------------------------------

    @Test fun alreadyIndexedAtCurrentVersion_isSkipped() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        seedBook(bookA, "epub")
        searchDao.markIndexed(SearchIndexStateEntity(bookA, SearchIndexCoordinator.INDEXER_VERSION, 1L, "indexed"))
        var extracted = false
        val coordinator = buildCoordinator(
            scope = this, dispatcher = dispatcher,
            extractorFor = {
                object : BookTextExtractor {
                    override suspend fun extract(book: Book, sink: SectionSink): ExtractResult {
                        extracted = true
                        return ExtractResult.Success(null)
                    }
                }
            },
        )
        coordinator.startSearchIndexing()
        advanceUntilIdle()

        assertFalse("an up-to-date indexed book is not re-extracted", extracted)
        this.coroutineContext[Job]!!.cancelChildren()
    }

    // --- stale indexerVersion → reindex ---------------------------------------------------------

    @Test fun staleIndexerVersion_triggersReindex() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        seedBook(bookA, "epub")
        searchDao.markIndexed(SearchIndexStateEntity(bookA, SearchIndexCoordinator.INDEXER_VERSION - 1, 1L, "indexed"))
        val coordinator = buildCoordinator(
            scope = this, dispatcher = dispatcher,
            extractorFor = { FakeExtractor(sectionsOf(1, base = "fresh"), ExtractResult.Success(null)) },
        )
        coordinator.startSearchIndexing()
        advanceUntilIdle()

        assertEquals("reindexed to the current version", SearchIndexCoordinator.INDEXER_VERSION, searchDao.indexState(bookA)?.indexerVersion)
        assertNotNull("fresh content published on reindex", searchDao.firstMatchingSection(bookA, "fresh"))
        this.coroutineContext[Job]!!.cancelChildren()
    }

    // --- failed state is retried ----------------------------------------------------------------

    @Test fun failedState_isRetried() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        seedBook(bookA, "epub")
        searchDao.markIndexed(SearchIndexStateEntity(bookA, SearchIndexCoordinator.INDEXER_VERSION, 1L, "failed"))
        val coordinator = buildCoordinator(
            scope = this, dispatcher = dispatcher,
            extractorFor = { FakeExtractor(sectionsOf(1, base = "retried"), ExtractResult.Success(null)) },
        )
        coordinator.startSearchIndexing()
        advanceUntilIdle()

        assertEquals("a failed book is retried and settles to indexed", "indexed", searchDao.indexState(bookA)?.status)
        assertNotNull("content published after a retry", searchDao.firstMatchingSection(bookA, "retried"))
        this.coroutineContext[Job]!!.cancelChildren()
    }

    // --- author backfill: only when currently null; EPUB Success author rides through -----------

    @Test fun authorBackfilled_onlyWhenNull() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        seedBook(bookA, "epub", author = null)
        seedBook(bookB, "epub", author = "Existing")
        val coordinator = buildCoordinator(
            scope = this, dispatcher = dispatcher,
            extractorFor = { FakeExtractor(sectionsOf(1), ExtractResult.Success(author = "Extracted")) },
        )
        coordinator.startSearchIndexing()
        advanceUntilIdle()

        assertEquals("null author is backfilled", "Extracted", db.bookDao().find(bookA)?.author)
        assertEquals("a set author is never clobbered by backfill", "Existing", db.bookDao().find(bookB)?.author)
        this.coroutineContext[Job]!!.cancelChildren()
    }

    // --- corrupt-book isolation: one Failed book does not stop the others ------------------------

    @Test fun corruptBook_isIsolated_othersStillIndex() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        seedBook(bookA, "epub")   // this one throws mid-extract
        seedBook(bookB, "epub")   // this one succeeds
        val coordinator = buildCoordinator(
            scope = this, dispatcher = dispatcher,
            extractorFor = { fmt ->
                object : BookTextExtractor {
                    override suspend fun extract(book: Book, sink: SectionSink): ExtractResult {
                        if (book.fingerprintKey == bookA) throw RuntimeException("boom")
                        sink.emit(BookTextSection(0, 0, null, "healthy widget text"))
                        return ExtractResult.Success(null)
                    }
                }
            },
        )
        coordinator.startSearchIndexing()
        advanceUntilIdle()

        assertEquals("the corrupt book is marked failed (retryable)", "failed", searchDao.indexState(bookA)?.status)
        assertTrue("the corrupt book leaves no sections", searchDao.sectionsFor(bookA).isEmpty())
        assertTrue("the corrupt book leaves no staging", searchDao.stagingFor(bookA).isEmpty())
        assertEquals("the healthy book still indexed", "indexed", searchDao.indexState(bookB)?.status)
        assertNotNull("the healthy book is searchable", searchDao.firstMatchingSection(bookB, "widget"))
        this.coroutineContext[Job]!!.cancelChildren()
    }

    // --- partial last batch flushed: 1, N-1, N, N+1 sections all fully staged→published ---------

    @Test fun flushRemaining_persistsEveryPartialBatch() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val batch = 4
        val cases = mapOf(
            keyFor('a') to 1,          // fewer than one batch
            keyFor('b') to batch - 1,  // N-1
            keyFor('c') to batch,      // exactly N
            keyFor('d') to batch + 1,  // N+1
        )
        cases.keys.forEach { seedBook(it, "epub") }
        val coordinator = buildCoordinator(
            scope = this, dispatcher = dispatcher, batchSize = batch,
            extractorFor = { fmt ->
                object : BookTextExtractor {
                    override suspend fun extract(book: Book, sink: SectionSink): ExtractResult {
                        val n = cases.getValue(book.fingerprintKey)
                        repeat(n) { sink.emit(BookTextSection(it, it, null, "term$it content")) }
                        return ExtractResult.Success(null)
                    }
                }
            },
        )
        coordinator.startSearchIndexing()
        advanceUntilIdle()

        cases.forEach { (key, n) ->
            assertEquals("all $n sections published for $key (no lost tail)", n, searchDao.sectionsFor(key).size)
            assertTrue("staging fully cleared for $key", searchDao.stagingFor(key).isEmpty())
        }
        this.coroutineContext[Job]!!.cancelChildren()
    }

    // --- bounded EPUB memory: staging is flushed in batches, not fully materialized --------------

    @Test fun boundedMemory_stagingFlushedInBatches_notFullyMaterialized() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        seedBook(bookA, "epub")
        val batch = 8
        val total = 25
        var maxStagingSeen = 0
        val coordinator = buildCoordinator(
            scope = this, dispatcher = dispatcher, batchSize = batch,
            extractorFor = { fmt ->
                object : BookTextExtractor {
                    override suspend fun extract(book: Book, sink: SectionSink): ExtractResult {
                        repeat(total) {
                            sink.emit(BookTextSection(it, it, null, "chunk$it text"))
                            // Observe how much staging is resident as we stream.
                            val staged = searchDao.stagingFor(book.fingerprintKey).size
                            if (staged > maxStagingSeen) maxStagingSeen = staged
                        }
                        return ExtractResult.Success(null)
                    }
                }
            },
        )
        coordinator.startSearchIndexing()
        advanceUntilIdle()

        assertEquals("all sections eventually published", total, searchDao.sectionsFor(bookA).size)
        assertTrue(
            "resident staging never approaches the full book (bounded to ~one batch), saw $maxStagingSeen",
            maxStagingSeen < total,
        )
        this.coroutineContext[Job]!!.cancelChildren()
    }

    // --- cancellation mid-extraction: staging present (invisible), NO state row, NO author clobber

    @Test fun cancellationMidExtraction_leavesStagingInvisible_noStateRow_noAuthorClobber() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        seedBook(bookA, "epub", author = null)
        val gate = CompletableDeferred<Unit>()
        val coordinator = buildCoordinator(
            scope = this, dispatcher = dispatcher,
            // Emits one section then awaits the gate forever → the coordinator is suspended
            // between staging and publish when we cancel.
            extractorFor = { FakeExtractor(sectionsOf(1), ExtractResult.Success("ShouldNeverApply"), gateAfterEmit = gate) },
        )
        coordinator.startSearchIndexing()
        // Let the collector reach the extractor and stage the first section, then suspend on the gate.
        testScheduler.runCurrent()

        // Cancel the whole collector while it is suspended mid-extraction.
        this.coroutineContext[Job]!!.cancelChildren()
        advanceUntilIdle()

        assertNull("no current index-state row after a mid-extraction cancel", searchDao.indexState(bookA))
        assertTrue("no published sections after a mid-extraction cancel", searchDao.sectionsFor(bookA).isEmpty())
        assertNull("the author was never clobbered by an aborted extract", db.bookDao().find(bookA)?.author)
    }

    // --- DELETE mid-extraction: FK-cascaded staging + bookExists no-op, no FK failure/orphan -----

    @Test fun deleteMidExtraction_bookExistsNoOp_noFkFailure_noOrphanState() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        seedBook(bookA, "epub")
        val gate = CompletableDeferred<Unit>()
        val coordinator = buildCoordinator(
            scope = this, dispatcher = dispatcher,
            extractorFor = { FakeExtractor(sectionsOf(2), ExtractResult.Success(null), gateAfterEmit = gate) },
        )
        coordinator.startSearchIndexing()
        // Reach the gate: two sections staged, extractor suspended before returning Success.
        testScheduler.runCurrent()
        assertFalse("some staging exists before delete", searchDao.stagingFor(bookA).isEmpty())

        // Delete the book mid-index — FK CASCADE removes the in-flight staging rows.
        db.bookDao().delete(bookA)
        assertFalse("bookExists sees the delete", searchDao.bookExists(bookA))

        // Release the gate → extractor returns Success → coordinator flushes + publishBook (no-op).
        gate.complete(Unit)
        advanceUntilIdle()

        assertNull("no orphan state row after a mid-index delete", searchDao.indexState(bookA))
        assertTrue("no orphan sections after a mid-index delete", searchDao.sectionsFor(bookA).isEmpty())
        assertTrue("staging cascaded away by the delete", searchDao.stagingFor(bookA).isEmpty())
    }

    // --- single-collector idempotency: double start() spawns exactly one collector --------------

    @Test fun doubleStart_spawnsExactlyOneCollector() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        seedBook(bookA, "epub")
        var extractCount = 0
        val coordinator = buildCoordinator(
            scope = this, dispatcher = dispatcher,
            extractorFor = {
                object : BookTextExtractor {
                    override suspend fun extract(book: Book, sink: SectionSink): ExtractResult {
                        extractCount++
                        sink.emit(BookTextSection(0, 0, null, "solo widget"))
                        return ExtractResult.Success(null)
                    }
                }
            },
        )
        coordinator.startSearchIndexing()
        coordinator.startSearchIndexing()   // idempotent — second call must be a no-op
        advanceUntilIdle()

        assertEquals("a single collector indexed the book exactly once", 1, extractCount)
        assertEquals("indexed once", "indexed", searchDao.indexState(bookA)?.status)
        this.coroutineContext[Job]!!.cancelChildren()
    }
}
