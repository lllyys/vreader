// Purpose: Tests for WebDAVProvider.loadManifest + restoreSelectively
// added in feature #47 WI-6 part 1. Reuses MockWebDAVTransport and
// the StubCollector / NoopRestorer pattern from
// WebDAVProviderTests.swift. Feature #47 WI-6 part 1.

import Testing
import Foundation
@testable import vreader

@Suite("WebDAVProvider — loadManifest + restoreSelectively (WI-6)")
struct WebDAVProviderSelectiveRestoreTests {

    private final class TestBundleAnchor {}

    private static func loadLegacyZIPFixture() throws -> Data {
        let bundle = Bundle(for: TestBundleAnchor.self)
        let url = try #require(bundle.url(
            forResource: "legacy-backup-no-manifest",
            withExtension: "vreader.zip"
        ))
        return try Data(contentsOf: url)
    }

    /// Builds a provider whose mock transport already has the legacy
    /// fixture pre-staged at a backup path. Returns the path so tests
    /// can drive listBackups()-derived backupId lookups.
    private static func makeProviderWithLegacyBackup() async throws -> (WebDAVProvider, MockWebDAVTransport) {
        let zipData = try loadLegacyZIPFixture()
        let path = "VReader/backups/2026-05-03T08-07-21Z_cfaff06e.vreader.zip"
        let mock = MockWebDAVTransport()
        mock.files[path] = zipData

        let mockPersistence = MockPersistenceActor()
        let importer = BookImporter(
            persistence: mockPersistence,
            sandboxBooksDirectory: FileManager.default.temporaryDirectory
        )

        let provider = WebDAVProvider(
            transport: mock,
            dataCollector: WebDAVProviderBackupWithManifestTests.StubCollector(manifestEntries: []),
            dataRestorer: WebDAVProviderBackupWithManifestTests.NoopRestorer(),
            deviceName: "TestDevice",
            appVersion: "test",
            bookImporter: importer
        )
        return (provider, mock)
    }

    // MARK: - loadManifest

    @Test func loadManifest_legacyBackupWithoutManifest_returnsNil() async throws {
        let (provider, _) = try await Self.makeProviderWithLegacyBackup()
        let backups = try await provider.listBackups()
        let backup = try #require(backups.first)
        let manifest = try await provider.loadManifest(backupId: backup.id)
        #expect(manifest == nil)
    }

    @Test func loadManifest_unknownBackupId_throwsBackupNotFound() async throws {
        let (provider, _) = try await Self.makeProviderWithLegacyBackup()
        do {
            _ = try await provider.loadManifest(backupId: UUID())
            Issue.record("expected throw")
        } catch let error as BackupError {
            if case .backupNotFound = error {
                // ok
            } else {
                Issue.record("expected backupNotFound, got \(error)")
            }
        }
    }

    // MARK: - restoreSelectively

    @Test func restoreSelectively_legacyBackup_throwsArchiveCorrupted() async throws {
        // Legacy backups don't carry library-manifest.json. The
        // restoreSelectively API requires a #46+ backup; legacy ZIPs
        // surface as archiveCorrupted with a clear message.
        let (provider, _) = try await Self.makeProviderWithLegacyBackup()
        let backups = try await provider.listBackups()
        let backup = try #require(backups.first)

        let mockPersistence = MockPersistenceActor()
        let modelContainer = try CollectionTestHelper.makeContainer()
        let realPersistence = PersistenceActor(modelContainer: modelContainer)
        _ = mockPersistence  // unused — kept for symmetry

        do {
            _ = try await provider.restoreSelectively(
                backupId: backup.id,
                selectedKeys: [],
                persistence: realPersistence,
                progress: { _ in }
            )
            Issue.record("expected throw")
        } catch let error as BackupError {
            if case .archiveCorrupted(let msg) = error {
                #expect(msg.contains("library-manifest.json"))
            } else {
                Issue.record("expected archiveCorrupted, got \(error)")
            }
        }
    }
}
