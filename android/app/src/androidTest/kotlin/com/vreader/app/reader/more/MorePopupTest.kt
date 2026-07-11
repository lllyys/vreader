package com.vreader.app.reader.more

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.outlined.Timer
import androidx.compose.material.icons.outlined.Translate
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.LayoutDirection
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.reader.settings.ReaderTheme
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Feature #134 WI-3 — the reader More popover (`vreader-more.jsx` `MorePopover`) over the `MoreRow`
 * model. The popup renders ONLY the rows the caller supplies (the §more-row-ownership contract): an
 * action id with NO supplied row is ABSENT — no dead TTS/Auto-turn/Bilingual/Export rows. #134 owns
 * only DETAILS + SHARE. Action rows fire onTap, Toggle rows reflect `on` + call onToggle, Disabled rows
 * are non-interactive with a sub-text. Backdrop tap dismisses. Reuses the [ReaderTheme] token map.
 */
@RunWith(AndroidJUnit4::class)
class MorePopupTest {
    @get:Rule val compose = createComposeRule()

    private fun detailsRow(onTap: () -> Unit = {}) =
        MoreRow.Action(id = MoreActionId.DETAILS, label = "Book details", icon = Icons.Filled.Info, onTap = onTap)

    private fun shareRow(onTap: () -> Unit = {}) =
        MoreRow.Action(id = MoreActionId.SHARE, label = "Share book", icon = Icons.Filled.Share, onTap = onTap)

    @Test fun popupRendersWithTestTag() {
        compose.setContent {
            MorePopup(theme = ReaderTheme.Paper, rows = listOf(detailsRow(), shareRow()), onDismiss = {})
        }
        compose.onNodeWithTag("more-popup", useUnmergedTree = true).assertExists()
    }

