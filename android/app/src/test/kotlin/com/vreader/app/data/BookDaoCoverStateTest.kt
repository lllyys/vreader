package com.vreader.app.data

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import vreader.contracts.BookFormat
import vreader.contracts.Identity

/**
 * Feature #152 WI-2 — the cover-state columns as BEHAVIOUR, on a real in-memory Room DB.
 *
 * Two things are under test, and the second is the load-bearing one:
 *
 * 1. The three cover-state transitions (`setCoverArt` / `setCoverAbsent` / `clearCoverState`) write
 *    the `(coverPath, coverExtractorVersion)` pair, including the two tri-state corners that a
 *    single-column design cannot express — "no art, already looked" (NULL path WITH a version) and
 *    "eligible again" (both NULL).
 * 2. **The no-clobber guard.** Android's import path UPDATEs an existing row
 *    ([BookDao.upsertPreservingAuthor] → [BookDao.updateImportedColumns]) rather than skipping it, so
 *    a re-import of a book the user already owns would erase a cover pointer unless the cover columns
 *    join `author`/`lastOpenedAt` in that statement's exclusion list. This has no iOS counterpart.
 *
 * The guard is asserted as behaviour, never by inspecting the SQL: each guard test ALSO asserts that
 * the import-owned columns really did change in the same call. Without that second half a no-op
 * `updateImportedColumns` would satisfy every "cover survived" assertion vacuously — the exact shape
 * of feature #142 WI-1's round-1 Medium, where a source-order scan passed while the defect was live.
 */
@RunWith(RobolectricTestRunner::class)
class BookDaoCoverStateTest {
    private lateinit var db: VReaderDatabase
    private lateinit var dao: BookDao
    private lateinit var repo: LibraryRepository

    private val sha = "a".repeat(64)
    private val key = Identity.canonicalKey("epub", sha, 2048)
    private val coverPath = "/data/user/0/com.vreader.app/files/covers/$sha.jpg"

    private fun entity(
        title: String = "Moby-Dick",
        localFilePath: String? = "/files/books/original.epub",
        sourceUri: String? = "content://saf/doc/1",
        addedAt: Long = 1_000L,
        author: String? = null,
    ) = BookEntity(
        fingerprintKey = key,
        title = title,
        originalFormat = BookFormat.epub.name,
        contentSHA256 = sha,
        fileByteCount = 2048,
        localFilePath = localFilePath,
        sourceUri = sourceUri,
        addedAt = addedAt,
        lastOpenedAt = null,
        author = author,
    )

