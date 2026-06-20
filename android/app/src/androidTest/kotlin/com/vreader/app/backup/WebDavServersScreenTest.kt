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
 * Feature #114 WI-3 — the WebDAV servers list (design surface A): empty onboarding, populated
 * rows with the exact failure reason, and the Add/Edit affordances routing their callbacks.
 */
@RunWith(AndroidJUnit4::class)
class WebDavServersScreenTest {
    @get:Rule val compose = createComposeRule()

    private val servers = listOf(
        ServerSummary("nas", "Home NAS", "nas.local/dav/vreader", ServerStatus.ok, "Connected · last sync 9:14 AM", wifiOnly = true),
        ServerSummary("fm", "Fastmail Files", "myfiles.fastmail.com/dav", ServerStatus.error, "401 — authentication failed", wifiOnly = false),
    )

    @Test fun empty_onboards_withAddServerCta() {
        compose.setContent { BackupSurface { WebDavServersScreen(emptyList()) } }
        compose.onNodeWithText("No servers yet").assertIsDisplayed()
        compose.onNodeWithText("Add a WebDAV server to back up your library and sync reading progress across devices. Works with Nextcloud, Fastmail, Synology, and any standard WebDAV host.").assertIsDisplayed()
        compose.onNodeWithText("Add Server").assertIsDisplayed()
    }

    @Test fun populated_showsRows_withExactFailureReason() {
        compose.setContent { BackupSurface { WebDavServersScreen(servers) } }
        compose.onNodeWithText("Home NAS").assertIsDisplayed()
        compose.onNodeWithText("Connected · last sync 9:14 AM").assertIsDisplayed()
        compose.onNodeWithText("Fastmail Files").assertIsDisplayed()
        compose.onNodeWithText("401 — authentication failed").assertIsDisplayed()
    }

    @Test fun tappingRow_passesServerId() {
        var editedId: String? = null
        compose.setContent { BackupSurface { WebDavServersScreen(servers, onEdit = { editedId = it }) } }
        compose.onNodeWithText("Fastmail Files").performClick()
        assertEquals("fm", editedId)
    }

    @Test fun emptyState_addButton_invokesOnAdd() {
        var added = false
        compose.setContent { BackupSurface { WebDavServersScreen(emptyList(), onAdd = { added = true }) } }
        compose.onNodeWithText("Add Server").performClick()
        assertTrue(added)
    }

    @Test fun populatedAddRow_invokesOnAdd() {
        var added = false
        compose.setContent { BackupSurface { WebDavServersScreen(servers, onAdd = { added = true }) } }
        // The "Add Server" card row at the bottom of the populated list.
        compose.onNodeWithText("Add Server").performClick()
        assertTrue(added)
    }

    @Test fun topBarAddButton_invokesOnAdd() {
        var added = false
        compose.setContent { BackupSurface { WebDavServersScreen(servers, onAdd = { added = true }) } }
        compose.onNodeWithContentDescription("Add server").performClick()
        assertTrue(added)
    }

    @Test fun rendersInDark() {
        compose.setContent { BackupSurface(darkOverride = true) { WebDavServersScreen(servers) } }
        compose.onNodeWithText("Home NAS").assertIsDisplayed()
    }
}
