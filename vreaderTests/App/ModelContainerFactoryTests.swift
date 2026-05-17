// Purpose: Tests for ModelContainerFactory — the Bug #186 / GH #633
// decision to skip VReaderMigrationPlan on a fresh install.

import Testing
import Foundation
import SwiftData
@testable import vreader

@Suite("ModelContainerFactory")
struct ModelContainerFactoryTests {

    @Test("nil store URL — skip the migration plan (in-memory / no store)")
    func nilStoreURLSkipsPlan() {
        #expect(ModelContainerFactory.shouldApplyMigrationPlan(storeURL: nil) == false)
    }

    @Test("absent store file — skip the migration plan (fresh install)")
    func absentStoreFileSkipsPlan() {
        let absent = FileManager.default.temporaryDirectory
            .appendingPathComponent("vreader-test-\(UUID().uuidString).store")
        #expect(ModelContainerFactory.shouldApplyMigrationPlan(storeURL: absent) == false)
    }

    @Test("existing store file — apply the migration plan (upgrade path)")
    func existingStoreFileAppliesPlan() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vreader-test-\(UUID().uuidString).store")
        try Data("store".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(ModelContainerFactory.shouldApplyMigrationPlan(storeURL: url) == true)
    }

    @Test("makeContainer builds a usable container for an in-memory store")
    func makeContainerInMemoryStore() throws {
        let schema = Schema(SchemaV6.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainerFactory.makeContainer(
            schema: schema, configuration: config
        )
        // The container builds (no migration plan path) and carries the
        // current schema's entities.
        #expect(container.schema.entities.isEmpty == false)
    }
}
