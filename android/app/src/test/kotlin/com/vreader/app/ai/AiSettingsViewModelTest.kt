package com.vreader.app.ai

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import com.vreader.app.backup.net.SecretCipher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
class AiSettingsViewModelTest {
    @get:Rule val tmp = TemporaryFolder()

    private val cipher = object : SecretCipher {
        override fun encrypt(plaintext: String) = "enc($plaintext)"
        override fun decrypt(token: String) = token.removePrefix("enc(").removeSuffix(")")
    }
    private val dispatcher = StandardTestDispatcher()
    private lateinit var store: AiProviderStore

    private class FakeClient(val result: AiTestResult) : AiClient {
        override fun streamChat(request: AiRequest): Flow<AiChunk> = flowOf()
        override suspend fun chat(request: AiRequest) = AiResponse("")
        override suspend fun testConnection() = result
    }

    @Before fun setUp() {
        Dispatchers.setMain(dispatcher)
        // DataStore on the SAME test dispatcher so advanceUntilIdle() drives its IO too.
        store = AiProviderStore(
            PreferenceDataStoreFactory.create(scope = CoroutineScope(dispatcher)) { tmp.newFile("ai.preferences_pb") },
            cipher,
        )
    }

    @After fun tearDown() = Dispatchers.resetMain()

    private fun vm(result: AiTestResult = AiTestResult.Ok) =
        AiSettingsViewModel(store, dispatcher) { _, _ -> FakeClient(result) }

    @Test fun openAdd_test_ok_thenSave_persists() = runTest(dispatcher) {
        val vm = vm(AiTestResult.Ok)
        vm.openAdd()
        vm.update { it.copy(name = "OpenRouter", apiKey = "sk-test") }
        vm.test(); advanceUntilIdle()
        assertEquals(AiConnTest.ok, vm.editState.value!!.test)

        vm.save(); advanceUntilIdle()
        assertNull(vm.editState.value)                     // sheet closed
        assertEquals(1, store.list().size)                 // persisted
        assertEquals("sk-test", store.apiKey(store.list()[0].id))
    }

    @Test fun test_fail_surfacesMessage() = runTest(dispatcher) {
        val vm = vm(AiTestResult.Fail(AiError.Auth401, "Failed: 401"))
        vm.openAdd()
        vm.update { it.copy(name = "X", apiKey = "bad") }
        vm.test(); advanceUntilIdle()
        assertEquals(AiConnTest.fail, vm.editState.value!!.test)
        assertTrue(vm.editState.value!!.testMessage.contains("401"))
    }

    @Test fun list_reflectsSavedProvider_andActive() = runTest(dispatcher) {
        store.upsert("p1", "Claude", AiProviderKind.anthropicNative, "", "claude-sonnet-4-6", 0.7, 2048, "k")
        advanceUntilIdle()
        val vm = vm()
        val job = launch { vm.listState.collect {} }  // subscribe so WhileSubscribed collects upstream
        advanceUntilIdle()
        val rows = vm.listState.value.providers
        assertEquals(1, rows.size)
        assertTrue(rows[0].active)
        assertEquals("claude-sonnet-4-6", rows[0].detail)
        job.cancel()
    }

    // ── WI-AIP save-result seam ─────────────────────────────────────────────────────────────────
    // The scoped in-reader AI Providers sheet needs the SAVED provider id, surfaced AFTER the upsert
    // commits, to deterministically `setActive(savedId)` + pop-on-success without racing the async
    // upsert. The seam is an additive `saveResult` signal; existing `save()` callers are unaffected.

    @Test fun save_emitsSavedProviderId_afterUpsertCommits() = runTest(dispatcher) {
        val vm = vm()
        val ids = mutableListOf<String>()
        val collector = launch { vm.saveResult.collect { ids.add(it) } }
        advanceUntilIdle()

        vm.openAdd()
        vm.update { it.copy(name = "OpenRouter", apiKey = "sk-test") }
        vm.save(); advanceUntilIdle()

        assertEquals(1, ids.size)                            // exactly one save-result emitted
        val savedId = ids.single()
        // The emitted id is the one that actually persisted (upsert has committed by emit time).
        assertEquals(1, store.list().size)
        assertEquals(savedId, store.list().single().id)
        assertNull(vm.editState.value)                       // sheet still closes (existing behavior)
        collector.cancel()
    }

    @Test fun save_firstProvider_becomesActive_viaSavedId() = runTest(dispatcher) {
        // A store that already has an (unrelated) active provider, so first-provider-active default
        // does NOT cover us: the sheet must call setActive(savedId) explicitly. Here we prove the
        // saved id is the one to activate, and that setActive(savedId) makes it the store's active.
        val vm = vm()
        var savedId: String? = null
        val collector = launch { vm.saveResult.collect { savedId = it } }
        advanceUntilIdle()

        vm.openAdd()
        vm.update { it.copy(name = "Claude", apiKey = "k", kind = AiProviderKind.anthropicNative) }
        vm.save(); advanceUntilIdle()

        val id = savedId!!
        vm.setActive(id); advanceUntilIdle()
        assertEquals(id, store.snapshot().activeId)          // the freshly-saved provider is active
        collector.cancel()
    }

    @Test fun save_ofEdit_emitsExistingId() = runTest(dispatcher) {
        store.upsert("existing", "Claude", AiProviderKind.anthropicNative, "", "claude-sonnet-4-6", 0.7, 2048, "k")
        advanceUntilIdle()
        val vm = vm()
        var savedId: String? = null
        val collector = launch { vm.saveResult.collect { savedId = it } }
        advanceUntilIdle()

        vm.openEdit("existing"); advanceUntilIdle()
        vm.update { it.copy(name = "Claude Pro") }
        vm.save(); advanceUntilIdle()

        assertEquals("existing", savedId)                    // editing keeps the same id
        assertEquals(1, store.list().size)                   // no duplicate row
        assertEquals("Claude Pro", store.list().single().name)
        collector.cancel()
    }

    @Test fun rapidDoubleSave_persistsOneProfile_emitsOneResult() = runTest(dispatcher) {
        // Gate-4 High-2: a double-tap Save must NOT create two providers or emit two results (which
        // would double-pop the in-reader sheet). The single-flight guard collapses the second call.
        val vm = vm()
        val ids = mutableListOf<String>()
        val collector = launch { vm.saveResult.collect { ids.add(it) } }
        advanceUntilIdle()

        vm.openAdd()
        vm.update { it.copy(name = "OpenRouter", apiKey = "sk-test") }
        vm.save()   // both fire synchronously before the launched upsert runs
        vm.save()
        advanceUntilIdle()

        assertEquals(1, store.list().size)                   // exactly ONE provider persisted
        assertEquals(1, ids.size)                            // exactly ONE save-result emitted
        collector.cancel()
    }

    @Test fun setActiveAndAwait_commitsBeforeReturning() = runTest(dispatcher) {
        // Gate-4 High-1: the await variant JOINs the setActive commit, so the caller can pop only
        // after the active id is durably the saved one (no race with the async persist).
        store.upsert("p1", "Claude", AiProviderKind.anthropicNative, "", "claude-sonnet-4-6", 0.7, 2048, "k")
        store.upsert("p2", "DeepSeek", AiProviderKind.openAiCompatible, "", "deepseek-chat", 0.7, 2048, "k")
        advanceUntilIdle()
        val vm = vm()
        assertEquals("p1", store.snapshot().activeId)        // p1 is active initially

        launch { vm.setActiveAndAwait("p2") }; advanceUntilIdle()
        assertEquals("p2", store.snapshot().activeId)        // committed by the time await returned
    }
}
