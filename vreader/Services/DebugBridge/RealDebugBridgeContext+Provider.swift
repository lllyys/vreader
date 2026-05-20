// Purpose: `provider` command handler for the vreader-debug:// URL scheme
// (Bug #243). Adds / removes / clears `ProviderProfile`s and their per-
// profile Keychain API keys so verification flows can configure an AI
// provider without driving Settings → AI through computer-use.
//
// Why this is a separate extension file:
//   The handler depends on AI-feature types (`ProviderProfile`,
//   `ProviderProfileStore`, `KeychainService+ProviderProfile`) that the
//   main `RealDebugBridgeContext.swift` doesn't otherwise reach. Splitting
//   keeps the parent file's surface area unchanged for unrelated commands
//   and respects the 300-line LOC guideline.
//
// DEBUG-only — entire file compiled out of Release builds.
//
// @coordinates-with: DebugCommand.swift (ProviderAction parsing),
//   DebugBridge.swift (dispatcher), RealDebugBridgeContext.swift (deps),
//   ProviderProfileStore.swift (actor), KeychainService+ProviderProfile.swift.

#if DEBUG

import Foundation

extension RealDebugBridgeContext {

    /// Dispatch the `provider` sub-action. Each branch is idempotent and
    /// best-effort logged so a verification run can pin failure causes by
    /// reading `snapshot.lastError` (the bridge records this method's
    /// throws there).
    func provider(action: DebugCommand.ProviderAction) async throws {
        switch action {
        case .add(let name, let kindURL, let endpoint, let apiKey, let model, let active):
            try await addProvider(
                name: name,
                kindURL: kindURL,
                endpoint: endpoint,
                apiKey: apiKey,
                model: model,
                explicitlyActive: active
            )

        case .remove(let name):
            try await removeProvider(name: name)

        case .clear:
            try await clearProviders()
        }
    }

    // MARK: - add

    /// Insert (or replace) a profile + persist its API key. Mirrors the
    /// in-app `AISettingsViewModel.addProfile(_:apiKey:)` flow:
    /// 1. **Reuse existing UUID by display name** when one already exists so
    ///    re-running an `add` URL is idempotent. `remove(name:)` would
    ///    otherwise be non-deterministic when multiple profiles shared a
    ///    name (Round-1 Codex audit Medium finding).
    /// 2. Trim the API key (mirroring the production Settings flow) so a
    ///    host-side quoting / encoding accident doesn't leave whitespace
    ///    in Keychain.
    /// 3. Save the keychain entry first so a half-saved profile (listed
    ///    without a retrievable key) can't happen.
    /// 4. `upsert` the profile into the store.
    /// 5. Auto-promote to active if `explicitlyActive` is true OR if no
    ///    profile is currently active (so a single `add` URL leaves the
    ///    harness with an immediately-usable configuration).
    private func addProvider(
        name: String,
        kindURL: DebugCommand.ProviderActionKind,
        endpoint: URL,
        apiKey: String,
        model: String?,
        explicitlyActive: Bool
    ) async throws {
        let kind = Self.providerKind(from: kindURL)
        let resolvedModel = model ?? kind.defaultModel
        // Round-1 Codex audit Medium fix: replace-by-name so re-running the
        // same `add` URL is idempotent. Without this, every re-run would
        // create a new UUID + duplicate name, breaking `remove(name:)`'s
        // ability to clean up by name. We keep the existing UUID + key
        // account when a name match exists.
        let existing = (await providerStore.loadAll()).first(where: { $0.name == name })
        let profileID = existing?.id ?? UUID()
        let profile = ProviderProfile(
            id: profileID,
            name: name,
            kind: kind,
            baseURL: endpoint,
            model: resolvedModel,
            temperature: 0.7,
            maxTokens: 4096
        )

        // Round-1 Codex audit Low fix: trim whitespace + newlines from the
        // API key so a host-side quoting/encoding mistake doesn't produce
        // avoidable auth failures. Matches `AISettingsViewModel.addProfile`.
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        // Save key first. Failure here aborts the whole add (no orphan
        // profile in the store).
        try keychain.saveAPIKey(trimmedKey, forProfile: profileID)

        await providerStore.upsert(profile)

        // Decide active selection. `explicitlyActive` wins over auto-promote.
        let snapshot = await providerStore.loadSnapshot()
        if explicitlyActive {
            await providerStore.setActiveProfileID(profileID)
        } else if snapshot.activeID == nil {
            await providerStore.setActiveProfileID(profileID)
        }

        log.info(
            "provider.add: name=\(name, privacy: .public) kind=\(kind.rawValue, privacy: .public) model=\(resolvedModel, privacy: .public) active=\(explicitlyActive) replaced=\(existing != nil)"
        )
    }

