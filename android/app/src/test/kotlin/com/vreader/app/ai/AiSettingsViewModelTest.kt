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
}
