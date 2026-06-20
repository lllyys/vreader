// Purpose: feature #114 WI-2 (#110 Phase 3) — the backup/restore design tokens, mapped EXACTLY
// from the committed design's UI.light / UI.dark (vreader-ai-provider-fields.jsx, reused by
// vreader-backup-webdav.jsx). A dedicated provider (NOT a mutation of the light-only global
// VReaderColors — Gate-2) exposed via a CompositionLocal chosen on the system dark mode.
package com.vreader.app.backup

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily

/** The backup-surface token set — every value 1:1 with the design's `ui.*`. */
@Immutable
data class BackupTokens(
    val bg: Color,
    val sheetBg: Color,
    val card: Color,
    val ink: Color,
    val sec: Color,
    val ter: Color,
    val sep: Color,
    val tint: Color,
    val placeholder: Color,
    val green: Color,
    val red: Color,
    val chipBg: Color,
    val tagBg: Color,
    val codeBg: Color,
    val isDark: Boolean,
) {
    companion object {
        // UI.light — exact from vreader-ai-provider-fields.jsx.
        val Light = BackupTokens(
            bg = Color(0xFFF4EEE0),
            sheetBg = Color(0xFFFCF8F0),
            card = Color(0xFFFFFFFF),
            ink = Color(0xFF1D1A14),
            sec = Color(0x8C1D1A14),          // rgba(29,26,20,0.55)
            ter = Color(0x571D1A14),          // rgba(29,26,20,0.34)
            sep = Color(0x1F1D1A14),          // rgba(29,26,20,0.12)
            tint = Color(0xFF8C2F2F),
            placeholder = Color(0x571D1A14),  // rgba(29,26,20,0.34)
            green = Color(0xFF3A6A5A),
            red = Color(0xFFA8402F),
            chipBg = Color(0x1A8C2F2F),       // rgba(140,47,47,0.10)
            tagBg = Color(0x1F8C2F2F),        // rgba(140,47,47,0.12)
            codeBg = Color(0x0F1D1A14),       // rgba(29,26,20,0.06)
            isDark = false,
        )

        // UI.dark — exact from vreader-ai-provider-fields.jsx.
        val Dark = BackupTokens(
            bg = Color(0xFF1A1815),
            sheetBg = Color(0xFF222020),
            card = Color(0x0AFFFFFF),         // rgba(255,255,255,0.04)
            ink = Color(0xFFD8D2C5),
            sec = Color(0x80D8D2C5),          // rgba(216,210,197,0.5)
            ter = Color(0x4DD8D2C5),          // rgba(216,210,197,0.3)
            sep = Color(0x1FD8D2C5),          // rgba(216,210,197,0.12)
            tint = Color(0xFFD6885A),
            placeholder = Color(0x52D8D2C5),  // rgba(216,210,197,0.32)
            green = Color(0xFF5A9A7A),
            red = Color(0xFFE0775A),
            chipBg = Color(0x29D6885A),       // rgba(214,136,90,0.16)
            tagBg = Color(0x33D6885A),        // rgba(214,136,90,0.20)
            codeBg = Color(0x1AD8D2C5),       // rgba(216,210,197,0.10)
            isDark = true,
        )
    }
}

/** Source Serif 4 (titles) / Inter (body) / mono — platform approximations (as VReaderFonts). */
object BackupFonts {
    val Serif = FontFamily.Serif
    val Sans = FontFamily.SansSerif
    val Mono = FontFamily.Monospace
}

val LocalBackupTokens = staticCompositionLocalOf { BackupTokens.Light }
