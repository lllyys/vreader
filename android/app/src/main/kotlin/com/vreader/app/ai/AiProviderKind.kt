// Purpose: feature #118 WI-1 (#110 Phase 3) — discriminator for the AI provider wire protocol,
// mirroring iOS `ProviderKind` (raw values match for future config parity):
//   openAiCompatible — POST <baseUrl>/chat/completions, Authorization: Bearer
//   anthropicNative  — POST <baseUrl>/v1/messages, x-api-key + anthropic-version: 2023-06-01
// Each kind carries its default base URL + model so the "Add provider" editor can pre-fill.
package com.vreader.app.ai

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class AiProviderKind {
    // @SerialName matches the iOS `ProviderKind` raw value exactly (`openAICompatible`) so a
    // persisted profile is config-parity-compatible; the Kotlin identifier stays camelCase.
    @SerialName("openAICompatible") openAiCompatible,
    anthropicNative;

    val defaultBaseUrl: String
        get() = when (this) {
            openAiCompatible -> "https://api.openai.com/v1"
            anthropicNative -> "https://api.anthropic.com"
        }

    val defaultModel: String
        get() = when (this) {
            openAiCompatible -> "gpt-4o-mini"
            anthropicNative -> "claude-sonnet-4-6"
        }

    val displayName: String
        get() = when (this) {
            openAiCompatible -> "OpenAI-compatible"
            anthropicNative -> "Anthropic"
        }

    /** The path the client appends to the base URL when calling the model (Bug #185 parity — the
     *  editor shows this so users enter the base URL only, not the full endpoint). */
    val endpointPath: String
        get() = when (this) {
            openAiCompatible -> "/chat/completions"
            anthropicNative -> "/v1/messages"
        }

    val endpointPathHint: String
        get() = "Enter the base URL only — the app appends $endpointPath. Example: $defaultBaseUrl"
}
