// Purpose: Tombstone storage for soft-delete tracking in sync.
// Provides add, query, purge, and count operations.
//
// Key decisions:
// - Protocol-based for testability and future SwiftData-backed implementation.
// - InMemoryTombstoneStore is the V2 implementation (sufficient for current scope).
// - Idempotent adds: re-adding keeps the latest deletedAt.
// - Purge uses a cutoff date; tombstones older than the cutoff are removed.
// - 30-day minimum retention is enforced at the call site, not in the store.
//
// @coordinates-with: SyncTypes.swift, SyncConflictResolver.swift

import Foundation

/// Protocol for tombstone persistence.
protocol TombstonePersisting: Sendable {
    mutating func addTombstone(
        entityType: TombstoneEntityType,
        entityId: String,
        deviceId: String,
        deletedAt: Date
    )
    func hasTombstone(
        entityType: TombstoneEntityType,
        entityId: String
    ) -> (exists: Bool, deletedAt: Date?)
    mutating func purgeTombstones(olderThan cutoff: Date) -> Int
    var count: Int { get }
}

/// Composite key for tombstone lookup.
private struct TombstoneKey: Hashable, Sendable {
    let entityType: TombstoneEntityType
    let entityId: String
}

/// In-memory tombstone store for V2. Suitable for testing and initial sync.
struct InMemoryTombstoneStore: TombstonePersisting, Sendable {

    private var tombstones: [TombstoneKey: Tombstone] = [:]

    var count: Int { tombstones.count }

    /// Adds a tombstone. If one already exists for the same entity, keeps the later date.
    mutating func addTombstone(
        entityType: TombstoneEntityType,
        entityId: String,
        deviceId: String,
        deletedAt: Date
    ) {
        let key = TombstoneKey(entityType: entityType, entityId: entityId)
        if let existing = tombstones[key], existing.deletedAt >= deletedAt {
            return // Keep the later date
        }
        tombstones[key] = Tombstone(
            entityType: entityType,
            entityId: entityId,
            deletedAt: deletedAt,
            deviceId: deviceId
        )
    }

    /// Checks if a tombstone exists for the given entity.
    func hasTombstone(
        entityType: TombstoneEntityType,
        entityId: String
    ) -> (exists: Bool, deletedAt: Date?) {
        let key = TombstoneKey(entityType: entityType, entityId: entityId)
        guard let tombstone = tombstones[key] else {
            return (false, nil)
        }
        return (true, tombstone.deletedAt)
    }

    /// Removes tombstones older than the cutoff date. Returns the count of purged items.
    @discardableResult
    mutating func purgeTombstones(olderThan cutoff: Date) -> Int {
        let keysToPurge = tombstones.filter { $0.value.deletedAt < cutoff }.map(\.key)
        for key in keysToPurge {
            tombstones.removeValue(forKey: key)
        }
        return keysToPurge.count
    }
}
