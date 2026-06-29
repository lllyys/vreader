// Purpose: feature #129 WI-4 (#110 Phase 3) — map the reader [ReaderSettings] to the Compose text
// styling the TXT/MD host applies (the iOS TXTViewConfig analog). Pure function so it's JVM-unit-
// testable; the host threads `settings.toTxtTextStyle()` into its `Text` and uses [ReaderSettings.theme]
// for the surface background + [marginDp] for the horizontal padding.
package com.vreader.app.reader.settings

import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.sp
import com.vreader.app.ui.theme.VReaderFonts

/** The Compose [FontFamily] for a reader font choice (Source Serif 4 / Inter → platform serif / sans). */
fun ReaderFontFamily.toComposeFontFamily(): FontFamily = when (this) {
    ReaderFontFamily.Serif -> VReaderFonts.Serif
    ReaderFontFamily.Sans -> VReaderFonts.Sans
}

/**
 * The body `TextStyle` for the TXT/MD reader: the theme ink color, the chosen size (sp), a line height of
 * `fontSize * lineSpacing` (lineSpacing is a 1.3–2.0 multiplier), and the chosen family. The margin +
 * surface background are applied by the host (a TextStyle carries neither).
 */
fun ReaderSettings.toTxtTextStyle(): TextStyle = TextStyle(
    color = theme.ink,
    fontSize = fontSizeSp.sp,
    lineHeight = (fontSizeSp * lineSpacing).sp,
    fontFamily = fontFamily.toComposeFontFamily(),
)
