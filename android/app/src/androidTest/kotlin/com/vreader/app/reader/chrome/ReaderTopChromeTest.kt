package com.vreader.app.reader.chrome

import androidx.compose.material3.Text
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertWidthIsAtLeast
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.reader.settings.ReaderTheme
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Feature #132 WI-2 — the `ReaderTopChrome` shell (vreader-reader.jsx `ReaderTopChrome`): a leading
 * "‹ Library" back control, a centered italic-serif title (maxLines=1, ellipsized), and a trailing
 * cluster (Search / bookmark slot / More). Per the #129 dead-control rule the Search / More / bookmark
 * slots render NOTHING when their callback/slot is null (NOT shown-disabled) — Search/More land with
 * #133/#134, the bookmark slot is filled by #135, all via the already-present nullable params.
 */
@RunWith(AndroidJUnit4::class)
class ReaderTopChromeTest {
    @get:Rule val compose = createComposeRule()

    @Test fun tappingBack_invokesOnBack() {
        var backed = false
        compose.setContent {
            ReaderTopChrome(theme = ReaderTheme.Paper, title = "The Great Gatsby", onBack = { backed = true })
        }
        compose.onNodeWithTag("chrome-back", useUnmergedTree = true).performClick()
        assertTrue(backed)
    }

    @Test fun titleRenders() {
        compose.setContent {
            ReaderTopChrome(theme = ReaderTheme.Paper, title = "Moby Dick", onBack = {})
        }
        compose.onNodeWithTag("reader-top-chrome").assertExists()
        compose.onNodeWithText("Moby Dick", useUnmergedTree = true).assertExists()
    }

    @Test fun searchPresentOnlyWhenCallbackNonNull() {
        // Absent when null (#133 back-compat).
        compose.setContent {
            ReaderTopChrome(theme = ReaderTheme.Paper, title = "T", onBack = {}, onSearch = null)
        }
        compose.onAllNodesWithTag("chrome-search", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun searchPresentAndInvokesWhenCallbackGiven() {
        var searched = false
        compose.setContent {
            ReaderTopChrome(theme = ReaderTheme.Paper, title = "T", onBack = {}, onSearch = { searched = true })
        }
        compose.onNodeWithTag("chrome-search", useUnmergedTree = true).assertExists().performClick()
        assertTrue(searched)
    }

    @Test fun morePresentOnlyWhenCallbackNonNull() {
        // Absent when null (#134 back-compat).
        compose.setContent {
            ReaderTopChrome(theme = ReaderTheme.Paper, title = "T", onBack = {}, onMore = null)
        }
        compose.onAllNodesWithTag("chrome-more", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun morePresentAndInvokesWhenCallbackGiven() {
        var mored = false
        compose.setContent {
            ReaderTopChrome(theme = ReaderTheme.Paper, title = "T", onBack = {}, onMore = { mored = true })
        }
        compose.onNodeWithTag("chrome-more", useUnmergedTree = true).assertExists().performClick()
        assertTrue(mored)
    }

    @Test fun bookmarkSlotAbsentWhenNull() {
        // Absent when null (#135 back-compat — no dead bookmark control).
        compose.setContent {
            ReaderTopChrome(theme = ReaderTheme.Paper, title = "T", onBack = {}, bookmarkSlot = null)
        }
        compose.onAllNodesWithTag("chrome-bookmark-slot", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun bookmarkSlotRendersWhenProvided() {
        compose.setContent {
            ReaderTopChrome(
                theme = ReaderTheme.Paper, title = "T", onBack = {},
                bookmarkSlot = { Text("BMK", modifier = Modifier.testTag("test-bookmark-content")) },
            )
        }
        compose.onNodeWithTag("chrome-bookmark-slot", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("BMK", useUnmergedTree = true).assertExists()
    }

    @Test fun allTrailingSlotsAbsentByDefault() {
        // The default is back + title only — no dead controls (the #129 rule).
        compose.setContent {
            ReaderTopChrome(theme = ReaderTheme.Dark, title = "T", onBack = {})
        }
        compose.onNodeWithTag("chrome-back", useUnmergedTree = true).assertExists()
        compose.onAllNodesWithTag("chrome-search", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithTag("chrome-more", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithTag("chrome-bookmark-slot", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun longTitleStillRendersAsSingleNode() {
        // A very long title must not crash / wrap the row — it renders (maxLines=1 + ellipsize is the
        // production Text config; here we assert the long title is present and the row is intact).
        val longTitle = "A Very Long Title That Would Otherwise Wrap Across Multiple Lines In The Top Chrome"
        compose.setContent {
            ReaderTopChrome(theme = ReaderTheme.Paper, title = longTitle, onBack = {})
        }
        compose.onNodeWithTag("reader-top-chrome").assertExists()
        compose.onNodeWithText(longTitle, useUnmergedTree = true).assertExists()
    }

    @Test fun rtlLayoutRenders() {
        compose.setContent {
            CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
                ReaderTopChrome(
                    theme = ReaderTheme.Paper, title = "كتاب", onBack = {},
                    onSearch = {}, onMore = {},
                )
            }
        }
        compose.onNodeWithTag("reader-top-chrome").assertExists()
        compose.onNodeWithTag("chrome-back", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("chrome-search", useUnmergedTree = true).assertExists()
    }

    @Test fun controlsHaveContentDescriptions() {
        compose.setContent {
            ReaderTopChrome(theme = ReaderTheme.Paper, title = "T", onBack = {}, onSearch = {}, onMore = {})
        }
        compose.onNodeWithContentDescription("Back to library").assertExists()
        compose.onNodeWithContentDescription("Search").assertExists()
        compose.onNodeWithContentDescription("More").assertExists()
    }

    @Test fun controlsMeetMinimumTouchTarget() {
        compose.setContent {
            ReaderTopChrome(theme = ReaderTheme.Paper, title = "T", onBack = {}, onSearch = {}, onMore = {})
        }
        // Every interactive control is at least 48dp in both dimensions (a11y minimum) — incl. the
        // always-present back control.
        compose.onNodeWithContentDescription("Back to library")
            .assertHeightIsAtLeast(48.dp)
        compose.onNodeWithContentDescription("Search")
            .assertWidthIsAtLeast(48.dp)
            .assertHeightIsAtLeast(48.dp)
        compose.onNodeWithContentDescription("More")
            .assertWidthIsAtLeast(48.dp)
            .assertHeightIsAtLeast(48.dp)
    }

    @Test fun bookmarkSlotHasMinimumTouchTarget() {
        // The wrapper guarantees a >=48dp minimum around the host-supplied slot so the trailing-cluster
        // a11y contract holds regardless of the slot's content.
        compose.setContent {
            ReaderTopChrome(
                theme = ReaderTheme.Paper, title = "T", onBack = {},
                bookmarkSlot = { Text("B", modifier = Modifier.testTag("bmk")) },
            )
        }
        compose.onNodeWithTag("chrome-bookmark-slot", useUnmergedTree = true)
            .assertWidthIsAtLeast(48.dp)
            .assertHeightIsAtLeast(48.dp)
    }
}
