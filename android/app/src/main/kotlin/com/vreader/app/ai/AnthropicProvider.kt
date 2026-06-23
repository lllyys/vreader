// Purpose: feature #118 WI-2 (#110 Phase 3) — the Anthropic Messages client. POST <baseUrl>/v1/
// messages, x-api-key (NOT Authorization: Bearer) + anthropic-version: 2023-06-01. Stream is
// event-typed SSE: `content_block_delta` events carry `delta.text`; `message_stop` ends; an
// `error` event throws. `system` is a top-level field (not a message). One-shot: `content[0].text`.
// Mirrors iOS AnthropicProvider.
package com.vreader.app.ai

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import java.net.HttpURLConnection

class AnthropicProvider(
    baseUrl: String,
    apiKey: String,
    model: String,
    temperature: Double,
    maxTokens: Int,
    dispatcher: CoroutineDispatcher = Dispatchers.IO,
) : BaseHttpAiClient(baseUrl, apiKey, model, temperature, maxTokens, dispatcher) {

    override val endpointPath = "/v1/messages"

    override fun applyAuth(conn: HttpURLConnection) {
        conn.setRequestProperty("x-api-key", apiKey)  // never logged
        conn.setRequestProperty("anthropic-version", ANTHROPIC_VERSION)
    }

    override fun requestBody(request: AiRequest, stream: Boolean): String = buildJsonObject {
        put("model", request.model)
        put("max_tokens", request.maxTokens)
        put("temperature", request.temperature)
        put("stream", stream)
        request.system?.let { put("system", it) }  // top-level, not a message
        putJsonArray("messages") {
            request.messages.forEach { m ->
                // Anthropic accepts user/assistant only; a stray system message folds to user.
                val role = if (m.role == AiRole.assistant) "assistant" else "user"
                addJsonObject { put("role", role); put("content", m.content) }
            }
        }
    }.toString()

    override fun parseDelta(event: SseEvent): DeltaParse {
        // Prefer the event-type line; fall back to the data's own `type` (some servers omit event:).
        val data = runCatching { JSON.parseToJsonElement(event.data).jsonObject }.getOrNull()
        val type = event.event ?: data?.get("type")?.jsonPrimitive?.content
        return when (type) {
            "message_stop" -> DeltaParse(null, done = true)
            "error" -> throw AiError.Stream(data?.get("error")?.jsonObject?.get("message")?.jsonPrimitive?.content ?: "provider error")
            "content_block_delta" -> {
                val text = data?.get("delta")?.jsonObject?.get("text")?.jsonPrimitive?.content
                DeltaParse(text, done = false)
            }
            else -> DeltaParse(null, done = false)  // message_start / ping / content_block_start/stop
        }
    }

    override fun parseOneShot(json: String): String =
        runCatching {
            JSON.parseToJsonElement(json).jsonObject["content"]?.jsonArray
                ?.firstOrNull()?.jsonObject?.get("text")?.jsonPrimitive?.content
        }.getOrNull() ?: throw AiError.Decode("no content[0].text")

    private companion object {
        const val ANTHROPIC_VERSION = "2023-06-01"
        val JSON = Json { ignoreUnknownKeys = true }
    }
}
