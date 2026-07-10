// Purpose: feature #129 WI-4 (#110 Phase 3) — the pure `ReaderSettings → Compose TextStyle` mapping
// the TXT/MD reader body applies: font size in sp, line height = fontSize × lineSpacing (the Display
// sheet's multiplier semantics), the active theme's ink color, and the chosen serif/sans family
// (VReaderFonts design approximations). Pure value types (JVM-unit-testable, TxtDisplaySettingsTest).
// MD headings scale relative to this body size via MarkdownRenderer's em-relative heading SpanStyles.
//
// @coordinates-with: TxtReaderActivity.kt (threads bodyTextStyle into the body Text),
//   MarkdownRenderer.kt (em-relative heading sizes use the body size as their base),
//   ReaderSettings.kt (the value type + clamped ranges this maps from).
package com.vreader.app.reader.settings

import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.vreader.app.ui.theme.VReaderFonts

/** The Compose [FontFamily] for a [ReaderFontFamily] (Source Serif 4 / Inter → platform serif/sans). */
fun ReaderFontFamily.composeFontFamily(): FontFamily = when (this) {
    ReaderFontFamily.Serif -> VReaderFonts.Serif
    ReaderFontFamily.Sans -> VReaderFonts.Sans
}

/**
 * The TXT/MD reader body text style for these settings: `fontSize` in sp, `lineHeight` =
 * fontSize × lineSpacing (18sp × 1.5 = 27sp at the defaults), the theme's ink, the chosen family.
 * Assumes clamped inputs (the [ReaderSettingsStore] clamps on read AND write).
 */
fun ReaderSettings.bodyTextStyle(): TextStyle = TextStyle(
    color = theme.ink,
    fontFamily = fontFamily.composeFontFamily(),
    fontWeight = FontWeight.Normal,
    fontSize = fontSizeSp.sp,
    lineHeight = (fontSizeSp * lineSpacing).sp,
)
