// Purpose: Tests for AnthropicProvider streaming — feature #50 WI-4.
// SSE event parsing: `content_block_delta` yields text deltas;
// `message_stop` terminates the stream; `error` events raise through;
// `message_start` / `content_block_start` / `content_block_stop` /
// `message_delta` / `ping` events are ignored; partial-line buffering
// across `Data` chunks correct; UTF-8 multi-byte mid-character split
// buffered correctly (plan round-1 audit finding [2']); HTTP error
// codes (401/429/5xx) surface as the matching AIError before any
// stream chunks are yielded.
//
// Non-streaming sendRequest is covered by AnthropicProviderTests
// (WI-3). This file complements that with streaming-only paths.
//
// @coordinates-with: AnthropicProvider.swift, AIProvider.swift,
//   AITypes.swift, AIError.swift
//
// Suite is `.serialized` for the same reason as the WI-3 suite:
// per-suite static URLProtocol stub state would race under default
// parallel Swift Testing execution.

import Testing
import Foundation
@testable import vreader

// MARK: - Stub URLProtocol for streaming

/// Streaming-only URLProtocol stub. Separate from the non-streaming
/// `AnthropicStubURLProtocol` so the two test files can use independent
/// handler state without serializing across files. Delivers data in
/// configurable chunks to exercise partial-line / mid-byte buffering.
final class AnthropicStreamingStubURLProtocol: URLProtocol, @unchecked Sendable {
    /// Returns (response, [bodyChunks]) for the request. Each chunk is
    /// delivered as a separate `didLoad` call, which is what allows tests
    /// to verify the SSE parser handles partial lines across data
    /// boundaries.
    nonisolated(unsafe) static var requestHandler: ((URLRequest) -> (HTTPURLResponse, [Data]))?

    nonisolated(unsafe) static var capturedRequests: [URLRequest] = []
    nonisolated(unsafe) static var capturedBodies: [Data] = []

    override class func canInit(with request: URLRequest) -> Bool {
        if let body = request.httpBody {
            capturedBodies.append(body)
        } else if let stream = request.httpBodyStream {
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
        let (response, chunks) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in chunks {
            client?.urlProtocol(self, didLoad: chunk)
        }
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
    config.protocolClasses = [AnthropicStreamingStubURLProtocol.self]
    return URLSession(configuration: config)
}

private func makeResponse(url: URL, status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
    var allHeaders = headers
    if allHeaders["Content-Type"] == nil {
        allHeaders["Content-Type"] = "text/event-stream"
    }
    return HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: allHeaders)!
}

private func makeRequest(actionType: AIActionType = .summarize, context: String = "Hello.") -> AIRequest {
    AIRequest(
        actionType: actionType,
        bookFingerprint: nil,
        locator: nil,
        contextText: context,
        userPrompt: nil,
        targetLanguage: nil,
        promptVersion: "test-v1"
    )
}

private func makeProvider(
    baseURL: URL = URL(string: "https://api.anthropic.com")!,
    apiKey: String = "sk-ant-test-key",
    model: String = "claude-sonnet-4-6",
    maxTokens: Int = 4096
) -> AnthropicProvider {
    AnthropicProvider(
        baseURL: baseURL,
        apiKey: apiKey,
        model: model,
        maxTokens: maxTokens,
        session: makeStubSession()
    )
}

/// Build a single SSE event block in Anthropic's exact wire format:
/// `event: <name>\ndata: <json>\n\n`. Multiple events concatenate into
/// the body chunks the stub returns.
private func sseEvent(_ name: String, _ json: String) -> String {
    "event: \(name)\ndata: \(json)\n\n"
}

/// Drain a stream into [chunks], capturing each yield AND the final
/// thrown error (if any). Bounded by a timeout token to avoid hangs.
private func drain(_ stream: AsyncThrowingStream<AIStreamChunk, Error>) async -> (chunks: [AIStreamChunk], error: Error?) {
    var chunks: [AIStreamChunk] = []
    do {
        for try await chunk in stream {
            chunks.append(chunk)
        }
        return (chunks, nil)
    } catch {
        return (chunks, error)
    }
}

// MARK: - Tests

@Suite("AnthropicProvider — streamRequest (WI-4)", .serialized)
struct AnthropicProviderStreamingTests {

    init() { AnthropicStreamingStubURLProtocol.reset() }

    // MARK: - Body shape — stream flag set

