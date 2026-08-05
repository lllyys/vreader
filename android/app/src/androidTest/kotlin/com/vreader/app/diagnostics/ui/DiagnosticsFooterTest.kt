package com.vreader.app.diagnostics.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.diagnostics.DiagnosticsCategoryBounding
import com.vreader.app.diagnostics.DiagnosticsLevelFilter
import com.vreader.app.diagnostics.DiagnosticsUiState
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Feature #164 WI-6a — the pinned status footer (`DiagFooter`, `vreader-diagnostics.jsx:319-334`).
 *
 * The footer is a STATEMENT, not a control: the design's note is that capture is always on in
 * Release, so there is no toggle and no "paused" form. Its left half is whatever grammar
 * [DiagnosticsUiState.footerScope] produced — the footer never re-derives a scope sentence of its own,
 * which is what keeps the viewer, the export header and the filtered-empty copy in agreement.
 */
@RunWith(AndroidJUnit4::class)
class DiagnosticsFooterTest {

    @get:Rule val compose = createComposeRule()

    private fun state(
        level: DiagnosticsLevelFilter = DiagnosticsLevelFilter.ALL,
        category: String = DiagnosticsCategoryBounding.ALL,
        total: Int = 487,
        visible: Int = 487,
    ) = DiagnosticsUiState(
        hasLoaded = true,
        levelFilter = level,
        categoryFilter = category,
        totalCount = total,
        visibleCount = visible,
    )

    @Test fun theFooterRendersTheScopeLineAndTheCapturingStatus() {
        compose.setContent { DiagnosticsFooter(scope = state().footerScope) }

        compose.onNodeWithTag(DiagnosticsFooterTags.FOOTER).assertExists()
        compose.onNodeWithText("487 entries · recent activity", useUnmergedTree = true)
            .assertIsDisplayed()
        compose.onNodeWithText("Capturing", useUnmergedTree = true).assertIsDisplayed()
        compose.onNodeWithTag(DiagnosticsFooterTags.DOT, useUnmergedTree = true).assertExists()
    }

    @Test fun theCapturingDotUsesTheDesignsGreen() {
        compose.setContent { DiagnosticsFooter(scope = state().footerScope) }

        compose.onNodeWithTag(DiagnosticsFooterTags.DOT, useUnmergedTree = true)
            .assert(SemanticsMatcher.expectValue(DiagnosticsColorKey, 0xFF4A9A6A.toInt()))
    }

    @Test fun theFooterRendersEachOfTheThreeDesignedScopeGrammars() {
        val unfiltered = state()
        val filtered = state(level = DiagnosticsLevelFilter.ERRORS, visible = 12)
        val filteredEmpty = state(
            level = DiagnosticsLevelFilter.ERRORS,
            category = "DebugBridge",
            visible = 0,
        )

        compose.setContent {
            Column {
                DiagnosticsFooter(scope = unfiltered.footerScope)
                DiagnosticsFooter(scope = filtered.footerScope)
                DiagnosticsFooter(scope = filteredEmpty.footerScope)
            }
        }

        compose.onNodeWithText("487 entries · recent activity", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("Showing 12 of 487 · errors", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("0 of 487 entries", useUnmergedTree = true).assertExists()
    }

    @Test fun theFooterRendersInTheDarkTokenSet() {
        compose.setContent {
            CompositionLocalProvider(LocalDiagnosticsTokens provides DiagnosticsTokens.Dark) {
                DiagnosticsFooter(scope = state(total = 1, visible = 1).footerScope)
            }
        }

        // The one-entry singular grammar, rendered under the dark tokens.
        compose.onNodeWithText("1 entry · recent activity", useUnmergedTree = true).assertIsDisplayed()
        compose.onNodeWithTag(DiagnosticsFooterTags.DOT, useUnmergedTree = true)
            .assert(SemanticsMatcher.expectValue(DiagnosticsColorKey, 0xFF4A9A6A.toInt()))
    }

    @Test fun aVeryLongScopeLineDoesNotDisplaceTheCapturingStatus() {
        val long = "Showing 12345 of 987654 · " + "VeryLongCategoryName".repeat(6) + " errors"
        compose.setContent { DiagnosticsFooter(scope = long) }

        compose.onNodeWithText("Capturing", useUnmergedTree = true).assertIsDisplayed()
        val footer = compose.onNodeWithTag(DiagnosticsFooterTags.FOOTER).fetchSemanticsNode()
        val capturing = compose.onNodeWithTag(DiagnosticsFooterTags.CAPTURING, useUnmergedTree = true)
            .fetchSemanticsNode()
        assertTrue(
            "the Capturing status was pushed outside the footer",
            capturing.boundsInRoot.right <= footer.boundsInRoot.right + 1f,
        )
    }
}
