package com.vreader.app.diagnostics.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.diagnostics.DiagnosticsLogStore

/**
 * Purpose: Feature #164 WI-6b — the viewer's two non-list bodies: `DiagLoading` (`:339-353`) and
 * `DiagEmpty` in both its plain and filtered forms (`:355-384`). Artboards S1, S2/S3, F3.
 *
 * Key decisions:
 * - **The empty state is selected by the DESCRIPTOR, not by a boolean.** A `filtered: Boolean` pair
 *   admits `(filtered = true, label = null)`, whose only rendering would be "Nothing matches null in
 *   …" — and the rule-51-legal repair for that combination is another DESIGNED state, not invented
 *   copy. Passing `filterDescriptor: String?` makes the bad pair unrepresentable: a descriptor names
 *   the filtered form, its absence names the plain one.
 * - **The filtered body single-sources [DiagnosticsLogStore.CAPTURE_SCOPE_LABEL].** The design
 *   hardcodes *"in the last 24 hours"* (`:372`), naming a window this plan deliberately replaced;
 *   re-typing a third capture-scope phrase here is exactly what would let the footer, the export
 *   header and this sentence drift apart. The label is read, never repeated.
 * - **The plain body ships VERBATIM even when capture is degraded.** If logcat is denied and the
 *   ring is empty, *"Entries appear here automatically"* is untrue — but inventing replacement copy
 *   is what rule 51 forbids, and the availability signal reaches the reader through the export
 *   header's `capture source:` line instead. The designed availability treatment is filed as
 *   **GH #2022** (plan section 6.5b); when it lands, it replaces this state.
 * - **The spinner is Material's indeterminate circular indicator**, configured to the design's
 *   geometry (26dp, 2.5 stroke, accent arc over a `rule` track) rather than hand-animated: the
 *   design draws exactly that — a track circle plus a one-quadrant accent arc in a linear spin.
 *
 * @coordinates-with DiagnosticsScreen.kt, DiagnosticsLevelStyle.kt, DiagnosticsLogStore.kt,
 *   `dev-docs/designs/vreader-fidelity-v1/project/vreader-diagnostics.jsx`
 */
object DiagnosticsStateTags {
    const val LOADING = "diag-loading"
    const val SPINNER = "diag-loading-spinner"
    const val EMPTY = "diag-empty"
    const val EMPTY_TILE = "diag-empty-tile"
    const val CLEAR_FILTERS = "diag-clear-filters"
}

/** Every literal these two states render. */
object DiagnosticsStateStrings {
    const val LOADING_TITLE = "Reading log store…"

    /** Plan section 6.6: the design's `OSLogStore · com.vreader.app` is an iOS type name. */
    const val LOADING_SOURCE = "logcat · com.vreader.app"

    const val EMPTY_TITLE = "No log entries yet"

    const val EMPTY_BODY =
        "VReader records errors and key events as you read. " +
            "Entries appear here automatically — nothing to turn on."

    const val FILTERED_TITLE = "No matching entries"

    const val CLEAR_FILTERS = "Clear filters"

    /**
     * `Nothing matches <descriptor> in <capture scope>.` — the design's sentence with its hardcoded
     * window replaced by the one label the footer and the export header also use.
     */
    fun filteredBody(descriptor: String): String =
        "Nothing matches $descriptor in ${DiagnosticsLogStore.CAPTURE_SCOPE_LABEL}."
}

/** `DIAG_TILE` — the steel diagnostics tile (`vreader-diagnostics.jsx:19`). */
private val EmptyTileSteel = Color(0xFF5B6770)

/** The loading body: spinner over the title + the platform-true source line (`:339-353`). */
@Composable
fun DiagnosticsLoadingState(modifier: Modifier = Modifier) {
    val tokens = LocalDiagnosticsTokens.current
    Column(
        modifier
            .fillMaxSize()
            .testTag(DiagnosticsStateTags.LOADING),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        CircularProgressIndicator(
            modifier = Modifier
                .size(26.dp)
                .testTag(DiagnosticsStateTags.SPINNER),
            color = tokens.accent,
            trackColor = tokens.rule,
            strokeWidth = 2.5.dp,
        )
        Text(
            DiagnosticsStateStrings.LOADING_TITLE,
            modifier = Modifier.padding(top = 14.dp),
            color = tokens.ink,
            fontFamily = DiagnosticsFonts.Sans,
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            DiagnosticsStateStrings.LOADING_SOURCE,
            modifier = Modifier.padding(top = 4.dp),
            color = tokens.sub,
            fontFamily = DiagnosticsFonts.Mono,
            fontSize = 10.5.sp,
        )
    }
}

