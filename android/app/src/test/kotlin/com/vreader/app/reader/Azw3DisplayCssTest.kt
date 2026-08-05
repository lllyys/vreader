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

    // ---- feature #156 WI-3: justify-by-default, scoped to guarded paragraphs ----

    @Test
    fun justifiesParagraphs_withTheIntentionalAlignmentGuards() {
        val css = ReaderSettings().foliateDisplayCss()
        assertTrue(
            "expected a guarded p justify rule, got:\n$css",
            css.contains(
                "p:not([style*='text-align' i]):not([align])" +
                    ":not([class*='center' i])" +
                    ":not([class~='right' i]):not([class*='text-right' i])" +
                    ":not([class*='align-right' i]):not([class*='right-align' i])" +
                    ":not([class*='alignright' i]):not([class*='rightalign' i]) " +
                    "{ text-align: justify !important; }",
            ),
        )
    }

    @Test
    fun rightGuard_isTokenMatched_soCopyrightProseStillJustifies() {
        // `copyright` CONTAINS `right`. A substring guard therefore silently skipped justification on
        // every `<p class="copyright">` — ordinary prose in a very common front-matter class. The guard
        // must be a token match plus explicit alignment-shaped patterns, never a bare `[class*=right]`.
        val css = ReaderSettings().foliateDisplayCss()
        val rule = css.lines().single { it.contains("text-align: justify") }
        assertFalse(
            "a bare substring guard on 'right' also matches 'copyright', got: $rule",
            rule.contains("[class*='right'"),
        )
        assertTrue("expected a token match on right, got: $rule", rule.contains("[class~='right' i]"))
        val shapes = listOf(
            "[class*='text-right' i]", "[class*='align-right' i]", "[class*='right-align' i]",
            // No-hyphen variants are what plain HTML/CSS exports emit (`class="alignright"`).
            "[class*='alignright' i]", "[class*='rightalign' i]",
        )
        for (shape in shapes) {
            assertTrue("expected alignment-shaped guard $shape, got: $rule", rule.contains(shape))
        }
    }

    @Test
    fun cssCarriesTheOwnershipSentinel() {
        // The connected control arm reconstructs "production CSS minus one rule" from the blob actually
        // live in the section document, and has to find OURS among the book's own stylesheets.
        val css = ReaderSettings().foliateDisplayCss()
        assertTrue("expected the ownership sentinel, got:\n$css", css.contains(VREADER_CSS_SENTINEL))
        assertEquals("the sentinel must appear exactly once", 1, css.split(VREADER_CSS_SENTINEL).size - 1)
        assertTrue("the sentinel must be a CSS comment so it is inert", VREADER_CSS_SENTINEL.startsWith("/*"))
    }

    @Test
    fun justifyGuards_areCaseInsensitive() {
        // CSS attribute-substring matching is case-sensitive WITHOUT the ` i` flag, so an unflagged
        // guard would force-justify a paragraph the book centred as `style="TEXT-ALIGN:center"` or
        // `class="Center"`. Each guarded attribute must carry the flag.
        val css = ReaderSettings().foliateDisplayCss()
        val rule = css.lines().single { it.contains("text-align: justify") }
        val guards = listOf(
            "[style*='text-align' i]", "[class*='center' i]", "[class~='right' i]",
            "[class*='text-right' i]", "[class*='align-right' i]", "[class*='right-align' i]",
            "[class*='alignright' i]", "[class*='rightalign' i]",
        )
        for (guard in guards) {
            assertTrue("guard $guard must be case-insensitive, got: $rule", rule.contains(guard))
        }
        // `align` is a bare presence check — it has no value to case-fold, so it takes no flag.
        assertTrue("the align attribute guard must remain a presence check, got: $rule", rule.contains(":not([align])"))
    }

    @Test
    fun justifyRule_isScopedToParagraphs_neverHeadingsOrBody() {
        // The rule is `p`-scoped ON PURPOSE. iOS #95 rejected `body { text-align: justify }` as too broad,
        // and WI-2 measured the consequence of the broad shape on EPUB: ReadiumCSS's override targets
        // `:root`, so headings INHERIT justification (effect E1c). Here headings and body must be untouched
        // — which is what makes AC-7's "prose justifies while headings do not" achievable at all.
        val css = ReaderSettings().foliateDisplayCss()
        val justifyLines = css.lines().filter { it.contains("text-align: justify") }
        assertEquals("exactly one justify rule expected, got:\n$css", 1, justifyLines.size)
        val rule = justifyLines.single()
        assertTrue("the justify rule must be p-scoped, got: $rule", rule.trimStart().startsWith("p:not("))
        for (h in listOf("h1", "h2", "h3", "h4", "h5", "h6")) {
            assertFalse("the justify rule must not target $h, got: $rule", rule.contains(h))
        }
        assertFalse("the justify rule must not target body, got: $rule", rule.contains("body"))
        // `text-align-last` is deliberately NOT set: the engine leaves a paragraph's last line
        // start-aligned by default, which is the no-stretched-final-line behaviour the plan relies on.
        assertFalse("text-align-last must not be forced, got:\n$css", css.contains("text-align-last"))
    }

    @Test
    fun justifyRule_isInvariantAcrossEverySetting() {
        // Alignment is orthogonal to theme / family / size / spacing / margin (the T8 edge matrix).
        for (theme in ReaderTheme.entries) {
            for (family in ReaderFontFamily.entries) {
                for (size in listOf(ReaderSettings.MIN_FONT_SIZE, 18f, ReaderSettings.MAX_FONT_SIZE)) {
                    for (spacing in listOf(ReaderSettings.MIN_LINE_SPACING, ReaderSettings.MAX_LINE_SPACING)) {
                        for (margin in listOf(ReaderSettings.MIN_MARGIN, ReaderSettings.MAX_MARGIN)) {
                            val css = ReaderSettings(
                                theme = theme, fontFamily = family, fontSizeSp = size,
                                lineSpacing = spacing, marginDp = margin,
                            ).foliateDisplayCss()
                            assertEquals(
                                "justify must be emitted exactly once for $theme/$family/$size/$spacing/$margin",
                                1, css.lines().count { it.contains("text-align: justify") },
                            )
                        }
                    }
                }
            }
        }
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
