// Purpose: Tests for SchemaV6 migration — adds Book.fileState (default "local")
// and Book.blobPath (optional nil). Lightweight additive migration; existing rows
// default to .local with nil blobPath.
//
// @coordinates-with: SchemaV5.swift, SchemaV6.swift, Book.swift,
//   dev-docs/plans/20260503-feature-47-selective-picker-lazy-load.md (WI-1)

import Testing
import Foundation
import SwiftData
@testable import vreader

@Suite("V5toV6Migration")
struct V5toV6MigrationTests {

    // MARK: - SchemaV6 structure

    @Test func schemaV6VersionIsSixZeroZero() {
        #expect(SchemaV6.versionIdentifier == Schema.Version(6, 0, 0))
    }

    @Test func schemaV6HasSameModelCountAsV5() {
        // V6 is additive on Book — same model classes registered.
        #expect(SchemaV6.models.count == SchemaV5.models.count)
    }

    @Test func migrationPlanIncludesV6() {
        // V6 is in the plan; SchemaV7 (feature #56) is now the tail.
        let names = VReaderMigrationPlan.schemas.map { String(describing: $0) }
        #expect(names.contains(String(describing: SchemaV6.self)))
    }

    @Test func migrationPlanLength() {
        // V1…V8 — eight schemas (V8 added by feature #42, V7 by feature #56).
        #expect(VReaderMigrationPlan.schemas.count == 8)
    }

    @Test func migrationPlanHasNoExplicitStages() {
        // V5→V6 is a lightweight additive migration (default String + optional String).
        // SwiftData infers it automatically.
        let stages = VReaderMigrationPlan.stages
        #expect(stages.isEmpty)
    }

    // MARK: - Book defaults under V6

    @Test func newBookDefaultsToLocalFileState() throws {
        let schema = Schema(SchemaV6.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let fp = DocumentFingerprint(
            contentSHA256: String(repeating: "a", count: 64),
            fileByteCount: 1024,
            format: .epub
        )
        let book = Book(
            fingerprint: fp,
            title: "Test",
            provenance: ImportProvenance(source: .filesApp, importedAt: Date(), originalURLBookmarkData: nil)
        )
        context.insert(book)
        try context.save()

        // Default fileState is "local"; default blobPath is nil.
        #expect(book.fileState == "local")
        #expect(book.blobPath == nil)
    }

    @Test func bookCanStoreNonLocalFileState() throws {
        let schema = Schema(SchemaV6.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let fp = DocumentFingerprint(
            contentSHA256: String(repeating: "b", count: 64),
            fileByteCount: 2048,
            format: .epub
        )
        let book = Book(
            fingerprint: fp,
            title: "Remote",
            provenance: ImportProvenance(source: .filesApp, importedAt: Date(), originalURLBookmarkData: nil)
        )
        book.fileState = "remoteOnly"
        book.blobPath = "VReader/books/epub/abc_2048.epub"
        context.insert(book)
        try context.save()

        #expect(book.fileState == "remoteOnly")
        #expect(book.blobPath == "VReader/books/epub/abc_2048.epub")
    }

    @Test func fetchedBookRetainsFileState() throws {
        let schema = Schema(SchemaV6.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let fp = DocumentFingerprint(
            contentSHA256: String(repeating: "c", count: 64),
            fileByteCount: 4096,
            format: .pdf
        )
        let book = Book(
            fingerprint: fp,
            title: "Round-trip",
            provenance: ImportProvenance(source: .filesApp, importedAt: Date(), originalURLBookmarkData: nil)
        )
        book.fileState = "downloading"
        book.blobPath = "VReader/books/pdf/c_4096.pdf"
        context.insert(book)
        try context.save()

        let key = book.fingerprintKey
        let predicate = #Predicate<Book> { $0.fingerprintKey == key }
        let descriptor = FetchDescriptor<Book>(predicate: predicate)
        let fetched = try context.fetch(descriptor).first
        #expect(fetched != nil)
        #expect(fetched?.fileState == "downloading")
        #expect(fetched?.blobPath == "VReader/books/pdf/c_4096.pdf")
    }
}
