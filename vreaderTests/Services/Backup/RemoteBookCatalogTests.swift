// Purpose: Tests for RemoteBookCatalog — decodes library-manifest.json
// out of a backup ZIP into the [BackupLibraryEntry] rows the
// selective-restore picker (#47 WI-6) shows. Feature #47 WI-4a.

import Testing
import Foundation
@testable import vreader

@Suite("RemoteBookCatalog — feature #47 WI-4a")
struct RemoteBookCatalogTests {

    // MARK: - Helpers

    private static func makeEntry(
        format: String = "epub",
        sha: String = String(repeating: "a", count: 64),
        bytes: Int64 = 1024,
        title: String = "Book"
    ) -> BackupLibraryEntry {
        let path = BlobPath.make(
            format: BookFormat(rawValue: format) ?? .epub,
            sha256: sha,
            byteCount: bytes
        )
        return BackupLibraryEntry(
            fingerprintKey: "\(format):\(sha):\(bytes)",
            format: format,
            sha256: sha,
            byteCount: bytes,
            originalExtension: format,
            title: title,
            author: "A",
            addedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastOpenedAt: nil,
            blobPath: path
        )
    }

    private static func makeManifestZIP(envelope: BackupLibraryManifestEnvelope) throws -> Data {
        let json = try JSONEncoder().encode(envelope)
        return try ZIPWriter.createArchive(entries: [
            ZIPWriter.Entry(name: "library-manifest.json", data: json),
            ZIPWriter.Entry(name: "metadata.json", data: Data("{}".utf8))
        ])
    }

    private static func makeZIPWithoutManifest() throws -> Data {
        try ZIPWriter.createArchive(entries: [
            ZIPWriter.Entry(name: "metadata.json", data: Data("{}".utf8))
        ])
    }

    // MARK: - Happy path

    @Test func loadEntries_validManifestWithBooks_returnsAll() throws {
        let entries = [
            Self.makeEntry(sha: String(repeating: "a", count: 64), title: "A"),
            Self.makeEntry(sha: String(repeating: "b", count: 64), title: "B"),
            Self.makeEntry(sha: String(repeating: "c", count: 64), title: "C")
        ]
        let envelope = BackupLibraryManifestEnvelope(schemaVersion: 1, books: entries)
        let zip = try Self.makeManifestZIP(envelope: envelope)

        let decoded = try RemoteBookCatalog.loadEntries(fromBackupZIP: zip)
        #expect(decoded.count == 3)
        #expect(decoded.map(\.title) == ["A", "B", "C"])
        #expect(decoded[0].fingerprintKey == entries[0].fingerprintKey)
    }

    @Test func loadEntries_validManifestWithEmptyBooks_returnsEmpty() throws {
        let envelope = BackupLibraryManifestEnvelope(schemaVersion: 1, books: [])
        let zip = try Self.makeManifestZIP(envelope: envelope)
        let decoded = try RemoteBookCatalog.loadEntries(fromBackupZIP: zip)
        #expect(decoded.isEmpty)
    }

    // MARK: - Error paths

    @Test func loadEntries_zipWithoutManifest_throwsManifestMissing() throws {
        let zip = try Self.makeZIPWithoutManifest()
        do {
            _ = try RemoteBookCatalog.loadEntries(fromBackupZIP: zip)
            Issue.record("expected throw")
        } catch let error as RemoteBookCatalogError {
            #expect(error == .manifestMissing)
        }
    }

    @Test func loadEntries_undecodableManifest_throwsManifestUndecodable() throws {
        let zip = try ZIPWriter.createArchive(entries: [
            ZIPWriter.Entry(name: "library-manifest.json", data: Data("not json".utf8))
        ])
        do {
            _ = try RemoteBookCatalog.loadEntries(fromBackupZIP: zip)
            Issue.record("expected throw")
        } catch let RemoteBookCatalogError.manifestUndecodable(reason) {
            #expect(!reason.isEmpty)
        }
    }

    @Test func loadEntries_futureSchemaVersion_throwsSchemaVersionTooNew() throws {
        // Hand-craft envelope JSON with a future schemaVersion. Direct
        // struct init can't bypass the constant currentSchemaVersion.
        let json = """
        {"schemaVersion":99,"books":[]}
        """.data(using: .utf8)!
        let zip = try ZIPWriter.createArchive(entries: [
            ZIPWriter.Entry(name: "library-manifest.json", data: json)
        ])
        do {
            _ = try RemoteBookCatalog.loadEntries(fromBackupZIP: zip)
            Issue.record("expected throw")
        } catch let RemoteBookCatalogError.manifestSchemaVersionTooNew(saw, supported) {
            #expect(saw == 99)
            #expect(supported == RemoteBookCatalog.supportedSchemaVersion)
        }
    }

    @Test func loadEntries_garbageZIPData_throwsManifestMissing() throws {
        // A non-ZIP byte buffer should fail extractEntry and surface as
        // manifestMissing — not a crash.
        let bogus = Data(repeating: 0xAB, count: 100)
        do {
            _ = try RemoteBookCatalog.loadEntries(fromBackupZIP: bogus)
            Issue.record("expected throw")
        } catch let error as RemoteBookCatalogError {
            #expect(error == .manifestMissing)
        }
    }

    // MARK: - Constants

    @Test func supportedSchemaVersionIsOne() {
        #expect(RemoteBookCatalog.supportedSchemaVersion == 1)
    }

    @Test func manifestFilenameMatchesProducer() {
        // WebDAVProvider emits "library-manifest.json" — keep the
        // catalog reader in lock-step.
        #expect(RemoteBookCatalog.manifestFilename == "library-manifest.json")
    }
}
