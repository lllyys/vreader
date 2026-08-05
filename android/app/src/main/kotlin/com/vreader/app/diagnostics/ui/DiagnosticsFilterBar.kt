package com.vreader.app.diagnostics.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.diagnostics.DiagnosticsLevelFilter
import com.vreader.app.diagnostics.DiagnosticsUiState

/**
 * Purpose: Feature #164 WI-6a — the designed filter bar (`DiagFilterBar` + `DiagChip`,
 * `vreader-diagnostics.jsx:205-243`, artboards F1/F2/F4): a level chip row carrying counts, above a
 * horizontally-scrolling category chip row.
 *
 * Key decisions:
 * - **The bar renders WI-5's state; it derives nothing.** Counts, the bounded chip list and the two
 *   active filters all arrive on [DiagnosticsUiState]. A chip row that recomputed its own counts
 *   could disagree with the footer about how many errors the device has.
 * - **Three chip forms, per the design** — the ACTIVE `Errors` chip takes the error tint (so a
 *   filtered list is legible at a glance), any other ACTIVE chip takes the inverted-ink pill, and an
 *   inactive chip is outlined. The fill is published through [DiagnosticsColorKey] so which form a
 *   chip took is assertable without capturing pixels.
 * - **The category row SCROLLS, never wraps** (`overflowX: auto` on a nowrap flex row). A plain
 *   `horizontalScroll` (not a `LazyRow`) is deliberate: the row is capped at
 *   `DiagnosticsCategoryBounding.MAX_CATEGORY_CHIPS + 1` chips, so laziness buys nothing and would
 *   cost off-screen chips their place in the semantics tree.
 * - **The LEVEL row scrolls too, though the design draws it as a plain flex row** (Gate-4 round 1
 *   High). Four chips plus their counts fit at the designed text size, but at a large accessibility
 *   font scale — or on a narrow device — the trailing chips overflow the viewport and become
 *   permanently unreachable, which is a filter a user cannot clear. Scrolling engages ONLY on
 *   overflow, so at the designed scale the row is pixel-identical to the artboards; nothing visible
 *   is invented. Asserted at `fontScale = 2f`.
 * - **The chip list is defended against blank and duplicate labels.** `DiagnosticsCategoryBounding`
 *   cannot emit either today, but a blank chip renders as an unlabelled tap target and a duplicate
 *   produces two identically-tagged, identically-acting chips. Filtering here keeps a malformed
 *   upstream state from becoming an untappable UI.
 * - **No `Warn` chip.** The design has four level chips and plan section 6.3 keeps it that way
 *   pending GH #2021; warn-level entries stay reachable under `All`.
 *
 * @coordinates-with DiagnosticsUiState.kt, DiagnosticsLevelStyle.kt, DiagnosticsCategoryBounding.kt,
 *   `dev-docs/designs/vreader-fidelity-v1/project/vreader-diagnostics.jsx`
 */
object DiagnosticsFilterTags {
    const val FILTER_BAR = "diag-filter-bar"
    const val LEVEL_ROW = "diag-level-row"
    const val CATEGORY_ROW = "diag-category-row"

    fun levelChip(filter: DiagnosticsLevelFilter): String = "diag-level-chip-${filter.name}"

    fun categoryChip(chip: String): String = "diag-category-chip-$chip"
}

/**
 * The two chip rows. [state] supplies the counts, the bounded category chips and both active
 * filters; [onSelectLevel] / [onSelectCategory] report a tap (the caller owns the filter state).
 */
@Composable
fun DiagnosticsFilterBar(
    state: DiagnosticsUiState,
    onSelectLevel: (DiagnosticsLevelFilter) -> Unit,
    onSelectCategory: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val tokens = LocalDiagnosticsTokens.current
    Column(
        modifier
            .fillMaxWidth()
            .testTag(DiagnosticsFilterTags.FILTER_BAR),
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .padding(top = 12.dp)
                .horizontalScroll(rememberScrollState())
                .padding(start = 18.dp, end = 18.dp)
                .testTag(DiagnosticsFilterTags.LEVEL_ROW),
            horizontalArrangement = Arrangement.spacedBy(7.dp),
        ) {
            DiagnosticsLevelFilter.entries.forEach { filter ->
                DiagnosticsChip(
                    label = filter.label,
                    count = state.levelCounts[filter] ?: 0,
                    active = state.levelFilter == filter,
                    // Only the Errors chip tints; every other active chip is the inverted-ink pill.
                    tint = if (filter == DiagnosticsLevelFilter.ERRORS) tokens.errorTint else null,
                    tag = DiagnosticsFilterTags.levelChip(filter),
                    onClick = { onSelectLevel(filter) },
                )
            }
        }
        Row(
            Modifier
                .fillMaxWidth()
                .padding(top = 8.dp)
                .horizontalScroll(rememberScrollState())
                .padding(start = 18.dp, end = 18.dp, bottom = 10.dp)
                .testTag(DiagnosticsFilterTags.CATEGORY_ROW),
            horizontalArrangement = Arrangement.spacedBy(7.dp),
        ) {
            state.categoryChips.filter { it.isNotBlank() }.distinct().forEach { chip ->
                DiagnosticsChip(
                    label = chip,
                    count = null,
                    active = state.categoryFilter == chip,
                    tint = null,
                    tag = DiagnosticsFilterTags.categoryChip(chip),
                    onClick = { onSelectCategory(chip) },
                )
            }
        }
        Box(
            Modifier
                .fillMaxWidth()
                .height(0.5.dp)
                .background(tokens.rule),
        )
    }
}

/**
 * One chip. [count] renders the design's dimmed badge when non-null; [tint] is the error color for
 * the `Errors` chip and null everywhere else, which is what selects between the three forms.
 */
@Composable
private fun DiagnosticsChip(
    label: String,
    count: Int?,
    active: Boolean,
    tint: Color?,
    tag: String,
    onClick: () -> Unit,
) {
    val tokens = LocalDiagnosticsTokens.current
    val fill = if (active) (tint ?: tokens.ink) else Color.Transparent
    // The design gives the ACTIVE chip a 0.5px TRANSPARENT border, not no border: both forms occupy
    // the same box, so a chip does not resize the row when it is selected.
    val outline = if (active) Color.Transparent else tokens.rule
    val content = when {
        !active -> tokens.sub
        tint != null -> Color.White
        else -> tokens.onInk
    }
    Row(
        Modifier
            .clip(RoundedCornerShape(percent = 50))
            .background(fill)
            .border(0.5.dp, outline, RoundedCornerShape(percent = 50))
            .clickable(onClick = onClick)
            .padding(horizontal = 11.dp, vertical = 5.dp)
            .testTag(tag)
            .semantics {
                diagnosticsColor = fill.toArgb()
                diagnosticsBorderColor = outline.toArgb()
            },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Text(
            label,
            color = content,
            fontFamily = DiagnosticsFonts.Sans,
            fontSize = 12.5.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
        )
        if (count != null) {
            Text(
                count.toString(),
                color = content.copy(alpha = content.alpha * 0.55f),
                fontFamily = DiagnosticsFonts.Sans,
                fontSize = 12.5.sp,
                fontWeight = FontWeight.Medium,
                maxLines = 1,
            )
        }
    }
}
