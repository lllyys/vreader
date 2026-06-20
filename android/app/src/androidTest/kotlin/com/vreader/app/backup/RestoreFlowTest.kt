package com.vreader.app.backup

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Feature #114 WI-4 — the restore flow (design surface D): the confirm dialog's merge copy, the
 * in-progress ring + book label + Cancel, and the three distinct results (success/partial/failed)
 * with their CTAs. "Restore never deletes" appears in the confirm + the success copy.
 */
@RunWith(AndroidJUnit4::class)
class RestoreFlowTest {
    @get:Rule val compose = createComposeRule()

    @Test fun confirmDialog_statesMergeRules_andConfirms() {
        var confirmed = false
        compose.setContent { BackupSurface { RestoreConfirmDialog(12, "Today, 9:14 AM", onConfirm = { confirmed = true }, onDismiss = {}) } }
        compose.onNodeWithText("Restore this backup?").assertIsDisplayed()
        compose.onNodeWithText("Nothing is deleted", substring = true).assertIsDisplayed()
        compose.onNodeWithText("Restore").performClick()
        assertTrue(confirmed)
    }

    @Test fun inProgress_showsPercent_bookLabel_andCancel() {
        compose.setContent { BackupSurface { RestoreScreen(RestoreProgress.InProgress(done = 7, total = 12, currentTitle = "The Pragmatic Programmer")) } }
        compose.onNodeWithText("Restore").assertIsDisplayed()          // compact top-bar title
        compose.onNodeWithText("58%").assertIsDisplayed()              // 7/12 = 58%
        compose.onNodeWithText("Restoring your library").assertIsDisplayed()
        compose.onNodeWithText("Downloading book 7 of 12 · The Pragmatic Programmer").assertIsDisplayed()
        compose.onNodeWithText("Cancel").assertIsDisplayed()
    }

    @Test fun inProgress_cancel_invokesCallback() {
        var cancelled = false
        compose.setContent { BackupSurface { RestoreScreen(RestoreProgress.InProgress(7, 12, "Book"), onCancel = { cancelled = true }) } }
        compose.onNodeWithText("Cancel").performClick()
        assertTrue(cancelled)
    }

    @Test fun success_showsComplete_withDate_neverDeletes_andDone() {
        var done = false
        compose.setContent { BackupSurface { RestoreScreen(RestoreProgress.Result(RestoreOutcome.success, restored = 12, total = 12, failed = 0, whenLabel = "Today, 9:14 AM"), onDone = { done = true }) } }
        compose.onNodeWithText("Restore complete").assertIsDisplayed()
        compose.onNodeWithText("12 of 12 books restored from Today, 9:14 AM. Nothing in your library was deleted.").assertIsDisplayed()
        compose.onNodeWithText("Done").performClick()
        assertTrue(done)
    }

    @Test fun partial_showsIssues_retryFailed_andDone() {
        var retried = false
        var done = false
        compose.setContent { BackupSurface { RestoreScreen(RestoreProgress.Result(RestoreOutcome.partial, restored = 9, total = 12, failed = 3), onRetry = { retried = true }, onDone = { done = true }) } }
        compose.onNodeWithText("Restored with issues").assertIsDisplayed()
        compose.onNodeWithText("Done").performClick()
        assertTrue("partial Done fires", done)
        compose.onNodeWithText("Retry 3 Books").performClick()
        assertTrue(retried)
    }

    @Test fun failed_saysLibraryUnchanged_tryAgain_andBack() {
        var tried = false
        var back = false
        compose.setContent { BackupSurface { RestoreScreen(RestoreProgress.Result(RestoreOutcome.failed, restored = 0, total = 12, failed = 12), onTryAgain = { tried = true }, onCancel = { back = true }) } }
        compose.onNodeWithText("Restore failed").assertIsDisplayed()
        compose.onNodeWithText("Your library is unchanged.", substring = true).assertIsDisplayed()
        compose.onNodeWithText("Back").performClick()
        assertTrue("failed Back fires", back)
        compose.onNodeWithText("Try Again").performClick()
        assertTrue(tried)
    }

    @Test fun rendersInDark() {
        compose.setContent { BackupSurface(darkOverride = true) { RestoreScreen(RestoreProgress.Result(RestoreOutcome.success, 12, 12, 0)) } }
        compose.onNodeWithText("Restore complete").assertIsDisplayed()
    }
}
