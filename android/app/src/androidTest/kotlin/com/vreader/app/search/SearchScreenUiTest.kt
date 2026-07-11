package com.vreader.app.search

import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.data.Book
import com.vreader.app.data.Collection
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import vreader.contracts.BookFormat

/**
 * Feature #128 WI-7 — [SearchScreen] renders the three states of the committed design
 * (`vreader-library-android.jsx` section C): EMPTY (recents + browse-collections chips, each hidden
 * when empty), RESULTS (cover + wash-highlighted serif title + author subtitle + italic snippet +
 * chapter attribution), NO-RESULTS (definitive copy gated on `indexComplete` AND empty results). Pure
 * function of [SearchUiState] + event callbacks — no gestures, just clicks + semantics.
 */
@RunWith(AndroidJUnit4::class)
class SearchScreenUiTest {
    @get:Rule val compose = createComposeRule()

    private fun book(key: String, title: String, author: String? = null): Book = Book(
        fingerprintKey = key,
        title = title,
        originalFormat = BookFormat.epub,
        contentSHA256 = "sha-$key",
        fileByteCount = 1L,
        addedAt = 1L,
        lastOpenedAt = null,
        author = author,
    )

    private fun render(
        state: SearchUiState,
        onQueryChange: (String) -> Unit = {},
        onCancel: () -> Unit = {},
        onRecentTap: (String) -> Unit = {},
        onPickCollection: (String) -> Unit = {},
        onOpenResult: (SearchResultRow) -> Unit = {},
    ) {
        compose.setContent {
            SearchScreen(
                state = state,
                onQueryChange = onQueryChange,
                onCancel = onCancel,
                onRecentTap = onRecentTap,
                onPickCollection = onPickCollection,
                onOpenResult = onOpenResult,
            )
        }
    }

    // ── EMPTY state ────────────────────────────────────────────────

    @Test fun emptyState_showsRecents_andBrowseCollectionsChips() {
        render(
            SearchUiState(
                query = "",
                recents = listOf("pragmatic", "austen"),
                collections = listOf(Collection("c1", "Fiction", 1L, 3), Collection("c2", "Tech", 2L, 1)),
            ),
        )
        compose.onNodeWithText("RECENT").assertIsDisplayed()
        compose.onNodeWithText("pragmatic").assertIsDisplayed()
        compose.onNodeWithText("austen").assertIsDisplayed()
        compose.onNodeWithText("BROWSE COLLECTIONS").assertIsDisplayed()
        compose.onNodeWithText("Fiction").assertIsDisplayed()
        compose.onNodeWithText("Tech").assertIsDisplayed()
    }

    @Test fun emptyState_recentsHidden_whenNoRecents() {
        render(SearchUiState(query = "", recents = emptyList(), collections = listOf(Collection("c1", "Fiction", 1L, 3))))
        compose.onNodeWithText("RECENT").assertIsNotDisplayed()
        // the browse-collections section is still shown.
        compose.onNodeWithText("BROWSE COLLECTIONS").assertIsDisplayed()
    }

    @Test fun emptyState_collectionsHidden_whenNoCollections() {
        render(SearchUiState(query = "", recents = listOf("austen"), collections = emptyList()))
        compose.onNodeWithText("BROWSE COLLECTIONS").assertIsNotDisplayed()
        compose.onNodeWithText("RECENT").assertIsDisplayed()
    }

    @Test fun emptyState_recentTap_reQueries() {
        var tapped: String? = null
        render(
            SearchUiState(query = "", recents = listOf("pragmatic")),
            onRecentTap = { tapped = it },
        )
        compose.onNodeWithText("pragmatic").performClick()
        assertEquals("pragmatic", tapped)
    }

    @Test fun emptyState_collectionChip_reportsId() {
        var picked: String? = null
        render(
            SearchUiState(query = "", collections = listOf(Collection("c1", "Fiction", 1L, 3))),
            onPickCollection = { picked = it },
        )
        compose.onNodeWithText("Fiction").performClick()
        assertEquals("c1", picked)
    }

    // ── RESULTS state ──────────────────────────────────────────────

    private fun resultsState(): SearchUiState {
        val row0 = SearchResultRow(
            book = book("k0", "The Pragmatic Programmer", author = "Andrew Hunt"),
            titleMatch = true,
            authorMatch = false,
            textHit = TextHit(
                bookKey = "k0",
                sectionTitle = "Chapter 1",
                snippet = "the pragmatic programmer is quick to adapt",
                matchRanges = listOf(IntRange(4, 12)),
            ),
        )
        val row1 = SearchResultRow(
            book = book("k1", "Practical Data", author = "Jane Doe"),
            titleMatch = true,
            authorMatch = false,
            textHit = null,
        )
        return SearchUiState(query = "pra", results = listOf(row0, row1), searched = true, indexComplete = true)
    }

    @Test fun resultsState_showsSummary_titles_authors_andSnippet() {
        render(resultsState())
        // summary: 2 books · 1 in-text match
        compose.onNodeWithText("2 books · 1 in-text match").assertIsDisplayed()
        compose.onNodeWithText("The Pragmatic Programmer").assertIsDisplayed()
        compose.onNodeWithText("Practical Data").assertIsDisplayed()
        // author subtitles
        compose.onNodeWithText("Andrew Hunt").assertIsDisplayed()
        compose.onNodeWithText("Jane Doe").assertIsDisplayed()
        // italic snippet text (substring; wash spans are within the annotated string)
        compose.onNodeWithText("the pragmatic programmer is quick to adapt", substring = true).assertIsDisplayed()
    }

