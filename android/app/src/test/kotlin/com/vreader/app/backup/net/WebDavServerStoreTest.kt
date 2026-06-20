package com.vreader.app.backup.net

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Feature #116 WI-5 — WebDavServerStore CRUD + password encryption, with a temp DataStore and a
 * reversible FAKE cipher (the real AndroidKeyStore cipher isn't available under Robolectric;
 * it's exercised on-device in WI-6). Verifies plaintext is never persisted, edits keep the
 * password when null, and decrypt round-trips.
 */
@RunWith(RobolectricTestRunner::class)
class WebDavServerStoreTest {
    @get:Rule val tmp = TemporaryFolder()

    /** Reversible stand-in for the AES-GCM cipher — prefixes so the test can prove the stored
     *  value is the ciphertext, not the plaintext. */
    private val fakeCipher = object : SecretCipher {
        override fun encrypt(plaintext: String) = "enc(${plaintext})"
        override fun decrypt(token: String) = token.removePrefix("enc(").removeSuffix(")")
    }

    private lateinit var dataStore: DataStore<Preferences>
    private lateinit var store: WebDavServerStore

    @Before fun setUp() {
        dataStore = PreferenceDataStoreFactory.create { tmp.newFile("servers.preferences_pb") }
        store = WebDavServerStore(dataStore, fakeCipher)
    }

    @After fun tearDown() { /* DataStore closes with the temp folder */ }

    @Test fun upsert_thenList_storesCiphertextNotPlaintext() = runTest {
        store.upsert("s1", "Home NAS", "https://nas.local/dav/", "alice", "s3cret", wifiOnly = true)
        val list = store.list()
        assertEquals(1, list.size)
        assertEquals("Home NAS", list[0].name)
        assertEquals("enc(s3cret)", list[0].encryptedPassword)  // never the plaintext
        assertTrue(list[0].wifiOnly)
        assertEquals("s3cret", store.password("s1"))  // decrypts
    }

    @Test fun upsert_existingId_updatesInPlace() = runTest {
        store.upsert("s1", "A", "https://a/", "u", "p1", wifiOnly = false)
        store.upsert("s1", "A renamed", "https://a2/", "u2", "p2", wifiOnly = true)
        val list = store.list()
        assertEquals(1, list.size)  // updated, not duplicated
        assertEquals("A renamed", list[0].name)
        assertEquals("https://a2/", list[0].baseUrl)
        assertEquals("p2", store.password("s1"))
    }

    @Test fun upsert_nullPassword_keepsExisting() = runTest {
        store.upsert("s1", "A", "https://a/", "u", "orig", wifiOnly = false)
        store.upsert("s1", "A", "https://a/", "u", password = null, wifiOnly = true)  // edit, no pw change
        assertEquals("orig", store.password("s1"))
        assertTrue(store.list()[0].wifiOnly)
    }

    @Test fun upsert_nullPassword_newId_throws() = runTest {
        val ex = runCatching {
            store.upsert("new", "A", "https://a/", "u", password = null, wifiOnly = false)
        }.exceptionOrNull()
        assertTrue(ex is IllegalArgumentException)
    }

    @Test fun delete_removesProfile() = runTest {
        store.upsert("s1", "A", "https://a/", "u", "p", wifiOnly = false)
        store.upsert("s2", "B", "https://b/", "u", "p", wifiOnly = false)
        store.delete("s1")
        assertEquals(listOf("s2"), store.list().map { it.id })
        assertNull(store.password("s1"))
    }

    @Test fun observe_reflectsWrites() = runTest {
        assertTrue(store.observe().first().isEmpty())
        store.upsert("s1", "A", "https://a/", "u", "p", wifiOnly = false)
        assertEquals(1, store.observe().first().size)
    }
}
