// Purpose: feature #113 WI-1 (#110 Phase 3) — backup archive schema constants + the
// restore-error type + the versioned-envelope interface. Mirrors the Swift reference
// (vreader/Services/Backup/BackupSectionDTOs.swift): kBackupCurrentSchemaVersion=3,
// accepted={1,2,3}, manifest schema=1. Pure JVM, in :identity so the conformance lane
// (no :app dep) tests the same code the app will run.
package vreader.contracts.backup

/** Backup archive schema versions — the cross-platform contract (backup-format.md). */
object BackupSchema {
    /** What the COLLECTOR emits (schema 3 = +ai-conversations on top of v2's +reading-history). */
    const val CURRENT_SCHEMA_VERSION = 3

    /** What a RESTORER accepts — the pre-v3 section shapes are byte-identical across v1/v2/v3. */
    val ACCEPTED_SCHEMA_VERSIONS = setOf(1, 2, 3)

    /** `library-manifest.json` carries its own schema, separate from the global one. */
    const val MANIFEST_SCHEMA_VERSION = 1
}

/** Errors on the backup restore path — mirrors Swift `BackupRestoreError`. */
sealed class BackupRestoreError : Exception() {
    /** A section was produced by a newer schema this client doesn't know about. */
    data class UnsupportedSchemaVersion(
        val section: String,
        val actual: Int,
        val supported: Int,
    ) : BackupRestoreError()

    /** Some per-entry restores in a section failed while others succeeded. */
    data class PartialFailure(
        val section: String,
        val failed: Int,
        val total: Int,
    ) : BackupRestoreError()
}

/** Common shape every section envelope honors so a restorer can validate `schemaVersion`
 *  without special-casing each section — mirrors Swift `BackupVersionedEnvelope`. */
interface BackupVersionedEnvelope {
    val schemaVersion: Int
}
