package com.vreader.app.diagnostics.ui

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.diagnostics.DiagnosticsCategoryBounding
import com.vreader.app.diagnostics.DiagnosticsLevelFilter
import com.vreader.app.diagnostics.DiagnosticsUiState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Feature #164 WI-6a — the designed filter bar (`DiagFilterBar` / `DiagChip`,
 * `vreader-diagnostics.jsx:205-243`, artboards F1/F2/F4).
 *
 * Three chip forms are asserted by their FILL, not by eye: the active `Errors` chip takes the error
 * tint, any other active chip takes the inverted-ink pill, and an inactive chip is outlined
 * (transparent fill + rule border). Per theme in separate methods — `setContent` is once-per-method.
 */
@RunWith(AndroidJUnit4::class)
class DiagnosticsFilterBarTest {

    @get:Rule val compose = createComposeRule()

    private fun state(
        level: DiagnosticsLevelFilter = DiagnosticsLevelFilter.ALL,
        category: String = DiagnosticsCategoryBounding.ALL,
        counts: Map<DiagnosticsLevelFilter, Int> = mapOf(
            DiagnosticsLevelFilter.ALL to 487,
            DiagnosticsLevelFilter.ERRORS to 12,
            DiagnosticsLevelFilter.DEBUG to 203,
            DiagnosticsLevelFilter.INFO to 272,
        ),
        chips: List<String> = listOf(
            DiagnosticsCategoryBounding.ALL,
            "Library", "Persistence", "Reader", "AI", "Sync", "DebugBridge", "Other",
        ),
    ) = DiagnosticsUiState(
        hasLoaded = true,
        levelFilter = level,
        categoryFilter = category,
        levelCounts = counts,
        categoryChips = chips,
        totalCount = 487,
        visibleCount = 487,
    )

    private fun showBar(
        state: DiagnosticsUiState,
        tokens: DiagnosticsTokens = DiagnosticsTokens.Light,
        onSelectLevel: (DiagnosticsLevelFilter) -> Unit = {},
        onSelectCategory: (String) -> Unit = {},
    ) {
        compose.setContent {
            CompositionLocalProvider(LocalDiagnosticsTokens provides tokens) {
                DiagnosticsFilterBar(
                    state = state,
                    onSelectLevel = onSelectLevel,
                    onSelectCategory = onSelectCategory,
                )
            }
        }
    }

    private fun assertChipFill(tag: String, expected: Int) {
        compose.onNodeWithTag(tag, useUnmergedTree = true)
            .assert(SemanticsMatcher.expectValue(DiagnosticsColorKey, expected))
    }

    // ───────────────────────────────────────────────────────── chips + counts

