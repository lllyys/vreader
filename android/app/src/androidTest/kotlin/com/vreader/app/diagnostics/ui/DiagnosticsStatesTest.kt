package com.vreader.app.diagnostics.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.diagnostics.DiagnosticsCategoryBounding
import com.vreader.app.diagnostics.DiagnosticsDaySection
import com.vreader.app.diagnostics.DiagnosticsLevel
import com.vreader.app.diagnostics.DiagnosticsLevelFilter
import com.vreader.app.diagnostics.DiagnosticsLogEntry
import com.vreader.app.diagnostics.DiagnosticsLogStore
import com.vreader.app.diagnostics.DiagnosticsUiState
import com.vreader.app.diagnostics.IdentifiedDiagnosticsEntry
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.time.Instant
import java.time.ZoneId

/**
 * Feature #164 WI-6b — the viewer's four content states as `DiagLogViewer` draws them
 * (`vreader-diagnostics.jsx:441-491`; artboards V1/V2, S1, S2/S3, F3).
 *
 * The load-bearing assertions are the CHROME ones. `DiagLogViewer` gates the share affordance
 * (`:456`), the filter bar (`:457`) AND the footer (`:469`) behind the SAME
 * `!busy && state !== 'empty'` predicate. Plan v1/v2 recorded only the first two, which would have
 * rendered `"0 entries · recent activity · ● Capturing"` on a fresh-install screen no artboard
 * depicts — so "the footer is hidden in empty" is asserted as its own criterion here, never folded
 * into a general "the empty state renders" check.
 *
 * `setContent` is called at most ONCE per test method (#134 precedent: looping states inside one
 * test throws `IllegalStateException`, and only the connected run catches it).
 */
@RunWith(AndroidJUnit4::class)
class DiagnosticsStatesTest {

    @get:Rule val compose = createComposeRule()

    private val zone: ZoneId = ZoneId.of("UTC")
    private val baseMillis = Instant.parse("2026-06-10T09:14:22Z").toEpochMilli()

    // ---------------------------------------------------------------- default (V1/V2)

    @Test fun theDefaultStateRendersTheFilterBarTheDayGroupedListAndTheFooter() {
        content(entriesState())

        compose.onNodeWithTag(DiagnosticsFilterTags.FILTER_BAR).assertExists()
        compose.onNodeWithTag(DiagnosticsRowTags.DAY_HEADER, useUnmergedTree = true).assertExists()
        compose.onNodeWithText("TODAY · 10 JUNE", useUnmergedTree = true).assertIsDisplayed()
        compose.onNodeWithText("library scanned 42 books", useUnmergedTree = true).assertIsDisplayed()
        compose.onNodeWithTag(DiagnosticsFooterTags.FOOTER).assertExists()
        compose.onNodeWithText("3 entries · recent activity", useUnmergedTree = true).assertIsDisplayed()
        // The share affordance is present whenever there is something to export.
        compose.onNodeWithTag(DiagnosticsShareTags.BUTTON).assertExists()
    }

    // ---------------------------------------------------------------- loading (S1)

    @Test fun theLoadingStateRendersTheSpinnerAndThePlatformTrueSourceLine() {
        content(DiagnosticsUiState(isLoading = true))

        compose.onNodeWithTag(DiagnosticsStateTags.LOADING).assertExists()
        compose.onNodeWithTag(DiagnosticsStateTags.SPINNER, useUnmergedTree = true).assertExists()
        compose.onNodeWithText(DiagnosticsStateStrings.LOADING_TITLE, useUnmergedTree = true)
            .assertIsDisplayed()
        // Plan section 6.6: the design's iOS "OSLogStore · com.vreader.app" becomes the Android
        // truth in the same slot.
        compose.onNodeWithText(DiagnosticsStateStrings.LOADING_SOURCE, useUnmergedTree = true)
            .assertIsDisplayed()
        compose.onNodeWithText("OSLogStore · com.vreader.app", useUnmergedTree = true)
            .assertDoesNotExist()
    }

    @Test fun theLoadingStateHidesTheFilterBarTheShareAffordanceAndTheFooter() {
        content(DiagnosticsUiState(isLoading = true))

        compose.onNodeWithTag(DiagnosticsFilterTags.FILTER_BAR).assertDoesNotExist()
        compose.onNodeWithTag(DiagnosticsShareTags.BUTTON).assertDoesNotExist()
        compose.onNodeWithTag(DiagnosticsFooterTags.FOOTER).assertDoesNotExist()
    }

    /** Before the first load completes the viewer knows nothing — it must not claim an empty log. */
    @Test fun theNotYetLoadedStateRendersLoadingRatherThanTheEmptyClaim() {
        content(DiagnosticsUiState(isLoading = false, hasLoaded = false))

        compose.onNodeWithTag(DiagnosticsStateTags.LOADING).assertExists()
        compose.onNodeWithText(DiagnosticsStateStrings.EMPTY_TITLE, useUnmergedTree = true)
            .assertDoesNotExist()
    }

    // ---------------------------------------------------------------- empty (S2/S3)

