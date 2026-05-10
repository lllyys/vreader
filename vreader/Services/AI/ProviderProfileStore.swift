// Purpose: Actor-isolated storage for the list of saved AI provider
// profiles, with one active selection. Triggers idempotent commit-style
// migration from legacy AIConfiguration on first read (feature #50 WI-2).
//
// Why an actor (Gate-2 round-1 audit finding [4]):
//   PreferenceStoring exposes atomic key-level reads/writes but NOT
//   atomic load-modify-save. Cross-actor writers (AIService actor +
//   @MainActor settings VM) could lose updates if the store were a
//   plain struct. Actor isolation gives us atomic upsert/remove/
//   setActiveProfileID without locks. Cost: every read becomes async.
//
// Shared-instance contract (Gate-2 round-2 audit finding [2]):
//   `.shared` is the production singleton. `AIService`,
//   `AISettingsViewModel`, `AIProviderPickerViewModel` all use `.shared`.
//   Tests inject a separate test-container instance via the
//   public `init(preferences:migrator:keychain:)`. Multiple stores
//   backed by the same UserDefaults would re-introduce lost updates.
//
// Snapshot semantics (Gate-2 round-1 audit finding [6]):
//   `activeProfileSnapshot()` returns a by-value copy. AIService's
//   request/stream pipeline takes one snapshot at request start and
//   uses it for the request's lifetime; later mutations to the store
//   don't affect in-flight calls.
//
// @coordinates-with: ProviderProfile.swift, ProviderProfileMigrator.swift,
//   AIConfigurationStore.swift, KeychainService.swift, AIService.swift

import Foundation

/// Actor-isolated list-with-active-selection of AI provider profiles.
actor ProviderProfileStore {

    /// App-scoped production singleton. All production callers
    /// (`AIService`, `AISettingsViewModel`, `AIProviderPickerViewModel`)
    /// MUST use this exact instance — otherwise the actor isolation
    /// guarantee doesn't hold (round-2 audit finding [2]).
    static let shared = ProviderProfileStore()

    private let preferences: any PreferenceStoring
    private let migrator: ProviderProfileMigrating
    private let keychain: KeychainService

    /// In-memory marker so we don't re-run the migration check on every
    /// read after the first one. The migrator's flag-based persistence
    /// handles cross-process / cross-launch idempotency.
    private var migrationCompleted: Bool = false

    /// Test-only init. Production callers MUST use `.shared`.
    init(
        preferences: any PreferenceStoring = UserDefaultsPreferenceStore(),
        migrator: ProviderProfileMigrating = DefaultProviderProfileMigrator(),
        keychain: KeychainService = KeychainService()
    ) {
        self.preferences = preferences
        self.migrator = migrator
        self.keychain = keychain
    }

    // MARK: - Public API (all async because actor)

    /// Returns the current list of saved profiles. Triggers lazy
    /// migration on the first call.
    func loadAll() async -> [ProviderProfile] {
        await ensureMigrated()
        return DefaultProviderProfileMigrator.readProfiles(preferences: preferences)
    }

    /// Returns the currently active profile (resolved by id), or nil
    /// if no active id is set or it doesn't resolve to a known profile.
    func activeProfile() async -> ProviderProfile? {
        await ensureMigrated()
        guard let id = DefaultProviderProfileMigrator.readActiveID(preferences: preferences) else {
            return nil
        }
        let profiles = DefaultProviderProfileMigrator.readProfiles(preferences: preferences)
        return profiles.first(where: { $0.id == id })
    }

    /// Snapshot of the active profile, taken once at call time. The
    /// returned value is by-value (struct) and is stable for the
    /// caller's lifetime regardless of subsequent mutations to the
    /// store. Used by AIService.resolveProvider() so an in-flight
    /// request keeps its profile state.
    func activeProfileSnapshot() async -> ProviderProfile? {
        await activeProfile()
    }

    /// Inserts a new profile or replaces an existing one with the same id.
    func upsert(_ profile: ProviderProfile) async {
        await ensureMigrated()
        var profiles = DefaultProviderProfileMigrator.readProfiles(preferences: preferences)
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        } else {
            profiles.append(profile)
        }
        let activeID = DefaultProviderProfileMigrator.readActiveID(preferences: preferences)
        DefaultProviderProfileMigrator.writeProfiles(
            profiles,
            activeID: activeID,
            preferences: preferences
        )
    }

    /// Removes the profile with the given id. If the removed profile
    /// was the active one, clears active. (Per the plan, "clear" not
    /// "fall back to first" — the UI surfaces the no-active case
    /// explicitly.)
    func remove(id: UUID) async {
        await ensureMigrated()
        var profiles = DefaultProviderProfileMigrator.readProfiles(preferences: preferences)
        profiles.removeAll(where: { $0.id == id })
        let currentActive = DefaultProviderProfileMigrator.readActiveID(preferences: preferences)
        let nextActive: UUID? = (currentActive == id) ? nil : currentActive
        DefaultProviderProfileMigrator.writeProfiles(
            profiles,
            activeID: nextActive,
            preferences: preferences
        )
    }

    /// Sets the active profile by id. Passing nil clears active.
    /// Setting an unknown id is allowed but `activeProfile()` will
    /// return nil for it (the id is recorded but doesn't resolve).
    func setActiveProfileID(_ id: UUID?) async {
        await ensureMigrated()
        let profiles = DefaultProviderProfileMigrator.readProfiles(preferences: preferences)
        DefaultProviderProfileMigrator.writeProfiles(
            profiles,
            activeID: id,
            preferences: preferences
        )
    }

    // MARK: - Private

    /// Idempotent lazy-on-read migration trigger. Runs migrator at most
    /// once per actor lifetime IF migration genuinely completes;
    /// the migrator's own flag-based check handles re-launches.
    /// Synchronous on purpose — see the protocol's header for why
    /// an async migration introduces a re-entrancy race.
    ///
    /// Round-1 Gate-4 audit fix: only flip the in-memory flag when
    /// `shouldMigrate` is now false (i.e., the migrator actually
    /// committed). A bailed-out migrator (e.g., keychain copy verify
    /// failed mid-run) leaves both the persistent flag AND the
    /// in-memory flag clear, so the next read retries.
    private func ensureMigrated() {
        guard !migrationCompleted else { return }
        migrator.migrateIfNeeded(preferences: preferences, keychain: keychain)
        migrationCompleted = !DefaultProviderProfileMigrator.shouldMigrate(
            preferences: preferences,
            keychain: keychain
        )
    }
}