    @Before
    fun setUp() {
        db = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(),
            VReaderDatabase::class.java,
        ).build()
        dao = db.bookDao()
        repo = LibraryRepository(dao, db.readingPositionDao())
    }

    @After
    fun tearDown() = db.close()

    // ---- the tri-state transitions ----

    @Test
    fun freshlyImportedBook_hasNoCoverState() = runTest {
        dao.upsertPreservingAuthor(entity())

        val stored = dao.find(key)!!
        assertNull("a new row starts with no cover pointer", stored.coverPath)
        assertNull("…and no version memo, so the backfill treats it as eligible", stored.coverExtractorVersion)
    }

    @Test
    fun setCoverArt_writesBothColumns() = runTest {
        dao.upsertPreservingAuthor(entity())

        dao.setCoverArt(key, coverPath, 1)

        val stored = dao.find(key)!!
        assertEquals(coverPath, stored.coverPath)
        assertEquals(1, stored.coverExtractorVersion)
    }

    @Test
    fun setCoverAbsent_memoisesTheNoArtCase_asNullPathWithAVersion() = runTest {
        dao.upsertPreservingAuthor(entity())

        dao.setCoverAbsent(key, 1)

        val stored = dao.find(key)!!
        assertNull("a book with no art keeps a NULL pointer", stored.coverPath)
        assertEquals(
            "…but IS stamped, which is what stops the backfill re-parsing it on every app start",
            1,
            stored.coverExtractorVersion,
        )
    }

    @Test
    fun setCoverAbsent_afterArt_clearsTheStalePointer() = runTest {
        dao.upsertPreservingAuthor(entity())
        dao.setCoverArt(key, coverPath, 1)

        // A later pass at a newer version decides this book has no usable art after all — the old
        // pointer must not survive alongside the new verdict.
        dao.setCoverAbsent(key, 2)

        val stored = dao.find(key)!!
        assertNull("the stale pointer is cleared, not left dangling", stored.coverPath)
        assertEquals(2, stored.coverExtractorVersion)
    }

    @Test
    fun clearCoverState_makesTheBookEligibleAgain() = runTest {
        dao.upsertPreservingAuthor(entity())
        dao.setCoverArt(key, coverPath, 1)

        dao.clearCoverState(key)

        val stored = dao.find(key)!!
        assertNull(stored.coverPath)
        assertNull("both NULL is the 'never attempted / retry' corner", stored.coverExtractorVersion)
    }

    @Test
    fun setCoverArt_overwritesAPreviousPointer_onAVersionBump() = runTest {
        dao.upsertPreservingAuthor(entity())
        dao.setCoverArt(key, coverPath, 1)

        dao.setCoverArt(key, "$coverPath.v2", 2)

        val stored = dao.find(key)!!
        assertEquals("$coverPath.v2", stored.coverPath)
        assertEquals(2, stored.coverExtractorVersion)
    }

    @Test
    fun setCoverArt_atTheSameVersion_isAllowed_soAPointerCanBeReconciled() = runTest {
        dao.upsertPreservingAuthor(entity())
        dao.setCoverAbsent(key, 1)

        // #153's user pick and the coordinator's "cover file exists but the pointer is NULL"
        // reconcile both write at the CURRENT version. A monotonic "only if newer" guard at this
        // layer would silently drop both, so same-version writes must be accepted.
        dao.setCoverArt(key, coverPath, 1)

        val stored = dao.find(key)!!
        assertEquals(coverPath, stored.coverPath)
        assertEquals(1, stored.coverExtractorVersion)
    }

    @Test
    fun everyTransition_onAnUnknownKey_isANoOp_andCreatesNoRow() = runTest {
        val absent = "epub:${"f".repeat(64)}:99"

        dao.setCoverArt(absent, coverPath, 1)
        dao.setCoverAbsent(absent, 1)
        dao.clearCoverState(absent)

        assertEquals("a column-scoped UPDATE never inserts", 0, dao.getAll().size)
    }

    @Test
    fun coverState_writtenAfterTheBookWasDeleted_touchesNothing() = runTest {
        dao.upsertPreservingAuthor(entity())
        dao.delete(key)

        // An extraction that was already in flight when the user deleted the book resolves here.
        dao.setCoverArt(key, coverPath, 1)

        assertNull("the deleted book is not resurrected by a late cover write", dao.find(key))
        assertEquals(0, dao.getAll().size)
    }

    @Test
    fun setCoverArt_roundTripsAUnicodePathAndTheIntBoundary() = runTest {
        dao.upsertPreservingAuthor(entity())
        val cjkPath = "/files/covers/白鲸-Ⅶ-😀.jpg"

        dao.setCoverArt(key, cjkPath, Int.MAX_VALUE)

        val stored = dao.find(key)!!
        assertEquals(cjkPath, stored.coverPath)
        assertEquals(Int.MAX_VALUE, stored.coverExtractorVersion)
    }

    @Test
    fun coverState_isVisibleOnTheObservedLibraryFlow() = runTest {
        dao.upsertPreservingAuthor(entity())
        dao.setCoverArt(key, coverPath, 1)

        // The grid repaints off this Flow — the whole reason coverPath is a column at all.
        val observed = dao.observeAll().first().single()
        assertEquals(coverPath, observed.coverPath)
    }

    /**
     * The reactivity claim, tested as reactivity: subscribe FIRST, then write. Extraction finishes
     * after the row insert and the backfill long after first paint, so the grid only repaints if this
     * UPDATE pushes a fresh emission — that is the entire reason `coverPath` is a column rather than
     * a value derived from the key.
     *
     * `runBlocking`, not `runTest`: Room drives its invalidation Flow on its own real executor, which
     * a virtual-time scheduler does not advance. The first emission is awaited before the write, so
     * there is no subscribe-vs-write race and no sleep.
     */
    @Test
    fun theObservedFlow_emitsAgainWhenCoverStateChanges() = runBlocking {
        dao.upsertPreservingAuthor(entity())

        val emissions = Channel<String?>(Channel.UNLIMITED)
        val job = launch(Dispatchers.IO) {
            dao.observeAll().collect { emissions.send(it.single().coverPath) }
        }
        try {
            assertNull(
                "the first emission is the cover-less row",
                withTimeout(10_000) { emissions.receive() },
            )

            dao.setCoverArt(key, coverPath, 1)

            assertEquals(
                "the UPDATE pushed a fresh emission carrying the pointer",
                coverPath,
                withTimeout(10_000) { emissions.receive() },
            )
        } finally {
            job.cancel()
        }
    }

    // ---- the staleness guard ----

    @Test
    fun setCoverArt_fromAnOlderVersion_isRejected_andLeavesNewerStateIntact() = runTest {
        dao.upsertPreservingAuthor(entity())
        dao.setCoverArt(key, "$coverPath.v2", 2)

        // An extraction that started before the v2 pass finally resolves. It must not downgrade.
        val written = dao.setCoverArt(key, "$coverPath.v1", 1)

        assertEquals("a stale write reports that it changed nothing", 0, written)
        val stored = dao.find(key)!!
        assertEquals("$coverPath.v2", stored.coverPath)
        assertEquals(2, stored.coverExtractorVersion)
    }

    @Test
    fun setCoverAbsent_fromAnOlderVersion_isRejected() = runTest {
        dao.upsertPreservingAuthor(entity())
        dao.setCoverArt(key, coverPath, 2)

        val written = dao.setCoverAbsent(key, 1)

        assertEquals(0, written)
        assertEquals("a stale no-art verdict cannot erase newer art", coverPath, dao.find(key)!!.coverPath)
    }

    @Test
    fun setCoverAbsent_atTheSameVersion_cannotWipeAnEstablishedPointer() = runTest {
        dao.upsertPreservingAuthor(entity())
        dao.setCoverArt(key, coverPath, 1)

        // The dangerous interleaving: a no-art verdict at the CURRENT version landing after a cover
        // was established (an extraction result racing a #153 user pick). It must lose.
        val written = dao.setCoverAbsent(key, 1)

        assertEquals(0, written)
        val stored = dao.find(key)!!
        assertEquals("the established pointer survives", coverPath, stored.coverPath)
        assertEquals(1, stored.coverExtractorVersion)
    }

    @Test
    fun setCoverAbsent_atTheSameVersion_isAppliedWhenNoArtIsRecordedYet() = runTest {
        dao.upsertPreservingAuthor(entity())

        assertEquals("the first no-art verdict lands", 1, dao.setCoverAbsent(key, 1))
        // …and repeating it is harmless (still no art at the same version).
        assertEquals("re-stamping an already-art-less book is allowed", 1, dao.setCoverAbsent(key, 1))
        assertNull(dao.find(key)!!.coverPath)
        assertEquals(1, dao.find(key)!!.coverExtractorVersion)
    }

    @Test
    fun clearCoverState_isUnguarded_soTheReRunLeverAlwaysWorks() = runTest {
        dao.upsertPreservingAuthor(entity())
        dao.setCoverArt(key, coverPath, Int.MAX_VALUE)

        dao.clearCoverState(key)

        assertNull("the explicit reset is never rejected as stale", dao.find(key)!!.coverExtractorVersion)
    }

    /**
     * The "write every column" seam is the one that COULD have erased cover state — it still
     * overwrites `author` and `lastOpenedAt` (that is its documented purpose, unchanged), but after
     * Gate-4 round 2 its update branch is column-scoped and excludes the cover pair. So even a
     * CONSTRUCTED entity, whose cover fields default to null, cannot shred a user's cover.
     */
    @Test
    fun wholeRowUpsert_noLongerErasesCoverState_evenFromAConstructedEntity() = runTest {
        dao.upsertPreservingAuthor(entity(author = "Herman Melville"))
        dao.setCoverArt(key, coverPath, 1)

        dao.upsert(entity(title = "Whole-row rewrite"))   // cover fields AND author default to null

        val stored = dao.find(key)!!
        assertEquals("the cover pointer survives a whole-row write", coverPath, stored.coverPath)
        assertEquals("…as does the version memo", 1, stored.coverExtractorVersion)
        // Anti-vacuity: the write really happened, and this seam's documented clobbering is intact.
        assertEquals("Whole-row rewrite", stored.title)
        assertNull("this seam still overwrites author — that is its purpose", stored.author)
    }

    @Test
    fun wholeRowUpsert_ofANewBook_stillInserts() = runTest {
        dao.upsert(entity(title = "Brand new"))

        val stored = dao.find(key)!!
        assertEquals("Brand new", stored.title)
        assertNull(stored.coverPath)
        assertNull(stored.coverExtractorVersion)
    }

    @Test
    fun wholeRowUpsert_preservesCoverState_whenTheEntityWasRoundTripped() = runTest {
        dao.upsertPreservingAuthor(entity())
        dao.setCoverArt(key, coverPath, 1)

        // Reading the row first and writing it back must NOT lose the columns — that is what makes
        // the entity/DTO mapping lossless rather than a silent data shredder.
        val readBack = dao.find(key)!!
        dao.upsert(readBack.copy(title = "Round-tripped"))

        val stored = dao.find(key)!!
        assertEquals(coverPath, stored.coverPath)
        assertEquals(1, stored.coverExtractorVersion)
        assertEquals("Round-tripped", stored.title)
    }

    // ---- the no-clobber guard (D-1, DB layer) ----

    @Test
    fun reimport_throughUpsertPreservingAuthor_leavesCoverStateUntouched() = runTest {
        dao.upsertPreservingAuthor(entity(title = "Moby-Dick"))
        dao.setCoverArt(key, coverPath, 1)

        // The same book imported again — a new SAF pick of the same file. Room takes the UPDATE
        // branch (the PK already exists) and refreshes the import-owned columns.
        dao.upsertPreservingAuthor(
            entity(title = "Moby-Dick (2nd copy)", localFilePath = "/files/books/reimported.epub", addedAt = 9_000L),
        )

        val stored = dao.find(key)!!
        // The guard: the user's cover survived.
        assertEquals("a duplicate import must not erase the cover pointer", coverPath, stored.coverPath)
        assertEquals("…nor the version memo", 1, stored.coverExtractorVersion)
        // The anti-vacuity half: the UPDATE really ran, so the assertions above mean something.
        assertEquals("the import-owned title WAS refreshed", "Moby-Dick (2nd copy)", stored.title)
        assertEquals("the import-owned path WAS refreshed", "/files/books/reimported.epub", stored.localFilePath)
        assertEquals("the import-owned addedAt WAS refreshed", 9_000L, stored.addedAt)
    }

    @Test
    fun reimport_leavesAMemoisedNoArtBookUntouched_too() = runTest {
        dao.upsertPreservingAuthor(entity())
        dao.setCoverAbsent(key, 1)   // known art-less

        dao.upsertPreservingAuthor(entity(title = "Renamed", localFilePath = "/files/books/again.epub"))

        val stored = dao.find(key)!!
        assertNull(stored.coverPath)
        assertEquals(
            "clobbering the memo to NULL would re-parse this book on every future pass",
            1,
            stored.coverExtractorVersion,
        )
        assertEquals("Renamed", stored.title)
    }

    @Test
    fun applyRestoredMetadata_leavesCoverStateUntouched() = runTest {
        dao.upsertPreservingAuthor(entity())
        dao.setCoverArt(key, coverPath, 1)

        dao.applyRestoredMetadata(
            key = key,
            title = "Restored Title",
            addedAt = 7_000L,
            lastOpenedAt = 8_000L,
            manifestAuthor = "Herman Melville",
        )

        val stored = dao.find(key)!!
        assertEquals("a restore must not erase the cover pointer", coverPath, stored.coverPath)
        assertEquals(1, stored.coverExtractorVersion)
        // Anti-vacuity: the restore statement really did write.
        assertEquals("Restored Title", stored.title)
        assertEquals(7_000L, stored.addedAt)
        assertEquals(8_000L, stored.lastOpenedAt)
        assertEquals("Herman Melville", stored.author)
    }

    @Test
    fun markOpened_andAuthorBackfill_leaveCoverStateUntouched() = runTest {
        dao.upsertPreservingAuthor(entity())
        dao.setCoverArt(key, coverPath, 1)

        dao.markOpened(key, 4_242L)
        dao.backfillAuthorIfNull(key, "Herman Melville")

        val stored = dao.find(key)!!
        assertEquals(coverPath, stored.coverPath)
        assertEquals(1, stored.coverExtractorVersion)
        assertEquals(4_242L, stored.lastOpenedAt)
        assertEquals("Herman Melville", stored.author)
    }

    // ---- the repository boundary (DTO round-trip) ----

    @Test
    fun repository_roundTripsCoverStateThroughTheBookDto() = runTest {
        repo.upsertBookPreservingAuthor(
            Book(
                fingerprintKey = key,
                title = "Moby-Dick",
                originalFormat = BookFormat.epub,
                contentSHA256 = sha,
                fileByteCount = 2048,
                addedAt = 1_000L,
            ),
        )

        repo.setCoverArt(key, coverPath, 1)

        val loaded = repo.findBook(key)
        assertNotNull(loaded)
        assertEquals("the DTO exposes the pointer the grid renders", coverPath, loaded!!.coverPath)
        assertEquals(1, loaded.coverExtractorVersion)
    }

    @Test
    fun repository_upsertPreservingAuthor_doesNotClobberCoverState() = runTest {
        val book = Book(
            fingerprintKey = key,
            title = "Moby-Dick",
            originalFormat = BookFormat.epub,
            contentSHA256 = sha,
            fileByteCount = 2048,
            addedAt = 1_000L,
        )
        repo.upsertBookPreservingAuthor(book)
        repo.setCoverArt(key, coverPath, 1)

        // A DTO built by the importer never carries cover state (it does not know about covers) —
        // so mapping a null-cover DTO to an entity must not write those columns on the update branch.
        repo.upsertBookPreservingAuthor(book.copy(title = "Re-imported", localFilePath = "/files/books/again.epub"))

        val loaded = repo.findBook(key)!!
        assertEquals(coverPath, loaded.coverPath)
        assertEquals(1, loaded.coverExtractorVersion)
        assertEquals("Re-imported", loaded.title)
    }
}