    @Test fun resultsState_chapterAttribution_shown_forRowWithHit() {
        render(resultsState())
        // "Chapter 1" attribution accompanies the in-text snippet.
        compose.onNodeWithText("Chapter 1", substring = true).assertIsDisplayed()
    }

    @Test fun resultsState_nullAuthor_rendersNoAuthorSubtitle() {
        val row = SearchResultRow(
            book = book("k0", "Anonymous Work", author = null),
            titleMatch = true,
            authorMatch = false,
            textHit = null,
        )
        render(SearchUiState(query = "anon", results = listOf(row), searched = true, indexComplete = true))
        compose.onNodeWithText("Anonymous Work").assertIsDisplayed()
        // no "null" or blank author line — the title still renders.
        compose.onNodeWithText("null").assertIsNotDisplayed()
    }

    @Test fun resultsState_resultTap_invokesOpen() {
        var opened: SearchResultRow? = null
        val state = resultsState()
        render(state, onOpenResult = { opened = it })
        compose.onNodeWithText("The Pragmatic Programmer").performClick()
        assertEquals("k0", opened?.book?.fingerprintKey)
    }

    // ── NO-RESULTS state (the honest-empty-state gate) ─────────────

    @Test fun noResults_definitiveCopy_shown_whenIndexCompleteAndEmpty() {
        render(SearchUiState(query = "thermodynamics", results = emptyList(), searched = true, indexComplete = true))
        compose.onNodeWithText("No matches for", substring = true).assertIsDisplayed()
        // The query is echoed in the no-results heading, but it ALSO appears in the
        // search input field — so match BOTH nodes (input + heading) rather than a single
        // ambiguous one. Count == 2 proves the heading echoes the query without a locator clash.
        compose.onAllNodesWithText("thermodynamics", substring = true).assertCountEquals(2)
        compose.onNodeWithText("Search looks across titles, authors, and the text of downloaded books. Try a different term.")
            .assertIsDisplayed()
    }

    @Test fun noResults_definitiveCopy_absent_whileIndexing() {
        // indexComplete = false → the definitive text-inclusive copy must NOT appear (would lie).
        render(SearchUiState(query = "thermodynamics", results = emptyList(), searched = true, indexComplete = false))
        compose.onNodeWithText("Search looks across titles, authors, and the text of downloaded books. Try a different term.")
            .assertIsNotDisplayed()
        compose.onNodeWithText("No matches for", substring = true).assertIsNotDisplayed()
    }

    @Test fun noResults_notShown_beforeSearching() {
        // a settled, un-searched screen (searched = false) shows the empty state, never no-results.
        render(SearchUiState(query = "", searched = false, indexComplete = true, recents = listOf("austen")))
        compose.onNodeWithText("No matches for", substring = true).assertIsNotDisplayed()
        compose.onNodeWithText("RECENT").assertIsDisplayed()
    }

    // ── robustness: Unicode case-fold title + hostile match ranges ──

    @Test fun resultsState_unicodeCaseFoldTitle_doesNotCrash() {
        // "İ".lowercase() expands (İ→i̇), so a lowercase-then-index-back match would go out of bounds.
        // The screen must render the title without crashing.
        val row = SearchResultRow(
            book = book("k0", "İstanbul Nights", author = "A"),
            titleMatch = true,
            authorMatch = false,
            textHit = null,
        )
        render(SearchUiState(query = "nights", results = listOf(row), searched = true, indexComplete = true))
        compose.onNodeWithText("İstanbul Nights").assertIsDisplayed()
    }

    @Test fun resultsState_overlappingMatchRanges_doNotDuplicateSnippet() {
        // Overlapping/nested/reversed/past-end ranges must not duplicate or crash the snippet.
        val hit = TextHit(
            bookKey = "k0",
            sectionTitle = null,
            snippet = "alpha beta gamma",
            matchRanges = listOf(IntRange(0, 8), IntRange(2, 4), IntRange(6, 10), IntRange(-3, 2), IntRange(100, 200)),
        )
        val row = SearchResultRow(book = book("k0", "Doc", author = null), titleMatch = false, authorMatch = false, textHit = hit)
        render(SearchUiState(query = "alpha", results = listOf(row), searched = true, indexComplete = true))
        // the snippet renders once (the wrapping quotes appear exactly once around the single text run).
        compose.onNodeWithText("alpha beta gamma", substring = true).assertIsDisplayed()
    }

    // ── the search field ───────────────────────────────────────────

    @Test fun typingInField_flowsThroughOnQueryChange() {
        var typed = ""
        render(SearchUiState(query = "", recents = listOf("austen")), onQueryChange = { typed += it })
        compose.onNodeWithText("Search title, author, or text…").performTextInput("pra")
        assertEquals("pra", typed)
    }

    @Test fun clearAffordance_emitsEmptyQuery() {
        var lastQuery: String? = null
        render(SearchUiState(query = "pra", searched = true, indexComplete = true), onQueryChange = { lastQuery = it })
        compose.onNodeWithContentDescription("Clear search").performClick()
        assertEquals("", lastQuery)
    }

    // ── Cancel ─────────────────────────────────────────────────────

    @Test fun cancel_invokesCallback() {
        var cancelled = false
        render(SearchUiState(query = "pra"), onCancel = { cancelled = true })
        compose.onNodeWithText("Cancel").performClick()
        assertTrue(cancelled)
    }
}
