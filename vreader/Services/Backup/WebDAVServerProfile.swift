// Purpose: Saved WebDAV server configuration entry (feature #52 WI-1).
// One WebDAVServerProfile = one saved server the user can switch the active
// backup destination between. Persisted by WebDAVServerProfileStore as a JSON
// list in UserDefaults; passwords are stored separately in Keychain at the
// per-profile account string from `keychainPasswordAccount(for:)`.
//
// Key decisions:
// - `id` is UUID, stable across renames so downstream identity tracking
//   (active selector, Keychain key) doesn't drift.
// - `password` is NOT a stored property. Mixing the secret with display
//   metadata would defeat Keychain's purpose. The Keychain account string
//   for a given profile is derived externally via
//   `WebDAVServerProfile.keychainPasswordAccount(for:)`.
// - `Codable + Sendable + Hashable + Identifiable` so SwiftUI Lists, actor
//   boundary crossing, and JSON persistence all work uniformly.
// - Mirrors `ProviderProfile` (feature #50 WI-1, VERIFIED 2026-05-13) shape
//   intentionally — the WebDAV multi-profile architecture is a direct
//   adaptation of the AI multi-profile precedent.
//
// @coordinates-with: WebDAVServerProfileStore.swift,
//   WebDAVProviderFactory.swift, KeychainService.swift

import Foundation

/// A saved WebDAV server configuration entry.
struct WebDAVServerProfile: Codable, Sendable, Hashable, Identifiable {
    /// Stable identity for the profile, retained across renames.
    let id: UUID

    /// User-chosen display name for the profile (e.g. "Home Nextcloud",
    /// "Work Synology"). May be empty; `displayName` falls back to the
    /// `serverURL` hostname in that case (edge case (e) of bug #52 row).
    var name: String

    /// WebDAV server URL (e.g. "https://nextcloud.example.com/remote.php/dav/files/me/").
    /// Validation (HTTPS recommended, HTTP accepted per bug #110 /
    /// `NSAllowsArbitraryLoads: true`) is enforced by the Settings UI on
    /// save, not by the DTO.
    var serverURL: String

    /// Username for HTTP Basic Auth against the WebDAV server.
    var username: String

    /// User-facing label. Falls back to `serverURL`'s host component if
    /// `name` is empty (per bug #52 row edge case (e)). Returns the raw
    /// URL string if even hostname extraction fails.
    var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty { return trimmedName }
        if let url = URL(string: serverURL), let host = url.host, !host.isEmpty {
            return host
        }
        return serverURL
    }

    /// Keychain account string for a given profile id. The Keychain stores
    /// the password under this account. Format mirrors
    /// `KeychainService+ProviderProfile.swift`'s pattern.
    static func keychainPasswordAccount(for id: UUID) -> String {
        "com.vreader.webdav.profile.\(id.uuidString).password"
    }
}
