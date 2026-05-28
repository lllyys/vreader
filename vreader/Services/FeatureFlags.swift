// Purpose: Runtime feature flags with per-environment defaults, debug overrides,
// and thread-safe shared singleton.
// Flags gate features like AI assistant and sync that are disabled in V1.
//
// Key decisions:
// - Reference type (class) so AIService/SyncService see live changes via .shared.
// - Thread-safe via OSAllocatedUnfairLock (iOS 16+, os framework).
// - `static let shared` singleton configured once at startup via configure(environment:).
// - Persisted flags (`aiAssistant`, `epubContinuousScroll`, `readiumEPUBEngine`) write their overrides
//   to UserDefaults for cross-launch stickiness; see `persistedFlags`.
// - Non-persisted overrides remain session-scoped.
// - Convenience init(environment:) creates standalone instances for testing.
//
// @coordinates-with: AppConfiguration.swift, AIService.swift, SyncService.swift

import Foundation
import os

/// Identifies a specific feature flag.
enum FeatureFlagKey: String, Sendable, CaseIterable {
    case aiAssistant
    case sync
    case searchIndexingVerboseLogs
    case bilingualReading
    /// Feature #71: EPUB continuous cross-chapter scroll. Shipped through a
    /// multi-WI build (window/coordinator/JS/bridge/container/navigation/
    /// bilingual); the terminal WI (2026-05-28) flipped the default ON after
    /// real-touch-scroll device verification confirmed the rAF observer fires
    /// and the cross-chapter materialize/evict works end-to-end. EPUB `.scroll`
    /// layout now flows continuously across chapters by default; the persisted
    /// override can still disable it per-user.
    case epubContinuousScroll
    /// Feature #42 Phase 1: route EPUB rendering to the Readium Swift Toolkit
    /// engine instead of the legacy `EPUBWebViewBridge`. Default OFF — the
    /// Readium host (WI-5) is built behind this flag and `EPUBWebViewBridge`
    /// stays the live default until full parity (incl. bilingual #56 +
    /// continuous-scroll #71) is verified; only then does the WI-14 flip move
    /// the default ON (human-gated G2). Persisted so the override sticks across
    /// launches for testing + so it can be turned back OFF after the Readium
    /// engine has written data (the dual-write to the legacy `Locator` keeps
    /// that safe).
    case readiumEPUBEngine
}

