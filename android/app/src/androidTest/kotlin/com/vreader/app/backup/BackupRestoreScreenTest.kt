package com.vreader.app.backup

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Feature #114 WI-2 — the BackupRestoreScreen (design surface C) renders each designed state +
 * its single CTA, in VReader's vocabulary (light + dark). Stateless Compose test: drive each
 * state via setContent (no Activity / no backend), the authoritative UI verification.
 */
@RunWith(AndroidJUnit4::class)
class BackupRestoreScreenTest {
    @get:Rule val compose = createComposeRule()

    private val homeNas = ServerSummary("nas", "Home NAS", "nas.local/dav/vreader", ServerStatus.ok, "Connected", wifiOnly = true)
    private val oneBackup = listOf(
        BackupSummary("b1", "Today, 9:14 AM", "4.2 MB", "Pixel 8 · this device", 12, latest = true),
    )

    private fun render(state: BackupUiState, dark: Boolean = false) {
        compose.setContent { BackupSurface(darkOverride = dark) { BackupRestoreScreen(state) } }
    }

    @Test fun idle_showsHeader_backUpNow_backupRow_andLatestTag() {
        render(BackupUiState(activeServer = homeNas, list = BackupListUi.Idle(oneBackup)))
        compose.onNodeWithText("Backup & Restore").assertIsDisplayed()
        // "Home NAS" appears twice in idle (header card + the section's right-side label).
        assertEquals(2, compose.onAllNodesWithText("Home NAS").fetchSemanticsNodes().size)
        compose.onNodeWithText("Back Up Now").assertIsDisplayed()
        compose.onNodeWithText("Today, 9:14 AM").assertIsDisplayed()
        compose.onNodeWithText("LATEST").assertIsDisplayed()        // BackupTag uppercases
        compose.onNodeWithText("Restore").assertIsDisplayed()
        compose.onNodeWithText("Restoring merges a backup into your current library — nothing is deleted. Use selective restore to pick individual books.").assertIsDisplayed()
    }

    @Test fun loading_showsReadingFromServer() {
        render(BackupUiState(activeServer = homeNas, list = BackupListUi.Loading))
        compose.onNodeWithText("Reading backups from server…").assertIsDisplayed()
    }

    @Test fun empty_showsNoBackupsYet() {
        render(BackupUiState(activeServer = homeNas, list = BackupListUi.Empty))
        compose.onNodeWithText("No backups yet").assertIsDisplayed()
    }

    @Test fun error401_namesCause_andOpenServerSettingsCta() {
        render(BackupUiState(activeServer = homeNas, list = BackupListUi.Error(WebDavError.auth401)))
        compose.onNodeWithText("Authentication failed").assertIsDisplayed()
        compose.onNodeWithText("Open Server Settings").assertIsDisplayed()
    }

    @Test fun error404_namesCause_andBackUpNowCta() {
        render(BackupUiState(activeServer = homeNas, list = BackupListUi.Error(WebDavError.notFound404)))
        compose.onNodeWithText("No backup folder found").assertIsDisplayed()
        // "Back Up Now" appears both as the header button AND the 404 CTA → assert ≥1.
        assertTrue(compose.onAllNodesWithText("Back Up Now").fetchSemanticsNodes().isNotEmpty())
    }

    @Test fun errorOffline_namesServerSpecificCopy_andRetryCta() {
        render(BackupUiState(activeServer = homeNas, list = BackupListUi.Error(WebDavError.offline)))
        compose.onNodeWithText("You’re offline").assertIsDisplayed()
        compose.onNodeWithText("Connect to the internet to reach Home NAS, then pull to refresh.").assertExists()
        compose.onNodeWithText("Retry").assertIsDisplayed()
    }

    @Test fun errorTimeout_namesHost() {
        render(BackupUiState(activeServer = homeNas, list = BackupListUi.Error(WebDavError.timeout)))
        compose.onNodeWithText("Server didn’t respond").assertIsDisplayed()
        compose.onNodeWithText("The request to nas.local timed out. Check the server is reachable on your network.").assertExists()
    }

    // --- callback routing (Gate-4: prove the CTAs fire, not just render) ---

    @Test fun backUpNow_click_invokesCallback() {
        var clicked = false
        compose.setContent {
            BackupSurface { BackupRestoreScreen(BackupUiState(homeNas, BackupListUi.Idle(oneBackup)), onBackUpNow = { clicked = true }) }
        }
        compose.onNodeWithText("Back Up Now").performClick()
        assertTrue("Back Up Now fired its callback", clicked)
    }

    @Test fun restore_click_passesBackupId() {
        var restoredId: String? = null
        compose.setContent {
            BackupSurface { BackupRestoreScreen(BackupUiState(homeNas, BackupListUi.Idle(oneBackup)), onRestore = { restoredId = it }) }
        }
        compose.onNodeWithText("Restore").performClick()
        assertEquals("b1", restoredId)
    }

    @Test fun error401Cta_click_passesCause() {
        var cause: WebDavError? = null
        compose.setContent {
            BackupSurface { BackupRestoreScreen(BackupUiState(homeNas, BackupListUi.Error(WebDavError.auth401)), onErrorCta = { cause = it }) }
        }
        compose.onNodeWithText("Open Server Settings").performClick()
        assertEquals(WebDavError.auth401, cause)
    }

    @Test fun syncing_showsInlineProgress() {
        render(BackupUiState(activeServer = homeNas, list = BackupListUi.Idle(oneBackup), syncing = Syncing(8, 12)))
        compose.onNodeWithText("Backing up… 8 / 12").assertIsDisplayed()
    }

    @Test fun idle_rendersInDark() {
        render(BackupUiState(activeServer = homeNas, list = BackupListUi.Idle(oneBackup)), dark = true)
        assertTrue(compose.onAllNodesWithText("Home NAS").fetchSemanticsNodes().isNotEmpty())
        compose.onNodeWithText("Back Up Now").assertIsDisplayed()
    }
}
