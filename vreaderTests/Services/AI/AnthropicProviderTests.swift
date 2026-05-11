// Purpose: Tests for AnthropicProvider — feature #50 WI-3.
// Non-streaming sendRequest path: header correctness (x-api-key +
// anthropic-version), body shape (top-level system + messages array +
// required max_tokens), response parsing (content blocks → text), and
// HTTP error handling (401/403, 429 with retry-after seconds, 4xx/5xx).
//
// Stubs URLSession via a per-suite URLProtocol to avoid real network and
// to avoid cross-contamination with other test suites that may use a
// different URLProtocol stub.
//
// Streaming (streamRequest) is intentionally NOT covered here — that's
// WI-4 scope. WI-3 ships sendRequest only; streamRequest in the
// AnthropicProvider returns a not-yet-implemented error until WI-4.
//
// @coordinates-with: AnthropicProvider.swift, AIProvider.swift,
//   AITypes.swift, AIError.swift, ProviderKind.swift

import Testing
import Foundation
@testable import vreader

// MARK: - Stub URLProtocol (per-suite, isolated from other test suites)

/// URLProtocol stub dedicated to AnthropicProviderTests. A separate class
/// from `MockURLProtocol` used by BookSourceHTTPClientTests so the two
/// suites don't race on shared static handler state.
final class AnthropicStubURLProtocol: URLProtocol, @unchecked Sendable {
    /// Returns (response, body, optional throw error) for the request.
    nonisolated(unsafe) static var requestHandler: ((URLRequest) -> (HTTPURLResponse, Data))?

    /// Captures requests so tests can assert on headers / body / method.
    nonisolated(unsafe) static var capturedRequests: [URLRequest] = []

    /// Captures raw body bytes (the URLRequest in `startLoading` has the
    /// httpBody stripped when delivered through URLProtocol's normal
    /// flow; we capture from `canInit` time).
    nonisolated(unsafe) static var capturedBodies: [Data] = []

    override class func canInit(with request: URLRequest) -> Bool {
        if let body = request.httpBody {
            capturedBodies.append(body)
        } else if let stream = request.httpBodyStream {
            // URLRequest delivers POST bodies via stream when set with
            // setValue/setHttpBody at the right level. Drain it.
            stream.open()
            defer { stream.close() }
            var data = Data()
            let bufSize = 1024
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
            defer { buf.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buf, maxLength: bufSize)
                if read <= 0 { break }
                data.append(buf, count: read)
            }
            capturedBodies.append(data)
        }
        return true
    }

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
        capturedBodies = []
    }
}

// MARK: - Helpers

private func makeStubSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [AnthropicStubURLProtocol.self]
    return URLSession(configuration: config)
}

private func makeResponse(
    url: URL,
    status: Int,
    headers: [String: String] = [:]
) -> HTTPURLResponse {
    var allHeaders = headers
    if allHeaders["Content-Type"] == nil {
        allHeaders["Content-Type"] = "application/json"
    }
    return HTTPURLResponse(
        url: url, statusCode: status,
        httpVersion: "HTTP/1.1", headerFields: allHeaders
    )!
}

private func happyPathResponseJSON(text: String = "Once upon a time …") -> Data {
    let body: [String: Any] = [
        "id": "msg_01ABC",
        "type": "message",
        "role": "assistant",
        "model": "claude-sonnet-4-6",
        "content": [
            ["type": "text", "text": text]
        ],
        "stop_reason": "end_turn",
        "usage": ["input_tokens": 10, "output_tokens": 7]
    ]
    return try! JSONSerialization.data(withJSONObject: body)
}

private func makeRequest(
    actionType: AIActionType = .summarize,
    context: String = "Chapter One. It was a bright cold day in April.",
    userPrompt: String? = nil,
    targetLanguage: String? = nil
) -> AIRequest {
    AIRequest(
        actionType: actionType,
        bookFingerprint: nil,
        locator: nil,
        contextText: context,
        userPrompt: userPrompt,
        targetLanguage: targetLanguage,
        promptVersion: "test-v1"
    )
}

private func makeProvider(
    apiKey: String = "sk-ant-test-key",
    model: String = "claude-sonnet-4-6",
    maxTokens: Int = 4096,
    baseURL: URL = URL(string: "https://api.anthropic.com")!
) -> AnthropicProvider {
    AnthropicProvider(
        baseURL: baseURL,
        apiKey: apiKey,
        model: model,
        maxTokens: maxTokens,
        session: makeStubSession()
    )
}

// MARK: - Tests

