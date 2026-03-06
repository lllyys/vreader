// Purpose: Protocol abstraction over LLM providers and OpenAI-compatible implementation.
// Decouples the AI service from any specific provider, enabling testing with stubs.
//
// Key decisions:
// - Protocol is Sendable for cross-actor use.
// - sendRequest is async throws for one-shot responses.
// - streamRequest returns AsyncThrowingStream for incremental display.
// - OpenAICompatibleProvider uses URLSession for HTTP and parses SSE for streaming.
// - SSE parsing handles the "[DONE]" sentinel and partial JSON lines.
// - No retry logic here — that belongs in the coordinator (AIService).
//
// @coordinates-with: AIService.swift, AITypes.swift

import Foundation

/// Abstraction over an LLM provider.
protocol AIProvider: Sendable {
    /// Sends a one-shot request and returns the complete response.
    func sendRequest(_ request: AIRequest) async throws -> AIResponse

    /// Streams a request, yielding incremental chunks.
    func streamRequest(_ request: AIRequest) -> AsyncThrowingStream<AIStreamChunk, Error>

    /// Human-readable name for this provider (e.g., "OpenAI", "Local LLM").
    var providerName: String { get }
}

/// An AI provider that speaks the OpenAI-compatible chat completions API.
/// Works with OpenAI, Azure OpenAI, local LLMs (Ollama, LM Studio), etc.
struct OpenAICompatibleProvider: AIProvider, Sendable {

    let providerName: String
    let baseURL: URL
    let apiKey: String
    let model: String
    private let session: URLSession

    init(
        providerName: String = "OpenAI",
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        apiKey: String,
        model: String = "gpt-4o-mini",
        session: URLSession = .shared
    ) {
        self.providerName = providerName
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    func sendRequest(_ request: AIRequest) async throws -> AIResponse {
        let urlRequest = try buildURLRequest(for: request, stream: false)
        let (data, response) = try await session.data(for: urlRequest)

        try validateHTTPResponse(response, data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIError.invalidResponse
        }

        return AIResponse(
            content: content,
            actionType: request.actionType,
            promptVersion: request.promptVersion,
            createdAt: Date()
        )
    }

    func streamRequest(_ request: AIRequest) -> AsyncThrowingStream<AIStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let urlRequest = try buildURLRequest(for: request, stream: true)
                    let (bytes, response) = try await session.bytes(for: urlRequest)

                    try validateHTTPResponse(response, data: nil)

                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let payload = String(line.dropFirst(6))
                            if payload == "[DONE]" {
                                continuation.yield(AIStreamChunk(text: "", isComplete: true))
                                break
                            }
                            if let data = payload.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let choices = json["choices"] as? [[String: Any]],
                               let delta = choices.first?["delta"] as? [String: Any],
                               let content = delta["content"] as? String {
                                continuation.yield(AIStreamChunk(text: content, isComplete: false))
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private

    private func buildURLRequest(for request: AIRequest, stream: Bool) throws -> URLRequest {
        // Only send API key over HTTPS (or localhost for local LLM testing)
        let isLocalhost = baseURL.host == "localhost" || baseURL.host == "127.0.0.1"
        guard baseURL.scheme == "https" || isLocalhost else {
            throw AIError.networkError("API key requires HTTPS connection (got \(baseURL.scheme ?? "none"))")
        }

        let endpoint = baseURL.appendingPathComponent("chat/completions")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let systemPrompt = buildSystemPrompt(for: request.actionType)
        let userMessage = buildUserMessage(for: request)

        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage],
            ],
        ]
        if stream {
            body["stream"] = true
        }

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    private func buildSystemPrompt(for actionType: AIActionType) -> String {
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

    private func validateHTTPResponse(_ response: URLResponse, data: Data?) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.networkError("Invalid response type")
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap { Int($0) }
            throw AIError.rateLimited(retryAfterSeconds: retryAfter)
        case 401, 403:
            throw AIError.providerError("Authentication failed (HTTP \(httpResponse.statusCode))")
        default:
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "No body"
            throw AIError.providerError("HTTP \(httpResponse.statusCode): \(body)")
        }
    }
}