    @Test fun levelChipsRenderInTheDesignedOrderWithTheirCounts() {
        showBar(state())

        // "All" is BOTH the level chip and the leading category chip — the design's two rows each
        // carry their own; matching by text alone would be ambiguous, so the level row is addressed
        // by tag and the duplicate is asserted explicitly.
        DiagnosticsLevelFilter.entries.forEach { filter ->
            compose.onNodeWithTag(DiagnosticsFilterTags.levelChip(filter), useUnmergedTree = true)
                .assertExists()
        }
        compose.onAllNodesWithText("All", useUnmergedTree = true).assertCountEquals(2)
        compose.onNodeWithText("Errors", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("Debug", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("Info", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("487", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("12", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("203", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("272", useUnmergedTree = true).assertExists()

        // Designed order — left to right, All first.
        val xs = DiagnosticsLevelFilter.entries.map { filter ->
            compose.onNodeWithTag(DiagnosticsFilterTags.levelChip(filter), useUnmergedTree = true)
                .fetchSemanticsNode().positionInRoot.x
        }
        assertEquals(xs.sorted(), xs)
    }

    @Test fun aZeroCountChipStillShowsItsBadge() {
        showBar(state(counts = DiagnosticsLevelFilter.entries.associateWith { 0 }))

        compose.onAllNodesWithText("0", useUnmergedTree = true).assertCountEquals(4)
    }

    // ───────────────────────────────────────────────────────── the three chip forms

    @Test fun theActiveErrorsChipTakesTheErrorTintInLight() {
        showBar(state(level = DiagnosticsLevelFilter.ERRORS), DiagnosticsTokens.Light)
        assertChipFill(
            DiagnosticsFilterTags.levelChip(DiagnosticsLevelFilter.ERRORS),
            0xFFB13E36.toInt(),
        )
    }

    @Test fun theActiveErrorsChipTakesTheErrorTintInDark() {
        showBar(state(level = DiagnosticsLevelFilter.ERRORS), DiagnosticsTokens.Dark)
        assertChipFill(
            DiagnosticsFilterTags.levelChip(DiagnosticsLevelFilter.ERRORS),
            0xFFE0826F.toInt(),
        )
    }

    @Test fun anotherActiveChipTakesTheInvertedInkPillInLight() {
        showBar(state(level = DiagnosticsLevelFilter.DEBUG), DiagnosticsTokens.Light)
        assertChipFill(
            DiagnosticsFilterTags.levelChip(DiagnosticsLevelFilter.DEBUG),
            DiagnosticsTokens.Light.ink.toArgb(),
        )
    }

    @Test fun anotherActiveChipTakesTheInvertedInkPillInDark() {
        showBar(state(level = DiagnosticsLevelFilter.INFO), DiagnosticsTokens.Dark)
        assertChipFill(
            DiagnosticsFilterTags.levelChip(DiagnosticsLevelFilter.INFO),
            DiagnosticsTokens.Dark.ink.toArgb(),
        )
    }

    @Test fun inactiveChipsTakeTheOutlinedForm() {
        showBar(state(level = DiagnosticsLevelFilter.ALL))

        assertChipFill(
            DiagnosticsFilterTags.levelChip(DiagnosticsLevelFilter.ERRORS),
            Color.Transparent.toArgb(),
        )
        assertChipFill(
            DiagnosticsFilterTags.levelChip(DiagnosticsLevelFilter.DEBUG),
            Color.Transparent.toArgb(),
        )
        // …and the ACTIVE `All` chip is the inverted-ink pill, not the error tint.
        assertChipFill(
            DiagnosticsFilterTags.levelChip(DiagnosticsLevelFilter.ALL),
            DiagnosticsTokens.Light.ink.toArgb(),
        )
    }

    @Test fun theActiveCategoryChipTakesTheInvertedInkPill() {
        showBar(state(category = "Reader"))

        assertChipFill(
            DiagnosticsFilterTags.categoryChip("Reader"),
            DiagnosticsTokens.Light.ink.toArgb(),
        )
        assertChipFill(DiagnosticsFilterTags.categoryChip("Sync"), Color.Transparent.toArgb())
    }

    // ───────────────────────────────────────────────────────── selection callbacks

    @Test fun tappingALevelChipReportsThatFilter() {
        var picked: DiagnosticsLevelFilter? = null
        showBar(state(), onSelectLevel = { picked = it })

        compose.onNodeWithTag(
            DiagnosticsFilterTags.levelChip(DiagnosticsLevelFilter.ERRORS),
            useUnmergedTree = true,
        ).performClick()

        assertEquals(DiagnosticsLevelFilter.ERRORS, picked)
    }

    @Test fun tappingACategoryChipReportsThatCategory() {
        var picked: String? = null
        showBar(state(), onSelectCategory = { picked = it })

        compose.onNodeWithTag(DiagnosticsFilterTags.categoryChip("Persistence"), useUnmergedTree = true)
            .performScrollTo()
            .performClick()

        assertEquals("Persistence", picked)
    }

    // ───────────────────────────────────────────────────────── horizontal scroll, no wrap

    @Test fun theCategoryRowScrollsHorizontallyAndDoesNotWrap() {
        val chips = listOf(DiagnosticsCategoryBounding.ALL) +
            listOf("Library", "Persistence", "Reader", "AI", "Sync", "DebugBridge", "阅读器")
        showBar(state(chips = chips))

        // Every chip shares one baseline row — a wrapping row would push later chips down.
        val tops = chips.map {
            compose.onNodeWithTag(DiagnosticsFilterTags.categoryChip(it), useUnmergedTree = true)
                .fetchSemanticsNode().positionInRoot.y
        }
        assertEquals("category chips wrapped onto more than one line", 1, tops.distinct().size)

        // The row is wider than the viewport, and the far chip is reachable by scrolling.
        val rootWidth = compose.onNodeWithTag(DiagnosticsFilterTags.CATEGORY_ROW)
            .fetchSemanticsNode().size.width
        val lastX = compose.onNodeWithTag(
            DiagnosticsFilterTags.categoryChip(chips.last()),
            useUnmergedTree = true,
        ).fetchSemanticsNode().positionInRoot.x
        assertTrue("the category row is not overflowing; nothing to scroll", lastX > rootWidth)

        compose.onNodeWithTag(DiagnosticsFilterTags.categoryChip(chips.last()), useUnmergedTree = true)
            .performScrollTo()
            .assertExists()
        compose.onNodeWithText("阅读器", useUnmergedTree = true).assertExists()
    }
}
