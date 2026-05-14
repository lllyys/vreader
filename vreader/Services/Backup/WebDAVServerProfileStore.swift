// Purpose: Actor-isolated storage for the list of saved WebDAV server
// profiles, with one active selection. Feature #52 WI-1.
//
// Why an actor:
//   UserDefaults exposes atomic key-level reads/writes but NOT atomic
//   load-modify-save. Cross-actor writers (settings UI + backup factory
//   resolution) could lose updates if the store were a plain struct.
//   Actor isolation gives us atomic upsert/remove/setActiveProfileID
//   without locks. Cost: every read becomes async.
//
// Shared-instance contract:
//   `.shared` is the production singleton.
//   `WebDAVProviderFactory.make(...)` (in WI-3), settings UI (in WI-4a/4b),
//   and the future backup-now path all read from `.shared`. Tests inject
//   a separate test-container instance via `init(defaults:keychain:)`.
//   Multiple stores backed by the same UserDefaults would re-introduce
//   lost updates.
//
// Snapshot semantics:
//   `loadSnapshot()` returns `(profiles, activeID)` atomically in a single
//   actor hop. UI consumers MUST use this instead of pairing `loadAll()` +
//   `activeProfileID`, otherwise a concurrent mutation between the two
//   awaits can publish a list that doesn't agree with the active id.
//
// JSON corruption defense (Gate 2 audit finding #1):
//   `readProfiles` uses `try?` and falls back to empty list with a logged
//   warning if the persisted JSON is malformed. Prevents the actor from
//   crashing the app on a corrupt UserDefaults value (extremely unlikely
//   but defensible — same posture as `ProviderProfileMigrator`).
//
// Migration:
//   WI-1 handles fresh-install and JSON-corruption cases. Migration from
//   the legacy flat-keychain credentials (`com.vreader.webdav.serverURL/
//   username/password`) lands in WI-2 (`WebDAVProfileMigrator`). This
//   actor stays unaware of legacy keys.
//
// @coordinates-with: WebDAVServerProfile.swift, WebDAVProviderFactory.swift,
//   WebDAVProfileMigrator.swift (WI-2), KeychainService.swift

import Foundation
import os

