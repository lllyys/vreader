// Purpose: feature #129 WI-5 (#110 Phase 3) — pins the pure `ReaderSettings → EpubPreferences` mapping
// the EPUB (Readium) reader applies, with EXACT conversions (not just "field populated"). Guards the
// Readium 3.3.0 API assumption (EpubPreferences fontSize/fontFamily/lineHeight/pageMargins/backgroundColor/
// textColor are unitless Double multipliers + Readium Color/FontFamily value types, NOT sp/dp). Pure JVM
// (Readium value classes load without an Android runtime) — the RED test that leads WI-5.
//
// feature #156 WI-2 (+ bug #367 / GH #2074) adds the justify pair: `textAlign = JUSTIFY` AND
// `publisherStyles = false`, asserted TOGETHER because either alone is inert (ReadiumCSS gates
// `--USER__textAlign` — and `--USER__lineHeight` — behind `readium-advanced-on`, which only
// `publisherStyles = false` turns on). These are UNIT assertions on the mapper's output and are NOT
// evidence that a glyph moved — that is EpubJustifyConnectedTest's job (computed style in the live DOM).
package com.vreader.app.reader

import androidx.compose.ui.graphics.toArgb
import com.vreader.app.reader.settings.ReaderFontFamily
import com.vreader.app.reader.settings.ReaderLayout
import com.vreader.app.reader.settings.ReaderSettings
import com.vreader.app.reader.settings.ReaderTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.readium.r2.navigator.preferences.Color as ReadiumColor
import org.readium.r2.navigator.preferences.FontFamily as ReadiumFontFamily
import org.readium.r2.navigator.preferences.TextAlign as ReadiumTextAlign

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

    // ---- feature #156 WI-2 / bug #367: the justify pair is INSEPARABLE ----

    /**
     * The plan's T6, and deliberately ONE test asserting BOTH properties: `textAlign = JUSTIFY` with
     * `publisherStyles` unset emits `--USER__textAlign` that no ReadiumCSS rule consumes (measured on
     * device by WI-0's M3), and `publisherStyles = false` alone justifies nothing. Splitting these into
     * two tests would let either drift alone and still show green.
     */
    @Test
    fun justifyAndPublisherStylesFalse_areSetTogether() {
        val prefs = ReaderSettings().toEpubPreferences()
        assertEquals(
            "feature #156: EPUB body text must request justification",
            ReadiumTextAlign.JUSTIFY,
            prefs.textAlign,
        )
        assertEquals(
            "feature #156 / bug #367: publisherStyles=false is what turns ReadiumCSS's " +
                "`readium-advanced-on` gate on — without it BOTH --USER__textAlign and --USER__lineHeight " +
                "are emitted and ignored",
            false,
            prefs.publisherStyles,
        )
    }

    /**
     * Alignment is orthogonal to every other display setting (the plan's T8 edge matrix): no theme, font,
     * size, spacing, margin or layout may switch it off — including the clamp boundaries.
     */
    @Test
    fun justifyPair_isInvariantAcrossEveryOtherSetting() {
        val sizes = listOf(ReaderSettings.MIN_FONT_SIZE, ReaderSettings.DEFAULT_FONT_SIZE, ReaderSettings.MAX_FONT_SIZE)
        val spacings = listOf(ReaderSettings.MIN_LINE_SPACING, ReaderSettings.DEFAULT_LINE_SPACING, ReaderSettings.MAX_LINE_SPACING)
        val margins = listOf(ReaderSettings.MIN_MARGIN, ReaderSettings.DEFAULT_MARGIN, ReaderSettings.MAX_MARGIN)
        var cases = 0
        for (theme in ReaderTheme.entries) {
            for (family in ReaderFontFamily.entries) {
                for (size in sizes) {
                    for (spacing in spacings) {
                        for (margin in margins) {
                            for (layout in ReaderLayout.entries) {
                                val s = ReaderSettings(theme, family, size, spacing, margin, layout)
                                val p = s.toEpubPreferences()
                                assertEquals("textAlign for $s", ReadiumTextAlign.JUSTIFY, p.textAlign)
                                assertEquals("publisherStyles for $s", false, p.publisherStyles)
                                cases++
                            }
                        }
                    }
                }
            }
        }
        assertEquals("the matrix must actually have run", 5 * 2 * 3 * 3 * 3 * 2, cases)
    }

    /** Adding the pair must not have dropped any property #129 already mapped (the #92 analog). */
    @Test
    fun justifyPair_doesNotDropAnyExistingMapping() {
        val s = ReaderSettings(
            theme = ReaderTheme.Sepia,
            fontFamily = ReaderFontFamily.Sans,
            fontSizeSp = 22f,
            lineSpacing = 1.8f,
            marginDp = 32f,
        )
        val p = s.toEpubPreferences()
        assertEquals(22.0 / 18.0, p.fontSize!!, eps)
        assertEquals(1.8, p.lineHeight!!, eps)
        assertEquals(32.0 / 20.0, p.pageMargins!!, eps)
        assertEquals(ReadiumFontFamily.SANS_SERIF, p.fontFamily)
        assertEquals(ReadiumColor(ReaderTheme.Sepia.background.toArgb()), p.backgroundColor)
        assertEquals(ReadiumColor(ReaderTheme.Sepia.ink.toArgb()), p.textColor)
        assertNull("scroll still unset — the host owns layout", p.scroll)
    }

    /**
     * The BOUND on `publisherStyles = false`'s blast radius, expressed as code rather than prose (plan
     * §7.2). Every remaining `readium-advanced-on`-gated ReadiumCSS rule ALSO requires its own `--USER__*`
     * variable to be present; Readium only emits a variable for a preference that is set. So as long as
     * these stay null, those rules cannot fire and the observable effect set stays E1–E5. If a future WI
     * sets one of them, this test fails and forces the effect enumeration to be re-verified.
     */
    @Test
    fun advancedGatedPreferencesWeNeverSet_stayNull_soTheirRulesCannotFire() {
        val p = ReaderSettings().toEpubPreferences()
        assertNull("paraSpacing must stay unset", p.paragraphSpacing)
        assertNull("paraIndent must stay unset", p.paragraphIndent)
        assertNull("wordSpacing must stay unset", p.wordSpacing)
        assertNull("letterSpacing must stay unset", p.letterSpacing)
        assertNull("bodyHyphens must stay unset (ReadiumCSS auto-enables hyphens under justify — E5)", p.hyphens)
        assertNull("typeScale must stay unset (the advanced default 1.2 applies — E3)", p.typeScale)
    }
}
