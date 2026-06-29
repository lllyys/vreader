package com.vreader.app.reader.settings

import androidx.compose.ui.graphics.Color
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Feature #129 WI-1 — the 5 reader themes' colors must match the committed design bundle
 * (vreader-themes.jsx) exactly, and `isDark` must classify them correctly. Pure JVM (Compose `Color`
 * is a value type).
 */
class ReaderThemeTest {
    @Test fun fiveThemes_exist() {
        assertEquals(5, ReaderTheme.entries.size)
    }

    @Test fun themeColors_matchTheDesignBundleRgb() {
        assertEquals(Color(0xFFF4EEE0), ReaderTheme.Paper.background)
        assertEquals(Color(0xFF1D1A14), ReaderTheme.Paper.ink)
        assertEquals(Color(0xFF8C2F2F), ReaderTheme.Paper.accent)

        assertEquals(Color(0xFFE6D6B6), ReaderTheme.Sepia.background)
        assertEquals(Color(0xFF3A2913), ReaderTheme.Sepia.ink)
        assertEquals(Color(0xFF7A3A1F), ReaderTheme.Sepia.accent)

        assertEquals(Color(0xFF1A1815), ReaderTheme.Dark.background)
        assertEquals(Color(0xFFD8D2C5), ReaderTheme.Dark.ink)

        assertEquals(Color(0xFF000000), ReaderTheme.Oled.background)
        assertEquals(Color(0xFFB9B6B0), ReaderTheme.Oled.ink)

        assertEquals(Color(0xFF2A2520), ReaderTheme.Photo.background)
        assertEquals(Color(0xFFE8E0D0), ReaderTheme.Photo.ink)
        assertEquals(Color(0xFFE8B465), ReaderTheme.Photo.accent)
    }

    @Test fun isDark_classifiesLightVsDark() {
        assertFalse(ReaderTheme.Paper.isDark)
        assertFalse(ReaderTheme.Sepia.isDark)
        assertTrue(ReaderTheme.Dark.isDark)
        assertTrue(ReaderTheme.Oled.isDark)
        assertTrue(ReaderTheme.Photo.isDark)
    }
}