    @Test fun detailsAndShareRowsRenderAndFireCallbacks() {
        var detailed = false
        var shared = false
        compose.setContent {
            MorePopup(
                theme = ReaderTheme.Paper,
                rows = listOf(detailsRow { detailed = true }, shareRow { shared = true }),
                onDismiss = {},
            )
        }
        compose.onNodeWithText("Book details", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("Share book", useUnmergedTree = true).assertExists()

        compose.onNodeWithTag("more-row-details", useUnmergedTree = true).performClick()
        assertTrue(detailed)
        assertFalse(shared)

        compose.onNodeWithTag("more-row-share", useUnmergedTree = true).performClick()
        assertTrue(shared)
    }

    @Test fun suppliedToggleRowReflectsOnAndFiresOnToggle() {
        var toggledTo: Boolean? = null
        compose.setContent {
            MorePopup(
                theme = ReaderTheme.Dark,
                rows = listOf(
                    MoreRow.Toggle(
                        id = MoreActionId.AUTO_TURN, label = "Auto-turn pages", icon = Icons.Outlined.Timer,
                        sub = "Every 30s", on = true, onToggle = { toggledTo = it },
                    ),
                ),
                onDismiss = {},
            )
        }
        compose.onNodeWithText("Auto-turn pages", useUnmergedTree = true).assertExists()
        // The switch reflects on=true.
        compose.onNodeWithTag("more-row-toggle-auto_turn", useUnmergedTree = true).assertIsOn()
        // Tapping the row toggles it.
        compose.onNodeWithTag("more-row-auto_turn", useUnmergedTree = true).performClick()
        assertTrue(toggledTo == false)
    }

    @Test fun suppliedToggleRowReflectsOffState() {
        compose.setContent {
            MorePopup(
                theme = ReaderTheme.Paper,
                rows = listOf(
                    MoreRow.Toggle(
                        id = MoreActionId.AUTO_TURN, label = "Auto-turn pages", icon = Icons.Outlined.Timer,
                        sub = "Off", on = false, onToggle = {},
                    ),
                ),
                onDismiss = {},
            )
        }
        compose.onNodeWithTag("more-row-toggle-auto_turn", useUnmergedTree = true).assertIsOff()
    }

    @Test fun disabledRowRendersNonInteractiveWithSubText() {
        var tapped = false
        compose.setContent {
            MorePopup(
                theme = ReaderTheme.Paper,
                rows = listOf(
                    MoreRow.Disabled(
                        id = MoreActionId.BILINGUAL, label = "Bilingual mode", icon = Icons.Outlined.Translate,
                        sub = "Configure AI provider first", onTap = { tapped = true },
                    ),
                ),
                onDismiss = {},
            )
        }
        compose.onNodeWithText("Bilingual mode", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("Configure AI provider first", useUnmergedTree = true).assertExists()
        // A disabled row is non-interactive: clicking it does nothing (no crash, callback not fired).
        compose.onNodeWithTag("more-row-bilingual", useUnmergedTree = true).performClick()
        assertFalse(tapped)
    }

    @Test fun unsuppliedIdsAreAbsent_noDeadTtsAutoTurnBilingual() {
        // Only DETAILS + SHARE supplied → TTS / Auto-turn / Bilingual rows are ABSENT (§more-row-ownership).
        compose.setContent {
            MorePopup(theme = ReaderTheme.Paper, rows = listOf(detailsRow(), shareRow()), onDismiss = {})
        }
        compose.onAllNodesWithTag("more-row-tts", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithTag("more-row-auto_turn", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithTag("more-row-bilingual", useUnmergedTree = true).assertCountEquals(0)
        compose.onNodeWithText("Read aloud", useUnmergedTree = true).assertDoesNotExist()
        compose.onNodeWithText("Auto-turn pages", useUnmergedTree = true).assertDoesNotExist()
        compose.onNodeWithText("Bilingual mode", useUnmergedTree = true).assertDoesNotExist()
    }

    @Test fun exportRowNeverPresent() {
        // #134 has no export subsystem — the Export row is never rendered, even by absence there is no
        // MoreActionId for it. Assert by label + that no export row is present.
        compose.setContent {
            MorePopup(theme = ReaderTheme.Paper, rows = listOf(detailsRow(), shareRow()), onDismiss = {})
        }
        compose.onNodeWithText("Export annotations", useUnmergedTree = true).assertDoesNotExist()
        compose.onAllNodesWithTag("more-row-export", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun backdropTapDismisses() {
        var dismissed = false
        compose.setContent {
            MorePopup(theme = ReaderTheme.Paper, rows = listOf(detailsRow()), onDismiss = { dismissed = true })
        }
        compose.onNodeWithTag("more-backdrop", useUnmergedTree = true).assertHasClickAction().performClick()
        assertTrue(dismissed)
    }

    @Test fun rendersUnderRtlLayout() {
        // The popup anchors to the trailing edge; under RTL it still renders (Compose flips automatically).
        compose.setContent {
            CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
                MorePopup(theme = ReaderTheme.Paper, rows = listOf(detailsRow(), shareRow()), onDismiss = {})
            }
        }
        compose.onNodeWithTag("more-popup", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("Book details", useUnmergedTree = true).assertExists()
    }

    @Test fun rendersAcrossThemes() {
        // The popup is a pure function of the theme tokens — it renders in every theme (light + dark).
        // AndroidComposeTestRule.setContent may be called only ONCE per test; drive the theme via
        // state across a single content tree instead of looping setContent (which throws
        // "has already set content").
        val theme = androidx.compose.runtime.mutableStateOf(ReaderTheme.values().first())
        compose.setContent {
            MorePopup(theme = theme.value, rows = listOf(detailsRow(), shareRow()), onDismiss = {})
        }
        for (t in ReaderTheme.values()) {
            theme.value = t
            compose.onNodeWithTag("more-popup", useUnmergedTree = true).assertExists()
        }
    }

    @Test fun emptyRowsRendersEmptyPopupWithoutCrash() {
        // Degenerate case: no supplied rows → the popup surface exists but has no rows (no crash).
        compose.setContent {
            MorePopup(theme = ReaderTheme.Paper, rows = emptyList(), onDismiss = {})
        }
        compose.onNodeWithTag("more-popup", useUnmergedTree = true).assertExists()
    }
}