/// Actor-isolated list-with-active-selection of WebDAV server profiles.
actor WebDAVServerProfileStore {

    /// App-scoped production singleton. All production callers MUST use
    /// this exact instance — otherwise the actor isolation guarantee
    /// doesn't hold.
    static let shared = WebDAVServerProfileStore()

    /// UserDefaults key for the list of saved profiles (JSON-encoded array).
    static let profilesKey = "com.vreader.webdav.profiles"
    /// UserDefaults key for the active profile's UUID (hyphenated string).
    static let activeProfileIDKey = "com.vreader.webdav.activeProfileID"

    private let defaults: UserDefaults
    private let keychain: KeychainService

    /// Logger declared `nonisolated` so error paths can write without
    /// crossing the actor boundary.
    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "vreader",
        category: "WebDAVProfileStore"
    )

    /// Test-injectable init. Production callers MUST use `.shared`.
    init(
        defaults: UserDefaults = .standard,
        keychain: KeychainService = KeychainService()
    ) {
        self.defaults = defaults
        self.keychain = keychain
    }

    // MARK: - Public API (all async because actor)

    /// Returns the current list of saved profiles. Empty when the store
    /// has never been written or the persisted JSON is corrupt.
    func loadAll() -> [WebDAVServerProfile] {
        Self.readProfiles(defaults: defaults)
    }

    /// Returns the id of the active profile, if set. May refer to a
    /// profile that no longer exists in the list — callers that need
    /// resolution should use `activeProfile()` or `loadSnapshot()`.
    func activeProfileID() -> UUID? {
        Self.readActiveID(defaults: defaults)
    }

    /// Returns the currently active profile (resolved by id), or nil if
    /// no active id is set or it doesn't resolve to a known profile.
    func activeProfile() -> WebDAVServerProfile? {
        guard let id = Self.readActiveID(defaults: defaults) else { return nil }
        let profiles = Self.readProfiles(defaults: defaults)
        return profiles.first(where: { $0.id == id })
    }

    /// Atomic snapshot of the full list + active id, taken in a single
    /// actor hop. Callers that read list state for UI rendering MUST use
    /// this instead of pairing `loadAll()` + `activeProfileID()`,
    /// otherwise a concurrent mutation between the two awaits can publish
    /// a list that doesn't agree with the active id.
    func loadSnapshot() -> (profiles: [WebDAVServerProfile], activeID: UUID?) {
        let profiles = Self.readProfiles(defaults: defaults)
        let activeID = Self.readActiveID(defaults: defaults)
        return (profiles, activeID)
    }

    /// Inserts a new profile or replaces an existing one with the same id.
    func upsert(_ profile: WebDAVServerProfile) {
        var profiles = Self.readProfiles(defaults: defaults)
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        } else {
            profiles.append(profile)
        }
        Self.writeProfiles(profiles, defaults: defaults)
        Self.postDidChangeNotification()
    }

    /// Replace an existing profile by id IF AND ONLY IF the profile is
    /// currently in the store. Single-hop alternative to "loadAll →
    /// upsert" which would race against concurrent deletes (Feature #52
    /// WI-4b Codex round-2 Medium fix). Returns true if the replacement
    /// happened, false if no matching id was found (caller surfaces a
    /// stale-edit error to the user). No-op + no notification when the
    /// id is unknown.
    func updateIfExists(_ profile: WebDAVServerProfile) -> Bool {
        var profiles = Self.readProfiles(defaults: defaults)
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else {
            return false
        }
        profiles[idx] = profile
        Self.writeProfiles(profiles, defaults: defaults)
        Self.postDidChangeNotification()
        return true
    }

    /// Removes the profile with the given id. Also deletes its keychain
    /// password entry. If the removed profile was the active one, clears
    /// active (UI surfaces the "no active" case explicitly).
    func remove(id: UUID) {
        var profiles = Self.readProfiles(defaults: defaults)
        profiles.removeAll(where: { $0.id == id })
        Self.writeProfiles(profiles, defaults: defaults)
        let currentActive = Self.readActiveID(defaults: defaults)
        if currentActive == id {
            Self.writeActiveID(nil, defaults: defaults)
        }
        // Best-effort keychain cleanup. Failures are logged but not surfaced
        // — the profile is gone from the list regardless, so the orphaned
        // keychain entry (if any) is just dead weight, not a correctness
        // issue.
        try? keychain.delete(forAccount: WebDAVServerProfile.keychainPasswordAccount(for: id))
        Self.postDidChangeNotification()
    }

    /// Sets the active profile by id. Passing nil clears active.
    /// Setting an unknown id is allowed but `activeProfile()` will return
    /// nil for it (the id is recorded but doesn't resolve).
    func setActiveProfileID(_ id: UUID?) {
        Self.writeActiveID(id, defaults: defaults)
        Self.postDidChangeNotification()
    }

    // MARK: - Keychain bridging

    /// Writes the password for a given profile id to Keychain at the
    /// profile's account string. Posts `webdavProfilesDidChange` on
    /// success so observers (e.g., `WebDAVSettingsView`'s backup section)
    /// refresh — WI-5 Codex round-2 fix: previously password-only
    /// changes left the backup section stale until the next profile-
    /// list mutation re-fired the notification.
    func writePassword(_ password: String, for id: UUID) throws {
        try keychain.saveString(
            password,
            forAccount: WebDAVServerProfile.keychainPasswordAccount(for: id)
        )
        Self.postDidChangeNotification()
    }

    /// Reads the password for a given profile id from Keychain.
    /// Returns nil if no entry exists for the profile.
    func readPassword(for id: UUID) throws -> String? {
        try keychain.readString(
            forAccount: WebDAVServerProfile.keychainPasswordAccount(for: id)
        )
    }

    /// Deletes the password keychain entry for a given profile id. No-op
    /// if the entry doesn't exist (KeychainService.delete tolerates miss).
    /// Posts `webdavProfilesDidChange` on success — same rationale as
    /// `writePassword` (WI-5 Codex round-2 fix).
    func deletePassword(for id: UUID) throws {
        try keychain.delete(
            forAccount: WebDAVServerProfile.keychainPasswordAccount(for: id)
        )
        Self.postDidChangeNotification()
    }

    // MARK: - Notification

    /// Posted on every mutation (upsert / remove / setActiveProfileID).
    /// Future UI consumers (`WebDAVServerProfileListView` in WI-4a) observe
    /// this to resync while presented. Mirrors `providerProfilesDidChange`
    /// from Feature #50.
    nonisolated private static func postDidChangeNotification() {
        NotificationCenter.default.post(name: .webdavProfilesDidChange, object: nil)
    }

    // MARK: - Static read/write helpers

    /// Reads the persisted profile list. Returns empty array on missing or
    /// corrupt data. Logged warning on corruption (Gate 2 audit finding #1).
    nonisolated static func readProfiles(defaults: UserDefaults) -> [WebDAVServerProfile] {
        guard let data = defaults.data(forKey: profilesKey) else { return [] }
        do {
            return try JSONDecoder().decode([WebDAVServerProfile].self, from: data)
        } catch {
            logger.warning(
                "WebDAV profiles JSON decode failed; falling back to empty list. Error: \(String(describing: error), privacy: .public)"
            )
            return []
        }
    }

    /// Reads the persisted active profile id. Returns nil on missing
    /// or malformed UUID string.
    nonisolated static func readActiveID(defaults: UserDefaults) -> UUID? {
        guard let raw = defaults.string(forKey: activeProfileIDKey) else { return nil }
        return UUID(uuidString: raw)
    }

    /// Persists the profile list. Falls back to clearing the key on
    /// JSON encode failure (which Foundation never throws for `[Codable]`
    /// arrays of value types — defensive only).
    nonisolated static func writeProfiles(
        _ profiles: [WebDAVServerProfile],
        defaults: UserDefaults
    ) {
        do {
            let data = try JSONEncoder().encode(profiles)
            defaults.set(data, forKey: profilesKey)
        } catch {
            logger.error(
                "WebDAV profiles JSON encode failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// Persists the active profile id. Passing nil clears the key.
    nonisolated static func writeActiveID(_ id: UUID?, defaults: UserDefaults) {
        if let id {
            defaults.set(id.uuidString, forKey: activeProfileIDKey)
        } else {
            defaults.removeObject(forKey: activeProfileIDKey)
        }
    }
}

extension Notification.Name {
    /// Posted by `WebDAVServerProfileStore` after every successful mutation
    /// (`upsert`, `remove`, `setActiveProfileID`). Future UI consumers
    /// (WebDAV settings list in WI-4a) observe this to keep visible state
    /// in sync. No userInfo — observers should call `loadSnapshot()` to
    /// read the current state. Mirrors `providerProfilesDidChange` from
    /// Feature #50.
    static let webdavProfilesDidChange = Notification.Name("com.vreader.webdav.profilesDidChange")
}
