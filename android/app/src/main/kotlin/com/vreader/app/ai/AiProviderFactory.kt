// Purpose: feature #118 WI-2 (#110 Phase 3) — builds the right AiClient for a provider profile +
// its decrypted API key. The chat/test request path resolves the active profile from a single
// AiProviderStore.snapshot(), decrypts via apiKey(profile), and calls this — so the client is built
// from one consistent snapshot, never live mid-request reads.
package com.vreader.app.ai

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers

object AiProviderFactory {
    fun create(profile: AiProviderProfile, apiKey: String, dispatcher: CoroutineDispatcher = Dispatchers.IO): AiClient {
        val base = profile.baseUrl.ifBlank { profile.kind.defaultBaseUrl }
        val model = profile.model.ifBlank { profile.kind.defaultModel }
        return when (profile.kind) {
            AiProviderKind.openAiCompatible ->
                OpenAiCompatibleProvider(base, apiKey, model, profile.temperature, profile.maxTokens, dispatcher)
            AiProviderKind.anthropicNative ->
                AnthropicProvider(base, apiKey, model, profile.temperature, profile.maxTokens, dispatcher)
        }
    }
}
