// Purpose: Tests for BackupViewModel — orchestrates backup/restore/list/delete
// flows over an injected BackupProvider mock.
//
// @coordinates-with: BackupViewModel.swift, BackupProvider.swift,
//   MockBackupProvider.swift

import Testing
import Foundation
@testable import vreader

@MainActor
@Suite("BackupViewModel")
struct BackupViewModelSuite {

    private func makeProvider() -> MockBackupProvider {
        MockBackupProvider()
    }

    @Test func loadBackupsPopulatesArray() async {
        let provider = makeProvider()
        provider.metadataList = [
            BackupMetadata(
                id: UUID(), createdAt: Date(), deviceName: "iPhone",
                appVersion: "0.1.0", bookCount: 5, totalSizeBytes: 2048
            )
        ]
        let vm = BackupViewModel(provider: provider)

        await vm.loadBackups()

        #expect(vm.backups.count == 1)
        #expect(vm.errorMessage == nil)
    }

    @Test func loadBackupsSurfacesErrorMessage() async {
        let provider = makeProvider()
        provider.shouldFailNextOperation = .listBackups
        let vm = BackupViewModel(provider: provider)

        await vm.loadBackups()

        #expect(vm.backups.isEmpty)
        #expect(vm.errorMessage != nil)
        #expect(vm.errorMessage!.contains("Failed to load backups"))
    }

    @Test func performBackupReportsProgressAndRefreshes() async {
        let provider = makeProvider()
        let vm = BackupViewModel(provider: provider)

        await vm.performBackup()

        #expect(vm.lastBackupSucceeded == true)
        #expect(vm.errorMessage == nil)
        #expect(vm.backupProgress >= 0.99)
        #expect(vm.isBackingUp == false)
        // Refresh list should now contain the freshly-uploaded backup.
        #expect(vm.backups.count == 1)
    }

    @Test func performBackupSurfacesErrorMessage() async {
        let provider = makeProvider()
        provider.shouldFailNextOperation = .backup
        let vm = BackupViewModel(provider: provider)

        await vm.performBackup()

        #expect(vm.lastBackupSucceeded == false)
        #expect(vm.errorMessage != nil)
        #expect(vm.errorMessage!.contains("Backup failed"))
    }

    @Test func performRestoreReportsProgressAndCompletes() async throws {
        let provider = makeProvider()
        let createdMeta = try await provider.backup(progress: { _ in })
        let vm = BackupViewModel(provider: provider)

        await vm.performRestore(backupId: createdMeta.id)

        #expect(vm.errorMessage == nil)
        #expect(vm.restoreProgress >= 0.99)
        #expect(vm.isRestoring == false)
    }

    @Test func performRestoreSurfacesErrorMessage() async {
        let provider = makeProvider()
        provider.shouldFailNextOperation = .restore
        let vm = BackupViewModel(provider: provider)

        await vm.performRestore(backupId: UUID())

        #expect(vm.errorMessage != nil)
        #expect(vm.errorMessage!.contains("Restore failed"))
    }

    @Test func deleteBackupRemovesAndRefreshes() async throws {
        let provider = makeProvider()
        let metadata = try await provider.backup(progress: { _ in })
        let vm = BackupViewModel(provider: provider)
        await vm.loadBackups()
        #expect(vm.backups.count == 1)

        await vm.deleteBackup(id: metadata.id)

        #expect(vm.backups.isEmpty)
        #expect(vm.errorMessage == nil)
    }

    @Test func errorMessageClearedOnNextSuccessfulOp() async {
        let provider = makeProvider()
        provider.shouldFailNextOperation = .listBackups
        let vm = BackupViewModel(provider: provider)
        await vm.loadBackups()
        #expect(vm.errorMessage != nil)

        provider.shouldFailNextOperation = .none
        await vm.loadBackups()

        #expect(vm.errorMessage == nil)
    }
}

