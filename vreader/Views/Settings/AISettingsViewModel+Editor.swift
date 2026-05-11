// Purpose: Editor-side operations for AISettingsViewModel — feature #50
// WI-6b. Split out of the core VM to keep both files under the ~300-line
// guideline (mirrors AnthropicProvider+Streaming.swift's rationale).
//
// What lives here:
// - addProfile(_:apiKey:) — insert + save API key + auto-set active if
//   first profile. Atomic: if the keychain save fails the profile is
//   not inserted (round-1 audit fix [4] — no half-saved profiles).
// - updateProfile(_:) — mutate an existing profile by id (guards against
//   stale-view writes).
// - saveAPIKey(_:forID:) — write the per-profile keychain entry; empty
//   string falls through to deleteAPIKey(forID:).
// - deleteAPIKey(forID:) — clear the per-profile keychain entry.
// - testConnection(profile:) — construct the provider matching the
//   passed-in profile's kind (mirrors AIService.resolveProvider's
//   dispatch), send a single ping through `sendRequest`. Uses the VM's
//   injected URLSession so tests can stub the HTTP path via a custom
//   URLProtocol. The caller passes a fresh `ProviderProfile` built from
//   live UI form state, not a lookup by id — that's how the sheet can
//   test unsaved edits before committing (round-1 audit fix [1]).
// - validateBaseURL(_:) — `nonisolated static` helper for the editor
//   sheet to call before submit. HTTPS-only except localhost
//   (`localhost` / `127.0.0.1`); IPv6 loopback intentionally excluded
//   to match the providers' runtime preflight (round-1 audit fix [3]).
//
// @coordinates-with: AISettingsViewModel.swift, AIProviderEditSheet.swift,
//   AIProvider.swift (OpenAICompatibleProvider), AnthropicProvider.swift

import Foundation

extension AISettingsViewModel {

    // MARK: - Profile Editor Operations

