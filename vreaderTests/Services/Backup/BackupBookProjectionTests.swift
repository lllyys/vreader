// Purpose: Tests for BackupBookProjection + PersistenceActor.fetchAllBooksForBackup().
// Feature #46 WI-0a: foundational projection that BackupDataCollector.collectLibraryManifest
// will use to emit library-manifest.json without leaking SwiftData @Model instances.
//
// @coordinates-with: vreader/Services/PersistenceActor+Backup.swift,
//   vreader/Models/Book.swift, dev-docs/plans/20260503-feature-46-materializing-restore.md

import Testing
import Foundation
import SwiftData
@testable import vreader

@Suite("BackupBookProjection — feature #46 WI-0a")
struct BackupBookProjectionTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(SchemaV5.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makePersistence() throws -> PersistenceActor {
        PersistenceActor(modelContainer: try makeContainer())
    }

    private func makeFingerprint(
        sha: String,
        byteCount: Int64 = 1024,
        format: BookFormat = .epub
    ) -> DocumentFingerprint {
        DocumentFingerprint(contentSHA256: sha, fileByteCount: byteCount, format: format)
    }

    private func makeRecord(
        sha: String,
        format: BookFormat = .epub,
        title: String = "Test",
        author: String? = nil,
        addedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        lastOpenedAt: Date? = nil,
        originalExtension: String? = nil
    ) -> BookRecord {
        let fp = makeFingerprint(sha: sha, format: format)
        return BookRecord(
            fingerprintKey: fp.canonicalKey,
            title: title,
            author: author,
            coverImagePath: nil,
            fingerprint: fp,
            provenance: ImportProvenance(source: .filesApp, importedAt: addedAt, originalURLBookmarkData: nil),
            detectedEncoding: nil,
            addedAt: addedAt,
            originalExtension: originalExtension,
            lastOpenedAt: lastOpenedAt
        )
    }

    // MARK: - Empty library

    @Test func fetchAllBooksForBackup_emptyLibrary_returnsEmpty() async throws {
        let persistence = try makePersistence()
        let projections = try await persistence.fetchAllBooksForBackup()
        #expect(projections.isEmpty)
    }

    // MARK: - Single book — happy path

    @Test func fetchAllBooksForBackup_singleEpub_populatesAllFields() async throws {
        let persistence = try makePersistence()
        let sha = String(repeating: "a", count: 64)
        let added = Date(timeIntervalSince1970: 1_700_000_000)
        let record = makeRecord(
            sha: sha,
            format: .epub,
            title: "Alice",
            author: "Carroll",
            addedAt: added,
            originalExtension: "epub"
        )
        _ = try await persistence.insertBook(record)

        let projections = try await persistence.fetchAllBooksForBackup()
        #expect(projections.count == 1)

        let p = projections[0]
        #expect(p.fingerprintKey == "epub:\(sha):1024")
        #expect(p.format == "epub")
        #expect(p.sha256 == sha)
        #expect(p.byteCount == 1024)
        #expect(p.title == "Alice")
        #expect(p.author == "Carroll")
        #expect(p.addedAt == added)
        #expect(p.lastOpenedAt == nil)
        #expect(p.originalExtension == "epub")
    }

    // MARK: - Original extension preserves MOBI under .azw3 canonical

    @Test func fetchAllBooksForBackup_mobiUnderAzw3_preservesOriginalExtension() async throws {
        let persistence = try makePersistence()
        let sha = String(repeating: "b", count: 64)
        let record = makeRecord(
            sha: sha,
            format: .azw3,
            title: "Old MOBI",
            originalExtension: "mobi"
        )
        _ = try await persistence.insertBook(record)

        let projections = try await persistence.fetchAllBooksForBackup()
        #expect(projections.count == 1)
        // Canonical format stays azw3 (DocumentFingerprint uses BookFormat enum which collapses MOBI/PRC/AZW into .azw3).
        #expect(projections[0].format == "azw3")
        // Original extension preserved so restore can write the right .ext to the temp file.
        #expect(projections[0].originalExtension == "mobi")
    }

    // MARK: - Migration default for legacy rows missing originalExtension

    @Test func fetchAllBooksForBackup_legacyRowMissingOriginalExtension_defaultsToCanonical() async throws {
        let persistence = try makePersistence()
        let sha = String(repeating: "c", count: 64)
        // Insert with originalExtension = nil — simulates legacy V4 row migrated to V5.
        let record = makeRecord(sha: sha, format: .pdf, originalExtension: nil)
        _ = try await persistence.insertBook(record)

        let projections = try await persistence.fetchAllBooksForBackup()
        #expect(projections.count == 1)
        // Projection coalesces nil into the canonical extension for the format.
        #expect(projections[0].originalExtension == "pdf")
    }

    // MARK: - Multiple books

    @Test func fetchAllBooksForBackup_multipleBooks_returnsAllSorted() async throws {
        let persistence = try makePersistence()
        let sha1 = String(repeating: "1", count: 64)
        let sha2 = String(repeating: "2", count: 64)
        let sha3 = String(repeating: "3", count: 64)
        _ = try await persistence.insertBook(makeRecord(sha: sha1, format: .epub, title: "B1"))
        _ = try await persistence.insertBook(makeRecord(sha: sha2, format: .txt, title: "B2"))
        _ = try await persistence.insertBook(makeRecord(sha: sha3, format: .pdf, title: "B3"))

        let projections = try await persistence.fetchAllBooksForBackup()
        #expect(projections.count == 3)
        // Stable sort by fingerprintKey so output is deterministic across runs.
        let keys = projections.map(\.fingerprintKey)
        #expect(keys == keys.sorted())
    }
}
