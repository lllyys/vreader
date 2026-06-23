// Purpose: feature #118 WI-3 (#110 Phase 3) — UI state for the AI provider list + editor surfaces
// (the committed `AiProviderList` + the `EditorSheet` contract from vreader-ai-android.jsx /
// vreader-ai-provider-fields.jsx). Stateless composables render a pure function of these.
package com.vreader.app.ai

/** Test-connection state for the editor's Connection section (mirrors the design's test states). */
enum class AiConnTest { idle, testing, ok, fail }

/** One row in the provider list: active radio + name + model (ok) or the rejection reason (fail). */
data class AiProviderRow(
    val id: String,
    val name: String,
    val active: Boolean,
    val statusOk: Boolean,
    val detail: String,  // model when ok, e.g. "401 — key rejected" when fail
)

/** The provider-list screen state. */
data class AiProviderListState(
    val providers: List<AiProviderRow> = emptyList(),
) {
    val unconfigured: Boolean get() = providers.isEmpty()
}

/** The add/edit provider form state (the EditorSheet contract). */
data class AiEditState(
    val editMode: Boolean = false,
    val id: String? = null,
    val kind: AiProviderKind = AiProviderKind.openAiCompatible,
    val name: String = "",
    val baseUrl: String = "",      // blank → kind default
    val model: String = "",        // blank → kind default
    val temperature: Double = 0.7,
    val maxTokens: Int = 2048,
    val apiKey: String = "",       // entered key (blank in edit = keep existing)
    val keyAlreadySaved: Boolean = false,  // edit mode with a stored key
    val test: AiConnTest = AiConnTest.idle,
    val testMessage: String = "",
) {
    /** canSave = name non-empty AND a key is available — entered now, or already saved on edit (a
     *  blank base/model fall back to the kind default = valid; a NEW provider must have a key, since
     *  the store rejects a keyless new profile). */
    val canSave: Boolean get() = name.isNotBlank() && (apiKey.isNotBlank() || (editMode && keyAlreadySaved))
    /** Test is enabled once a key is available (entered now, or already saved in edit mode). */
    val canTest: Boolean get() = apiKey.isNotBlank() || keyAlreadySaved
    val effectiveBaseUrl: String get() = baseUrl.ifBlank { kind.defaultBaseUrl }
    val effectiveModel: String get() = model.ifBlank { kind.defaultModel }
}
