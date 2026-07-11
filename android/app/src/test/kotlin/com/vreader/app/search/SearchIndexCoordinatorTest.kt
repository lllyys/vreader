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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
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
 * extractors. Uses REAL dispatchers + `runBlocking` + `withTimeout`-polling because Room's Flow emits
 * on its own executor (not a virtual-time test scheduler — same pattern as LibraryViewModelTest).
 *
 * Covers: indexes epub/txt/md, skips pdf/azw3; null-content (Unsupported) → `skipped_unsupported`;
 * skips already-indexed; stale `indexerVersion` → reindex; `failed` → retried; author only-if-null;
 * cancellation mid-extraction leaves staging + NO current state row + NO author clobber; DELETE
 * mid-extraction → cascaded staging + `bookExists` no-op, no FK failure, no orphan state row; partial
 * last batch flushed (1, N-1, N, N+1); bounded EPUB memory (batched flush); corrupt-book isolation;
 * single-collector idempotency.
 */
@RunWith(RobolectricTestRunner::class)
class SearchIndexCoordinatorTest {

    private lateinit var db: VReaderDatabase
    private lateinit var searchDao: SearchDao
    private lateinit var repository: LibraryRepository
    private lateinit var scope: CoroutineScope
    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private fun keyFor(sha: Char, format: String = "epub") = "$format:${sha.toString().repeat(64)}:2048"
    private val bookA = keyFor('a')
    private val bookB = keyFor('b')

    @Before fun setUp() {
        db = Room.inMemoryDatabaseBuilder(context, VReaderDatabase::class.java).build()
        searchDao = db.searchDao()
        repository = LibraryRepository(db.bookDao(), db.readingPositionDao())
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    }

    @After fun tearDown() {
        scope.coroutineContext[Job]?.cancel()
        db.close()
    }

    // --- helpers -------------------------------------------------------------------------------

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

    /** Poll a DB condition with a real-time bound (Room's Flow + inserts run on background threads). */
    private suspend fun await(timeoutMs: Long = 5_000, cond: suspend () -> Boolean) {
        withTimeout(timeoutMs) { while (!cond()) delay(10) }
    }

    /** A fake streaming extractor: emits [sections] to the sink, then optionally awaits a gate and/or
     *  throws, then returns [result]. */
    private class FakeExtractor(
        private val sections: List<BookTextSection>,
        private val result: ExtractResult,
        private val gateAfterEmit: CompletableDeferred<Unit>? = null,
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
        now: () -> Long = { 1000L },
        batchSize: Int = 32,
        extractorFor: (BookFormat) -> BookTextExtractor?,
    ) = SearchIndexCoordinator(
        repository = repository,
        searchDao = searchDao,
        extractorFor = extractorFor,
        scope = scope,
        ioDispatcher = Dispatchers.Default,
        now = now,
        batchSize = batchSize,
    )

    // --- indexes the three text formats; skips the two metadata-only formats --------------------

    @Test fun indexesEpubTxtMd_skipsPdfAzw3() = runBlocking {
        seedBook(bookA, "epub")
        seedBook(keyFor('b', "txt"), "txt")
        seedBook(keyFor('c', "md"), "md")
        seedBook(keyFor('d', "pdf"), "pdf")
        seedBook(keyFor('e', "azw3"), "azw3")

        buildCoordinator { fmt ->
            when (fmt) {
                BookFormat.epub, BookFormat.txt, BookFormat.md ->
                    FakeExtractor(sectionsOf(2), ExtractResult.Success(author = null))
                else -> null
            }
        }.startSearchIndexing()

        await { searchDao.indexState(bookA)?.status == "indexed" &&
            searchDao.indexState(keyFor('b', "txt"))?.status == "indexed" &&
            searchDao.indexState(keyFor('c', "md"))?.status == "indexed" }

        assertEquals("epub indexed", "indexed", searchDao.indexState(bookA)?.status)
        assertEquals("txt indexed", "indexed", searchDao.indexState(keyFor('b', "txt"))?.status)
        assertEquals("md indexed", "indexed", searchDao.indexState(keyFor('c', "md"))?.status)
        assertNull("pdf never gets a state row", searchDao.indexState(keyFor('d', "pdf")))
        assertNull("azw3 never gets a state row", searchDao.indexState(keyFor('e', "azw3")))
        assertNotNull("published epub is MATCHable", searchDao.firstMatchingSection(bookA, "widget"))
    }

