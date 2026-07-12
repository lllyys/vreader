// Purpose: feature #131 WI-5 — the immutable UI state for bilingual reading, owned by
// BilingualViewModel and rendered by the setup sheet / interlinear body (WI-7a). The
// config slice (enabled / targetLanguage / granularity / needsSetupSheet / aiConfigured)
// is populated by WI-5's state core; the render slice (translationsByUnit / inFlightUnits
// / unavailableUnits / errorUnit) is DECLARED here but populated by WI-6's prefetch
// trigger — in WI-5 those fields stay empty and are only CLEARED (disable / language
// change). There is NO `style` field (Style descoped, §3). Granularity is `paragraph`
// in v1 (round-4 H3).
//
// @coordinates-with: BilingualViewModel.kt, BilingualLanguages.kt, TranslationUnitId.kt,
//   TranslationGranularity.kt,
//   dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md (WI-5/WI-6)
package com.vreader.app.bilingual

/**
 * The full bilingual UI state.
 *
 * @property enabled whether bilingual mode is on for this book.
 * @property targetLanguage the resolved target language (from the persisted key).
 * @property granularity always [TranslationGranularity.paragraph] in v1.
 * @property needsSetupSheet true when the first-enable setup sheet should be shown.
 * @property aiConfigured whether an AI provider is ready (BilingualAiReadiness gate).
 * @property translationsByUnit per-unit translated segments (WI-6 populates; WI-5 clears).
 * @property inFlightUnits units whose translation is being fetched (WI-6).
 * @property unavailableUnits units that couldn't be translated — source-only fallback (WI-6).
 * @property errorUnit the unit currently surfacing a retryable error, if any (WI-6).
 */
data class BilingualUiState(
    val enabled: Boolean = false,
    val targetLanguage: BilingualLanguage = BilingualLanguages.ALL.first(),
    val granularity: TranslationGranularity = TranslationGranularity.paragraph,
    val needsSetupSheet: Boolean = false,
    val aiConfigured: Boolean = false,
    val translationsByUnit: Map<TranslationUnitId, List<String>> = emptyMap(),
    val inFlightUnits: Set<TranslationUnitId> = emptySet(),
    val unavailableUnits: Set<TranslationUnitId> = emptySet(),
    val errorUnit: TranslationUnitId? = null,
)
