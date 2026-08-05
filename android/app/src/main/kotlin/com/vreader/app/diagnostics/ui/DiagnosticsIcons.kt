package com.vreader.app.diagnostics.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.unit.dp

/**
 * Purpose: Feature #164 WI-6a — the diagnostics glyph the design adds to the icon set
 * (`DiagPulseIcon`, `vreader-diagnostics.jsx:31-36`).
 *
 * Key decisions:
 * - **Built as an [ImageVector], not a `res/drawable`.** The design gives the glyph as a single SVG
 *   path in the same 24×24 viewport / round-cap / round-join stroke vocabulary as the rest of the
 *   bundle's icons, so the path data IS the spec; a drawable XML would be a second copy of it.
 * - **The stroke width is a parameter with the design's 1.8 default**, because the bundle draws the
 *   same glyph at 1.8 (Settings tile) and 1.7 (the larger empty-state tile).
 * - Colored by `tint` at the call site (an [Icon]'s tint), so the vector itself carries
 *   [Color.White]-neutral stroke geometry only.
 *
 * @coordinates-with DiagnosticsLevelStyle.kt,
 *   `dev-docs/designs/vreader-fidelity-v1/project/vreader-diagnostics.jsx`
 */
object DiagnosticsIcons {

    /** The design's waveform glyph, `M3 12h4l2.5-6 5 12 2.5-6h4` on a 24×24 viewport. */
    val Pulse: ImageVector by lazy { pulse(strokeWidth = 1.8f) }

    /** The same glyph at another stroke weight (the bundle uses 1.7 on the 54dp empty-state tile). */
    fun pulse(strokeWidth: Float): ImageVector =
        ImageVector.Builder(
            name = "DiagnosticsPulse",
            defaultWidth = 24.dp,
            defaultHeight = 24.dp,
            viewportWidth = 24f,
            viewportHeight = 24f,
        ).apply {
            path(
                fill = null,
                stroke = SolidColor(Color.White),
                strokeLineWidth = strokeWidth,
                strokeLineCap = StrokeCap.Round,
                strokeLineJoin = StrokeJoin.Round,
            ) {
                moveTo(3f, 12f)
                horizontalLineToRelative(4f)
                lineToRelative(2.5f, -6f)
                lineToRelative(5f, 12f)
                lineToRelative(2.5f, -6f)
                horizontalLineToRelative(4f)
            }
        }.build()
}
