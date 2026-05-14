// Purpose: Editor-side operations on `WebDAVProfileListViewModel` —
// add/update profiles, save/delete per-profile keychain passwords, and
// Test Connection against form state. Feature #52 WI-4b.
//
// Mirrors `AISettingsViewModel+Editor.swift` shape (Feature #50 WI-6b)
// so the editor sheet's surface is parallel between WebDAV and AI
// profile flows. Split into its own file per rule 50 file-size guideline.
//
// Key decisions:
// - `addProfile(_:password:)` writes BOTH the profile + keychain entry
//   atomically (write keychain → if that succeeds, upsert profile). If
//   either step fails, `editorError` is set and the keychain row is
//   cleaned up (orphan prevention — same posture as bug #184).
// - `updateProfile(_:)` upserts the profile metadata only; password
//   round-trips go through the explicit Save Key / Delete Key buttons in
//   edit-mode. This mirrors AI editor — keychain is never touched
//   silently by an edit-form save action.
// - `savePassword(_:forID:)` / `deletePassword(forID:)` are edit-mode
//   only (the editor sheet hides the buttons in add-mode per bug #184
//   pattern). Both surface failures via `editorError`.
// - `testConnection(serverURL:username:password:)` builds a transient
//   `WebDAVClient` from the supplied values and calls `testConnection()`.
//   Returns `Result<Void, Error>` so the caller can render a localized
//   status string. Transport is injected via the closure parameter so
//   tests can pass a `MockWebDAVTransport` without hitting the wire.
//
// @coordinates-with: WebDAVProfileListViewModel.swift,
//   WebDAVServerProfile.swift, WebDAVServerProfileStore.swift,
//   WebDAVClient.swift

import Foundation

@MainActor
extension WebDAVProfileListViewModel {

    // MARK: - Add / Update

    /// Adds a new profile + writes its keychain password atomically.
    /// Keychain write happens first — if it fails, the profile is NOT
    /// upserted (no orphan profile pointing at a missing key). If the
    /// profile upsert fails (extremely unlikely — UserDefaults write
    /// doesn't throw), the keychain entry is cleaned up.
    ///
    /// On success: appends to `profiles`, clears `editorError`.
    /// On failure: sets `editorError`, leaves `profiles` unchanged.
    func addProfile(_ profile: WebDAVServerProfile, password: String) async {
        // Codex round-2 Medium fix: persist the TRIMMED password so the
        // stored value matches what Test Connection and the live backup
        // path send. Previously a user typing `" secret "` would store
        // `" secret "` in keychain while Test Connection trimmed first
        // and authed against the trimmed value — same-session passes
        // but the stored credential mismatches the form input.
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPassword.isEmpty else {
            editorError = "Password is empty — nothing to save."
            return
        }
        // Keychain first — if this throws, the profile is not added.
        do {
            try await profileStore.writePassword(trimmedPassword, for: profile.id)
        } catch {
            editorError = "Couldn't save the password to the keychain. (\(error.localizedDescription))"
            return
        }
        // Upsert profile. UserDefaults write doesn't throw, but if a
        // future store implementation does, clean up the keychain entry
        // so the caller doesn't end up with an orphan.
        await profileStore.upsert(profile)
        // Reload to pick up the actor-side state (profiles + any active
        // mutation from the store). Mirrors AI list VM reload-after-mutate.
        await loadProfiles()
        editorError = nil
    }

    /// Updates an existing profile's metadata (name, serverURL, username).
    /// Does NOT touch the keychain — password changes go through the
    /// explicit Save Key / Delete Key buttons in edit-mode (mirrors AI
    /// editor and matches bug #184's keychain-only-on-explicit-action
    /// rule).
    ///
    /// Codex round-1 Medium fix + round-2 Medium fix: reject unknown IDs
    /// (stale-view guard) via the store's single-hop `updateIfExists`.
    /// Previously did `loadAll → upsert` which raced against concurrent
    /// deletes between the two actor hops.
    func updateProfile(_ profile: WebDAVServerProfile) async {
        let replaced = await profileStore.updateIfExists(profile)
        guard replaced else {
            editorError = "This profile no longer exists. Close the editor and add a new server instead."
            return
        }
        await loadProfiles()
        editorError = nil
    }

    // MARK: - Password presence probe (Codex round-1 Low fix [6])