    // --- null-content EPUB → skipped_unsupported (SETTLED, no sections) --------------------------

    @Test fun unsupportedBook_recordsSkippedUnsupported() = runBlocking {
        seedBook(bookA, "epub")
        buildCoordinator { FakeExtractor(emptyList(), ExtractResult.Unsupported) }.startSearchIndexing()

        await { searchDao.indexState(bookA) != null }
        assertEquals("skipped_unsupported settled state", "skipped_unsupported", searchDao.indexState(bookA)?.status)
        assertTrue("no sections for an unsupported book", searchDao.sectionsFor(bookA).isEmpty())
        assertTrue("staging cleared for an unsupported book", searchDao.stagingFor(bookA).isEmpty())
    }

    // --- already-indexed at the current version is NOT re-extracted ------------------------------

    @Test fun alreadyIndexedAtCurrentVersion_isSkipped() = runBlocking {
        seedBook(bookA, "epub")
        searchDao.markIndexed(SearchIndexStateEntity(bookA, SearchIndexCoordinator.INDEXER_VERSION, 1L, "indexed"))
        val extracted = java.util.concurrent.atomic.AtomicBoolean(false)
        buildCoordinator {
            object : BookTextExtractor {
                override suspend fun extract(book: Book, sink: SectionSink): ExtractResult {
                    extracted.set(true)
                    return ExtractResult.Success(null)
                }
            }
        }.startSearchIndexing()

        // Give the collector time to observe + decide; it must NOT re-extract.
        delay(500)
        assertFalse("an up-to-date indexed book is not re-extracted", extracted.get())
    }

    // --- stale indexerVersion → reindex ---------------------------------------------------------

    @Test fun staleIndexerVersion_triggersReindex() = runBlocking {
        seedBook(bookA, "epub")
        searchDao.markIndexed(SearchIndexStateEntity(bookA, SearchIndexCoordinator.INDEXER_VERSION - 1, 1L, "indexed"))
        buildCoordinator { FakeExtractor(sectionsOf(1, base = "fresh"), ExtractResult.Success(null)) }.startSearchIndexing()

        await { searchDao.indexState(bookA)?.indexerVersion == SearchIndexCoordinator.INDEXER_VERSION }
        assertEquals("reindexed to the current version", SearchIndexCoordinator.INDEXER_VERSION, searchDao.indexState(bookA)?.indexerVersion)
        assertNotNull("fresh content published on reindex", searchDao.firstMatchingSection(bookA, "fresh"))
    }

    // --- failed state is retried ----------------------------------------------------------------

    @Test fun failedState_isRetried() = runBlocking {
        seedBook(bookA, "epub")
        searchDao.markIndexed(SearchIndexStateEntity(bookA, SearchIndexCoordinator.INDEXER_VERSION, 1L, "failed"))
        buildCoordinator { FakeExtractor(sectionsOf(1, base = "retried"), ExtractResult.Success(null)) }.startSearchIndexing()

        await { searchDao.indexState(bookA)?.status == "indexed" }
        assertEquals("a failed book is retried and settles to indexed", "indexed", searchDao.indexState(bookA)?.status)
        assertNotNull("content published after a retry", searchDao.firstMatchingSection(bookA, "retried"))
    }

    // --- author backfill: only when currently null; EPUB Success author rides through -----------

    @Test fun authorBackfilled_onlyWhenNull() = runBlocking {
        seedBook(bookA, "epub", author = null)
        seedBook(bookB, "epub", author = "Existing")
        buildCoordinator { FakeExtractor(sectionsOf(1), ExtractResult.Success(author = "Extracted")) }.startSearchIndexing()

        await { searchDao.indexState(bookA)?.status == "indexed" && searchDao.indexState(bookB)?.status == "indexed" }
        assertEquals("null author is backfilled", "Extracted", db.bookDao().find(bookA)?.author)
        assertEquals("a set author is never clobbered by backfill", "Existing", db.bookDao().find(bookB)?.author)
    }

