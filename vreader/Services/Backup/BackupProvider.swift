// Purpose: Protocol for backup/restore operations against any storage backend.
// Defines the contract that concrete providers (WebDAV, iCloud) must satisfy.
// Phase E will add concrete implementations; this file is protocol-only.
//
// @coordinates-with: BackupMetadata (below), BackupError (below)

import Foundation

// MARK: - BackupMetadata

/// Metadata describing a single backup snapshot.
///
/// Codable for local persistence (e.g., caching backup lists).
/// Sendable for safe cross-actor transfer.
struct BackupMetadata: Codable, Sendable, Identifiable, Equatable {
    /// Unique identifier for this backup.
    let id: UUID
    /// When the backup was created.
    let createdAt: Date
    /// Human-readable device name (e.g., "iPhone 17 Pro").
    let deviceName: String
    /// App version that created this backup.
    let appVersion: String
    /// Number of books included in the backup.
    let bookCount: Int
    /// Total uncompressed size of all backup data in bytes.
    let totalSizeBytes: Int64
}

// MARK: - BackupError

/// Errors that backup/restore operations can produce.
enum BackupError: Error, Sendable, Equatable {
    /// The backup archive could not be created.
    case archiveCreationFailed(String)
    /// The backup archive is corrupted or unreadable.
    case archiveCorrupted(String)
    /// The storage backend is unreachable or unavailable.
    case storageUnavailable(String)
    /// No backup exists with the given ID.
    case backupNotFound(UUID)
    /// The operation was cancelled by the user or system.
    case cancelled
    /// One or more sections of an otherwise-valid archive failed to restore.
    /// Other sections were applied; the user can retry the missing pieces.
    case restorePartiallyFailed(String)
}

// MARK: - BackupProvider Protocol

/// Contract for backup storage backends.
///
/// Concrete implementations (WebDAV, iCloud Drive) will be added in Phase E.
/// All methods are async and report progress via a callback.
///
/// - Important: Implementations must be `Sendable` for safe use across actors.
protocol BackupProvider: Sendable {
    /// Creates a new backup of the current library.
    ///
    /// - Parameter progress: Called with values in `[0, 1]` as the backup proceeds.
    ///   Values are non-decreasing and the final call is always `1.0`.
    /// - Returns: Metadata describing the completed backup.
    /// - Throws: `BackupError` on failure.
    func backup(progress: @Sendable (Double) -> Void) async throws -> BackupMetadata

    /// Restores the library from a previous backup.
    ///
    /// - Parameters:
    ///   - backupId: The `id` of the backup to restore (from `listBackups()`).
    ///   - progress: Called with values in `[0, 1]` as the restore proceeds.
    /// - Throws: `BackupError.backupNotFound` if `backupId` is unknown.
    func restore(backupId: UUID, progress: @Sendable (Double) -> Void) async throws

    /// Lists all available backups, sorted newest first.
    ///
    /// - Returns: An array of `BackupMetadata`, sorted by `createdAt` descending.
    ///   Returns an empty array if no backups exist.
    func listBackups() async throws -> [BackupMetadata]

    /// Deletes a backup.
    ///
    /// - Parameter id: The `id` of the backup to delete.
    /// - Throws: `BackupError.backupNotFound` if `id` is unknown.
    func deleteBackup(id: UUID) async throws
}
