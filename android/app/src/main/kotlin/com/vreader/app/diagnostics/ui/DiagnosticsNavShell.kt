package com.vreader.app.diagnostics.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathBuilder
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.ui.theme.VReaderFonts

/**
 * Purpose: Feature #164 WI-6b — the viewer's container: the design's `DiagNavSheet`
 * (`vreader-diagnostics.jsx:137-183`) translated into the sheet vocabulary this app already ships
 * (grabber, leading back control, absolutely-centered serif title, trailing action slot).
 *
 * Key decisions (plan section 6.5a — the Android container is an ADJUDICATED translation, not an
 * invention):
 * - **The design is an iOS bottom sheet pushed inside Settings.** The Android translation reuses the
 *   shipped `ReaderAiProvidersList` / `BookDetailsSheet` shell — scrim, top-rounded panel, grabber,
 *   `‹ <parent>` leading control, centered `Source Serif` title, trailing slot — so the surface
 *   reads as one of this app's sheets rather than as a new kind of screen.
 * - **ONE dismissal path.** Android system back is routed to the SAME [onBack] the leading control
 *   calls. The design has no system-back concept, and two divergent dismissals would be a defect,
 *   not a design choice. This is why [onBack] is a single parameter and not a pair — the shell makes
 *   the divergence unrepresentable rather than merely discouraged.
 * - **The title carries no click and no back semantics**, matching the design's
 *   `pointerEvents: 'none'`: it is absolutely centered over the bar, so a clickable title would
 *   swallow taps aimed at the controls beneath its (full-width) box.
 * - **The trailing slot is nullable.** `DiagLogViewer` passes `null` in the loading and empty states;
 *   the slot renders nothing rather than an empty box, so no phantom target sits in the bar.
 *
 * @coordinates-with DiagnosticsScreen.kt, DiagnosticsShareButton.kt, DiagnosticsLevelStyle.kt,
 *   `dev-docs/designs/vreader-fidelity-v1/project/vreader-diagnostics.jsx`
 */
object DiagnosticsNavTags {
    const val SHELL = "diag-nav-shell"
    const val SCRIM = "diag-nav-scrim"
    const val GRABBER = "diag-nav-grabber"
    const val BAR = "diag-nav-bar"
    const val BACK = "diag-nav-back"
    const val TITLE = "diag-nav-title"
    const val TRAILING = "diag-nav-trailing"
}

/** The shell's literals, from the design's `DiagNavSheet` defaults (`:137`). */
object DiagnosticsNavStrings {
    const val TITLE = "Diagnostics"

    /** The design labels the back control with its PARENT surface, not with the word "Back". */
    const val BACK_LABEL = "Settings"
}

/** `height={740}` inside the 768pt artboard (`diagnostics-artboards.jsx:13`/`:93`). */
private const val SHEET_HEIGHT_FRACTION = 0.96f

/**
 * The diagnostics sheet frame. [onBack] is the ONE dismissal action — the leading control and
 * Android system back both call it. [trailing] is the nav bar's action slot (null renders nothing).
 * [content] fills the panel below the bar.
 */
@Composable
fun DiagnosticsNavShell(
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    title: String = DiagnosticsNavStrings.TITLE,
    backLabel: String = DiagnosticsNavStrings.BACK_LABEL,
    trailing: (@Composable () -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val tokens = LocalDiagnosticsTokens.current

    // The single dismissal path: system back IS the leading control (section 6.5a).
    BackHandler(enabled = true) { onBack() }

    Box(
        modifier
            .fillMaxSize()
            .background(SCRIM)          // `rgba(0,0,0,0.35)` (:143)
            .testTag(DiagnosticsNavTags.SCRIM),
        contentAlignment = Alignment.BottomCenter,
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .fillMaxHeight(SHEET_HEIGHT_FRACTION)
                .clip(RoundedCornerShape(topStart = 22.dp, topEnd = 22.dp))
                .background(tokens.sheetBg)
                .systemBarsPadding()
                .testTag(DiagnosticsNavTags.SHELL),
        ) {
            Grabber(isDark = tokens.isDark)
            NavBar(title = title, backLabel = backLabel, onBack = onBack, trailing = trailing)
            content()
        }
    }
}

