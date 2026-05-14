// Purpose: Tests for WebDAVServerProfileStore actor (feature #52 WI-1).
// Verifies persistence round-trip, atomic loadSnapshot, active-deleted
// fallback, JSON corruption defense, keychain bridging, mutation
// notifications.

import Testing
import Foundation
@testable import vreader

@Suite("WebDAVServerProfileStore")
struct WebDAVServerProfileStoreTests {

    // MARK: - Helpers

    /// Creates a fresh in-memory UserDefaults suite so each test starts
    /// with empty store state. The suite name embeds a UUID so parallel
    /// tests can't collide.
    private func makeDefaults() -> UserDefaults {
        let suiteName = "WebDAVServerProfileStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeProfile(name: String = "Test") -> WebDAVServerProfile {
        WebDAVServerProfile(
            id: UUID(),
            name: name,
            serverURL: "https://\(name.lowercased()).example.com/dav/",
            username: "user"
        )
    }

    // MARK: - Empty / default state

    @Test func loadAll_emptyOnFreshStore() async {
        let store = WebDAVServerProfileStore(defaults: makeDefaults())
        let profiles = await store.loadAll()
        #expect(profiles.isEmpty)
    }

    @Test func activeProfileID_nilOnFreshStore() async {
        let store = WebDAVServerProfileStore(defaults: makeDefaults())
        let id = await store.activeProfileID()
        #expect(id == nil)
    }

    @Test func activeProfile_nilOnFreshStore() async {
        let store = WebDAVServerProfileStore(defaults: makeDefaults())
        let p = await store.activeProfile()
        #expect(p == nil)
    }

    @Test func loadSnapshot_emptyOnFreshStore() async {
        let store = WebDAVServerProfileStore(defaults: makeDefaults())
        let snap = await store.loadSnapshot()
        #expect(snap.profiles.isEmpty)
        #expect(snap.activeID == nil)
    }

    // MARK: - upsert

    @Test func upsert_appendsNewProfile() async {
        let store = WebDAVServerProfileStore(defaults: makeDefaults())
        let p = makeProfile()
        await store.upsert(p)
        let loaded = await store.loadAll()
        #expect(loaded.count == 1)
        #expect(loaded.first?.id == p.id)
        #expect(loaded.first?.name == "Test")
    }

    @Test func upsert_replacesExistingProfileByID() async {
        let store = WebDAVServerProfileStore(defaults: makeDefaults())
        let original = makeProfile(name: "Original")
        await store.upsert(original)
        var updated = original
        updated.name = "Renamed"
        updated.username = "newuser"
        await store.upsert(updated)
        let loaded = await store.loadAll()
        #expect(loaded.count == 1)
        #expect(loaded.first?.name == "Renamed")
        #expect(loaded.first?.username == "newuser")
    }

    @Test func upsert_preservesOrderWhenAppending() async {
        let store = WebDAVServerProfileStore(defaults: makeDefaults())
        let p1 = makeProfile(name: "First")
        let p2 = makeProfile(name: "Second")
        let p3 = makeProfile(name: "Third")
        await store.upsert(p1)
        await store.upsert(p2)
        await store.upsert(p3)
        let loaded = await store.loadAll()
        #expect(loaded.map(\.name) == ["First", "Second", "Third"])
    }

    @Test func upsert_persistsThroughStoreRecreation() async {
        // UserDefaults is thread-safe but not declared Sendable; mark the
        // local binding `nonisolated(unsafe)` so it can cross into the
        // actor's init twice without Swift 6 strict-concurrency errors.
        nonisolated(unsafe) let defaults = makeDefaults()
        let store1 = WebDAVServerProfileStore(defaults: defaults)
        let p = makeProfile(name: "Persistent")
        await store1.upsert(p)
        // Recreate the store backed by the SAME defaults
        let store2 = WebDAVServerProfileStore(defaults: defaults)
        let loaded = await store2.loadAll()
        #expect(loaded.count == 1)
        #expect(loaded.first?.name == "Persistent")
    }

    // MARK: - remove

    @Test func remove_dropsProfileByID() async {
        let store = WebDAVServerProfileStore(defaults: makeDefaults())
        let p1 = makeProfile(name: "Keep")
        let p2 = makeProfile(name: "Drop")
        await store.upsert(p1)
        await store.upsert(p2)
        await store.remove(id: p2.id)
        let loaded = await store.loadAll()
        #expect(loaded.count == 1)
        #expect(loaded.first?.id == p1.id)
    }

    @Test func remove_unknownIDIsNoOp() async {
        let store = WebDAVServerProfileStore(defaults: makeDefaults())
        let p = makeProfile()
        await store.upsert(p)
        await store.remove(id: UUID())  // unrelated id
        let loaded = await store.loadAll()
        #expect(loaded.count == 1)
    }

