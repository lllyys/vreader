// Purpose: feature #131 WI-7a — the host-neutral bilingual render-state DTO shared by the
// TXT/MD Compose interlinear body (BilingualInterlinearBody) and — later — the EPUB DOM adapter
// (WI-7b's EpubBilingualJs/Controller). Per plan §211 it carries, per translation unit, the
// translated segments (or null while unresolved) and a `phase` describing what the render surface
// must draw: Loaded (show the translation), Loading(fraction) (in-flight, dim + N%), Error
// (couldn't translate — offer Retry), or SourceOnly (unavailable/offline — silent source-only
// fallback, iOS Decision 2). Compose and EPUB share THIS value type, not the composable body.
//
// The DTO is derived FROM BilingualUiState's shaped render slice (translationsByUnit /
// inFlightUnits / unavailableUnits / errorUnit) by [BilingualRenderState.forUnit] so both render
// surfaces agree on one phase-derivation rule. Pure value type (no Compose, no Android runtime) so
// it stays JVM-unit-testable and reusable by the non-Compose EPUB adapter.
//
// @coordinates-with: BilingualUiState.kt, BilingualInterlinearBody.kt, TranslationUnitId.kt,
//   dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md (WI-7a §211)
package com.vreader.app.bilingual

/**
 * What a translation unit's render slot should draw. Every phase preserves the interlinear
 * "translation slot" rhythm at the render layer (the shell is drawn by the render surface); the
 * phase only says WHAT goes in the slot.
 */
sealed interface BilingualRenderPhase {

    /** Translation is ready — render the [BilingualRenderState.segments] as muted interlinear text. */
    data object Loaded : BilingualRenderPhase

    /**
     * Translation is in flight. [fraction] is 0..1 completion for the "Translating… N%" label +
     * the per-segment dim (design offline-bundle loading state). Values are coerced into 0..1.
     */
    data class Loading(val fraction: Float) : BilingualRenderPhase {
        init {
            require(!fraction.isNaN()) { "loading fraction must not be NaN" }
        }

        /** The coerced 0..1 completion fraction. */
        val clampedFraction: Float get() = fraction.coerceIn(0f, 1f)

        /** The whole-number percent (0..100) for the "N%" label. */
        val percent: Int get() = (clampedFraction * 100f).toInt().coerceIn(0, 100)
    }

    /**
     * Translation failed transiently. The per-slot render surface draws the DEPICTED ghost slot
     * (dim dashed line, no copy — offline bundle `BilingualGhostSlot`); the page-level Retry
     * affordance (`BilingualPageBanner` "back online") is WI-8 chrome, not a per-slot control (rule 51).
     */
    data object Error : BilingualRenderPhase

    /**
     * No translation available (offline / unavailable). The render surface falls back to
     * source-only silently (iOS Decision 2) — it does NOT draw an error.
     */
    data object SourceOnly : BilingualRenderPhase
}

/**
 * The host-neutral render state for ONE translation unit.
 *
 * @property segments the translated segments in source order (null until [phase] is [Loaded];
 *   an empty list under [Loaded] means "translated to nothing" → treated as source-only by the
 *   render surface, never a crash).
 * @property phase what the render surface must draw for this unit.
 */
data class BilingualRenderState(
    val segments: List<String>?,
    val phase: BilingualRenderPhase,
) {
    companion object {

        /** A convenience empty/source-only state (nothing to render). */
        val sourceOnly: BilingualRenderState = BilingualRenderState(segments = null, phase = BilingualRenderPhase.SourceOnly)

        /**
         * Derive the render state for [unit] from the VM's shaped [BilingualUiState] slice. The
         * derivation is a single source of truth shared by both render surfaces (Compose + EPUB):
         *
         * 1. errorUnit == unit                         → [BilingualRenderPhase.Error]
         * 2. unit in inFlightUnits                     → [BilingualRenderPhase.Loading] ([loadingFraction])
         * 3. translationsByUnit[unit] present+nonempty → [BilingualRenderPhase.Loaded] with those segments
         * 4. unit in unavailableUnits (or nothing)     → [BilingualRenderPhase.SourceOnly]
         *
         * Error wins over loading (a surfaced error is the actionable state); loading wins over a
         * stale/absent cache. A present-but-empty translation list is source-only (nothing to draw).
         */
        fun forUnit(
            state: BilingualUiState,
            unit: TranslationUnitId,
            loadingFraction: Float = 0f,
        ): BilingualRenderState {
            val translated = state.translationsByUnit[unit]
            return when {
                state.errorUnit == unit -> BilingualRenderState(segments = translated, phase = BilingualRenderPhase.Error)
                unit in state.inFlightUnits -> BilingualRenderState(
                    segments = translated,
                    phase = BilingualRenderPhase.Loading(loadingFraction),
                )
                !translated.isNullOrEmpty() -> BilingualRenderState(segments = translated, phase = BilingualRenderPhase.Loaded)
                else -> sourceOnly
            }
        }
    }
}
