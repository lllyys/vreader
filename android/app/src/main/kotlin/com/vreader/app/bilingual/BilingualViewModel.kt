// Purpose: feature #131 WI-5/WI-6 — the bilingual reading ViewModel. Owns a
// StateFlow<BilingualUiState>, hydrates it from the per-book store, and handles the
// enable/disable/language setters, the first-enable setup sheet, and the aiConfigured
// readiness derivation (WI-5 state core). WI-6 adds the POSITION-DRIVEN PREFETCH:
// onPositionChanged derives the current TXT/MD unit via the injected text provider,
// dedupes (same-unit → no-op), and prefetches current+next through the injected
// BilingualPrefetching seam with per-unit single-flight, a monotonic position-request
// sequence, and a generation guard. retryUnit re-fetches through the same registry.
// onEpubBlocksEnumerated is present-but-inert — EPUB prefetch is owned by the WI-7b
// controller (Medium-1); the position path dispatches TXT/MD units ONLY.
//
// State discipline (rule 50 §12): StateFlow, viewModelScope (no GlobalScope), an injected
// CoroutineDispatcher for store I/O + snapshot reads. Granularity is `paragraph` in v1
// (round-4 H3); there is NO `style` field. A disable or language change CLEARS the shaped
// render state (translationsByUnit / inFlightUnits / unavailableUnits / errorUnit), bumps
// a `generation` counter, and cancels every in-flight prefetch job so any stale result is
// discarded.
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
// Prefetch guards (WI-6, M2 — owned by BilingualPrefetchController): a SUCCESSFUL result is
// committed under the GENERATION guard only (a translation is a durable cache entry, valid to
// commit even for a since-superseded position); the monotonic `positionSeq` gates the FAILURE
// path — a superseded failure is discarded (no errorUnit) UNLESS the unit is still current.
// Cancellation is handled BEFORE the generic error mapping: a native CancellationException (job
// cancelled) is re-thrown to keep the coroutine cancellation-cooperative, and a typed
// ChapterTranslationError.Cancelled is discarded — neither becomes an errorUnit. Per-unit
// single-flight (`prefetchTasks: Map<TranslationUnitId, Job>`) joins a re-triggered unit onto
// its live job so there is no double cache-write. A transient failure clears the current-unit
// anchor so the same position re-dispatches and retryUnit re-fetches.
//
// @coordinates-with: PerBookBilingualStore.kt, BilingualUiState.kt, BilingualAiReadiness.kt,
//   BilingualPrefetching.kt, ChapterTextProvider.kt, com.vreader.app.ai.AiProviderSnapshot,
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
 * @param prefetcher the WI-4a translation prefetcher — the production source of the
 *   [prefetching] seam (adapted by default). Held so the DI graph (WI-4b) stays unchanged.
 * @param snapshotProvider reads the current AI provider snapshot (injected seam — Medium-4).
 * @param readiness the provider+key readiness gate driving [BilingualUiState.aiConfigured].
 * @param dispatcher the dispatcher for store I/O + snapshot reads (Dispatchers.IO by default).
 * @param prefetching the WI-6 prefetch seam driven by the position path; defaults to an
 *   adapter over [prefetcher] (a fake is injected in tests — Medium-4).
 * @param textProvider the unit resolver ([ChapterTextProvider.unitContaining] /
 *   [ChapterTextProvider.unitAfter]) for the position-driven prefetch. Defaults to a no-op
 *   provider so an un-wired VM's position path is inert; the real host provider is wired by
 *   the reader-integration WI (WI-8) alongside the prefetcher.
 */
class BilingualViewModel(
    private val bookKey: String,
    private val store: PerBookBilingualStore,
    prefetcher: ChapterTranslationPrefetcher,
    private val snapshotProvider: suspend () -> AiProviderSnapshot,
    private val readiness: BilingualAiReadiness,
    private val dispatcher: CoroutineDispatcher = Dispatchers.IO,
    private val prefetching: BilingualPrefetching = ChapterTranslationPrefetcherAdapter(prefetcher),
    private val textProvider: ChapterTextProvider = NoTranslationUnitsProvider,
) : ViewModel() {

    private val _state = MutableStateFlow(BilingualUiState())
    val state: StateFlow<BilingualUiState> = _state.asStateFlow()

    // Bumped on disable / language change (NOT on unit change — a unit move only supersedes via
    // positionSeq) so a stale prefetch result that lands after the change is discarded. Mutated
    // ONLY by the single command consumer (serial), read from tests + the prefetch controller's
    // launch guards. @Volatile for cross-thread reads.
    @Volatile
    var generation: Int = 0
        private set

    /** The WI-6 position-driven prefetch controller (dedupe + single-flight + generation
     *  guard + dual-cancellation + failure mapping). Owns the render slice of [_state]. */
    private val prefetchController = BilingualPrefetchController(
        scope = viewModelScope,
        prefetching = prefetching,
        textProvider = textProvider,
        state = _state,
        generationOf = { generation },
    )

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

    // ── WI-6 position-driven prefetch (delegated to [prefetchController]) ──

    /** The reader moved to [charOffsetUtf16]: derive the current TXT/MD unit, dedupe, and
     *  prefetch current+next (EPUB is owned by the WI-7b controller — Medium-1). No-op while
     *  bilingual is disabled. */
    fun onPositionChanged(charOffsetUtf16: Int) = prefetchController.onPositionChanged(charOffsetUtf16)

    /** Re-fetch [unit] after a transient failure surfaced it as [BilingualUiState.errorUnit]. */
    fun retryUnit(unit: TranslationUnitId) = prefetchController.retryUnit(unit)

    /**
     * The EPUB controller's entry into VM render state (WI-7b). Present-but-INERT in WI-6:
     * the EPUB direct-block enumerate → prefetch → guarded-commit sequence is owned by the
     * WI-7b controller (Medium-1); the position path dispatches TXT/MD units only.
     */
    @Suppress("unused")
    fun onEpubBlocksEnumerated(unit: TranslationUnitId, blocks: List<String>) {
        // Inert in WI-6 — the WI-7b controller owns the EPUB enumerate flow (Medium-1).
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
                    invalidatePrefetch()
                    _state.update { st -> st.copy(enabled = false).cleared() }
                }
            }
            is Command.SetLanguage -> {
                invalidatePrefetch()
                _state.update { st -> st.copy(targetLanguage = BilingualLanguages.findOrDefault(cmd.key)).cleared() }
            }
        }
        persistCurrent()
    }

    /** Bump [generation] then invalidate the prefetch controller (cancel in-flight jobs +
     *  drop the anchor) so a disable / language change discards any stale in-flight result and
     *  re-arms a fresh dispatch. The generation guard is the belt (a late result is checked
     *  against it); the controller's cancel is the suspenders (the job never runs its commit). */
    private fun invalidatePrefetch() {
        generation++
        prefetchController.invalidate()
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
