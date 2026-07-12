// Purpose: feature #131 WI-3 — a deterministic test double for the #118 AiClient,
// recording every chat(request) call so ChapterTranslationServiceTest can assert
// zero-call cache hits, per-chunk graceful degrade, and the segment→prompt wiring
// WITHOUT any real network. The bilingual pipeline only calls chat() (one-shot);
// streamChat()/testConnection() are never exercised by the service, so they throw
// if a future change accidentally reaches them.
//
// @coordinates-with: com.vreader.app.ai.AiClient, ChapterTranslationService.kt,
//   ChapterTranslationServiceTest.kt
package com.vreader.app.bilingual

import com.vreader.app.ai.AiChunk
import com.vreader.app.ai.AiRequest
import com.vreader.app.ai.AiResponse
import com.vreader.app.ai.AiTestResult
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow

/**
 * A scriptable [AiClient] test double. [chatHandler] receives each request (in call
 * order) and returns the raw [AiResponse.text] the service will decode; [requests]
 * records every request seen. The default handler echoes a valid JSON string-array of
 * the expected size so a straight-through translate succeeds.
 */
class FakeAiClient(
    private val chatHandler: suspend (AiRequest, callIndex: Int) -> AiResponse,
) : com.vreader.app.ai.AiClient {

    val requests = mutableListOf<AiRequest>()
    val callCount: Int get() = requests.size

    override fun streamChat(request: AiRequest): Flow<AiChunk> = emptyFlow()

    override suspend fun chat(request: AiRequest): AiResponse {
        // Honour cooperative cancellation just like the real client's chat() does
        // (BaseHttpAiClient checks the job on cancel) so cancellation tests are real.
        currentCoroutineContext().ensureActive()
        val index = requests.size
        requests.add(request)
        return chatHandler(request, index)
    }

    override suspend fun testConnection(): AiTestResult = AiTestResult.Ok

    companion object {
        /**
         * A client that, for each chunk request, extracts the numbered `[i] source`
         * segments from the prompt and returns a JSON string-array of `"T:<source>"`
         * translations of the right length — the "happy path" wire form.
         */
        fun translating(): FakeAiClient = FakeAiClient { request, _ ->
            val sources = extractSources(userText(request))
            val translated = sources.map { "T:$it" }
            AiResponse(encodeJsonArray(translated))
        }

        /** Pulls the last user message's content (the chunk prompt) from a request. */
        fun userText(request: AiRequest): String =
            request.messages.lastOrNull { it.role == com.vreader.app.ai.AiRole.user }?.content
                ?: request.messages.joinToString("\n") { it.content }

        /** Parses the `[i] source` numbered lines the contract's userPrompt emits. */
        fun extractSources(prompt: String): List<String> {
            val regex = Regex("""^\[(\d+)]\s(.*)$""", RegexOption.DOT_MATCHES_ALL)
            // The prompt numbers segments as "[0] seg\n\n[1] seg". Split on the blank
            // line the contract uses between numbered segments, then match each block.
            return prompt
                .substringAfter("Source segments:\n", prompt)
                .split("\n\n")
                .mapNotNull { block ->
                    regex.find(block.trim())?.groupValues?.getOrNull(2)
                }
        }

        /** Minimal JSON string-array encoder (test-only). */
        fun encodeJsonArray(items: List<String>): String =
            items.joinToString(prefix = "[", postfix = "]", separator = ",") { s ->
                "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"")
                    .replace("\n", "\\n") + "\""
            }
    }
}
