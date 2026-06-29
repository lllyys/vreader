package com.vreader.app.backup

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.vreader.app.backup.archive.BackupArchiveReader
import com.vreader.app.backup.archive.BackupArchiveWriter
import com.vreader.app.data.Book
import com.vreader.app.data.BookImporter
import com.vreader.app.data.CollectionDao
import com.vreader.app.data.CollectionEntity
import com.vreader.app.data.LibraryRepository
import com.vreader.app.data.VReaderDatabase
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import vreader.contracts.BookFormat
import vreader.contracts.Identity
import vreader.contracts.backup.BackupCollection
import vreader.contracts.backup.BackupCollectionsEnvelope
import vreader.contracts.backup.BackupJson
import vreader.contracts.backup.BackupLibraryManifestEnvelope
import vreader.contracts.backup.BackupMetadata
import vreader.contracts.backup.BackupSchema
import java.io.File
import java.time.Instant
import java.util.Locale

/**
 * Feature #127 WI-6 — collections backup/restore. BackupCollector emits a deterministic `collections.json`
 * (sorted by nameKey, keys filtered to backed-up books + sorted → byte-stable); RestoreImporter merges it
 * by nameKey (create-with-backup-createdAt if absent, else keep existing + its createdAt), unions membership
 * for existing books only (unknown keys dropped). In-memory Room (Robolectric).
 */
