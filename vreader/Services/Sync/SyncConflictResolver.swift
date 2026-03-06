// Purpose: Pure-function conflict resolution for all synced entity types.
// Implements the merge algorithms from plan Section 9.4.
//
// Key decisions:
// - Struct-based, no side effects — easily testable and Sendable.
// - Uses lightweight record types (not SwiftData models) for sync resolution.
// - ReadingPosition: LWW by updatedAt, lexicographic deviceId tie-break.
// - Bookmark: tombstone-aware LWW, keep earliest createdAt.
// - Highlight: field-level merge with tombstones; newest updatedAt wins per field set.
// - AnnotationNote: LWW with tombstone precedence when newer.
// - LibraryMetadata: user-edited wins over extracted; newest user edit wins.
// - FileManifest: monotonic version; checksum mismatch forces stale.
// - ReadingSession: append-only, idempotent insert on duplicates.
//
// @coordinates-with: SyncTypes.swift, SyncService.swift

import Foundation

// MARK: - Sync Record Types (lightweight, not SwiftData)

/// Lightweight record for position conflict resolution.
struct SyncPositionRecord: Sendable, Equatable {
    let locatorHash: String
    let updatedAt: Date
    let deviceId: String
}

/// Lightweight record for bookmark conflict resolution.
struct SyncBookmarkRecord: Sendable, Equatable {
    let bookmarkId: String
    let updatedAt: Date
    let isDeleted: Bool
    let createdAt: Date
}

/// Result of a bookmark merge including the merged createdAt.
struct SyncBookmarkMergeResult: Sendable, Equatable {
    let winner: SyncConflictResult
    let mergedCreatedAt: Date
}

/// Lightweight record for highlight conflict resolution.
struct SyncHighlightRecord: Sendable, Equatable {
    let highlightId: String
    let updatedAt: Date
    let isDeleted: Bool
    let selectedText: String
    let color: String
    let note: String?
}

/// Result of a highlight merge.
struct SyncHighlightMergeResult: Sendable, Equatable {
    let winner: SyncConflictResult
}

/// Lightweight record for annotation conflict resolution.
struct SyncAnnotationRecord: Sendable, Equatable {
    let annotationId: String
    let updatedAt: Date
    let isDeleted: Bool
    let content: String
}

/// Lightweight record for library metadata conflict resolution.
struct SyncLibraryMetadataRecord: Sendable, Equatable {
    let bookFingerprintKey: String
    let title: String
    let author: String?
    let isUserEdited: Bool
    let updatedAt: Date
}

/// Lightweight record for file manifest conflict resolution.
struct SyncFileManifestRecord: Sendable, Equatable {
    let bookFingerprintKey: String
    let manifestVersion: Int
    let checksum: String
}

/// Result of a file manifest merge.
struct SyncFileManifestMergeResult: Sendable, Equatable {
    let winner: SyncConflictResult
    let requiresStale: Bool
}

// MARK: - Resolver

/// Pure-function conflict resolver for all synced entity types.
struct SyncConflictResolver: Sendable {

    // MARK: - ReadingPosition

    /// LWW by updatedAt. Tie-breaker: lexicographically larger deviceId wins.
    func resolvePosition(
        local: SyncPositionRecord,
        remote: SyncPositionRecord
    ) -> SyncConflictResult {
        if local.updatedAt > remote.updatedAt { return .useLocal }
        if remote.updatedAt > local.updatedAt { return .useRemote }
        // Tie: lexicographic deviceId, larger wins
        return local.deviceId >= remote.deviceId ? .useLocal : .useRemote
    }

    // MARK: - Bookmark

