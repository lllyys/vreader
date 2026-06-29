// Purpose: feature #129 WI-1 (#110 Phase 3) — the 5 reader themes for the "Display" settings, iOS
// `ReaderThemeV2` parity. Exact RGB lifted from the committed design bundle
// `dev-docs/designs/vreader-fidelity-v1/project/vreader-themes.jsx` (the SAME identity iOS uses;
// ADR-0001). Pure value type (Compose `Color`, no Android runtime) so it's JVM-unit-testable.
package com.vreader.app.reader.settings

import androidx.compose.ui.graphics.Color

/**
 * A reader theme: the page [background], the primary text [ink], the [accent] (per-theme oxblood/amber),
 * and [isDark] (the color-scheme hint). The 5 themes mirror iOS `ReaderThemeV2` (paper/sepia/dark/oled/
 * photo); colors are the design bundle's exact values.
 */
enum class ReaderTheme(
    val background: Color,
    val ink: Color,
    val accent: Color,
    val isDark: Boolean,
) {
    Paper(background = Color(0xFFF4EEE0), ink = Color(0xFF1D1A14), accent = Color(0xFF8C2F2F), isDark = false),
    Sepia(background = Color(0xFFE6D6B6), ink = Color(0xFF3A2913), accent = Color(0xFF7A3A1F), isDark = false),
    Dark(background = Color(0xFF1A1815), ink = Color(0xFFD8D2C5), accent = Color(0xFFD6885A), isDark = true),
    Oled(background = Color(0xFF000000), ink = Color(0xFFB9B6B0), accent = Color(0xFFD6885A), isDark = true),
    Photo(background = Color(0xFF2A2520), ink = Color(0xFFE8E0D0), accent = Color(0xFFE8B465), isDark = true),
}
