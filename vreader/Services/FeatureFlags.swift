// Purpose: Runtime feature flags with per-environment defaults and debug overrides.
// Flags gate features like AI assistant and sync that are disabled in V1.
//
// Key decisions:
// - Default values are determined by environment at construction time.
// - Runtime overrides allow debug builds to toggle flags without rebuild.
// - Struct-based (value type) for Sendable compliance and simple copy semantics.
// - Override storage is a plain dictionary; no persistence (overrides are session-scoped).
//
// @coordinates-with: AppConfiguration.swift

import Foundation

/// Identifies a specific feature flag.
enum FeatureFlagKey: String, Sendable, CaseIterable {
    case aiAssistant
    case sync
    case searchIndexingVerboseLogs
}

/// Runtime feature flags with environment-based defaults and override support.
///
/// **Usage**: Create once per app launch with the resolved environment.
/// This is a value type (struct) — copies are independent. Overrides are
/// session-scoped and not persisted across app launches.
///
/// Thread safety: Instances are `Sendable`. For shared mutable access,
/// wrap in an actor or use `@MainActor` property.
struct FeatureFlags: Sendable {

    /// The environment these flags were configured for.
    let environment: AppEnvironment

    /// Runtime overrides applied on top of defaults. Session-scoped, not persisted.
    private var overrides: [FeatureFlagKey: Bool] = [:]

    // MARK: - Flag Accessors

    /// Whether the AI assistant feature is enabled. Default: OFF in all environments.
    var aiAssistant: Bool {
        overrides[.aiAssistant] ?? defaultValue(for: .aiAssistant)
    }

    /// Whether sync is enabled. Default: OFF in all environments (V1).
    var sync: Bool {
        overrides[.sync] ?? defaultValue(for: .sync)
    }

    /// Whether verbose search indexing logs are enabled.
    /// Default: ON in dev/staging, OFF in prod.
    var searchIndexingVerboseLogs: Bool {
        overrides[.searchIndexingVerboseLogs] ?? defaultValue(for: .searchIndexingVerboseLogs)
    }

    // MARK: - Initialization

    /// Creates feature flags for the given environment.
    ///
    /// - Parameter environment: The app environment to determine defaults.
    init(environment: AppEnvironment) {
        self.environment = environment
    }

    // MARK: - Override Management

    /// Sets a runtime override for a feature flag.
    ///
    /// - Parameters:
    ///   - key: The flag to override.
    ///   - value: The override value.
    mutating func setOverride(_ key: FeatureFlagKey, value: Bool) {
        overrides[key] = value
    }

    /// Removes the runtime override for a feature flag, restoring the default.
    ///
    /// - Parameter key: The flag to restore to its default.
    mutating func removeOverride(_ key: FeatureFlagKey) {
        overrides.removeValue(forKey: key)
    }

    /// Removes all runtime overrides, restoring all flags to defaults.
    mutating func clearAllOverrides() {
        overrides.removeAll()
    }

    // MARK: - Private

    /// Returns the default value for a flag based on the current environment.
    private func defaultValue(for key: FeatureFlagKey) -> Bool {
        switch key {
        case .aiAssistant:
            return false
        case .sync:
            return false
        case .searchIndexingVerboseLogs:
            switch environment {
            case .dev, .staging:
                return true
            case .prod:
                return false
            }
        }
    }
}
