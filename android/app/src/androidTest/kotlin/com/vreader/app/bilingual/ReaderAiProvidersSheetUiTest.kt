package com.vreader.app.bilingual

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.ai.AiClient
import com.vreader.app.ai.AiChunk
import com.vreader.app.ai.AiProviderKind
import com.vreader.app.ai.AiProviderStore
import com.vreader.app.ai.AiRequest
import com.vreader.app.ai.AiResponse
import com.vreader.app.ai.AiSettingsViewModel
import com.vreader.app.ai.AiTestResult
import com.vreader.app.backup.BackupSurface
import com.vreader.app.backup.net.SecretCipher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.runBlocking
import java.io.File
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Feature #131 WI-AIP — the scoped in-reader AI-Providers sheet ([ReaderAiProvidersSheet]) over a REAL
 * [AiSettingsViewModel] + [AiProviderStore]. Verifies (rule 51 fidelity + the (a)/(b)/(c) contract):
 *  - the scoped list renders the ‹ Bilingual back label + the bilingual-context strip;
 *  - the empty state shows the bilingual-context onboarding ("No providers yet" / "Add provider");
 *  - a populated list checks the ACTIVE row ("In use") and tapping another row SELECTs it (setActive);
 *  - empty → Add → the REUSED AiProviderEditSheet (no divergent form) → Save → the save-result seam
 *    fires setActive(savedId) → pops the whole stack (onDone), the provider persisted + active (no race);
 *  - ‹ Bilingual with nothing added pops the stack with NO state mutation (snapshot unchanged);
 *  - "Change…" entry (already-populated) → current provider checked.
 *
 * A fake AiClient makes Test Connection succeed off-network; the save-seam still uses the REAL store.
 */
@RunWith(AndroidJUnit4::class)
class ReaderAiProvidersSheetUiTest {
    @get:Rule val compose = createComposeRule()

    private val cipher = object : SecretCipher {
        override fun encrypt(plaintext: String) = "enc($plaintext)"
        override fun decrypt(token: String) = token.removePrefix("enc(").removeSuffix(")")
    }
    private lateinit var storeFile: File
    private lateinit var store: AiProviderStore
    private val storeScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private class FakeClient : AiClient {
        override fun streamChat(request: AiRequest): Flow<AiChunk> = flowOf()
        override suspend fun chat(request: AiRequest) = AiResponse("")
        override suspend fun testConnection() = AiTestResult.Ok
    }

    @Before fun setUp() {
        val ctx = InstrumentationRegistry.getInstrumentation().targetContext
        storeFile = File(ctx.cacheDir, "wiaip-ai-${UUID.randomUUID()}.preferences_pb")
        store = AiProviderStore(
            PreferenceDataStoreFactory.create(scope = storeScope) { storeFile },
            cipher,
        )
    }

    @After fun tearDown() { storeFile.delete() }

    private fun vm() = AiSettingsViewModel(store, Dispatchers.IO) { _, _ -> FakeClient() }

    private fun seed(id: String, name: String, model: String) = runBlocking {
        store.upsert(id, name, AiProviderKind.anthropicNative, "", model, 0.7, 2048, "k")
    }

    // ── (b) the scoped list: chrome + bilingual-context empty state ─────────────────────────────

    @Test fun emptyList_showsBilingualNav_andContext_andOnboarding() {
        compose.setContent {
            BackupSurface(darkOverride = false) { ReaderAiProvidersSheet(vm = vm(), onDone = {}) }
        }
        compose.onNodeWithText("AI Providers").assertIsDisplayed()
        compose.onNodeWithTag("reader-ai-back").assertIsDisplayed()
        compose.onNodeWithText("Bilingual").assertIsDisplayed()  // the ‹ Bilingual back label
        compose.onNodeWithText("Choose the provider bilingual mode will use to translate this book.").assertIsDisplayed()
        compose.onNodeWithText("No providers yet").assertIsDisplayed()  // bilingual-context empty state
        compose.onNodeWithTag("reader-ai-empty").assertIsDisplayed()
    }

    @Test fun backLabel_withNothingAdded_popsWithoutMutation() {
        var done = false
        compose.setContent {
            BackupSurface(darkOverride = false) { ReaderAiProvidersSheet(vm = vm(), onDone = { done = true }) }
        }
        compose.onNodeWithTag("reader-ai-back").performClick()
        assertTrue("‹ Bilingual pops the stack", done)
        // Nothing was mutated — the store is still empty.
        assertTrue(runBlocking { store.list().isEmpty() })
        assertNull(runBlocking { store.snapshot().activeId })
    }

    // ── (b) populated: checked-active row + tap-to-SELECT ───────────────────────────────────────

