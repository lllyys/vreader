// Purpose: feature #118 WI-3 (#110 Phase 3) — drives the AI provider list + editor: observes the
// AiProviderStore for the list, owns the editor form state, runs Test Connection against the LIVE
// form (a transient AiClient built from the form + key, no save first), and saves/deletes. v1 list
// status is ok+model (persisted per-provider test status is a follow-on). The key is never logged.
package com.vreader.app.ai

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.UUID

class AiSettingsViewModel(
    private val store: AiProviderStore,
    private val clientDispatcher: CoroutineDispatcher = Dispatchers.IO,
    private val factory: (AiProviderProfile, String) -> AiClient = { p, key -> AiProviderFactory.create(p, key) },
) : ViewModel() {

    val listState: StateFlow<AiProviderListState> = store.observe()
        .map { snap ->
            AiProviderListState(
                snap.profiles.map { p ->
                    AiProviderRow(p.id, p.name, active = p.id == snap.activeId, statusOk = true, detail = p.model.ifBlank { p.kind.defaultModel })
                }
            )
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), AiProviderListState())

    private val _edit = MutableStateFlow<AiEditState?>(null)
    val editState: StateFlow<AiEditState?> = _edit

    // Bumped whenever the editor opens/closes or a new test starts — an in-flight test result is
    // only applied if its generation still matches, so a stale Ok/Fail can't land on a different
    // form (the user closed it, opened another provider, or re-tested).
    private var testGen = 0

    fun openAdd() { testGen++; _edit.value = AiEditState(editMode = false) }

    fun openEdit(id: String) = viewModelScope.launch {
        val p = store.list().firstOrNull { it.id == id } ?: return@launch
        testGen++
        _edit.value = AiEditState(
            editMode = true, id = p.id, kind = p.kind, name = p.name, baseUrl = p.baseUrl, model = p.model,
            temperature = p.temperature, maxTokens = p.maxTokens, keyAlreadySaved = true,
        )
    }

    fun close() { testGen++; _edit.value = null }

    fun update(transform: (AiEditState) -> AiEditState) { _edit.value = _edit.value?.let(transform) }

    fun test() {
        val s = _edit.value ?: return
        if (!s.canTest) return
        val gen = ++testGen
        update { it.copy(test = AiConnTest.testing, testMessage = "") }
        viewModelScope.launch {
            // Key lookup + client creation + the network call all off the main thread.
            val result = withContext(clientDispatcher) {
                val key = if (s.apiKey.isNotBlank()) s.apiKey else s.id?.let { store.apiKey(it) } ?: ""
                val profile = AiProviderProfile(
                    id = s.id ?: "transient", name = s.name, kind = s.kind, baseUrl = s.effectiveBaseUrl,
                    model = s.effectiveModel, temperature = s.temperature, maxTokens = s.maxTokens, encryptedApiKey = "",
                )
                runCatching { factory(profile, key).testConnection() }
                    .getOrElse { AiTestResult.Fail(AiError.Offline, it.message ?: "failed") }
            }
            if (gen != testGen) return@launch  // superseded by a newer test / form open / close
            update {
                when (result) {
                    is AiTestResult.Ok -> it.copy(test = AiConnTest.ok, testMessage = "Connected — the provider responded successfully.")
                    is AiTestResult.Fail -> it.copy(test = AiConnTest.fail, testMessage = result.message)
                }
            }
        }
    }

    fun save() {
        val s = _edit.value ?: return
        if (!s.canSave) return
        viewModelScope.launch {
            store.upsert(
                id = s.id ?: UUID.randomUUID().toString(),
                name = s.name, kind = s.kind, baseUrl = s.baseUrl, model = s.model,
                temperature = s.temperature, maxTokens = s.maxTokens,
                apiKey = s.apiKey.ifBlank { null },  // blank on edit = keep existing
            )
            _edit.value = null
        }
    }

    fun delete() {
        val id = _edit.value?.id ?: return
        viewModelScope.launch { store.delete(id); _edit.value = null }
    }

    fun setActive(id: String) = viewModelScope.launch { store.setActive(id) }
}
