package com.vreader.app.opds.ui

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.backup.BackupSurface
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Feature #120 WI-3 — the OPDS error views: offline→Retry, auth/notfound→Edit source. */
@RunWith(AndroidJUnit4::class)
class OpdsErrorViewTest {
    @get:Rule val compose = createComposeRule()

    @Test fun offline_ctaRetries() {
        var retried = false; var edited = false
        compose.setContent { BackupSurface(darkOverride = false) { OpdsErrorView(OpdsBrowseError.offline, onRetry = { retried = true }, onEditSource = { edited = true }) } }
        compose.onNodeWithText("You’re offline").assertIsDisplayed()
        compose.onNodeWithTag("opds-error-cta").performClick()
        assertTrue(retried && !edited)
    }

    @Test fun auth_ctaEditsSource() {
        var retried = false; var edited = false
        compose.setContent { BackupSurface(darkOverride = false) { OpdsErrorView(OpdsBrowseError.auth, onRetry = { retried = true }, onEditSource = { edited = true }) } }
        compose.onNodeWithTag("opds-error-auth").assertIsDisplayed()
        compose.onNodeWithTag("opds-error-cta").performClick()
        assertTrue(edited && !retried)
    }

    @Test fun notfound_ctaEditsSource() {
        var edited = false
        compose.setContent { BackupSurface(darkOverride = false) { OpdsErrorView(OpdsBrowseError.notfound, onEditSource = { edited = true }) } }
        compose.onNodeWithText("Feed not found").assertIsDisplayed()
        compose.onNodeWithTag("opds-error-cta").performClick()
        assertTrue(edited)
    }
}
