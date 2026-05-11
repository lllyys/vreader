// Purpose: ViewModel for the in-reader AI provider picker — feature #50
// WI-7. Lighter-weight than AISettingsViewModel because the in-reader
// surface doesn't host editor flows (add/edit profile, save key, test
// connection). The picker just reflects the saved profile list and
// lets the user flip the active selection from inside the reader.
//
// Lives next to the View (`AIProviderPicker.swift`) per the plan's
// "ViewModel separated from View" guidance (Gate-2 round-1 audit
// finding [8]); two separate files keep the View under 300 LOC and
// keep the @Observable-bearing type unit-testable without UI.
//
// Key decisions:
// - @Observable + @MainActor (iOS 17+; matches AISettingsViewModel and
//   AIChatViewModel precedent).
// - Backed by the shared `ProviderProfileStore` actor (round-2 plan
//   audit finding [2]). Tests inject a per-test store via the init
//   parameter.
// - `loadProfiles()` uses `loadSnapshot()` for a single actor hop (the
//   pattern WI-6a established to prevent split-read races between
//   `loadAll()` and `activeProfile()`).
// - Defensive: if the persisted activeID doesn't resolve to a present
//   profile, `activeID` surfaces as nil (mirrors WI-6a
//   AISettingsViewModel.loadProfiles).
// - `setActive` rejects unknown ids (same WI-6a contract).
//
// @coordinates-with: AIProviderPicker.swift, ProviderProfileStore.swift,
//   AISettingsViewModel.swift

import Foundation
import Observation

/// ViewModel for the in-reader AI provider picker.
@Observable
@MainActor
final class AIProviderPickerViewModel {

    // MARK: - Dependencies

    private let store: ProviderProfileStore

    // MARK: - Published state

    /// Currently saved provider profiles. Empty before first
    /// `loadProfiles()` call.
    private(set) var profiles: [ProviderProfile] = []

    /// The id of the active profile, or nil when no selection / when
    /// the persisted active id doesn't resolve to a present profile.
    private(set) var activeID: UUID?

    /// Convenience for the View's empty-state branch.
    var hasProfiles: Bool { !profiles.isEmpty }

    /// NotificationCenter observer for live store-change resync (WI-7
    /// round-1 audit finding [1]). Set once in init after all stored
    /// properties are initialized so `[weak self]` capture is valid;
    /// released in deinit.
    ///
    /// `nonisolated(unsafe)` because deinit of a @MainActor type may
    /// run on any queue under Swift 6 strict, and we need to call
    /// `NotificationCenter.removeObserver(_:)` from there. The plain
    /// `nonisolated` annotation is rejected on mutable stored
    /// properties of `@Observable` classes (the macro auto-generates
    /// Observation tracking that conflicts). The token is class-bound
    /// (Sendable) and NotificationCenter is thread-safe; the property
    /// has exactly one post-init write (`installObserver`) and one
    /// deinit read, so there's no contention.
    nonisolated(unsafe) private var didChangeObserver: NSObjectProtocol?

    // MARK: - Initialization

    init(store: ProviderProfileStore = .shared) {
        self.store = store
        // Install observer AFTER stored-property init completes so the
        // `[weak self]` capture is valid.
        installObserver()
    }

    private func installObserver() {
        didChangeObserver = NotificationCenter.default.addObserver(
            forName: .providerProfilesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.loadProfiles()
            }
        }
    }

    deinit {
        if let token = didChangeObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // MARK: - Operations

    /// Loads the current profile list + active id from the store via a
    /// single actor hop. Safe to call on every reader-panel appearance;
    /// the store is the source of truth and the call is idempotent.
    func loadProfiles() async {
        let snapshot = await store.loadSnapshot()
        profiles = snapshot.profiles
        if let id = snapshot.activeID,
           snapshot.profiles.contains(where: { $0.id == id }) {
            activeID = id
        } else {
            activeID = nil
        }
    }

    /// Switches the active profile. Passing nil clears the active
    /// selection. Unknown ids (not in the current `profiles` list)
    /// are rejected — mirrors `AISettingsViewModel.setActive`'s
    /// defense against stale-view writes.
    func setActive(_ id: UUID?) async {
        if let id, !profiles.contains(where: { $0.id == id }) {
            return
        }
        await store.setActiveProfileID(id)
        let active = await store.activeProfile()
        activeID = active?.id
    }
}
