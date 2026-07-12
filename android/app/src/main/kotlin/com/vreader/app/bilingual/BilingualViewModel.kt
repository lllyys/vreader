// Purpose: feature #131 WI-5 — the bilingual reading ViewModel STATE CORE. Owns a
// StateFlow<BilingualUiState>, hydrates it from the per-book store, and handles the
// enable/disable/language setters, the first-enable setup sheet, and the aiConfigured
// readiness derivation. It holds an injected ChapterTranslationPrefetcher + an injected
// AiProviderSnapshot provider (the Medium-4 seams) so WI-6/WI-4b can wire the real ones;
// WI-5 never invokes the prefetcher. The prefetch trigger, per-unit single-flight, and
// generation-guarded cancellation are WI-6 — onPositionChanged / retryUnit /
// onEpubBlocksEnumerated are declared as STUBS here so the type is stable.
//
// State discipline (rule 50 §12): StateFlow, viewModelScope (no GlobalScope), an injected
// CoroutineDispatcher for store I/O + snapshot reads. Granularity is `paragraph` in v1
// (round-4 H3); there is NO `style` field. A disable or language change CLEARS the shaped
// render state (translationsByUnit / inFlightUnits / unavailableUnits / errorUnit) and
// bumps a `generation` counter so any stale WI-6 prefetch result is discarded.
//
// @coordinates-with: PerBookBilingualStore.kt, BilingualUiState.kt, BilingualAiReadiness.kt,
//   ChapterTranslationPrefetcher.kt, com.vreader.app.ai.AiProviderSnapshot,
//   dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md (WI-5/WI-6)
package com.vreader.app.bilingual

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.vreader.app.ai.AiProviderSnapshot
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * @param bookKey the book's fingerprint key (the per-book store + cache identity).
 * @param store the per-book bilingual config store.
 * @param prefetcher the translation prefetcher — HELD for WI-6, never invoked by WI-5.
 * @param snapshotProvider reads the current AI provider snapshot (injected seam — Medium-4).
 * @param readiness the provider+key readiness gate driving [BilingualUiState.aiConfigured].
 * @param dispatcher the dispatcher for store I/O + snapshot reads (Dispatchers.IO by default).
 */
class BilingualViewModel(
    private val bookKey: String,
    private val store: PerBookBilingualStore,
    @Suppress("unused") private val prefetcher: ChapterTranslationPrefetcher,
    private val snapshotProvider: suspend () -> AiProviderSnapshot,
    private val readiness: BilingualAiReadiness,
    private val dispatcher: CoroutineDispatcher = Dispatchers.IO,
) : ViewModel() {

    private val _state = MutableStateFlow(BilingualUiState())
    val state: StateFlow<BilingualUiState> = _state.asStateFlow()

    // Bumped on disable / language change / (WI-6) unit change so a stale prefetch result
    // that lands after the change is discarded. Readable for tests + WI-6's launch guards.
    @Volatile
    var generation: Int = 0
        private set

    init {
        // Hydrate from the persisted per-book config WITHOUT raising the setup sheet
        // (hydration of an already-enabled book is not a "first enable").
        viewModelScope.launch {
            val cfg = withContext(dispatcher) { store.read(bookKey) }
            _state.update {
                it.copy(
                    enabled = cfg.enabled,
                    targetLanguage = BilingualLanguages.findOrDefault(cfg.targetLanguage),
                    granularity = cfg.granularity,   // paragraph in v1
                )
            }
        }
        refreshAiConfigured()
    }

    /**
     * Turn bilingual [on] for this book. Persists the new state. On the FIRST enable
     * (was-off → on) raises [BilingualUiState.needsSetupSheet]. Disabling clears the
     * shaped render state and bumps [generation] so a stale WI-6 result is discarded.
     */
    fun setEnabled(on: Boolean) {
        val wasEnabled = _state.value.enabled
        _state.update { st ->
            if (on) {
                st.copy(enabled = true, needsSetupSheet = st.needsSetupSheet || !wasEnabled)
            } else {
                generation++
                st.copy(enabled = false).cleared()
            }
        }
        persistCurrent()
    }

    /**
     * Change the target [languageKey]. Persists it, re-resolves the language, and CLEARS
     * the shaped render state + bumps [generation] (a language change invalidates every
     * cached/in-flight translation — they are re-keyed by language).
     */
    fun setTargetLanguage(languageKey: String) {
        generation++
        _state.update { st ->
            st.copy(targetLanguage = BilingualLanguages.findOrDefault(languageKey)).cleared()
        }
        persistCurrent()
    }

    /** Lower the setup-sheet flag (user dismissed or completed the sheet). */
    fun dismissSetupSheet() {
        _state.update { it.copy(needsSetupSheet = false) }
    }

    /** Re-derive [BilingualUiState.aiConfigured] from the current provider snapshot. */
    fun refreshAiConfigured() {
        viewModelScope.launch {
            val configured = withContext(dispatcher) { readiness.resolve(snapshotProvider()) }
            _state.update { it.copy(aiConfigured = configured) }
        }
    }

    // ── WI-6 stubs (declared so the type is stable; the real prefetch is WI-6) ──

    /** WI-6: derive the current unit + prefetch current/next. Stub in WI-5. */
    fun onPositionChanged(@Suppress("unused") charOffsetUtf16: Int) {
        // Implemented in WI-6 (position-driven prefetch + single-flight).
    }

    /** WI-6: re-fetch a unit through the single-flight registry. Stub in WI-5. */
    fun retryUnit(@Suppress("unused") unit: TranslationUnitId) {
        // Implemented in WI-6.
    }

    /** WI-6/WI-7b: the EPUB controller's entry into VM render state. Stub in WI-5. */
    fun onEpubBlocksEnumerated(
        @Suppress("unused") unit: TranslationUnitId,
        @Suppress("unused") blocks: List<String>,
    ) {
        // Implemented in WI-6/WI-7b (the EPUB controller owns the enumerate flow — Medium-1).
    }

    // ── internals ──

    /** Persist the current config slice to the per-book store (granularity pinned paragraph). */
    private fun persistCurrent() {
        val s = _state.value
        viewModelScope.launch {
            withContext(dispatcher) {
                store.write(
                    bookKey,
                    PerBookBilingualConfig(
                        enabled = s.enabled,
                        targetLanguage = s.targetLanguage.key,
                        granularity = TranslationGranularity.paragraph,
                    ),
                )
            }
        }
    }

    /** Reset the shaped render slice (WI-6 fills it; WI-5 only clears it). */
    private fun BilingualUiState.cleared() = copy(
        translationsByUnit = emptyMap(),
        inFlightUnits = emptySet(),
        unavailableUnits = emptySet(),
        errorUnit = null,
    )

    // ── test-only seam (WI-6 populates the shaped state for real) ──

    /** TEST-ONLY: seed the shaped render state so WI-5's clear-on-disable/language tests
     *  can observe it being cleared. WI-6 populates this state through the real prefetch. */
    internal fun debugSeedShapedState() {
        val unit = TranslationUnitId(TranslationUnitId.Kind.txtDocSegmentWindow, "0")
        _state.update {
            it.copy(
                translationsByUnit = mapOf(unit to listOf("译文")),
                inFlightUnits = setOf(unit),
            )
        }
    }
}