    @Test fun theEmptyStateRendersThePulseTileAndTheDesignedCopyVerbatim() {
        content(DiagnosticsUiState(hasLoaded = true))

        compose.onNodeWithTag(DiagnosticsStateTags.EMPTY).assertExists()
        compose.onNodeWithTag(DiagnosticsStateTags.EMPTY_TILE, useUnmergedTree = true).assertExists()
        compose.onNodeWithText(DiagnosticsStateStrings.EMPTY_TITLE, useUnmergedTree = true)
            .assertIsDisplayed()
        // GH #2022 tracks the capture-unavailable variant; WI-6b ships the designed copy verbatim
        // and invents nothing (rule 51).
        compose.onNodeWithText(DiagnosticsStateStrings.EMPTY_BODY, useUnmergedTree = true)
            .assertIsDisplayed()
        compose.onNodeWithTag(DiagnosticsStateTags.CLEAR_FILTERS).assertDoesNotExist()
    }

    /**
     * The criterion plan v1/v2 missed. `:469` gates the footer on the same predicate as `:456`/`:457`,
     * so a fresh install must not read "0 entries · recent activity · ● Capturing".
     */
    @Test fun theEmptyStateHidesTheFilterBarTheShareAffordanceAndTheFooter() {
        content(DiagnosticsUiState(hasLoaded = true))

        compose.onNodeWithTag(DiagnosticsFilterTags.FILTER_BAR).assertDoesNotExist()
        compose.onNodeWithTag(DiagnosticsShareTags.BUTTON).assertDoesNotExist()
        compose.onNodeWithTag(DiagnosticsFooterTags.FOOTER).assertDoesNotExist()
        compose.onNodeWithText("0 entries · recent activity", useUnmergedTree = true)
            .assertDoesNotExist()
        compose.onNodeWithText("Capturing", useUnmergedTree = true).assertDoesNotExist()
    }

    @Test fun theEmptyStateRendersInTheDarkTokenSet() {
        compose.setContent {
            CompositionLocalProvider(LocalDiagnosticsTokens provides DiagnosticsTokens.Dark) {
                screen(DiagnosticsUiState(hasLoaded = true))
            }
        }

        compose.onNodeWithText(DiagnosticsStateStrings.EMPTY_TITLE, useUnmergedTree = true)
            .assertIsDisplayed()
        compose.onNodeWithTag(DiagnosticsFooterTags.FOOTER).assertDoesNotExist()
    }

    // ---------------------------------------------------------------- filtered-empty (F3)

    @Test fun theFilteredEmptyStateRendersTheFilterTileTheTitleAndClearFilters() {
        content(filteredEmptyState())

        compose.onNodeWithTag(DiagnosticsStateTags.EMPTY).assertExists()
        compose.onNodeWithText(DiagnosticsStateStrings.FILTERED_TITLE, useUnmergedTree = true)
            .assertIsDisplayed()
        compose.onNodeWithText(DiagnosticsStateStrings.CLEAR_FILTERS, useUnmergedTree = true)
            .assertIsDisplayed()
    }

    /** F3 is a FILTER state, not an empty log: the chips and the scope line stay on screen. */
    @Test fun theFilteredEmptyStateKeepsTheFilterBarTheShareAffordanceAndTheFooter() {
        content(filteredEmptyState())

        compose.onNodeWithTag(DiagnosticsFilterTags.FILTER_BAR).assertExists()
        compose.onNodeWithTag(DiagnosticsShareTags.BUTTON).assertExists()
        compose.onNodeWithTag(DiagnosticsFooterTags.FOOTER).assertExists()
        compose.onNodeWithText("0 of 487 entries", useUnmergedTree = true).assertIsDisplayed()
    }

    /**
     * The body copy single-sources [DiagnosticsLogStore.CAPTURE_SCOPE_LABEL] — the same word the
     * footer and the export header use. The design hardcodes "in the last 24 hours" (`:372`), which
     * names a window this plan deliberately replaced; a third hand-typed string is what the
     * single-sourcing exists to prevent.
     */
    @Test fun theFilteredEmptyBodyCopySingleSourcesTheCaptureScopeLabel() {
        content(filteredEmptyState())

        compose.onNodeWithText("Nothing matches DebugBridge errors in recent activity.", useUnmergedTree = true)
            .assertIsDisplayed()
        compose.onNodeWithText(
            DiagnosticsStateStrings.filteredBody("DebugBridge errors"),
            useUnmergedTree = true,
        ).assertIsDisplayed()
        compose.onNodeWithText("Nothing matches DebugBridge errors in the last 24 hours.", useUnmergedTree = true)
            .assertDoesNotExist()
    }

    /** A level-only filter reads "errors"; a category-only one reads the category (F1/F2). */
    @Test fun theFilteredEmptyBodyNamesALevelOnlyFilterWithTheLevelWord() {
        content(
            filteredEmptyState(
                level = DiagnosticsLevelFilter.ERRORS,
                category = DiagnosticsCategoryBounding.ALL,
            ),
        )

        compose.onNodeWithText("Nothing matches errors in recent activity.", useUnmergedTree = true)
            .assertIsDisplayed()
    }

