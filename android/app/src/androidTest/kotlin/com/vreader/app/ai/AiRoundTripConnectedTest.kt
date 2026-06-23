package com.vreader.app.ai

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeNotNull
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Feature #118 WI-5 — the LIVE AI acceptance (Gate-5). Drives the REAL OpenAiCompatibleProvider
 * (HttpURLConnection + the bounded SSE framer) against a local OpenAI-compatible SSE stub on the Mac
 * host (reachable from the emulator at 10.0.2.2): test-connection (one-shot) succeeds, and a sent
 * prompt streams an assembled answer over a real socket SSE stream. Skips unless
 * scripts/run-ai-roundtrip.sh passes the `aiBaseUrl` instrumentation arg.
 */
@RunWith(AndroidJUnit4::class)
class AiRoundTripConnectedTest {

    @Test
    fun testConnection_and_streamChat_overLiveSse() = runBlocking {
        val base = InstrumentationRegistry.getArguments().getString("aiBaseUrl")
        assumeNotNull("set -e aiBaseUrl to run (via scripts/run-ai-roundtrip.sh)", base)

        val client = OpenAiCompatibleProvider(base!!, "sk-test", "gpt-4o-mini", 0.7, 64, Dispatchers.IO)

        // Test connection = a one-shot ping; the stub returns choices[0].message.content.
        assertTrue("testConnection ok", client.testConnection() is AiTestResult.Ok)

        // Stream a chat completion; the stub streams 4 deltas then [DONE].
        val answer = client.streamChat(
            AiRequest("gpt-4o-mini", listOf(AiMessage(AiRole.user, "hello")), 0.7, 64)
        ).toList().joinToString("") { it.deltaText }
        assertEquals("Hello from the vreader stub.", answer)
    }
}