    @Test fun populatedList_checksActiveRow_andShowsChangeContext() {
        seed("p1", "Claude", "claude-sonnet-4-6")
        seed("p2", "DeepSeek", "deepseek-chat")  // p1 stays active (first-provider-active default)
        val vm = vm()
        // subscribe so listState (WhileSubscribed) collects upstream before rendering
        compose.setContent {
            BackupSurface(darkOverride = false) { ReaderAiProvidersSheet(vm = vm, onDone = {}) }
        }
        compose.waitUntil(5_000) {
            compose.onAllNodesWithTag("reader-provider-p1").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithText("Claude").assertExists()
        compose.onNodeWithText("DeepSeek").assertExists()
        // p1 is active → its row shows the "In use" check; p2 does not. (assertExists, not
        // assertIsDisplayed — the rows live in a scrollable column and may be below the fold; the
        // "In use" Row's testTag is collapsed by the clickable provider Row → useUnmergedTree.)
        compose.onNodeWithTag("reader-provider-p1-active", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("reader-provider-p2-active", useUnmergedTree = true).assertDoesNotExist()
    }

    @Test fun tappingRow_selectsProvider_viaSetActive() {
        seed("p1", "Claude", "claude-sonnet-4-6")
        seed("p2", "DeepSeek", "deepseek-chat")  // p1 active initially
        val vm = vm()
        compose.setContent {
            BackupSurface(darkOverride = false) { ReaderAiProvidersSheet(vm = vm, onDone = {}) }
        }
        compose.waitUntil(5_000) {
            compose.onAllNodesWithTag("reader-provider-p2").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("reader-provider-p2").performClick()
        // Tap = SELECT (setActive), NOT edit; the store's active becomes p2, and the list stays put.
        compose.waitUntil(5_000) { runBlocking { store.snapshot().activeId } == "p2" }
        assertEquals("p2", runBlocking { store.snapshot().activeId })
        compose.onNodeWithText("AI Providers").assertIsDisplayed()  // did NOT navigate to the editor
    }

    // ── (a) reused editor + (c) save-result seam: Add → Save → setActive → pop ──────────────────

    @Test fun add_opensReusedEditor_thenSave_activatesAndPops_noRace() {
        // Seed an EXISTING active provider so the store's first-provider-active default does NOT mask a
        // missing setActive — the sheet must EXPLICITLY activate the newly-saved provider (Gate-4 M1).
        seed("existing", "Claude", "claude-sonnet-4-6")
        // Capture the store's active id AT the exact onDone callback time — proves activate-before-pop.
        var activeIdAtDone: String? = null
        var done = false
        val vm = vm()
        compose.setContent {
            BackupSurface(darkOverride = false) {
                ReaderAiProvidersSheet(vm = vm, onDone = {
                    activeIdAtDone = runBlocking { store.snapshot().activeId }
                    done = true
                })
            }
        }
        compose.onNodeWithTag("reader-ai-add").performClick()
        // (a) The REUSED AiProviderEditSheet — its verbatim "Add Provider" header + sections.
        compose.onNodeWithText("Add Provider").assertIsDisplayed()
        compose.onNodeWithText("PROVIDER TYPE").performScrollTo().assertIsDisplayed()

        // Fill the name + a key so canSave is true, then Save. (The editor's Field testTag is
        // "field-<label-or-placeholder>"; Name + API Key have blank labels → their placeholders.)
        // Scroll each SECTION header into view first (a scrollable Text child of the sheet body),
        // then input into the field it exposes — the BasicTextField node itself has no scroll ancestor.
        compose.onNodeWithText("NAME").performScrollTo()
        compose.onNodeWithTag("field-e.g. OpenRouter").performTextInput("OpenRouter")
        compose.onNodeWithText("API KEY").performScrollTo()
        compose.onNodeWithTag("field-Enter API Key").performTextInput("sk-test")
        compose.onNodeWithTag("ai-save").performClick()

        // (c) Save → saved id → setActiveAndAwait(savedId) → onDone. Activation is JOINED before the
        // pop, so the newly-saved provider is ALREADY the active engine at onDone time (no race).
        compose.waitUntil(5_000) { done }
        assertTrue("save pops the whole stack back to bilingual", done)
        val saved = runBlocking { store.snapshot() }
        assertEquals(2, saved.profiles.size)                 // existing + the new one persisted
        val newId = saved.profiles.first { it.name == "OpenRouter" }.id
        assertEquals("the new provider was activated BEFORE the pop", newId, activeIdAtDone)
        assertEquals(newId, saved.activeId)                  // and stays the active engine
        assertNull(vm.editState.value)                       // editor closed
    }

    @Test fun editorCancel_returnsToList_withoutMutation() {
        val vm = vm()
        compose.setContent {
            BackupSurface(darkOverride = false) { ReaderAiProvidersSheet(vm = vm, onDone = {}) }
        }
        compose.onNodeWithTag("reader-ai-add").performClick()
        compose.onNodeWithText("Add Provider").assertIsDisplayed()
        compose.onNodeWithText("Cancel").performClick()
        // Back on the scoped list (not the whole-stack pop), store untouched.
        compose.onNodeWithText("AI Providers").assertIsDisplayed()
        assertTrue(runBlocking { store.list().isEmpty() })
    }
}
