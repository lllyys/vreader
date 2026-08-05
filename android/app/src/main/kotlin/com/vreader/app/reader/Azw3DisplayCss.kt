// Purpose: feature #129 WI-6 (#110 Phase 3) — the pure `ReaderSettings → foliate CSS blob` the AZW3
// (foliate-js) reader injects via `readerAPI.setStyles(css)`. Mirrors iOS `FoliateStyleMapper.themeCSS`
// + `ReaderThemeV2+EPUBCSS`: font-size (px) + line-height (multiplier) on `html, body` (so Kindle rem/em
// resolve against the calibrated size), a descendant cascade-flatten (Kindle/MOBI carry per-element em
// font-size + <font color> ink that would otherwise compound / survive a body rule), headings revert,
// the serif/sans family stack, the theme's bg/ink hex, a descendant `color: inherit` reset for theme
// parity, the margin as `body { padding }`, and — feature #156 WI-3 — justify-by-default on guarded
// paragraphs (`p` only, never body/headings). Deterministic (byte-identical for equal settings). The
// JS-escape-safe injection wrapper is the SHARED `foliateSetStylesJs` in the foliate package (the same
// seam FoliateBridge.setStyles runs, so the pinned escaping IS the production escaping).
// Pure value types (JVM-unit-testable, Azw3DisplayCssTest) — no Android runtime beyond Compose Color.
//
// @coordinates-with: Azw3ReaderActivity.kt (collects ReaderSettings, injects the CSS through the
//   FoliateBridge setStyles seam on change), FoliateBridge.kt (exposes setStyles), ReaderSettings.kt /
//   ReaderTheme.kt (the value type + theme colors this maps from).
package com.vreader.app.reader

import androidx.compose.ui.graphics.toArgb
import com.vreader.app.reader.settings.ReaderFontFamily
import com.vreader.app.reader.settings.ReaderSettings
import com.vreader.app.reader.settings.ReaderTheme
import kotlin.math.roundToInt

// Font stacks mirror the iOS FoliateStyleMapper serif/sans intent (Source Serif 4 / Inter →
// platform-safe stacks). Deliberately quote-free so the emitted CSS carries no injection breakers.
private const val SERIF_STACK = "Georgia, 'Source Serif 4', 'Songti SC', serif"
private const val SANS_STACK = "'Helvetica Neue', Inter, 'PingFang SC', sans-serif"

/**
 * The deterministic foliate CSS blob for these display [ReaderSettings] — raw CSS (no `<style>` wrapper),
 * as `readerAPI.setStyles(css)` expects. Assumes clamped inputs (the [ReaderSettingsStore] clamps on read
 * AND write); a fractional slider sp is rounded to a whole px so the output stays byte-stable.
 */
fun ReaderSettings.foliateDisplayCss(): String {
    val sizePx = fontSizeSp.roundToInt()
    val lineHeight = formatLineHeight(lineSpacing)
    val marginPx = marginDp.roundToInt()
    val bg = theme.cssHex(theme.background)
    val ink = theme.cssHex(theme.ink)
    val fontStack = when (fontFamily) {
        ReaderFontFamily.Serif -> SERIF_STACK
        ReaderFontFamily.Sans -> SANS_STACK
    }

    // Rule order is fixed → deterministic output. Mirrors iOS FoliateStyleMapper.themeCSS.
    return listOf(
        // Base size + line-height on BOTH html and body so a book's rem/em CSS resolves against the
        // calibrated size, not the 16px UA root default (iOS bug #261 parity).
        "html, body { font-size: ${sizePx}px !important; line-height: $lineHeight !important; }",
        // Cascade-flatten: Kindle/MOBI text containers frequently carry their own em/% font-size which
        // would compound against the body base — force common containers to inherit the flat body px.
        "p, div, span, li, td, th, dd, dt, blockquote, figcaption, " +
            "section, article, aside, main, header, footer, figure { " +
            "font-size: inherit !important; line-height: inherit !important; }",
        // Headings revert to the UA proportional scale (scale WITH body, don't compound off the book base).
        "h1,h2,h3,h4,h5,h6 { font-size: revert !important; }",
        // The chosen family on body + every descendant (Kindle content sets per-element families).
        "body { font-family: $fontStack !important; }",
        "body * { font-family: inherit !important; }",
        // Theme ink on body + a descendant color reset so per-element ink (<font color>, span style,
        // heading colors) yields to the theme on dark themes (iOS #93 parity).
        "body { color: $ink !important; }",
        "h1, h2, h3, h4, h5, h6, p, div, span, li, td, th, dd, dt, " +
            "blockquote, figcaption, section, article, aside, main, " +
            "header, footer, figure, font { color: inherit !important; }",
        // Theme background on body.
        "body { background: $bg !important; }",
        // Horizontal (and matching vertical) reading margin as body padding.
        "body { padding: ${marginPx}px !important; margin: 0 !important; }",
        // feature #156 WI-3 — justify-by-default (the designed body rendering; no control, no new UI).
        // Scoped to `p` ON PURPOSE: `body { text-align: justify }` would be inherited by headings and
        // layout wrappers (iOS #95 rejected it for that reason, and WI-2 MEASURED that outcome on EPUB,
        // where ReadiumCSS's override targets `:root` and headings duly inherit justification). The
        // `:not()` guards skip paragraphs the book aligned on purpose — they are the same heuristics iOS
        // shipped, and they carry iOS's own caveat: verse-as-`<p>`, blockquote inner prose, and
        // faux-headings with an unusual class are NOT covered. A paragraph's last line stays
        // start-aligned by the engine's own `text-align-last: auto` default, so nothing forces a
        // stretched final line.
        "p:not([style*=text-align]):not([align]):not([class*=center]):not([class*=right]) " +
            "{ text-align: justify !important; }",
    ).joinToString("\n")
}

/** Format the line-spacing multiplier to one decimal for stable, deterministic CSS output. */
private fun formatLineHeight(v: Float): String {
    val tenths = (v * 10f).roundToInt()
    return "${tenths / 10}.${tenths % 10}"
}

/** A theme's Compose Color as a lowercase `#rrggbb` CSS hex (opaque; theme colors are all opaque). */
private fun ReaderTheme.cssHex(color: androidx.compose.ui.graphics.Color): String {
    val argb = color.toArgb()
    val r = (argb shr 16) and 0xFF
    val g = (argb shr 8) and 0xFF
    val b = argb and 0xFF
    return "#%02x%02x%02x".format(r, g, b)
}
