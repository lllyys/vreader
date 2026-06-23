// Purpose: feature #118 WI-4 (#110 Phase 3) — UI state for the AI chat + summary panel (the
// committed `AiChatPanel`). Spine = the design's states: unconfigured (gate) → idle (suggested
// prompts) → in-flight (typing) → answer (streamed) ; plus the summary mode (cached key-points).
package com.vreader.app.ai

enum class AiChatMode { chat, summary }

data class ChatMessage(val fromUser: Boolean, val text: String)

data class AiChatUiState(
    val mode: AiChatMode = AiChatMode.chat,
    val unconfigured: Boolean = true,
    val providerName: String? = null,
    val messages: List<ChatMessage> = emptyList(),
    val streaming: Boolean = false,
    val streamingText: String = "",   // the assistant answer assembled so far (in-flight)
    val summary: String? = null,
    val summaryCached: Boolean = false,
    val error: String? = null,
) {
    /** Idle = configured, chat mode, nothing sent yet, not streaming → show suggested prompts. */
    val showSuggestions: Boolean
        get() = !unconfigured && mode == AiChatMode.chat && messages.isEmpty() && !streaming

    companion object {
        val SUGGESTED_PROMPTS = listOf(
            "Who is the main character?",
            "Explain this passage",
            "What themes appear in this chapter?",
            "Summarize this chapter",
        )
    }
}
