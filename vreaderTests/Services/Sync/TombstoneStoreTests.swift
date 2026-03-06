// Purpose: Tests for TombstoneStore — add, query, purge, idempotency, entity types.

import Testing
import Foundation
@testable import vreader

@Suite("TombstoneStore")
struct TombstoneStoreTests {

    // MARK: - Add and Query

    @Test func addAndQueryTombstone() {
        var store = InMemoryTombstoneStore()
        let now = SyncTestHelpers.refDate
        store.addTombstone(
            entityType: .bookmark,
            entityId: "bm-001",
            deviceId: SyncTestHelpers.deviceA,
            deletedAt: now
        )
        let result = store.hasTombstone(entityType: .bookmark, entityId: "bm-001")
        #expect(result.exists == true)
        #expect(result.deletedAt == now)
    }

    @Test func queryNonexistentTombstoneReturnsFalse() {
        let store = InMemoryTombstoneStore()
        let result = store.hasTombstone(entityType: .bookmark, entityId: "nonexistent")
        #expect(result.exists == false)
        #expect(result.deletedAt == nil)
    }

    // MARK: - Multiple Entity Types

    @Test func differentEntityTypesAreIndependent() {
        var store = InMemoryTombstoneStore()
        let now = SyncTestHelpers.refDate
        store.addTombstone(entityType: .bookmark, entityId: "id-1", deviceId: "d", deletedAt: now)
        store.addTombstone(entityType: .highlight, entityId: "id-1", deviceId: "d", deletedAt: now)

        #expect(store.hasTombstone(entityType: .bookmark, entityId: "id-1").exists == true)
        #expect(store.hasTombstone(entityType: .highlight, entityId: "id-1").exists == true)
        #expect(store.hasTombstone(entityType: .annotation, entityId: "id-1").exists == false)
    }

    @Test func allEntityTypesSupported() {
        var store = InMemoryTombstoneStore()
        let now = SyncTestHelpers.refDate
        for entityType in TombstoneEntityType.allCases {
            store.addTombstone(entityType: entityType, entityId: "test-\(entityType)", deviceId: "d", deletedAt: now)
        }
        for entityType in TombstoneEntityType.allCases {
            #expect(store.hasTombstone(entityType: entityType, entityId: "test-\(entityType)").exists == true)
        }
    }

    // MARK: - Idempotent Adds

    @Test func idempotentAddKeepsLatestDate() {
        var store = InMemoryTombstoneStore()
        let earlier = SyncTestHelpers.date(offsetBy: -100)
        let later = SyncTestHelpers.date(offsetBy: 100)

        store.addTombstone(entityType: .bookmark, entityId: "bm-1", deviceId: "d", deletedAt: earlier)
        store.addTombstone(entityType: .bookmark, entityId: "bm-1", deviceId: "d", deletedAt: later)

        let result = store.hasTombstone(entityType: .bookmark, entityId: "bm-1")
        #expect(result.exists == true)
        #expect(result.deletedAt == later)
    }

    @Test func idempotentAddDoesNotOverwriteWithOlderDate() {
        var store = InMemoryTombstoneStore()
        let earlier = SyncTestHelpers.date(offsetBy: -100)
        let later = SyncTestHelpers.date(offsetBy: 100)

        store.addTombstone(entityType: .bookmark, entityId: "bm-1", deviceId: "d", deletedAt: later)
        store.addTombstone(entityType: .bookmark, entityId: "bm-1", deviceId: "d", deletedAt: earlier)

        let result = store.hasTombstone(entityType: .bookmark, entityId: "bm-1")
        #expect(result.deletedAt == later)
    }

    // MARK: - Purge

    @Test func purgeRemovesOldTombstones() {
        var store = InMemoryTombstoneStore()
        let thirtyOneDaysAgo = SyncTestHelpers.refDate.addingTimeInterval(-31 * 24 * 3600)
        let fiveDaysAgo = SyncTestHelpers.refDate.addingTimeInterval(-5 * 24 * 3600)

        store.addTombstone(entityType: .bookmark, entityId: "old", deviceId: "d", deletedAt: thirtyOneDaysAgo)
        store.addTombstone(entityType: .bookmark, entityId: "recent", deviceId: "d", deletedAt: fiveDaysAgo)

        let purged = store.purgeTombstones(olderThan: SyncTestHelpers.refDate.addingTimeInterval(-30 * 24 * 3600))
        #expect(purged == 1)
        #expect(store.hasTombstone(entityType: .bookmark, entityId: "old").exists == false)
        #expect(store.hasTombstone(entityType: .bookmark, entityId: "recent").exists == true)
    }

    @Test func purgeReturnsZeroWhenNothingToPurge() {
        var store = InMemoryTombstoneStore()
        let recent = SyncTestHelpers.refDate
        store.addTombstone(entityType: .highlight, entityId: "h1", deviceId: "d", deletedAt: recent)

        let purged = store.purgeTombstones(olderThan: SyncTestHelpers.refDate.addingTimeInterval(-30 * 24 * 3600))
        #expect(purged == 0)
    }

    @Test func purgeOnEmptyStoreReturnsZero() {
        var store = InMemoryTombstoneStore()
        let purged = store.purgeTombstones(olderThan: SyncTestHelpers.refDate)
        #expect(purged == 0)
    }

    @Test func purgeRemovesAcrossEntityTypes() {
        var store = InMemoryTombstoneStore()
        let old = SyncTestHelpers.refDate.addingTimeInterval(-40 * 24 * 3600)
        store.addTombstone(entityType: .bookmark, entityId: "b1", deviceId: "d", deletedAt: old)
        store.addTombstone(entityType: .highlight, entityId: "h1", deviceId: "d", deletedAt: old)
        store.addTombstone(entityType: .annotation, entityId: "a1", deviceId: "d", deletedAt: old)

        let purged = store.purgeTombstones(olderThan: SyncTestHelpers.refDate.addingTimeInterval(-30 * 24 * 3600))
        #expect(purged == 3)
    }

    // MARK: - Count

    @Test func countReturnsTotalTombstones() {
        var store = InMemoryTombstoneStore()
        let now = SyncTestHelpers.refDate
        store.addTombstone(entityType: .bookmark, entityId: "b1", deviceId: "d", deletedAt: now)
        store.addTombstone(entityType: .highlight, entityId: "h1", deviceId: "d", deletedAt: now)
        #expect(store.count == 2)
    }

    @Test func emptyStoreCountIsZero() {
        let store = InMemoryTombstoneStore()
        #expect(store.count == 0)
    }
}