/// Runtime feature flags with environment-based defaults, override support,
/// and a thread-safe shared singleton.
///
/// **Production usage**: Configure `.shared` once at app launch:
/// ```swift
/// FeatureFlags.shared.configure(environment: config.environment)
/// ```
/// Then read flags via `FeatureFlags.shared.isEnabled(.aiAssistant)`.
///
/// **Testing**: Create standalone instances with `FeatureFlags(environment:)`.
nonisolated final class FeatureFlags: Sendable {

    /// Thread-safe storage for overrides and environment.
    private let storage: OSAllocatedUnfairLock<Storage>

    /// Optional UserDefaults for persisting select flag overrides.
    /// nonisolated(unsafe) is safe because UserDefaults methods are thread-safe.
    private nonisolated(unsafe) let persistenceDefaults: UserDefaults?

    /// UserDefaults key prefix for persisted flags.
    private static let persistenceKeyPrefix = "com.vreader.featureFlags."

    /// Flags that are persisted to UserDefaults when overridden.
    private static let persistedFlags: Set<FeatureFlagKey> = [.aiAssistant, .epubContinuousScroll, .readiumEPUBEngine]

    // MARK: - Shared Singleton

    /// The shared singleton instance. Call `configure(environment:)` at startup.
    static let shared = FeatureFlags(environment: .prod, persistenceDefaults: .standard)

    // MARK: - Internal Storage

    private struct Storage: Sendable {
        var environment: AppEnvironment
        var overrides: [FeatureFlagKey: Bool]
    }

    // MARK: - Initialization

    /// Creates feature flags for the given environment.
    /// For production, use `.shared` instead.
    ///
    /// - Parameters:
    ///   - environment: The app environment to determine defaults.
    ///   - persistenceDefaults: Optional UserDefaults for persisting flag overrides.
    ///     Pass nil for session-scoped only (default for standalone instances).
    init(environment: AppEnvironment, persistenceDefaults: UserDefaults? = nil) {
        self.persistenceDefaults = persistenceDefaults

        // Load persisted overrides if UserDefaults is provided
        var initialOverrides: [FeatureFlagKey: Bool] = [:]
        if let defaults = persistenceDefaults {
            for key in Self.persistedFlags {
                let udKey = Self.persistenceKeyPrefix + key.rawValue
                if defaults.object(forKey: udKey) != nil {
                    initialOverrides[key] = defaults.bool(forKey: udKey)
                }
            }
        }

        self.storage = OSAllocatedUnfairLock(initialState: Storage(
            environment: environment,
            overrides: initialOverrides
        ))
    }

    // MARK: - Configuration

    /// Configures the shared instance with the resolved environment.
    /// Should be called once at app startup.
    ///
    /// - Parameter environment: The app environment.
    func configure(environment: AppEnvironment) {
        storage.withLock { state in
            state.environment = environment
        }
    }

    // MARK: - Flag Accessors

    /// Returns whether the given feature flag is enabled.
    ///
    /// Checks overrides first, then falls back to environment-based defaults.
    func isEnabled(_ key: FeatureFlagKey) -> Bool {
        storage.withLock { state in
            if let override = state.overrides[key] {
                return override
            }
            return Self.defaultValue(for: key, environment: state.environment)
        }
    }

    /// Whether the AI assistant feature is enabled.
    var aiAssistant: Bool { isEnabled(.aiAssistant) }

    /// Whether sync is enabled.
    var sync: Bool { isEnabled(.sync) }

    /// Whether verbose search indexing logs are enabled.
    var searchIndexingVerboseLogs: Bool { isEnabled(.searchIndexingVerboseLogs) }

    /// Whether bilingual reading mode is enabled (feature #56).
    var bilingualReading: Bool { isEnabled(.bilingualReading) }

    /// Whether EPUB continuous cross-chapter scroll is enabled (feature #71).
    /// Default ON (terminal WI, 2026-05-28); overridable per-launch via the
    /// persisted UserDefaults key `com.vreader.featureFlags.epubContinuousScroll`
    /// (aiAssistant pattern) — a user/debug `false` override still disables it.
    var epubContinuousScroll: Bool { isEnabled(.epubContinuousScroll) }

    /// Feature #42: render EPUB via the Readium engine. Default OFF (see the
    /// enum doc + `defaultValue`); the Readium host is built behind this until
    /// parity, then the WI-14 G2 flip moves it ON.
    var readiumEPUBEngine: Bool { isEnabled(.readiumEPUBEngine) }

    // MARK: - Override Management

    /// Sets a runtime override for a feature flag.
    /// Persisted flags (`aiAssistant`, `epubContinuousScroll`, `readiumEPUBEngine` — see `persistedFlags`)
    /// are written to UserDefaults; others remain session-scoped.
    ///
    /// - Parameters:
    ///   - value: The override value.
    ///   - key: The flag to override.
    func setOverride(_ value: Bool, for key: FeatureFlagKey) {
        storage.withLock { state in
            state.overrides[key] = value
        }
        // Persist to UserDefaults outside the lock (UserDefaults is thread-safe).
        // Order relative to memory is benign: the lock serializes the in-memory state,
        // and UserDefaults.set is itself atomic per-key.
        if Self.persistedFlags.contains(key), let defaults = persistenceDefaults {
            defaults.set(value, forKey: Self.persistenceKeyPrefix + key.rawValue)
        }
    }

    /// Removes the runtime override for a feature flag, restoring the default.
    ///
    /// - Parameter key: The flag to restore to its default.
    func removeOverride(for key: FeatureFlagKey) {
        storage.withLock { state in
            state.overrides.removeValue(forKey: key)
        }
        if Self.persistedFlags.contains(key), let defaults = persistenceDefaults {
            defaults.removeObject(forKey: Self.persistenceKeyPrefix + key.rawValue)
        }
    }

    /// Removes all runtime overrides, restoring all flags to defaults.
    func clearAllOverrides() {
        storage.withLock { state in
            state.overrides.removeAll()
        }
        if let defaults = persistenceDefaults {
            for key in Self.persistedFlags {
                defaults.removeObject(forKey: Self.persistenceKeyPrefix + key.rawValue)
            }
        }
    }

    // MARK: - Private

    /// Returns the default value for a flag based on environment.
    private static func defaultValue(for key: FeatureFlagKey, environment: AppEnvironment) -> Bool {
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
        case .bilingualReading:
            // Ships dark — enabled progressively via override (aiAssistant pattern).
            return false
        case .epubContinuousScroll:
            // Feature #71 terminal WI (2026-05-28): default ON in every
            // environment. Real-touch-scroll device verification confirmed the
            // rAF observer fires and cross-chapter materialize/evict works
            // end-to-end, so continuous scroll is now the default EPUB
            // scroll-mode reading experience. Users can still disable it via the
            // persisted override (see the enum doc).
            return true
        case .readiumEPUBEngine:
            // Feature #42 Phase 1: default OFF in every environment —
            // `EPUBWebViewBridge` stays the live EPUB engine until the Readium
            // host reaches full parity (incl. #56 bilingual + #71 continuous
            // scroll). The WI-14 flip (human-gated G2) moves this default ON.
            return false
        }
    }
}