/** The drag affordance — 36×5, radius 3 (`:151-156`). */
@Composable
private fun Grabber(isDark: Boolean) {
    Box(
        Modifier
            .fillMaxWidth()
            .padding(top = 8.dp),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .width(36.dp)
                .height(5.dp)
                .clip(RoundedCornerShape(3.dp))
                // `isDark ? rgba(255,255,255,0.18) : rgba(0,0,0,0.12)` (:154).
                .background(if (isDark) Color(0x2EFFFFFF) else Color(0x1F000000))
                .testTag(DiagnosticsNavTags.GRABBER),
        )
    }
}

/** `padding: '13px 16px 12px'` + a 0.5px bottom hairline (`:157-178`). */
@Composable
private fun NavBar(
    title: String,
    backLabel: String,
    onBack: () -> Unit,
    trailing: (@Composable () -> Unit)?,
) {
    val tokens = LocalDiagnosticsTokens.current
    Column(Modifier.fillMaxWidth()) {
        Box(
            Modifier
                .fillMaxWidth()
                .padding(start = 16.dp, end = 16.dp, top = 13.dp, bottom = 12.dp)
                .testTag(DiagnosticsNavTags.BAR),
        ) {
            // The centered title, drawn FIRST so the interactive controls sit above it. It takes no
            // pointer input (`pointerEvents: 'none'`, :175) and WRAPS its text rather than filling
            // the bar: a full-width title box would sit over both controls and swallow their taps.
            Text(
                title,
                modifier = Modifier
                    .align(Alignment.Center)
                    .testTag(DiagnosticsNavTags.TITLE),
                color = tokens.ink,
                fontFamily = VReaderFonts.Serif,
                fontSize = 17.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
            )
            Row(
                Modifier
                    .align(Alignment.CenterStart)
                    .clip(RoundedCornerShape(8.dp))
                    .clickable(onClickLabel = backLabel, onClick = onBack)
                    .padding(vertical = 6.dp, horizontal = 2.dp)
                    .testTag(DiagnosticsNavTags.BACK),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(1.dp),
            ) {
                Icon(
                    DiagnosticsChevronLeft,
                    contentDescription = null,
                    tint = tokens.accent,
                    modifier = Modifier.size(19.dp),
                )
                Text(
                    backLabel,
                    color = tokens.accent,
                    fontFamily = DiagnosticsFonts.Sans,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Medium,
                    maxLines = 1,
                )
            }
            if (trailing != null) {
                Box(
                    Modifier
                        .align(Alignment.CenterEnd)
                        .testTag(DiagnosticsNavTags.TRAILING),
                    contentAlignment = Alignment.Center,
                ) {
                    trailing()
                }
            }
        }
        Box(
            Modifier
                .fillMaxWidth()
                .height(0.5.dp)
                // `isDark ? rgba(255,255,255,0.08) : rgba(0,0,0,0.08)` (:160) — the bar's hairline is
                // lighter than the token `rule`, which the design uses for the body separators.
                .background(if (tokens.isDark) Color(0x14FFFFFF) else Color(0x14000000)),
        )
    }
}

/** `rgba(0,0,0,0.35)` — the sheet's dimming scrim (`:143`). */
private val SCRIM = Color(0x59000000)

/** `Icons.ChevronL` — `M15 6l-6 6 6 6` (`vreader-icons.jsx:17`) at the bundle's 2.2 stroke (`:168`). */
private val DiagnosticsChevronLeft: ImageVector by lazy {
    ImageVector.Builder(
        name = "DiagnosticsChevronLeft",
        defaultWidth = 24.dp,
        defaultHeight = 24.dp,
        viewportWidth = 24f,
        viewportHeight = 24f,
    ).apply {
        strokedPath {
            moveTo(15f, 6f)
            lineToRelative(-6f, 6f)
            lineToRelative(6f, 6f)
        }
    }.build()
}

private fun ImageVector.Builder.strokedPath(pathBuilder: PathBuilder.() -> Unit) = path(
    fill = null,
    stroke = SolidColor(Color.White),
    strokeLineWidth = 2.2f,
    strokeLineCap = StrokeCap.Round,
    strokeLineJoin = StrokeJoin.Round,
    pathBuilder = pathBuilder,
)
