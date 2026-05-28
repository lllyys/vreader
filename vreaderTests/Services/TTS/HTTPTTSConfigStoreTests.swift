// Purpose: Tests for HTTPTTSConfigStore (feature #72 WI-1) — loading the
// persisted HTTP cloud-TTS config + splicing in the Keychain API key, and the
// `loadValidConfig()` selection predicate. Uses an isolated UserDefaults suite
// + a stub keychain so no real Keychain / standard defaults are touched.
//
// @coordinates-with: HTTPTTSConfigStore.swift, HTTPTTSConfig.swift, GH #1174

import Testing
import Foundation
@testable import vreader

@Suite("HTTPTTSConfigStore (Feature #72 WI-1)")
struct HTTPTTSConfigStoreTests {

    private struct StubKeychain: HTTPTTSKeychainReading {
        let value: String?
        func readString(forAccount account: String) throws -> String? { value }
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "http-tts-store-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    /// Persists a config the way `HTTPTTSSettingsView.saveConfig` does: JSON
    /// with the API key blanked (the real key lives in the Keychain).
    private func persist(_ config: HTTPTTSConfig, to defaults: UserDefaults) {
        var stored = config
        stored.apiKey = ""
        let data = try! JSONEncoder().encode(stored)
        defaults.set(data, forKey: HTTPTTSConfigStore.configKey)
    }

    private func validConfig() -> HTTPTTSConfig {
        HTTPTTSConfig(endpoint: "https://tts.example.com/v1/speak",
                      apiKey: "REAL-KEY", voice: "en-US-JennyNeural",
                      provider: .azure(region: "eastus"))
    }

    @Test func load_returnsNilWhenNothingPersisted() {
        let store = HTTPTTSConfigStore(defaults: makeDefaults(), keychain: StubKeychain(value: nil))
        #expect(store.load() == nil)
    }

    @Test func load_returnsConfigWithKeychainKeySpliced() {
        let defaults = makeDefaults()
        persist(validConfig(), to: defaults)
        let store = HTTPTTSConfigStore(defaults: defaults, keychain: StubKeychain(value: "REAL-KEY"))
        let loaded = store.load()
        #expect(loaded?.endpoint == "https://tts.example.com/v1/speak")
        #expect(loaded?.voice == "en-US-JennyNeural")
        #expect(loaded?.apiKey == "REAL-KEY", "the API key must come from the Keychain, not UserDefaults")
    }

    @Test func loadValidConfig_returnsConfigWhenValid() {
        let defaults = makeDefaults()
        persist(validConfig(), to: defaults)
        let store = HTTPTTSConfigStore(defaults: defaults, keychain: StubKeychain(value: "REAL-KEY"))
        #expect(store.loadValidConfig()?.validate() == .valid)
    }

    @Test func loadValidConfig_returnsNilWhenKeychainKeyMissing() {
        // Config persisted but the Keychain has no key → apiKey "" → invalid.
        let defaults = makeDefaults()
        persist(validConfig(), to: defaults)
        let store = HTTPTTSConfigStore(defaults: defaults, keychain: StubKeychain(value: nil))
        #expect(store.load()?.apiKey == "")
        #expect(store.loadValidConfig() == nil)
    }

    @Test func loadValidConfig_returnsNilWhenEndpointInvalid() {
        let defaults = makeDefaults()
        persist(HTTPTTSConfig(endpoint: "not-a-url", apiKey: "k", voice: "v"), to: defaults)
        let store = HTTPTTSConfigStore(defaults: defaults, keychain: StubKeychain(value: "k"))
        #expect(store.loadValidConfig() == nil)
    }

    @Test func loadValidConfig_returnsNilWhenUnconfigured() {
        let store = HTTPTTSConfigStore(defaults: makeDefaults(), keychain: StubKeychain(value: "k"))
        #expect(store.loadValidConfig() == nil)
    }
}
