package com.vreader.app.bilingual

import com.vreader.app.data.ChapterTranslationDao
import com.vreader.app.data.ChapterTranslationEntity
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Feature #131 WI-2 — [ChapterTranslationStore] decode/encode boundary. Uses an in-memory fake
 * DAO so this stays a pure store unit test (the DAO's own Room behavior is covered by
 * ChapterTranslationDaoTest). Verifies: value type round-trips (segments decoded from JSON and
 * back), the Room entity NEVER crosses the boundary, corrupt JSON is a MISS (not a fake hit),
 * a well-formed empty array is a legitimate empty hit (distinct from a miss), and lookupKey is
 * the canonical `book|unit|lang|prompt` (profile-agnostic).
 */
class ChapterTranslationStoreTest {

    private class FakeDao : ChapterTranslationDao {
        val rows = LinkedHashMap<String, ChapterTranslationEntity>()
        override suspend fun getByLookupKey(key: String): ChapterTranslationEntity? = rows[key]
        override suspend fun upsert(row: ChapterTranslationEntity) { rows[row.lookupKey] = row }
        override suspend fun deleteByLookupKey(key: String) { rows.remove(key) }
        override suspend fun count(): Int = rows.size
    }

    private fun cached(
        bookKey: String = "epub:${"a".repeat(64)}:2048",
        unitStorageKey: String = "epubHref:ch1",
        targetLanguage: String = "zh-Hans",
        promptVersion: String = "bilingual-v1|g=paragraph",
        segments: List<String> = listOf("你好", "世界"),
        sourceParagraphCount: Int = segments.size,
        createdAt: Long = 100L,
    ) = CachedTranslation(
        bookKey, unitStorageKey, targetLanguage, promptVersion, segments, sourceParagraphCount, createdAt,
    )

    @Test fun lookupKey_isCanonicalFourPartPipeJoined() {
        val t = cached()
        assertEquals(
            "epub:${"a".repeat(64)}:2048|epubHref:ch1|zh-Hans|bilingual-v1|g=paragraph",
            t.lookupKey,
        )
        assertEquals(
            "companion helper agrees with the instance property",
            t.lookupKey,
            CachedTranslation.lookupKey(t.bookKey, t.unitStorageKey, t.targetLanguage, t.promptVersion),
        )
    }

    @Test fun upsert_thenTranslation_roundTripsValueType() = runTest {
        val store = ChapterTranslationStore(FakeDao())
        val t = cached()
        store.upsert(t)
        assertEquals("decoded value type round-trips", t, store.translation(t.lookupKey))
    }

    @Test fun upsert_encodesSegmentsAsJsonStringArray_entityOffBoundary() = runTest {
        val dao = FakeDao()
        val store = ChapterTranslationStore(dao)
        store.upsert(cached(segments = listOf("你好", "世界")))
        // The store persisted a JSON string-array — the entity, not the value type, holds the JSON.
        val stored = dao.rows.values.single()
        assertEquals("""["你好","世界"]""", stored.translatedJson)
        assertEquals(2, stored.sourceParagraphCount)
    }

    @Test fun translation_miss_returnsNull() = runTest {
        val store = ChapterTranslationStore(FakeDao())
        assertNull(store.translation("nope"))
    }

    @Test fun translation_corruptJson_isTreatedAsMiss_notFakeHit() = runTest {
        val dao = FakeDao()
        // seed a row with undecodable translatedJson (not a JSON string array)
        val e = ChapterTranslationEntity(
            lookupKey = "k1", bookKey = "b", unitStorageKey = "u", targetLanguage = "zh-Hans",
            promptVersion = "p", translatedJson = "{not json array", sourceParagraphCount = 1,
            createdAt = 1L,
        )
        dao.rows[e.lookupKey] = e
        val store = ChapterTranslationStore(dao)
        assertNull("a corrupt row is a cache MISS, never a fake hit", store.translation("k1"))
    }

    @Test fun translation_wellFormedEmptyArray_isLegitimateEmptyHit() = runTest {
        val store = ChapterTranslationStore(FakeDao())
        val t = cached(segments = emptyList(), sourceParagraphCount = 0)
        store.upsert(t)
        val got = store.translation(t.lookupKey)
        assertEquals("empty array decodes to an empty (non-null) hit", t, got)
        assertTrue("segments are empty, not null", got!!.translatedSegments.isEmpty())
    }

    @Test fun delete_removesRow() = runTest {
        val store = ChapterTranslationStore(FakeDao())
        val t = cached()
        store.upsert(t)
        store.delete(t.lookupKey)
        assertNull(store.translation(t.lookupKey))
    }

    @Test fun roundTrip_preservesUnicodeAndEmbeddedQuotes() = runTest {
        val store = ChapterTranslationStore(FakeDao())
        // segments with embedded double-quotes + CJK + a literal backslash must survive JSON round-trip.
        val t = cached(segments = listOf("""She said "hi"""", "日本語\\パス", "café"))
        store.upsert(t)
        assertEquals(t, store.translation(t.lookupKey))
    }
}
