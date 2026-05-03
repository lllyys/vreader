// Purpose: Schema version 5 — adds Book.originalExtension to support feature #46
// (WebDAV materializing restore). Optional String field defaults to nil for legacy
// rows; lightweight migration applies automatically because the field is additive.
//
// @coordinates-with: SchemaV4.swift, Book.swift,
//   dev-docs/plans/20260503-feature-46-materializing-restore.md

import Foundation
import SwiftData

/// Schema version 5: adds Book.originalExtension for backup blob extension preservation.
enum SchemaV5: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)

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
