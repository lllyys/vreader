// Purpose: Schema version 7 — adds the ChapterTranslation @Model (feature #56
// bilingual-reading persistent translation cache). The migration is lightweight
// because it introduces a brand-new independent entity with no backfill of
// existing rows; SwiftData's implicit lightweight migration applies and no
// explicit MigrationStage is required.
//
// @coordinates-with: SchemaV6.swift, ChapterTranslation.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-1)

import Foundation
import SwiftData

/// Schema version 7: adds ChapterTranslation for the bilingual-reading cache.
enum SchemaV7: VersionedSchema {
    static let versionIdentifier = Schema.Version(7, 0, 0)

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
