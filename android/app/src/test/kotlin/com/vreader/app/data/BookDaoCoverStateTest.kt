package com.vreader.app.data

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
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
 * 1. `setCoverState` writes the `(coverPath, coverExtractorVersion)` pair, including the two
 *    tri-state corners that a single-column design cannot express — "no art, already looked"
 *    (NULL path WITH a version) and "eligible again" (both NULL).
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

    // ---- setCoverState: the tri-state ----

    @Test
    fun freshlyImportedBook_hasNoCoverState() = runTest {
        dao.upsertPreservingAuthor(entity())

        val stored = dao.find(key)!!
        assertNull("a new row starts with no cover pointer", stored.coverPath)
        assertNull("…and no version memo, so the backfill treats it as eligible", stored.coverExtractorVersion)
    }

    @Test
    fun setCoverState_writesBothColumns_forTheArtCase() = runTest {
        dao.upsertPreservingAuthor(entity())

        dao.setCoverState(key, coverPath, 1)

        val stored = dao.find(key)!!
        assertEquals(coverPath, stored.coverPath)
        assertEquals(1, stored.coverExtractorVersion)
    }

    @Test
    fun setCoverState_memoisesTheNoArtCase_asNullPathWithAVersion() = runTest {
        dao.upsertPreservingAuthor(entity())

        dao.setCoverState(key, null, 1)

        val stored = dao.find(key)!!
        assertNull("a book with no art keeps a NULL pointer", stored.coverPath)
        assertEquals(
            "…but IS stamped, which is what stops the backfill re-parsing it on every app start",
            1,
            stored.coverExtractorVersion,
        )
    }

    @Test
    fun setCoverState_canClearTheMemo_makingTheBookEligibleAgain() = runTest {
        dao.upsertPreservingAuthor(entity())
        dao.setCoverState(key, coverPath, 1)

        dao.setCoverState(key, null, null)

        val stored = dao.find(key)!!
        assertNull(stored.coverPath)
        assertNull("both NULL is the 'never attempted / retry' corner", stored.coverExtractorVersion)
    }

    @Test
    fun setCoverState_overwritesAPreviousPointer_onAVersionBump() = runTest {
        dao.upsertPreservingAuthor(entity())
        dao.setCoverState(key, coverPath, 1)

        dao.setCoverState(key, "$coverPath.v2", 2)

        val stored = dao.find(key)!!
        assertEquals("$coverPath.v2", stored.coverPath)
        assertEquals(2, stored.coverExtractorVersion)
    }

    @Test
    fun setCoverState_onAnUnknownKey_isANoOp_andCreatesNoRow() = runTest {
        dao.setCoverState("epub:${"f".repeat(64)}:99", coverPath, 1)

        assertEquals("a column-scoped UPDATE never inserts", 0, dao.getAll().size)
    }

    @Test
    fun setCoverState_roundTripsAUnicodePathAndTheIntBoundary() = runTest {
        dao.upsertPreservingAuthor(entity())
        val cjkPath = "/files/covers/白鲸-Ⅶ-😀.jpg"

        dao.setCoverState(key, cjkPath, Int.MAX_VALUE)

        val stored = dao.find(key)!!
        assertEquals(cjkPath, stored.coverPath)
        assertEquals(Int.MAX_VALUE, stored.coverExtractorVersion)
    }

    @Test
    fun coverState_isVisibleOnTheObservedLibraryFlow() = runTest {
        dao.upsertPreservingAuthor(entity())
        dao.setCoverState(key, coverPath, 1)

        // The grid repaints off this Flow — the whole reason coverPath is a column at all.
        val observed = dao.observeAll().first().single()
        assertEquals(coverPath, observed.coverPath)
    }

    // ---- the no-clobber guard (D-1, DB layer) ----

    @Test
    fun reimport_throughUpsertPreservingAuthor_leavesCoverStateUntouched() = runTest {
        dao.upsertPreservingAuthor(entity(title = "Moby-Dick"))
        dao.setCoverState(key, coverPath, 1)

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
        dao.setCoverState(key, null, 1)   // known art-less

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
        dao.setCoverState(key, coverPath, 1)

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
        dao.setCoverState(key, coverPath, 1)

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

        repo.setCoverState(key, coverPath, 1)

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
        repo.setCoverState(key, coverPath, 1)

        // A DTO built by the importer never carries cover state (it does not know about covers) —
        // so mapping a null-cover DTO to an entity must not write those columns on the update branch.
        repo.upsertBookPreservingAuthor(book.copy(title = "Re-imported", localFilePath = "/files/books/again.epub"))

        val loaded = repo.findBook(key)!!
        assertEquals(coverPath, loaded.coverPath)
        assertEquals(1, loaded.coverExtractorVersion)
        assertEquals("Re-imported", loaded.title)
    }
}