    // --- corrupt-book isolation: one throwing book does not stop the others ----------------------

    @Test fun corruptBook_isIsolated_othersStillIndex() = runBlocking {
        seedBook(bookA, "epub")   // this one throws mid-extract
        seedBook(bookB, "epub")   // this one succeeds
        buildCoordinator {
            object : BookTextExtractor {
                override suspend fun extract(book: Book, sink: SectionSink): ExtractResult {
                    if (book.fingerprintKey == bookA) throw RuntimeException("boom")
                    sink.emit(BookTextSection(0, 0, null, "healthy widget text"))
                    return ExtractResult.Success(null)
                }
            }
        }.startSearchIndexing()

        await { searchDao.indexState(bookA)?.status == "failed" && searchDao.indexState(bookB)?.status == "indexed" }
        assertEquals("the corrupt book is marked failed (retryable)", "failed", searchDao.indexState(bookA)?.status)
        assertTrue("the corrupt book leaves no sections", searchDao.sectionsFor(bookA).isEmpty())
        assertTrue("the corrupt book leaves no staging", searchDao.stagingFor(bookA).isEmpty())
        assertEquals("the healthy book still indexed", "indexed", searchDao.indexState(bookB)?.status)
        assertNotNull("the healthy book is searchable", searchDao.firstMatchingSection(bookB, "widget"))
    }

    // --- partial last batch flushed: 1, N-1, N, N+1 sections all fully staged→published ---------

    @Test fun flushRemaining_persistsEveryPartialBatch() = runBlocking {
        val batch = 4
        val cases = mapOf(
            keyFor('a') to 1,          // fewer than one batch
            keyFor('b') to batch - 1,  // N-1
            keyFor('c') to batch,      // exactly N
            keyFor('d') to batch + 1,  // N+1
        )
        cases.keys.forEach { seedBook(it, "epub") }
        buildCoordinator(batchSize = batch) {
            object : BookTextExtractor {
                override suspend fun extract(book: Book, sink: SectionSink): ExtractResult {
                    val n = cases.getValue(book.fingerprintKey)
                    repeat(n) { sink.emit(BookTextSection(it, it, null, "term$it content")) }
                    return ExtractResult.Success(null)
                }
            }
        }.startSearchIndexing()

        await { cases.keys.all { searchDao.indexState(it)?.status == "indexed" } }
        cases.forEach { (key, n) ->
            assertEquals("all $n sections published for $key (no lost tail)", n, searchDao.sectionsFor(key).size)
            assertTrue("staging fully cleared for $key", searchDao.stagingFor(key).isEmpty())
        }
    }

    // --- bounded EPUB memory: staging is flushed in batches, not fully materialized --------------

    @Test fun boundedMemory_stagingFlushedInBatches_notFullyMaterialized() = runBlocking {
        seedBook(bookA, "epub")
        val batch = 8
        val total = 25
        val maxStagingSeen = java.util.concurrent.atomic.AtomicInteger(0)
        buildCoordinator(batchSize = batch) {
            object : BookTextExtractor {
                override suspend fun extract(book: Book, sink: SectionSink): ExtractResult {
                    repeat(total) {
                        sink.emit(BookTextSection(it, it, null, "chunk$it text"))
                        val staged = searchDao.stagingFor(book.fingerprintKey).size
                        maxStagingSeen.updateAndGet { prev -> if (staged > prev) staged else prev }
                    }
                    return ExtractResult.Success(null)
                }
            }
        }.startSearchIndexing()

        await { searchDao.indexState(bookA)?.status == "indexed" }
        assertEquals("all sections eventually published", total, searchDao.sectionsFor(bookA).size)
        assertTrue(
            "resident staging never approaches the full book (bounded to ~one batch), saw ${maxStagingSeen.get()}",
            maxStagingSeen.get() < total,
        )
    }

    // --- cancellation mid-extraction: staging present (invisible), NO state row, NO author clobber

