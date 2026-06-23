// Purpose: feature #118 WI-2 (#110 Phase 3) — the AI client value types + typed errors, mirroring
// iOS AITypes (AIRequest/AIResponse/AIStreamChunk/AIError). Provider-neutral; the OpenAI vs
// Anthropic wire differences live in the providers.
package com.vreader.app.ai

enum class AiRole { system, user, assistant }

data class AiMessage(val role: AiRole, val content: String)

/** A chat request. `system` is the system prompt (Anthropic carries it top-level; the OpenAI
 *  provider prepends it as a system message). */
data class AiRequest(
    val model: String,
    val messages: List<AiMessage>,
    val temperature: Double,
    val maxTokens: Int,
    val system: String? = null,
)

/** One streamed delta (the incremental assistant text). */
data class AiChunk(val deltaText: String)

/** A one-shot (non-streamed) response. */
data class AiResponse(val text: String)

/** Typed AI failures (HTTP + transport + protocol). */
sealed class AiError(message: String) : Exception(message) {
    object Auth401 : AiError("authentication failed (401) — check the API key")
    object RateLimited429 : AiError("rate limited (429) — try again shortly")
    object Offline : AiError("the provider couldn't be reached")
    object Timeout : AiError("the provider took too long to respond")
    class Http(val code: Int) : AiError("HTTP $code from the provider")
    class Decode(detail: String) : AiError("couldn't parse the provider response: $detail")
    class Stream(detail: String) : AiError("the stream ended abnormally: $detail")
    /** Refused to send the API key over cleartext http:// to a non-local host. */
    object InsecureUrl : AiError("the provider URL must be https:// (won't send the key over cleartext)")
    class Config(detail: String) : AiError("provider misconfigured: $detail")
}

/** Test-connection outcome (the editor's Connection section). */
sealed interface AiTestResult {
    object Ok : AiTestResult
    data class Fail(val error: AiError, val message: String) : AiTestResult
}
