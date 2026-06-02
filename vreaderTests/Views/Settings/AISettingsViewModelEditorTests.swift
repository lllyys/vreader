// Purpose: Tests for AISettingsViewModel's editor-side operations
// (feature #50 WI-6b) — addProfile, updateProfile, saveAPIKey,
// deleteAPIKey, testConnection, and the static validateBaseURL helper.
//
// List-side operations (loadProfiles, setActive, deleteProfile) are
// covered by AISettingsViewModelMultiProfileTests. Bug #167 regression
// + consent are covered by AISettingsViewModelTests. This file is the
// editor-side counterpart.
//
// Each test builds a fresh `ProviderProfileStore` backed by per-test
// `MockPreferenceStore` + isolated `KeychainService` (a unique
// `serviceIdentifier`). HTTP-touching tests (`testConnection`) inject a
// stubbed `URLSession` via `EditorStubURLProtocol`.
//
// @coordinates-with: AISettingsViewModel.swift,
//   AISettingsViewModel+Editor.swift, AIProvider.swift,
//   AnthropicProvider.swift, ProviderProfileStore.swift,
//   KeychainService+ProviderProfile.swift

import Testing
import Foundation
@testable import vreader

// MARK: - Stub URLProtocol

/// Test-only URLProtocol that returns canned responses for testConnection
/// tests. Distinct from `AnthropicStubURLProtocol` to avoid shared static
/// handler-state races when both suites run in parallel.
final class EditorStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var capturedRequests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.capturedRequests.append(request)
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func reset() {
        requestHandler = nil
        capturedRequests = []
    }
}

private func makeStubSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [EditorStubURLProtocol.self]
    return URLSession(configuration: config)
}

@Suite("AISettingsViewModel editor (WI-6b)")
struct AISettingsViewModelEditorTests {

    // MARK: - Helpers

    private static func makeIsolatedDeps(
        urlSession: URLSession = .shared
    ) -> (FeatureFlags, AIConsentManager, KeychainService, ProviderProfileStore, URLSession) {
        let flags = FeatureFlags(environment: .prod)
        let consent = AIConsentManager(defaults: UserDefaults(
            suiteName: "com.vreader.test.consent.\(UUID().uuidString)"
        )!)
        let keychain = KeychainService(
            serviceIdentifier: "com.vreader.test.\(UUID().uuidString)"
        )
        let store = ProviderProfileStore(
            preferences: MockPreferenceStore(),
            migrator: DefaultProviderProfileMigrator(),
            keychain: keychain
        )
        return (flags, consent, keychain, store, urlSession)
    }

    @MainActor
    private static func makeVM(
        flags: FeatureFlags, consent: AIConsentManager,
        keychain: KeychainService, store: ProviderProfileStore,
        urlSession: URLSession
    ) -> AISettingsViewModel {
        AISettingsViewModel(
            featureFlags: flags,
            consentManager: consent,
            keychainService: keychain,
            profileStore: store,
            urlSession: urlSession
        )
    }

    private static func makeProfile(
        id: UUID = UUID(),
        name: String = "Test Profile",
        kind: ProviderKind = .openAICompatible
    ) -> ProviderProfile {
        ProviderProfile(
            id: id, name: name, kind: kind,
            baseURL: kind.defaultBaseURL,
            model: kind.defaultModel,
            temperature: 0.7,
            maxTokens: 2048
        )
    }

    // MARK: - addProfile

    @Test @MainActor func addProfile_emptyList_insertsAndSetsActive() async throws {
        let (flags, consent, keychain, store, session) = Self.makeIsolatedDeps()
        let vm = Self.makeVM(flags: flags, consent: consent, keychain: keychain, store: store, urlSession: session)
        await vm.loadProfiles()

        let p = Self.makeProfile(name: "First")
        await vm.addProfile(p, apiKey: "sk-test-key")

        #expect(vm.profiles.count == 1)
        #expect(vm.profiles.first?.id == p.id)
        #expect(vm.activeID == p.id, "First profile added must be set active automatically")
        #expect(vm.editorError == nil)

        // Store + keychain should both reflect the insert.
        let storeProfiles = await store.loadAll()
        #expect(storeProfiles.count == 1)
        #expect(try keychain.readAPIKey(forProfile: p.id) == "sk-test-key")
    }

