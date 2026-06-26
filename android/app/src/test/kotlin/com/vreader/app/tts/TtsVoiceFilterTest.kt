package com.vreader.app.tts

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Locale

/** Feature #121 WI-2 — TtsVoiceFilter: locale filter + very-low deprioritize that never drops all. */
class TtsVoiceFilterTest {
    private fun c(name: String, lang: String, quality: Int, net: Boolean = false, notInstalled: Boolean = false) =
        TtsVoiceFilter.Candidate(name, Locale.forLanguageTag(lang), quality, net, notInstalled)

    @Test fun filtersToLocaleAndSortsByQuality() {
        val out = TtsVoiceFilter.filter(
            listOf(c("en-low", "en-US", 200), c("fr", "fr-FR", 400), c("en-high", "en-GB", 500)),
            Locale.ENGLISH,
        )
        assertEquals(listOf("en-high", "en-low"), out.map { it.name })  // both English, high first
    }

    @Test fun deprioritizesVeryLowWhenBetterExists() {
        val out = TtsVoiceFilter.filter(
            listOf(c("verylow", "en-US", TtsVoiceFilter.QUALITY_VERY_LOW), c("normal", "en-US", 300)),
            Locale.ENGLISH,
        )
        assertEquals(listOf("normal"), out.map { it.name })  // very-low dropped because a better one exists
    }

    @Test fun keepsVeryLowWhenItsAllThereIs() {
        // the load-bearing fix: a locale whose ONLY voices are very-low must still surface them
        val out = TtsVoiceFilter.filter(
            listOf(c("only", "en-US", TtsVoiceFilter.QUALITY_VERY_LOW)),
            Locale.ENGLISH,
        )
        assertEquals(listOf("only"), out.map { it.name })
    }

    @Test fun emptyWhenLocaleHasNoCandidates() {
        assertTrue(TtsVoiceFilter.filter(listOf(c("fr", "fr-FR", 400)), Locale.GERMAN).isEmpty())
    }

    @Test fun nullLocaleReturnsAll() {
        val out = TtsVoiceFilter.filter(listOf(c("en", "en-US", 300), c("fr", "fr-FR", 400)), null)
        assertEquals(2, out.size)
    }

    @Test fun preservesNetworkAndNotInstalledFlags() {
        val out = TtsVoiceFilter.filter(listOf(c("net", "en-US", 300, net = true, notInstalled = true)), Locale.ENGLISH)
        assertTrue(out.single().networkRequired && out.single().notInstalled)
    }
}
