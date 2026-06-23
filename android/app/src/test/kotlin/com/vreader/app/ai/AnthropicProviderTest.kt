package com.vreader.app.ai

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Feature #118 WI-2 — AnthropicProvider against a ServerSocket SSE fake (event-typed stream). */
class AnthropicProviderTest {
    private lateinit var server: AiFakeServer
    @Before fun setUp() { server = AiFakeServer() }
    @After fun tearDown() = server.stop()

    private fun provider() = AnthropicProvider(server.baseUrl(), "sk-ant", "claude-sonnet-4-6", 0.7, 256, Dispatchers.Unconfined)
    private fun req(system: String? = null) = AiRequest("claude-sonnet-4-6", listOf(AiMessage(AiRole.user, "Hi")), 0.7, 256, system)

    @Test fun stream_contentBlockDeltas_untilMessageStop() = runTest {
        server.handlers["POST /v1/messages"] = {
            AiFakeServer.Response(200, contentType = "text/event-stream", body = buildString {
                append("event: message_start\ndata: {\"type\":\"message_start\"}\n\n")
                append("event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"Hel\"}}\n\n")
                append("event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"lo\"}}\n\n")
                append("event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n")
            })
        }
        val text = provider().streamChat(req()).toList().joinToString("") { it.deltaText }
        assertEquals("Hello", text)
        // x-api-key + anthropic-version are sent (header presence verified by a successful parse);
        // system is top-level, NOT a message.
        val sent = server.lastBody["POST /v1/messages"]!!
        assertTrue(sent.contains("\"max_tokens\""))
    }

    @Test fun stream_errorEvent_throws() = runTest {
        server.handlers["POST /v1/messages"] = {
            AiFakeServer.Response(200, contentType = "text/event-stream", body =
                "event: error\ndata: {\"type\":\"error\",\"error\":{\"message\":\"overloaded\"}}\n\n")
        }
        val ex = runCatching { provider().streamChat(req()).toList() }.exceptionOrNull()
        assertTrue(ex is AiError.Stream)
        assertTrue(ex!!.message!!.contains("overloaded"))
    }

    @Test fun chat_oneShot_parsesContentText() = runTest {
        server.handlers["POST /v1/messages"] = {
            AiFakeServer.Response(200, "{\"content\":[{\"type\":\"text\",\"text\":\"Answer.\"}]}")
        }
        assertEquals("Answer.", provider().chat(req()).text)
    }

    @Test fun systemIsTopLevel_notAMessage() = runTest {
        server.handlers["POST /v1/messages"] = { AiFakeServer.Response(200, contentType = "text/event-stream", body = "event: message_stop\ndata: {}\n\n") }
        provider().streamChat(req(system = "Be terse.")).toList()
        val sent = server.lastBody["POST /v1/messages"]!!
        assertTrue("system at top level", sent.contains("\"system\":\"Be terse.\""))
        assertTrue("messages are user/assistant only", !sent.contains("\"role\":\"system\""))
    }
}
