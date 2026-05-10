// Purpose: Saved AI provider configuration entry (feature #50 WI-1).
// One ProviderProfile = one saved provider that the user can switch active
// AI calls between. Persisted by ProviderProfileStore (WI-2) as a JSON list
// in UserDefaults; API keys are stored separately in Keychain via the
// per-profile account string from KeychainService+ProviderProfile.
//
// Key decisions:
// - id is UUID, stable across renames so downstream identity tracking
//   (active selector, in-flight request snapshots) doesn't drift.
// - apiKey is NOT a stored property. Mixing the secret with display
//   metadata would defeat Keychain's purpose; the keychain account string
//   for a given profile is derived externally via
//   KeychainService.providerAccount(for:).
// - Codable + Sendable + Equatable + Identifiable so SwiftUI Lists,
//   actor boundary crossing, and JSON persistence all work uniformly.
//
// @coordinates-with: ProviderKind.swift, ProviderProfileStore.swift,
//   KeychainService+ProviderProfile.swift, AISettingsViewModel.swift

import Foundation

/// A saved AI provider configuration entry.
struct ProviderProfile: Codable, Sendable, Equatable, Identifiable {
    /// Stable identity for the profile, retained across renames.
    let id: UUID

    /// User-chosen display name for the profile (e.g. "ChatGPT", "Local Llama").
    var name: String

    /// Which on-the-wire API this profile speaks.
    var kind: ProviderKind

    /// API endpoint base URL for this profile.
    var baseURL: URL

    /// Model identifier (e.g. "gpt-4o-mini", "claude-sonnet-4-6").
    var model: String

    /// Sampling temperature (0.0 = deterministic, 1.0 = creative).
    /// Clamping is enforced by the Settings UI on save, not the DTO.
    var temperature: Double

    /// Maximum tokens in the response. Anthropic requires this on every
    /// request; OpenAI treats it as optional but we always send it.
    var maxTokens: Int
}
