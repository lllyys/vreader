package com.vreader.app.library

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.data.Collection
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Feature #127 WI-3 — the [CollectionShelfBar] renders "All" + each collection chip, tapping a chip
 * reports its id (null for "All"), and the active chip carries the `selected` semantics (the designed
 * ink-filled state). Renders the composable directly (clicks + semantics, no Activity/gesture flakiness).
 */
@RunWith(AndroidJUnit4::class)
class CollectionShelfBarUiTest {
    @get:Rule val compose = createComposeRule()

    private val cols = listOf(
        Collection(id = "c1", name = "Fiction", createdAt = 1L, bookCount = 3),
        Collection(id = "c2", name = "Tech", createdAt = 2L, bookCount = 1),
    )

    @Test fun rendersAll_andEachChip() {
        compose.setContent { CollectionShelfBar(cols, selectedId = null, onSelect = {}) }
        compose.onNodeWithText("All").assertIsDisplayed()
        compose.onNodeWithText("Fiction").assertIsDisplayed()
        compose.onNodeWithText("Tech").assertIsDisplayed()
    }

    @Test fun tappingChip_reportsItsId_andAllReportsNull() {
        var selected: String? = "unset"
        compose.setContent { CollectionShelfBar(cols, selectedId = null, onSelect = { selected = it }) }
        compose.onNodeWithText("Fiction").performClick()
        assertEquals("c1", selected)
        compose.onNodeWithText("All").performClick()
        assertNull(selected)
    }

    @Test fun activeChip_hasSelectedSemantics() {
        compose.setContent { CollectionShelfBar(cols, selectedId = "c2", onSelect = {}) }
        compose.onNodeWithText("Tech").assertIsSelected()
        compose.onNodeWithText("Fiction").assertIsNotSelected()
        compose.onNodeWithText("All").assertIsNotSelected()
    }
}
