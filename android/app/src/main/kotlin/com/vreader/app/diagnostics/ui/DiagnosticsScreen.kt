package com.vreader.app.diagnostics.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.vreader.app.diagnostics.DiagnosticsContent
import com.vreader.app.diagnostics.DiagnosticsLevelFilter
import com.vreader.app.diagnostics.DiagnosticsUiState
import com.vreader.app.diagnostics.DiagnosticsViewModel
import java.time.ZoneId

/**
 * Purpose: Feature #164 WI-6b — the diagnostics viewer screen (`DiagLogViewer`,
 * `vreader-diagnostics.jsx:441-491`): the nav shell, the state-driven body, and the chrome the
 * design shows or hides with it. Split into [DiagnosticsScreen] (binds the ViewModel) and
 * [DiagnosticsScreenContent] (a pure function of state, directly testable) — the
 * `ReaderSettingsSheet`/`…Content` and `BookDetailsSheet`/`…Content` house convention.
 *
 * Key decisions:
 * - **ONE chrome predicate, computed once.** `DiagLogViewer` gates the share affordance (`:456`),
 *   the filter bar (`:457`) AND the footer (`:469`) on the SAME `!busy && state !== 'empty'`. Plan
 *   v1/v2 recorded only the first two, which would have shipped
 *   `"0 entries · recent activity · ● Capturing"` over a fresh install — an artboard that does not
 *   exist. `chromeVisible` below is that predicate, named once and read three times, so the three
 *   cannot drift apart again.
 * - **The list VIRTUALIZES.** A `LazyColumn` keeps only the rows near the viewport composed, so a
 *   long capture window costs a bounded amount of composition rather than one row object per entry.
 *   Asserted as behaviour (peak concurrent row compositions over a 2000-entry state), not by naming
 *   the widget — see [LocalDiagnosticsRowProbe].
 * - **Row identity is the LazyColumn key.** `IdentifiedDiagnosticsEntry.id` is positional within the
 *   current filter, so it is namespaced by section id: two byte-identical entries must scroll and
 *   expand independently, which content-derived keys would collapse.
 * - **This screen has NO production call site until WI-8** wires it behind the Settings entry
 *   (#171). That is recorded as annotated debt in `scripts/.orphan-surfaces-allow`, NOT silenced —
 *   `scripts/check-orphan-surfaces.sh` exists because four Android features shipped `VERIFIED` with
 *   UI a user could never reach.
 *
 * @coordinates-with DiagnosticsNavShell.kt, DiagnosticsStates.kt, DiagnosticsShareButton.kt,
 *   DiagnosticsFilterBar.kt, DiagnosticsLogRow.kt, DiagnosticsFooter.kt, DiagnosticsViewModel.kt,
 *   `dev-docs/designs/vreader-fidelity-v1/project/vreader-diagnostics.jsx`
 */
object DiagnosticsScreenTags {
    const val CONTENT = "diag-screen-content"
    const val LIST = "diag-log-list"
}

/**
 * Reports a log row entering and leaving the composition.
 *
 * A test-observability seam, exactly like `DiagnosticsColorKey` (WI-6a) and a `testTag`: whether the
 * list virtualizes is otherwise invisible to the semantics tree, because a snapshot of that tree
 * cannot see a row that composed and was disposed between two idle points. Production supplies no
 * probe ([LocalDiagnosticsRowProbe] defaults to null), so the cost is one null check per composed
 * row — and rows composed are bounded, which is the very property being measured.
 */
interface DiagnosticsRowProbe {
    fun onRowEnterComposition()
    fun onRowLeaveComposition()
}

/** Null in production; a connected test provides a counter. */
val LocalDiagnosticsRowProbe = staticCompositionLocalOf<DiagnosticsRowProbe?> { null }

/**
 * The viewer bound to its [viewModel]. Loads on first composition; [onBack] dismisses (the leading
 * control AND Android system back), [onShare] fires WI-7's export flow.
 */