/// Serialized because the suite mutates static handler state on
/// `AnthropicStubURLProtocol`. Swift Testing parallelizes tests by default,
/// which would let two cases stomp on each other's stub. Per-test
/// isolation (per Codex round-1 audit, Medium 2) — serialize the suite as
/// the simplest robust fix; the stronger fix would key handler state per
/// test instance, but that adds wiring noise without measurable speedup
/// on a 16-test suite.
@Suite("AnthropicProvider — sendRequest (WI-3)", .serialized)
struct AnthropicProviderTests {

    init() { AnthropicStubURLProtocol.reset() }

    // MARK: - Happy path

    @Test func sendRequest_happyPath_returnsContent() async throws {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        AnthropicStubURLProtocol.requestHandler = { _ in
            (makeResponse(url: url, status: 200), happyPathResponseJSON(text: "Hello back."))
        }
        let provider = makeProvider()

        let response = try await provider.sendRequest(makeRequest())

        #expect(response.content == "Hello back.")
        #expect(response.actionType == .summarize)
        #expect(response.promptVersion == "test-v1")
    }

    // MARK: - Headers

    @Test func sendRequest_setsAnthropicHeaders() async throws {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        AnthropicStubURLProtocol.requestHandler = { _ in
            (makeResponse(url: url, status: 200), happyPathResponseJSON())
        }
        let provider = makeProvider(apiKey: "my-secret-key-123")

        _ = try await provider.sendRequest(makeRequest())

        let captured = AnthropicStubURLProtocol.capturedRequests.last
        #expect(captured != nil, "Provider must have issued a request")
        #expect(captured?.url == url, "Endpoint must be /v1/messages")
        #expect(captured?.httpMethod == "POST")
        #expect(captured?.value(forHTTPHeaderField: "x-api-key") == "my-secret-key-123", "Must send x-api-key header (NOT Authorization: Bearer)")
        #expect(captured?.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01", "Must send anthropic-version: 2023-06-01 (the GA-stable version pin per the plan)")
        #expect(captured?.value(forHTTPHeaderField: "Content-Type") == "application/json")
        // Authorization MUST NOT leak through from any prior caller.
        #expect(captured?.value(forHTTPHeaderField: "Authorization") == nil, "Must NOT send Authorization: Bearer — that's the OpenAI-compatible path")
    }

    // MARK: - Body shape — system field is top-level, messages array

    @Test func sendRequest_bodyShape_systemFieldIsTopLevel_notInMessages() async throws {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        AnthropicStubURLProtocol.requestHandler = { _ in
            (makeResponse(url: url, status: 200), happyPathResponseJSON())
        }
        let provider = makeProvider()
        _ = try await provider.sendRequest(makeRequest(actionType: .summarize, context: "TEXT"))

        let body = AnthropicStubURLProtocol.capturedBodies.last
        #expect(body != nil)
        let json = try JSONSerialization.jsonObject(with: body!) as? [String: Any]
        #expect(json != nil)
        // system must be a top-level field (Anthropic's API requires it
        // there, NOT as a role inside `messages`).
        let system = json?["system"] as? String
        #expect(system != nil, "Anthropic requires the system prompt at top level, not inside messages")
        #expect(system?.isEmpty == false)
        // messages must contain only user (and optionally assistant) roles.
        let messages = json?["messages"] as? [[String: Any]]
        #expect(messages != nil)
        for msg in messages ?? [] {
            let role = msg["role"] as? String
            #expect(role != "system", "system role must NOT appear inside messages — it goes at top level for Anthropic")
        }
        // First user message present.
        let firstUserContent = messages?.first?["content"] as? String
        #expect(firstUserContent?.contains("TEXT") == true)
    }

    @Test func sendRequest_bodyShape_includesRequiredMaxTokensAndModel() async throws {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        AnthropicStubURLProtocol.requestHandler = { _ in
            (makeResponse(url: url, status: 200), happyPathResponseJSON())
        }
        let provider = makeProvider(model: "claude-opus-4-7", maxTokens: 2048)
        _ = try await provider.sendRequest(makeRequest())

        let body = AnthropicStubURLProtocol.capturedBodies.last
        let json = try JSONSerialization.jsonObject(with: body!) as? [String: Any]
        #expect(json?["model"] as? String == "claude-opus-4-7")
        // max_tokens is REQUIRED by Anthropic — must always be present.
        #expect(json?["max_tokens"] as? Int == 2048, "max_tokens is required by Anthropic Messages API; must be in every request body")
    }

