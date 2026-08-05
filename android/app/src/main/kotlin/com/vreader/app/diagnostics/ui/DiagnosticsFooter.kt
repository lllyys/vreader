package com.vreader.app.diagnostics.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Purpose: Feature #164 WI-6a — the pinned status footer (`DiagFooter`,
 * `vreader-diagnostics.jsx:319-334`): the mono scope line on the left, the green-dot "Capturing"
 * status on the right.
 *
 * Key decisions:
 * - **A statement, not a control.** The design's note is explicit — capture is always on in Release,
 *   so the footer says so instead of offering a toggle. There is therefore no `capturing` parameter
 *   and no "paused" form: an undepicted state would be invented UI (rule 51).
 * - **The scope sentence is passed in, never composed here.** `DiagnosticsUiState.footerScope` owns
 *   all three designed grammars (unfiltered / filtered-with-results / filtered-empty) and
 *   single-sources the capture-window label with the export header. A footer that built its own
 *   sentence would be a fourth grammar nobody could keep in step.
 * - **The scope line yields, the status does not.** A pathological scope string ellipsizes rather
 *   than pushing "Capturing" off the edge — the status is the reassurance the footer exists for.
 *
 * @coordinates-with DiagnosticsUiState.kt, DiagnosticsLogStore.kt (CAPTURE_SCOPE_LABEL),
 *   DiagnosticsLevelStyle.kt, `dev-docs/designs/vreader-fidelity-v1/project/vreader-diagnostics.jsx`
 */
object DiagnosticsFooterTags {
    const val FOOTER = "diag-footer"
    const val SCOPE = "diag-footer-scope"
    const val CAPTURING = "diag-footer-capturing"
    const val DOT = "diag-footer-dot"
}

/** The design's "Capturing" reassurance — a literal, not a state the app can be out of. */
private const val CAPTURING_LABEL = "Capturing"

/** The pinned footer. [scope] is `DiagnosticsUiState.footerScope`, rendered verbatim. */
@Composable
fun DiagnosticsFooter(scope: String, modifier: Modifier = Modifier) {
    val tokens = LocalDiagnosticsTokens.current
    Column(
        modifier
            .fillMaxWidth()
            .testTag(DiagnosticsFooterTags.FOOTER),
    ) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(0.5.dp)
                .background(tokens.rule),
        )
        Row(
            Modifier
                .fillMaxWidth()
                .padding(start = 18.dp, end = 18.dp, top = 10.dp, bottom = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                scope,
                modifier = Modifier
                    .weight(1f, fill = false)
                    .testTag(DiagnosticsFooterTags.SCOPE),
                color = tokens.sub,
                fontFamily = DiagnosticsFonts.Mono,
                fontSize = 10.5.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Row(
                Modifier.testTag(DiagnosticsFooterTags.CAPTURING),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(5.dp),
            ) {
                Box(
                    Modifier
                        .size(6.dp)
                        .clip(CircleShape)
                        .background(tokens.capturingDot)
                        .testTag(DiagnosticsFooterTags.DOT)
                        .semantics { diagnosticsColor = tokens.capturingDot.toArgb() },
                )
                Text(
                    CAPTURING_LABEL,
                    color = tokens.sub,
                    fontFamily = DiagnosticsFonts.Sans,
                    fontSize = 10.5.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                )
            }
        }
    }
}
