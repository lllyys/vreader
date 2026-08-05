package com.vreader.app.diagnostics.ui

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.SemanticsPropertyKey
import androidx.compose.ui.semantics.SemanticsPropertyReceiver
import androidx.compose.ui.text.font.FontFamily
import com.vreader.app.diagnostics.DiagnosticsLevel

/**
 * Purpose: Feature #164 WI-6a — the diagnostics viewer's design tokens and the FUNCTIONAL level
 * palette (`diagLevelColor`, `vreader-diagnostics.jsx:22-26`), plus the semantics seam that makes a
 * rendered color assertable without pixel capture.
 *
 * Key decisions:
 * - **A dedicated token set, mapped 1:1 from the design's `THEMES.paper` / `THEMES.dark`** (the two
 *   themes every diagnostics artboard is drawn in). The app's global `VReaderColors` is light-only,
 *   so a diagnostics surface that read from it could not render the dark artboards at all; the
 *   `BackupTokens` precedent (feature #114) is the house shape for this.
 * - **Level color is FUNCTIONAL, not decorative** — error = warm red, info = cool blue, debug = the
 *   theme's `sub`. The exact RGB is the design's, per theme, and is asserted in the connected tests.
 * - **Six Android priorities map onto the design's THREE row treatments, inventing no token.**
 *   `WARN` renders with the DEBUG treatment (plan section 6.3's interim, pending the designed Warn
 *   treatment filed as GH #2021 — option (i): under-state severity rather than paint every one of
 *   this app's `Log.w` breadcrumbs red or invent a fourth token). `VERBOSE` folds into `DEBUG` and
 *   `ASSERT` rides with `ERROR` for the same reason, matching the level SETS the filter chips use.
 *   The TRUE level is never lost — the export payload carries `[WARN]` / `[ASSERT]` verbatim.
 * - **[DiagnosticsColorKey] is a test-observability seam, exactly like a `testTag`.** A color is
 *   otherwise invisible to the semantics tree, so "the Errors chip takes the error tint" could only
 *   be checked by capturing pixels (flaky) or not at all. It carries the ARGB the node actually
 *   painted with, so a wrong wire-up fails the test rather than the reviewer's eye.
 *
 * @coordinates-with DiagnosticsLogRow.kt, DiagnosticsFilterBar.kt, DiagnosticsFooter.kt,
 *   DiagnosticsLevel.kt, `dev-docs/designs/vreader-fidelity-v1/project/vreader-diagnostics.jsx`
 */
