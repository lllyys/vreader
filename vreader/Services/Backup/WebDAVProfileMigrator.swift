// Purpose: One-shot migration from legacy flat-keychain WebDAV credentials
// (`com.vreader.webdav.serverURL/username/password`) to the new
// `WebDAVServerProfileStore` (list of profiles + active selector).
// Feature #52 WI-2.
//
// Why this exists:
//   Before Feature #52, the app supported exactly one WebDAV server.
//   Server URL, username, and password lived in three flat Keychain
//   entries that `WebDAVProviderFactory.make(...)` read directly.
//   Feature #52 replaces that single-server contract with a list + active
//   selector; this migrator turns the legacy single entry into one
//   `WebDAVServerProfile` named "Default", copies the password to the new
//   per-profile keychain account, and marks the migration complete.
//
// Why the legacy keychain entries are kept (NOT deleted) in this WI:
//   Defensive 2-step pattern — migrate now (this WI), delete the legacy
//   keys in a later WI after a release of dwell time. Mirrors Feature
//   #50's `AIConfiguration` retention pattern. If the migration ever
//   reveals a bug, the legacy keys are still recoverable. The legacy
//   factory path in `WebDAVProviderFactory.make(...)` continues to read
//   them through WI-3, after which the factory switches to reading the
//   store; the legacy delete happens later still (WI-cleanup, post-#52).
//
// Why idempotent on two axes:
//   1. **Marker key set** (`com.vreader.webdav.profilesMigrated.v1` in
//      UserDefaults) → migration already ran, no-op.
//   2. **Profiles list already non-empty** → user has added profiles via
//      the editor (after WI-4a/4b ship), or a prior migration succeeded
//      but the marker write was lost (e.g. partial-crash) — set the
//      marker to prevent re-running but do NOT touch the existing list.
//
// Why the migrated "Default" profile uses a stable UUID:
//   If migration ever runs twice (corrupt marker recovery + non-empty
//   guard both miss), the deterministic id means we replace-in-place
//   via `upsert`, not append a duplicate.
//
// @coordinates-with: WebDAVServerProfile.swift, WebDAVServerProfileStore.swift,
//   WebDAVProviderFactory.swift (legacy reads — kept through WI-3),
//   KeychainService.swift

import Foundation
import os

/// One-shot migration from legacy flat-keychain WebDAV credentials to
/// the new `WebDAVServerProfileStore`. Idempotent.
enum WebDAVProfileMigrator {

    /// UserDefaults key marking the migration as complete. The value is
    /// a Bool; `false` (the default) means "not yet migrated".
    static let migrationMarkerKey = "com.vreader.webdav.profilesMigrated.v1"

    /// Stable UUID for the auto-migrated "Default" profile. Carries no
    /// semantic meaning — just a deterministic identity so that any
    /// re-run after a partial-crash recovery upserts in place instead
    /// of appending a duplicate.
    static let migratedProfileID = UUID(
        uuidString: "00000002-AAAA-4000-8000-000000000001"
    )!

    /// Display name used for the auto-migrated profile.
    static let migratedProfileName = "Default"

    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "vreader",
        category: "WebDAVProfileMigrator"
    )

    /// Runs the migration if not already complete. Safe to call any
    /// number of times from any context. Mirrors `ProviderProfileMigrator`
    /// (Feature #50 WI-2) but specialised for the WebDAV flat-keychain
    /// → profile-list shape.
    ///
    /// - Parameters:
    ///   - store: target profile store (defaults to `.shared`).
    ///   - keychain: keychain used to read legacy + write per-profile
    ///     password. Production callers use a default `KeychainService()`;
    ///     tests inject one with a unique `serviceIdentifier` for isolation.
    ///   - defaults: UserDefaults used for the migration marker.
    ///
    /// - Throws: any error from `store.writePassword(...)` if the
    ///   keychain copy fails. The marker is NOT set when copy fails, so
    ///   the next launch retries.
    static func migrateIfNeeded(
        store: WebDAVServerProfileStore = .shared,
        keychain: KeychainService = KeychainService(),
        defaults: UserDefaults = .standard
    ) async throws {
        // Idempotency check 1: marker set.
        if defaults.bool(forKey: migrationMarkerKey) {
            return
        }

        // Idempotency check 2: defensive — never clobber an existing
        // profile list, even if the marker is somehow missing (e.g.
        // user restored a partial backup that captured profiles but
        // not the migration marker). Set the marker so subsequent
        // launches short-circuit, then return.
        let existing = await store.loadAll()
        if !existing.isEmpty {
            defaults.set(true, forKey: migrationMarkerKey)
            logger.info("WebDAV migration skipped: store already contains \(existing.count, privacy: .public) profile(s). Marker set.")
            return
        }

        // Read legacy keychain entries (read-only). Each may be missing
        // independently — true fresh install has none, partial-install
        // has some.
        let legacyServerURL = (try? keychain.readString(forAccount: legacyServerURLAccount)) ?? ""
        let legacyUsername = (try? keychain.readString(forAccount: legacyUsernameAccount)) ?? ""
        let legacyPassword = (try? keychain.readString(forAccount: legacyPasswordAccount)) ?? ""

        let hasLegacyData = !legacyServerURL.isEmpty
            || !legacyUsername.isEmpty
            || !legacyPassword.isEmpty

        guard hasLegacyData else {
            // True fresh install — no legacy data to migrate. Mark
            // migrated so future launches don't recheck.
            defaults.set(true, forKey: migrationMarkerKey)
            logger.info("WebDAV migration completed: no legacy data found (fresh install).")
            return
        }

        // Build the Default profile from whatever legacy data we have.
        // Missing fields end up as empty strings — the editor (WI-4b)
        // will let the user fill in the gaps, and missingCredentials
        // errors will surface clearly until they do.
        let profile = WebDAVServerProfile(
            id: migratedProfileID,
            name: migratedProfileName,
            serverURL: legacyServerURL,
            username: legacyUsername
        )

        // Copy the password to the new per-profile keychain slot FIRST.
        // If this throws, the rest of the migration doesn't run and the
        // marker stays unset — next launch retries. Writing only when
        // we actually have a password keeps the per-profile slot empty
        // for partial-legacy cases (e.g. user wiped the password through
        // a settings reset but left URL/username intact).
        if !legacyPassword.isEmpty {
            try await store.writePassword(legacyPassword, for: profile.id)
        }

        // Insert + activate. Both writes are inside the actor's
        // serialized region — there is no observable interleaving.
        await store.upsert(profile)
        await store.setActiveProfileID(profile.id)

        // Set the marker LAST. Any failure above leaves the marker
        // unset so the next launch retries from scratch.
        defaults.set(true, forKey: migrationMarkerKey)
        logger.info("WebDAV migration completed: migrated 1 legacy profile to \(migratedProfileName, privacy: .public).")
    }

    // MARK: - Legacy keychain accounts (intentionally duplicated)

    // Why we don't import these from WebDAVProviderFactory: this migrator
    // is a one-shot module that should keep working even after the factory
    // is refactored in WI-3 to drop the flat-keychain constants. Mirroring
    // them here makes the migrator self-contained.

    /// Legacy keychain account for the single server URL (pre-Feature-#52).
    static let legacyServerURLAccount = "com.vreader.webdav.serverURL"
    /// Legacy keychain account for the single username (pre-Feature-#52).
    static let legacyUsernameAccount = "com.vreader.webdav.username"
    /// Legacy keychain account for the single password (pre-Feature-#52).
    static let legacyPasswordAccount = "com.vreader.webdav.password"
}
