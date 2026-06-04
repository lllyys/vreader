// Purpose: AnthropicProvider — concrete `AIProvider` for the Anthropic
// Messages API. `sendRequest` (non-streaming) shipped in feature #50
// WI-3; `streamRequest` (SSE) shipped in WI-4.
//
// On-the-wire shape (from plan `dev-docs/plans/20260510-feature-50-...`):
// - POST <baseURL>/v1/messages
// - x-api-key: <key>            (NOT Authorization: Bearer — that's OpenAI)
// - anthropic-version: 2023-06-01  (GA-stable version pin, see plan risks)
// - Content-Type: application/json
// - Body:
//   { "model": "...",
//     "max_tokens": <int, REQUIRED by Anthropic>,
//     "system": "<system prompt>",       // top-level — NOT inside messages
//     "messages": [ { "role": "user", "content": "..." } ] }
// - Response:
//   { "content": [ { "type": "text", "text": "..." }, ... ],
//     "stop_reason": "...", ... } → first text block is the answer
//
// HTTP error handling mirrors `OpenAICompatibleProvider.validateHTTPResponse`:
// 401/403 → `.providerError("Authentication ...")`,
// 429 → `.rateLimited(retryAfterSeconds:)` parsed from the `retry-after`
// header in seconds (HTTP-standard; the plan's round-1 audit finding [3]
// pinned this so we don't accidentally parse as ms),
// other 4xx/5xx → `.providerError("HTTP <code>: <body excerpt>")`.
//
// @coordinates-with: AIProvider.swift, AITypes.swift, AIError.swift,
//   ProviderKind.swift, ProviderProfile.swift

import Foundation

/// `AIProvider` implementation for the Anthropic Messages API.
///
/// Use one instance per active profile. The struct is `Sendable` (its
/// stored properties are value types or Sendable references), so it can
/// cross actor boundaries — `AIService.resolveProvider()` snapshots the
/// active profile and constructs one of these at request start.
struct AnthropicProvider: AIProvider, Sendable {

    let providerName: String
    let baseURL: URL
    let apiKey: String
    let model: String
    let maxTokens: Int
    let session: URLSession   // exposed for `AnthropicProvider+Streaming.swift`

    /// Anthropic Messages API version pin. Documented in the feature #50
    /// plan: the API requires a non-empty `anthropic-version` header and
    /// the GA-stable value is `2023-06-01`. Bumping this is a deliberate
    /// follow-up — never auto-upgrade.
    static let anthropicVersionHeader = "2023-06-01"

    /// Default `max_tokens` when callers don't override. Anthropic requires
    /// `max_tokens` on every request (unlike OpenAI which infers from
    /// model capacity). 4096 matches typical chat response sizes.
    static let defaultMaxTokens = 4096

    init(
        providerName: String = "Anthropic",
        baseURL: URL = URL(string: "https://api.anthropic.com")!,
        apiKey: String,
        model: String = "claude-sonnet-4-6",
        maxTokens: Int = AnthropicProvider.defaultMaxTokens,
        session: URLSession = .shared
    ) {
        self.providerName = providerName
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.maxTokens = maxTokens
        self.session = session
    }

    // MARK: - AIProvider

    func sendRequest(_ request: AIRequest) async throws -> AIResponse {
        let urlRequest = try buildURLRequest(for: request, stream: false)
        let (data, response) = try await session.data(for: urlRequest)

        try validateHTTPResponse(response, data: data)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.invalidResponse
        }
        // Anthropic returns `content: [{type, text}, ...]`. We take the
        // first text block. If `content` is missing, empty, or the first
        // block has no `text`, that's an invalid response.
        guard let blocks = json["content"] as? [[String: Any]], !blocks.isEmpty else {
            throw AIError.invalidResponse
        }
        // The first text-type block is the assistant's reply. (Anthropic
        // may emit non-text blocks like `tool_use` in future, but the
        // model is configured for plain chat here so we expect `text`.)
        let firstText = blocks.compactMap { $0["text"] as? String }.first
        guard let content = firstText, !content.isEmpty else {
            throw AIError.invalidResponse
        }

