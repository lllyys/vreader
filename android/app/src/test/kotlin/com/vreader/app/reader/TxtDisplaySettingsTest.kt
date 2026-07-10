package com.vreader.app.reader

import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.isUnspecified
import com.vreader.app.reader.settings.ReaderFontFamily
import com.vreader.app.reader.settings.ReaderSettings
import com.vreader.app.reader.settings.ReaderTheme
import com.vreader.app.reader.settings.bodyTextStyle
import com.vreader.app.reader.settings.composeFontFamily
import com.vreader.app.ui.theme.VReaderFonts
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Feature #129 WI-4 — the pure `ReaderSettings → Compose TextStyle` mapping the TXT/MD reader body
 * applies (fontSize sp, lineHeight = fontSize × lineSpacing, theme ink color, serif/sans family),
 * plus the MD heading size-scale contract: `MarkdownRenderer` heading SpanStyles are EM-RELATIVE
 * (not absolute sp) so headings scale with the user's body font-size setting.
 */
class TxtDisplaySettingsTest {

    // --- ReaderSettings → body TextStyle ---

    @Test
    fun defaults_mapToTheDefaultBodyLook() {
        val style = ReaderSettings().bodyTextStyle()
        assertTrue("fontSize is sp", style.fontSize.isSp)
        assertEquals(18f, style.fontSize.value, 1e-4f)
        assertTrue("lineHeight is sp", style.lineHeight.isSp)
        assertEquals(27f, style.lineHeight.value, 1e-4f)             // 18sp × 1.5
        assertEquals(ReaderTheme.Paper.ink, style.color)
        assertEquals(VReaderFonts.Serif, style.fontFamily)
        assertEquals(FontWeight.Normal, style.fontWeight)
    }

    @Test
    fun fontSizeAndLineSpacing_multiplyIntoTheLineHeight() {
        val max = ReaderSettings(fontSizeSp = 26f, lineSpacing = 2.0f).bodyTextStyle()
        assertEquals(26f, max.fontSize.value, 1e-4f)
        assertEquals(52f, max.lineHeight.value, 1e-4f)
        val min = ReaderSettings(fontSizeSp = 13f, lineSpacing = 1.3f).bodyTextStyle()
        assertEquals(13f, min.fontSize.value, 1e-4f)
        assertEquals(13f * 1.3f, min.lineHeight.value, 1e-4f)
    }

    @Test
    fun fontFamilySetting_mapsToTheDesignFamilies() {
        assertEquals(VReaderFonts.Serif, ReaderFontFamily.Serif.composeFontFamily())
        assertEquals(VReaderFonts.Sans, ReaderFontFamily.Sans.composeFontFamily())
        assertEquals(
            VReaderFonts.Sans,
            ReaderSettings(fontFamily = ReaderFontFamily.Sans).bodyTextStyle().fontFamily,
        )
    }

    @Test
    fun everyTheme_itsInkBecomesTheBodyColor() {
        for (theme in ReaderTheme.entries) {
            assertEquals(theme.ink, ReaderSettings(theme = theme).bodyTextStyle().color)
        }
    }

    // --- MD heading SpanStyle size-scale (the body Text's fontSize is the em base) ---

    @Test
    fun mdHeadings_useEmRelativeSizes_soTheyScaleWithTheBodyFontSize() {
        val h1 = MarkdownRenderer.render("# H").spanStyles.single().item.fontSize
        assertTrue("heading size must be em-relative (scales with the setting)", h1.isEm)
        assertEquals(26f / 18f, h1.value, 1e-4f)   // 26sp at the 18sp default base
        val h6 = MarkdownRenderer.render("###### H").spanStyles.single().item.fontSize
        assertTrue(h6.isEm)
        assertEquals(15f / 18f, h6.value, 1e-4f)
    }

    @Test
    fun mdHeadingHierarchy_isPreservedAfterEmScaling() {
        val h1 = MarkdownRenderer.render("# H").spanStyles.single().item.fontSize
        val h2 = MarkdownRenderer.render("## H").spanStyles.single().item.fontSize
        val h3 = MarkdownRenderer.render("### H").spanStyles.single().item.fontSize
        assertTrue("h1 > h2 > h3", h1.value > h2.value && h2.value > h3.value)
    }

    @Test
    fun mdInlineCode_keepsMonospace_withNoAbsoluteSizeOverride() {
        val span = MarkdownRenderer.render("`code`").spanStyles.single().item
        assertEquals(androidx.compose.ui.text.font.FontFamily.Monospace, span.fontFamily)
        assertTrue("code span inherits the body size", span.fontSize.isUnspecified)
    }
}
