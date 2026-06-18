// Purpose: vreader Android visual identity — the design tokens from the committed
// claude.ai/design bundle `dev-docs/designs/vreader-fidelity-v1` (the SAME identity
// the iOS app implements; ADR-0001 shares the visual identity across the two native
// apps). Colors + type lifted from vreader-library.jsx / vreader-reader.jsx so the
// Compose surfaces match the prototype. Fonts: the bundle uses Source Serif 4
// (titles) + Inter (body); approximated here with the platform serif/sans until the
// exact font assets are bundled (a polish follow-on).
package com.vreader.app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily

/** Palette from the design bundle (light theme — the foundation-bar surface). */
object VReaderColors {
    val Background = Color(0xFFF7F4EE)   // page bg
    val Ink = Color(0xFF1D1A14)          // primary text / active chip
    val InkMuted = Color(0xFF7A6A4A)     // secondary text
    val IconBrown = Color(0xFF3A2913)    // nav icons
    val PillFill = Color(0x0F3C2814)     // rgba(60,40,20,0.06) translucent brown
    val ChipFill = Color(0x0F3C2814)
    val Accent = Color(0xFF8C2F2F)       // "see all" / progress ring (deep red)
    val Finished = Color(0xFF3A6A5A)     // finished check (green)
    val Surface = Color(0xFFFFFFFF)      // list card
    val OnInk = Color(0xFFF7F4EE)        // text on the dark active chip
}

/** Source Serif 4 (titles) / Inter (body) → platform serif / default sans approximations. */
object VReaderFonts {
    val Serif = FontFamily.Serif
    val Sans = FontFamily.SansSerif
}

private val LightColors = lightColorScheme(
    primary = VReaderColors.Ink,
    onPrimary = VReaderColors.OnInk,
    background = VReaderColors.Background,
    onBackground = VReaderColors.Ink,
    surface = VReaderColors.Surface,
    onSurface = VReaderColors.Ink,
    secondary = VReaderColors.InkMuted,
    error = VReaderColors.Accent,
)

@Composable
fun VReaderTheme(content: @Composable () -> Unit) {
    // The foundation-bar design is the light theme; dark is a Phase-3 follow-on.
    @Suppress("UNUSED_VARIABLE") val dark = isSystemInDarkTheme()
    MaterialTheme(colorScheme = LightColors, content = content)
}
