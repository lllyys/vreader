// Purpose: feature #129 WI-7 (#110 Phase 3) — the RED test that leads WI-7. Pins the pure
// `ReaderSettings → PDF viewer backdrop Color` mapping. PDF is rasterized (can't reflow), so it
// inherits ONLY the theme background from the global ReaderSettingsStore — no font/size/spacing, no
// Display sheet / Aa slot (a theme-only reduced sheet would be undesigned — rule 51). Each of the 5
// themes must map its background to the backdrop; the default settings map to Paper. Pure JVM
// (Compose `Color` is a value type — no Android runtime).
package com.vreader.app.reader

import androidx.compose.ui.graphics.Color
import com.vreader.app.reader.settings.ReaderFontFamily
import com.vreader.app.reader.settings.ReaderSettings
import com.vreader.app.reader.settings.ReaderTheme
import org.junit.Assert.assertEquals
import org.junit.Test

class PdfDisplayBackdropTest {

    @Test fun eachTheme_mapsItsBackgroundToTheBackdrop() {
        for (theme in ReaderTheme.entries) {
            assertEquals(
                "PDF backdrop for $theme must be the theme background",
                theme.background,
                ReaderSettings(theme = theme).pdfBackdrop(),
            )
        }
    }

    @Test fun defaultSettings_mapToPaperBackground() {
        assertEquals(ReaderTheme.Paper.background, ReaderSettings().pdfBackdrop())
        assertEquals(Color(0xFFF4EEE0), ReaderSettings().pdfBackdrop())
    }

    @Test fun darkTheme_mapsToDarkBackground() {
        assertEquals(Color(0xFF1A1815), ReaderSettings(theme = ReaderTheme.Dark).pdfBackdrop())
    }

    @Test fun oledTheme_mapsToBlackBackground() {
        assertEquals(Color(0xFF000000), ReaderSettings(theme = ReaderTheme.Oled).pdfBackdrop())
    }

    @Test fun backdrop_ignoresNonThemeTypographyFields() {
        // PDF can't reflow — font family / size / spacing / margin must not affect the backdrop.
        val a = ReaderSettings(theme = ReaderTheme.Sepia, fontFamily = ReaderFontFamily.Sans, fontSizeSp = 26f, lineSpacing = 2.0f, marginDp = 48f)
        val b = ReaderSettings(theme = ReaderTheme.Sepia)
        assertEquals(b.pdfBackdrop(), a.pdfBackdrop())
        assertEquals(ReaderTheme.Sepia.background, a.pdfBackdrop())
    }
}
