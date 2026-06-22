// Purpose: feature #118 WI-1 (#110 Phase 3) — persists saved AI provider profiles + the active
// selection. Profile metadata (name/kind/baseUrl/model/temperature/maxTokens) lives in DataStore
// as a JSON list; the API key is kept ONLY as a SecretCipher token (the #116 KeystoreSecretCipher).
// Reuses the #116 WebDavServerStore DataStore+SecretCipher credential pattern, adding an active-id
// and a request-start `snapshot()` (a chat/test reads one consistent profile, not live mid-request
// store reads). The key + auth headers are NEVER logged.
package com.vreader.app.ai

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.vreader.app.backup.net.SecretCipher
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** A saved AI provider. `encryptedApiKey` is a [SecretCipher] token, never plaintext. */
@Serializable
data class AiProviderProfile(
    val id: String,
    val name: String,
    val kind: AiProviderKind,
    val baseUrl: String,
    val model: String,
    val temperature: Double = 0.7,
    val maxTokens: Int = 2048,
    val encryptedApiKey: String,
)

/** A consistent point-in-time view: the profiles + which is active. */
data class AiProviderSnapshot(val profiles: List<AiProviderProfile>, val activeId: String?) {
    val active: AiProviderProfile? get() = profiles.firstOrNull { it.id == activeId }
}

@Serializable
private data class AiStoreState(val profiles: List<AiProviderProfile> = emptyList(), val activeId: String? = null)

class AiProviderStore(
    private val dataStore: DataStore<Preferences>,
    private val cipher: SecretCipher,
    private val json: Json = Json { ignoreUnknownKeys = true; encodeDefaults = true },
) {
    /** One consistent profiles + active-id view (read once at request start). */
    suspend fun snapshot(): AiProviderSnapshot = read(dataStore.data.first()).toSnapshot()

    fun observe(): Flow<AiProviderSnapshot> = dataStore.data.map { read(it).toSnapshot() }

    suspend fun list(): List<AiProviderProfile> = snapshot().profiles

    suspend fun activeProfile(): AiProviderProfile? = snapshot().active

    /**
     * Insert/update a profile by [id]. [apiKey] is the PLAINTEXT to encrypt; pass null on an edit
     * that leaves the key unchanged (the existing ciphertext is kept). A brand-new id REQUIRES a
     * key. The first profile added becomes active. Returns the saved profile (key encrypted).
     */
    suspend fun upsert(
        id: String,
        name: String,
        kind: AiProviderKind,
        baseUrl: String,
        model: String,
        temperature: Double,
        maxTokens: Int,
        apiKey: String?,
    ): AiProviderProfile {
        lateinit var saved: AiProviderProfile
        dataStore.edit { prefs ->
            val cur = read(prefs)
            val existing = cur.profiles.firstOrNull { it.id == id }
            val encrypted = when {
                apiKey != null -> cipher.encrypt(apiKey)
                existing != null -> existing.encryptedApiKey  // unchanged on edit
                else -> throw IllegalArgumentException("a new provider ($id) requires an API key")
            }
            saved = AiProviderProfile(id, name, kind, baseUrl, model, temperature, maxTokens, encrypted)
            val next = cur.profiles.filterNot { it.id == id } + saved
            val activeId = cur.activeId ?: id  // first provider becomes active
            prefs[KEY] = json.encodeToString(AiStoreState(next, activeId))
        }
        return saved
    }

    /** Remove a profile. If it was active, the active selection moves to the first remaining (or null). */
    suspend fun delete(id: String) {
        dataStore.edit { prefs ->
            val cur = read(prefs)
            val next = cur.profiles.filterNot { it.id == id }
            val activeId = if (cur.activeId == id) next.firstOrNull()?.id else cur.activeId
            prefs[KEY] = json.encodeToString(AiStoreState(next, activeId))
        }
    }

    /** Select the active provider (no-op if the id isn't present). */
    suspend fun setActive(id: String) {
        dataStore.edit { prefs ->
            val cur = read(prefs)
            if (cur.profiles.any { it.id == id }) prefs[KEY] = json.encodeToString(cur.copy(activeId = id))
        }
    }

    /** Decrypt the key from a CAPTURED [profile] — snapshot-consistent (no live store read). The
     *  chat/test request path uses THIS with a profile from a single [snapshot], so it can't pair
     *  snapshot metadata with a concurrently-edited/deleted key. */
    fun apiKey(profile: AiProviderProfile): String = cipher.decrypt(profile.encryptedApiKey)

    /** The decrypted API key for [id] via a live read, or null if absent. Convenience for UI flows
     *  that aren't mid-request; the request path should prefer [apiKey] (profile). */
    suspend fun apiKey(id: String): String? =
        list().firstOrNull { it.id == id }?.let { cipher.decrypt(it.encryptedApiKey) }

    private fun read(prefs: Preferences): AiStoreState {
        val raw = prefs[KEY] ?: return AiStoreState()
        return runCatching { json.decodeFromString<AiStoreState>(raw) }.getOrDefault(AiStoreState())
    }

    private fun AiStoreState.toSnapshot() = AiProviderSnapshot(profiles, activeId)

    companion object {
        private val KEY = stringPreferencesKey("ai_providers_json")
    }
}
