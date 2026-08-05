package com.vreader.app.diagnostics.ui

import androidx.activity.ComponentActivity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToIndex
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.diagnostics.DiagnosticsCategoryBounding
import com.vreader.app.diagnostics.DiagnosticsDaySection
import com.vreader.app.diagnostics.DiagnosticsLevel
import com.vreader.app.diagnostics.DiagnosticsLevelFilter
import com.vreader.app.diagnostics.DiagnosticsLogEntry
import com.vreader.app.diagnostics.DiagnosticsUiState
import com.vreader.app.diagnostics.IdentifiedDiagnosticsEntry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.time.Instant
import java.time.ZoneId
import java.util.concurrent.atomic.AtomicInteger

/**
 * Feature #164 WI-6b — the screen shell (`DiagNavSheet`, `vreader-diagnostics.jsx:137-183`), its
 * single dismissal path, and the list's virtualization.
 *
 * Two assertions here are deliberately stated as BEHAVIOUR rather than as structure:
 *
 * 1. **Back parity.** The design has no system-back concept, so "Android back does the same thing
 *    as the leading control" cannot be read off the bundle — it is the §6.5 adjudication, and two
 *    divergent dismissal paths would be a defect. The test drives both and asserts they land in the
 *    same action.
 * 2. **Virtualization.** Asserted with a COMPOSITION COUNTER ([CountingRowProbe]) that tracks how
 *    many rows are alive in the composition at once, never by the scroll merely completing (which
 *    an eager `Column` of 2000 rows also does) and never by naming the widget (which would make the
 *    test a restatement of the implementation).
 *
 * `setContent` is called at most ONCE per test method (#134 precedent).
 */
@RunWith(AndroidJUnit4::class)
class DiagnosticsScreenTest {

    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    private val zone: ZoneId = ZoneId.of("UTC")
    private val baseMillis = Instant.parse("2026-06-10T09:14:22Z").toEpochMilli()

    // ---------------------------------------------------------------- the shell (V1)

    @Test fun theNavShellRendersTheGrabberTheBackControlTheTitleAndTheTrailingAction() {
        compose.setContent { screen(entriesState()) }

        compose.onNodeWithTag(DiagnosticsNavTags.GRABBER, useUnmergedTree = true).assertExists()
        compose.onNodeWithTag(DiagnosticsNavTags.BACK).assertExists()
        compose.onNodeWithText(DiagnosticsNavStrings.BACK_LABEL, useUnmergedTree = true)
            .assertIsDisplayed()
        compose.onNodeWithTag(DiagnosticsNavTags.TITLE, useUnmergedTree = true).assertExists()
        compose.onNodeWithText(DiagnosticsNavStrings.TITLE, useUnmergedTree = true)
            .assertIsDisplayed()
        compose.onNodeWithTag(DiagnosticsNavTags.TRAILING, useUnmergedTree = true).assertExists()
        compose.onNodeWithTag(DiagnosticsShareTags.BUTTON).assertExists()
    }

    /** The design's layout: back leads, the title is centered in the bar, the action trails. */
    @Test fun theTitleIsCenteredBetweenTheLeadingBackControlAndTheTrailingAction() {
        compose.setContent { screen(entriesState()) }

        val bar = compose.onNodeWithTag(DiagnosticsNavTags.BAR, useUnmergedTree = true)
            .fetchSemanticsNode().boundsInRoot
        val back = compose.onNodeWithTag(DiagnosticsNavTags.BACK).fetchSemanticsNode().boundsInRoot
        val title = compose.onNodeWithTag(DiagnosticsNavTags.TITLE, useUnmergedTree = true)
            .fetchSemanticsNode().boundsInRoot
        val trailing = compose.onNodeWithTag(DiagnosticsNavTags.TRAILING, useUnmergedTree = true)
            .fetchSemanticsNode().boundsInRoot

        assertTrue("the back control is not leading", back.left < title.left)
        assertTrue("the trailing action is not trailing", trailing.left > title.right)
        val leftGap = title.left - bar.left
        val rightGap = bar.right - title.right
        assertTrue(
            "the title is not centered in the nav bar (left=$leftGap right=$rightGap)",
            kotlin.math.abs(leftGap - rightGap) <= 2f,
        )
    }

