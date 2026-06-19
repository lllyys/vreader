// Purpose: feature #114 WI-1 (#110 Phase 3) — the UI-oriented seam between the backup/restore
// UI (BackupViewModel) and the future WebDAV client + restore pipeline (a SEPARATE backend
// feature). Deliberately UI-shaped (Gate-2 Medium-2): no blob paths / ZIP / PROPFIND / raw
// download concepts leak in. The production AppContainer injects nothing here yet; a DEBUG
// PreviewBackupService drives the designed states for emulator verification.
package com.vreader.app.backup

import kotlinx.coroutines.flow.Flow

/** A WebDAV error the client can surface — each maps to one designed error block + CTA. */
enum class WebDavError { auth401, notFound404, offline, timeout }

/** A saved server as the list renders it (the design's SERVERS shape). */
data class ServerSummary(
    val id: String,
    val name: String,
    val url: String,
    val status: ServerStatus,
    val detail: String,
    val wifiOnly: Boolean,
)

enum class ServerStatus { ok, error, unknown }

/** The live add/edit form (Test Connection runs against THIS, no save first). */
data class ServerDraft(
    val name: String,
    val baseUrl: String,
    val username: String,
    val password: String,
    val wifiOnly: Boolean,
)

/** One backup on the server (date · books · size · device, newest tagged latest). */
data class BackupSummary(
    val id: String,
    val whenLabel: String,
    val sizeLabel: String,
    val device: String,
    val books: Int,
    val latest: Boolean,
)

/** A book in a backup manifest; `state` is the whole point of the selective picker. */
data class ManifestBook(
    val id: String,
    val title: String,
    val author: String?,
    val sizeLabel: String,
    val state: BookState,
    val progress: Float = 0f,
)

enum class BookState { local, remote, downloading, failed }

/** Test-connection outcome — `Ok` carries the "found /vreader with N backups" detail; `Fail`
 *  carries the TYPED cause (so the designed server-test states render exactly, not by parsing
 *  text — Gate-4) plus the user-facing message. */
sealed interface TestResult {
    data class Ok(val detail: String) : TestResult
    data class Fail(val cause: WebDavError, val message: String) : TestResult
}

/** Reading the server's backup list — ok(list) or a typed WebDAV error. */
sealed interface BackupListResult {
    data class Ok(val backups: List<BackupSummary>) : BackupListResult
    data class Error(val cause: WebDavError) : BackupListResult
}

/** Backup progress (done/total); the Flow completes when the backup finishes. */
data class BackupProgress(val done: Int, val total: Int)

/** Restore progress: per-book download, then a terminal result (success/partial/failed). */
sealed interface RestoreProgress {
    data class InProgress(val done: Int, val total: Int, val currentTitle: String) : RestoreProgress
    data class Result(val outcome: RestoreOutcome, val restored: Int, val total: Int, val failed: Int) : RestoreProgress
}

enum class RestoreOutcome { success, partial, failed }

enum class BookRestoreResult { restored, failed }

/**
 * UI-oriented backup/restore seam. The future WebDAV+restore backend implements this; the UI
 * never sees networking/ZIP/blob mechanics. All suspend/Flow so cancellation propagates.
 */
interface BackupService {
    suspend fun listServers(): List<ServerSummary>
    suspend fun testConnection(draft: ServerDraft): TestResult
    suspend fun listBackups(serverId: String): BackupListResult
    /** Emits progress; completes (or throws) when the backup finishes. */
    fun startBackup(serverId: String): Flow<BackupProgress>
    suspend fun loadManifest(backupId: String): List<ManifestBook>
    /** Emits per-book progress then a terminal [RestoreProgress.Result]. */
    fun restore(backupId: String, selection: Set<String>): Flow<RestoreProgress>
    suspend fun retryBook(backupId: String, bookId: String): BookRestoreResult
}
