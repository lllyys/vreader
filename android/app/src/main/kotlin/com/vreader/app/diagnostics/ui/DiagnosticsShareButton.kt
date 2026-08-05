package com.vreader.app.diagnostics.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathBuilder
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

/**
 * Purpose: Feature #164 WI-6b — the nav bar's trailing share affordance (`DiagShareButton`,
 * `vreader-diagnostics.jsx:186-197`), the design's CANONICAL export trigger (artboard X1; the
 * pinned "Export log…" footer CTA at X2 is an explicitly rejected alternative and is not built).
 *
 * Key decisions:
 * - **The 28dp circle is the VISUAL, not the touch target.** The design draws a 28×28 button, which
 *   is well under Android's 48dp minimum tap size. The glyph and its wash keep the designed 28dp
 *   while an invisible 48dp box carries the click, so the affordance looks like the artboard and is
 *   still reachable with a thumb. Changing the visual diameter would be a design change; changing
 *   the touch box is not. The nav bar pins its own designed height, so this larger target does not
 *   push the bar taller than the artboard (see `DiagnosticsNavShell`).
 * - **The glyph is transcribed from the bundle**, not taken from material-icons-extended — the same
 *   call `DiagnosticsIcons` (WI-6a) made for the pulse and copy glyphs, so every diagnostics icon
 *   traces to committed design.
 * - **Visibility is the CALLER's decision.** `DiagLogViewer` hides this affordance in the loading
 *   and empty states (`:456`); expressing that here would split one predicate across two files.
 *   [DiagnosticsScreenContent] owns it, and the hidden cases are asserted there.
 *
 * @coordinates-with DiagnosticsNavShell.kt, DiagnosticsScreen.kt, DiagnosticsLevelStyle.kt,
 *   `dev-docs/designs/vreader-fidelity-v1/project/vreader-diagnostics.jsx`
 */
object DiagnosticsShareTags {
    const val BUTTON = "diag-share-button"
}

/** The accessibility label for an icon-only control — the action, not the glyph. */
const val DIAGNOSTICS_SHARE_LABEL: String = "Share log"

/** The design's 28×28 visual (`:189`). */
private val SHARE_DIAMETER = 28.dp

/** Android's minimum interactive size — invisible, centered on the 28dp visual. */
val DIAGNOSTICS_MIN_TOUCH_TARGET = 48.dp

/** `Icons.Share size={15}` (`:194`). */
private val SHARE_GLYPH_SIZE = 15.dp

/**
 * The share trigger. [onShare] fires the export flow (WI-7 supplies it); the button renders the
 * design's wash over the current token set.
 */
@Composable
fun DiagnosticsShareButton(onShare: () -> Unit, modifier: Modifier = Modifier) {
    val tokens = LocalDiagnosticsTokens.current
    // `t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)'` (:191).
    val wash = if (tokens.isDark) Color(0x14FFFFFF) else Color(0x0F000000)
    Box(
        modifier
            .size(DIAGNOSTICS_MIN_TOUCH_TARGET)
            .clip(CircleShape)
            .clickable(onClick = onShare)
            .testTag(DiagnosticsShareTags.BUTTON)
            .semantics { contentDescription = DIAGNOSTICS_SHARE_LABEL },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .size(SHARE_DIAMETER)
                .clip(CircleShape)
                .background(wash)
                .semantics { diagnosticsColor = wash.toArgb() },
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                DiagnosticsShareGlyph,
                contentDescription = null,
                tint = tokens.accent,
                modifier = Modifier.size(SHARE_GLYPH_SIZE),
            )
        }
    }
}

/**
 * `Icons.Share` — `M12 3v13M8 7l4-4 4 4M5 14v5a2 2 0 002 2h10a2 2 0 002-2v-5`
 * (`vreader-icons.jsx:27`) at the bundle's 1.9 stroke for this call site (`:194`).
 */
private val DiagnosticsShareGlyph: ImageVector by lazy {
    ImageVector.Builder(
        name = "DiagnosticsShare",
        defaultWidth = 24.dp,
        defaultHeight = 24.dp,
        viewportWidth = 24f,
        viewportHeight = 24f,
    ).apply {
        // The upright shaft and its arrowhead.
        strokedPath {
            moveTo(12f, 3f)
            verticalLineToRelative(13f)
        }
        strokedPath {
            moveTo(8f, 7f)
            lineToRelative(4f, -4f)
            lineToRelative(4f, 4f)
        }
        // The tray it lifts out of.
        strokedPath {
            moveTo(5f, 14f)
            verticalLineToRelative(5f)
            arcToRelative(2f, 2f, 0f, false, false, 2f, 2f)
            horizontalLineToRelative(10f)
            arcToRelative(2f, 2f, 0f, false, false, 2f, -2f)
            verticalLineToRelative(-5f)
        }
    }.build()
}

/** One stroked subpath in the bundle's vocabulary: no fill, round caps, round joins. */
private fun ImageVector.Builder.strokedPath(pathBuilder: PathBuilder.() -> Unit) = path(
    fill = null,
    stroke = SolidColor(Color.White),
    strokeLineWidth = 1.9f,
    strokeLineCap = StrokeCap.Round,
    strokeLineJoin = StrokeJoin.Round,
    pathBuilder = pathBuilder,
)
