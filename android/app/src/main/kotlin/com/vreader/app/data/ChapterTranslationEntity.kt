// Purpose: feature #131 WI-2 — the Room entity for the bilingual translation cache
// (`chapter_translations`). The Android mirror of the iOS ChapterTranslation @Model:
// one cached translation per canonical key. `lookupKey` is the PK (the dedupe key
// `bookKey|unitStorageKey|targetLanguage|promptVersion`, profile-AGNOSTIC per iOS
// Bug #342 — the provider profile is provenance, NOT identity, so a re-translate /
// profile re-creation shares the same row). Every column is NON-NULL. The FK
// (bookKey → books.fingerprintKey ON DELETE CASCADE) drops a book's cached
// translations when the book is deleted, the same shape as every other child table.
// `sourceParagraphCount` records the segment count this translation was produced for
// (load-bearing for the count-keyed cache-restore path — H2).
//
// The column names/order/nullability MUST match VReaderDatabase.MIGRATION_8_9's exact
// DDL AND Room's generated schemas/…/9.json (the migration test opens the real Room DB
// so its structural PRAGMA validation catches any drift — cf. #135's stale-version
// finding).
//
// @coordinates-with: VReaderDatabase.kt (MIGRATION_8_9, entities), ChapterTranslationDao.kt,
//   com.vreader.app.bilingual.ChapterTranslationStore, TranslationUnitId.kt,
//   iOS vreader/Models/ChapterTranslation.swift / ChapterTranslationRecord.swift,
//   dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md (WI-2)
package com.vreader.app.data

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * One cached chapter/unit translation. Keyed by [lookupKey] =
 * `bookKey|unitStorageKey|targetLanguage|promptVersion` (profile-agnostic, iOS Bug #342).
 * [translatedJson] holds the ordered JSON string-array of translated segments
 * (the [TranslationChunkContract] wire form); [sourceParagraphCount] is the source
 * segment count when the translation was produced.
 */
@Entity(
    tableName = "chapter_translations",
    foreignKeys = [
        ForeignKey(
            entity = BookEntity::class,
            parentColumns = ["fingerprintKey"],
            childColumns = ["bookKey"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [Index("bookKey")],
)
data class ChapterTranslationEntity(
    @PrimaryKey val lookupKey: String,   // bookKey|unitStorageKey|targetLanguage|promptVersion
    val bookKey: String,                 // fingerprintKey (FK)
    val unitStorageKey: String,          // TranslationUnitId.storageKey
    val targetLanguage: String,          // BCP-47-ish tag (e.g. "zh-Hans")
    val promptVersion: String,           // bumping it invalidates cached rows
    val translatedJson: String,          // ordered JSON string-array of translated segments
    val sourceParagraphCount: Int,       // source segment count at production time
    val createdAt: Long,                 // epoch millis when produced
)
