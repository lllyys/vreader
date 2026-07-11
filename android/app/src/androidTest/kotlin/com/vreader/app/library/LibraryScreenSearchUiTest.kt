package com.vreader.app.library

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import vreader.contracts.BookFormat

/**
 * Feature #128 WI-7 — the Library entry for search: the functional Search [PillIcon] in the nav row
 * (opens the search route) + the designed author subtitle under each grid title (design lines ~80-96).
 * Direct composable render (clicks + semantics, no Activity/gesture flakiness).
 */
@RunWith(AndroidJUnit4::class)
class LibraryScreenSearchUiTest {
    @get:Rule val compose = createComposeRule()

    private fun libraryBook(id: String, title: String, author: String? = null): LibraryBook = LibraryBook(
        id = id,
        title = title,
        originalFormat = BookFormat.epub,
        addedAt = 1L,
        lastOpenedAt = null,
        author = author,
    )

    @Test fun searchPill_isPresent_andInvokesCallback() {
        var searchOpened = false
        compose.setContent {
            LibraryScreen(
                state = LibraryUiState(loading = false, books = listOf(libraryBook("b1", "Dune"))),
                onOpenBook = {},
                onImport = {},
                onOpenSearch = { searchOpened = true },
            )
        }
        compose.onNodeWithContentDescription("Search").assertIsDisplayed()
        compose.onNodeWithContentDescription("Search").performClick()
        assertTrue(searchOpened)
    }

    @Test fun grid_rendersAuthorSubtitle_underTitle() {
        compose.setContent {
            LibraryScreen(
                state = LibraryUiState(
                    loading = false,
                    books = listOf(libraryBook("b1", "Pride and Prejudice", author = "Jane Austen")),
                ),
                onOpenBook = {},
                onImport = {},
                onOpenSearch = {},
            )
        }
        compose.onNodeWithText("Pride and Prejudice").assertIsDisplayed()
        compose.onNodeWithText("Jane Austen").assertIsDisplayed()
    }
}
