// Purpose: feature #108 WI-1 — SchemaV10 adds the additive optional
// `Book.sourceCanonicalKey: String?` (converted-Kindle cross-platform identity).
// Verifies: (1) the schema/plan structure; (2) the field round-trips through
// PersistenceActor insert→fetch; (3) a V9 store reopens under V10 (lightweight
// migration) preserving rows with `sourceCanonicalKey == nil` (existing converted
// books grandfather — their source bytes were discarded).
//
// @coordinates-with: SchemaV10.swift, SchemaV1.swift (VReaderMigrationPlan),
//   Book.swift, PersistenceActor.swift (BookRecord),
//   dev-docs/plans/20260618-feature-108-kindle-source-bytes-identity.md

import Testing
import Foundation
import SwiftData
@testable import vreader

@Suite("SchemaV10 source-key migration (#108 WI-1)")
struct SchemaV10SourceKeyMigrationTests {

    // MARK: - Structure

    @Test func schemaV10VersionIsTenZeroZero() {
        #expect(SchemaV10.versionIdentifier == Schema.Version(10, 0, 0))
    }

    @Test func migrationPlanIncludesV10AsLastWithNoStages() {
        #expect(VReaderMigrationPlan.schemas.count == 10)
        #expect(String(describing: VReaderMigrationPlan.schemas.last!) == String(describing: SchemaV10.self))
        // V9→V10 is an additive lightweight migration — no explicit stage.
        #expect(VReaderMigrationPlan.stages.isEmpty)
    }

    // MARK: - Round-trip through PersistenceActor

    @Test func sourceCanonicalKeyRoundTripsThroughInsertAndFetch() async throws {
        let container = try ModelContainer(
            for: Schema(SchemaV10.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let persistence = PersistenceActor(modelContainer: container)

        // A converted-Kindle book: local primary key is the converted EPUB; the
        // cross-platform identity is the source-bytes key.
        let epubFP = DocumentFingerprint(
            contentSHA256: String(repeating: "a", count: 64), fileByteCount: 2048, format: .epub)
        let sourceKey = "azw3:\(String(repeating: "b", count: 64)):4096"
        let record = BookRecord(
            fingerprintKey: epubFP.canonicalKey, title: "Converted Kindle", author: nil,
            coverImagePath: nil, fingerprint: epubFP,
            provenance: ImportProvenance(source: .filesApp, importedAt: Date(timeIntervalSince1970: 1), originalURLBookmarkData: nil),
            detectedEncoding: nil, addedAt: Date(timeIntervalSince1970: 1),
            originalExtension: "epub", sourceCanonicalKey: sourceKey)

        let inserted = try await persistence.insertBook(record)
        #expect(inserted.sourceCanonicalKey == sourceKey)

        let fetched = try await persistence.findBook(byFingerprintKey: epubFP.canonicalKey)
        #expect(fetched?.sourceCanonicalKey == sourceKey)
    }

    @Test func sourceCanonicalKeyDefaultsNilForNativeImport() async throws {
        let container = try ModelContainer(
            for: Schema(SchemaV10.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let persistence = PersistenceActor(modelContainer: container)
        let fp = DocumentFingerprint(
            contentSHA256: String(repeating: "c", count: 64), fileByteCount: 100, format: .epub)
        let record = BookRecord(
            fingerprintKey: fp.canonicalKey, title: "Native", author: nil, coverImagePath: nil,
            fingerprint: fp,
            provenance: ImportProvenance(source: .filesApp, importedAt: Date(timeIntervalSince1970: 1), originalURLBookmarkData: nil),
            detectedEncoding: nil, addedAt: Date(timeIntervalSince1970: 1))
        let inserted = try await persistence.insertBook(record)
        #expect(inserted.sourceCanonicalKey == nil)
    }

    // MARK: - Disk-backed V9 → V10 (lightweight)

    @Test func v9StoreReopensUnderV10WithNilSourceKey() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("v9v10src-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("store.sqlite")

        let fp = DocumentFingerprint(
            contentSHA256: String(repeating: "e", count: 64), fileByteCount: 4096, format: .epub)
        let provenance = ImportProvenance(source: .filesApp, importedAt: Date(timeIntervalSince1970: 1_700_000_000), originalURLBookmarkData: nil)

        // Seed a V9 store on disk (no sourceCanonicalKey written).
        do {
            let v9 = try ModelContainer(for: Schema(SchemaV9.models),
                                        configurations: [ModelConfiguration(url: storeURL)])
            let ctx = ModelContext(v9)
            ctx.insert(Book(fingerprint: fp, title: "Grandfathered", provenance: provenance, originalExtension: "epub"))
            try ctx.save()
        }

        // Reopen under V10 + the plan → lightweight migration adds the nil column.
        let v10 = try ModelContainer(for: Schema(SchemaV10.models), migrationPlan: VReaderMigrationPlan.self,
                                     configurations: [ModelConfiguration(url: storeURL)])
        let ctx = ModelContext(v10)
        let books = try ctx.fetch(FetchDescriptor<Book>())
        #expect(books.count == 1)
        let migrated = try #require(books.first)
        #expect(migrated.title == "Grandfathered")
        #expect(migrated.fingerprintKey == fp.canonicalKey)
        #expect(migrated.sourceCanonicalKey == nil)   // additive column defaults nil
    }
}