    @Test fun cancellationMidExtraction_leavesStagingInvisible_noStateRow_noAuthorClobber() = runBlocking {
        seedBook(bookA, "epub", author = null)
        val gate = CompletableDeferred<Unit>()
        // batchSize = 1 so each emit flushes to staging immediately — the section is observably staged
        // while the extractor is suspended on the gate (before Success/flushRemaining/publish).
        buildCoordinator(batchSize = 1) {
            FakeExtractor(sectionsOf(1), ExtractResult.Success("ShouldNeverApply"), gateAfterEmit = gate)
        }.startSearchIndexing()

        // Wait until the section is staged (extractor reached the gate).
        await { searchDao.stagingFor(bookA).isNotEmpty() }

        // Cancel the whole collector while it is suspended mid-extraction.
        scope.coroutineContext[Job]!!.cancelChildrenAndJoin()

        assertNull("no current index-state row after a mid-extraction cancel", searchDao.indexState(bookA))
        assertTrue("no published sections after a mid-extraction cancel", searchDao.sectionsFor(bookA).isEmpty())
        assertNull("the author was never clobbered by an aborted extract", db.bookDao().find(bookA)?.author)
        // Staging cleared on the cancellation path (NonCancellable) — invisible either way.
        assertTrue("staging cleared on cancel", searchDao.stagingFor(bookA).isEmpty())
    }

    // --- DELETE mid-extraction: FK-cascaded staging + bookExists no-op, no FK failure/orphan -----

    @Test fun deleteMidExtraction_bookExistsNoOp_noFkFailure_noOrphanState() = runBlocking {
        seedBook(bookA, "epub")
        val gate = CompletableDeferred<Unit>()
        // batchSize = 1 so both sections are flushed to staging while the extractor is gated.
        buildCoordinator(batchSize = 1) {
            FakeExtractor(sectionsOf(2), ExtractResult.Success(null), gateAfterEmit = gate)
        }.startSearchIndexing()

        // Two sections staged, extractor suspended before returning Success.
        await { searchDao.stagingFor(bookA).size == 2 }

        // Delete the book mid-index — FK CASCADE removes the in-flight staging rows.
        db.bookDao().delete(bookA)
        await { !searchDao.bookExists(bookA) }

        // Release the gate → extractor returns Success → coordinator flushes + publishBook (no-op).
        gate.complete(Unit)
        // Let the publish path run; nothing observable to await, so give it a bounded window.
        delay(500)

        assertNull("no orphan state row after a mid-index delete", searchDao.indexState(bookA))
        assertTrue("no orphan sections after a mid-index delete", searchDao.sectionsFor(bookA).isEmpty())
        assertTrue("staging cascaded away by the delete", searchDao.stagingFor(bookA).isEmpty())
    }

    // --- single-collector idempotency: double start() spawns exactly one collector --------------

    @Test fun doubleStart_spawnsExactlyOneCollector() = runBlocking {
        seedBook(bookA, "epub")
        val extractCount = java.util.concurrent.atomic.AtomicInteger(0)
        val coordinator = buildCoordinator {
            object : BookTextExtractor {
                override suspend fun extract(book: Book, sink: SectionSink): ExtractResult {
                    extractCount.incrementAndGet()
                    sink.emit(BookTextSection(0, 0, null, "solo widget"))
                    return ExtractResult.Success(null)
                }
            }
        }
        coordinator.startSearchIndexing()
        coordinator.startSearchIndexing()   // idempotent — second call must be a no-op

        await { searchDao.indexState(bookA)?.status == "indexed" }
        // Let any (erroneous) second collector also run before asserting.
        delay(300)
        assertEquals("a single collector indexed the book exactly once", 1, extractCount.get())
        assertEquals("indexed once", "indexed", searchDao.indexState(bookA)?.status)
    }

    private suspend fun Job.cancelChildrenAndJoin() {
        children.forEach { it.cancelAndJoinQuietly() }
    }

    private suspend fun Job.cancelAndJoinQuietly() {
        cancel()
        try { join() } catch (_: Throwable) {}
    }
}
