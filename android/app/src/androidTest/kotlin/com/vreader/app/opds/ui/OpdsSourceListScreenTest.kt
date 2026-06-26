package com.vreader.app.opds.ui

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.backup.BackupSurface
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Feature #120 WI-2 — the OPDS catalog list: empty onboarding + populated rows. */
@RunWith(AndroidJUnit4::class)
class OpdsSourceListScreenTest {
    @get:Rule val compose = createComposeRule()

    @Test fun empty_onboardsWithSuggestions() {
        var added = false
        var picked: Pair<String, String>? = null
        compose.setContent {
            BackupSurface(darkOverride = false) {
                OpdsSourceListScreen(OpdsSourceListState(emptyList()), onAdd = { added = true }, onPickSuggested = { n, u -> picked = n to u })
            }
        }
        compose.onNodeWithText("Add a catalog").assertIsDisplayed()
        compose.onNodeWithTag("suggest-Standard Ebooks").assertIsDisplayed().performClick()
        assertEquals("Standard Ebooks" to "https://standardebooks.org/opds", picked)

        compose.onNodeWithTag("opds-add").assertIsDisplayed().performClick()
        assertTrue(added)
    }

    @Test fun populated_showsRowsAndBrowses() {
        val state = OpdsSourceListState(
            listOf(
                OpdsSourceRow("a", "Standard Ebooks", "standardebooks.org/opds", OpdsSourceStatus.unknown, "standardebooks.org/opds"),
                OpdsSourceRow("b", "Calibre", "192.168.1.20:8080/opds", OpdsSourceStatus.auth, "192.168.1.20:8080/opds"),
            )
        )
        var browsed: String? = null
        compose.setContent { BackupSurface(darkOverride = false) { OpdsSourceListScreen(state, onBrowse = { browsed = it }) } }
        compose.onNodeWithText("Standard Ebooks").assertIsDisplayed()
        compose.onNodeWithText("192.168.1.20:8080/opds").assertIsDisplayed()
        compose.onNodeWithTag("source-b").performClick()
        assertEquals("b", browsed)
    }
}
