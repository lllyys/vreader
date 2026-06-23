package com.vreader.app.ai

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import com.vreader.app.backup.net.SecretCipher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
class AiChatViewModelTest {
    @get:Rule val tmp = TemporaryFolder()

    private val cipher = object : SecretCipher {
        override fun encrypt(plaintext: String) = "enc($plaintext)"
        override fun decrypt(token: String) = token.removePrefix("enc(").removeSuffix(")")
    }
    private val dispatcher = StandardTestDispatcher()
    private lateinit var store: AiProviderStore

    /** A fake client: streams the [deltas], and chat() returns [oneShot]; counts chat() calls. */
    private class FakeClient(val deltas: List<String>, val oneShot: String) : AiClient {
        var chatCalls = 0
        override fun streamChat(request: AiRequest): Flow<AiChunk> = flow { deltas.forEach { emit(AiChunk(it)) } }
        override suspend fun chat(request: AiRequest): AiResponse { chatCalls++; return AiResponse(oneShot) }
        override suspend fun testConnection() = AiTestResult.Ok
    }

    @Before fun setUp() {
        Dispatchers.setMain(dispatcher)
        store = AiProviderStore(PreferenceDataStoreFactory.create(scope = CoroutineScope(dispatcher)) { tmp.newFile("ai.preferences_pb") }, cipher)
    }
    @After fun tearDown() = Dispatchers.resetMain()

    private suspend fun configure() = store.upsert("p1", "Claude", AiProviderKind.anthropicNative, "", "claude-sonnet-4-6", 0.7, 2048, "k")

    @Test fun unconfigured_gatesEverything() = runTest(dispatcher) {
        val vm = AiChatViewModel(store, dispatcher) { _, _ -> FakeClient(emptyList(), "") }
        advanceUntilIdle()
        assertTrue(vm.state.value.unconfigured)
        vm.send("hi"); advanceUntilIdle()
        assertTrue("send is a no-op when unconfigured", vm.state.value.messages.isEmpty())
    }

    @Test fun send_streamsAndAssemblesAnswer() = runTest(dispatcher) {
        configure(); advanceUntilIdle()
        val vm = AiChatViewModel(store, dispatcher) { _, _ -> FakeClient(listOf("Mr. ", "Bingley ", "is rich."), "") }
        vm.refreshProvider(); advanceUntilIdle()
        assertFalse(vm.state.value.unconfigured)
        vm.send("Who is Mr. Bingley?"); advanceUntilIdle()
        val msgs = vm.state.value.messages
        assertEquals(2, msgs.size)                       // user + assistant
        assertTrue(msgs[0].fromUser)
        assertEquals("Mr. Bingley is rich.", msgs[1].text)  // deltas assembled
        assertFalse(vm.state.value.streaming)
    }

    @Test fun summarize_cachesPerChapter() = runTest(dispatcher) {
        configure(); advanceUntilIdle()
        val fake = FakeClient(emptyList(), "- point one\n- point two")
        val vm = AiChatViewModel(store, dispatcher) { _, _ -> fake }
        vm.refreshProvider(); advanceUntilIdle()
        vm.summarize("book:1", "ch1", "chapter text"); advanceUntilIdle()
        assertEquals("- point one\n- point two", vm.state.value.summary)
        assertFalse(vm.state.value.summaryCached)
        // Same chapter again → cache hit, no second network call.
        vm.summarize("book:1", "ch1", "chapter text"); advanceUntilIdle()
        assertTrue(vm.state.value.summaryCached)
        assertEquals(1, fake.chatCalls)
        // Regenerate → invalidate + a fresh call.
        vm.summarize("book:1", "ch1", "chapter text", regenerate = true); advanceUntilIdle()
        assertEquals(2, fake.chatCalls)
    }
}