    /// Inserts a new profile and (if `apiKey` is non-empty) saves the API
    /// key to the per-profile Keychain account. If this is the first
    /// profile, sets it as active so the user gets an immediately-usable
    /// configuration. Caller is expected to validate the profile fields
    /// first via `validateBaseURL` etc. — this method does not re-check.
    ///
    /// Failure mode: if the keychain save fails, the profile is NOT
    /// inserted into the store — a half-saved profile (listed but no key
    /// retrievable) is worse than a clean failure that the user can
    /// retry.
    func addProfile(_ profile: ProviderProfile, apiKey: String) async {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            do {
                try keychainService.saveAPIKey(trimmedKey, forProfile: profile.id)
            } catch {
                editorError = "Failed to save API key: \(error.localizedDescription)"
                return
            }
        }
        await profileStore.upsert(profile)
        let snapshot = await profileStore.loadSnapshot()
        // If there's no active selection yet, the newly-added profile
        // becomes active so AI features are immediately usable.
        if snapshot.activeID == nil {
            await profileStore.setActiveProfileID(profile.id)
            let final = await profileStore.loadSnapshot()
            _setProfiles(final.profiles, activeID: final.activeID)
        } else {
            _setProfiles(snapshot.profiles, activeID: snapshot.activeID)
        }
        editorError = nil
    }

    /// Mutates an existing profile by id. The caller passes a fully-
    /// formed ProviderProfile with the same id and updated fields. If the
    /// id isn't in the current profile list, sets `editorError` and
    /// returns — guards against stale-view writes that would otherwise
    /// insert a new profile under the same id.
    func updateProfile(_ profile: ProviderProfile) async {
        guard profiles.contains(where: { $0.id == profile.id }) else {
            editorError = "Cannot update an unknown profile. Reload and try again."
            return
        }
        await profileStore.upsert(profile)
        let snapshot = await profileStore.loadSnapshot()
        _setProfiles(snapshot.profiles, activeID: snapshot.activeID)
        editorError = nil
    }

    /// Saves an API key to the per-profile Keychain account. Used by the
    /// editor sheet when the user changes the API key without changing
    /// other profile fields. An empty `key` (after trimming) is treated
    /// as "clear the key" — calls deleteAPIKey(forID:) instead of saving
    /// an empty string.
    func saveAPIKey(_ key: String, forID id: UUID) async {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            await deleteAPIKey(forID: id)
            return
        }
        do {
            try keychainService.saveAPIKey(trimmed, forProfile: id)
            editorError = nil
        } catch {
            editorError = "Failed to save API key: \(error.localizedDescription)"
        }
    }

    /// Deletes the per-profile API key from the Keychain. Idempotent —
    /// deleting a non-existent key is not an error.
    func deleteAPIKey(forID id: UUID) async {
        do {
            try keychainService.deleteAPIKey(forProfile: id)
            editorError = nil
        } catch {
            editorError = "Failed to delete API key: \(error.localizedDescription)"
        }
    }

    /// Sends a one-token "ping" through the provider matching the given
    /// profile's kind. Returns `.success` if the request reaches the
    /// provider and gets a 2xx response, `.failure` with a structured
    /// AIError otherwise (e.g. `apiKeyMissing`, `unauthorized`, network
    /// errors).
    ///
    /// Round-1 audit finding [1]: previously this method took only an
    /// `id` and re-looked-up the stored profile, which meant the sheet
    /// could not test unsaved edits. Now the caller passes the candidate
    /// `ProviderProfile` directly (built from the sheet's current form
    /// state); we only consult the keychain for the API key. The id is
    /// the keychain account key, not a profile-list lookup.
    ///
    /// Dispatches on `profile.kind` exactly the same way
    /// `AIService.resolveProvider` does (OpenAICompatibleProvider /
    /// AnthropicProvider). Uses the VM's injected `urlSession`
    /// (production `.shared`; tests inject a stubbed session via init).
    func testConnection(profile: ProviderProfile) async -> Result<Void, Error> {
        let apiKey: String
        do {
            guard let key = try keychainService.readAPIKey(forProfile: profile.id), !key.isEmpty else {
                return .failure(AIError.apiKeyMissing)
            }
            apiKey = key
        } catch {
            return .failure(error)
        }

        let provider: any AIProvider
        switch profile.kind {
        case .openAICompatible:
            provider = OpenAICompatibleProvider(
                baseURL: profile.baseURL,
                apiKey: apiKey,
                model: profile.model,
                session: urlSession
            )
        case .anthropicNative:
            // Audit fix: pass the profile's own maxTokens so the test
            // exercises the same runtime config AIService.resolveProvider
            // will build at request time. Previously hardcoded to 1.
            provider = AnthropicProvider(
                baseURL: profile.baseURL,
                apiKey: apiKey,
                model: profile.model,
                maxTokens: profile.maxTokens,
                session: urlSession
            )
        }

        // Minimal request — empty context + "ping" prompt. Providers
        // build their own message lists from this; we only care whether
        // the call returns or throws.
        let request = AIRequest(
            actionType: .questionAnswer,
            bookFingerprint: nil,
            locator: nil,
            contextText: "",
            userPrompt: "ping",
            targetLanguage: nil,
            promptVersion: "test-connection-v1"
        )

        do {
            _ = try await provider.sendRequest(request)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    // MARK: - URL Validation (static helper)

    /// Validates a profile baseURL string. Returns nil on valid, or a
    /// user-readable error message on invalid. HTTPS-only except for
    /// localhost (`localhost` / `127.0.0.1`). The accepted-loopback set
    /// MUST match the runtime preflight in `OpenAICompatibleProvider`
    /// and `AnthropicProvider`; round-1 audit finding [3] caught drift
    /// when this validator accepted `::1` / `[::1]` while the providers
    /// rejected them, producing profiles the editor saved but requests
    /// could never send.
    ///
    /// `nonisolated` so callers off the main actor (including
    /// Swift Testing tests) can validate without an `await`. The body
    /// touches no actor state — it's a pure string transform.
    nonisolated static func validateBaseURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "URL cannot be empty." }
        guard let url = URL(string: trimmed) else {
            return "Please enter a valid URL."
        }
        guard let scheme = url.scheme?.lowercased() else {
            return "URL must include a scheme (e.g., https://)."
        }
        if scheme == "http" {
            let host = url.host?.lowercased() ?? ""
            let isLocalhost = host == "localhost" || host == "127.0.0.1"
            guard isLocalhost else {
                return "Only HTTPS URLs are allowed. HTTP is permitted only for localhost."
            }
            return nil
        }
        if scheme != "https" {
            return "URL must use HTTPS (or HTTP for localhost only)."
        }
        return nil
    }
}