@Immutable
data class DiagnosticsTokens(
    /** The screen background (`t.bg`). */
    val bg: Color,
    /** The sheet surface the viewer sits on (`DiagNavSheet`'s panel). */
    val sheetBg: Color,
    /** Primary text (`t.ink`). */
    val ink: Color,
    /** Secondary text — and the DEBUG level treatment (`t.sub`). */
    val sub: Color,
    /** Hairline separators (`t.rule`). */
    val rule: Color,
    /** The theme accent — the "Copy entry" action (`t.accent`). */
    val accent: Color,
    /** Text on an inverted-ink pill (`t.isDark ? '#1a1815' : '#faf6ea'`). */
    val onInk: Color,
    /** The mono category pill's fill. */
    val pill: Color,
    /** The expanded row's background wash. */
    val expandedRow: Color,
    /** The error level/chip tint. */
    val errorTint: Color,
    /** The info level tint. */
    val infoTint: Color,
    /** The footer's "Capturing" dot — one green in both themes. */
    val capturingDot: Color,
    val isDark: Boolean,
) {
    /** The design's color for [level]'s row treatment (`diagLevelColor`). */
    fun levelColor(level: DiagnosticsLevel): Color = when (levelTreatment(level)) {
        DiagnosticsLevelTreatment.ERROR -> errorTint
        DiagnosticsLevelTreatment.INFO -> infoTint
        DiagnosticsLevelTreatment.DEBUG -> sub
    }

    companion object {
        /**
         * The footer status dot (`vreader-diagnostics.jsx:328`) — the same green in both themes.
         * Declared FIRST: companion properties initialize in declaration order, so a constant the
         * token sets read must precede them or it reads back as an unset value.
         */
        private val CapturingGreen = Color(0xFF4A9A6A)

        /** `THEMES.paper` + the diagnostics-local washes, exact from the bundle. */
        val Light = DiagnosticsTokens(
            bg = Color(0xFFF4EEE0),
            sheetBg = Color(0xFFFCF8F0),
            ink = Color(0xFF1D1A14),
            sub = Color(0x8C1D1A14),          // rgba(29,26,20,0.55)
            rule = Color(0x1F1D1A14),         // rgba(29,26,20,0.12)
            accent = Color(0xFF8C2F2F),
            onInk = Color(0xFFFAF6EA),
            pill = Color(0x0D000000),         // rgba(0,0,0,0.05)
            expandedRow = Color(0x06000000),  // rgba(0,0,0,0.025)
            errorTint = Color(0xFFB13E36),
            infoTint = Color(0xFF3A6F9C),
            capturingDot = CapturingGreen,
            isDark = false,
        )

        /** `THEMES.dark` + the diagnostics-local washes, exact from the bundle. */
        val Dark = DiagnosticsTokens(
            bg = Color(0xFF1A1815),
            sheetBg = Color(0xFF222020),
            ink = Color(0xFFD8D2C5),
            sub = Color(0x80D8D2C5),          // rgba(216,210,197,0.5)
            rule = Color(0x1FD8D2C5),         // rgba(216,210,197,0.12)
            accent = Color(0xFFD6885A),
            onInk = Color(0xFF1A1815),
            pill = Color(0x12FFFFFF),         // rgba(255,255,255,0.07)
            expandedRow = Color(0x08FFFFFF),  // rgba(255,255,255,0.03)
            errorTint = Color(0xFFE0826F),
            infoTint = Color(0xFF7FB2D9),
            capturingDot = CapturingGreen,
            isDark = true,
        )
    }
}

/** The three row treatments the design draws — NOT one per Android priority. */
enum class DiagnosticsLevelTreatment(val token: String) {
    ERROR("ERROR"),
    INFO("INFO"),
    DEBUG("DEBUG"),
}

/** Which of the design's three treatments [level] renders in. See this file's header for WARN. */
fun levelTreatment(level: DiagnosticsLevel): DiagnosticsLevelTreatment = when (level) {
    DiagnosticsLevel.ERROR, DiagnosticsLevel.ASSERT -> DiagnosticsLevelTreatment.ERROR
    DiagnosticsLevel.INFO -> DiagnosticsLevelTreatment.INFO
    DiagnosticsLevel.WARN, DiagnosticsLevel.DEBUG, DiagnosticsLevel.VERBOSE ->
        DiagnosticsLevelTreatment.DEBUG
}

/** The uppercase token the meta line prints for [level] — one of the design's three. */
fun levelToken(level: DiagnosticsLevel): String = levelTreatment(level).token

/** The diagnostics surface's fonts: the design's mono for data, Inter (sans) for chrome. */
object DiagnosticsFonts {
    val Mono: FontFamily = FontFamily.Monospace
    val Sans: FontFamily = FontFamily.SansSerif
}

/** The tokens the diagnostics surface renders in; the host provides the dark set on a dark device. */
val LocalDiagnosticsTokens = staticCompositionLocalOf { DiagnosticsTokens.Light }

/**
 * The ARGB a diagnostics node painted with, published to the semantics tree so a color is assertable
 * in a connected test. Test-observability only — no user-visible effect, no accessibility impact.
 */
val DiagnosticsColorKey = SemanticsPropertyKey<Int>("DiagnosticsColor")

var SemanticsPropertyReceiver.diagnosticsColor by DiagnosticsColorKey
