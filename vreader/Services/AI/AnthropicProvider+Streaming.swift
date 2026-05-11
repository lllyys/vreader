// Purpose: AnthropicProvider streaming — feature #50 WI-4. SSE parser
// for the Anthropic Messages API. Split out of AnthropicProvider.swift
// to keep both files under the ~300-line conventions cap.
//
// Wire format: `event: <name>\ndata: <json>\n\n`. We dispatch on the
// `type` field inside each `data:` line's JSON (not the `event:`
// header — duplicate state with no benefit).
//
// Edge cases handled:
// - Partial-line buffering across `Data` chunks (URLSession.AsyncBytes
//   .lines buffers internally).
// - UTF-8 multi-byte mid-character splits across chunks (same).
// - Malformed `data:` lines → log-and-skip, not fatal.
// - Premature transport EOF (no `message_stop`) → throw, NOT silent
//   success — Codex Gate-4 round-1 High.
// - Streaming HTTP error body excerpt (1KB buffered before throwing
//   on non-2xx) — Codex Gate-4 round-1 Medium.
//
// @coordinates-with: AnthropicProvider.swift, AIProvider.swift,
//   AITypes.swift, AIError.swift

import Foundation
import OSLog

private let streamingLog = Logger(subsystem: "com.vreader.app", category: "AnthropicProviderStreaming")

extension AnthropicProvider {

    func streamRequest(_ request: AIRequest) -> AsyncThrowingStream<AIStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try buildURLRequest(for: request, stream: true)
                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    try await validateStreamingHTTPResponse(response, bytes: bytes)

                    // Track terminal sentinel so a premature transport
                    // EOF (network drop, server crash mid-stream) is
                    // surfaced as an error rather than silent success.
                    // Without this guard, callers like AIChatViewModel
                    // would keep the partial assistant text with no
                    // signal that the rest never arrived.
                    var sawMessageStop = false

                    // `URLSession.AsyncBytes.lines` buffers bytes until a
                    // newline and decodes UTF-8 across chunk boundaries,
                    // which makes the SSE parser tolerant of (a) tiny
                    // chunks splitting a line and (b) a multi-byte UTF-8
                    // character split across chunks.
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let type = json["type"] as? String else {
                            streamingLog.warning("\(self.providerName, privacy: .public) stream: skipping malformed data line (len=\(payload.count))")
                            continue
                        }

                        switch type {
                        case "content_block_delta":
                            if let delta = json["delta"] as? [String: Any],
                               let deltaType = delta["type"] as? String,
                               deltaType == "text_delta",
                               let text = delta["text"] as? String {
                                continuation.yield(AIStreamChunk(text: text, isComplete: false))
                            }
                        case "message_stop":
                            sawMessageStop = true
                            continuation.yield(AIStreamChunk(text: "", isComplete: true))
                            continuation.finish()
                            return
                        case "error":
                            let inner = json["error"] as? [String: Any]
                            let message = inner?["message"] as? String
                                ?? inner?["type"] as? String
                                ?? "Anthropic stream error"
                            throw AIError.providerError("\(self.providerName) stream error: \(message)")
                        default:
                            continue   // forward-compat: ignore unknown event types
                        }
                    }
                    // Reached EOF without a `message_stop`. Anthropic's
                    // streaming docs make `message_stop` the terminal
                    // event; absence almost always means the connection
                    // dropped mid-response, which we must NOT report as
                    // success.
                    if !sawMessageStop && !Task.isCancelled {
                        throw AIError.providerError(
                            "\(self.providerName) stream ended before message_stop — connection likely dropped mid-response."
                        )
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Streaming counterpart of `validateHTTPResponse`. On non-2xx we
    /// drain a small prefix of the body bytes so the `HTTP <code>: <…>`
    /// error message carries the same diagnostic excerpt the non-streaming
    /// path produces. On 2xx, the bytes stream is left untouched for the
    /// caller's SSE loop.
    fileprivate func validateStreamingHTTPResponse(
        _ response: URLResponse,
        bytes: URLSession.AsyncBytes
    ) async throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.networkError("Invalid response type")
        }
        if (200..<300).contains(httpResponse.statusCode) { return }

        // Non-2xx: read up to 1KB to compose an error excerpt before
        // throwing. Cap is intentional — error bodies are typically
        // small JSON; reading more risks blocking on a slow server.
        var buf = Data()
        do {
            for try await byte in bytes {
                buf.append(byte)
                if buf.count >= 1024 { break }
            }
        } catch {
            // Ignore body-read failure; surface the HTTP code anyway.
        }
        try validateHTTPResponse(response, data: buf.isEmpty ? nil : buf)
    }
}
