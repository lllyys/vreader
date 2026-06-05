// Purpose: Tests for SchemaV8 migration — adds an additive optional
// `vreaderLocatorData: Data?` column to ReadingPosition (Feature #42, WI-2)
// holding the JSON-encoded VReaderLocator envelope. Stored as raw Data? to
// mirror Highlight.anchorData's SwiftData-safe precedent. Purely-additive
// optional field; SwiftData's implicit lightweight migration applies and
// the explicit stages list stays empty.
//
// @coordinates-with: SchemaV7.swift, SchemaV8.swift, ReadingPosition.swift,
//   VReaderLocator.swift, dev-docs/plans/20260528-feature-42-readium-libmobi-reader-engine.md (WI-2)

import Testing
import Foundation
import SwiftData
@testable import vreader

@Suite("SchemaV8Migration")
struct SchemaV8MigrationTests {

    // MARK: - SchemaV8 structure

    @Test func schemaV8VersionIsEightZeroZero() {
        #expect(SchemaV8.versionIdentifier == Schema.Version(8, 0, 0))
    }

    @Test func schemaV8HasSameModelSetAsV7() {
        // SchemaV8 is purely an additive-field change on ReadingPosition; the
        // model SET is unchanged from V7 (no new @Model entity).
        let v8Names = Set(SchemaV8.models.map { String(describing: $0) })
        let v7Names = Set(SchemaV7.models.map { String(describing: $0) })
        #expect(v8Names == v7Names)
    }

    @Test func migrationPlanIncludesV8BeforeV9() {
        // V8 is no longer the tail (SchemaV9 was appended by Feature #88 WI-1);
        // V8's stable invariant is that it is present and ordered before V9.
        let names = VReaderMigrationPlan.schemas.map { String(describing: $0) }
        let v8Index = names.firstIndex(of: String(describing: SchemaV8.self))
        let v9Index = names.firstIndex(of: String(describing: SchemaV9.self))
        let v8 = try! #require(v8Index)
        let v9 = try! #require(v9Index)
        #expect(v8 < v9)
    }

    @Test func migrationPlanContainsV8() {
        let names = VReaderMigrationPlan.schemas.map { String(describing: $0) }
        #expect(names.contains(String(describing: SchemaV8.self)))
    }

    @Test func migrationPlanHasNoExplicitStages() {
        // V7→V8 adds one optional Data? field — implicit lightweight migration,
        // no explicit stage required.
        #expect(VReaderMigrationPlan.stages.isEmpty)
    }

    // MARK: - V7 row survives migration to V8, new field defaults nil

    @Test func migratingExistingV7StoreOpensUnderV8AndPreservesLocator() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("v7v8-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("store.sqlite")

        let fp = DocumentFingerprint(
            contentSHA256: String(repeating: "e", count: 64),
            fileByteCount: 2048,
            format: .epub
        )
        let originalLocator = Locator(
            bookFingerprint: fp, href: "ch3.xhtml",
            progression: 0.33, totalProgression: 0.5,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let originalHash = originalLocator.canonicalHash

        // Write a ReadingPosition under V7.
        do {
            let v7 = try ModelContainer(
                for: Schema(SchemaV7.models),
                configurations: [ModelConfiguration(url: storeURL)]
            )
            let ctx = ModelContext(v7)
            let position = ReadingPosition(locator: originalLocator, deviceId: "dev-1")
            ctx.insert(position)
            try ctx.save()
        }

        // Reopen under V8 with the migration plan.
        let v8 = try ModelContainer(
            for: Schema(SchemaV8.models),
            migrationPlan: VReaderMigrationPlan.self,
            configurations: [ModelConfiguration(url: storeURL)]
        )
        let ctx = ModelContext(v8)
        let positions = try ctx.fetch(FetchDescriptor<ReadingPosition>())
        #expect(positions.count == 1)
        let migrated = try #require(positions.first)
        // Original locator survived intact.
        #expect(migrated.locator.canonicalHash == originalHash)
        #expect(migrated.locator.href == "ch3.xhtml")
        #expect(migrated.deviceId == "dev-1")
        // New additive field defaults to nil for migrated rows.
        #expect(migrated.vreaderLocatorData == nil)
    }

    // MARK: - V8 row can store + read back a VReaderLocator envelope

    @Test func v8ReadingPositionStoresAndReadsBackVReaderLocator() throws {
        let schema = Schema(SchemaV8.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let fp = DocumentFingerprint(
            contentSHA256: String(repeating: "f", count: 64),
            fileByteCount: 4096,
            format: .epub
        )
        let legacy = Locator(
            bookFingerprint: fp, href: "ch1.xhtml",
            progression: 0.1, totalProgression: nil,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let envelope = VReaderLocator(
            fingerprintKey: fp.canonicalKey, originalFormat: .epub,
            engine: .readium,
            readiumLocatorJSON: #"{"href":"ch1.xhtml","locations":{"progression":0.1}}"#,
            legacyLocator: legacy, schemaVersion: 1
        )

        let position = ReadingPosition(locator: legacy, deviceId: "dev-2")
        position.vreaderLocatorData = try JSONEncoder().encode(envelope)
        context.insert(position)
        try context.save()

        let fetched = try #require(
            try context.fetch(FetchDescriptor<ReadingPosition>()).first
        )
        let data = try #require(fetched.vreaderLocatorData)
        let decoded = try JSONDecoder().decode(VReaderLocator.self, from: data)
        #expect(decoded == envelope)
        // Legacy locator still independently readable.
        #expect(fetched.locator.href == "ch1.xhtml")
    }

    @Test func v8ReadingPositionDefaultsVReaderLocatorDataToNil() throws {
        let schema = Schema(SchemaV8.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let fp = DocumentFingerprint(
            contentSHA256: String(repeating: "0", count: 64),
            fileByteCount: 10, format: .pdf
        )
        let locator = Locator(
            bookFingerprint: fp, href: nil, progression: nil, totalProgression: nil,
            cfi: nil, page: 3,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let position = ReadingPosition(locator: locator)
        context.insert(position)
        try context.save()

        let fetched = try #require(
            try context.fetch(FetchDescriptor<ReadingPosition>()).first
        )
        #expect(fetched.vreaderLocatorData == nil)
    }
}
