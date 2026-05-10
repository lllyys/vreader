// Purpose: Keychain account naming + per-profile API key wrappers
// (feature #50 WI-1).
//
// The keychain naming convention for per-profile API keys is intentionally
// kept OFF the ProviderProfile DTO so the DTO doesn't leak storage details
// (round-1 audit finding [8]). This extension is the one place that knows
// the convention.
//
// @coordinates-with: ProviderProfile.swift, ProviderProfileStore.swift,
//   AISettingsViewModel.swift

import Foundation

extension KeychainService {
    /// Returns the keychain account string for a given profile id.
    /// Format: `com.vreader.ai.apiKey.<UUID-string>`. The UUID is whatever
    /// `UUID.uuidString` returns (uppercase hex), so callers should pass
    /// the same UUID instance they used when saving.
    static func providerAccount(for profileID: UUID) -> String {
        "com.vreader.ai.apiKey.\(profileID.uuidString)"
    }

    /// Reads the API key for a given profile, or nil if no key is stored.
    func readAPIKey(forProfile profileID: UUID) throws -> String? {
        try readString(forAccount: Self.providerAccount(for: profileID))
    }

    /// Saves the API key for a given profile, overwriting any existing key.
    func saveAPIKey(_ key: String, forProfile profileID: UUID) throws {
        try saveString(key, forAccount: Self.providerAccount(for: profileID))
    }

    /// Deletes the API key for a given profile. Idempotent — deleting a
    /// nonexistent key is a no-op (inherited from `delete(forAccount:)`).
    func deleteAPIKey(forProfile profileID: UUID) throws {
        try delete(forAccount: Self.providerAccount(for: profileID))
    }
}
