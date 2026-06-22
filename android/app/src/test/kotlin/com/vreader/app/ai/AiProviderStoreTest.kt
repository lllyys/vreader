package com.vreader.app.ai

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import com.vreader.app.backup.net.SecretCipher
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
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

/**
 * Feature #118 WI-1 — AiProviderStore CRUD + active-id + key-as-cipher-token, with a temp DataStore
 * and a reversible FAKE cipher. Verifies the API key is never persisted in plaintext, the first
 * provider becomes active, active-deletion reselects, and edit-with-null-key keeps the key.
 */
@RunWith(RobolectricTestRunner::class)
class AiProviderStoreTest {
    @get:Rule val tmp = TemporaryFolder()

    private val fakeCipher = object : SecretCipher {
        override fun encrypt(plaintext: String) = "enc($plaintext)"
        override fun decrypt(token: String) = token.removePrefix("enc(").removeSuffix(")")
    }

    private lateinit var dataStore: DataStore<Preferences>
    private lateinit var store: AiProviderStore

    @Before fun setUp() {
        dataStore = PreferenceDataStoreFactory.create { tmp.newFile("ai.preferences_pb") }
        store = AiProviderStore(dataStore, fakeCipher)
    }

    @After fun tearDown() { /* closes with temp folder */ }

    private suspend fun add(id: String, key: String? = "k-$id", kind: AiProviderKind = AiProviderKind.anthropicNative) =
        store.upsert(id, "Provider $id", kind, kind.defaultBaseUrl, kind.defaultModel, 0.7, 2048, key)

    @Test fun upsert_storesCiphertext_firstBecomesActive() = runTest {
        add("p1", key = "s3cret")
        val snap = store.snapshot()
        assertEquals(1, snap.profiles.size)
        assertEquals("enc(s3cret)", snap.profiles[0].encryptedApiKey)  // never plaintext
        assertEquals("p1", snap.activeId)                              // first → active
        assertEquals("s3cret", store.apiKey("p1"))                     // decrypts
        assertEquals("p1", store.activeProfile()?.id)
    }

    @Test fun secondProvider_doesNotStealActive_butCanBeSelected() = runTest {
        add("p1"); add("p2")
        assertEquals("p1", store.snapshot().activeId)  // active stays the first
        store.setActive("p2")
        assertEquals("p2", store.snapshot().activeId)
    }

    @Test fun edit_nullKey_keepsExisting() = runTest {
        add("p1", key = "orig")
        store.upsert("p1", "Renamed", AiProviderKind.openAiCompatible, "https://x/", "gpt-4o-mini", 0.9, 1024, apiKey = null)
        assertEquals("orig", store.apiKey("p1"))           // key kept
        assertEquals("Renamed", store.list()[0].name)      // metadata updated
        assertEquals(AiProviderKind.openAiCompatible, store.list()[0].kind)
    }

    @Test fun newProvider_withoutKey_throws() = runTest {
        val ex = runCatching { add("p1", key = null) }.exceptionOrNull()
        assertTrue(ex is IllegalArgumentException)
    }

    @Test fun deletingActive_reselectsFirstRemaining() = runTest {
        add("p1"); add("p2"); store.setActive("p1")
        store.delete("p1")
        assertEquals("p2", store.snapshot().activeId)  // active moved on
        assertNull(store.apiKey("p1"))
        store.delete("p2")
        assertNull(store.snapshot().activeId)           // none left → null
    }

    @Test fun observe_reflectsWrites() = runTest {
        assertTrue(store.observe().first().profiles.isEmpty())
        add("p1")
        assertEquals(1, store.observe().first().profiles.size)
    }
}
