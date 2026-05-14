// Purpose: ViewModel for the WebDAV Server Profile list. Owns the
// observable `profiles` + `activeID` mirror of `WebDAVServerProfileStore`,
// plus the list operations the UI surfaces (loadProfiles, setActive,
// deleteProfile). Feature #52 WI-4a.
//
// Mirrors `AISettingsViewModel`'s profile-list slice (Feature #50 WI-6a):
// same Observable @MainActor shape, same `loadSnapshot()` atomic-read
// hop, same "reject unknown active id" guard, same "clear keychain on
// delete" semantics. The split into a dedicated list ViewModel (vs
// folding into a hypothetical `BackupSettingsViewModel`) keeps the
// surface narrow and mirrors `AISettingsViewModel`'s focused contract.
//
// Key decisions:
// - `@Observable @MainActor` for SwiftUI binding.
// - Uses `WebDAVServerProfileStore.shared` by default; tests inject a
//   separate store instance via the init parameter (shared-instance
//   contract from `WebDAVServerProfileStore.swift` header).
// - `loadProfiles()` uses `loadSnapshot()` (single actor hop) so a
//   concurrent mutation can't publish a list that disagrees with the
//   active id. Mirror of AISettingsViewModel Round-1 audit finding [1].
// - `setActive(_:)` rejects ids not in `profiles` rather than writing a
//   dangling reference. The UI only renders rows for ids in `profiles`,
//   so an unknown id always indicates a stale view or a programmer
//   error. Mirror of AISettingsViewModel Round-1 audit finding [2].
// - `deleteProfile(_:)` removes from the store (store side already
//   clears the keychain entry per `WebDAVServerProfileStore.remove`).
//   No separate VM-side keychain delete because the store handles it.
//
// WI-4b will add editor operations (add / update / save-password /
// delete-password / test-connection) — likely in a `+Editor` extension
// per the AI ViewModel split precedent.
//
// @coordinates-with: WebDAVServerProfileStore.swift,
//   WebDAVServerProfile.swift, WebDAVServerProfileListView.swift

import Foundation
import Observation
import OSLog

/// ViewModel for the WebDAV server profile list screen.
@Observable
@MainActor
final class WebDAVProfileListViewModel {

    // MARK: - Dependencies

    let profileStore: WebDAVServerProfileStore

    static let log = Logger(subsystem: "com.vreader.app", category: "WebDAVProfileList")

    // MARK: - List State

    /// Current saved profiles, loaded on the most recent `loadProfiles()`.
    /// Empty list before first load.
    private(set) var profiles: [WebDAVServerProfile] = []

    /// The id of the currently-active profile, or nil if none active OR
    /// the persisted active id no longer resolves to a known profile.
    private(set) var activeID: UUID?

    /// Last error from a list operation. nil after a successful op.
    /// Surfaces via an `.alert(...)` binding in the list view.
    var listError: String?

    /// Last error from an editor operation (add/update/save-key/delete-key
    /// /test-connection). nil after success. The editor sheet surfaces this
    /// via an `.alert(...)` binding mirroring the AI editor pattern.
    /// Set by methods in `WebDAVProfileListViewModel+Editor.swift` (WI-4b).
    var editorError: String?

    // MARK: - Initialization

    init(profileStore: WebDAVServerProfileStore = .shared) {
        self.profileStore = profileStore
    }

    // MARK: - List Operations

    /// Loads the current profile list and active id from the store via
    /// an atomic `loadSnapshot()` hop. Filters out a dangling active id
    /// (one that doesn't resolve to any profile in the loaded list) so
    /// the UI never highlights an absent row.
    func loadProfiles() async {
        let snapshot = await profileStore.loadSnapshot()
        profiles = snapshot.profiles
        if let id = snapshot.activeID,
           snapshot.profiles.contains(where: { $0.id == id }) {
            activeID = id
        } else {
            activeID = nil
        }
        listError = nil
    }

    /// Sets the currently-active profile by id. Passing nil clears active.
    /// Rejects ids not in the loaded `profiles` list (stale-view guard).
    func setActive(_ id: UUID?) async {
        if let id, !profiles.contains(where: { $0.id == id }) {
            return
        }
        await profileStore.setActiveProfileID(id)
        let active = await profileStore.activeProfile()
        activeID = active?.id
        listError = nil
    }

    /// Removes the profile with the given id from the store. Store's
    /// `remove(id:)` also clears the per-profile keychain password entry.
    /// Idempotent — removing an unknown id is a no-op.
    func deleteProfile(_ id: UUID) async {
        await profileStore.remove(id: id)
        profiles.removeAll(where: { $0.id == id })
        if activeID == id { activeID = nil }
        listError = nil
    }
}
