package com.vreader.app.backup

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Feature #114 WI-5 — the selective restore picker (design surface E): per-book state
 * (local/remote/downloading/failed), the selection footer total, toggle/retry/restore callbacks.
 */
@RunWith(AndroidJUnit4::class)
class SelectiveRestoreSheetTest {
    @get:Rule val compose = createComposeRule()

    private val books = listOf(
        ManifestBook("m1", "Pride and Prejudice", "Jane Austen", "432 KB", BookState.local),
        ManifestBook("m2", "The Beginning of Infinity", "David Deutsch", "1.8 MB", BookState.remote),
        ManifestBook("m3", "Designing Data-Intensive Applications", "Martin Kleppmann", "8.4 MB", BookState.downloading, progress = 0.46f),
        ManifestBook("m5", "Meditations", "Marcus Aurelius", "298 KB", BookState.failed),
    )
    private val selected = setOf("m1", "m2", "m3", "m5")

    private fun render(sel: Set<String> = selected) {
        compose.setContent { BackupSurface { SelectiveRestoreSheet(books, sel, whenLabel = "Today, 9:14 AM") } }
    }

    @Test fun showsTitle_intro_andEachBook() {
        render()
        compose.onNodeWithText("Choose Books").assertIsDisplayed()
        compose.onNodeWithText("Pride and Prejudice").assertIsDisplayed()
        compose.onNodeWithText("Designing Data-Intensive Applications").assertIsDisplayed()
    }

    @Test fun perBookStates_render() {
        render()
        compose.onNodeWithText("On this device").assertIsDisplayed()              // local
        compose.onNodeWithText("Download · 1.8 MB").assertIsDisplayed()           // remote
        compose.onNodeWithText("46%").assertIsDisplayed()                        // downloading
        compose.onNodeWithText("Download failed — tap to retry").assertIsDisplayed() // failed
    }

    @Test fun footer_totalsSelection() {
        render()
        compose.onNodeWithText("4 books selected").assertIsDisplayed()
        compose.onNodeWithText("1 already local · 3 will download").assertIsDisplayed()
    }

    @Test fun footer_updatesWhenFewerSelected() {
        render(sel = setOf("m1", "m2"))
        compose.onNodeWithText("2 books selected").assertIsDisplayed()
        compose.onNodeWithText("1 already local · 1 will download").assertIsDisplayed()
    }

    @Test fun tappingRow_togglesSelection() {
        var toggled: String? = null
        compose.setContent { BackupSurface { SelectiveRestoreSheet(books, selected, "Today, 9:14 AM", onToggle = { toggled = it }) } }
        compose.onNodeWithText("Pride and Prejudice").performClick()
        assertEquals("m1", toggled)
    }

    @Test fun restore_invokesCallback() {
        var restored = false
        compose.setContent { BackupSurface { SelectiveRestoreSheet(books, selected, "Today, 9:14 AM", onRestore = { restored = true }) } }
        compose.onNodeWithText("Restore").performClick()
        assertTrue(restored)
    }

    @Test fun deselectAll_whenAllSelected() {
        var toggled = false
        compose.setContent { BackupSurface { SelectiveRestoreSheet(books, selected, "Today, 9:14 AM", onToggleSelectAll = { toggled = true }) } }
        compose.onNodeWithText("Deselect all").performClick()
        assertTrue(toggled)
    }

    @Test fun retry_failedBook_invokesRetry_notRowToggle() {
        var retried: String? = null
        var toggled: String? = null
        compose.setContent { BackupSurface { SelectiveRestoreSheet(books, selected, "Today, 9:14 AM", onToggle = { toggled = it }, onRetry = { retried = it }) } }
        compose.onNodeWithContentDescription("Retry").performClick()
        assertEquals("m5", retried)        // the failed book's id
        assertEquals("retry did not also toggle the row", null, toggled)
    }

    @Test fun selectAll_shownWhenNotAllSelected() {
        render(sel = setOf("m1"))
        compose.onNodeWithText("Select all").assertIsDisplayed()
    }

    @Test fun rendersInDark() {
        compose.setContent { BackupSurface(darkOverride = true) { SelectiveRestoreSheet(books, selected, "Today, 9:14 AM") } }
        compose.onNodeWithText("Choose Books").assertIsDisplayed()
    }
}
