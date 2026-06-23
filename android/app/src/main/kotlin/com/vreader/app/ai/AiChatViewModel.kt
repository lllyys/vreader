// Purpose: feature #118 WI-4 (#110 Phase 3) — drives the AI chat + summary panel. Resolves the
// ACTIVE provider from one AiProviderStore snapshot, streams a chat answer (accumulating deltas),
// produces a per-chapter summary cached by (book + chapter + source digest + provider + model +
// prompt version) so re-opening is instant + free, and gates every surface when unconfigured. The
// key is never logged.
package com.vreader.app.ai

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.security.MessageDigest

private const val CHAT_SYSTEM = "You are a concise reading assistant helping a reader understand the book they're reading. Answer in clear prose."
private const val SUMMARY_PROMPT_VERSION = "v1"

class AiChatViewModel(
    private val store: AiProviderStore,
    private val clientDispatcher: CoroutineDispatcher = Dispatchers.IO,
    private val factory: (AiProviderProfile, String) -> AiClient = { p, key -> AiProviderFactory.create(p, key) },
) : ViewModel() {

    private val _state = MutableStateFlow(AiChatUiState())
    val state: StateFlow<AiChatUiState> = _state

    private val summaryCache = HashMap<String, String>()
    private var streamJob: Job? = null
    private var activeProviderId: String? = null
    // Bumped on send + on an active-provider change; a chunk/final-append is applied only if its
    // generation still matches, so an in-flight answer from the old provider can't land after a swap.
    private var chatGen = 0

    init { refreshProvider() }

    /** Re-resolve the active provider (call when the panel opens / provider settings change). */
    fun refreshProvider() = viewModelScope.launch {
        val active = withContext(clientDispatcher) { store.activeProfile() }
        if (active?.id != activeProviderId) {
            activeProviderId = active?.id
            chatGen++            // invalidate any in-flight answer started under the previous provider
            streamJob?.cancel()
            _state.update { it.copy(streaming = false, streamingText = "") }
        }
        _state.update { it.copy(unconfigured = active == null, providerName = active?.name) }
    }

    fun send(prompt: String) {
        val s = _state.value
        if (s.unconfigured || prompt.isBlank() || s.streaming) return
        val gen = ++chatGen
        _state.update { it.copy(mode = AiChatMode.chat, messages = it.messages + ChatMessage(true, prompt), streaming = true, streamingText = "", error = null) }
        streamJob = viewModelScope.launch {
            val (profile, key) = activeClient() ?: run { _state.update { it.copy(streaming = false, unconfigured = true) }; return@launch }
            val history = _state.value.messages.map { AiMessage(if (it.fromUser) AiRole.user else AiRole.assistant, it.text) }
            val request = AiRequest(profile.model.ifBlank { profile.kind.defaultModel }, history, profile.temperature, profile.maxTokens, system = CHAT_SYSTEM)
            val sb = StringBuilder()
            try {
                factory(profile, key).streamChat(request).collect { chunk ->
                    if (gen != chatGen) return@collect  // superseded by a provider swap / newer send
                    sb.append(chunk.deltaText)
                    _state.update { it.copy(streamingText = sb.toString()) }
                }
                if (gen == chatGen) _state.update { it.copy(messages = it.messages + ChatMessage(false, sb.toString()), streaming = false, streamingText = "") }
            } catch (e: AiError) {
                if (gen == chatGen) _state.update { it.copy(streaming = false, streamingText = "", error = e.message) }
            }
        }
    }

    /** Stop a streaming answer; keep whatever streamed so far as the assistant message. */
    fun stop() {
        streamJob?.cancel()
        _state.update { st ->
            val partial = st.streamingText
            st.copy(streaming = false, streamingText = "", messages = if (partial.isNotBlank()) st.messages + ChatMessage(false, partial) else st.messages)
        }
    }

    /** Show the chapter summary — cache hit is instant; else a one-shot request, then cached. */
    fun summarize(bookFingerprintKey: String, chapterId: String, chapterText: String, regenerate: Boolean = false) {
        val s = _state.value
        if (s.unconfigured) return
        _state.update { it.copy(mode = AiChatMode.summary, error = null) }
        viewModelScope.launch {
            val (profile, key) = activeClient() ?: run { _state.update { it.copy(unconfigured = true) }; return@launch }
            val effectiveModel = profile.model.ifBlank { profile.kind.defaultModel }
            // SHA-256 over the source text (not the 32-bit String.hashCode, which collides) so two
            // different chapters can't share a cached summary.
            val cacheKey = listOf(bookFingerprintKey, chapterId, sha256(chapterText), profile.id, effectiveModel, SUMMARY_PROMPT_VERSION).joinToString("|")
            if (regenerate) summaryCache.remove(cacheKey)
            summaryCache[cacheKey]?.let { cached ->
                _state.update { it.copy(summary = cached, summaryCached = true, streaming = false) }
                return@launch
            }
            _state.update { it.copy(streaming = true, summary = null) }
            try {
                val req = AiRequest(
                    profile.model.ifBlank { profile.kind.defaultModel },
                    listOf(AiMessage(AiRole.user, "Summarize this chapter in 4 concise key points (markdown bullet list):\n\n$chapterText")),
                    profile.temperature, profile.maxTokens, system = CHAT_SYSTEM,
                )
                val resp = factory(profile, key).chat(req)
                summaryCache[cacheKey] = resp.text
                _state.update { it.copy(summary = resp.text, summaryCached = false, streaming = false) }
            } catch (e: AiError) {
                _state.update { it.copy(streaming = false, error = e.message) }
            }
        }
    }

    fun openChat() { _state.update { it.copy(mode = AiChatMode.chat) } }

    private suspend fun activeClient(): Pair<AiProviderProfile, String>? = withContext(clientDispatcher) {
        val snap = store.snapshot()
        val p = snap.active ?: return@withContext null
        p to store.apiKey(p)  // snapshot-consistent decrypt
    }

    private fun sha256(s: String): String =
        MessageDigest.getInstance("SHA-256").digest(s.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
}