        return AIResponse(
            content: content,
            actionType: request.actionType,
            promptVersion: request.promptVersion,
            createdAt: Date()
        )
    }

    // `streamRequest` lives in `AnthropicProvider+Streaming.swift` —
    // SSE parsing + per-stream HTTP error-body buffering are isolated
    // there to keep this file under the ~300-line convention.

    // MARK: - Request construction

    func buildURLRequest(for request: AIRequest, stream: Bool) throws -> URLRequest {
        var urlRequest = try makeMessagesURLRequest(validatingMaxTokens: maxTokens)

        let systemPrompt = buildSystemPrompt(for: request.actionType)
        let userMessage = buildUserMessage(for: request)

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userMessage]
            ]
        ]
        if stream {
            body["stream"] = true
        }

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    /// Shared `/v1/messages` POST scaffolding (validation + endpoint + headers)
    /// for both the plain-chat `buildURLRequest` and the Feature #91 tool-use
    /// `buildToolURLRequest`. The caller sets `httpBody`. `validatingMaxTokens` is
    /// the EFFECTIVE budget the caller will actually emit (Gate-4 Low: the tool
    /// path's per-request override means the profile value alone is the wrong
    /// thing to validate).
    func makeMessagesURLRequest(validatingMaxTokens effectiveMaxTokens: Int) throws -> URLRequest {
        // Anthropic requires `max_tokens >= 1` (per Messages API docs). We
        // validate here rather than at init so misconfigured profiles
        // surface as a clean `AIError` to UI instead of a precondition
        // trap on profile load. Sending the value untouched would also
        // work (the API returns 400) but burns a network round trip and
        // produces a less specific error message.
        guard effectiveMaxTokens >= 1 else {
            throw AIError.providerError(
                "\(providerName) profile is misconfigured: max_tokens must be >= 1 (got \(effectiveMaxTokens))."
            )
        }

        // Only send API key over HTTPS (or localhost for local-LLM proxy
        // testing). Matches `OpenAICompatibleProvider`'s policy.
        let isLocalhost = baseURL.host == "localhost" || baseURL.host == "127.0.0.1"
        guard baseURL.scheme == "https" || isLocalhost else {
            throw AIError.networkError(
                "API key requires HTTPS connection (got \(baseURL.scheme ?? "none"))"
            )
        }

        let endpoint = baseURL.appendingPathComponent("v1/messages")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(
            Self.anthropicVersionHeader,
            forHTTPHeaderField: "anthropic-version"
        )
        return urlRequest
    }

    private func buildSystemPrompt(for actionType: AIActionType) -> String {
        // Mirror `OpenAICompatibleProvider.buildSystemPrompt` so the same
        // user-facing prompts work across providers. If a prompt change is
        // needed for one provider only, branch here later.
        switch actionType {
        case .summarize:
            return "You are a reading assistant. Summarize the provided text concisely."
        case .explain:
            return "You are a reading assistant. Explain the provided text clearly and simply."
        case .translate:
            return "You are a translation assistant. Translate the provided text accurately."
        case .vocabulary:
            return "You are a vocabulary assistant. Define and explain key terms in the text."
        case .questionAnswer:
            return "You are a reading assistant. Answer questions about the provided text."
        }
    }

    private func buildUserMessage(for request: AIRequest) -> String {
        var message = request.contextText
        if let prompt = request.userPrompt, !prompt.isEmpty {
            message += "\n\nQuestion: \(prompt)"
        }
        if let lang = request.targetLanguage, !lang.isEmpty {
            message += "\n\nTranslate to: \(lang)"
        }
        return message
    }

    // MARK: - Response validation

    // `validateStreamingHTTPResponse` (with error-body buffering for
    // non-2xx streaming responses) lives in `AnthropicProvider+Streaming.swift`.

    func validateHTTPResponse(_ response: URLResponse, data: Data?) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.networkError("Invalid response type")
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return
        case 429:
            // Anthropic's `retry-after` header is in seconds (per HTTP
            // RFC 7231 §7.1.3 and the plan's round-1 audit finding [3]).
            let retryAfter = httpResponse.value(forHTTPHeaderField: "retry-after")
                .flatMap { Int($0) }
            throw AIError.rateLimited(retryAfterSeconds: retryAfter)
        case 401:
            throw AIError.providerError(
                "Authentication failed (HTTP 401) — check the \(providerName) API key for this profile."
            )
        case 403:
            // 403 from Anthropic typically means the key is valid but
            // lacks access to the configured model/workspace (or the
            // workspace is gated). Don't tell the user the key is wrong
            // when it isn't — point them at access too.
            throw AIError.providerError(
                "Authorization failed (HTTP 403) — the \(providerName) API key for this profile lacks access to the configured model or workspace."
            )
        default:
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "No body"
            let truncated = body.count > 200 ? String(body.prefix(200)) + "…" : body
            throw AIError.providerError("HTTP \(httpResponse.statusCode): \(truncated)")
        }
    }
}