    @Test @MainActor func addProfile_secondProfile_leavesExistingActiveAlone() async {
        let (flags, consent, keychain, store, session) = Self.makeIsolatedDeps()
        let vm = Self.makeVM(flags: flags, consent: consent, keychain: keychain, store: store, urlSession: session)

        let first = Self.makeProfile(name: "First")
        let second = Self.makeProfile(name: "Second")
        await vm.addProfile(first, apiKey: "sk-first")
        await vm.addProfile(second, apiKey: "sk-second")

        #expect(vm.profiles.count == 2)
        #expect(vm.activeID == first.id, "Adding a second profile must not displace the active selection")
    }

    @Test @MainActor func addProfile_emptyAPIKey_insertsProfileButNoKeychainEntry() async throws {
        let (flags, consent, keychain, store, session) = Self.makeIsolatedDeps()
        let vm = Self.makeVM(flags: flags, consent: consent, keychain: keychain, store: store, urlSession: session)

        let p = Self.makeProfile()
        await vm.addProfile(p, apiKey: "")

        #expect(vm.profiles.count == 1)
        #expect(try keychain.readAPIKey(forProfile: p.id) == nil, "Empty API key must not write a keychain entry")
        #expect(vm.editorError == nil)
    }

    @Test @MainActor func addProfile_whitespaceOnlyAPIKey_treatedAsEmpty() async throws {
        let (flags, consent, keychain, store, session) = Self.makeIsolatedDeps()
        let vm = Self.makeVM(flags: flags, consent: consent, keychain: keychain, store: store, urlSession: session)

        let p = Self.makeProfile()
        await vm.addProfile(p, apiKey: "   \t\n  ")

        #expect(try keychain.readAPIKey(forProfile: p.id) == nil, "Whitespace-only API key must not write a keychain entry")
    }

    // MARK: - updateProfile

    @Test @MainActor func updateProfile_mutatesFieldsByID() async {
        let (flags, consent, keychain, store, session) = Self.makeIsolatedDeps()
        let vm = Self.makeVM(flags: flags, consent: consent, keychain: keychain, store: store, urlSession: session)

        let original = Self.makeProfile(name: "Original")
        await vm.addProfile(original, apiKey: "sk-key")

        let mutated = ProviderProfile(
            id: original.id,
            name: "Renamed",
            kind: .anthropicNative,
            baseURL: URL(string: "https://api.anthropic.com/v1")!,
            model: "claude-sonnet-4-6",
            temperature: 0.3,
            maxTokens: 4096
        )
        await vm.updateProfile(mutated)

        #expect(vm.profiles.count == 1)
        let after = vm.profiles.first!
        #expect(after.id == original.id, "ID must be preserved across update")
        #expect(after.name == "Renamed")
        #expect(after.kind == .anthropicNative)
        #expect(after.model == "claude-sonnet-4-6")
        #expect(after.temperature == 0.3)
        #expect(after.maxTokens == 4096)
        #expect(vm.editorError == nil)
    }

    @Test @MainActor func updateProfile_unknownID_setsEditorErrorAndDoesNotWrite() async {
        let (flags, consent, keychain, store, session) = Self.makeIsolatedDeps()
        let vm = Self.makeVM(flags: flags, consent: consent, keychain: keychain, store: store, urlSession: session)

        let known = Self.makeProfile(name: "Known")
        await vm.addProfile(known, apiKey: "sk-key")

        let unknown = Self.makeProfile(name: "Stale view")  // different id
        await vm.updateProfile(unknown)

        #expect(vm.editorError != nil, "Unknown-id update must surface an error")
        #expect(vm.profiles.count == 1, "Store must not insert a new profile under the unknown id")
        #expect(vm.profiles.first?.id == known.id)
    }

    // MARK: - saveAPIKey