    // MARK: - remove

    /// Delete the profile with display name `name` (case-sensitive). No-op
    /// when no profile has that name. Also deletes the per-profile Keychain
    /// entry. Mirrors the idempotency posture of `ProviderProfileStore.remove`.
    private func removeProvider(name: String) async throws {
        let profiles = await providerStore.loadAll()
        guard let target = profiles.first(where: { $0.name == name }) else {
            log.info("provider.remove: no profile named \(name, privacy: .public) — no-op")
            return
        }
        // Delete the keychain entry first. If that throws, the profile
        // still exists in the store — better than the opposite where the
        // key would outlive its owner.
        try keychain.deleteAPIKey(forProfile: target.id)
        await providerStore.remove(id: target.id)
        log.info("provider.remove: removed name=\(name, privacy: .public) id=\(target.id.uuidString, privacy: .public)")
    }

    // MARK: - clear

    /// Remove every profile + every per-profile Keychain entry + clear the
    /// active selection. Idempotent. Used by verification flows that need
    /// a known-empty starting state (mirrors `reset` for the AI subsystem).
    ///
    /// **Concurrency caveat (Round-1 Codex audit Low, accepted)**: this is
    /// snapshot-based. An out-of-band writer using `ProviderProfileStore.shared`
    /// that lands a new profile between `loadAll()` and the removal loop
    /// would survive `clear`. The `DebugBridge` itself serializes its own
    /// commands, and verification flows do not exercise the AI subsystem in
    /// parallel with `provider?action=clear`, so this gap is theoretical.
    /// If a future flow needs strict-atomic clear, the right fix is on the
    /// store side (an actor-level `removeAll()`), not in the bridge.
    private func clearProviders() async throws {
        let profiles = await providerStore.loadAll()
        // Delete keychain entries first so a mid-loop error still leaves
        // an in-consistent state where the store has zero profiles whose
        // keys are still present (caller can retry to clean up).
        for profile in profiles {
            try keychain.deleteAPIKey(forProfile: profile.id)
        }
        // Wipe the list one entry at a time through the store's public
        // mutators so each delete posts `.providerProfilesDidChange` (UI
        // observers get incremental updates instead of one big jump).
        for profile in profiles {
            await providerStore.remove(id: profile.id)
        }
        // `remove(id:)` clears active when the removed profile was the
        // active one; this final call covers any pathological case where
        // active was set to a non-existent id (e.g., a race between the
        // loop and a concurrent setActive).
        await providerStore.setActiveProfileID(nil)
        log.info("provider.clear: removed \(profiles.count) profile(s) + keys")
    }

    // MARK: - Helpers

    /// Map the URL-grammar kind to the in-app `ProviderKind`. 1:1, lossless.
    /// Centralized here so a future kind add only touches one site.
    nonisolated static func providerKind(
        from urlKind: DebugCommand.ProviderActionKind
    ) -> ProviderKind {
        switch urlKind {
        case .openAICompatible: return .openAICompatible
        case .anthropicNative:  return .anthropicNative
        }
    }
}

#endif
