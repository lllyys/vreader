// Purpose: Schema version 10 — adds the additive optional `sourceCanonicalKey:
// String?` column to `Book` (feature #108), holding the cross-platform canonical
// identity for converted-Kindle books (SHA-256 of the SOURCE `.azw3`/`.mobi`/
// `.prc` bytes). The migration is LIGHTWEIGHT: a purely-additive optional with
// no backfill of existing rows (their source bytes were discarded → nil), so
// SwiftData's implicit lightweight migration applies and no explicit
// MigrationStage is required. The model SET is unchanged from V9.
//
// NOTE: this is a *real* SchemaV10 (a genuine entity-shape change, so the
// lightweight migration fires). It is unrelated to feature #109's earlier,
// since-removed shape-identical SchemaV10 — that one never fired precisely
// because it changed no shape, which is why #109 shipped a launch backfill
// instead.
//
// @coordinates-with: SchemaV9.swift, Book.swift (sourceCanonicalKey),
//   SchemaV1.swift (VReaderMigrationPlan registration),
//   contracts/identity/DECISION.md,
//   dev-docs/plans/20260618-feature-108-kindle-source-bytes-identity.md

import Foundation
import SwiftData

/// Schema version 10: `Book` gains the additive optional `sourceCanonicalKey:
/// String?` column for the converted-Kindle cross-platform identity (feature #108).
enum SchemaV10: VersionedSchema {
    static let versionIdentifier = Schema.Version(10, 0, 0)

    static var models: [any PersistentModel.Type] {
        SchemaV9.models
    }
}