    @Test @MainActor func saveAPIKey_writesPerProfileKeychainAccount() async throws {
        let (flags, consent, keychain, store, session) = Self.makeIsolatedDeps()
        let vm = Self.makeVM(flags: flags, consent: consent, keychain: keychain, store: store, urlSession: session)

        let p = Self.makeProfile()
        await vm.addProfile(p, apiKey: "")  // start with no key

        await vm.saveAPIKey("sk-new-key", forID: p.id)

        #expect(try keychain.readAPIKey(forProfile: p.id) == "sk-new-key")
        #expect(vm.editorError == nil)
    }

    @Test @MainActor func saveAPIKey_trimsLeadingTrailingWhitespace() async throws {
        let (flags, consent, keychain, store, session) = Self.makeIsolatedDeps()
        let vm = Self.makeVM(flags: flags, consent: consent, keychain: keychain, store: store, urlSession: session)

        let p = Self.makeProfile()
        await vm.addProfile(p, apiKey: "")

        await vm.saveAPIKey("  sk-padded-key  ", forID: p.id)

        #expect(try keychain.readAPIKey(forProfile: p.id) == "sk-padded-key", "Trim leading/trailing whitespace before saving")
    }

    @Test @MainActor func saveAPIKey_emptyKey_routesToDeleteAPIKey() async throws {
        let (flags, consent, keychain, store, session) = Self.makeIsolatedDeps()
        let vm = Self.makeVM(flags: flags, consent: consent, keychain: keychain, store: store, urlSession: session)

        let p = Self.makeProfile()
        await vm.addProfile(p, apiKey: "sk-original")
        #expect(try keychain.readAPIKey(forProfile: p.id) == "sk-original")

        await vm.saveAPIKey("", forID: p.id)

        #expect(try keychain.readAPIKey(forProfile: p.id) == nil, "Empty key must route to deleteAPIKey, removing the entry")
    }

    @Test @MainActor func deleteAPIKey_isIdempotent() async {
        let (flags, consent, keychain, store, session) = Self.makeIsolatedDeps()
        let vm = Self.makeVM(flags: flags, consent: consent, keychain: keychain, store: store, urlSession: session)

        let unknownID = UUID()
        await vm.deleteAPIKey(forID: unknownID)
        #expect(vm.editorError == nil, "Deleting a non-existent keychain entry must not raise an error")
    }

    // MARK: - testConnection — guard paths
    //
    // Round-1 audit finding [1] changed the signature from
    // `testConnection(forID:)` to `testConnection(profile:)`. The caller
    // now builds a candidate ProviderProfile from sheet form state, so
    // the "profile not in vm.profiles" guard is gone — there's no
    // lookup. The remaining guard is the keychain probe.

    @Test @MainActor func testConnection_missingAPIKey_returnsAPIKeyMissingError() async {
        let (flags, consent, keychain, store, session) = Self.makeIsolatedDeps()
        let vm = Self.makeVM(flags: flags, consent: consent, keychain: keychain, store: store, urlSession: session)

        let p = Self.makeProfile()  // no addProfile + no keychain write
        let result = await vm.testConnection(profile: p)
        switch result {
        case .success:
            Issue.record("Expected failure when no API key is saved")
        case .failure(let error as AIError):
            if case .apiKeyMissing = error {} else {
                Issue.record("Expected AIError.apiKeyMissing, got \(error)")
            }
        case .failure(let error):
            Issue.record("Expected AIError.apiKeyMissing, got \(error)")
        }
    }

    // MARK: - testConnection — HTTP paths (stubbed URLSession)
    //
    // Round-1 audit finding [6]: EditorStubURLProtocol shares static
    // handler state, so HTTP-touching tests can race under Swift
    // Testing's default parallel execution. Mark the HTTP suite
    // `.serialized` so each test gets a clean handler slot in turn.
    @Suite("AISettingsViewModel editor testConnection (serialized)",
           .serialized)
    struct EditorTestConnectionHTTP {

