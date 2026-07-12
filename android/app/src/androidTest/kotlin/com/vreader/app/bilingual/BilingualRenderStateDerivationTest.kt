package com.vreader.app.bilingual

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Feature #131 WI-7a — the pure phase-derivation ([BilingualRenderState.forUnit]) that the Compose
 * body + the (WI-7b) EPUB adapter share. A pure value function; exercised here in the androidTest
 * source set (the WI-7a write-set) to keep it under the same PR without adding a JVM-test file
 * outside scope. Covers the priority ladder (error > loading > loaded > source-only) + the empty /
 * out-of-map fallbacks + the loading-fraction clamp.
 */
@RunWith(AndroidJUnit4::class)
class BilingualRenderStateDerivationTest {

    private val unit = TranslationUnitId(TranslationUnitId.Kind.txtDocSegmentWindow, "0")
    private val other = TranslationUnitId(TranslationUnitId.Kind.txtDocSegmentWindow, "1")

    @Test fun error_winsOverEverything() {
        val state = BilingualUiState(
            translationsByUnit = mapOf(unit to listOf("译文")),
            inFlightUnits = setOf(unit),
            errorUnit = unit,
        )
        assertEquals(BilingualRenderPhase.Error, BilingualRenderState.forUnit(state, unit).phase)
    }

    @Test fun loading_winsOverStaleCache() {
        val state = BilingualUiState(
            translationsByUnit = mapOf(unit to listOf("译文")),
            inFlightUnits = setOf(unit),
        )
        val derived = BilingualRenderState.forUnit(state, unit, loadingFraction = 0.5f)
        assertTrue(derived.phase is BilingualRenderPhase.Loading)
        assertEquals(50, (derived.phase as BilingualRenderPhase.Loading).percent)
    }

    @Test fun loaded_whenTranslationPresent() {
        val state = BilingualUiState(translationsByUnit = mapOf(unit to listOf("译文A", "译文B")))
        val derived = BilingualRenderState.forUnit(state, unit)
        assertEquals(BilingualRenderPhase.Loaded, derived.phase)
        assertEquals(listOf("译文A", "译文B"), derived.segments)
    }

    @Test fun sourceOnly_whenUnavailable() {
        val state = BilingualUiState(unavailableUnits = setOf(unit))
        assertEquals(BilingualRenderPhase.SourceOnly, BilingualRenderState.forUnit(state, unit).phase)
    }

    @Test fun sourceOnly_whenUnknownUnit() {
        val state = BilingualUiState(translationsByUnit = mapOf(other to listOf("译文")))
        val derived = BilingualRenderState.forUnit(state, unit)
        assertEquals(BilingualRenderPhase.SourceOnly, derived.phase)
        assertNull(derived.segments)
    }

    @Test fun emptyTranslationList_isSourceOnly() {
        val state = BilingualUiState(translationsByUnit = mapOf(unit to emptyList()))
        assertEquals(BilingualRenderPhase.SourceOnly, BilingualRenderState.forUnit(state, unit).phase)
    }

    @Test fun loadingFraction_clampsAndPercentBounds() {
        assertEquals(0, BilingualRenderPhase.Loading(-3f).percent)
        assertEquals(100, BilingualRenderPhase.Loading(9f).percent)
        assertEquals(0f, BilingualRenderPhase.Loading(-3f).clampedFraction)
        assertEquals(1f, BilingualRenderPhase.Loading(9f).clampedFraction)
    }
}
