// Purpose: feature #113 WI-1 (#110 Phase 3) — the CORE identity-bearing backup section
// DTOs: annotations (highlights/bookmarks/notes), positions, collections, and the library
// manifest. Field-name-identical to the Swift reference (BackupSectionDTOs.swift) so a
// backup written on one platform restores on the other. UUIDs are Strings (Swift UUID
// JSON-encodes as a string); Dates use IsoInstantSerializer (Swift .iso8601); nil optionals
// are OMITTED via BackupJson.DEFAULT's explicitNulls=false. Cross-book refs are by
// fingerprintKey (the canonical identity). The remaining sections (settings/book-sources/
// per-book-settings/replacement-rules/reading-history/ai-conversations) land in WI-2.
package vreader.contracts.backup

import kotlinx.serialization.Serializable
import java.time.Instant

// MARK: - Annotations

/** Highlights / bookmarks / notes flattened across all books. */
@Serializable
data class BackupAnnotationsEnvelope(
    override val schemaVersion: Int,
    val highlights: List<BackupHighlight>,
    val bookmarks: List<BackupBookmark>,
    val notes: List<BackupNote>,
) : BackupVersionedEnvelope

@Serializable
data class BackupHighlight(
    val highlightId: String,
    val bookFingerprintKey: String,
    val locatorJSON: String,
    val selectedText: String,
    val color: String,
    val note: String? = null,
    @Serializable(IsoInstantSerializer::class) val createdAt: Instant,
    @Serializable(IsoInstantSerializer::class) val updatedAt: Instant,
)

@Serializable
data class BackupBookmark(
    val bookmarkId: String,
    val bookFingerprintKey: String,
    val locatorJSON: String,
    val title: String? = null,
    @Serializable(IsoInstantSerializer::class) val createdAt: Instant,
    @Serializable(IsoInstantSerializer::class) val updatedAt: Instant,
)

@Serializable
data class BackupNote(
    val annotationId: String,
    val bookFingerprintKey: String,
    val locatorJSON: String,
    val content: String,
    @Serializable(IsoInstantSerializer::class) val createdAt: Instant,
    @Serializable(IsoInstantSerializer::class) val updatedAt: Instant,
)

// MARK: - Positions

/** Reading positions per book. `locatorJSON` is a PLAIN `Locator` (not `VReaderLocator`). */
@Serializable
data class BackupPositionsEnvelope(
    override val schemaVersion: Int,
    val positions: List<BackupPosition>,
) : BackupVersionedEnvelope

@Serializable
data class BackupPosition(
    val bookFingerprintKey: String,
    val locatorJSON: String,
    @Serializable(IsoInstantSerializer::class) val updatedAt: Instant,
    @Serializable(IsoInstantSerializer::class) val lastOpenedAt: Instant? = null,
)

// MARK: - Collections

@Serializable
data class BackupCollectionsEnvelope(
    override val schemaVersion: Int,
    val collections: List<BackupCollection>,
) : BackupVersionedEnvelope

@Serializable
data class BackupCollection(
    val name: String,
    @Serializable(IsoInstantSerializer::class) val createdAt: Instant,
    val bookFingerprintKeys: List<String>,
)

// MARK: - Library Manifest (the materializing-restore index, manifest schema 1)

@Serializable
data class BackupLibraryManifestEnvelope(
    override val schemaVersion: Int,
    val books: List<BackupLibraryEntry>,
) : BackupVersionedEnvelope

/** One book in the manifest: canonical fingerprint fields + the WebDAV blob path, so the
 *  materializer re-attaches positions/annotations by `fingerprintKey` and downloads the blob.
 *  `sourceCanonicalKey` (feature #108) is null for native/non-Kindle/pre-#108 books and is
 *  back-compatible (older manifest without it decodes to null). */
@Serializable
data class BackupLibraryEntry(
    val fingerprintKey: String,
    val format: String,
    val sha256: String,
    val byteCount: Long,
    val originalExtension: String,
    val title: String? = null,
    val author: String? = null,
    @Serializable(IsoInstantSerializer::class) val addedAt: Instant,
    @Serializable(IsoInstantSerializer::class) val lastOpenedAt: Instant? = null,
    val blobPath: String,
    val sourceCanonicalKey: String? = null,
)
