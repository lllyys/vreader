// Purpose: Schema version 9 — adds the additive `ChatSession` @Model entity plus
// the new to-many `Book.chatSessions` cascade relationship (Feature #88, WI-1).
// The migration is lightweight because it is purely additive (a new entity + a
// new to-many relationship, no field changes to existing models); SwiftData's
// implicit lightweight migration applies and no explicit MigrationStage is
// required. The model SET is V8's set plus `ChatSession`.
//
// @coordinates-with: SchemaV8.swift, ChatSession.swift, Book.swift,
//   dev-docs/plans/20260605-feature-88-conversation-sessions.md (WI-1)

import Foundation
import SwiftData

/// Schema version 9: adds the additive `ChatSession` entity for multiple
/// switchable, persisted AI conversations per book.
enum SchemaV9: VersionedSchema {
    static let versionIdentifier = Schema.Version(9, 0, 0)

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
            ChatSession.self,
        ]
    }
}
