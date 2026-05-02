// Purpose: ViewModel for the WebDAV backup section of WebDAVSettingsView.
// Owns the user-facing backup/restore/list/delete flows: progress reporting,
// error surfacing, and refreshing the on-server backup catalog.
//
// Key decisions:
// - @MainActor + @Observable so SwiftUI binds directly without extra ceremony.
// - Backups happen in detached Tasks; progress is published via @Published-style
//   stored properties updated on the main actor.
// - The provider is injected, not constructed here, so tests can drive a Mock.
//   See WebDAVProviderFactory for the production wiring.
// - Errors surface as a single `errorMessage` string for easy banner display;
//   the underlying error is logged via OSLog.
//
// @coordinates-with: WebDAVSettingsView.swift, WebDAVProviderFactory.swift,
//   BackupProvider.swift, BackupDataCollector.swift, BackupDataRestorer.swift

import Foundation
import OSLog
import SwiftUI

private let log = Logger(subsystem: "com.vreader.app", category: "BackupVM")

@MainActor
@Observable
final class BackupViewModel {

    // MARK: - State

    /// Loaded backups, newest first. Populated by `loadBackups()`.
    var backups: [BackupMetadata] = []

    /// True while `loadBackups()` is in flight.
    var isLoading: Bool = false

    /// True while a backup is being created.
    var isBackingUp: Bool = false

    /// Progress (0.0 → 1.0) of the in-flight backup, if any.
    var backupProgress: Double = 0.0

    /// True while a restore is in flight.
    var isRestoring: Bool = false

    /// Progress (0.0 → 1.0) of the in-flight restore, if any.
    var restoreProgress: Double = 0.0

    /// Surfaced as a banner / inline error in the UI. Cleared by the user or
    /// by the next operation that succeeds.
    var errorMessage: String?

    /// True after a backup completes successfully (resets on next op).
    var lastBackupSucceeded: Bool = false

    // MARK: - Dependencies

    private let provider: BackupProvider

    // MARK: - Init

    init(provider: BackupProvider) {
        self.provider = provider
    }

    // MARK: - Operations

    /// Fetches the catalog of backups from the server. Newest first.
    func loadBackups() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            backups = try await provider.listBackups()
        } catch {
            log.error("listBackups failed: \(String(describing: error), privacy: .public)")
            errorMessage = userMessage(for: error, action: "Failed to load backups")
        }
    }

    /// Creates a new backup and uploads it to the server. Refreshes the list on success.
    func performBackup() async {
        isBackingUp = true
        backupProgress = 0.0
        errorMessage = nil
        lastBackupSucceeded = false
        defer { isBackingUp = false }

        do {
            _ = try await provider.backup { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.backupProgress = progress
                }
            }
            lastBackupSucceeded = true
            await loadBackups()
        } catch {
            log.error("backup failed: \(String(describing: error), privacy: .public)")
            errorMessage = userMessage(for: error, action: "Backup failed")
        }
    }

    /// Restores the given backup. Caller is responsible for confirming destructive intent.
    func performRestore(backupId: UUID) async {
        isRestoring = true
        restoreProgress = 0.0
        errorMessage = nil
        defer { isRestoring = false }

        do {
            try await provider.restore(backupId: backupId) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.restoreProgress = progress
                }
            }
        } catch {
            log.error("restore failed: \(String(describing: error), privacy: .public)")
            errorMessage = userMessage(for: error, action: "Restore failed")
        }
    }

    /// Deletes the given backup from the server. Refreshes the list on success.
    func deleteBackup(id: UUID) async {
        errorMessage = nil
        do {
            try await provider.deleteBackup(id: id)
            await loadBackups()
        } catch {
            log.error("deleteBackup failed: \(String(describing: error), privacy: .public)")
            errorMessage = userMessage(for: error, action: "Failed to delete backup")
        }
    }

    // MARK: - Helpers

    private func userMessage(for error: Error, action: String) -> String {
        if let backupError = error as? BackupError {
            return "\(action): \(backupError.userMessage)"
        }
        if let restoreError = error as? BackupRestoreError {
            return "\(action): \(restoreError.userMessage)"
        }
        return "\(action): \(error.localizedDescription)"
    }
}

extension BackupRestoreError {
    var userMessage: String {
        switch self {
        case .unsupportedSchemaVersion(let section, let actual, let supported):
            return "Backup section '\(section)' uses schema v\(actual); this version supports v\(supported). Update the app to restore."
        case .partialFailure(let section, let failed, let total):
            return "\(failed) of \(total) entries in section '\(section)' failed to restore."
        }
    }
}

// MARK: - BackupError UI Surface

extension BackupError {
    /// User-visible explanation; never includes paths or stack details.
    var userMessage: String {
        switch self {
        case .archiveCorrupted: return "The backup archive is corrupted."
        case .archiveCreationFailed: return "Could not create the backup archive."
        case .backupNotFound: return "Backup not found on the server."
        case .storageUnavailable(let msg): return "Server unavailable. \(msg)"
        case .cancelled: return "Cancelled."
        case .restorePartiallyFailed(let sections):
            return "These sections didn't restore: \(sections). Other sections were applied; try the restore again."
        }
    }
}
