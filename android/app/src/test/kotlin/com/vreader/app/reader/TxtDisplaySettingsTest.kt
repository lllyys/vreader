package com.vreader.app.reader

import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.isUnspecified
import com.vreader.app.reader.settings.ReaderFontFamily
import com.vreader.app.reader.settings.ReaderSettings
import com.vreader.app.reader.settings.ReaderTheme
import com.vreader.app.reader.settings.bodyTextStyle
import com.vreader.app.reader.settings.chunkTextAlign
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

    // --- feature #156 WI-1: justify-by-default at the bodyTextStyle() seam ---
    //
    // These pin the REQUEST only. They are NOT evidence that a glyph moved — WI-0 measured
    // `TextAlign.Justify` as a total no-op on space-free CJK (0 of 19 non-final lines, 0 pixels) while
    // the Latin control on the identical path moved 14 of 14 lines / 191 965 pixels. The discriminating
    // post-layout assertions live in the connected `TxtJustificationConnectedTest` (getLineRight).

    @Test
    fun bodyTextStyle_isJustified_theDesignedBodyAlignment() {
        // vreader-reader.jsx:380 renders the reader body `<p>` with `textAlign: 'justify'`.
        assertEquals(TextAlign.Justify, ReaderSettings().bodyTextStyle().textAlign)
    }

    @Test
    fun bodyTextStyle_keepsSizeFamilyLineHeightWithJustify() {
        // Adding alignment must not drop an existing mapped property (the #92 analog).
        val style = ReaderSettings(
            theme = ReaderTheme.Dark,
            fontFamily = ReaderFontFamily.Sans,
            fontSizeSp = 22f,
            lineSpacing = 1.8f,
        ).bodyTextStyle()
        assertEquals(TextAlign.Justify, style.textAlign)
        assertEquals(22f, style.fontSize.value, 1e-4f)
        assertEquals(22f * 1.8f, style.lineHeight.value, 1e-4f)
        assertEquals(ReaderTheme.Dark.ink, style.color)
        assertEquals(VReaderFonts.Sans, style.fontFamily)
        assertEquals(FontWeight.Normal, style.fontWeight)
    }

    @Test
    fun bodyTextStyle_alignmentIsInvariantAcrossEverySettingCombination() {
        // Justification is orthogonal to every other Display setting — no combination turns it off
        // (and none of them is allowed to become an implicit alignment switch).
        for (theme in ReaderTheme.entries) {
            for (family in ReaderFontFamily.entries) {
                for (size in listOf(ReaderSettings.MIN_FONT_SIZE, 18f, ReaderSettings.MAX_FONT_SIZE)) {
                    for (spacing in listOf(ReaderSettings.MIN_LINE_SPACING, 1.5f, ReaderSettings.MAX_LINE_SPACING)) {
                        for (margin in listOf(ReaderSettings.MIN_MARGIN, ReaderSettings.MAX_MARGIN)) {
                            val s = ReaderSettings(theme, family, size, spacing, margin).bodyTextStyle()
                            assertEquals(
                                "theme=$theme family=$family size=$size spacing=$spacing margin=$margin",
                                TextAlign.Justify, s.textAlign,
                            )
                        }
                    }
                }
            }
        }
    }

    @Test
    fun chunkTextAlign_headingChunkIsNotJustified_proseIs() {
        // The SCROLL-mode Markdown heading exclusion (plan §5.2). A wrapping heading rendered flush on
        // both edges reads as body prose; iOS guarded the same class in #92.
        assertEquals(TextAlign.Start, chunkTextAlign(isHeadingChunk = true))
        assertEquals(TextAlign.Justify, chunkTextAlign(isHeadingChunk = false))
        // The heading alignment must match what the body actually applies for a non-heading chunk, i.e.
        // the seam's own default — so the two cannot drift apart.
        assertEquals(ReaderSettings().bodyTextStyle().textAlign, chunkTextAlign(isHeadingChunk = false))
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
