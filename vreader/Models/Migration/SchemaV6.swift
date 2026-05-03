// Purpose: Schema version 6 — adds Book.fileState (default "local") and
// Book.blobPath (optional String) to support feature #47 (WebDAV selective
// restore + lazy-on-tap downloads). Both fields are additive with safe
// defaults, so SwiftData's lightweight migration applies automatically;
// no explicit MigrationStage required.
//
// @coordinates-with: SchemaV5.swift, Book.swift, BookFileState.swift,
//   dev-docs/plans/20260503-feature-47-selective-picker-lazy-load.md

import Foundation
import SwiftData

/// Schema version 6: adds Book.fileState + Book.blobPath for selective restore.
enum SchemaV6: VersionedSchema {
    static let versionIdentifier = Schema.Version(6, 0, 0)

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
        ]
    }
}
