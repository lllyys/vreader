// Purpose: feature #113 WI-1 (#110 Phase 3) — `metadata.json`, written into every backup
// ZIP before the sections (Swift `BackupMetadata`, BackupProvider.swift:15). The Android
// backup-list UI (design-gated #1767) will read this to show available backups.
package vreader.contracts.backup

import kotlinx.serialization.Serializable
import java.time.Instant

/** Archive-level metadata — mirrors Swift `BackupMetadata` (id/createdAt/deviceName/
 *  appVersion/bookCount/totalSizeBytes). `id` is a UUID string (Swift `UUID`). */
@Serializable
data class BackupMetadata(
    val id: String,
    @Serializable(IsoInstantSerializer::class) val createdAt: Instant,
    val deviceName: String,
    val appVersion: String,
    val bookCount: Int,
    val totalSizeBytes: Long,
)
