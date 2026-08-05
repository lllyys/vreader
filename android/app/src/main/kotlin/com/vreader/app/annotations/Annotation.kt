// Purpose: feature #123 — the annotation DTOs crossing the repository boundary (the iOS
// HighlightRecord/…Record analog; rule 50 §2: never return Room entities across a layer) + the
// entity<->record mappers + the profileKey/anchorKey derivation.
//
// Storage contract:
//  - `locatorJSON` stores the FULL serialized `Locator` (round-trippable, a PLAIN Locator — never a
//    VReaderLocator envelope or Readium JSON; the position-precedent of storing the round-trippable
//    form in Room). The on-wire `BackupHighlight.locatorJSON` is the SAME plain form — the backup
//    mapper emits `BackupJson.encode(locator)`, NOT `canonicalJson()` (`AnnotationBackupMapper`;
//    iOS parity, `contracts/identity/backup-format.md`). `canonicalJson()` is used ONLY to derive
//    `profileKey` below; it is a hashing input, never a wire format.
//  - `profileKey = "$bookKey:${sha256(locator.canonicalJson())}"` — derived from the CANONICAL form
//    so dedup is cross-platform-stable regardless of the stored round-trip form.
//  - `anchorKey = anchor?.anchorHash ?: NIL_ANCHOR` — the non-null dedupe sentinel.
package com.vreader.app.annotations

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import vreader.contracts.Locator
import java.util.UUID

const val NIL_ANCHOR = "__nil_anchor__"

private val ANNOTATION_JSON = Json { ignoreUnknownKeys = true; encodeDefaults = true }

fun profileKeyFor(bookKey: String, locator: Locator): String =
    "$bookKey:${AnnotationHashing.sha256Hex(locator.canonicalJson())}"

fun anchorKeyFor(anchor: AnnotationAnchor?): String = anchor?.anchorHash ?: NIL_ANCHOR

private fun Locator.toJson(): String = ANNOTATION_JSON.encodeToString(this)
private fun locatorFromJson(json: String): Locator = ANNOTATION_JSON.decodeFromString(json)

/** A highlight as the UI/repo sees it (the iOS `HighlightRecord` analog). */
data class HighlightRecord(
    val id: String,
    val bookKey: String,
    val color: AnnotationColor,
    val selectedText: String,
    val note: String?,
    val locator: Locator,
    val anchor: AnnotationAnchor?,
    val createdAt: Long,
    val updatedAt: Long,
)

data class NoteRecord(
    val id: String,
    val bookKey: String,
    val content: String,
    val locator: Locator,
    val anchor: AnnotationAnchor?,
    val createdAt: Long,
    val updatedAt: Long,
)

data class BookmarkRecord(
    val id: String,
    val bookKey: String,
    val title: String?,
    val locator: Locator,
    val createdAt: Long,
    val updatedAt: Long,
)

// ---- record -> entity ----

fun HighlightRecord.toEntity() = com.vreader.app.data.HighlightEntity(
    highlightId = id,
    bookKey = bookKey,
    profileKey = profileKeyFor(bookKey, locator),
    anchorKey = anchorKeyFor(anchor),
    color = color.key,
    selectedText = selectedText,
    note = note,
    locatorJSON = locator.toJson(),
    anchorJSON = anchor?.let { AnnotationAnchor.encode(it) },
    createdAt = createdAt,
    updatedAt = updatedAt,
)

fun NoteRecord.toEntity() = com.vreader.app.data.AnnotationNoteEntity(
    noteId = id,
    bookKey = bookKey,
    profileKey = profileKeyFor(bookKey, locator),
    content = content,
    locatorJSON = locator.toJson(),
    anchorJSON = anchor?.let { AnnotationAnchor.encode(it) },
    createdAt = createdAt,
    updatedAt = updatedAt,
)

fun BookmarkRecord.toEntity() = com.vreader.app.data.BookmarkEntity(
    bookmarkId = id,
    bookKey = bookKey,
    profileKey = profileKeyFor(bookKey, locator),
    title = title,
    locatorJSON = locator.toJson(),
    createdAt = createdAt,
    updatedAt = updatedAt,
)

// ---- entity -> record (null when locatorJSON is corrupt — skip, don't crash) ----

fun com.vreader.app.data.HighlightEntity.toRecordOrNull(): HighlightRecord? = runCatching {
    HighlightRecord(
        id = highlightId, bookKey = bookKey,
        color = AnnotationColor.from(color) ?: AnnotationColor.DEFAULT,
        selectedText = selectedText, note = note,
        locator = locatorFromJson(locatorJSON),
        anchor = AnnotationAnchor.decodeOrNull(anchorJSON),
        createdAt = createdAt, updatedAt = updatedAt,
    )
}.getOrNull()

fun com.vreader.app.data.AnnotationNoteEntity.toRecordOrNull(): NoteRecord? = runCatching {
    NoteRecord(
        id = noteId, bookKey = bookKey, content = content,
        locator = locatorFromJson(locatorJSON),
        anchor = AnnotationAnchor.decodeOrNull(anchorJSON),
        createdAt = createdAt, updatedAt = updatedAt,
    )
}.getOrNull()

fun com.vreader.app.data.BookmarkEntity.toRecordOrNull(): BookmarkRecord? = runCatching {
    BookmarkRecord(
        id = bookmarkId, bookKey = bookKey, title = title,
        locator = locatorFromJson(locatorJSON),
        createdAt = createdAt, updatedAt = updatedAt,
    )
}.getOrNull()

/** A fresh UUID string id for a new annotation (iOS `UUID()` parity). */
fun newAnnotationId(): String = UUID.randomUUID().toString()
