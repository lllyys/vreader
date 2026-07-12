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
// Ordering (Gate-4 r1/r2 Mediums): config-mutating setters (setEnabled/setTargetLanguage)
// SYNCHRONOUSLY enqueue a command into an unlimited Channel at the call site — so the
// enqueue order == the API-call order (unlike `viewModelScope.launch`, whose start order is
// not contractual on a multi-worker dispatcher, and unlike a Mutex, whose FIFO only orders
// contenders that have already reached the lock). A SINGLE consumer coroutine drains the
// channel serially (serial by construction — one consumer), after `hydration.join()`, so
// the mutation + its persist land in call order and hydration can never clobber a racing
// setter. The `generation` bump happens once per drained command. (The transient,
// non-persisted setters dismissSetupSheet/refreshAiConfigured use atomic StateFlow.update
// and do NOT participate in the ordered config-write channel.)
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
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.consumeAsFlow
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
    // that lands after the change is discarded. Mutated ONLY by the single command consumer
    // (serial), read from tests + WI-6's launch guards. @Volatile for cross-thread reads.
    @Volatile
    var generation: Int = 0
        private set

    /** An ordered config-mutating command. Enqueued synchronously at the setter call site
     *  (preserving API-call order) and drained serially by the single consumer. */
    private sealed interface Command {
        data class Enable(val on: Boolean) : Command
        data class SetLanguage(val key: String) : Command
    }

    // Unlimited so a synchronous trySend at the call site never suspends or drops — the
    // enqueue order IS the API-call order. A single consumer drains it in FIFO order.
    private val commands = Channel<Command>(Channel.UNLIMITED)

    init {
        // The single serial consumer: hydrate FIRST, then drain commands in enqueue (call)
        // order. One consumer ⇒ each command's state-update + persist completes before the
        // next begins ⇒ setter-call order == state order == store-write order. Hydration
        // running first means a command that raced the initial read still sees hydrated state.
        viewModelScope.launch {
            val cfg = withContext(dispatcher) { store.read(bookKey) }
            _state.update {
                it.copy(
                    enabled = cfg.enabled,
                    targetLanguage = BilingualLanguages.findOrDefault(cfg.targetLanguage),
                    granularity = cfg.granularity,   // paragraph in v1
                )
            }
            commands.consumeAsFlow().collect { apply(it) }
        }
        refreshAiConfigured()
    }

    /**
     * Turn bilingual [on] for this book. Persists the new state. On the FIRST enable
     * (was-off → on) raises [BilingualUiState.needsSetupSheet]. Disabling clears the
     * shaped render state and bumps [generation] so a stale WI-6 result is discarded.
     */
    fun setEnabled(on: Boolean) {
        commands.trySend(Command.Enable(on))
    }

    /**
     * Change the target [languageKey]. Persists it, re-resolves the language, and CLEARS
     * the shaped render state + bumps [generation] (a language change invalidates every
     * cached/in-flight translation — they are re-keyed by language).
     */
    fun setTargetLanguage(languageKey: String) {
        commands.trySend(Command.SetLanguage(languageKey))
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

    override fun onCleared() {
        // Stop accepting commands once the ViewModel is gone so a post-clear setter can't
        // buffer a command that will never be consumed (Gate-4 r3 Low — lifecycle hardening).
        // The consumer's collect is already cancelled with viewModelScope; closing the channel
        // makes a stray post-clear trySend fail-fast instead of silently accumulating.
        commands.close()
        super.onCleared()
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

    /** Apply one command: update state + bump generation, then persist — in the consumer,
     *  so exactly once and in call order. Runs serially (one consumer). */
    private suspend fun apply(cmd: Command) {
        when (cmd) {
            is Command.Enable -> {
                val wasEnabled = _state.value.enabled
                if (cmd.on) {
                    _state.update { st -> st.copy(enabled = true, needsSetupSheet = st.needsSetupSheet || !wasEnabled) }
                } else {
                    generation++
                    _state.update { st -> st.copy(enabled = false).cleared() }
                }
            }
            is Command.SetLanguage -> {
                generation++
                _state.update { st -> st.copy(targetLanguage = BilingualLanguages.findOrDefault(cmd.key)).cleared() }
            }
        }
        persistCurrent()
    }

    /** Persist the current config slice to the per-book store (granularity pinned paragraph). */
    private suspend fun persistCurrent() {
        val s = _state.value
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
