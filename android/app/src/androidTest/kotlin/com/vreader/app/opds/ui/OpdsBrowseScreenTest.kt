package com.vreader.app.opds.ui

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.backup.BackupSurface
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Feature #120 WI-3 — the OPDS browse screen: nav rows, acquisition entries + states, phases. */
@RunWith(AndroidJUnit4::class)
class OpdsBrowseScreenTest {
    @get:Rule val compose = createComposeRule()

    private fun entry(key: String, title: String, state: OpdsItemState, fail: String? = null) =
        OpdsEntryRow(key = key, index = 0, title = title, author = "Author", format = "EPUB", state = state, failMessage = fail)

    @Test fun feed_showsNavAndEntries_andDrills() {
        val state = OpdsBrowseState(
            title = "Standard Ebooks", phase = OpdsBrowsePhase.feed,
            navRows = listOf(OpdsNavRow("By author", "https://x/a")),
            sectionTitle = "Newest", entries = listOf(entry("k1", "Middlemarch", OpdsItemState.remote)),
        )
        var navigated: String? = null; var downloaded: String? = null
        compose.setContent { BackupSurface(darkOverride = false) { OpdsBrowseScreen(state, onNavigate = { navigated = it.title }, onDownload = { downloaded = it }) } }
        compose.onNodeWithText("By author").assertIsDisplayed()
        compose.onNodeWithText("Middlemarch").assertIsDisplayed()
        compose.onNodeWithTag("nav-By author").performClick()
        assertEquals("By author", navigated)
        compose.onNodeWithTag("dl-get-k1").performScrollTo().performClick()
        assertEquals("k1", downloaded)
    }

    @Test fun entryStates_render() {
        val state = OpdsBrowseState(
            title = "Cat", phase = OpdsBrowsePhase.feed,
            entries = listOf(
                entry("a", "Downloading", OpdsItemState.downloading),
                entry("b", "Owned", OpdsItemState.library),
                entry("c", "Broken", OpdsItemState.failed, fail = "That download isn't a supported book."),
            ),
        )
        compose.setContent { BackupSurface(darkOverride = false) { OpdsBrowseScreen(state) } }
        compose.onNodeWithTag("dl-progress-a").assertIsDisplayed()
        compose.onNodeWithTag("dl-library-b").performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("dl-get-c").performScrollTo().assertIsDisplayed()  // failed → Retry chip
    }

    @Test fun loading_showsShimmer() {
        compose.setContent { BackupSurface(darkOverride = false) { OpdsBrowseScreen(OpdsBrowseState(title = "Cat", phase = OpdsBrowsePhase.loading)) } }
        compose.onNodeWithTag("opds-loading").assertIsDisplayed()
    }

    @Test fun empty_showsEmptyShelf() {
        compose.setContent { BackupSurface(darkOverride = false) { OpdsBrowseScreen(OpdsBrowseState(title = "Cat", phase = OpdsBrowsePhase.empty)) } }
        compose.onNodeWithTag("opds-empty").assertIsDisplayed()
    }

    @Test fun loadMore_invokesCallback() {
        var more = false
        val state = OpdsBrowseState(title = "Cat", phase = OpdsBrowsePhase.feed, entries = listOf(entry("k1", "M", OpdsItemState.remote)), canLoadMore = true)
        compose.setContent { BackupSurface(darkOverride = false) { OpdsBrowseScreen(state, onLoadMore = { more = true }) } }
        compose.onNodeWithTag("opds-load-more").performScrollTo().performClick()
        assertTrue(more)
    }
}
