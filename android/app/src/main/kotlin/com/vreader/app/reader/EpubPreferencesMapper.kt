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
// feature #156 WI-2 adds justify-by-default (`textAlign = JUSTIFY`) together with `publisherStyles =
// false`, and that pairing is the whole point: ReadiumCSS applies `--USER__textAlign` ONLY under
// `:root[style*=readium-advanced-on]`, and `publisherStyles = false` is the only thing that sets that
// flag — so `textAlign` alone emits a variable no rule reads (measured on device by WI-0's M3). The same
// gate covers `--USER__lineHeight`, which is why #129's line-spacing slider was inert on EPUB
// (**bug #367 / GH #2074**) and why this change fixes it. The flag's full observable effect set is
// bounded to five items (plan §7.2 E1–E5), because every other advanced-gated rule additionally needs a
// `--USER__*` variable this mapper never emits — pinned by
// `EpubPreferencesMappingTest.advancedGatedPreferencesWeNeverSet_stayNull_soTheirRulesCannotFire` and
// verified in the live DOM by `EpubJustifyConnectedTest`.
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
import org.readium.r2.navigator.preferences.TextAlign as ReadiumTextAlign
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
 *
 * [textAlign] and [publisherStyles] are one indivisible unit (feature #156 / bug #367): the first is inert
 * without the second, and the second is what makes the line-height mapping above take effect at all.
 */
@OptIn(ExperimentalReadiumApi::class)
fun ReaderSettings.toEpubPreferences(): EpubPreferences = EpubPreferences(
    fontSize = fontSizeSp / REFERENCE_FONT_SIZE_SP,
    fontFamily = fontFamily.toReadiumFontFamily(),
    lineHeight = lineSpacing.toDouble(),
    pageMargins = marginDp / REFERENCE_MARGIN_DP,
    backgroundColor = ReadiumColor(theme.background.toArgb()),
    textColor = ReadiumColor(theme.ink.toArgb()),
    // feature #156 — the designed body alignment (vreader-reader.jsx: `textAlign: 'justify'`).
    textAlign = ReadiumTextAlign.JUSTIFY,
    publisherStyles = false,
)

@OptIn(ExperimentalReadiumApi::class)
private fun ReaderFontFamily.toReadiumFontFamily(): ReadiumFontFamily = when (this) {
    ReaderFontFamily.Serif -> ReadiumFontFamily.SERIF
    ReaderFontFamily.Sans -> ReadiumFontFamily.SANS_SERIF
}
