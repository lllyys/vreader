// Purpose: Schema version 8 — adds an additive optional `vreaderLocatorData:
// Data?` column to ReadingPosition (Feature #42, WI-2), holding the JSON-encoded
// VReaderLocator envelope. The migration is lightweight because the field is a
// purely-additive optional with no backfill of existing rows; SwiftData's
// implicit lightweight migration applies and no explicit MigrationStage is
// required. The model SET is unchanged from V7 (no new @Model entity).
//
// @coordinates-with: SchemaV7.swift, ReadingPosition.swift, VReaderLocator.swift,
//   dev-docs/plans/20260528-feature-42-readium-libmobi-reader-engine.md (WI-2)

import Foundation
import SwiftData

/// Schema version 8: ReadingPosition gains the additive optional
/// `vreaderLocatorData: Data?` column for the engine-agnostic locator envelope.
enum SchemaV8: VersionedSchema {
    static let versionIdentifier = Schema.Version(8, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Book.self,
            ReadingPosition.self,
            Bookmark.self,
            Highlight.self,
            AnnotationNote.self,
            ReadingSession.self,
            ReadingStats.self,
            BookCollection.self,
            BookSource.self,
            ContentReplacementRule.self,
            ChapterTranslation.self,
        ]
    }
}
