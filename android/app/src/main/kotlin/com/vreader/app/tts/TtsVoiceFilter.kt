// Purpose: feature #121 WI-2 (#110 Phase 3) — pure voice selection logic, extracted from
// AndroidTtsEngine so it's JVM-unit-testable without the Android Voice type. Filters voices to a
// locale and DEPRIORITIZES (never hard-drops) very-low-quality voices — so a locale whose only voices
// are low-quality / not-yet-installed still surfaces them rather than appearing voice-less.
package com.vreader.app.tts

import java.util.Locale

object TtsVoiceFilter {
    // == android.speech.tts.Voice.QUALITY_VERY_LOW (kept as a literal so this stays Android-free).
    const val QUALITY_VERY_LOW = 100

    /** A platform-free projection of an android.speech.tts.Voice. */
    data class Candidate(
        val name: String,
        val locale: Locale,
        val quality: Int,
        val networkRequired: Boolean,
        val notInstalled: Boolean,
    )

    /**
     * Voices for [locale] (or all if null), best-quality first, never returning empty when the locale
     * HAS candidates: above-very-low voices are preferred, but if a locale only has very-low ones they
     * are still returned (a low-quality voice beats no read-aloud).
     */
    fun filter(candidates: List<Candidate>, locale: Locale?): List<TtsVoiceOption> {
        val byLocale = candidates.filter { locale == null || it.locale.language.equals(locale.language, ignoreCase = true) }
        if (byLocale.isEmpty()) return emptyList()
        val aboveVeryLow = byLocale.filter { it.quality > QUALITY_VERY_LOW }
        val chosen = (if (aboveVeryLow.isNotEmpty()) aboveVeryLow else byLocale).sortedByDescending { it.quality }
        return chosen.map { c ->
            TtsVoiceOption(
                name = c.name, locale = c.locale, label = label(c),
                networkRequired = c.networkRequired, notInstalled = c.notInstalled,
            )
        }
    }

    private fun label(c: Candidate): String {
        val loc = c.locale.getDisplayName(Locale.getDefault()).ifBlank { c.locale.toLanguageTag() }
        val net = if (c.networkRequired) " · network" else ""
        return "$loc$net"
    }
}
