// Purpose: feature #131 WI-4a — RED-first JVM tests for BilingualAiReadiness, the
// provider+key readiness gate. Asserts: active profile + decryptable non-empty key →
// true; NO active profile even with profiles present → false (the activeId-null case);
// activeId null → false; an empty decrypted key → false; and a cipher/keystore decrypt
// throw → false (never a crash). Uses a real AiProviderStore over a temp DataStore + a
// controllable fake cipher (the AiProviderStoreTest precedent).
package com.vreader.app.bilingual

import com.vreader.app.ai.AiProviderKind
import com.vreader.app.ai.AiProviderProfile
import com.vreader.app.ai.AiProviderSnapshot
import com.vreader.app.ai.AiProviderStore
import com.vreader.app.backup.net.SecretCipher
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class BilingualAiReadinessTest {

    @get:Rule val tmp = TemporaryFolder()

    private class FakeCipher(var throwOnDecrypt: Boolean = false) : SecretCipher {
        override fun encrypt(plaintext: String) = "enc($plaintext)"
        override fun decrypt(token: String): String {
            if (throwOnDecrypt) throw IllegalStateException("keystore unavailable")
            return token.removePrefix("enc(").removeSuffix(")")
        }
    }

    private lateinit var dataStore: DataStore<Preferences>
    private lateinit var cipher: FakeCipher
    private lateinit var store: AiProviderStore
    private lateinit var readiness: BilingualAiReadiness

    @Before fun setUp() {
        dataStore = PreferenceDataStoreFactory.create { tmp.newFile("ai.preferences_pb") }
        cipher = FakeCipher()
        store = AiProviderStore(dataStore, cipher)
        readiness = BilingualAiReadiness(store)
    }

    private fun profile(id: String, key: String) = AiProviderProfile(
        id = id,
        name = "P",
        kind = AiProviderKind.openAiCompatible,
        baseUrl = "https://x/",
        model = "m",
        encryptedApiKey = cipher.encrypt(key),
    )

    // ── active + non-empty decryptable key → true ──

    @Test fun activeWithNonEmptyKey_isReady() = runTest {
        val snapshot = AiProviderSnapshot(listOf(profile("p1", "s3cret")), activeId = "p1")
        assertTrue(readiness.resolve(snapshot))
    }

    // ── profiles present but NONE active (activeId null) → false ──

    @Test fun noActiveWithProfilesPresent_isNotReady() = runTest {
        val snapshot = AiProviderSnapshot(
            profiles = listOf(profile("p1", "s3cret"), profile("p2", "another")),
            activeId = null,                                 // profiles exist, none active
        )
        assertFalse(readiness.resolve(snapshot))
    }

    // ── activeId null (no profiles at all) → false ──

    @Test fun activeIdNull_emptyProfiles_isNotReady() = runTest {
        val snapshot = AiProviderSnapshot(profiles = emptyList(), activeId = null)
        assertFalse(readiness.resolve(snapshot))
    }

    // ── activeId points at a missing profile → false (active == null) ──

    @Test fun activeIdMissingProfile_isNotReady() = runTest {
        val snapshot = AiProviderSnapshot(listOf(profile("p1", "s3cret")), activeId = "ghost")
        assertFalse(readiness.resolve(snapshot))
    }

    // ── empty decrypted key → false ──

    @Test fun emptyKey_isNotReady() = runTest {
        val snapshot = AiProviderSnapshot(listOf(profile("p1", key = "")), activeId = "p1")
        assertFalse(readiness.resolve(snapshot))
    }

    // ── cipher/keystore decrypt throw → false, never a crash ──

    @Test fun cipherThrow_isNotReady_noCrash() = runTest {
        val snapshot = AiProviderSnapshot(listOf(profile("p1", "s3cret")), activeId = "p1")
        cipher.throwOnDecrypt = true
        assertFalse(readiness.resolve(snapshot))             // must not throw
    }
}
