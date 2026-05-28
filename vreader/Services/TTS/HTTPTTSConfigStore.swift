// Purpose: Feature #72 WI-1 — load the persisted HTTP cloud-TTS configuration
// (UserDefaults `httpTTSConfig`, config minus API key) and inject the API key
// from the Keychain (account `com.vreader.httpTTS.apiKey`), so the live TTS
// pipeline (`TTSService.defaultSynthesizer()`, WI-3) can decide whether a valid
// cloud provider is configured. The persistence shape mirrors
// `HTTPTTSSettingsView`'s save/load exactly (same keys + Keychain account).
//
// Key decisions:
// - Reads through a `HTTPTTSKeychainReading` seam (prod: `KeychainService`) +
//   an injected `UserDefaults`, so the loader is unit-testable without touching
//   the real Keychain / standard defaults.
// - `load()` returns the persisted config with the Keychain key spliced back in
//   (it may still be invalid — caller checks `validate()`); `loadValidConfig()`
//   is the selection predicate (`validate() == .valid`).
//
// @coordinates-with: HTTPTTSConfig.swift, HTTPTTSSettingsView.swift (the writer),
//   KeychainService.swift, TTSService.swift (WI-3 consumer)

import Foundation

/// The Keychain read surface `HTTPTTSConfigStore` needs — a seam so tests can
/// stub the API-key read without the real Keychain.
protocol HTTPTTSKeychainReading {
    func readString(forAccount account: String) throws -> String?
}

extension KeychainService: HTTPTTSKeychainReading {}

/// Loads the persisted `HTTPTTSConfig` + its Keychain-stored API key.
struct HTTPTTSConfigStore {

    /// UserDefaults key holding the JSON-encoded config (API key blanked).
    /// Must match `HTTPTTSSettingsView.configKey`.
    static let configKey = "httpTTSConfig"
    /// Keychain account holding the API key. Must match
    /// `HTTPTTSSettingsView.keychainAccount`.
    static let keychainAccount = "com.vreader.httpTTS.apiKey"

    private let defaults: UserDefaults
    private let keychain: HTTPTTSKeychainReading

    init(defaults: UserDefaults = .standard, keychain: HTTPTTSKeychainReading = KeychainService()) {
        self.defaults = defaults
        self.keychain = keychain
    }

    /// The persisted config with the Keychain API key spliced in, or `nil` when
    /// no config has been saved. The returned config may be INVALID — the
    /// caller calls `validate()` (or uses `loadValidConfig()`).
    func load() -> HTTPTTSConfig? {
        guard let data = defaults.data(forKey: Self.configKey),
              var config = try? JSONDecoder().decode(HTTPTTSConfig.self, from: data)
        else { return nil }
        config.apiKey = (try? keychain.readString(forAccount: Self.keychainAccount)) ?? ""
        return config
    }

    /// The persisted config IFF it validates as `.valid` — the predicate
    /// `TTSService.defaultSynthesizer()` (WI-3) uses to select the cloud
    /// synthesizer over the on-device one. `nil` when unconfigured or invalid.
    func loadValidConfig() -> HTTPTTSConfig? {
        guard let config = load(), config.validate() == .valid else { return nil }
        return config
    }
}
