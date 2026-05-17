// Purpose: Builds the app's SwiftData `ModelContainer`, deciding whether the
// 6-stage `VReaderMigrationPlan` is actually needed.
//
// Bug #186 / GH #633: `VReaderApp.init()` constructs the container
// synchronously on `@MainActor`. Passing `migrationPlan:` forces SwiftData
// to materialize and validate every schema the plan references (SchemaV1
// through SchemaV6) while building the migration graph — even on a fresh
// install where there is no store to migrate. That wasted main-thread work
// is the multi-second freeze on the first launch after install.
//
// A fresh install (no store file on disk) or an in-memory store has nothing
// to migrate: the store IS the latest schema by construction. Skipping the
// plan in that case removes the wasted SchemaV1–V5 materialization while
// keeping the plan for genuine upgrades of a pre-existing store.
//
// @coordinates-with: VReaderApp.swift, VReaderMigrationPlan.swift

import Foundation
import SwiftData

/// Constructs the SwiftData `ModelContainer`, applying `VReaderMigrationPlan`
/// only when an existing on-disk store actually needs upgrading.
enum ModelContainerFactory {

    /// Whether to apply `VReaderMigrationPlan` when constructing the
    /// container.
    ///
    /// The plan is only meaningful when an existing store must be upgraded.
    /// A fresh install (the store file does not exist yet) or an in-memory
    /// store (whose `url` points at a path that never lands on disk) has
    /// nothing to migrate — applying the plan there is pure wasted
    /// schema-graph materialization on the main thread (Bug #186).
    static func shouldApplyMigrationPlan(
        storeURL: URL?,
        fileManager: FileManager = .default
    ) -> Bool {
        guard let storeURL else { return false }
        return fileManager.fileExists(atPath: storeURL.path)
    }

    /// Builds the `ModelContainer` for `schema`, applying
    /// `VReaderMigrationPlan` only when `configuration`'s store already
    /// exists on disk (see `shouldApplyMigrationPlan`).
    static func makeContainer(
        schema: Schema,
        configuration: ModelConfiguration
    ) throws -> ModelContainer {
        if shouldApplyMigrationPlan(storeURL: configuration.url) {
            return try ModelContainer(
                for: schema,
                migrationPlan: VReaderMigrationPlan.self,
                configurations: [configuration]
            )
        }
        // Fresh install / in-memory store — nothing to migrate, so skip
        // the plan and the SchemaV1–V5 materialization it would force.
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
