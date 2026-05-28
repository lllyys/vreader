// Purpose: Tests for SchemaV7 migration — adds the ChapterTranslation @Model
// (feature #56 bilingual-reading persistent cache). Purely-additive independent
// entity; SwiftData's implicit lightweight migration applies, stages stay empty.
//
// @coordinates-with: SchemaV6.swift, SchemaV7.swift, ChapterTranslation.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-1)

import Testing
import Foundation
import SwiftData
@testable import vreader

@Suite("V6toV7Migration")
struct V6toV7MigrationTests {

    // MARK: - SchemaV7 structure

    @Test func schemaV7VersionIsSevenZeroZero() {
        #expect(SchemaV7.versionIdentifier == Schema.Version(7, 0, 0))
    }

    @Test func schemaV7IsV6PlusChapterTranslationExactly() {
        // Exact set assertion: catches a regression where one V6 model is
        // dropped while ChapterTranslation is added and the count still holds.
        let v7Names = Set(SchemaV7.models.map { String(describing: $0) })
        let expected = Set(SchemaV6.models.map { String(describing: $0) })
            .union(["ChapterTranslation"])
        #expect(v7Names == expected)
    }

    @Test func migrationPlanIncludesV7AtIndex6() {
        // V7 is the 7th schema (index 6). It is no longer the tail — SchemaV8
        // (feature #42) follows it; the tail assertion lives in
        // SchemaV8MigrationTests so this stays stable as new schemas land.
        #expect(VReaderMigrationPlan.schemas.count > 6)
        #expect(String(describing: VReaderMigrationPlan.schemas[6]) == String(describing: SchemaV7.self))
    }

    @Test func migrationPlanLengthIsEight() {
        // V1…V8 — eight schemas (V8 added by feature #42).
        #expect(VReaderMigrationPlan.schemas.count == 8)
    }

    @Test func migrationPlanHasNoExplicitStages() {
        // V6→V7 introduces one new independent @Model with no backfill of
        // existing rows — implicit lightweight migration, no explicit stage.
        #expect(VReaderMigrationPlan.stages.isEmpty)
    }

    // MARK: - ChapterTranslation under V7

    @Test func newChapterTranslationPersistsAndRoundTrips() throws {
        let schema = Schema(SchemaV7.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let profileID = UUID()
        let entry = ChapterTranslation(
            lookupKey: "fp1|epubHref:ch1.xhtml|zh-Hans|\(profileID.uuidString)|v1",
            bookFingerprintKey: "fp1",
            unitStorageKey: "epubHref:ch1.xhtml",
            targetLanguage: "zh-Hans",
            providerProfileID: profileID,
            promptVersion: "v1",
            translatedJSON: #"["你好","世界"]"#,
            sourceParagraphCount: 2
        )
        context.insert(entry)
        try context.save()

        let predicate = #Predicate<ChapterTranslation> { $0.bookFingerprintKey == "fp1" }
        let fetched = try context.fetch(FetchDescriptor<ChapterTranslation>(predicate: predicate)).first
        #expect(fetched != nil)
        #expect(fetched?.unitStorageKey == "epubHref:ch1.xhtml")
        #expect(fetched?.targetLanguage == "zh-Hans")
        #expect(fetched?.providerProfileID == profileID)
        #expect(fetched?.promptVersion == "v1")
        #expect(fetched?.translatedJSON == #"["你好","世界"]"#)
        #expect(fetched?.sourceParagraphCount == 2)
    }

    @Test func providerProfileIDRoundTripsAsUUID() throws {
        let schema = Schema(SchemaV7.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let id = UUID()
        let entry = ChapterTranslation(
            lookupKey: "k-uuid",
            bookFingerprintKey: "fp",
            unitStorageKey: "txtChapterIndex:0",
            targetLanguage: "en",
            providerProfileID: id,
            promptVersion: "v1",
            translatedJSON: "[]",
            sourceParagraphCount: 0
        )
        context.insert(entry)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<ChapterTranslation>()).first
        #expect(fetched?.providerProfileID == id)
    }

    @Test func lookupKeyUniqueConstraintIsHonored() throws {
        // @Attribute(.unique) on lookupKey: inserting a second row with the same
        // key and saving must collapse to one row. This verifies uniqueness only
        // — which payload survives is not asserted here; the idempotent in-place
        // upsert that pins last-writer-wins lands with ChapterTranslationStore (WI-2).
        let schema = Schema(SchemaV7.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        func make(_ json: String) -> ChapterTranslation {
            ChapterTranslation(
                lookupKey: "dup-key",
                bookFingerprintKey: "fp",
                unitStorageKey: "epubHref:x",
                targetLanguage: "zh-Hans",
                providerProfileID: UUID(),
                promptVersion: "v1",
                translatedJSON: json,
                sourceParagraphCount: 1
            )
        }
        context.insert(make(#"["first"]"#))
        try context.save()
        context.insert(make(#"["second"]"#))
        try context.save()

        let predicate = #Predicate<ChapterTranslation> { $0.lookupKey == "dup-key" }
        let rows = try context.fetch(FetchDescriptor<ChapterTranslation>(predicate: predicate))
        #expect(rows.count == 1)
    }

    @Test func migratingExistingV6StoreOpensUnderV7() throws {
        // Open a store at V6, write a Book, close, reopen at V7 — the Book survives
        // and ChapterTranslation is now available (implicit lightweight migration).
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("v6v7-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("store.sqlite")

        let fp = DocumentFingerprint(
            contentSHA256: String(repeating: "d", count: 64),
            fileByteCount: 512,
            format: .epub
        )
        let bookKey: String
        do {
            let v6 = try ModelContainer(
                for: Schema(SchemaV6.models),
                configurations: [ModelConfiguration(url: storeURL)]
            )
            let ctx = ModelContext(v6)
            let book = Book(
                fingerprint: fp,
                title: "Pre-V7",
                provenance: ImportProvenance(source: .filesApp, importedAt: Date(), originalURLBookmarkData: nil)
            )
            ctx.insert(book)
            try ctx.save()
            bookKey = book.fingerprintKey
        }

        let v7 = try ModelContainer(
            for: Schema(SchemaV7.models),
            migrationPlan: VReaderMigrationPlan.self,
            configurations: [ModelConfiguration(url: storeURL)]
        )
        let ctx = ModelContext(v7)
        let books = try ctx.fetch(FetchDescriptor<Book>())
        #expect(books.contains { $0.fingerprintKey == bookKey })

        // ChapterTranslation table exists post-migration.
        let translations = try ctx.fetch(FetchDescriptor<ChapterTranslation>())
        #expect(translations.isEmpty)
    }
}