    /**
     * Edge case: a filtered-empty state whose descriptor is absent must fall back to the DESIGNED
     * plain-empty copy rather than render "Nothing matches null …". No invented string exists for
     * that combination, so the only rule-51-legal degradation is another designed state.
     */
    @Test fun aFilteredEmptyStateWithNoDescriptorFallsBackToTheDesignedPlainCopy() {
        compose.setContent {
            DiagnosticsEmptyState(filterDescriptor = null, onClearFilters = {})
        }

        compose.onNodeWithText(DiagnosticsStateStrings.EMPTY_TITLE, useUnmergedTree = true)
            .assertIsDisplayed()
        compose.onNodeWithText("null", substring = true, useUnmergedTree = true).assertDoesNotExist()
        compose.onNodeWithTag(DiagnosticsStateTags.CLEAR_FILTERS).assertDoesNotExist()
    }

    /**
     * The designed pill is ~30dp tall — under Android's 48dp interactive minimum — so the clickable
     * box around it is grown. Asserted because every other test clicks the node's center, which
     * succeeds at any size and would never notice the target shrinking back.
     */
    @Test fun theClearFiltersControlMeetsTheMinimumInteractiveSize() {
        content(filteredEmptyState())

        val minPx = with(compose.density) { 48.dp.toPx() }
        val target = compose.onNodeWithTag(DiagnosticsStateTags.CLEAR_FILTERS).fetchSemanticsNode()

        assertTrue(
            "the Clear filters target is ${target.size.height}px tall, under $minPx px",
            target.size.height >= minPx - 1f,
        )
    }

    /**
     * "Clear filters" is a WORKING control, not a decoration: tapping it restores the unfiltered
     * list. One `setContent`; the state flips inside the composition.
     */
    @Test fun clearFiltersRestoresTheUnfilteredList() {
        compose.setContent {
            var filtered by remember { mutableStateOf(true) }
            screen(
                state = if (filtered) filteredEmptyState() else entriesState(),
                onClearFilters = { filtered = false },
            )
        }

        compose.onNodeWithText(DiagnosticsStateStrings.FILTERED_TITLE, useUnmergedTree = true)
            .assertIsDisplayed()
        compose.onNodeWithTag(DiagnosticsStateTags.CLEAR_FILTERS).performClick()

        compose.onNodeWithText(DiagnosticsStateStrings.FILTERED_TITLE, useUnmergedTree = true)
            .assertDoesNotExist()
        compose.onNodeWithText("library scanned 42 books", useUnmergedTree = true).assertIsDisplayed()
        compose.onNodeWithText("3 entries · recent activity", useUnmergedTree = true).assertIsDisplayed()
    }

    // ---------------------------------------------------------------- helpers

    private fun content(state: DiagnosticsUiState) {
        compose.setContent { screen(state) }
    }

    @Composable
    private fun screen(
        state: DiagnosticsUiState,
        onClearFilters: () -> Unit = {},
    ) {
        DiagnosticsScreenContent(
            state = state,
            onBack = {},
            onShare = {},
            onSelectLevel = {},
            onSelectCategory = {},
            onClearFilters = onClearFilters,
            onToggleExpanded = {},
            zone = zone,
        )
    }

    private fun entriesState(): DiagnosticsUiState {
        val entries = listOf(
            entry(0, DiagnosticsLevel.ERROR, "Persistence", "save failed: disk full"),
            entry(1, DiagnosticsLevel.INFO, "Library", "library scanned 42 books"),
            entry(2, DiagnosticsLevel.DEBUG, "Reader", "locator restored"),
        )
        return DiagnosticsUiState(
            hasLoaded = true,
            levelCounts = DiagnosticsLevelFilter.entries.associateWith { 1 },
            categoryChips = listOf(DiagnosticsCategoryBounding.ALL, "Library", "Persistence"),
            totalCount = 3,
            visibleCount = 3,
            sections = listOf(
                DiagnosticsDaySection(
                    id = "2026-06-10",
                    relativeWord = "Today",
                    dateLabel = "10 June",
                    entries = entries,
                ),
            ),
        )
    }

    private fun filteredEmptyState(
        level: DiagnosticsLevelFilter = DiagnosticsLevelFilter.ERRORS,
        category: String = "DebugBridge",
    ) = DiagnosticsUiState(
        hasLoaded = true,
        levelFilter = level,
        categoryFilter = category,
        levelCounts = DiagnosticsLevelFilter.entries.associateWith { 12 },
        categoryChips = listOf(DiagnosticsCategoryBounding.ALL, "DebugBridge"),
        totalCount = 487,
        visibleCount = 0,
        sections = emptyList(),
    )

    private fun entry(
        index: Int,
        level: DiagnosticsLevel,
        category: String,
        message: String,
    ) = IdentifiedDiagnosticsEntry(
        id = index,
        entry = DiagnosticsLogEntry(
            timeMillis = baseMillis - index * 1_000L,
            level = level,
            category = category,
            message = message,
        ),
    )
}