    @Test func streamRequest_bodyShape_setsStreamTrue() async throws {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        AnthropicStreamingStubURLProtocol.requestHandler = { _ in
            let body = sseEvent("message_stop", #"{"type":"message_stop"}"#).data(using: .utf8)!
            return (makeResponse(url: url, status: 200), [body])
        }
        let provider = makeProvider()
        _ = await drain(provider.streamRequest(makeRequest()))

        let body = AnthropicStreamingStubURLProtocol.capturedBodies.last
        #expect(body != nil, "Provider must have issued a streaming request")
        let json = try JSONSerialization.jsonObject(with: body!) as? [String: Any]
        #expect(json?["stream"] as? Bool == true, "streamRequest must set body.stream = true")
        // Headers + endpoint identical to sendRequest — sanity-check Anthropic-version + x-api-key still present.
        let captured = AnthropicStreamingStubURLProtocol.capturedRequests.last
        #expect(captured?.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test-key")
        #expect(captured?.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(captured?.url == url)
    }

    // MARK: - Happy path: content_block_delta yields, message_stop terminates

    @Test func streamRequest_yieldsTextDeltasInOrder() async throws {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        let events =
            sseEvent("message_start", #"{"type":"message_start","message":{"id":"msg_1"}}"#) +
            sseEvent("content_block_start", #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#) +
            sseEvent("content_block_delta", #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#) +
            sseEvent("content_block_delta", #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":", "}}"#) +
            sseEvent("content_block_delta", #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"world!"}}"#) +
            sseEvent("content_block_stop", #"{"type":"content_block_stop","index":0}"#) +
            sseEvent("message_delta", #"{"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#) +
            sseEvent("message_stop", #"{"type":"message_stop"}"#)
        AnthropicStreamingStubURLProtocol.requestHandler = { _ in
            (makeResponse(url: url, status: 200), [events.data(using: .utf8)!])
        }
        let provider = makeProvider()

        let (chunks, error) = await drain(provider.streamRequest(makeRequest()))

        #expect(error == nil, "Happy-path stream must not throw; got \(String(describing: error))")
        // Text deltas join to the full message.
        let assembled = chunks.filter { !$0.isComplete }.map(\.text).joined()
        #expect(assembled == "Hello, world!", "Text deltas must be yielded in order; got '\(assembled)'")
        // A final isComplete-true chunk MUST follow the deltas — the
        // existing OpenAI path establishes this contract; Anthropic must
        // match so callers can use the same terminator detection.
        #expect(chunks.last?.isComplete == true, "Last yielded chunk must have isComplete=true (matches OpenAI sentinel contract)")
    }

    // MARK: - Ignored events (message_start, content_block_start, content_block_stop, message_delta, ping)

    @Test func streamRequest_ignoresNonDeltaEvents() async throws {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        // Only non-delta events + final message_stop. Should yield ONLY the
        // terminator (isComplete=true), no text chunks.
        let events =
            sseEvent("message_start", #"{"type":"message_start","message":{"id":"msg_1"}}"#) +
            sseEvent("content_block_start", #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#) +
            sseEvent("content_block_stop", #"{"type":"content_block_stop","index":0}"#) +
            sseEvent("message_delta", #"{"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#) +
            sseEvent("ping", #"{"type":"ping"}"#) +
            sseEvent("message_stop", #"{"type":"message_stop"}"#)
        AnthropicStreamingStubURLProtocol.requestHandler = { _ in
            (makeResponse(url: url, status: 200), [events.data(using: .utf8)!])
        }
        let provider = makeProvider()

        let (chunks, error) = await drain(provider.streamRequest(makeRequest()))
        #expect(error == nil)
        let textChunks = chunks.filter { !$0.isComplete && !$0.text.isEmpty }
        #expect(textChunks.isEmpty, "Non-delta events must not yield text chunks; got \(textChunks.map(\.text))")
        #expect(chunks.last?.isComplete == true)
    }

    // MARK: - Error event raises through the stream

    @Test func streamRequest_errorEvent_throwsProviderError() async throws {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        let events =
            sseEvent("content_block_delta", #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"start"}}"#) +
            sseEvent("error", #"{"type":"error","error":{"type":"overloaded_error","message":"Anthropic is over capacity"}}"#)
        AnthropicStreamingStubURLProtocol.requestHandler = { _ in
            (makeResponse(url: url, status: 200), [events.data(using: .utf8)!])
        }
        let provider = makeProvider()

        let (chunks, error) = await drain(provider.streamRequest(makeRequest()))
        // The "start" delta should arrive BEFORE the error throws — partial
        // delivery is part of the streaming contract.
        #expect(chunks.contains { $0.text == "start" }, "Pre-error text deltas must still be delivered to the caller")
        #expect(error != nil, "Error event must surface as a thrown error")
        if let aiError = error as? AIError {
            if case .providerError(let msg) = aiError {
                // Error body details should reach the user — they're often actionable.
                #expect(msg.contains("overloaded") || msg.contains("over capacity") || msg.lowercased().contains("error"), "Provider error should surface the Anthropic error message; got: \(msg)")
            } else {
                Issue.record("Expected .providerError, got \(aiError)")
            }
        } else {
            Issue.record("Expected AIError, got \(String(describing: error))")
        }
    }

    // MARK: - Partial-line buffering across Data chunks

    @Test func streamRequest_buffersPartialLinesAcrossChunks() async throws {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        // Build the full SSE byte stream, then deliver it in tiny chunks
        // that split lines in the middle. The parser MUST reassemble lines
        // correctly across chunks.
        let full = (sseEvent("content_block_delta", #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"abc"}}"#) +
                    sseEvent("content_block_delta", #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"def"}}"#) +
                    sseEvent("message_stop", #"{"type":"message_stop"}"#)).data(using: .utf8)!
        // Split into 7-byte chunks — small enough to land inside data: lines
        // and inside the JSON payload.
        var chunks: [Data] = []
        let chunkSize = 7
        var idx = 0
        while idx < full.count {
            let end = min(idx + chunkSize, full.count)
            chunks.append(full.subdata(in: idx..<end))
            idx = end
        }
        AnthropicStreamingStubURLProtocol.requestHandler = { _ in
            (makeResponse(url: url, status: 200), chunks)
        }
        let provider = makeProvider()

        let (yielded, error) = await drain(provider.streamRequest(makeRequest()))
        #expect(error == nil, "Partial-line buffering must not lose data or throw; got \(String(describing: error))")
        let assembled = yielded.filter { !$0.isComplete }.map(\.text).joined()
        #expect(assembled == "abcdef", "Deltas must reassemble correctly across tiny chunk splits; got '\(assembled)'")
    }

    // MARK: - UTF-8 multi-byte mid-character split

    @Test func streamRequest_handlesUTF8MidCharacterSplit() async throws {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        // CJK character "你" is 3 UTF-8 bytes: 0xE4 0xBD 0xA0. We craft a
        // chunk boundary that splits it mid-character to confirm the
        // underlying byte → line decoder buffers correctly. Encode the
        // CJK string into the data delta literally (no escape) and split
        // the body bytes at the very middle of the encoded character.
        let json = #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"你好"}}"#
        let full = (sseEvent("content_block_delta", json) +
                    sseEvent("message_stop", #"{"type":"message_stop"}"#)).data(using: .utf8)!

        // Find the byte index of the CJK character inside the body.
        // ASCII prefix length up to the first CJK byte = location of "你"
        // in the full payload string when encoded to UTF-8.
        let nihaoUTF8: [UInt8] = [0xE4, 0xBD, 0xA0]   // "你"
        var splitIndex = 0
        outer: for i in 0..<(full.count - 2) {
            if full[i] == nihaoUTF8[0] && full[i+1] == nihaoUTF8[1] && full[i+2] == nihaoUTF8[2] {
                splitIndex = i + 1   // split BETWEEN byte 0 and byte 1 of the 3-byte char
                break outer
            }
        }
        #expect(splitIndex > 0, "Test fixture: must have located '你' inside the encoded SSE body")

        let chunkA = full.subdata(in: 0..<splitIndex)
        let chunkB = full.subdata(in: splitIndex..<full.count)
        AnthropicStreamingStubURLProtocol.requestHandler = { _ in
            (makeResponse(url: url, status: 200), [chunkA, chunkB])
        }
        let provider = makeProvider()

        let (yielded, error) = await drain(provider.streamRequest(makeRequest()))
        #expect(error == nil, "UTF-8 mid-byte split must not lose data; got \(String(describing: error))")
        let assembled = yielded.filter { !$0.isComplete }.map(\.text).joined()
        #expect(assembled == "你好", "Multi-byte UTF-8 character split across chunks must reassemble correctly; got '\(assembled)'")
    }

    // MARK: - Unknown event types are silently skipped (forward-compat)

    @Test func streamRequest_unknownEventTypesSkipped() async throws {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        let events =
            sseEvent("content_block_delta", #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"hi"}}"#) +
            // Future-Anthropic-API-might-add events: parser must ignore.
            sseEvent("future_event_we_dont_know", #"{"type":"future_event_we_dont_know","payload":42}"#) +
            sseEvent("message_stop", #"{"type":"message_stop"}"#)
        AnthropicStreamingStubURLProtocol.requestHandler = { _ in
            (makeResponse(url: url, status: 200), [events.data(using: .utf8)!])
        }
        let provider = makeProvider()

        let (chunks, error) = await drain(provider.streamRequest(makeRequest()))
        #expect(error == nil, "Unknown event types must NOT raise — forward-compat with future Anthropic SSE additions")
        let assembled = chunks.filter { !$0.isComplete }.map(\.text).joined()
        #expect(assembled == "hi")
    }

    // MARK: - Malformed JSON on a data line is skipped (not a fatal error)

    @Test func streamRequest_malformedDataLineSkipped() async throws {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        // Inject a `data:` line whose payload isn't valid JSON — parser
        // should log-and-skip rather than abort the stream.
        let events =
            sseEvent("content_block_delta", #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"good"}}"#) +
            "event: content_block_delta\ndata: not-actual-json{{\n\n" +
            sseEvent("content_block_delta", #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"-bye"}}"#) +
            sseEvent("message_stop", #"{"type":"message_stop"}"#)
        AnthropicStreamingStubURLProtocol.requestHandler = { _ in
            (makeResponse(url: url, status: 200), [events.data(using: .utf8)!])
        }
        let provider = makeProvider()

        let (chunks, error) = await drain(provider.streamRequest(makeRequest()))
        #expect(error == nil, "Malformed data lines must be skipped, not fatal")
        let assembled = chunks.filter { !$0.isComplete }.map(\.text).joined()
        #expect(assembled == "good-bye", "Surrounding valid deltas must still be delivered; got '\(assembled)'")
    }

    // MARK: - HTTP error codes before any stream data

    @Test func streamRequest_401_throwsAuthenticationFailed() async throws {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        AnthropicStreamingStubURLProtocol.requestHandler = { _ in
            (makeResponse(url: url, status: 401), [Data()])
        }
        let provider = makeProvider()

        let (chunks, error) = await drain(provider.streamRequest(makeRequest()))
        #expect(chunks.isEmpty, "No chunks should be yielded on a 401 — HTTP failure precedes any stream data")
        if let aiError = error as? AIError, case .providerError(let msg) = aiError {
            let lower = msg.lowercased()
            #expect(lower.contains("authentication") || msg.contains("401"))
            #expect(!lower.contains("workspace"), "401 must not mention workspace access (that's 403)")
        } else {
            Issue.record("Expected .providerError(401), got \(String(describing: error))")
        }
    }

    @Test func streamRequest_403_throwsAuthorizationFailed_distinctFrom401() async throws {
        // Codex Gate-4 round-1 Low #4: 403 in the streaming path must
        // surface the same distinct authorization-vs-authentication message
        // as the non-streaming path, and it must interpolate `providerName`.
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        let errBody = #"{"type":"error","error":{"type":"permission_error","message":"This API key does not have access to claude-opus-4."}}"#
        AnthropicStreamingStubURLProtocol.requestHandler = { _ in
            (makeResponse(url: url, status: 403), [errBody.data(using: .utf8)!])
        }
        let provider = AnthropicProvider(
            providerName: "MyCustomProfile",
            apiKey: "sk-ant-x",
            session: makeStubSession()
        )

        let (chunks, error) = await drain(provider.streamRequest(makeRequest()))
        #expect(chunks.isEmpty)
        if let aiError = error as? AIError, case .providerError(let msg) = aiError {
            let lower = msg.lowercased()
            #expect(msg.contains("403"))
            #expect(lower.contains("authorization") || lower.contains("access") || lower.contains("workspace") || lower.contains("model"), "403 message must mention authorization/access/model/workspace; got: \(msg)")
            #expect(msg.contains("MyCustomProfile"), "403 message must interpolate providerName for renamed profiles; got: \(msg)")
        } else {
            Issue.record("Expected .providerError(403), got \(String(describing: error))")
        }
    }

    @Test func streamRequest_429_throwsRateLimitedWithRetryAfter() async throws {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        AnthropicStreamingStubURLProtocol.requestHandler = { _ in
            (makeResponse(url: url, status: 429, headers: ["retry-after": "17"]), [Data()])
        }
        let provider = makeProvider()

        let (chunks, error) = await drain(provider.streamRequest(makeRequest()))
        #expect(chunks.isEmpty)
        if let aiError = error as? AIError, case .rateLimited(let retryAfter) = aiError {
            #expect(retryAfter == 17, "retry-after must be parsed as seconds; got \(String(describing: retryAfter))")
        } else {
            Issue.record("Expected .rateLimited, got \(String(describing: error))")
        }
    }

    @Test func streamRequest_5xx_throwsProviderError() async throws {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        AnthropicStreamingStubURLProtocol.requestHandler = { _ in
            (makeResponse(url: url, status: 503), [Data()])
        }
        let provider = makeProvider()

        let (chunks, error) = await drain(provider.streamRequest(makeRequest()))
        #expect(chunks.isEmpty)
        if let aiError = error as? AIError, case .providerError(let msg) = aiError {
            #expect(msg.contains("503"))
        } else {
            Issue.record("Expected .providerError(503), got \(String(describing: error))")
        }
    }

    // MARK: - Pre-network validation (matches WI-3 contract)

    @Test func streamRequest_rejectsZeroMaxTokens_beforeNetwork() async throws {
        let provider = makeProvider(maxTokens: 0)

        let (chunks, error) = await drain(provider.streamRequest(makeRequest()))
        #expect(chunks.isEmpty)
        if let aiError = error as? AIError, case .providerError(let msg) = aiError {
            #expect(msg.lowercased().contains("max_tokens") || msg.lowercased().contains("max tokens"))
        } else {
            Issue.record("Expected .providerError(max_tokens), got \(String(describing: error))")
        }
        #expect(AnthropicStreamingStubURLProtocol.capturedRequests.isEmpty, "Must not issue a network request when maxTokens is invalid")
    }

    @Test func streamRequest_rejectsNonHTTPSNonLocalhost() async throws {
        let httpURL = URL(string: "http://api.anthropic.com")!
        let provider = makeProvider(baseURL: httpURL)

        let (chunks, error) = await drain(provider.streamRequest(makeRequest()))
        #expect(chunks.isEmpty)
        if let aiError = error as? AIError {
            switch aiError {
            case .networkError(let msg):
                #expect(msg.lowercased().contains("https"))
            case .providerError(let msg):
                #expect(msg.lowercased().contains("https"))
            default:
                Issue.record("Expected .networkError or .providerError, got \(aiError)")
            }
        } else {
            Issue.record("Expected AIError, got \(String(describing: error))")
        }
        // Codex Gate-4 round-1 Low: must not even issue the network call.
        #expect(AnthropicStreamingStubURLProtocol.capturedRequests.isEmpty, "Non-HTTPS preflight must reject before any network call")
    }

    // MARK: - Premature transport EOF (Codex Gate-4 round-1 High)

    @Test func streamRequest_eofBeforeMessageStop_throwsProviderError() async throws {
        // Codex Gate-4 round-1 High: a stream that ends (transport EOF)
        // without delivering `message_stop` must NOT report success.
        // Callers like AIChatViewModel would otherwise keep the partial
        // assistant text with no signal that the rest never arrived.
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        let events =
            sseEvent("content_block_delta", #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"start of reply"}}"#)
            // No message_stop event — simulate connection drop.
        AnthropicStreamingStubURLProtocol.requestHandler = { _ in
            (makeResponse(url: url, status: 200), [events.data(using: .utf8)!])
        }
        let provider = makeProvider()

        let (chunks, error) = await drain(provider.streamRequest(makeRequest()))
        // Partial deltas still delivered to the caller.
        #expect(chunks.contains { $0.text == "start of reply" }, "Pre-EOF deltas must still be delivered before the truncation error")
        #expect(error != nil, "EOF without message_stop must surface as an error, not silent success")
        if let aiError = error as? AIError, case .providerError(let msg) = aiError {
            #expect(msg.contains("message_stop") || msg.lowercased().contains("truncated") || msg.lowercased().contains("connection"), "Truncation error should explain why; got: \(msg)")
        } else {
            Issue.record("Expected .providerError(truncated), got \(String(describing: error))")
        }
    }

    // MARK: - Streaming HTTP error body excerpt (Codex Gate-4 round-1 Medium)

    @Test func streamRequest_5xx_includesBodyExcerpt() async throws {
        // Codex Gate-4 round-1 Medium: the streaming path must include
        // the response body excerpt in the error message (matching the
        // non-streaming path's "HTTP <code>: <excerpt>" contract).
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        let errBody = #"{"type":"error","error":{"type":"api_error","message":"upstream timeout"}}"#
        AnthropicStreamingStubURLProtocol.requestHandler = { _ in
            (makeResponse(url: url, status: 503), [errBody.data(using: .utf8)!])
        }
        let provider = makeProvider()

        let (_, error) = await drain(provider.streamRequest(makeRequest()))
        if let aiError = error as? AIError, case .providerError(let msg) = aiError {
            #expect(msg.contains("503"))
            #expect(msg.contains("upstream timeout") || msg.contains("api_error"), "5xx streaming error must surface the response body excerpt, not just the status code; got: \(msg)")
        } else {
            Issue.record("Expected .providerError(503), got \(String(describing: error))")
        }
    }
}