/**
 * The empty body. A non-null [filterDescriptor] ("errors", "Persistence", "DebugBridge errors")
 * renders the FILTERED form — filter tile, "No matching entries", and the working [onClearFilters]
 * button. A null descriptor renders the plain fresh-install form, which has no button.
 */
@Composable
fun DiagnosticsEmptyState(
    filterDescriptor: String?,
    onClearFilters: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val tokens = LocalDiagnosticsTokens.current
    val filtered = filterDescriptor != null
    Column(
        modifier
            .fillMaxSize()
            .padding(horizontal = 44.dp)
            .testTag(DiagnosticsStateTags.EMPTY),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Box(
            Modifier
                .size(54.dp)
                .clip(RoundedCornerShape(14.dp))
                .background(
                    if (filtered) {
                        // `isDark ? rgba(255,255,255,0.06) : rgba(0,0,0,0.05)` (:360).
                        if (tokens.isDark) Color(0x0FFFFFFF) else Color(0x0D000000)
                    } else {
                        EmptyTileSteel
                    },
                )
                .testTag(DiagnosticsStateTags.EMPTY_TILE),
            contentAlignment = Alignment.Center,
        ) {
            if (filtered) {
                Icon(
                    DiagnosticsFilterGlyph,
                    contentDescription = null,
                    tint = tokens.sub,
                    modifier = Modifier.size(22.dp),
                )
            } else {
                Icon(
                    DiagnosticsIcons.pulse(strokeWidth = 1.7f),
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(26.dp),
                )
            }
        }
        Text(
            if (filtered) {
                DiagnosticsStateStrings.FILTERED_TITLE
            } else {
                DiagnosticsStateStrings.EMPTY_TITLE
            },
            modifier = Modifier.padding(top = 16.dp),
            color = tokens.ink,
            fontFamily = DiagnosticsFonts.Sans,
            fontSize = 15.sp,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
        )
        Text(
            filterDescriptor?.let { DiagnosticsStateStrings.filteredBody(it) }
                ?: DiagnosticsStateStrings.EMPTY_BODY,
            modifier = Modifier.padding(top = 6.dp),
            color = tokens.sub,
            fontFamily = DiagnosticsFonts.Sans,
            fontSize = 12.5.sp,
            lineHeight = 18.75.sp,   // `lineHeight: 1.5` on 12.5
            textAlign = TextAlign.Center,
        )
        if (filtered) {
            Text(
                DiagnosticsStateStrings.CLEAR_FILTERS,
                modifier = Modifier
                    .padding(top = 14.dp)
                    .clip(RoundedCornerShape(percent = 50))
                    .clickable(onClick = onClearFilters)
                    // `background: ${t.accent}18` (:378) — the accent at 0x18 alpha.
                    .background(tokens.accent.copy(alpha = 0x18 / 255f))
                    .padding(horizontal = 14.dp, vertical = 6.dp)
                    .testTag(DiagnosticsStateTags.CLEAR_FILTERS),
                color = tokens.accent,
                fontFamily = DiagnosticsFonts.Sans,
                fontSize = 12.5.sp,
                fontWeight = FontWeight.SemiBold,
            )
        }
    }
}

/** `Icons.Filter` — `M4 5h16l-6 8v6l-4-2v-4z` (`vreader-icons.jsx:15`) at the 1.7 stroke of `:364`. */
private val DiagnosticsFilterGlyph: ImageVector by lazy {
    ImageVector.Builder(
        name = "DiagnosticsFilter",
        defaultWidth = 24.dp,
        defaultHeight = 24.dp,
        viewportWidth = 24f,
        viewportHeight = 24f,
    ).apply {
        strokedPath {
            moveTo(4f, 5f)
            horizontalLineToRelative(16f)
            lineToRelative(-6f, 8f)
            verticalLineToRelative(6f)
            lineToRelative(-4f, -2f)
            verticalLineToRelative(-4f)
            close()
        }
    }.build()
}

private fun ImageVector.Builder.strokedPath(pathBuilder: PathBuilder.() -> Unit) = path(
    fill = null,
    stroke = SolidColor(Color.White),
    strokeLineWidth = 1.7f,
    strokeLineCap = StrokeCap.Round,
    strokeLineJoin = StrokeJoin.Round,
    pathBuilder = pathBuilder,
)
