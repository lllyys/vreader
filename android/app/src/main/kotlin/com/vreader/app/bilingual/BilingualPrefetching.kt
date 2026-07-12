// Purpose: feature #131 WI-6 — the prefetch SEAM the BilingualViewModel drives + the
// POSITION-DRIVEN PREFETCH CONTROLLER extracted from the VM (to keep
// BilingualViewModel.kt under the ~300-line bar, rule 50 §9).
//
// [BilingualPrefetching] is the narrow one-suspend-fun seam so the VM/controller can be
// unit-tested against a controllable fake (Medium-4 seam) instead of the whole AI
// transport stack; [ChapterTranslationPrefetcherAdapter] is the production adapter over the
// WI-4a ChapterTranslationPrefetcher (its plain-text `prefetch` path — the direct /
// cache-only-restore paths are the EPUB controller's, WI-7b — so the WI-4a class need NOT
// be modified to implement the interface). [NoTranslationUnitsProvider] is the inert
// default resolver for a pre-WI-8 VM.
//
// [BilingualPrefetchController] owns the WI-6 orchestration: the current-unit anchor +
// dedupe, the monotonic position-request sequence, the per-unit single-flight
// `prefetchTasks: Map<TranslationUnitId, Job>`, the generation guard, dual-cancellation
// handling (native CancellationException AND typed ChapterTranslationError.Cancelled both
// discarded before the generic mapping — a cancelled request is NEVER an errorUnit), and
// the failure mapping (Offline → unavailableUnits; transient → retryable errorUnit + clear
// the anchor so the same position re-dispatches). It mutates the VM's shared StateFlow +
// reads the VM's live `generation` via injected accessors, so the VM keeps single ownership
// of the config-command generation counter.
//
// @coordinates-with: BilingualViewModel.kt, ChapterTranslationPrefetcher.kt,
//   ChapterTextProvider.kt, ChapterTranslationService.kt (ChapterTranslationResult),
//   ChapterTranslationError.kt,
//   dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md (WI-6)
package com.vreader.app.bilingual

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * The prefetch seam the VM's position-driven trigger drives for a single TXT/MD unit.
 * A minimal surface — one `suspend fun` — so the VM can be unit-tested against a fake that
 * records completed writes without standing up the whole AI transport stack.
 */
interface BilingualPrefetching {

    /**
     * Translates [unit]'s source text into [targetLanguage] (cache-first inside the
     * service), returning one translated segment per source segment. Throws a
     * [ChapterTranslationException] on a typed failure (Offline / TimedOut / ProviderFailed
     * / Cancelled) and propagates a coroutine [CancellationException] on cooperative
     * cancellation. [granularity] is paragraph in v1.
     */
    suspend fun prefetch(
        unit: TranslationUnitId,
        targetLanguage: String,
        granularity: TranslationGranularity = TranslationGranularity.paragraph,
    ): ChapterTranslationResult
}

/**
 * The production [BilingualPrefetching] over the WI-4a [ChapterTranslationPrefetcher].
 * Delegates to the prefetcher's plain-text `prefetch` path (segments enumerated from the
 * bound text provider) — the path the VM's position-driven TXT/MD prefetch uses.
 */
class ChapterTranslationPrefetcherAdapter(
    private val prefetcher: ChapterTranslationPrefetcher,
) : BilingualPrefetching {
    override suspend fun prefetch(
        unit: TranslationUnitId,
        targetLanguage: String,
        granularity: TranslationGranularity,
    ): ChapterTranslationResult = prefetcher.prefetch(unit, targetLanguage, granularity)
}

/**
 * The default [ChapterTextProvider] for a VM that has not yet been wired to a host provider
 * (pre-WI-8). It reports NO translatable units, so the position-driven prefetch path is
 * inert until the reader-integration WI injects the real per-host provider.
 */
object NoTranslationUnitsProvider : ChapterTextProvider {
    override fun units(): List<TranslationUnitId> = emptyList()
    override fun sourceSegments(unit: TranslationUnitId): List<String> = emptyList()
    override fun sourceText(unit: TranslationUnitId): String = ""
    override fun unitContaining(charOffsetUtf16: Int): TranslationUnitId? = null
    override fun unitAfter(unit: TranslationUnitId): TranslationUnitId? = null
}

/**
 * Owns the WI-6 position-driven prefetch for a [BilingualViewModel]. All mutable fields are
 * touched only on the VM's single-threaded main dispatcher (via [scope]); the controller
 * mutates the VM's shared [state] and reads the VM's live generation via [generationOf].
 *
 * @param scope the VM's `viewModelScope` (launched jobs are cancelled with the VM).
 * @param prefetching the injectable prefetch seam (a fake in tests — Medium-4).
 * @param textProvider the host unit resolver (`unitContaining` / `unitAfter`).
 * @param state the VM's shared UI state (this controller writes the render slice).
 * @param generationOf reads the VM's live generation counter (the config core owns it).
 */
