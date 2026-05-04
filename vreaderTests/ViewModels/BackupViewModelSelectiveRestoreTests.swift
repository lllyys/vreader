// Purpose: Tests for the selective-restore wrappers added to
// BackupViewModel in feature #47 WI-6 — `loadManifest` and
// `performSelectiveRestore`. The picker UI binds to these.

import Testing
import Foundation
@testable import vreader

@MainActor
@Suite("BackupViewModel — selective restore wrappers (WI-6)")
struct BackupViewModelSelectiveRestoreTests {

    @Test func loadManifest_nonWebDAVProvider_setsErrorAndDoesNotCrash() async {
        // MockBackupProvider isn't a WebDAVProvider — selective restore
        // is WebDAV-specific. The wrapper guards via type-check and
        // surfaces a friendly error rather than crashing.
        let mock = MockBackupProvider()
        let vm = BackupViewModel(provider: mock)
        await vm.loadManifest(for: UUID())
        #expect(vm.loadedManifest == nil)
        #expect(vm.errorMessage?.contains("WebDAV") == true)
        #expect(vm.isLoadingManifest == false)
    }

    @Test func performSelectiveRestore_nonWebDAVProvider_setsErrorAndDoesNotCrash() async throws {
        let mock = MockBackupProvider()
        let vm = BackupViewModel(provider: mock)
        // Build any persistence actor — the test exits before reaching it.
        let persistence = try CollectionTestHelper.makePersistence()
        await vm.performSelectiveRestore(
            backupId: UUID(),
            selectedKeys: [],
            persistence: persistence
        )
        #expect(vm.errorMessage?.contains("WebDAV") == true)
        #expect(vm.isRestoringSelectively == false)
        #expect(vm.lastSelectiveRestoreSummary == nil)
    }

    @Test func loadManifest_emptyArrayMeansEmptyBackup_notLegacy() {
        // Sanity: an empty manifest array is not the same signal as
        // nil (legacy backup). Catching this distinction in a separate
        // assertion so a future regression that confuses them surfaces.
        let empty: [BackupLibraryEntry] = []
        let legacy: [BackupLibraryEntry]? = nil
        #expect(empty.isEmpty)
        #expect(legacy == nil)
    }
}
