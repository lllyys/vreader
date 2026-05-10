// Purpose: Idempotent commit-style migrator from legacy AIConfiguration
// (single profile) to ProviderProfileStore (list of profiles)
// (feature #50 WI-2).
//
// Commit ordering (per Gate-2 round-2 audit finding [1]):
//   1. Check the migration flag + verify profile data is intact. If both
//      indicate migrated, return immediately (idempotent no-op).
//   2. Read legacy AIConfiguration via AIConfigurationStore (read-only).
//   3. Read legacy keychain key at AIService.apiKeyAccount (read-only).
//   4. If neither exists (true fresh install): set the flag with empty
//      list. Otherwise build a single ProviderProfile of kind
//      .openAICompatible from the legacy data.
//   5. Copy the legacy keychain key to the per-profile account
//      (idempotent — saveString overwrites).
//   6. Verify the keychain copy via read-back.
//   7. Encode profile list + active ID, write to UserDefaults.
//   8. Verify decode round-trip — only then set the migration flag.
//
// On read: `migrated == true` is treated valid only if `profilesKey`
// decodes to a non-empty array (or, for fresh-install, the flag stays
// set with empty list — that case bypasses the re-run trigger because
// we know there was no legacy data to lose). If the flag is set BUT
// legacy data is present and profile data isn't, re-run migration.
//
// @coordinates-with: ProviderProfileStore.swift, AIConfigurationStore.swift,
//   KeychainService.swift, KeychainService+ProviderProfile.swift

import Foundation

/// Idempotent legacy-config-to-provider-profile migrator.
///
/// The protocol is intentionally **synchronous**: the migrator's work
/// (read preferences, read/write keychain, encode/decode JSON) is all
/// sync, and an `async` signature would introduce an `await` suspension
/// point inside the calling actor — letting concurrent calls re-enter
/// the actor between the migration check and a subsequent
/// read-modify-write of the profile list. That race manifested as a
/// failing concurrency-stress test for `ProviderProfileStore`.
protocol ProviderProfileMigrating: Sendable {
    /// Migrates legacy data if needed. Idempotent — safe to call any
    /// number of times from any context. Mid-migration crash recovery
    /// is built into the read path (see `Self.shouldMigrate`).
    func migrateIfNeeded(
        preferences: any PreferenceStoring,
        keychain: KeychainService
    )
}

/// Default migrator: lifts a single legacy AIConfiguration + its API
/// key into one OpenAI-compatible ProviderProfile, set as active.
struct DefaultProviderProfileMigrator: ProviderProfileMigrating {

    /// Stable UUID used for the auto-migrated profile so that re-runs
    /// after a partial-crash recovery don't create a second profile.
    /// Carries no semantic meaning; just a deterministic identity.
    private static let migratedProfileID = UUID(
        uuidString: "00000001-AAAA-4000-8000-000000000001"
    )!

    static let profilesKey = "com.vreader.ai.providerProfiles"
    static let activeIDKey = "com.vreader.ai.activeProviderID"
    static let migrationFlagKey = "com.vreader.ai.providerProfiles.migrated"

    func migrateIfNeeded(
        preferences: any PreferenceStoring,
        keychain: KeychainService
    ) {
        // Step 1: idempotency check + crash recovery.
        // Pass keychain so the recovery check can detect "flag set +
        // profiles missing + keychain-only legacy data" mid-crash state
        // (round-1 Gate-4 audit fix [2]).
        if !Self.shouldMigrate(preferences: preferences, keychain: keychain) {
            return
        }

        // Steps 2-3: read legacy data (read-only).
        let legacyStore = AIConfigurationStore(preferences: preferences)
        let legacyConfig = legacyStore.load()
        let legacyAPIKey: String? = (try? keychain.readString(
            forAccount: AIService.apiKeyAccount
        ))

        // Step 4: fresh install detection.
        let hasLegacyConfig = preferences.string(forKey: "com.vreader.ai.configuration") != nil
        let hasLegacyKey = (legacyAPIKey?.isEmpty == false)

        guard hasLegacyConfig || hasLegacyKey else {
            // True fresh install — set flag, write empty list, no profile.
            Self.writeProfiles([], activeID: nil, preferences: preferences)
            Self.setMigrationFlag(preferences: preferences)
            return
        }

        // Build a single ProviderProfile from the legacy data.
        let profile = ProviderProfile(
            id: Self.migratedProfileID,
            name: "OpenAI",
            kind: .openAICompatible,
            baseURL: legacyConfig.endpoint,
            model: legacyConfig.model,
            temperature: legacyConfig.temperature,
            maxTokens: legacyConfig.maxTokens
        )

        // Step 5: copy legacy keychain key to per-profile account
        // (idempotent — overwrite-safe).
        if let key = legacyAPIKey, !key.isEmpty {
            do {
                try keychain.saveAPIKey(key, forProfile: profile.id)
            } catch {
                // Step 6 (verify) will fail — fall through; flag won't be set.
            }

            // Step 6: verify keychain copy via read-back. If it doesn't match,
            // bail out without setting the flag — next run will retry.
            let readBack = try? keychain.readAPIKey(forProfile: profile.id)
            guard readBack == key else {
                return
            }
        }

        // Step 7: encode + write profile list + active ID.
        Self.writeProfiles([profile], activeID: profile.id, preferences: preferences)

        // Step 8: verify decode round-trip; only then set the flag.
        let verified = Self.readProfiles(preferences: preferences)
        guard verified == [profile] else {
            return
        }
        Self.setMigrationFlag(preferences: preferences)
    }

