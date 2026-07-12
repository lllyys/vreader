// Purpose: feature #131 WI-2 — the coroutine boundary over ChapterTranslationDao.
// The Android analog of the iOS ChapterTranslationStore actor. It keeps Room entities
// OFF the boundary: reads decode the row's `translatedJson` into an ordered segment
// list and return the value-type [CachedTranslation]; writes encode the segment list
// back to JSON. `lookupKey` is the canonical dedupe key (bookKey|unit|lang|prompt),
// profile-agnostic per iOS Bug #342, built via [CachedTranslation.lookupKey] so the
// store and the (WI-3) translation service always agree.
//
// Key decisions (mirroring iOS):
// - A row whose stored `translatedJson` cannot be decoded into a string array is
//   treated as a cache MISS (returns null), NEVER a fake empty-translation hit — so
//   corruption can't masquerade as a legitimate hit and get served forever. A
//   well-formed empty array "[]" is a legitimate hit (empty segments), kept distinct
//   from a decode failure (null).
// - `upsert` is idempotent via the DAO's `@Upsert` on the `lookupKey` PK.
//
// @coordinates-with: com.vreader.app.data.ChapterTranslationDao,
//   com.vreader.app.data.ChapterTranslationEntity, TranslationChunkContract.kt
//   (the same JSON string-array wire form), TranslationUnitId.kt,
//   iOS vreader/Services/ChapterTranslationStore.swift,
//   dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md (WI-2)
package com.vreader.app.bilingual

import com.vreader.app.data.ChapterTranslationDao
import com.vreader.app.data.ChapterTranslationEntity
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json

/**
 * A decoded cached translation — the value type crossing the store boundary
 * (never the Room entity). [translatedSegments] is the decoded, ordered segment
 * list; [sourceParagraphCount] is the source segment count at production time.
 */
data class CachedTranslation(
    val bookKey: String,
    val unitStorageKey: String,
    val targetLanguage: String,
    val promptVersion: String,
    val translatedSegments: List<String>,
    val sourceParagraphCount: Int,
    val createdAt: Long,
) {
    /** The canonical `lookupKey` for this translation's identity. */
    val lookupKey: String get() =
        lookupKey(bookKey, unitStorageKey, targetLanguage, promptVersion)

    companion object {
        /**
         * The canonical dedupe key `bookKey|unitStorageKey|targetLanguage|promptVersion`
         * — the single source of truth. Profile-AGNOSTIC (iOS Bug #342): the provider
         * profile is provenance, not identity. `|` is the separator; none of the
         * components legitimately contains it (`unitStorageKey` uses `:`, language
         * tags + prompt versions are alphanumeric/dash).
         */
        fun lookupKey(
            bookKey: String,
            unitStorageKey: String,
            targetLanguage: String,
            promptVersion: String,
        ): String = listOf(bookKey, unitStorageKey, targetLanguage, promptVersion).joinToString("|")
    }
}

/** Coroutine cache boundary over [ChapterTranslationDao] returning decoded value types. */
class ChapterTranslationStore(private val dao: ChapterTranslationDao) {

    /**
     * Returns the cached translation for [lookupKey], or null on a miss. A row whose
     * `translatedJson` cannot be decoded is a MISS (not a fake hit).
     */
    suspend fun translation(lookupKey: String): CachedTranslation? =
        dao.getByLookupKey(lookupKey)?.let { decode(it) }

    /** Idempotently inserts or updates one translation (upsert on the `lookupKey` PK). */
    suspend fun upsert(translation: CachedTranslation) {
        dao.upsert(
            ChapterTranslationEntity(
                lookupKey = translation.lookupKey,
                bookKey = translation.bookKey,
                unitStorageKey = translation.unitStorageKey,
                targetLanguage = translation.targetLanguage,
                promptVersion = translation.promptVersion,
                translatedJson = encodeSegments(translation.translatedSegments),
                sourceParagraphCount = translation.sourceParagraphCount,
                createdAt = translation.createdAt,
            ),
        )
    }

    /** Removes one cached translation by `lookupKey`; a missing key is a silent no-op. */
    suspend fun delete(lookupKey: String) {
        dao.deleteByLookupKey(lookupKey)
    }

    /**
     * Decodes a stored entity into the value type. Returns null when `translatedJson`
     * is not a JSON string array — a corrupt row surfaces as a cache MISS, never a
     * fake hit.
     */
    private fun decode(entity: ChapterTranslationEntity): CachedTranslation? {
        val segments = decodeSegments(entity.translatedJson) ?: return null
        return CachedTranslation(
            bookKey = entity.bookKey,
            unitStorageKey = entity.unitStorageKey,
            targetLanguage = entity.targetLanguage,
            promptVersion = entity.promptVersion,
            translatedSegments = segments,
            sourceParagraphCount = entity.sourceParagraphCount,
            createdAt = entity.createdAt,
        )
    }

    private companion object {
        private val json = Json { ignoreUnknownKeys = true }
        private val listSerializer = ListSerializer(String.serializer())

        /** JSON-encodes an ordered segment array (a `[String]` never fails to encode). */
        fun encodeSegments(segments: List<String>): String =
            json.encodeToString(listSerializer, segments)

        /**
         * Strictly decodes the stored JSON into a segment list, or null on a malformed
         * blob. A well-formed empty array "[]" decodes to an empty list (a legitimate
         * value, kept distinct from null).
         */
        fun decodeSegments(raw: String): List<String>? =
            runCatching { json.decodeFromString(listSerializer, raw) }.getOrNull()
    }
}
