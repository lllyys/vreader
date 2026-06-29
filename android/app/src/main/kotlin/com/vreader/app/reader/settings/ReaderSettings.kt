// Purpose: feature #129 WI-1 (#110 Phase 3) — the reader "Display" settings value type. iOS parity:
// `TypographySettings` + `ReaderThemeV2`. Global (not per-book), device-local (not backed up). The
// layout (scroll/paged) toggle is a tracked follow-up — NOT in #129 (TXT/MD are scroll-only). Ranges
// are the committed design's slider bounds (vreader-panels.jsx ReaderSettingsSheet).
package com.vreader.app.reader.settings

/** The two designed font families (Source Serif 4 / Inter → platform serif / sans). */
enum class ReaderFontFamily { Serif, Sans }

/**
 * The display settings applied across the reflowable readers (EPUB/TXT/MD/AZW3); PDF reads only [theme]
 * (its background). A pure value type — the [ReaderSettingsStore] persists it, the hosts apply it.
 */
data class ReaderSettings(
    val theme: ReaderTheme = ReaderTheme.Paper,
    val fontFamily: ReaderFontFamily = ReaderFontFamily.Serif,
    val fontSizeSp: Float = DEFAULT_FONT_SIZE,
    val lineSpacing: Float = DEFAULT_LINE_SPACING,
    val marginDp: Float = DEFAULT_MARGIN,
) {
    companion object {
        // Defaults = the current hardcoded look (so an install with no stored settings is unchanged).
        const val DEFAULT_FONT_SIZE = 18f
        const val DEFAULT_LINE_SPACING = 1.5f
        const val DEFAULT_MARGIN = 20f

        // Slider bounds from the design (vreader-panels.jsx): font-size 13–26pt, line-spacing 1.3–2.0,
        // margin 16–48px.
        const val MIN_FONT_SIZE = 13f
        const val MAX_FONT_SIZE = 26f
        const val MIN_LINE_SPACING = 1.3f
        const val MAX_LINE_SPACING = 2.0f
        const val MIN_MARGIN = 16f
        const val MAX_MARGIN = 48f

        // Total clamps: a non-finite (NaN/±Inf) input — which `coerceIn` does NOT sanitize and which
        // would fail JSON encoding — falls back to the default before coercing into range.
        fun clampFontSize(v: Float) = (if (v.isFinite()) v else DEFAULT_FONT_SIZE).coerceIn(MIN_FONT_SIZE, MAX_FONT_SIZE)
        fun clampLineSpacing(v: Float) = (if (v.isFinite()) v else DEFAULT_LINE_SPACING).coerceIn(MIN_LINE_SPACING, MAX_LINE_SPACING)
        fun clampMargin(v: Float) = (if (v.isFinite()) v else DEFAULT_MARGIN).coerceIn(MIN_MARGIN, MAX_MARGIN)
    }
}
