package com.vreader.app.opds

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import com.vreader.app.backup.net.SecretCipher
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** Feature #120 WI-1 — OpdsSourceStore CRUD + optional-auth credential handling (fake cipher). */
@RunWith(RobolectricTestRunner::class)
class OpdsSourceStoreTest {
    @get:Rule val tmp = TemporaryFolder()

    private val cipher = object : SecretCipher {
        override fun encrypt(plaintext: String) = "enc($plaintext)"
        override fun decrypt(token: String) = token.removePrefix("enc(").removeSuffix(")")
    }
    private lateinit var dataStore: DataStore<Preferences>
    private lateinit var store: OpdsSourceStore

    @Before fun setUp() {
        dataStore = PreferenceDataStoreFactory.create { tmp.newFile("opds.preferences_pb") }
        store = OpdsSourceStore(dataStore, cipher)
    }

    @Test fun upsert_noAuth_storesNoCreds() = runTest {
        store.upsert("s1", "Standard Ebooks", "https://standardebooks.org/opds", requiresAuth = false, username = "", password = null)
        val s = store.list().single()
        assertEquals("Standard Ebooks", s.name)
        assertTrue(!s.requiresAuth && s.username.isEmpty() && s.encryptedPassword.isEmpty())
        assertNull(store.password(s))
    }

    @Test fun upsert_withAuth_storesCiphertext_decrypts() = runTest {
        store.upsert("s1", "Calibre", "http://192.168.1.20:8080/opds", requiresAuth = true, username = "reader", password = "pw")
        val s = store.list().single()
        assertEquals("enc(pw)", s.encryptedPassword)   // never plaintext
        assertEquals("pw", store.password(s))
        assertEquals("reader", s.username)
    }

    @Test fun edit_nullPassword_keepsExisting() = runTest {
        store.upsert("s1", "Calibre", "http://192.168.1.20:8080/opds", requiresAuth = true, username = "reader", password = "orig")
        store.upsert("s1", "Calibre HQ", "http://192.168.1.20:8080/opds", requiresAuth = true, username = "reader", password = null)
        assertEquals("orig", store.password(store.list().single()))
        assertEquals("Calibre HQ", store.list().single().name)
    }

    @Test fun turningAuthOff_clearsCreds() = runTest {
        store.upsert("s1", "C", "http://192.168.1.20:8080/opds", requiresAuth = true, username = "reader", password = "pw")
        store.upsert("s1", "C", "http://192.168.1.20:8080/opds", requiresAuth = false, username = "reader", password = null)
        val s = store.list().single()
        assertTrue(!s.requiresAuth && s.encryptedPassword.isEmpty() && s.username.isEmpty())
    }

    @Test fun delete_removes() = runTest {
        store.upsert("s1", "A", "https://a/opds", false, "", null)
        store.upsert("s2", "B", "https://b/opds", false, "", null)
        store.delete("s1")
        assertEquals(listOf("s2"), store.list().map { it.id })
    }

    @Test fun observe_reflectsWrites() = runTest {
        assertTrue(store.observe().first().isEmpty())
        store.upsert("s1", "A", "https://a/opds", false, "", null)
        assertEquals(1, store.observe().first().size)
    }
}
