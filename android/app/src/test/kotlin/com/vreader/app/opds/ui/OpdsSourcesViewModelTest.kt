package com.vreader.app.opds.ui

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import com.vreader.app.backup.net.SecretCipher
import com.vreader.app.opds.OpdsError
import com.vreader.app.opds.OpdsFeed
import com.vreader.app.opds.OpdsSourceStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** Feature #120 WI-2 — OpdsSourcesViewModel: list mapping, add/edit, test-connection, save, delete. */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
class OpdsSourcesViewModelTest {
    @get:Rule val tmp = TemporaryFolder()

    private val cipher = object : SecretCipher {
        override fun encrypt(plaintext: String) = "enc($plaintext)"
        override fun decrypt(token: String) = token.removePrefix("enc(").removeSuffix(")")
    }
    private val dispatcher = StandardTestDispatcher()
    private lateinit var store: OpdsSourceStore

    @Before fun setUp() {
        Dispatchers.setMain(dispatcher)
        store = OpdsSourceStore(
            PreferenceDataStoreFactory.create(scope = CoroutineScope(dispatcher)) { tmp.newFile("opds.preferences_pb") },
            cipher,
        )
    }

    @After fun tearDown() = Dispatchers.resetMain()

    /** A VM whose test-connection client either returns a feed or throws [error]. Records the creds
     *  the factory was handed so the test can assert origin-scoped auth wiring. */
    private class Recorder { var user: String? = null; var origin: String? = null; var url: String? = null }

    private fun vm(error: OpdsError? = null, rec: Recorder = Recorder()): OpdsSourcesViewModel =
        OpdsSourcesViewModel(store, dispatcher) { u, _, o ->
            rec.user = u; rec.origin = o
            OpdsFeedTester { url ->
                rec.url = url
                error?.let { throw it }
                OpdsFeed(title = "Cat", id = "i")
            }
        }

    @Test fun list_mapsSavedSources_authAndPublic() = runTest(dispatcher) {
        store.upsert("a", "Standard Ebooks", "https://standardebooks.org/opds", requiresAuth = false, username = "", password = null)
        store.upsert("b", "Calibre", "http://192.168.1.20:8080/opds", requiresAuth = true, username = "reader", password = "pw")
        val v = vm()
        val job = launch { v.listState.collect {} }
        advanceUntilIdle()
        val rows = v.listState.value.sources
        assertFalse(v.listState.value.empty)
        assertEquals(setOf("standardebooks.org/opds", "192.168.1.20:8080/opds"), rows.map { it.host }.toSet())
        assertEquals(OpdsSourceStatus.auth, rows.first { it.id == "b" }.status)
        assertEquals(OpdsSourceStatus.unknown, rows.first { it.id == "a" }.status)
        job.cancel()
    }

    @Test fun openAdd_prefilled_thenTestOk_thenSave_persists() = runTest(dispatcher) {
        val rec = Recorder()
        val v = vm(rec = rec)
        v.openAdd(name = "Standard Ebooks", url = "https://standardebooks.org/opds")
        assertEquals("Standard Ebooks", v.editState.value!!.name)
        v.test(); advanceUntilIdle()
        assertEquals(OpdsConnTest.ok, v.editState.value!!.test)
        assertEquals("https://standardebooks.org/opds", rec.url)
        assertNull("public catalog → no origin-scoped auth", rec.user)

        v.save(); advanceUntilIdle()
        assertNull(v.editState.value)
        assertEquals(1, store.list().size)
        assertEquals("https://standardebooks.org/opds", store.list()[0].url)
    }

    @Test fun test_withAuth_passesOriginScopedCreds() = runTest(dispatcher) {
        val rec = Recorder()
        val v = vm(rec = rec)
        v.openAdd()
        v.update { it.copy(name = "C", url = "http://192.168.1.20:8080/opds", requiresAuth = true, username = "reader", password = "pw") }
        v.test(); advanceUntilIdle()
        assertEquals(OpdsConnTest.ok, v.editState.value!!.test)
        assertEquals("reader", rec.user)
        assertEquals("http://192.168.1.20:8080", rec.origin)
    }

    @Test fun test_401_mapsToSignInMessage() = runTest(dispatcher) {
        val v = vm(error = OpdsError.Http(401))
        v.openAdd(); v.update { it.copy(name = "C", url = "http://h/opds", requiresAuth = true, username = "u", password = "bad") }
        v.test(); advanceUntilIdle()
        assertEquals(OpdsConnTest.fail, v.editState.value!!.test)
        assertTrue(v.editState.value!!.testMessage.contains("401"))
    }

    @Test fun test_offline_mapsToNetworkMessage() = runTest(dispatcher) {
        val v = vm(error = OpdsError.Network("offline"))
        v.openAdd(); v.update { it.copy(name = "C", url = "http://h/opds") }
        v.test(); advanceUntilIdle()
        assertEquals(OpdsConnTest.fail, v.editState.value!!.test)
        assertTrue(v.editState.value!!.testMessage.contains("reach", ignoreCase = true))
    }

    @Test fun openEdit_blankPasswordSave_keepsExistingKey() = runTest(dispatcher) {
        store.upsert("b", "Calibre", "http://h/opds", requiresAuth = true, username = "reader", password = "orig")
        val v = vm()
        v.openEdit("b"); advanceUntilIdle()
        assertTrue(v.editState.value!!.keyAlreadySaved)
        assertEquals("", v.editState.value!!.password)  // not prefilled
        v.update { it.copy(name = "Calibre HQ") }
        v.save(); advanceUntilIdle()
        val s = store.list().single()
        assertEquals("Calibre HQ", s.name)
        assertEquals("orig", store.password(s))          // key preserved
    }

    @Test fun delete_removesSource() = runTest(dispatcher) {
        store.upsert("a", "A", "https://a/opds", false, "", null)
        val v = vm()
        v.openEdit("a"); advanceUntilIdle()
        v.delete(); advanceUntilIdle()
        assertTrue(store.list().isEmpty())
        assertNull(v.editState.value)
    }

    @Test fun staleTestResult_discardedWhenFormEditedMidTest() = runTest(dispatcher) {
        val v = vm()  // tester returns ok
        v.openAdd(); v.update { it.copy(name = "C", url = "http://a/opds") }
        v.test()                                       // launched against catalog A, not yet idle
        v.update { it.copy(url = "http://b/opds") }     // user edits the URL mid-test
        advanceUntilIdle()
        // the ok for /a must NOT land on the /b form — it resets to idle instead
        assertEquals(OpdsConnTest.idle, v.editState.value!!.test)
    }

    @Test fun staleTestResult_ignoredAfterClose() = runTest(dispatcher) {
        val v = vm()
        v.openAdd(); v.update { it.copy(name = "C", url = "http://h/opds") }
        v.test()          // launched, not yet idle
        v.close()         // bumps testGen → the in-flight result must be discarded
        advanceUntilIdle()
        assertNull(v.editState.value)
    }
}
