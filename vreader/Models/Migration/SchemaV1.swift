// Purpose: Schema version 1 baseline for SwiftData migration support.
// Every schema change requires a new version, migration plan, fixture, and rollback behavior.
//
// == CloudKit + SwiftData Feasibility Spike (WI-1 Task 12-13) ==
//
// FINDINGS:
//
// 1. @Attribute(.unique) and CloudKit:
//    - SwiftData's @Attribute(.unique) works locally but CloudKit does NOT enforce
//      unique constraints server-side. CKRecord field constraints are limited to
//      recordName (the system-assigned ID).
//    - Consequence: Two devices importing the same book could create duplicate records
//      in CloudKit. Deduplication must happen at the application layer.
//
// 2. Custom Codable types as @Attribute(.unique):
//    - SwiftData stores Codable structs as binary/JSON blobs in the underlying store.
//    - @Attribute(.unique) on a Codable struct field does NOT work — SwiftData cannot
//      index or compare opaque blob columns for uniqueness.
//    - SOLUTION: Use primitive key columns (String) derived from the struct.
//      e.g., Book.fingerprintKey = DocumentFingerprint.canonicalKey (a String).
//
// 3. Sync key strategy (implemented):
//    - Book.fingerprintKey: String — "{format}:{sha256}:{byteCount}"
//    - ReadingSession.sessionId: UUID — naturally unique per session
//    - ReadingStats.bookFingerprintKey: String — one stats record per book
//    - Bookmark/Highlight/AnnotationNote.profileKey: String — "{bookKey}:{locatorHash}"
//    - All @Attribute(.unique) constraints use primitive types (String, UUID).
//
// 4. CloudKit record types:
//    - Each @Model class maps to a CKRecord type.
//    - Relationships use CKReference (parent/child).
//    - Cascade delete rules work with CloudKit parent references.
//
// 5. Recommended V2 sync architecture:
//    - Application-layer dedup on fingerprintKey after CloudKit merge.
//    - Last-writer-wins for ReadingPosition (compare updatedAt).
//    - Merge-and-dedup for bookmarks/highlights (compare profileKey).
//    - Session records are append-only (no conflict possible with UUID keys).
//    - Stats are recomputed from sessions (no sync conflict — recompute on merge).
//
// 6. Known limitations:
//    - Cannot test actual CloudKit integration without Xcode.app and provisioning.
//    - CloudKit schema migration is forward-only (no rollback).
//    - Cover images are stored as file paths (coverImagePath) to avoid inline blob
//      pressure. V2 may use CKAsset for syncing cover images across devices.
//
// DECISION: Proceed with primitive key columns as sync keys. This is the standard
// pattern used by Apple's own sample code (e.g., "SyncingDataWithCloudKitAndCoreData").

import Foundation
import SwiftData

/// Schema version 1: baseline schema for vreader.
/// All models defined in this version.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Book.self,
            ReadingPosition.self,
            Bookmark.self,
            Highlight.self,
            AnnotationNote.self,
            ReadingSession.self,
            ReadingStats.self,
        ]
    }
}

/// Migration plan for vreader schema evolution.
/// Currently only V1 exists; future versions will add migration stages.
enum VReaderMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        // No migration stages yet — V1 is the baseline.
        []
    }
}