@Composable
fun DiagnosticsScreen(
    viewModel: DiagnosticsViewModel,
    onBack: () -> Unit,
    onShare: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val tokens = if (isSystemInDarkTheme()) DiagnosticsTokens.Dark else DiagnosticsTokens.Light

    LaunchedEffect(viewModel) { viewModel.load() }

    CompositionLocalProvider(LocalDiagnosticsTokens provides tokens) {
        DiagnosticsScreenContent(
            state = state,
            onBack = onBack,
            onShare = onShare,
            onSelectLevel = viewModel::selectLevel,
            onSelectCategory = viewModel::selectCategory,
            onClearFilters = viewModel::clearFilters,
            onToggleExpanded = viewModel::toggleExpanded,
            modifier = modifier,
        )
    }
}

/**
 * The viewer as a pure function of [state]. [zone] renders the row timestamps (injected so a test
 * is not at the mercy of the device zone).
 */
@Composable
fun DiagnosticsScreenContent(
    state: DiagnosticsUiState,
    onBack: () -> Unit,
    onShare: () -> Unit,
    onSelectLevel: (DiagnosticsLevelFilter) -> Unit,
    onSelectCategory: (String) -> Unit,
    onClearFilters: () -> Unit,
    onToggleExpanded: (Int) -> Unit,
    modifier: Modifier = Modifier,
    zone: ZoneId = ZoneId.systemDefault(),
) {
    val content = state.content
    // The design's `!busy && state !== 'empty'` (:456 / :457 / :469) — ONE predicate for the share
    // affordance, the filter bar and the footer. Loading covers the design's `busy` (it also covers
    // "not read yet", which must not claim an empty log); Empty covers a capture window that held
    // nothing. Filtered-empty is a FILTER state and keeps all three.
    val chromeVisible = content != DiagnosticsContent.Loading && content != DiagnosticsContent.Empty

    DiagnosticsNavShell(
        onBack = onBack,
        modifier = modifier.testTag(DiagnosticsScreenTags.CONTENT),
        trailing = if (chromeVisible) {
            { DiagnosticsShareButton(onShare = onShare) }
        } else {
            null
        },
    ) {
        if (chromeVisible) {
            DiagnosticsFilterBar(
                state = state,
                onSelectLevel = onSelectLevel,
                onSelectCategory = onSelectCategory,
            )
        }
        Box(
            Modifier
                .fillMaxWidth()
                .weight(1f),
        ) {
            when (content) {
                DiagnosticsContent.Loading -> DiagnosticsLoadingState()
                DiagnosticsContent.Empty ->
                    DiagnosticsEmptyState(filterDescriptor = null, onClearFilters = onClearFilters)
                // A filtered-empty state with no descriptor cannot be produced by
                // DiagnosticsUiState, but if one ever were, this degrades to the DESIGNED plain copy
                // rather than rendering "Nothing matches null …" (rule 51: no invented string).
                DiagnosticsContent.FilteredEmpty -> DiagnosticsEmptyState(
                    filterDescriptor = state.filterDescriptor,
                    onClearFilters = onClearFilters,
                )
                DiagnosticsContent.Entries -> DiagnosticsLogList(
                    state = state,
                    onToggleExpanded = onToggleExpanded,
                    zone = zone,
                )
            }
        }
        if (chromeVisible) {
            DiagnosticsFooter(scope = state.footerScope)
        }
    }
}

/** The day-grouped, virtualizing list (`DiagLogList`, `:303-315`). */
@Composable
private fun DiagnosticsLogList(
    state: DiagnosticsUiState,
    onToggleExpanded: (Int) -> Unit,
    zone: ZoneId,
) {
    val probe = LocalDiagnosticsRowProbe.current
    // The design drops the trailing hairline on the list's FINAL row (`last`), not on each day's.
    val lastRowId = state.sections.lastOrNull()?.entries?.lastOrNull()?.id

    LazyColumn(
        Modifier
            .fillMaxSize()
            .testTag(DiagnosticsScreenTags.LIST),
    ) {
        state.sections.forEach { section ->
            item(key = "header-${section.id}") {
                DiagnosticsDayHeader(section.header)
            }
            items(
                items = section.entries,
                key = { identified -> "row-${section.id}-${identified.id}" },
            ) { identified ->
                DisposableEffect(probe) {
                    probe?.onRowEnterComposition()
                    onDispose { probe?.onRowLeaveComposition() }
                }
                DiagnosticsLogRow(
                    entry = identified.entry,
                    expanded = state.expandedEntryId == identified.id,
                    onToggleExpanded = { onToggleExpanded(identified.id) },
                    isLast = identified.id == lastRowId,
                    zone = zone,
                )
            }
        }
    }
}