class BilingualPrefetchController(
    private val scope: CoroutineScope,
    private val prefetching: BilingualPrefetching,
    private val textProvider: ChapterTextProvider,
    private val state: MutableStateFlow<BilingualUiState>,
    private val generationOf: () -> Int,
) {
    /** The current translation-unit anchor. `null` re-arms a fresh dispatch; a transient
     *  failure clears it so the same position re-dispatches (and [retryUnit] re-fetches). */
    private var currentUnit: TranslationUnitId? = null

    /** Monotonic per-trigger position-request sequence. Captured at launch and re-checked
     *  after every suspension so a superseded (older) request discards its late result. */
    private var positionSeq: Long = 0L

    /** Per-unit single-flight: a live prefetch [Job] per unit. A re-triggered unit joins its
     *  existing job (no double dispatch / cache-write); an [invalidate] cancels them all. */
    private val prefetchTasks = mutableMapOf<TranslationUnitId, Job>()

    /**
     * The reader moved to [charOffsetUtf16]. Derives the current TXT/MD unit (EPUB is owned
     * by the WI-7b controller — Medium-1), DEDUPES against the anchor (same unit → no-op),
     * then prefetches current + next. Bumps [positionSeq] so a superseded request does not
     * surface a stale ERROR (a successful translation is always a valid cache entry and is
     * committed under the generation guard). No-op while bilingual is disabled.
     *
     * MAIN-THREAD CONTRACT: called on the reader's Main thread (its position callback); the
     * anchor / sequence / registry fields are Main-confined (Gate-4 Medium — the production
     * caller, WI-8's TxtReaderActivity, is a Main-thread lifecycle callback).
     */
    fun onPositionChanged(charOffsetUtf16: Int) {
        if (!state.value.enabled) return
        val unit = textProvider.unitContaining(charOffsetUtf16)?.takeIf { it.isDispatchable } ?: return
        if (unit == currentUnit) return   // dedupe — same unit, nothing to do
        currentUnit = unit
        val seq = ++positionSeq
        prefetch(unit, seq)
        textProvider.unitAfter(unit)?.takeIf { it.isDispatchable }?.let { prefetch(it, seq) }
    }

    /**
     * Re-fetch [unit] through the single-flight registry (a user "retry" after a transient
     * failure surfaced it as [BilingualUiState.errorUnit]). No position sequence is captured
     * — a retry is superseded only by a generation change, not by position movement. Called
     * on Main (see the [onPositionChanged] main-thread contract).
     */
    fun retryUnit(unit: TranslationUnitId) {
        if (!state.value.enabled || !unit.isDispatchable) return
        prefetch(unit, positionSeqAtLaunch = null)
    }

    /**
     * Cancel every in-flight prefetch job and drop the anchor. Called by the VM AFTER it
     * bumps `generation` on a disable / language change, so a stale in-flight result is
     * discarded (the generation guard is the belt; this cancel is the suspenders). Each
     * cancelled job's `finally` is entry-specific, so a replacement launched immediately
     * after is never clobbered (Gate-4 Medium).
     */
    fun invalidate() {
        prefetchTasks.values.forEach { it.cancel() }
        prefetchTasks.clear()
        currentUnit = null
    }

    /**
     * Launch (or JOIN) a single-flight prefetch for [unit]. If a live job already exists for
     * the unit this is a no-op (→ exactly one dispatch / cache-write). On completion:
     * - a SUCCESS commits the translation under the GENERATION guard only — a translation is a
     *   durable cache entry, valid to commit even for a since-superseded position (fixing the
     *   Gate-4 High where a joined lookahead-turned-current would else discard its own result);
     * - a FAILURE is discarded (no `errorUnit`) when it is stale by generation, OR superseded by
     *   a newer position AND the unit is no longer current; a failure for the STILL-CURRENT unit
     *   always surfaces (Gate-4 r2 High — a joined lookahead-turned-current must not swallow its
     *   own failure into a stuck, un-retryable state);
     * - a native [CancellationException] AND a typed [ChapterTranslationError.Cancelled] are
     *   BOTH handled before the generic mapping so a cancelled request never becomes errorUnit;
     * - any OTHER throwable maps to a transient failure (the taxonomy's `from()` fallback) so an
     *   unexpected error still clears the spinner + surfaces a retryable errorUnit (Gate-4 r2 M).
     * Every terminal path clears [unit] from `inFlightUnits` (no stuck spinner — Gate-4 High)
     * and every registry/in-flight cleanup is entry-specific (Gate-4 Medium). The job is started
     * LAZILY and only after it is registered, so `Dispatchers.Main.immediate` cannot run the
     * body (and reach `self` / the registry) before the assignment (Gate-4 r2 High).
     */
    private fun prefetch(unit: TranslationUnitId, positionSeqAtLaunch: Long?) {
        prefetchTasks[unit]?.let { if (it.isActive) return }   // single-flight: join the live job

        val launchGen = generationOf()
        val launchLang = state.value.targetLanguage.key
        state.update { it.copy(inFlightUnits = it.inFlightUnits + unit, errorUnit = it.errorUnit.takeUnless { e -> e == unit }) }

        lateinit var self: Job
        self = scope.launch(start = CoroutineStart.LAZY) {
            try {
                val result = prefetching.prefetch(unit, launchLang)
                if (generationOf() != launchGen) {
                    clearInFlight(unit, self)   // config changed under us — discard, no leak
                    return@launch
                }
                state.update {
                    it.copy(
                        translationsByUnit = it.translationsByUnit + (unit to result.segments),
                        inFlightUnits = it.inFlightUnits - unit,
                        unavailableUnits = it.unavailableUnits - unit,
                        errorUnit = it.errorUnit.takeUnless { e -> e == unit },
                    )
                }
            } catch (e: CancellationException) {
                clearInFlight(unit, self)   // cooperative cancellation — NEVER an errorUnit
                throw e
            } catch (e: ChapterTranslationException) {
                if (isFailureStale(unit, launchGen, positionSeqAtLaunch)) clearInFlight(unit, self)
                else handleFailure(unit, e.error)
            } catch (e: Throwable) {
                // An unexpected error (e.g. from textProvider/cache) still surfaces as a
                // retryable transient failure — never a silent stuck spinner (Gate-4 r2 Medium).
                if (isFailureStale(unit, launchGen, positionSeqAtLaunch)) clearInFlight(unit, self)
                else handleFailure(unit, ChapterTranslationError.from(e))
            } finally {
                // Entry-specific: only drop the registry slot if it still points at THIS job, so
                // a replacement launched after an invalidate()/cancel is never clobbered.
                if (prefetchTasks[unit] === self) prefetchTasks.remove(unit)
            }
        }
        prefetchTasks[unit] = self
        // start() is false when the scope is already cancelled (e.g. after the VM's onCleared):
        // the lazy body never runs, so its catch/finally never fire — clean up here so the unit
        // is not left leaked in the registry + inFlightUnits (Gate-4 r3 Medium).
        if (!self.start()) {
            if (prefetchTasks[unit] === self) prefetchTasks.remove(unit)
            state.update { it.copy(inFlightUnits = it.inFlightUnits - unit) }
        }
    }

    /** A FAILED request is stale (discard, no errorUnit) when its captured generation changed,
     *  OR a newer position superseded [positionSeqAtLaunch] AND [unit] is no longer the current
     *  unit. A failure for the STILL-CURRENT unit always surfaces (so a joined lookahead that
     *  became current + then failed is retryable, not silently swallowed — Gate-4 r2 High). A
     *  null position sequence (a retry) is superseded only by generation. (Success uses a
     *  generation-only guard — a translation is a durable cache entry, valid regardless of
     *  position movement.) */
    private fun isFailureStale(unit: TranslationUnitId, launchGen: Int, positionSeqAtLaunch: Long?): Boolean {
        if (launchGen != generationOf()) return true
        val superseded = positionSeqAtLaunch != null && positionSeqAtLaunch != positionSeq
        return superseded && unit != currentUnit
    }

    /** Map a typed failure to render state. Offline → source-only [unavailableUnits]; a
     *  transient failure surfaces the retryable [errorUnit] AND clears the anchor so the same
     *  position re-dispatches. Cancelled is handled at the call site (defensive here). */
    private fun handleFailure(unit: TranslationUnitId, error: ChapterTranslationError) {
        when (error) {
            ChapterTranslationError.Cancelled -> state.update { it.copy(inFlightUnits = it.inFlightUnits - unit) }
            ChapterTranslationError.Offline ->
                state.update { it.copy(inFlightUnits = it.inFlightUnits - unit, unavailableUnits = it.unavailableUnits + unit) }
            ChapterTranslationError.TimedOut, is ChapterTranslationError.ProviderFailed -> {
                if (unit == currentUnit) currentUnit = null   // clear the anchor so the same position retries
                state.update { it.copy(inFlightUnits = it.inFlightUnits - unit, errorUnit = unit) }
            }
        }
    }

    /** Drop [unit] from the in-flight set without committing a translation (a discarded /
     *  cancelled result). Entry-specific: leaves a NEWER replacement job's in-flight marker
     *  intact when [completing] is no longer the registered job for the unit (Gate-4 Medium). */
    private fun clearInFlight(unit: TranslationUnitId, completing: Job) {
        if (prefetchTasks[unit] != null && prefetchTasks[unit] !== completing) return
        state.update { it.copy(inFlightUnits = it.inFlightUnits - unit) }
    }

    /** Only TXT/MD document-window units are dispatched by the position path; EPUB (href) +
     *  PDF (page-range) units are owned by their own controllers (Medium-1). */
    private val TranslationUnitId.isDispatchable: Boolean
        get() = kind == TranslationUnitId.Kind.txtDocSegmentWindow ||
            kind == TranslationUnitId.Kind.mdDocSegmentWindow
}
