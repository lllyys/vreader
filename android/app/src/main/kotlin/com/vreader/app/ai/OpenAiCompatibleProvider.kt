// Purpose: feature #118 WI-2 (#110 Phase 3) — the OpenAI-compatible chat client (OpenAI, Azure,
// OpenRouter, Ollama, LM Studio, …). POST <baseUrl>/chat/completions, Authorization: Bearer.
// Stream: `data: {json}` lines, `choices[0].delta.content` deltas, `[DONE]` sentinel. One-shot:
// `choices[0].message.content`. Mirrors iOS OpenAICompatibleProvider.
package com.vreader.app.ai

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.add
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import java.net.HttpURLConnection

class OpenAiCompatibleProvider(
    baseUrl: String,
    apiKey: String,
    model: String,
    temperature: Double,
    maxTokens: Int,
    dispatcher: CoroutineDispatcher = Dispatchers.IO,
) : BaseHttpAiClient(baseUrl, apiKey, model, temperature, maxTokens, dispatcher) {

    override val endpointPath = "/chat/completions"

    override fun applyAuth(conn: HttpURLConnection) {
        conn.setRequestProperty("Authorization", "Bearer $apiKey")  // never logged
    }

    override fun requestBody(request: AiRequest, stream: Boolean): String = buildJsonObject {
        put("model", request.model)
        put("temperature", request.temperature)
        put("max_tokens", request.maxTokens)
        put("stream", stream)
        putJsonArray("messages") {
            request.system?.let { addJsonObject { put("role", "system"); put("content", it) } }
            request.messages.forEach { m ->
                addJsonObject { put("role", m.role.name); put("content", m.content) }
            }
        }
    }.toString()

    override fun parseDelta(event: SseEvent): DeltaParse {
        val data = event.data
        if (data == "[DONE]") return DeltaParse(null, done = true)
        val text = runCatching {
            JSON.parseToJsonElement(data).jsonObject["choices"]?.jsonArray
                ?.firstOrNull()?.jsonObject?.get("delta")?.jsonObject?.get("content")?.jsonPrimitive?.content
        }.getOrNull()
        return DeltaParse(text, done = false)
    }

    override fun parseOneShot(json: String): String =
        runCatching {
            JSON.parseToJsonElement(json).jsonObject["choices"]?.jsonArray
                ?.firstOrNull()?.jsonObject?.get("message")?.jsonObject?.get("content")?.jsonPrimitive?.content
        }.getOrNull() ?: throw AiError.Decode("no choices[0].message.content")

    private companion object { val JSON = Json { ignoreUnknownKeys = true } }
}