    // MARK: - Helpers (static so they can be reused by ProviderProfileStore)

    /// Returns true if migration must run. Considers the flag AND the
    /// integrity of the post-migration data:
    ///
    /// - Flag NOT set → migrate.
    /// - Flag set + profiles raw missing → check legacy data:
    ///   - Legacy config OR legacy keychain key exists → mid-crash, re-migrate.
    ///   - Neither exists → fresh-install completed legitimately, no migrate.
    /// - Flag set + profiles raw exists but doesn't decode → corrupt, re-migrate.
    /// - Flag set + profiles raw decodes to non-empty list → migrated.
    /// - Flag set + profiles raw decodes to `[]` → ambiguous; consult legacy:
    ///   - Legacy data still exists → mid-crash, re-migrate.
    ///   - No legacy data → legitimate fresh-install completion, no migrate.
    ///
    /// Round-1 Gate-4 audit fixes: previously this only checked
    /// `string?.isEmpty == false` for integrity, which let corrupt JSON
    /// pass; and it ignored legacy-keychain-only state for crash recovery.
    static func shouldMigrate(
        preferences: any PreferenceStoring,
        keychain: KeychainService? = nil
    ) -> Bool {
        let flagSet = preferences.string(forKey: Self.migrationFlagKey) == "true"
        if !flagSet {
            return true
        }

        // Flag is set. Validate the post-migration state via actual decode.
        let raw = preferences.string(forKey: Self.profilesKey)

        if let json = raw,
           let data = json.data(using: .utf8) {
            if let decoded = try? JSONDecoder().decode([ProviderProfile].self, from: data) {
                // Decoded successfully. Populated array → migration done.
                if !decoded.isEmpty {
                    return false
                }
                // Decoded to []: ambiguous. Could be legitimate fresh-install
                // result (flag set + empty list + no legacy data) OR mid-crash
                // where profile write succeeded but as []. Round-2 Gate-4
                // audit fix [1]: fall through to legacy-data check.
                return Self.legacyDataExists(preferences: preferences, keychain: keychain)
            }
            // Corrupt JSON: re-migrate.
            return true
        }

        // No profile data. Was there legacy data (config OR keychain key)?
        if Self.legacyDataExists(preferences: preferences, keychain: keychain) {
            // Mid-migration crash: legacy still readable, profiles missing.
            return true
        }

        // Flag set + no profiles + no legacy = fresh install completed; no work.
        return false
    }

    /// Helper: checks whether ANY legacy data is still present
    /// (config in preferences OR API key in keychain).
    static func legacyDataExists(
        preferences: any PreferenceStoring,
        keychain: KeychainService?
    ) -> Bool {
        if preferences.string(forKey: "com.vreader.ai.configuration") != nil {
            return true
        }
        guard let keychain = keychain else { return false }
        if let key = try? keychain.readString(forAccount: AIService.apiKeyAccount),
           !key.isEmpty {
            return true
        }
        return false
    }

    static func writeProfiles(
        _ profiles: [ProviderProfile],
        activeID: UUID?,
        preferences: any PreferenceStoring
    ) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(profiles),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        preferences.set(json, forKey: Self.profilesKey)
        if let id = activeID {
            preferences.set(id.uuidString, forKey: Self.activeIDKey)
        } else {
            preferences.set("", forKey: Self.activeIDKey)
        }
    }

    static func readProfiles(preferences: any PreferenceStoring) -> [ProviderProfile] {
        guard let json = preferences.string(forKey: Self.profilesKey),
              let data = json.data(using: .utf8),
              let profiles = try? JSONDecoder().decode([ProviderProfile].self, from: data) else {
            return []
        }
        return profiles
    }

    static func readActiveID(preferences: any PreferenceStoring) -> UUID? {
        guard let raw = preferences.string(forKey: Self.activeIDKey),
              !raw.isEmpty,
              let id = UUID(uuidString: raw) else {
            return nil
        }
        return id
    }

    static func setMigrationFlag(preferences: any PreferenceStoring) {
        preferences.set("true", forKey: Self.migrationFlagKey)
    }
}
