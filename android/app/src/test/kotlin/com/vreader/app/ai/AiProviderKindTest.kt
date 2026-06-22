package com.vreader.app.ai

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Feature #118 WI-1 — AiProviderKind defaults + endpoint paths (iOS ProviderKind parity). */
class AiProviderKindTest {
    @Test fun openAiCompatible_defaults() {
        val k = AiProviderKind.openAiCompatible
        assertEquals("https://api.openai.com/v1", k.defaultBaseUrl)
        assertEquals("gpt-4o-mini", k.defaultModel)
        assertEquals("/chat/completions", k.endpointPath)
        assertEquals("OpenAI-compatible", k.displayName)
        assertTrue(k.endpointPathHint.contains("/chat/completions"))
    }

    @Test fun anthropicNative_defaults() {
        val k = AiProviderKind.anthropicNative
        assertEquals("https://api.anthropic.com", k.defaultBaseUrl)
        assertEquals("claude-sonnet-4-6", k.defaultModel)
        assertEquals("/v1/messages", k.endpointPath)
        assertEquals("Anthropic", k.displayName)
    }

    @Test fun serializedNames_matchIosRawValues() {
        // The PERSISTED form must match iOS `ProviderKind` raw values (openAICompatible /
        // anthropicNative) for config parity — @SerialName drives this, not the Kotlin identifier.
        val json = kotlinx.serialization.json.Json
        assertEquals("\"openAICompatible\"", json.encodeToString(AiProviderKind.serializer(), AiProviderKind.openAiCompatible))
        assertEquals("\"anthropicNative\"", json.encodeToString(AiProviderKind.serializer(), AiProviderKind.anthropicNative))
    }
}