    // ---------------------------------------------------------------- one dismissal path (§6.5)

    @Test fun theLeadingBackControlInvokesTheDismissAction() {
        val dismissals = AtomicInteger(0)
        compose.setContent { screen(entriesState(), onBack = { dismissals.incrementAndGet() }) }

        compose.onNodeWithTag(DiagnosticsNavTags.BACK).performClick()
        compose.waitForIdle()

        assertEquals("the leading back control did not dismiss", 1, dismissals.get())
    }

    /**
     * Android system back must invoke the SAME action, not a second one. Both paths are driven in
     * one test so the assertion is about their equality, not about each in isolation.
     */
    @Test fun androidSystemBackInvokesTheSameDismissActionAsTheLeadingControl() {
        val dismissals = AtomicInteger(0)
        compose.setContent { screen(entriesState(), onBack = { dismissals.incrementAndGet() }) }

        compose.onNodeWithTag(DiagnosticsNavTags.BACK).performClick()
        compose.waitForIdle()
        val afterControl = dismissals.get()

        compose.runOnUiThread { compose.activity.onBackPressedDispatcher.onBackPressed() }
        compose.waitForIdle()
        val afterSystemBack = dismissals.get()

        assertEquals("the leading back control did not dismiss", 1, afterControl)
        assertEquals(
            "Android system back did not route to the same dismissal action",
            2,
            afterSystemBack,
        )
    }

    // ---------------------------------------------------------------- share + filters wiring

    @Test fun theShareActionReportsThroughTheScreensShareCallback() {
        val shares = AtomicInteger(0)
        compose.setContent { screen(entriesState(), onShare = { shares.incrementAndGet() }) }

        compose.onNodeWithTag(DiagnosticsShareTags.BUTTON).performClick()
        compose.waitForIdle()

        assertEquals(1, shares.get())
    }

    @Test fun tappingALevelChipReportsThroughTheScreensLevelCallback() {
        val selected = mutableListOf<DiagnosticsLevelFilter>()
        compose.setContent { screen(entriesState(), onSelectLevel = { selected.add(it) }) }

        compose.onNodeWithTag(DiagnosticsFilterTags.levelChip(DiagnosticsLevelFilter.ERRORS))
            .performClick()
        compose.waitForIdle()

        assertEquals(listOf(DiagnosticsLevelFilter.ERRORS), selected)
    }

    @Test fun tappingACategoryChipReportsThroughTheScreensCategoryCallback() {
        val selected = mutableListOf<String>()
        compose.setContent { screen(entriesState(), onSelectCategory = { selected.add(it) }) }

        compose.onNodeWithTag(DiagnosticsFilterTags.categoryChip("Persistence")).performClick()
        compose.waitForIdle()

        assertEquals(listOf("Persistence"), selected)
    }

    @Test fun tappingARowReportsItsPositionalIdentityThroughTheToggleCallback() {
        val toggled = mutableListOf<Int>()
        compose.setContent { screen(entriesState(), onToggleExpanded = { toggled.add(it) }) }

        compose.onNodeWithText("library scanned 42 books", useUnmergedTree = true).performClick()
        compose.waitForIdle()

        assertEquals(listOf(1), toggled)
    }

    // ---------------------------------------------------------------- virtualization

