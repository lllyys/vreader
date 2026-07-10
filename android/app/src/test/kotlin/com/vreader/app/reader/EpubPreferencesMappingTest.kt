// Purpose: feature #129 WI-5 (#110 Phase 3) — pins the pure `ReaderSettings → EpubPreferences` mapping
// the EPUB (Readium) reader applies, with EXACT conversions (not just "field populated"). Guards the
// Readium 3.3.0 API assumption (EpubPreferences fontSize/fontFamily/lineHeight/pageMargins/backgroundColor/
// textColor are unitless Double multipliers + Readium Color/FontFamily value types, NOT sp/dp). Pure JVM
// (Readium value classes load without an Android runtime) — the RED test that leads WI-5.
package com.vreader.app.reader

import androidx.compose.ui.graphics.toArgb
import com.vreader.app.reader.settings.ReaderFontFamily
import com.vreader.app.reader.settings.ReaderSettings
import com.vreader.app.reader.settings.ReaderTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.readium.r2.navigator.preferences.Color as ReadiumColor
import org.readium.r2.navigator.preferences.FontFamily as ReadiumFontFamily

class EpubPreferencesMappingTest {

    private val eps = 1e-6

    // ---- fontSize = fontSizeSp / 18.0 (18sp default → 1.0 = 100%) ----

    @Test
    fun defaultFontSize_mapsToOneHundredPercent() {
        val prefs = ReaderSettings(fontSizeSp = 18f).toEpubPreferences()
        assertEquals(1.0, prefs.fontSize!!, eps)
    }

    @Test
    fun minFontSize_mapsTo13Over18() {
        val prefs = ReaderSettings(fontSizeSp = ReaderSettings.MIN_FONT_SIZE).toEpubPreferences()
        assertEquals(13.0 / 18.0, prefs.fontSize!!, eps) // ≈ 0.7222
    }

    @Test
    fun maxFontSize_mapsTo26Over18() {
        val prefs = ReaderSettings(fontSizeSp = ReaderSettings.MAX_FONT_SIZE).toEpubPreferences()
        assertEquals(26.0 / 18.0, prefs.fontSize!!, eps) // ≈ 1.4444
    }

    // ---- lineHeight = lineSpacing (the 1.3–2.0 multiplier, same Double) ----

    @Test
    fun lineSpacing_mapsToLineHeightUnchanged() {
        assertEquals(1.5, ReaderSettings(lineSpacing = 1.5f).toEpubPreferences().lineHeight!!, eps)
        assertEquals(1.3, ReaderSettings(lineSpacing = ReaderSettings.MIN_LINE_SPACING).toEpubPreferences().lineHeight!!, eps)
        assertEquals(2.0, ReaderSettings(lineSpacing = ReaderSettings.MAX_LINE_SPACING).toEpubPreferences().lineHeight!!, eps)
    }

    // ---- pageMargins = marginDp / 20.0 (20dp ≈ current default → 1.0) ----

    @Test
    fun defaultMargin_mapsToOne() {
        assertEquals(1.0, ReaderSettings(marginDp = 20f).toEpubPreferences().pageMargins!!, eps)
    }

    @Test
    fun minAndMaxMargin_scaleAgainst20() {
        assertEquals(16.0 / 20.0, ReaderSettings(marginDp = ReaderSettings.MIN_MARGIN).toEpubPreferences().pageMargins!!, eps) // 0.8
        assertEquals(48.0 / 20.0, ReaderSettings(marginDp = ReaderSettings.MAX_MARGIN).toEpubPreferences().pageMargins!!, eps) // 2.4
    }

    // ---- fontFamily → Readium FontFamily.SERIF / SANS_SERIF ----

    @Test
    fun serif_mapsToReadiumSerif() {
        val prefs = ReaderSettings(fontFamily = ReaderFontFamily.Serif).toEpubPreferences()
        assertEquals(ReadiumFontFamily.SERIF, prefs.fontFamily)
    }

    @Test
    fun sans_mapsToReadiumSansSerif() {
        val prefs = ReaderSettings(fontFamily = ReaderFontFamily.Sans).toEpubPreferences()
        assertEquals(ReadiumFontFamily.SANS_SERIF, prefs.fontFamily)
    }

    // ---- each of the 5 themes → Readium Color(bg/ink) from the theme RGB ----

    @Test
    fun everyTheme_mapsBackgroundAndTextColorFromThemeRgb() {
        for (theme in ReaderTheme.entries) {
            val prefs = ReaderSettings(theme = theme).toEpubPreferences()
            assertEquals(
                "background for $theme",
                ReadiumColor(theme.background.toArgb()),
                prefs.backgroundColor,
            )
            assertEquals(
                "text for $theme",
                ReadiumColor(theme.ink.toArgb()),
                prefs.textColor,
            )
        }
    }

    @Test
    fun paperTheme_hasExpectedArgbColors() {
        // Paper: bg #F4EEE0 / ink #1D1A14 (design bundle) — full-opacity ARGB.
        val prefs = ReaderSettings(theme = ReaderTheme.Paper).toEpubPreferences()
        assertEquals(ReadiumColor(0xFFF4EEE0.toInt()), prefs.backgroundColor)
        assertEquals(ReadiumColor(0xFF1D1A14.toInt()), prefs.textColor)
    }

    @Test
    fun oledTheme_hasBlackBackground() {
        val prefs = ReaderSettings(theme = ReaderTheme.Oled).toEpubPreferences()
        assertEquals(ReadiumColor(0xFF000000.toInt()), prefs.backgroundColor)
    }

    // ---- scroll stays at its current default (layout out of #129 scope) ----

    @Test
    fun scroll_isLeftUnset_soTheReaderKeepsItsDefault() {
        // The mapper must NOT force a layout — WI-5 owns typography/theme only; the reader's
        // scroll default is set once at open (EpubPreferences(scroll = true) in ReaderActivity).
        assertNull(ReaderSettings().toEpubPreferences().scroll)
    }
}
