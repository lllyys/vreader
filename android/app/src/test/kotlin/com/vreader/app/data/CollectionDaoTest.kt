package com.vreader.app.data

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Feature #127 WI-1 — [CollectionDao] skeleton against an in-memory v5 Room DB (no migration). Covers
 * the WI-1 surface: upsert, findByNameKey, observe, membership add/remove (idempotent), and the reverse
 * lookup. The full transactional CRUD + counts + repository validation is WI-2.
 */
@RunWith(RobolectricTestRunner::class)
class CollectionDaoTest {
    private lateinit var db: VReaderDatabase
    private lateinit var dao: CollectionDao
    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val bookKey = "epub:${"a".repeat(64)}:2048"

    @Before fun setUp() {
        db = Room.inMemoryDatabaseBuilder(context, VReaderDatabase::class.java)
            .allowMainThreadQueries().build()
        dao = db.collectionDao()
        // a book row is required for the cross-ref FK.
        runBlocking {
            db.bookDao().upsert(
                BookEntity(bookKey, "T", "epub", "a".repeat(64), 2048L, null, null, 1L, null),
            )
        }
    }

    @After fun tearDown() = db.close()

    @Test fun insert_andFindByNameKey() = runBlocking {
        dao.insertCollection(CollectionEntity("c1", "Fiction", "fiction", 1L))
        assertEquals("Fiction", dao.findByNameKey("fiction")?.name)
        assertNull("no match for a different key", dao.findByNameKey("scifi"))
    }

    @Test fun observeCollections_emitsInsertedRows() = runBlocking {
        dao.insertCollection(CollectionEntity("c1", "Alpha", "alpha", 1L))
        dao.insertCollection(CollectionEntity("c2", "Beta", "beta", 2L))
        val rows = dao.observeCollections().first()
        assertEquals(listOf("Alpha", "Beta"), rows.map { it.name }) // ordered by createdAt ASC
    }

    @Test fun membership_addIdempotent_remove_reverseLookup() = runBlocking {
        dao.insertCollection(CollectionEntity("c1", "Fiction", "fiction", 1L))
        dao.addMembership(bookKey, "c1")
        dao.addMembership(bookKey, "c1") // INSERT OR IGNORE — no duplicate, no throw
        assertEquals(listOf(bookKey), dao.bookKeysInCollection("c1"))
        dao.removeMembership(bookKey, "c1")
        assertEquals(emptyList<String>(), dao.bookKeysInCollection("c1"))
    }
}
