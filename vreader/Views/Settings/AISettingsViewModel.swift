// Purpose: ViewModel for the AI Settings section. Manages global AI toggle,
// consent state, and the saved-provider-profile list with one active selection.
//
// Feature #50 WI-6a: previously a single-profile VM (model/baseURL/apiKey
// fields here, single AIConfigurationStore). Now a multi-profile VM backed
// by the shared `ProviderProfileStore` actor. The editor sheet (add/edit
// profile + API key + test-connection) lands in WI-6b.
//
// Key decisions:
// - @Observable + @MainActor for SwiftUI binding (iOS 17+).
// - Uses `ProviderProfileStore.shared` by default; tests inject a separate
//   store via the init parameter (shared-instance contract from
//   `ProviderProfileStore.swift` header).
// - `loadProfiles()` triggers the lazy migration inside the store; the VM
//   doesn't run migration itself.
// - `deleteProfile(_:)` clears the per-profile keychain entry as well as
//   the store entry — orphaned keychain rows would otherwise outlive the UI.
// - Feature flag (`isAIEnabled`) and consent state remain stored locally
//   on this VM; they're global, not per-profile. The stored-property +
//   didSet write-through for `isAIEnabled` is bug #167's fix and must
//   stay (see test `toggleNotifiesObservationTracker`).
//
// @coordinates-with: FeatureFlags.swift, AIConsentManager.swift,
//   KeychainService+ProviderProfile.swift, ProviderProfileStore.swift,
//   AIProviderListView.swift

import Foundation
import Observation
import OSLog

/// ViewModel for the AI settings screen.
@Observable
@MainActor
final class AISettingsViewModel {

    // MARK: - Dependencies

    private let featureFlags: FeatureFlags
    private let consentManager: AIConsentManager
    private let keychainService: KeychainService
    private let profileStore: ProviderProfileStore

    private static let log = Logger(subsystem: "com.vreader.app", category: "AISettings")

    // MARK: - Global Toggles

    /// Whether the AI assistant feature flag is enabled. Bug #167 fix:
    /// stored property + didSet write-through (not a pure computed
    /// property) so the @Observable macro instruments the storage and
    /// SwiftUI re-renders dependent sections without an app relaunch.
    /// The oldValue != isAIEnabled guard dedupes UserDefaults writes on
    /// same-value reassignments from @Bindable view rebuilds.
    var isAIEnabled: Bool {
        didSet {
            guard oldValue != isAIEnabled else { return }
            featureFlags.setOverride(isAIEnabled, for: .aiAssistant)
        }
    }

    /// Whether the user has granted AI data consent. Pure pass-through to
    /// AIConsentManager; the manager handles UserDefaults persistence.
    var hasConsent: Bool {
        get { consentManager.hasConsent }
        set {
            if newValue {
                consentManager.grantConsent()
            } else {
                consentManager.revokeConsent()
            }
        }
    }

    // MARK: - Profile List State

    /// Current saved profiles, loaded on the most recent `loadProfiles()`.
    /// Empty list before first load.
    private(set) var profiles: [ProviderProfile] = []

    /// The id of the currently-active profile, or nil if none active.
    private(set) var activeID: UUID?

    /// Last error from a list operation. nil after a successful op.
    var listError: String?

    // MARK: - Initialization

    init(
        featureFlags: FeatureFlags = .shared,
        consentManager: AIConsentManager = AIConsentManager(),
        keychainService: KeychainService = KeychainService(),
        profileStore: ProviderProfileStore = .shared
    ) {
        self.featureFlags = featureFlags
        self.consentManager = consentManager
        self.keychainService = keychainService
        self.profileStore = profileStore
        self.isAIEnabled = featureFlags.isEnabled(.aiAssistant)
    }

    // MARK: - Profile List Operations (WI-6a)

    /// Loads the current profile list and active id from the store. The
    /// store transparently runs the legacy → multi-profile migration on
    /// its first read; callers don't need to invoke migration themselves.
    ///
    /// Round-1 audit finding [1]: uses `loadSnapshot()` (single actor
    /// hop) instead of pairing `loadAll()` + `activeProfile()`, so a
    /// concurrent mutation between two awaits can't publish a list that
    /// disagrees with the active id.
    func loadProfiles() async {
        let snapshot = await profileStore.loadSnapshot()
        profiles = snapshot.profiles
        // Defensive: if the persisted active id no longer resolves to a
        // present profile (the store permits this so unknown ids round-
        // trip through `setActiveProfileID`), surface it to the UI as
        // "no active selection" rather than dangling.
        if let id = snapshot.activeID,
           snapshot.profiles.contains(where: { $0.id == id }) {
            activeID = id
        } else {
            activeID = nil
        }
        listError = nil
    }

    /// Sets the currently-active profile by id. Passing nil clears active.
    /// Round-1 audit finding [2]: rejects ids not in the current profile
    /// list rather than writing them and leaving the VM with a dangling
    /// active id. The UI only renders rows from `profiles`, so an
    /// unknown id always indicates a stale view or a programmer error.
    func setActive(_ id: UUID?) async {
        if let id, !profiles.contains(where: { $0.id == id }) {
            // Don't write a dangling id to the store. The store would
            // accept it, but `activeProfile()` would later resolve to nil
            // and the VM's `activeID` would diverge from a meaningful row.
            return
        }
        await profileStore.setActiveProfileID(id)
        // Read back authoritatively from the store, not from the local id,
        // so a concurrent delete that cleared active is reflected here.
        let active = await profileStore.activeProfile()
        activeID = active?.id
        listError = nil
    }

    /// Removes the profile with the given id from the store AND deletes
    /// its per-profile API key from the Keychain. Idempotent — removing
    /// an unknown id is a no-op against both stores. If the removed
    /// profile was active, the store clears the active id; this VM
    /// reflects that by setting `activeID = nil` to match.
    func deleteProfile(_ id: UUID) async {
        await profileStore.remove(id: id)
        do {
            try keychainService.deleteAPIKey(forProfile: id)
        } catch {
            // Keychain delete failures are surfaced but don't unwind the
            // store remove — leaving the profile listed with no key is
            // worse than an orphaned keychain row that costs ~32 bytes.
            Self.log.error("deleteAPIKey(forProfile:) failed: \(String(describing: error), privacy: .public)")
            listError = "Profile removed but its saved API key could not be cleared. You may need to delete it manually."
        }
        profiles.removeAll(where: { $0.id == id })
        if activeID == id { activeID = nil }
    }
}
