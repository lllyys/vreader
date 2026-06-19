// Purpose: feature #114 WI-1 (#110 Phase 3) — the immutable UI-state models for the backup &
// restore surfaces, each a pure mirror of a designed state in vreader-backup-webdav.jsx. The
// BackupViewModel owns these as StateFlow; the Compose screens (WI-2+) render them. One-shot
// effects (nav to server settings, toasts) go through BackupEvent, never the durable state.
package com.vreader.app.backup

// ── Backup & Restore screen (surface C) ───────────────────────

/** The Available-Backups area state — loading / idle(list) / empty / error(cause). */
sealed interface BackupListUi {
    data object Loading : BackupListUi
    data class Idle(val backups: List<BackupSummary>) : BackupListUi
    data object Empty : BackupListUi
    data class Error(val cause: WebDavError) : BackupListUi
}

/** Non-null while "Back Up Now" is running (drives the inline "Backing up… d / t"). */
data class Syncing(val done: Int, val total: Int)

/** The Backup & Restore screen's durable state. */
data class BackupUiState(
    val activeServer: ServerSummary? = null,
    val list: BackupListUi = BackupListUi.Loading,
    val syncing: Syncing? = null,
)

/** One-shot effects the screen consumes once (mirrors LibraryEvent). */
sealed interface BackupEvent {
    /** A 401 error CTA asks to open server settings. */
    data object OpenServerSettings : BackupEvent
    data class Toast(val message: String) : BackupEvent
}
