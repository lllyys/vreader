// Purpose: Core types for the sync subsystem — file availability states,
// conflict resolution outcomes, tombstone tracking, file manifests, and errors.
//
// Key decisions:
// - All types are Sendable for safe cross-actor transfer.
// - FileAvailability models the 6-state machine from the sync plan (Section 4.3).
// - SyncConflictResult is a simple enum for binary resolution outcomes.
// - Tombstone tracks soft-delete metadata for eventual purge.
// - FileManifest is a plain struct (SwiftData backing deferred to V3).
// - SyncError covers all expected failure modes.
//
// @coordinates-with: SyncConflictResolver.swift, FileAvailabilityStateMachine.swift, SyncService.swift

import Foundation

// MARK: - File Availability

/// States for file availability on the current device.
/// See plan Section 4.3 for the full state machine.
enum FileAvailability: String, Sendable, Codable, Equatable {
    case metadataOnly
    case queuedDownload
    case downloading
    case available
    case failed
    case stale
}

/// Events that drive file availability state transitions.
enum FileAvailabilityEvent: Sendable, Equatable {
    case userOpen
    case autoDownload
    case schedulerStart
    case downloadComplete(checksumValid: Bool)
    case downloadFailed
    case corruptionDetected
    case retry
}

// MARK: - Conflict Resolution

/// Outcome of a two-way sync conflict resolution.
enum SyncConflictResult: Sendable, Equatable {
    case useLocal
    case useRemote
}

/// Outcome of a session merge operation.
enum SyncSessionResult: Sendable, Equatable {
    case append
    case skip
}

// MARK: - Sync Operation Results

/// Result of a sync operation, including feature-flag guard state.
enum SyncOperationResult: Sendable, Equatable {
    case disabled
    case success
    case queued
    case error(String)
}

// MARK: - Sync Status

/// Current state of the sync subsystem.
enum SyncStatus: Sendable, Equatable {
    case disabled
    case idle
    case syncing
    case error(String)
    case offline
}

// MARK: - Tombstone

/// Entity types that support soft-delete tombstones.
enum TombstoneEntityType: String, Sendable, CaseIterable {
    case bookmark
    case highlight
    case annotation
}

/// A soft-delete tombstone for eventual purge.
struct Tombstone: Sendable, Equatable {
    let entityType: TombstoneEntityType
    let entityId: String
    let deletedAt: Date
    let deviceId: String
}

// MARK: - File Manifest

/// Tracks file identity and version for sync. Plain struct; SwiftData backing deferred.
struct FileManifest: Sendable, Equatable, Codable {
    let bookFingerprintKey: String
    let manifestVersion: Int
    let checksum: String
    let fileURL: URL?
    let fileSize: Int64?
}

// MARK: - Sync Error

/// Errors specific to the sync subsystem.
enum SyncError: Error, Sendable, Equatable {
    case syncDisabled
    case networkUnavailable
    case authenticationFailed
    case quotaExceeded
    case checksumMismatch
    case mergeConflict(String)
    case unknown(String)
}
