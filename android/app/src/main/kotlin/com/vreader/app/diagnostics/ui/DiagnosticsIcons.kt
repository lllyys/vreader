package com.vreader.app.diagnostics.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathBuilder
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.unit.dp

/**
 * Purpose: Feature #164 WI-6a — the diagnostics glyphs, transcribed from the committed design
 * bundle: the pulse waveform the design adds to the icon set (`DiagPulseIcon`,
 * `vreader-diagnostics.jsx:31-36`) and the copy glyph the expanded row's "Copy entry" action needs.
 *
 * Key decisions:
 * - **Built as [ImageVector]s, not `res/drawable`s.** The design gives each glyph as SVG path data
 *   in one 24×24 viewport / round-cap / round-join stroke vocabulary, so the path data IS the spec;
 *   a drawable XML would be a second copy of it.
 * - **The stroke width is a parameter with the design's 1.8 default** for the pulse, because the
 *   bundle draws the same glyph at 1.8 (Settings tile) and 1.7 (the larger empty-state tile).
 * - **[Copy] is the BUNDLE's copy glyph, not the platform's** (Gate-4 round 2). `vreader-icons.jsx`
 *   has no `Copy` entry even though `vreader-diagnostics.jsx:295` references `Icons.Copy`, so the
 *   first implementation substituted Material's `Icons.Outlined.ContentCopy` on the belief that the
 *   bundle contained no copy path at all. That was WRONG: the bundle defines this exact glyph twice
 *   — `AAGlyph(name = "copy")` in `vreader-annotations-actions.jsx:60` (24×24, stroke 1.7, round
 *   caps/joins — the same vocabulary as the pulse) and `HPCopyGlyph` in
 *   `vreader-highlight-popover.jsx:413` (a 20×20 variant of the same two shapes). The 24×24 form is
 *   transcribed here, so the row's glyph traces to committed design rather than to Material.
 * - Colored by `tint` at the call site (an `Icon`'s tint), so the vectors carry [Color.White]-neutral
 *   stroke geometry only.
 *
 * @coordinates-with DiagnosticsLevelStyle.kt,
 *   `dev-docs/designs/vreader-fidelity-v1/project/vreader-diagnostics.jsx`
 */
object DiagnosticsIcons {

    /** The design's waveform glyph, `M3 12h4l2.5-6 5 12 2.5-6h4` on a 24×24 viewport. */
    val Pulse: ImageVector by lazy { pulse(strokeWidth = 1.8f) }

    /** The same glyph at another stroke weight (the bundle uses 1.7 on the 54dp empty-state tile). */
    fun pulse(strokeWidth: Float): ImageVector =
        glyph("DiagnosticsPulse", strokeWidth) {
            moveTo(3f, 12f)
            horizontalLineToRelative(4f)
            lineToRelative(2.5f, -6f)
            lineToRelative(5f, 12f)
            lineToRelative(2.5f, -6f)
            horizontalLineToRelative(4f)
        }

    /**
     * The bundle's copy glyph — `AAGlyph(name = "copy")`, a rounded 11×11 sheet at (9,9) with the
     * page behind it, drawn at the bundle's 1.7 stroke weight.
     */
    val Copy: ImageVector by lazy {
        ImageVector.Builder(
            name = "DiagnosticsCopy",
            defaultWidth = 24.dp,
            defaultHeight = 24.dp,
            viewportWidth = 24f,
            viewportHeight = 24f,
        ).apply {
            // `<rect x="9" y="9" width="11" height="11" rx="2"/>` — the front sheet.
            strokePath(BUNDLE_STROKE) {
                moveTo(11f, 9f)
                horizontalLineTo(18f)
                arcToRelative(2f, 2f, 0f, false, true, 2f, 2f)
                verticalLineTo(18f)
                arcToRelative(2f, 2f, 0f, false, true, -2f, 2f)
                horizontalLineTo(11f)
                arcToRelative(2f, 2f, 0f, false, true, -2f, -2f)
                verticalLineTo(11f)
                arcToRelative(2f, 2f, 0f, false, true, 2f, -2f)
                close()
            }
            // `<path d="M5 15V5a2 2 0 012-2h8"/>` — the page behind it.
            strokePath(BUNDLE_STROKE) {
                moveTo(5f, 15f)
                verticalLineTo(5f)
                arcToRelative(2f, 2f, 0f, false, true, 2f, -2f)
                horizontalLineToRelative(8f)
            }
        }.build()
    }

    /** The bundle's default stroke weight for a 24×24 glyph (`AAGlyph`'s `strokeWidth: 1.7`). */
    private const val BUNDLE_STROKE = 1.7f

    private fun glyph(
        name: String,
        strokeWidth: Float,
        pathData: PathBuilder.() -> Unit,
    ): ImageVector = ImageVector.Builder(
        name = name,
        defaultWidth = 24.dp,
        defaultHeight = 24.dp,
        viewportWidth = 24f,
        viewportHeight = 24f,
    ).apply { strokePath(strokeWidth, pathData) }.build()

    /** One stroked subpath in the bundle's vocabulary: no fill, round caps, round joins. */
    private fun ImageVector.Builder.strokePath(
        strokeWidth: Float,
        pathData: PathBuilder.() -> Unit,
    ) = path(
        fill = null,
        stroke = SolidColor(Color.White),
        strokeLineWidth = strokeWidth,
        strokeLineCap = StrokeCap.Round,
        strokeLineJoin = StrokeJoin.Round,
        pathBuilder = pathData,
    )
}