    @Test func remove_clearsActiveWhenActiveRemoved() async {
        let store = WebDAVServerProfileStore(defaults: makeDefaults())
        let p1 = makeProfile(name: "P1")
        let p2 = makeProfile(name: "P2")
        await store.upsert(p1)
        await store.upsert(p2)
        await store.setActiveProfileID(p1.id)
        await store.remove(id: p1.id)
        let activeID = await store.activeProfileID()
        #expect(activeID == nil, "Active should be cleared when active profile is removed")
    }

    @Test func remove_keepsActiveWhenOtherRemoved() async {
        let store = WebDAVServerProfileStore(defaults: makeDefaults())
        let p1 = makeProfile(name: "P1")
        let p2 = makeProfile(name: "P2")
        await store.upsert(p1)
        await store.upsert(p2)
        await store.setActiveProfileID(p1.id)
        await store.remove(id: p2.id)
        let activeID = await store.activeProfileID()
        #expect(activeID == p1.id)
    }

    // MARK: - setActiveProfileID

    @Test func setActiveProfileID_setsIDForExistingProfile() async {
        let store = WebDAVServerProfileStore(defaults: makeDefaults())
        let p = makeProfile()
        await store.upsert(p)
        await store.setActiveProfileID(p.id)
        let activeID = await store.activeProfileID()
        #expect(activeID == p.id)
        let active = await store.activeProfile()
        #expect(active?.id == p.id)
    }

    @Test func setActiveProfileID_nilClearsActive() async {
        let store = WebDAVServerProfileStore(defaults: makeDefaults())
        let p = makeProfile()
        await store.upsert(p)
        await store.setActiveProfileID(p.id)
        await store.setActiveProfileID(nil)
        let activeID = await store.activeProfileID()
        #expect(activeID == nil)
    }

    @Test func setActiveProfileID_unknownIDIsRecordedButDoesNotResolve() async {
        let store = WebDAVServerProfileStore(defaults: makeDefaults())
        let unknownID = UUID()
        await store.setActiveProfileID(unknownID)
        let recorded = await store.activeProfileID()
        #expect(recorded == unknownID)
        let resolved = await store.activeProfile()
        #expect(resolved == nil, "activeProfile() must return nil for an id that doesn't match any saved profile")
    }

    // MARK: - loadSnapshot atomicity

    @Test func loadSnapshot_returnsBothFieldsTogether() async {
        let store = WebDAVServerProfileStore(defaults: makeDefaults())
        let p1 = makeProfile(name: "P1")
        let p2 = makeProfile(name: "P2")
        await store.upsert(p1)
        await store.upsert(p2)
        await store.setActiveProfileID(p2.id)
        let snap = await store.loadSnapshot()
        #expect(snap.profiles.count == 2)
        #expect(snap.activeID == p2.id)
    }

    // MARK: - JSON corruption defense (Gate 2 audit finding #1)

    @Test func loadAll_returnsEmptyOnCorruptJSON() async {
        let defaults = makeDefaults()
        // Write a non-JSON-decodable Data blob under the profiles key
        defaults.set("not valid json".data(using: .utf8), forKey: WebDAVServerProfileStore.profilesKey)
        let store = WebDAVServerProfileStore(defaults: defaults)
        let loaded = await store.loadAll()
        #expect(loaded.isEmpty, "Corrupt JSON should yield empty list, not crash")
    }

    @Test func activeProfileID_returnsNilOnInvalidUUIDString() async {
        let defaults = makeDefaults()
        defaults.set("not a uuid", forKey: WebDAVServerProfileStore.activeProfileIDKey)
        let store = WebDAVServerProfileStore(defaults: defaults)
        let id = await store.activeProfileID()
        #expect(id == nil)
    }

    // MARK: - Notification

    @Test func upsert_postsDidChangeNotification() async {
        let store = WebDAVServerProfileStore(defaults: makeDefaults())
        let received = NotificationExpectation(name: .webdavProfilesDidChange)
        await store.upsert(makeProfile())
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(received.fired)
    }

    @Test func remove_postsDidChangeNotification() async {
        let store = WebDAVServerProfileStore(defaults: makeDefaults())
        let p = makeProfile()
        await store.upsert(p)
        let received = NotificationExpectation(name: .webdavProfilesDidChange)
        await store.remove(id: p.id)
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(received.fired)
    }

    @Test func setActiveProfileID_postsDidChangeNotification() async {
        let store = WebDAVServerProfileStore(defaults: makeDefaults())
        let p = makeProfile()
        await store.upsert(p)
        let received = NotificationExpectation(name: .webdavProfilesDidChange)
        await store.setActiveProfileID(p.id)
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(received.fired)
    }
}

// MARK: - Notification fire detector

/// One-shot notification observer; sets `fired` to true after the first
/// post. Auto-removes its observer in `deinit`. Each test creates a
/// fresh instance so prior test state can't leak.
private final class NotificationExpectation: @unchecked Sendable {
    private(set) var fired: Bool = false
    private var token: NSObjectProtocol?

    init(name: Notification.Name) {
        token = NotificationCenter.default.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.fired = true
        }
    }

    deinit {
        if let token { NotificationCenter.default.removeObserver(token) }
    }
}