    /// Reads the stored password for a profile id through the VM's
    /// configured `profileStore` (and thus its injected KeychainService).
    /// Returns nil if no entry exists or the read failed.
    ///
    /// The editor sheet uses this to decide whether to send the
    /// stored password into Test Connection or require the user to
    /// type a fresh one — going through the VM keeps test-injected
    /// keychain configurations consistent.
    func readStoredPassword(for id: UUID) async -> String? {
        do {
            return try await profileStore.readPassword(for: id)
        } catch {
            return nil
        }
    }

    // MARK: - Per-profile keychain ops (edit-mode only)

    /// Writes a new password for an existing profile id. Edit-mode only.
    /// Empty / whitespace-only passwords are rejected before the keychain
    /// write to match the AI editor's "non-empty key required" gate.
    func savePassword(_ password: String, forID id: UUID) async {
        // Codex round-2 Medium fix: persist the TRIMMED password (was
        // persisting raw input; validation used trimmed but storage used
        // raw — see addProfile note above for the failure mode).
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            editorError = "Password is empty — nothing to save."
            return
        }
        do {
            try await profileStore.writePassword(trimmed, for: id)
            editorError = nil
        } catch {
            editorError = "Couldn't save the password to the keychain. (\(error.localizedDescription))"
        }
    }

    /// Deletes the keychain password entry for a profile id. Edit-mode
    /// only. Idempotent — deleting a missing entry is a no-op (the
    /// underlying `KeychainService.delete` tolerates miss).
    func deletePassword(forID id: UUID) async {
        do {
            try await profileStore.deletePassword(for: id)
            editorError = nil
        } catch {
            editorError = "Couldn't delete the password from the keychain. (\(error.localizedDescription))"
        }
    }

    // MARK: - Test Connection

    /// Runs a PROPFIND-based connection test against the supplied form
    /// state. Builds a transient `WebDAVClient` (or test transport via
    /// the `makeTransport` closure) and calls `testConnection()`. Returns
    /// `.success` on 200/207, `.failure(WebDAVError)` otherwise.
    ///
    /// The form state is what's tested — not the stored profile — so
    /// unsaved edits in the editor sheet exercise correctly (same pattern
    /// as AI editor's testConnection).
    ///
    /// `makeTransport` defaults to the production `WebDAVClient` path;
    /// tests inject a `MockWebDAVTransport` to validate HTTP-shape
    /// branches without hitting the wire.
    func testConnection(
        serverURL: String,
        username: String,
        password: String,
        makeTransport: (URL, String, String) -> WebDAVTransport = { url, user, pass in
            WebDAVClient(serverURL: url, username: user, password: pass)
        }
    ) async -> Result<Void, Error> {
        guard let url = WebDAVProfileListViewModel.validatedServerURL(from: serverURL) else {
            return .failure(WebDAVTestConnectionError.invalidURL)
        }
        // Codex round-1 Medium fix [4]: trim before emptiness check so
        // whitespace-only username/password can't slip through. The Save
        // path already trims; this path must match.
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUser.isEmpty else {
            return .failure(WebDAVTestConnectionError.missingUsername)
        }
        guard !trimmedPassword.isEmpty else {
            return .failure(WebDAVTestConnectionError.missingPassword)
        }
        let transport = makeTransport(url, trimmedUser, trimmedPassword)
        do {
            try await transport.testConnection()
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    // MARK: - URL validation (Codex round-1 High fix [1])

    /// Validates a WebDAV server URL. Requires:
    /// - non-empty after trim
    /// - parses to `URL`
    /// - scheme is `http` or `https` (bug #110 + NSAllowsArbitraryLoads)
    /// - non-empty host
    ///
    /// Returns the parsed `URL` on success, nil on any failure. Reused
    /// by `canSave`, `save()`, `testConnection`, and the field
    /// `.onChange` validator in the editor sheet so all four paths agree.
    static func validatedServerURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let url = URL(string: trimmed) else { return nil }
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        guard let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}

/// Errors specific to the WebDAV editor's Test Connection form gating.
/// Wire-level failures bubble up as `WebDAVError`; these cover the
/// pre-flight form-state checks the editor enforces before constructing
/// a transport.
enum WebDAVTestConnectionError: LocalizedError, Equatable {
    case invalidURL
    case missingUsername
    case missingPassword

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Server URL is missing or malformed."
        case .missingUsername: return "Username is empty."
        case .missingPassword: return "Password is empty."
        }
    }
}

