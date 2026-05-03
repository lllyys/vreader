// Purpose: Integration test for RemoteBookCatalog against a real
// backup ZIP produced by a live rclone-backed WebDAV server. Pins the
// pre-#46 backup compatibility behavior — older backups land in
// `manifestMissing` (not crash, not garbled). Feature #47 WI-7.
//
// Fixture: vreaderTests/Fixtures/legacy-backup-no-manifest.vreader.zip
// — a real backup ZIP captured from the user's
// ~/vreader-webdav-data/VReader/backups/ directory on 2026-05-03,
// produced by a vreader build that pre-dates #46's
// library-manifest.json emit. 8 entries (metadata + 7 metadata
// sections) and zero books.

import Testing
import Foundation
@testable import vreader

@Suite("RemoteBookCatalog — rclone backup integration (WI-7)")
struct RemoteBookCatalogIntegrationTests {

    private func loadFixture() throws -> Data {
        let bundle = Bundle(for: TestBundleAnchor.self)
        let url = try #require(bundle.url(
            forResource: "legacy-backup-no-manifest",
            withExtension: "vreader.zip"
        ))
        return try Data(contentsOf: url)
    }

    /// Anchor class so `Bundle(for:)` resolves to the test bundle.
    private final class TestBundleAnchor {}

    @Test func loadEntries_legacyBackupWithoutManifest_throwsManifestMissing() throws {
        let zipData = try loadFixture()
        do {
            _ = try RemoteBookCatalog.loadEntries(fromBackupZIP: zipData)
            Issue.record("expected manifestMissing for legacy backup")
        } catch let error as RemoteBookCatalogError {
            #expect(error == .manifestMissing)
        }
    }

    @Test func legacyBackup_zipDataIsNonEmptyAndReadable() throws {
        // Sanity: the fixture loaded, it's a valid byte buffer, and
        // it's the size we expect (~5.3 KB per the captured backup).
        let zipData = try loadFixture()
        #expect(zipData.count > 1000)
        #expect(zipData.count < 100_000)
        // ZIP magic bytes.
        #expect(zipData.starts(with: [0x50, 0x4B, 0x03, 0x04]))
    }
}