    /// Tombstone-aware LWW. Keeps earliest createdAt from either side.
    func resolveBookmark(
        local: SyncBookmarkRecord,
        remote: SyncBookmarkRecord
    ) -> SyncBookmarkMergeResult {
        let mergedCreatedAt = min(local.createdAt, remote.createdAt)
        let winner = resolveTombstoneAwareLWW(
            localUpdatedAt: local.updatedAt, localIsDeleted: local.isDeleted,
            remoteUpdatedAt: remote.updatedAt, remoteIsDeleted: remote.isDeleted
        )
        return SyncBookmarkMergeResult(winner: winner, mergedCreatedAt: mergedCreatedAt)
    }

    // MARK: - Highlight

    /// Field-level merge with tombstones. Newer updatedAt wins for the full field set.
    func resolveHighlight(
        local: SyncHighlightRecord,
        remote: SyncHighlightRecord
    ) -> SyncHighlightMergeResult {
        let winner = resolveTombstoneAwareLWW(
            localUpdatedAt: local.updatedAt, localIsDeleted: local.isDeleted,
            remoteUpdatedAt: remote.updatedAt, remoteIsDeleted: remote.isDeleted
        )
        return SyncHighlightMergeResult(winner: winner)
    }

    // MARK: - Annotation

    /// LWW with tombstone precedence when newer.
    func resolveAnnotation(
        local: SyncAnnotationRecord,
        remote: SyncAnnotationRecord
    ) -> SyncConflictResult {
        resolveTombstoneAwareLWW(
            localUpdatedAt: local.updatedAt, localIsDeleted: local.isDeleted,
            remoteUpdatedAt: remote.updatedAt, remoteIsDeleted: remote.isDeleted
        )
    }

    // MARK: - LibraryMetadata

    /// User-edited wins over extracted. Among same type, newer wins.
    func resolveLibraryMetadata(
        local: SyncLibraryMetadataRecord,
        remote: SyncLibraryMetadataRecord
    ) -> SyncConflictResult {
        // User edit always wins over extracted
        if local.isUserEdited && !remote.isUserEdited { return .useLocal }
        if remote.isUserEdited && !local.isUserEdited { return .useRemote }
        // Both same type: newer wins
        if local.updatedAt >= remote.updatedAt { return .useLocal }
        return .useRemote
    }

    // MARK: - FileManifest

    /// Monotonic version. Higher version wins. Checksum mismatch at same version forces stale.
    func resolveFileManifest(
        local: SyncFileManifestRecord,
        remote: SyncFileManifestRecord
    ) -> SyncFileManifestMergeResult {
        if remote.manifestVersion > local.manifestVersion {
            return SyncFileManifestMergeResult(winner: .useRemote, requiresStale: false)
        }
        if local.manifestVersion > remote.manifestVersion {
            return SyncFileManifestMergeResult(winner: .useLocal, requiresStale: false)
        }
        // Same version: check checksums
        if local.checksum != remote.checksum {
            return SyncFileManifestMergeResult(winner: .useLocal, requiresStale: true)
        }
        return SyncFileManifestMergeResult(winner: .useLocal, requiresStale: false)
    }

    // MARK: - ReadingSession

    /// Append-only: skip if session ID already exists locally.
    func resolveSession(
        localSessionIds: Set<String>,
        remoteSessionId: String
    ) -> SyncSessionResult {
        localSessionIds.contains(remoteSessionId) ? .skip : .append
    }

    // MARK: - Private: Tombstone-Aware LWW

    /// Shared tombstone-aware LWW logic.
    /// If timestamps are equal and one is tombstoned, tombstone wins (delete bias).
    private func resolveTombstoneAwareLWW(
        localUpdatedAt: Date, localIsDeleted: Bool,
        remoteUpdatedAt: Date, remoteIsDeleted: Bool
    ) -> SyncConflictResult {
        if localUpdatedAt > remoteUpdatedAt { return .useLocal }
        if remoteUpdatedAt > localUpdatedAt { return .useRemote }
        // Equal timestamps: tombstone wins (delete bias)
        if remoteIsDeleted && !localIsDeleted { return .useRemote }
        if localIsDeleted && !remoteIsDeleted { return .useLocal }
        // Both same state: local wins
        return .useLocal
    }
}
