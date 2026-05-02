// Purpose: In-memory mock of BackupProvider for contract testing.
// Stores backups in a dictionary and supports cancellation simulation.
//
// @coordinates-with: BackupProvider.swift, BackupProviderContractTests.swift

import Foundation
@testable import vreader

/// In-memory mock of BackupProvider for unit and contract tests.
///
/// - Note: Uses `final class` (not actor) because the protocol requires `Sendable`
///   and all mutable state is protected by `@unchecked Sendable` with synchronous
///   access from a single test context. For true concurrent testing, wrap in an actor.
final class MockBackupProvider: BackupProvider, @unchecked Sendable {

    // MARK: - Configuration

    /// When true, the next `backup()` call throws `BackupError.cancelled`.
    var simulateCancellation = false

    /// Device name reported in metadata.
    var deviceName = "Test Device"

    /// App version reported in metadata.
    var appVersion = "0.1.0"

    /// Number of books to report per backup.
    var bookCount = 5

    /// Total size in bytes to report per backup.
    var totalSizeBytes: Int64 = 2048

    /// Per-operation failure injection.
    enum InjectedFailure { case none, listBackups, backup, restore, delete }
    var shouldFailNextOperation: InjectedFailure = .none

    // MARK: - Internal State

    /// In-memory backup store keyed by UUID. Public so tests can pre-seed.
    var metadataList: [BackupMetadata] {
        get { Array(backups.values) }
        set { backups = Dictionary(uniqueKeysWithValues: newValue.map { ($0.id, $0) }) }
    }

    private var backups: [UUID: BackupMetadata] = [:]

    // MARK: - BackupProvider

    func backup(progress: @Sendable (Double) -> Void) async throws -> BackupMetadata {
        if simulateCancellation {
            throw BackupError.cancelled
        }
        if shouldFailNextOperation == .backup {
            shouldFailNextOperation = .none
            throw BackupError.archiveCreationFailed("injected failure")
        }

        // Simulate progress: 0 → 0.5 → 1.0
        progress(0.0)
        progress(0.5)
        progress(1.0)

        let metadata = BackupMetadata(
            id: UUID(),
            createdAt: Date(),
            deviceName: deviceName,
            appVersion: appVersion,
            bookCount: bookCount,
            totalSizeBytes: totalSizeBytes
        )

        backups[metadata.id] = metadata
        return metadata
    }

    func restore(backupId: UUID, progress: @Sendable (Double) -> Void) async throws {
        if shouldFailNextOperation == .restore {
            shouldFailNextOperation = .none
            throw BackupError.archiveCorrupted("injected failure")
        }
        guard backups[backupId] != nil else {
            throw BackupError.backupNotFound(backupId)
        }

        // Simulate progress: 0 → 0.5 → 1.0
        progress(0.0)
        progress(0.5)
        progress(1.0)
    }

    func listBackups() async throws -> [BackupMetadata] {
        if shouldFailNextOperation == .listBackups {
            shouldFailNextOperation = .none
            throw BackupError.storageUnavailable("injected failure")
        }
        return backups.values
            .sorted { $0.createdAt > $1.createdAt }
    }

    func deleteBackup(id: UUID) async throws {
        if shouldFailNextOperation == .delete {
            shouldFailNextOperation = .none
            throw BackupError.storageUnavailable("injected failure")
        }
        guard backups.removeValue(forKey: id) != nil else {
            throw BackupError.backupNotFound(id)
        }
    }

    // MARK: - Test Helpers

    /// Resets all state.
    func reset() {
        backups = [:]
        simulateCancellation = false
    }
}
