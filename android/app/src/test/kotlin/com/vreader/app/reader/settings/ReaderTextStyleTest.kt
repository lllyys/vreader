package com.vreader.app.reader.settings

import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.sp
import com.vreader.app.ui.theme.VReaderFonts
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Feature #129 WI-4 — `ReaderSettings.toTxtTextStyle()` maps to the TXT/MD body style: theme ink color,
 * fontSize (sp), lineHeight = fontSize * lineSpacing, and the chosen font family. Pure JVM (Compose
 * text/unit value types).
 */
class ReaderTextStyleTest {
    @Test fun mapsSizeFamilyColorAndLineHeight() {
        val s = ReaderSettings(theme = ReaderTheme.Dark, fontFamily = ReaderFontFamily.Sans, fontSizeSp = 22f, lineSpacing = 1.8f, marginDp = 30f)
        val style = s.toTxtTextStyle()
        assertEquals(ReaderTheme.Dark.ink, style.color)
        assertEquals(22f.sp, style.fontSize)
        assertEquals((22f * 1.8f).sp, style.lineHeight)   // 39.6sp
        assertEquals(FontFamily.SansSerif, style.fontFamily)
    }

    @Test fun defaults_mapToPaperSerif18() {
        val style = ReaderSettings().toTxtTextStyle()
        assertEquals(ReaderTheme.Paper.ink, style.color)
        assertEquals(18f.sp, style.fontSize)
        assertEquals((18f * 1.5f).sp, style.lineHeight)   // 27sp
        assertEquals(FontFamily.Serif, style.fontFamily)
    }

    @Test fun fontFamily_mapsBothChoices() {
        assertEquals(VReaderFonts.Serif, ReaderFontFamily.Serif.toComposeFontFamily())
        assertEquals(VReaderFonts.Sans, ReaderFontFamily.Sans.toComposeFontFamily())
    }
}