@RunWith(RobolectricTestRunner::class)
class CollectionBackupTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private lateinit var db: VReaderDatabase
    private lateinit var repo: LibraryRepository
    private lateinit var dao: CollectionDao
    private val readable = mutableSetOf<String>()
    private val now = Instant.parse("2026-06-29T12:00:00Z")

    @Before fun setUp() {
        db = Room.inMemoryDatabaseBuilder(context, VReaderDatabase::class.java).build()
        repo = LibraryRepository(db.bookDao(), db.readingPositionDao())
        dao = db.collectionDao()
    }

    @After fun tearDown() { db.close() }

    private suspend fun seedBook(seed: Char, bytes: Long = 2048L): String {
        val sha = seed.toString().repeat(64)
        val key = Identity.canonicalKey(BookFormat.epub.name, sha, bytes)
        val path = "/data/$seed.epub"; readable += path
        repo.upsertBook(Book(key, "Book-$seed", BookFormat.epub, sha, bytes, path, null, 1000L, null))
        return key
    }

    private suspend fun seedCollection(name: String, createdAt: Long, members: List<String>) {
        val id = "id-$name-$createdAt"
        dao.insertCollection(CollectionEntity(id, name, name.lowercase(Locale.ROOT), createdAt))
        for (m in members) dao.addMembership(m, id)
    }

    private fun collector() = BackupCollector(repo, fileChecker = { it in readable }, collectionDao = dao)
    private suspend fun collectCollectionsJson(): String =
        collector().collect("Dev", "0.13.7", "bid", now).sections[BackupCollector.COLLECTIONS_SECTION]!!

    /** Rebuild a fresh in-memory db (avoids `clearAllTables`, which asserts off-main-thread under
     *  `runTest`), run [seed] against it, and return the collections.json — for byte-stability across
     *  two independently-seeded-but-logically-equal libraries. */
    private suspend fun freshDbCollectionsJson(seed: suspend () -> Unit): String {
        db.close()
        db = Room.inMemoryDatabaseBuilder(context, VReaderDatabase::class.java).build()
        repo = LibraryRepository(db.bookDao(), db.readingPositionDao())
        dao = db.collectionDao()
        readable.clear()
        seed()
        return collectCollectionsJson()
    }

    private fun importer() = BookImporter(File(context.cacheDir, "books-${System.nanoTime()}"), repo, Dispatchers.Unconfined)
    private fun restorer() = RestoreImporter(
        importer(), repo, fetchBlob = { throw IllegalStateException("no blobs in this test") },
        ioDispatcher = Dispatchers.Unconfined, collectionDao = dao,
    )

    /** A *.vreader.zip reader carrying only metadata + an empty manifest + the optional collections section. */
    private fun readerWith(env: BackupCollectionsEnvelope?): BackupArchiveReader {
        val sections = buildMap {
            if (env != null) put(BackupCollector.COLLECTIONS_SECTION, BackupJson.encode(env))
        }
        val manifest = BackupLibraryManifestEnvelope(BackupSchema.MANIFEST_SCHEMA_VERSION, emptyList())
        val meta = BackupMetadata("bid", now, "Dev", "0.13.7", bookCount = 0, totalSizeBytes = 0L)
        return BackupArchiveReader.read(BackupArchiveWriter.write(meta, manifest, sections))
    }

    @Test fun collect_emitsCollectionsSortedByNameKey_keysFilteredAndSorted() = runTest {
        val a = seedBook('a'); val b = seedBook('b')
        seedCollection("Tech", 300, listOf(a))
        seedCollection("Fiction", 100, listOf(b, a))
        seedCollection("Bio", 200, emptyList())

        val env = BackupJson.decode<BackupCollectionsEnvelope>(collectCollectionsJson())
        assertEquals(BackupSchema.CURRENT_SCHEMA_VERSION, env.schemaVersion)
        assertEquals(listOf("Bio", "Fiction", "Tech"), env.collections.map { it.name })   // nameKey order
        assertEquals(emptyList<String>(), env.collections[0].bookFingerprintKeys)          // Bio is empty
        assertEquals(listOf(a, b).sorted(), env.collections[1].bookFingerprintKeys)        // Fiction keys sorted
        assertEquals(listOf(a), env.collections[2].bookFingerprintKeys)                    // Tech
    }

    @Test fun collect_isByteStable_acrossInsertOrder() = runTest {
        val first = freshDbCollectionsJson {
            val a = seedBook('a'); val b = seedBook('b')
            seedCollection("Tech", 300, listOf(a, b))
            seedCollection("Fiction", 100, listOf(b))
        }
        // The SAME logical library, seeded in a different collection + membership insert order.
        val second = freshDbCollectionsJson {
            val a = seedBook('a'); val b = seedBook('b')
            seedCollection("Fiction", 100, listOf(b))      // Fiction inserted first this time
            seedCollection("Tech", 300, listOf(b, a))      // members in reverse order
        }
        assertEquals("collections.json is byte-stable regardless of row insert order", first, second)
    }

    @Test fun restore_createsCollections_unionsMembership_dropsUnknownKeys() = runTest {
        val a = seedBook('a'); val b = seedBook('b')
        val env = BackupCollectionsEnvelope(
            BackupSchema.CURRENT_SCHEMA_VERSION,
            listOf(
                BackupCollection("Tech", Instant.ofEpochMilli(300), listOf(a, "no-such-book-key")),
                BackupCollection("Fiction", Instant.ofEpochMilli(100), listOf(b)),
            ),
        )
        val result = restorer().restore(readerWith(env))

        assertEquals(2, result.collectionsRestored)
        val cols = dao.getAllCollections().sortedBy { it.nameKey }
        assertEquals(listOf("Fiction", "Tech"), cols.map { it.name })
        assertEquals(listOf(a), dao.bookKeysInCollection(cols.first { it.nameKey == "tech" }.id))  // unknown dropped
        assertEquals(listOf(b), dao.bookKeysInCollection(cols.first { it.nameKey == "fiction" }.id))
    }

    @Test fun restore_mergeByNameKey_keepsExistingCreatedAt_andUnionsMembers() = runTest {
        val a = seedBook('a'); val b = seedBook('b')
        seedCollection("Fiction", 100L, listOf(a))   // pre-existing collection with member a
        val env = BackupCollectionsEnvelope(
            BackupSchema.CURRENT_SCHEMA_VERSION,
            listOf(BackupCollection("FICTION", Instant.ofEpochMilli(999L), listOf(b))),  // case-variant, later createdAt
        )
        val result = restorer().restore(readerWith(env))

        assertEquals(1, result.collectionsRestored)
        val cols = dao.getAllCollections()
        assertEquals(1, cols.size)                                   // merged by nameKey, not duplicated
        assertEquals(100L, cols[0].createdAt)                        // existing createdAt kept (never overwritten)
        assertEquals(listOf(a, b).sorted(), dao.bookKeysInCollection(cols[0].id).sorted())  // membership union
    }

    @Test fun restore_selective_restoresOnlySelectedMembership_andSkipsUnrelatedCollections() = runTest {
        val a = seedBook('a'); val b = seedBook('b')
        val env = BackupCollectionsEnvelope(
            BackupSchema.CURRENT_SCHEMA_VERSION,
            listOf(
                BackupCollection("Tech", Instant.ofEpochMilli(300), listOf(a, b)),     // mixed members
                BackupCollection("Fiction", Instant.ofEpochMilli(100), listOf(b)),     // only b — unrelated to {a}
            ),
        )
        // Only book a is selected (a retryBook / selective restore) — Fiction (b-only) must NOT be created,
        // and book b must NOT be added to Tech even though b exists locally (Gate-4 WI-6 High).
        val result = restorer().restore(readerWith(env), selection = setOf(a))

        assertEquals(1, result.collectionsRestored)
        val cols = dao.getAllCollections()
        assertEquals(listOf("Tech"), cols.map { it.name })                 // Fiction skipped (no selected member)
        assertEquals(listOf(a), dao.bookKeysInCollection(cols[0].id))      // only a, not the unselected b
    }

    @Test fun restore_whitespaceName_mergesWithTrimmedExisting() = runTest {
        val a = seedBook('a'); val b = seedBook('b')
        seedCollection("Fiction", 100L, listOf(a))   // existing nameKey "fiction"
        val env = BackupCollectionsEnvelope(
            BackupSchema.CURRENT_SCHEMA_VERSION,
            listOf(BackupCollection("  Fiction  ", Instant.ofEpochMilli(999L), listOf(b))),  // whitespace-padded
        )
        val result = restorer().restore(readerWith(env))

        assertEquals(1, result.collectionsRestored)
        val cols = dao.getAllCollections()
        assertEquals(1, cols.size)                                          // trimmed → merged, not duplicated
        assertEquals(100L, cols[0].createdAt)
        assertEquals(listOf(a, b).sorted(), dao.bookKeysInCollection(cols[0].id).sorted())
    }

    @Test fun restore_absentCollectionsSection_isNoOp() = runTest {
        seedBook('a')
        val result = restorer().restore(readerWith(null))
        assertEquals(0, result.collectionsRestored)
        assertTrue(dao.getAllCollections().isEmpty())
    }
}
