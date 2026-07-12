// Purpose: feature #131 WI-2 — the Room DAO for the bilingual translation cache.
// The Android analog of the iOS ChapterTranslationStore CRUD (feature #56). `@Upsert`
// on the `lookupKey` PK is idempotent (insert-or-update-in-place), so re-caching the
// same canonical unit replaces the row rather than inserting a duplicate — and, unlike
// @Insert(REPLACE) (delete-then-insert in SQLite), it does NOT fire the FK CASCADE.
// Views never touch this DAO directly; the coroutine boundary is
// [com.vreader.app.bilingual.ChapterTranslationStore], which returns a decoded value
// type so Room entities stay off the boundary (rule 50 §2).
//
// @coordinates-with: ChapterTranslationEntity.kt, VReaderDatabase.kt,
//   com.vreader.app.bilingual.ChapterTranslationStore,
//   dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md (WI-2)
package com.vreader.app.data

import androidx.room.Dao
import androidx.room.Query
import androidx.room.Upsert

@Dao
interface ChapterTranslationDao {

    /** Returns the cached row for [key], or null on a miss. */
    @Query("SELECT * FROM chapter_translations WHERE lookupKey = :key")
    suspend fun getByLookupKey(key: String): ChapterTranslationEntity?

    /** Idempotent insert-or-update on the `lookupKey` PK (never REPLACE — see file doc). */
    @Upsert
    suspend fun upsert(row: ChapterTranslationEntity)

    /** Removes one cached translation by `lookupKey`; a missing key is a silent no-op. */
    @Query("DELETE FROM chapter_translations WHERE lookupKey = :key")
    suspend fun deleteByLookupKey(key: String)

    /** Total cached rows — a cache-management/diagnostic count. */
    @Query("SELECT COUNT(*) FROM chapter_translations")
    suspend fun count(): Int
}