        @Test @MainActor func openAICompatible_2xx_buildsChatCompletionsURL() async throws {
            let session = makeStubSession()
            EditorStubURLProtocol.reset()
            EditorStubURLProtocol.requestHandler = { request in
                let resp = HTTPURLResponse(
                    url: request.url!, statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                let body = Data(#"""
                {"choices":[{"message":{"content":"pong"}}]}
                """#.utf8)
                return (resp, body)
            }
            defer { EditorStubURLProtocol.reset() }

            let (flags, consent, keychain, store, _) = makeIsolatedDeps(urlSession: session)
            let vm = await makeVM(flags: flags, consent: consent, keychain: keychain, store: store, urlSession: session)

            let p = makeProfile(kind: .openAICompatible)
            await vm.addProfile(p, apiKey: "sk-test-key")

            let result = await vm.testConnection(profile: p)
            if case .failure(let error) = result {
                Issue.record("Expected success, got \(error)")
            }

            // Stronger assertion (round-1 audit [6]): verify the request
            // actually went to the OpenAI-compatible chat/completions
            // endpoint with a Bearer auth header. This is the only way
            // a regression in AIService dispatch would show up here.
            let req = try #require(EditorStubURLProtocol.capturedRequests.last)
            #expect(req.url?.path.hasSuffix("/chat/completions") == true,
                    "OpenAI-compatible test must hit /chat/completions, got \(req.url?.absoluteString ?? "nil")")
            #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test-key")
        }

        @Test @MainActor func anthropic_2xx_buildsMessagesURL_andSendsAPIKeyHeader() async throws {
            let session = makeStubSession()
            EditorStubURLProtocol.reset()
            EditorStubURLProtocol.requestHandler = { request in
                let resp = HTTPURLResponse(
                    url: request.url!, statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                let body = Data(#"""
                {"id":"msg_test","type":"message","role":"assistant","content":[{"type":"text","text":"pong"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}
                """#.utf8)
                return (resp, body)
            }
            defer { EditorStubURLProtocol.reset() }

            let (flags, consent, keychain, store, _) = makeIsolatedDeps(urlSession: session)
            let vm = await makeVM(flags: flags, consent: consent, keychain: keychain, store: store, urlSession: session)

            let p = makeProfile(kind: .anthropicNative)
            await vm.addProfile(p, apiKey: "sk-ant-test")

            let result = await vm.testConnection(profile: p)
            if case .failure(let error) = result {
                Issue.record("Expected success, got \(error)")
            }

            // Stronger assertion: verify the dispatch produced an
            // Anthropic-shaped request (x-api-key header, /messages
            // path) — proves the kind switch routes correctly.
            let req = try #require(EditorStubURLProtocol.capturedRequests.last)
            #expect(req.url?.path.hasSuffix("/messages") == true,
                    "Anthropic test must hit /messages, got \(req.url?.absoluteString ?? "nil")")
            #expect(req.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test")
            #expect(req.value(forHTTPHeaderField: "Authorization") == nil,
                    "Anthropic must not send Bearer auth")
        }

        @Test @MainActor func usesLiveFormState_notStoredProfile() async throws {
            // Round-1 audit finding [1] regression test: edit the
            // profile in-memory (simulating sheet form edits the user
            // hasn't yet saved) and verify the outgoing request reflects
            // the LIVE values, not what was originally stored.
            let session = makeStubSession()
            EditorStubURLProtocol.reset()
            EditorStubURLProtocol.requestHandler = { request in
                let resp = HTTPURLResponse(
                    url: request.url!, statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (resp, Data(#"{"choices":[{"message":{"content":"ok"}}]}"#.utf8))
            }
            defer { EditorStubURLProtocol.reset() }

            let (flags, consent, keychain, store, _) = makeIsolatedDeps(urlSession: session)
            let vm = await makeVM(flags: flags, consent: consent, keychain: keychain, store: store, urlSession: session)

            // Save the profile with the *default* baseURL.
            let saved = makeProfile(kind: .openAICompatible)
            await vm.addProfile(saved, apiKey: "sk-live")

            // Now construct a candidate with a DIFFERENT baseURL —
            // imagine the user typed a new endpoint into the sheet.
            let edited = ProviderProfile(
                id: saved.id, name: saved.name, kind: saved.kind,
                baseURL: URL(string: "https://edited.example.com/v1")!,
                model: "edited-model",
                temperature: saved.temperature,
                maxTokens: saved.maxTokens
            )

            _ = await vm.testConnection(profile: edited)

            let req = try #require(EditorStubURLProtocol.capturedRequests.last)
            #expect(req.url?.host == "edited.example.com",
                    "testConnection must use the passed-in (live form) baseURL, not the stored profile's. Got \(req.url?.absoluteString ?? "nil")")
        }

        @Test @MainActor func usesApiKeyOverride_notKeychain() async throws {
            // Feature #80: the editor passes the TYPED in-memory key so an unsaved
            // (or different) key can be tested without a Save round-trip. The
            // override must win over the keychain.
            let session = makeStubSession()
            EditorStubURLProtocol.reset()
            EditorStubURLProtocol.requestHandler = { request in
                let resp = HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
                return (resp, Data(#"{"choices":[{"message":{"content":"ok"}}]}"#.utf8))
            }
            defer { EditorStubURLProtocol.reset() }

            let (flags, consent, keychain, store, _) = makeIsolatedDeps(urlSession: session)
            let vm = await makeVM(flags: flags, consent: consent, keychain: keychain, store: store, urlSession: session)

            // Keychain holds one key…
            let p = makeProfile(kind: .openAICompatible)
            await vm.addProfile(p, apiKey: "sk-saved-keychain")

            // …but the test passes a DIFFERENT typed override.
            _ = await vm.testConnection(profile: p, apiKeyOverride: "sk-typed-override")

            let req = try #require(EditorStubURLProtocol.capturedRequests.last)
            #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer sk-typed-override",
                    "testConnection must use apiKeyOverride (typed in-memory), not the keychain key")
        }

        @Test @MainActor func nilOverride_fallsBackToKeychain() async throws {
            // Edit-mode no-regression: a nil override → the keychain key is used.
            let session = makeStubSession()
            EditorStubURLProtocol.reset()
            EditorStubURLProtocol.requestHandler = { request in
                let resp = HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
                return (resp, Data(#"{"choices":[{"message":{"content":"ok"}}]}"#.utf8))
            }
            defer { EditorStubURLProtocol.reset() }

            let (flags, consent, keychain, store, _) = makeIsolatedDeps(urlSession: session)
            let vm = await makeVM(flags: flags, consent: consent, keychain: keychain, store: store, urlSession: session)

            let p = makeProfile(kind: .openAICompatible)
            await vm.addProfile(p, apiKey: "sk-saved-keychain")

            _ = await vm.testConnection(profile: p, apiKeyOverride: nil)

            let req = try #require(EditorStubURLProtocol.capturedRequests.last)
            #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer sk-saved-keychain",
                    "nil override must fall back to the keychain key (edit-mode path unchanged)")
        }

        @Test @MainActor func serverError_returnsFailure() async {
            let session = makeStubSession()
            EditorStubURLProtocol.reset()
            EditorStubURLProtocol.requestHandler = { request in
                let resp = HTTPURLResponse(
                    url: request.url!, statusCode: 401,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (resp, Data("{\"error\":\"unauthorized\"}".utf8))
            }
            defer { EditorStubURLProtocol.reset() }

            let (flags, consent, keychain, store, _) = makeIsolatedDeps(urlSession: session)
            let vm = await makeVM(flags: flags, consent: consent, keychain: keychain, store: store, urlSession: session)

            let p = makeProfile(kind: .openAICompatible)
            await vm.addProfile(p, apiKey: "sk-bad-key")

            let result = await vm.testConnection(profile: p)
            if case .success = result {
                Issue.record("Expected failure for 401 response")
            }
        }

        // Helpers copied (not shared) — the nested suite is structurally
        // independent so it can opt into `.serialized` without forcing
        // the outer suite's non-HTTP tests to serialize too.
        fileprivate func makeIsolatedDeps(
            urlSession: URLSession = .shared
        ) -> (FeatureFlags, AIConsentManager, KeychainService, ProviderProfileStore, URLSession) {
            let flags = FeatureFlags(environment: .prod)
            let consent = AIConsentManager(defaults: UserDefaults(
                suiteName: "com.vreader.test.consent.\(UUID().uuidString)"
            )!)
            let keychain = KeychainService(
                serviceIdentifier: "com.vreader.test.\(UUID().uuidString)"
            )
            let store = ProviderProfileStore(
                preferences: MockPreferenceStore(),
                migrator: DefaultProviderProfileMigrator(),
                keychain: keychain
            )
            return (flags, consent, keychain, store, urlSession)
        }

        @MainActor
        fileprivate func makeVM(
            flags: FeatureFlags, consent: AIConsentManager,
            keychain: KeychainService, store: ProviderProfileStore,
            urlSession: URLSession
        ) -> AISettingsViewModel {
            AISettingsViewModel(
                featureFlags: flags,
                consentManager: consent,
                keychainService: keychain,
                profileStore: store,
                urlSession: urlSession
            )
        }

        fileprivate func makeProfile(
            id: UUID = UUID(),
            name: String = "Test Profile",
            kind: ProviderKind = .openAICompatible
        ) -> ProviderProfile {
            ProviderProfile(
                id: id, name: name, kind: kind,
                baseURL: kind.defaultBaseURL,
                model: kind.defaultModel,
                temperature: 0.7,
                maxTokens: 2048
            )
        }
    }

    // MARK: - validateBaseURL (static helper)

    @Test func validateBaseURL_emptyString_returnsErrorMessage() {
        let err = AISettingsViewModel.validateBaseURL("")
        #expect(err?.contains("empty") == true)
    }

    @Test func validateBaseURL_whitespaceOnly_returnsErrorMessage() {
        let err = AISettingsViewModel.validateBaseURL("   \t  ")
        #expect(err != nil)
    }

    @Test func validateBaseURL_validHTTPS_returnsNil() {
        #expect(AISettingsViewModel.validateBaseURL("https://api.openai.com/v1") == nil)
        #expect(AISettingsViewModel.validateBaseURL("https://api.anthropic.com/v1/messages") == nil)
    }

    @Test func validateBaseURL_httpRemoteHost_returnsErrorMessage() {
        let err = AISettingsViewModel.validateBaseURL("http://api.openai.com/v1")
        #expect(err?.contains("HTTPS") == true)
    }

    @Test func validateBaseURL_httpLocalhost_returnsNil() {
        // Round-1 audit finding [3]: validator accepts only the loopback
        // names the providers also accept (`localhost` + `127.0.0.1`).
        // IPv6 loopback was previously accepted by the validator but
        // rejected at request time by the providers, producing profiles
        // the editor saved but couldn't actually use.
        #expect(AISettingsViewModel.validateBaseURL("http://localhost:11434/v1") == nil)
        #expect(AISettingsViewModel.validateBaseURL("http://127.0.0.1:8080") == nil)
    }

    @Test func validateBaseURL_httpIPv6Loopback_rejectedToMatchProviderPolicy() {
        // The providers (OpenAICompatibleProvider / AnthropicProvider)
        // only whitelist `localhost` + `127.0.0.1` for HTTP. Validator
        // must mirror that to avoid editor/runtime divergence.
        let err1 = AISettingsViewModel.validateBaseURL("http://[::1]:8080")
        #expect(err1?.contains("HTTPS") == true, "IPv6 loopback over HTTP must be rejected to match provider preflight")
    }

    @Test func validateBaseURL_unsupportedScheme_returnsErrorMessage() {
        let err = AISettingsViewModel.validateBaseURL("ftp://files.example.com")
        #expect(err != nil)
    }

    @Test func validateBaseURL_trimsLeadingTrailingWhitespace() {
        #expect(AISettingsViewModel.validateBaseURL("  https://api.example.com  ") == nil)
    }

    // MARK: - KindResetPolicy (round-2 audit fix [1])

    @Test func kindReset_baseURL_replacesWhenStillOldDefault() {
        let oldKind = ProviderKind.openAICompatible
        // Field still holds the OpenAI default — user never edited.
        #expect(KindResetPolicy.shouldReplaceBaseURL(
            current: oldKind.defaultBaseURL.absoluteString,
            oldKind: oldKind
        ) == true)
    }

    @Test func kindReset_baseURL_leavesAloneWhenUserEdited() {
        // Field holds a custom URL — user definitely edited it.
        #expect(KindResetPolicy.shouldReplaceBaseURL(
            current: "https://my-custom-proxy.example.com/v1",
            oldKind: .openAICompatible
        ) == false)
    }

    @Test func kindReset_model_replacesWhenStillOldDefault() {
        let oldKind = ProviderKind.anthropicNative
        #expect(KindResetPolicy.shouldReplaceModel(
            current: oldKind.defaultModel,
            oldKind: oldKind
        ) == true)
    }

    @Test func kindReset_model_leavesAloneWhenUserEdited() {
        #expect(KindResetPolicy.shouldReplaceModel(
            current: "my-finetuned-model-v2",
            oldKind: .anthropicNative
        ) == false)
    }

    @Test func kindReset_editMode_neverReplaces_evenWhenFieldsEqualOldDefaults() {
        // Round-3 audit fix: edit-mode prefill is sticky. The user
        // already committed those values once by saving the profile, so
        // changing the kind in the editor must NOT overwrite them even
        // if they happen to equal the old kind's defaults.
        let oldKind = ProviderKind.openAICompatible
        #expect(KindResetPolicy.shouldReplaceBaseURL(
            current: oldKind.defaultBaseURL.absoluteString,
            oldKind: oldKind,
            inEditMode: true
        ) == false, "Edit-mode: never replace baseURL, even when it equals the old default")
        #expect(KindResetPolicy.shouldReplaceModel(
            current: oldKind.defaultModel,
            oldKind: oldKind,
            inEditMode: true
        ) == false, "Edit-mode: never replace model, even when it equals the old default")
    }

    @Test func kindReset_addMode_explicitFlagMatchesDefault() {
        // Mirror coverage with the inEditMode flag set explicitly false.
        let oldKind = ProviderKind.openAICompatible
        #expect(KindResetPolicy.shouldReplaceBaseURL(
            current: oldKind.defaultBaseURL.absoluteString,
            oldKind: oldKind,
            inEditMode: false
        ) == true)
    }

    @Test func kindReset_roundTripsOpenAIToAnthropicToOpenAI_withoutUserEdits() {
        // The round-2 regression: simulate a kind flip OpenAI → Anthropic
        // → OpenAI without typing in either field. After each hop, the
        // policy must agree that the (still-default) field can be
        // replaced with the next kind's default.
        var url = ProviderKind.openAICompatible.defaultBaseURL.absoluteString
        var model = ProviderKind.openAICompatible.defaultModel

        // Hop 1: OpenAI → Anthropic. URL/model still hold OpenAI
        // defaults, so policy says replace.
        var fromKind = ProviderKind.openAICompatible
        var toKind = ProviderKind.anthropicNative
        #expect(KindResetPolicy.shouldReplaceBaseURL(current: url, oldKind: fromKind))
        #expect(KindResetPolicy.shouldReplaceModel(current: model, oldKind: fromKind))
        url = toKind.defaultBaseURL.absoluteString
        model = toKind.defaultModel

        // Hop 2: Anthropic → OpenAI. URL/model now hold Anthropic
        // defaults — still the previous kind's defaults, so policy says
        // replace. The old design (flag-based) failed this hop because
        // the field .onChange handlers marked the fields as user-edited
        // when the kind picker wrote the Anthropic defaults at hop 1.
        fromKind = .anthropicNative
        toKind = .openAICompatible
        #expect(KindResetPolicy.shouldReplaceBaseURL(current: url, oldKind: fromKind))
        #expect(KindResetPolicy.shouldReplaceModel(current: model, oldKind: fromKind))
    }

    // MARK: - Feature #79: add-mode placeholder / effective-value helpers

    @Test @MainActor func effectiveBaseURL_addModeBlank_usesKindDefault() {
        let kind = ProviderKind.openAICompatible
        #expect(AIProviderEditSheet.effectiveBaseURLText(isAddMode: true, typed: "", kind: kind)
                == kind.defaultBaseURL.absoluteString)
        #expect(AIProviderEditSheet.effectiveBaseURLText(isAddMode: true, typed: "   ", kind: kind)
                == kind.defaultBaseURL.absoluteString)  // whitespace == blank
    }

    @Test @MainActor func effectiveBaseURL_addModeTyped_usesTypedVerbatim() {
        #expect(AIProviderEditSheet.effectiveBaseURLText(
            isAddMode: true, typed: "https://x.example/v1", kind: .openAICompatible) == "https://x.example/v1")
    }

    @Test @MainActor func effectiveBaseURL_editModeBlank_staysRaw_notDefaulted() {
        // Gate-2 round-1 High: edit-mode clearing must NOT silently default.
        #expect(AIProviderEditSheet.effectiveBaseURLText(
            isAddMode: false, typed: "", kind: .openAICompatible) == "")
        #expect(AIProviderEditSheet.effectiveBaseURLText(
            isAddMode: false, typed: "https://kept.example", kind: .openAICompatible) == "https://kept.example")
    }

    @Test @MainActor func effectiveModel_addModeBlankDefaults_editModeRaw() {
        let kind = ProviderKind.openAICompatible
        // Gate-2 round-1 Medium: blank model is NOT provider-tolerated, so add-mode
        // blank must resolve to the kind default (never "").
        #expect(AIProviderEditSheet.effectiveModel(isAddMode: true, typed: "", kind: kind) == kind.defaultModel)
        #expect(AIProviderEditSheet.effectiveModel(isAddMode: true, typed: "gpt-x", kind: kind) == "gpt-x")
        #expect(AIProviderEditSheet.effectiveModel(isAddMode: false, typed: "", kind: kind) == "")  // edit raw
    }

    @Test @MainActor func effectiveModel_editMode_preservesRawWhitespace_noNormalization() {
        // Gate-4 Medium: edit-mode save persisted the RAW (untrimmed) model
        // pre-#79; the effective helper must NOT silently normalize it.
        let kind = ProviderKind.openAICompatible
        #expect(AIProviderEditSheet.effectiveModel(isAddMode: false, typed: "  gpt-x  ", kind: kind) == "  gpt-x  ")
        #expect(AIProviderEditSheet.effectiveModel(isAddMode: false, typed: "   ", kind: kind) == "   ")
    }

    @Test @MainActor func placeholder_addModeKindDefault_editModeEmpty() {
        let kind = ProviderKind.openAICompatible
        #expect(AIProviderEditSheet.placeholderBaseURL(isAddMode: true, kind: kind) == kind.defaultBaseURL.absoluteString)
        #expect(AIProviderEditSheet.placeholderModel(isAddMode: true, kind: kind) == kind.defaultModel)
        // Gate-2 round-2 Medium: edit-mode shows NO default hint.
        #expect(AIProviderEditSheet.placeholderBaseURL(isAddMode: false, kind: kind) == "")
        #expect(AIProviderEditSheet.placeholderModel(isAddMode: false, kind: kind) == "")
    }

    // MARK: - Feature #80: Test-before-save gating

    @Test @MainActor func hasTestableKey_typedKeyOrSaved() {
        // A typed key (add-mode) OR a saved key (edit-mode) enables Test.
        #expect(AIProviderEditSheet.hasTestableKey(typedKey: "sk-typed", isSaved: false))
        #expect(AIProviderEditSheet.hasTestableKey(typedKey: "", isSaved: true))
        #expect(AIProviderEditSheet.hasTestableKey(typedKey: "sk-typed", isSaved: true))
        // No key at all → no test; whitespace-only typed key counts as no key.
        #expect(!AIProviderEditSheet.hasTestableKey(typedKey: "", isSaved: false))
        #expect(!AIProviderEditSheet.hasTestableKey(typedKey: "   ", isSaved: false))
    }

    @Test @MainActor func shouldApplyTestResult_onlyWhenGenerationUnchanged() {
        // Gate-4 High: an in-flight test whose form changed mid-request (the
        // generation was bumped by resetTestResult) must NOT repaint its stale
        // result over the new form state.
        #expect(AIProviderEditSheet.shouldApplyTestResult(runGeneration: 3, currentGeneration: 3))
        #expect(!AIProviderEditSheet.shouldApplyTestResult(runGeneration: 3, currentGeneration: 4))
    }
}
