// Purpose: feature #129 WI-5 (#110 Phase 3) — the pure `ReaderSettings → EpubPreferences` mapping the
// EPUB (Readium) reader applies. Readium's EpubPreferences are unitless Double multipliers + Readium
// Color/FontFamily value types, NOT sp/dp — so this defines the EXACT conversions (pinned by
// EpubPreferencesMappingTest): fontSize = fontSizeSp / 18.0 (18sp default → 1.0 = 100%), lineHeight =
// lineSpacing (already a 1.3–2.0 multiplier), pageMargins = marginDp / 20.0 (20dp ≈ current default),
// backgroundColor/textColor from each theme's ARGB (the 5 themes need explicit colors — Readium's Theme
// enum is only light/sepia/dark), fontFamily → Readium SERIF/SANS_SERIF. `scroll` is left unset so the
// reader keeps the scroll default set once at open (layout is out of #129's scope). Pure value types
// (JVM-unit-testable).
//
// @coordinates-with: ReaderActivity.kt (submits the mapped prefs live via submitPreferences()),
//   ReaderSettings.kt / ReaderTheme.kt (the value type + theme colors this maps from).
package com.vreader.app.reader

import androidx.compose.ui.graphics.toArgb
import com.vreader.app.reader.settings.ReaderFontFamily
import com.vreader.app.reader.settings.ReaderSettings
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.navigator.preferences.Color as ReadiumColor
import org.readium.r2.navigator.preferences.FontFamily as ReadiumFontFamily
import org.readium.r2.shared.ExperimentalReadiumApi

/** The reference font size (sp) that maps to Readium's 100% (`fontSize = 1.0`). Matches the pre-#129
 *  hardcoded body size and [ReaderSettings.DEFAULT_FONT_SIZE]. */
private const val REFERENCE_FONT_SIZE_SP = 18.0

/** The reference horizontal margin (dp) that maps to Readium's `pageMargins = 1.0`. Calibrated so the
 *  default 20dp ≈ the reader's current default margin. */
private const val REFERENCE_MARGIN_DP = 20.0

/**
 * Map these display [ReaderSettings] to a Readium [EpubPreferences] for live submission. Assumes clamped
 * inputs (the [ReaderSettingsStore] clamps on read AND write). Only the typography/theme fields #129 owns
 * are set; `scroll` is deliberately left null so the reader keeps the scroll default configured at open.
 */
@OptIn(ExperimentalReadiumApi::class)
fun ReaderSettings.toEpubPreferences(): EpubPreferences = EpubPreferences(
    fontSize = fontSizeSp / REFERENCE_FONT_SIZE_SP,
    fontFamily = fontFamily.toReadiumFontFamily(),
    lineHeight = lineSpacing.toDouble(),
    pageMargins = marginDp / REFERENCE_MARGIN_DP,
    backgroundColor = ReadiumColor(theme.background.toArgb()),
    textColor = ReadiumColor(theme.ink.toArgb()),
)

@OptIn(ExperimentalReadiumApi::class)
private fun ReaderFontFamily.toReadiumFontFamily(): ReadiumFontFamily = when (this) {
    ReaderFontFamily.Serif -> ReadiumFontFamily.SERIF
    ReaderFontFamily.Sans -> ReadiumFontFamily.SANS_SERIF
}
