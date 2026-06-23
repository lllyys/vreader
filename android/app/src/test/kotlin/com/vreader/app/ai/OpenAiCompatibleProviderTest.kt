package com.vreader.app.ai

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Feature #118 WI-2 — OpenAiCompatibleProvider against a ServerSocket SSE fake. */
class OpenAiCompatibleProviderTest {
    private lateinit var server: AiFakeServer
    @Before fun setUp() { server = AiFakeServer() }
    @After fun tearDown() = server.stop()

    private fun provider() = OpenAiCompatibleProvider(server.baseUrl(), "sk-test", "gpt-4o-mini", 0.7, 256, Dispatchers.Unconfined)
    private fun req(text: String = "Hi", system: String? = null) =
        AiRequest("gpt-4o-mini", listOf(AiMessage(AiRole.user, text)), 0.7, 256, system)

    @Test fun stream_assemblesDeltas_untilDone() = runTest {
        server.handlers["POST /chat/completions"] = {
            AiFakeServer.Response(200, contentType = "text/event-stream", body = buildString {
                append("data: {\"choices\":[{\"delta\":{\"content\":\"Hel\"}}]}\n\n")
                append(": keepalive\n\n")  // comment line — skipped
                append("data: {\"choices\":[{\"delta\":{\"content\":\"lo \"}}]}\n\n")
                append("data: {\"choices\":[{\"delta\":{\"content\":\"世界\"}}]}\n\n")
                append("data: [DONE]\n\n")
            })
        }
        val text = provider().streamChat(req()).toList().joinToString("") { it.deltaText }
        assertEquals("Hello 世界", text)
        // The request carried the system message + stream:true.
        val sent = server.lastBody["POST /chat/completions"]!!
        assertTrue(sent.contains("\"stream\":true"))
    }

    @Test fun stream_includesSystemMessage() = runTest {
        server.handlers["POST /chat/completions"] = { AiFakeServer.Response(200, "data: [DONE]\n\n", "text/event-stream") }
        provider().streamChat(req(system = "You are a tutor.")).toList()
        val sent = server.lastBody["POST /chat/completions"]!!
        assertTrue(sent.contains("\"role\":\"system\""))
        assertTrue(sent.contains("You are a tutor."))
    }

    @Test fun chat_oneShot_parsesMessageContent() = runTest {
        server.handlers["POST /chat/completions"] = {
            AiFakeServer.Response(200, "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"Answer.\"}}]}")
        }
        assertEquals("Answer.", provider().chat(req()).text)
    }

    @Test fun testConnection_okAnd401() = runTest {
        server.handlers["POST /chat/completions"] = { AiFakeServer.Response(200, "{\"choices\":[{\"message\":{\"content\":\"ok\"}}]}") }
        assertTrue(provider().testConnection() is AiTestResult.Ok)
        server.handlers["POST /chat/completions"] = { AiFakeServer.Response(401, "{\"error\":\"bad key\"}") }
        val fail = provider().testConnection()
        assertTrue(fail is AiTestResult.Fail && fail.error is AiError.Auth401)
    }

    @Test fun stream_eofBeforeDone_throwsStream() = runTest {
        // Deltas but NO [DONE] (a dropped/truncated stream) → surfaced, not a silent partial.
        server.handlers["POST /chat/completions"] = {
            AiFakeServer.Response(200, "data: {\"choices\":[{\"delta\":{\"content\":\"par\"}}]}\n\n", "text/event-stream")
        }
        val ex = runCatching { provider().streamChat(req()).toList() }.exceptionOrNull()
        assertTrue(ex is AiError.Stream)
    }

    @Test fun cleartextHttpToRemoteHost_refused() = runTest {
        // http:// to a NON-local host must refuse before sending the key.
        val insecure = OpenAiCompatibleProvider("http://api.example.com/v1", "sk", "m", 0.7, 8, Dispatchers.Unconfined)
        assertTrue((runCatching { insecure.chat(req()) }.exceptionOrNull()) is AiError.InsecureUrl)
    }

    @Test fun maps429AndOffline() = runTest {
        server.handlers["POST /chat/completions"] = { AiFakeServer.Response(429) }
        assertTrue((runCatching { provider().chat(req()) }.exceptionOrNull()) is AiError.RateLimited429)
        val dead = OpenAiCompatibleProvider("http://127.0.0.1:1", "k", "m", 0.7, 8, Dispatchers.Unconfined)
        assertTrue((runCatching { dead.chat(req()) }.exceptionOrNull()) is AiError.Offline)
    }
}
