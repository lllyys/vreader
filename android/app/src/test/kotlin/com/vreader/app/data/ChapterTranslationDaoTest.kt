package com.vreader.app.data

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Feature #131 WI-2 — [ChapterTranslationDao] CRUD / upsert-by-PK / FK-cascade over an in-memory
 * Room db (the iOS ChapterTranslationStore-test analog). A parent `books` row is seeded first
 * because the `bookKey → books.fingerprintKey` FK is enforced in-memory (Room enables FK).
 */
@RunWith(RobolectricTestRunner::class)
class ChapterTranslationDaoTest {
    private lateinit var db: VReaderDatabase
    private lateinit var dao: ChapterTranslationDao
    private val key = "epub:${"a".repeat(64)}:2048"

    @Before fun setUp() {
        db = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(), VReaderDatabase::class.java,
        ).build()
        dao = db.chapterTranslationDao()
        // a parent book is required for the FK
        runBlocking {
            db.bookDao().upsert(
                BookEntity(key, "War and Peace", "epub", "a".repeat(64), 2048L, null, null, 1L, null),
            )
        }
    }

    @After fun tearDown() = db.close()

    private fun row(
        lookupKey: String = "$key|epubHref:ch1|zh-Hans|bilingual-v1|g=paragraph",
        unitStorageKey: String = "epubHref:ch1",
        targetLanguage: String = "zh-Hans",
        promptVersion: String = "bilingual-v1|g=paragraph",
        translatedJson: String = """["你好","世界"]""",
        sourceParagraphCount: Int = 2,
        createdAt: Long = 100L,
        bookKey: String = key,
    ) = ChapterTranslationEntity(
        lookupKey = lookupKey, bookKey = bookKey, unitStorageKey = unitStorageKey,
        targetLanguage = targetLanguage, promptVersion = promptVersion,
        translatedJson = translatedJson, sourceParagraphCount = sourceParagraphCount,
        createdAt = createdAt,
    )

    @Test fun upsert_thenGetByLookupKey_returnsIt() = runBlocking {
        val r = row()
        dao.upsert(r)
        val got = dao.getByLookupKey(r.lookupKey)
        assertEquals("cached row round-trips", r, got)
    }

    @Test fun getByLookupKey_miss_returnsNull() = runBlocking {
        assertNull("a key never inserted is a miss", dao.getByLookupKey("no-such-key"))
    }

    @Test fun upsert_samePrimaryKey_replacesInPlace_notDuplicated() = runBlocking {
        val first = row(translatedJson = """["旧"]""", sourceParagraphCount = 1, createdAt = 100L)
        dao.upsert(first)
        // same lookupKey (PK), NEW payload → UPDATE in place, not a second row.
        val updated = first.copy(
            translatedJson = """["新一","新二"]""", sourceParagraphCount = 2, createdAt = 200L,
        )
        dao.upsert(updated)
        val got = dao.getByLookupKey(first.lookupKey)
        assertEquals("upsert updated in place", updated, got)
        assertEquals("only ONE row for the PK", 1, dao.count())
    }

    @Test fun deleteByLookupKey_removesTheRow() = runBlocking {
        val r = row()
        dao.upsert(r)
        dao.deleteByLookupKey(r.lookupKey)
        assertNull("row is gone", dao.getByLookupKey(r.lookupKey))
    }

    @Test fun deleteByLookupKey_missingKey_isSilentNoOp() = runBlocking {
        val r = row()
        dao.upsert(r)
        dao.deleteByLookupKey("some-other-key")   // does not exist → no-op
        assertEquals("the present row survives", r, dao.getByLookupKey(r.lookupKey))
    }

    @Test fun deletingBook_cascades_toChapterTranslations() = runBlocking {
        val r = row()
        dao.upsert(r)
        db.bookDao().delete(key)   // ON DELETE CASCADE
        assertNull("the cached translation cascaded away with its book", dao.getByLookupKey(r.lookupKey))
        assertEquals("no orphan rows remain", 0, dao.count())
    }

    @Test fun distinctLookupKeys_coexist() = runBlocking {
        val a = row(lookupKey = "$key|epubHref:ch1|zh-Hans|bilingual-v1|g=paragraph")
        val b = row(
            lookupKey = "$key|epubHref:ch1|es|bilingual-v1|g=paragraph",
            targetLanguage = "es", translatedJson = """["Hola","Mundo"]""",
        )
        dao.upsert(a)
        dao.upsert(b)
        assertEquals(a, dao.getByLookupKey(a.lookupKey))
        assertEquals(b, dao.getByLookupKey(b.lookupKey))
        assertEquals(2, dao.count())
    }
}
