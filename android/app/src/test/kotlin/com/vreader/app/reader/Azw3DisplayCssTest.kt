// Purpose: feature #129 WI-6 (#110 Phase 3) — pins the DETERMINISTIC theme+typography CSS blob the
// AZW3 (foliate-js) reader injects via `readerAPI.setStyles(css)`, and its JS-escape safety (the
// FoliateJSEscaper analog). Guards two assumptions: (1) the CSS mirrors the iOS
// `ReaderThemeV2+EPUBCSS` / `FoliateStyleMapper.themeCSS` shape (font-size + line-height on html,body;
// descendant cascade-flatten; headings revert; family; theme bg/ink + descendant color reset; margin
// padding); (2) the settings-derived string is safely JSON-encoded into a JS string literal for
// injection (no shell-JS break). Pure JVM (no Android runtime) — the RED test that leads WI-6.
package com.vreader.app.reader

import com.vreader.app.reader.foliate.foliateSetStylesJs
import com.vreader.app.reader.settings.ReaderFontFamily
import com.vreader.app.reader.settings.ReaderSettings
import com.vreader.app.reader.settings.ReaderTheme
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class Azw3DisplayCssTest {

    // ---- font-size: fontSizeSp in px on html,body (Kindle books' rem/em resolve against this) ----

    @Test
    fun defaultFontSize_emitsE18pxOnHtmlBody() {
        val css = ReaderSettings(fontSizeSp = 18f).foliateDisplayCss()
        assertTrue(css.contains("html, body {"))
        assertTrue("expected 18px font-size, got:\n$css", css.contains("font-size: 18px !important"))
    }

    @Test
    fun minFontSize_emits13px() {
        val css = ReaderSettings(fontSizeSp = ReaderSettings.MIN_FONT_SIZE).foliateDisplayCss()
        assertTrue(css.contains("font-size: 13px !important"))
    }

    @Test
    fun maxFontSize_emits26px() {
        val css = ReaderSettings(fontSizeSp = ReaderSettings.MAX_FONT_SIZE).foliateDisplayCss()
        assertTrue(css.contains("font-size: 26px !important"))
    }

    @Test
    fun fractionalFontSize_isRoundedToWholePx() {
        // A slider can land on a non-integer sp; CSS px stays deterministic (rounded, no trailing ".0").
        val css = ReaderSettings(fontSizeSp = 20.6f).foliateDisplayCss()
        assertTrue("expected 21px, got:\n$css", css.contains("font-size: 21px !important"))
        assertFalse(css.contains("20.6"))
    }

    // ---- line-height: the lineSpacing multiplier, one decimal, deterministic ----

    @Test
    fun defaultLineSpacing_emitsOnePointFive() {
        val css = ReaderSettings(lineSpacing = 1.5f).foliateDisplayCss()
        assertTrue("expected line-height 1.5, got:\n$css", css.contains("line-height: 1.5 !important"))
    }

    @Test
    fun minLineSpacing_emitsOnePointThree() {
        val css = ReaderSettings(lineSpacing = ReaderSettings.MIN_LINE_SPACING).foliateDisplayCss()
        assertTrue(css.contains("line-height: 1.3 !important"))
    }

    @Test
    fun maxLineSpacing_emitsTwoPointZero() {
        val css = ReaderSettings(lineSpacing = ReaderSettings.MAX_LINE_SPACING).foliateDisplayCss()
        assertTrue(css.contains("line-height: 2.0 !important"))
    }

    // ---- margin: body padding in px ----

    @Test
    fun defaultMargin_emitsBodyPadding20px() {
        val css = ReaderSettings(marginDp = 20f).foliateDisplayCss()
        assertTrue("expected body padding 20px, got:\n$css", css.contains("padding: 20px !important"))
    }

    @Test
    fun minMargin_emits16px() {
        val css = ReaderSettings(marginDp = ReaderSettings.MIN_MARGIN).foliateDisplayCss()
        assertTrue(css.contains("padding: 16px !important"))
    }

    @Test
    fun maxMargin_emits48px() {
        val css = ReaderSettings(marginDp = ReaderSettings.MAX_MARGIN).foliateDisplayCss()
        assertTrue(css.contains("padding: 48px !important"))
    }

    // ---- font family: serif / sans stack on body (and body * inherit) ----

    @Test
    fun serifFamily_emitsSerifStack() {
        val css = ReaderSettings(fontFamily = ReaderFontFamily.Serif).foliateDisplayCss()
        assertTrue("expected serif stack, got:\n$css", css.contains("serif"))
        assertFalse("serif settings must not emit a sans-serif stack", css.contains("sans-serif !important"))
    }

    @Test
    fun sansFamily_emitsSansSerifStack() {
        val css = ReaderSettings(fontFamily = ReaderFontFamily.Sans).foliateDisplayCss()
        assertTrue("expected sans-serif stack, got:\n$css", css.contains("sans-serif !important"))
    }

    // ---- theme bg/ink for all 5 themes (exact hex, descendant color reset present) ----

    @Test
    fun allThemes_emitExactBackgroundAndInkHex() {
        val expected = mapOf(
            ReaderTheme.Paper to Pair("#f4eee0", "#1d1a14"),
            ReaderTheme.Sepia to Pair("#e6d6b6", "#3a2913"),
            ReaderTheme.Dark to Pair("#1a1815", "#d8d2c5"),
            ReaderTheme.Oled to Pair("#000000", "#b9b6b0"),
            ReaderTheme.Photo to Pair("#2a2520", "#e8e0d0"),
        )
        for ((theme, colors) in expected) {
            val (bg, ink) = colors
            val css = ReaderSettings(theme = theme).foliateDisplayCss()
            assertTrue("theme $theme must emit background $bg, got:\n$css", css.contains("background: $bg !important"))
            assertTrue("theme $theme must emit color $ink, got:\n$css", css.contains("color: $ink !important"))
        }
    }

    @Test
    fun themeColor_hasDescendantColorInheritReset() {
        // Kindle/MOBI books carry per-element ink (<font color>, span style) — a descendant color reset
        // is required so a dark theme actually recolors the text (iOS #93 parity).
        val css = ReaderSettings(theme = ReaderTheme.Dark).foliateDisplayCss()
        assertTrue("expected descendant color: inherit reset, got:\n$css", css.contains("color: inherit !important"))
        assertTrue("descendant reset should include legacy <font>, got:\n$css", css.contains("font { color: inherit !important; }") || css.contains(", font"))
    }

    // ---- determinism: same settings → byte-identical CSS (no set ordering / float jitter) ----

    @Test
    fun sameSettings_produceIdenticalCss() {
        val a = ReaderSettings(theme = ReaderTheme.Sepia, fontFamily = ReaderFontFamily.Sans, fontSizeSp = 19f, lineSpacing = 1.7f, marginDp = 30f).foliateDisplayCss()
        val b = ReaderSettings(theme = ReaderTheme.Sepia, fontFamily = ReaderFontFamily.Sans, fontSizeSp = 19f, lineSpacing = 1.7f, marginDp = 30f).foliateDisplayCss()
        assertEquals(a, b)
    }

    @Test
    fun cssHasNoInjectionBreakers_fromSettingsDerivedValues() {
        // All settings-derived values (hex colors, numeric px) are structurally clean — no stray
        // quotes/backslashes that would need extra CSS escaping. (The JS-literal safety is below.)
        for (theme in ReaderTheme.entries) {
            val css = ReaderSettings(theme = theme).foliateDisplayCss()
            assertFalse("CSS must not contain a raw backslash", css.contains("\\"))
            assertFalse("CSS must not contain a double-quote", css.contains("\""))
        }
    }

    // ---- JS-escape safety: the SHARED production seam (foliateSetStylesJs — the exact function
    // FoliateBridge.setStyles runs through evaluateJavascript) wraps the CSS in a JSON-encoded literal.

    @Test
    fun setStylesJs_wrapsCssInJsonEncodedLiteral() {
        val css = ReaderSettings().foliateDisplayCss()
        val js = foliateSetStylesJs(css)
        assertTrue("must call readerAPI.setStyles, got:\n$js", js.contains("readerAPI.setStyles("))
        // A JSON-encoded string literal is a valid JS string literal: begins+ends with a double quote,
        // and any interior double-quote/backslash is escaped. Decoding the argument round-trips the CSS.
        val start = js.indexOf('"')
        val end = js.lastIndexOf('"')
        assertTrue(start in 0 until end)
        val literal = js.substring(start, end + 1)
        assertEquals(css, Json.decodeFromString(String.serializer(), literal))
    }

    @Test
    fun setStylesJs_isSafeAgainstAdversarialCss() {
        // Even a hypothetical CSS carrying injection breakers (defense-in-depth; the deterministic blob
        // never does) is neutralized by JSON encoding — the result stays a single JS string literal
        // whose decode equals the input, so a `</script>`, quote, backslash, or newline cannot break out.
        val nasty = "body{}\";evil();//\\\n  </script>"
        val js = foliateSetStylesJs(nasty)
        assertFalse("a raw newline must not survive into the JS", js.contains("\n"))
        // The argument is exactly one JSON literal that decodes back to the nasty input.
        val start = js.indexOf('"')
        val end = js.lastIndexOf('"')
        val literal = js.substring(start, end + 1)
        assertEquals(nasty, Json.decodeFromString(String.serializer(), literal))
    }
}
