// Purpose: feature #114 WI-2 (#110 Phase 3) — DEBUG-ONLY preview data for the backup/restore
// UI (the designed SERVERS/BACKUPS from vreader-backup-webdav.jsx). In src/debug so it is
// excluded from the release APK (Gate-2 High-1: no fake data ships to production). Drives
// BackupDebugActivity + is available to instrumented tests.
package com.vreader.app.backup

import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.flow

class PreviewBackupService : BackupService {
    override suspend fun listServers(): List<ServerSummary> = listOf(
        ServerSummary("nas", "Home NAS", "nas.local/dav/vreader", ServerStatus.ok, "Connected · last sync 9:14 AM", wifiOnly = true),
    )

    override suspend fun testConnection(draft: ServerDraft): TestResult =
        TestResult.Ok("Connected — found an existing /vreader folder with 3 backups.")

    override suspend fun listBackups(serverId: String): BackupListResult = BackupListResult.Ok(
        listOf(
            BackupSummary("b1", "Today, 9:14 AM", "4.2 MB", "Pixel 8 · this device", 12, latest = true),
            BackupSummary("b2", "Yesterday, 10:01 PM", "4.1 MB", "Pixel 8", 12, latest = false),
            BackupSummary("b3", "Jun 16, 8:30 AM", "3.9 MB", "iPad Air", 11, latest = false),
            BackupSummary("b4", "Jun 9, 7:42 PM", "3.6 MB", "iPhone 15", 10, latest = false),
        ),
    )

    override fun startBackup(serverId: String): Flow<BackupProgress> = flow {
        for (i in 1..12) {
            emit(BackupProgress(i, 12))
            delay(180)
        }
    }

    override suspend fun loadManifest(backupId: String): List<ManifestBook> = emptyList()
    override fun restore(backupId: String, selection: Set<String>): Flow<RestoreProgress> = emptyFlow()
    override suspend fun retryBook(backupId: String, bookId: String): BookRestoreResult = BookRestoreResult.restored
}