    @Test func sendRequest_bodyShape_doesNotSetStreamWhenNonStreaming() async throws {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        AnthropicStubURLProtocol.requestHandler = { _ in
            (makeResponse(url: url, status: 200), happyPathResponseJSON())
        }
        let provider = makeProvider()
        _ = try await provider.sendRequest(makeRequest())

        let body = AnthropicStubURLProtocol.capturedBodies.last
        let json = try JSONSerialization.jsonObject(with: body!) as? [String: Any]
        // stream defaults to false / absent for non-streaming sendRequest.
        let stream = json?["stream"] as? Bool
        #expect(stream == nil || stream == false, "sendRequest must not request streaming")
    }

    // MARK: - Error paths

    @Test func sendRequest_4xx_nonAuth_surfacesProviderErrorWithStatusAndBody() async throws {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        let errBody = "{\"type\":\"error\",\"error\":{\"type\":\"invalid_request\",\"message\":\"bad input\"}}"
        AnthropicStubURLProtocol.requestHandler = { _ in
            (makeResponse(url: url, status: 400), errBody.data(using: .utf8)!)
        }
        let provider = makeProvider()

        await #expect(throws: AIError.self) {
            _ = try await provider.sendRequest(makeRequest())
        }
        // More specific: providerError carrying status + body excerpt.
        do {
            _ = try await provider.sendRequest(makeRequest())
            Issue.record("Expected throw for 400")
        } catch let error as AIError {
            switch error {
            case .providerError(let msg):
                #expect(msg.contains("400"), "Provider error must include status code; got: \(msg)")
                #expect(msg.contains("bad input") || msg.contains("invalid_request"), "Provider error must include some of the error body; got: \(msg)")
            default:
                Issue.record("Expected .providerError, got \(error)")
            }
        } catch {
            Issue.record("Expected AIError, got \(error)")
        }
    }

    @Test func sendRequest_401_surfacesAuthenticationFailed() async throws {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        AnthropicStubURLProtocol.requestHandler = { _ in
            (makeResponse(url: url, status: 401), Data())
        }
        let provider = makeProvider()

        do {
            _ = try await provider.sendRequest(makeRequest())
            Issue.record("Expected throw for 401")
        } catch let error as AIError {
            switch error {
            case .providerError(let msg):
                let lower = msg.lowercased()
                #expect(lower.contains("authentication") || lower.contains("401"))
                // 401 = key invalid → message should NOT mention model/workspace
                // access (that's 403). Codex round-1 Medium 1.
                #expect(!lower.contains("workspace"), "401 message must not mention workspace access; that's 403")
            default:
                Issue.record("Expected providerError, got \(error)")
            }
        } catch {
            Issue.record("Expected AIError, got \(error)")
        }
    }

    @Test func sendRequest_403_surfacesAuthorizationFailed_distinctFrom401() async throws {
        // Codex round-1 audit Medium 1: 403 from Anthropic typically means
        // the key is valid but lacks access to the configured model or
        // workspace. The message must be distinct from 401 ("key wrong")
        // so users don't rotate a key that's actually fine.
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        AnthropicStubURLProtocol.requestHandler = { _ in
            (makeResponse(url: url, status: 403), Data())
        }
        let provider = makeProvider()

        do {
            _ = try await provider.sendRequest(makeRequest())
            Issue.record("Expected throw for 403")
        } catch let error as AIError {
            switch error {
            case .providerError(let msg):
                let lower = msg.lowercased()
                #expect(lower.contains("403"))
                // Message must distinguish 403 from 401 — mention
                // authorization/access, not just "key is wrong".
                #expect(lower.contains("authorization") || lower.contains("access") || lower.contains("workspace") || lower.contains("model"), "403 message must mention authorization/access/model/workspace, not just the key; got: \(msg)")
            default:
                Issue.record("Expected providerError, got \(error)")
            }
        } catch {
            Issue.record("Expected AIError, got \(error)")
        }
    }

    @Test func sendRequest_401_messageInterpolatesProviderName() async throws {
        // Codex round-1 audit Medium 1: error messages should reference the
        // provider's configured display name (so renamed profiles get an
        // accurate error), not a hardcoded "Anthropic".
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        AnthropicStubURLProtocol.requestHandler = { _ in
            (makeResponse(url: url, status: 401), Data())
        }
        let provider = AnthropicProvider(
            providerName: "MyCustomProfile",
            apiKey: "sk-ant-x",
            session: makeStubSession()
        )

        do {
            _ = try await provider.sendRequest(makeRequest())
            Issue.record("Expected throw for 401")
        } catch let error as AIError {
            if case .providerError(let msg) = error {
                #expect(msg.contains("MyCustomProfile"), "Error must interpolate providerName for renamed profiles; got: \(msg)")
            } else {
                Issue.record("Expected providerError, got \(error)")
            }
        } catch {
            Issue.record("Expected AIError, got \(error)")
        }
    }

    @Test func sendRequest_429_withRetryAfter_surfacesRateLimitedInSeconds() async throws {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        AnthropicStubURLProtocol.requestHandler = { _ in
            (makeResponse(url: url, status: 429, headers: ["retry-after": "42"]), Data())
        }
        let provider = makeProvider()

        do {
            _ = try await provider.sendRequest(makeRequest())
            Issue.record("Expected throw for 429")
        } catch let error as AIError {
            switch error {
            case .rateLimited(let retryAfterSeconds):
                // Plan round-1 audit finding [3]: Anthropic's retry-after
                // header is in seconds (matches the HTTP spec and the
                // existing AIError.rateLimited contract).
                #expect(retryAfterSeconds == 42, "retry-after must be parsed as seconds, not milliseconds; got \(String(describing: retryAfterSeconds))")
            default:
                Issue.record("Expected .rateLimited, got \(error)")
            }
        } catch {
            Issue.record("Expected AIError, got \(error)")
        }
    }

    @Test func sendRequest_429_withoutRetryAfter_surfacesRateLimitedNil() async throws {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        AnthropicStubURLProtocol.requestHandler = { _ in
            (makeResponse(url: url, status: 429), Data())
        }
        let provider = makeProvider()

        do {
            _ = try await provider.sendRequest(makeRequest())
            Issue.record("Expected throw for 429")
        } catch let error as AIError {
            switch error {
            case .rateLimited(let retryAfterSeconds):
                #expect(retryAfterSeconds == nil, "No retry-after header → retryAfterSeconds must be nil")
            default:
                Issue.record("Expected .rateLimited, got \(error)")
            }
        } catch {
            Issue.record("Expected AIError, got \(error)")
        }
    }

    @Test func sendRequest_5xx_surfacesProviderError() async throws {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        AnthropicStubURLProtocol.requestHandler = { _ in
            (makeResponse(url: url, status: 503), Data("upstream gateway".utf8))
        }
        let provider = makeProvider()

        do {
            _ = try await provider.sendRequest(makeRequest())
            Issue.record("Expected throw for 503")
        } catch let error as AIError {
            switch error {
            case .providerError(let msg):
                #expect(msg.contains("503"))
            default:
                Issue.record("Expected .providerError, got \(error)")
            }
        } catch {
            Issue.record("Expected AIError, got \(error)")
        }
    }

    // MARK: - Malformed response parsing

    @Test func sendRequest_malformedJSON_surfacesInvalidResponse() async throws {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        AnthropicStubURLProtocol.requestHandler = { _ in
            (makeResponse(url: url, status: 200), Data("{not json".utf8))
        }
        let provider = makeProvider()

        do {
            _ = try await provider.sendRequest(makeRequest())
            Issue.record("Expected throw for malformed JSON")
        } catch let error as AIError {
            switch error {
            case .invalidResponse, .providerError:
                // either is acceptable as long as we don't crash or return
                // garbage content
                break
            default:
                Issue.record("Expected .invalidResponse or .providerError, got \(error)")
            }
        } catch {
            Issue.record("Expected AIError, got \(error)")
        }
    }

    @Test func sendRequest_emptyContentArray_surfacesInvalidResponse() async throws {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        let emptyContent: [String: Any] = [
            "id": "msg_x", "type": "message", "role": "assistant",
            "model": "claude-sonnet-4-6",
            "content": [], // EMPTY
            "stop_reason": "end_turn"
        ]
        let body = try JSONSerialization.data(withJSONObject: emptyContent)
        AnthropicStubURLProtocol.requestHandler = { _ in
            (makeResponse(url: url, status: 200), body)
        }
        let provider = makeProvider()

        do {
            _ = try await provider.sendRequest(makeRequest())
            Issue.record("Expected throw for empty content array")
        } catch let error as AIError {
            switch error {
            case .invalidResponse, .providerError:
                break
            default:
                Issue.record("Expected .invalidResponse or .providerError, got \(error)")
            }
        } catch {
            Issue.record("Expected AIError, got \(error)")
        }
    }

    // MARK: - Translate path — targetLanguage flows into user message

    @Test func sendRequest_translate_includesTargetLanguageInUserMessage() async throws {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        AnthropicStubURLProtocol.requestHandler = { _ in
            (makeResponse(url: url, status: 200), happyPathResponseJSON())
        }
        let provider = makeProvider()
        _ = try await provider.sendRequest(makeRequest(
            actionType: .translate,
            context: "Bonjour",
            targetLanguage: "English"
        ))

        let body = AnthropicStubURLProtocol.capturedBodies.last
        let json = try JSONSerialization.jsonObject(with: body!) as? [String: Any]
        let messages = json?["messages"] as? [[String: Any]]
        let userContent = messages?.first?["content"] as? String
        #expect(userContent?.contains("Bonjour") == true)
        #expect(userContent?.contains("English") == true, "Target language must surface in the user prompt for translate action")
    }

    // MARK: - HTTPS enforcement

    @Test func sendRequest_rejectsNonHTTPSNonLocalhost() async throws {
        let httpURL = URL(string: "http://api.anthropic.com")!
        let provider = makeProvider(baseURL: httpURL)

        do {
            _ = try await provider.sendRequest(makeRequest())
            Issue.record("Expected throw for non-HTTPS, non-localhost baseURL")
        } catch let error as AIError {
            switch error {
            case .networkError(let msg):
                #expect(msg.lowercased().contains("https"), "Error must mention HTTPS requirement; got: \(msg)")
            case .providerError(let msg):
                #expect(msg.lowercased().contains("https"), "Error must mention HTTPS requirement; got: \(msg)")
            default:
                Issue.record("Expected .networkError or .providerError, got \(error)")
            }
        } catch {
            Issue.record("Expected AIError, got \(error)")
        }
    }

    @Test func sendRequest_acceptsLocalhostHTTP() async throws {
        // Match OpenAICompatibleProvider's behavior — local LLM testing
        // (Ollama/LM Studio at http://localhost) is allowed.
        let url = URL(string: "http://localhost:8080")!
        AnthropicStubURLProtocol.requestHandler = { _ in
            let messagesURL = URL(string: "http://localhost:8080/v1/messages")!
            return (makeResponse(url: messagesURL, status: 200), happyPathResponseJSON())
        }
        let provider = makeProvider(baseURL: url)
        // Should NOT throw on HTTPS guard — should reach the stub.
        let response = try await provider.sendRequest(makeRequest())
        #expect(response.content.isEmpty == false)
    }

    // MARK: - Provider identity

    @Test func providerName_defaultsToAnthropic() {
        let provider = makeProvider()
        #expect(provider.providerName == "Anthropic")
    }

    // MARK: - max_tokens validation (Codex round-1 audit Low)

    @Test func sendRequest_rejectsZeroMaxTokens_beforeNetwork() async throws {
        // Anthropic requires max_tokens >= 1; sending 0 would burn a
        // network round trip and return a generic 400. Fail fast with a
        // clear, profile-scoped error.
        let provider = makeProvider(maxTokens: 0)

        do {
            _ = try await provider.sendRequest(makeRequest())
            Issue.record("Expected throw for maxTokens=0")
        } catch let error as AIError {
            if case .providerError(let msg) = error {
                #expect(msg.lowercased().contains("max_tokens") || msg.lowercased().contains("max tokens"), "Error must mention max_tokens; got: \(msg)")
                #expect(msg.contains("0"), "Error must include the invalid value; got: \(msg)")
            } else {
                Issue.record("Expected .providerError, got \(error)")
            }
        } catch {
            Issue.record("Expected AIError, got \(error)")
        }

        // Confirm we never hit the network.
        #expect(AnthropicStubURLProtocol.capturedRequests.isEmpty, "Provider must not issue a request when maxTokens is invalid")
    }

    @Test func sendRequest_rejectsNegativeMaxTokens_beforeNetwork() async throws {
        let provider = makeProvider(maxTokens: -1)

        do {
            _ = try await provider.sendRequest(makeRequest())
            Issue.record("Expected throw for maxTokens=-1")
        } catch let error as AIError {
            if case .providerError(let msg) = error {
                #expect(msg.contains("-1"))
            } else {
                Issue.record("Expected .providerError, got \(error)")
            }
        } catch {
            Issue.record("Expected AIError, got \(error)")
        }

        #expect(AnthropicStubURLProtocol.capturedRequests.isEmpty, "Provider must not issue a request when maxTokens is invalid")
    }

    // Note: streamRequest behavior is covered by AnthropicProviderStreamingTests
    // (WI-4 shipped the real SSE parser; the WI-3 "not-yet-implemented" stub
    // assertion has been retired).
}