    /**
     * The last of 2000 entries is reachable AND the list keeps only a bounded number of rows in the
     * composition. [CountingRowProbe] measures rows alive CONCURRENTLY (enter/leave composition),
     * which is the property virtualization actually has — a cumulative count would legitimately
     * approach 2000 after scrolling the whole list, and a snapshot of the semantics tree alone
     * cannot see a row that composed and was disposed between two idle points.
     *
     * The probe's own liveness is asserted first: a probe that was never invoked would satisfy
     * "peak <= bound" vacuously.
     */
    @Test fun scrollingToTheLastOfTwoThousandEntriesComposesOnlyABoundedNumberOfRows() {
        val probe = CountingRowProbe()
        val state = bigState(ENTRY_COUNT)
        compose.setContent {
            CompositionLocalProvider(LocalDiagnosticsRowProbe provides probe) { screen(state) }
        }
        compose.waitForIdle()

        assertTrue("the composition probe was never invoked", probe.peakAlive > 0)
        assertTrue(
            "every one of $ENTRY_COUNT rows was composed at once (peak=${probe.peakAlive}) — " +
                "the list is not virtualizing",
            probe.peakAlive <= MAX_CONCURRENT_ROWS,
        )

        // 1 day header + ENTRY_COUNT rows; the last row is the final lazy item.
        compose.onNodeWithTag(DiagnosticsScreenTags.LIST).performScrollToIndex(ENTRY_COUNT)
        compose.waitForIdle()

        compose.onNodeWithText("entry #${ENTRY_COUNT - 1}", useUnmergedTree = true)
            .assertIsDisplayed()
        assertTrue(
            "scrolling to the end composed $ENTRY_COUNT rows at once (peak=${probe.peakAlive})",
            probe.peakAlive <= MAX_CONCURRENT_ROWS,
        )
        // Cross-check through a second, independent lens: the semantics tree holds only the rows
        // that are currently composed.
        val liveRows = compose.onAllNodesWithTag(DiagnosticsRowTags.ROW).fetchSemanticsNodes().size
        assertTrue(
            "the semantics tree holds $liveRows rows of $ENTRY_COUNT",
            liveRows in 1..MAX_CONCURRENT_ROWS,
        )
    }

    // ---------------------------------------------------------------- helpers

    @Composable
    private fun screen(
        state: DiagnosticsUiState,
        onBack: () -> Unit = {},
        onShare: () -> Unit = {},
        onSelectLevel: (DiagnosticsLevelFilter) -> Unit = {},
        onSelectCategory: (String) -> Unit = {},
        onToggleExpanded: (Int) -> Unit = {},
    ) {
        DiagnosticsScreenContent(
            state = state,
            onBack = onBack,
            onShare = onShare,
            onSelectLevel = onSelectLevel,
            onSelectCategory = onSelectCategory,
            onClearFilters = {},
            onToggleExpanded = onToggleExpanded,
            zone = zone,
        )
    }

    private fun entriesState(): DiagnosticsUiState = DiagnosticsUiState(
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
                entries = listOf(
                    row(0, DiagnosticsLevel.ERROR, "Persistence", "save failed: disk full"),
                    row(1, DiagnosticsLevel.INFO, "Library", "library scanned 42 books"),
                    row(2, DiagnosticsLevel.DEBUG, "Reader", "locator restored"),
                ),
            ),
        ),
    )

    private fun bigState(count: Int): DiagnosticsUiState = DiagnosticsUiState(
        hasLoaded = true,
        levelCounts = DiagnosticsLevelFilter.entries.associateWith { count },
        categoryChips = listOf(DiagnosticsCategoryBounding.ALL, "Library"),
        totalCount = count,
        visibleCount = count,
        sections = listOf(
            DiagnosticsDaySection(
                id = "2026-06-10",
                relativeWord = "Today",
                dateLabel = "10 June",
                entries = (0 until count).map { i ->
                    row(i, DiagnosticsLevel.INFO, "Library", "entry #$i")
                },
            ),
        ),
    )

    private fun row(
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

    /**
     * Counts rows that are alive in the composition CONCURRENTLY, and remembers the peak. Enter and
     * leave are called from the composition (main) thread; the assertions read from the test
     * thread, hence the atomics.
     */
    private class CountingRowProbe : DiagnosticsRowProbe {
        private val alive = AtomicInteger(0)
        private val peak = AtomicInteger(0)

        override fun onRowEnterComposition() {
            val now = alive.incrementAndGet()
            peak.updateAndGet { previous -> if (now > previous) now else previous }
        }

        override fun onRowLeaveComposition() {
            alive.decrementAndGet()
        }

        val peakAlive: Int get() = peak.get()
    }

    private companion object {
        const val ENTRY_COUNT = 2000

        /**
         * A generous ceiling: a full-screen list of ~50dp rows shows roughly 16, plus the lazy
         * layout's prefetch. It is two orders of magnitude below [ENTRY_COUNT], so an eager list
         * fails unambiguously while ordinary prefetch variation never flakes.
         */
        const val MAX_CONCURRENT_ROWS = 60
    }
}
