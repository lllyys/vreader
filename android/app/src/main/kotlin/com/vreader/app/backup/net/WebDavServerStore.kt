// Purpose: feature #116 WI-5 (#110 Phase 3) — persists saved WebDAV server profiles. URL / user /
// name / wifiOnly live in DataStore as a JSON list; the password is kept only as a SecretCipher
// token (AndroidKeyStore AES-GCM in production). The WebDavBackupService (WI-5b) reads a profile +
// decrypts its password to build a WebDavClient. Chosen over EncryptedSharedPreferences (Gate-2
// Low-2). All ops suspend; `observe()` is reactive for the #114 server-list UI.
package com.vreader.app.backup.net

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** A saved server. `encryptedPassword` is a [SecretCipher] token, never plaintext. */
@Serializable
data class WebDavServerProfile(
    val id: String,
    val name: String,
    val baseUrl: String,
    val username: String,
    val encryptedPassword: String,
    val wifiOnly: Boolean,
)

class WebDavServerStore(
    private val dataStore: DataStore<Preferences>,
    private val cipher: SecretCipher,
    private val json: Json = Json { ignoreUnknownKeys = true; encodeDefaults = true },
) {
    /** All saved profiles (password still encrypted). */
    suspend fun list(): List<WebDavServerProfile> = read(dataStore.data.first())

    /** Reactive list for the server-list UI. */
    fun observe(): Flow<List<WebDavServerProfile>> = dataStore.data.map(::read)

    /**
     * Inserts or updates a profile by [id]. [password] is the PLAINTEXT to encrypt; pass null on an
     * edit that leaves the password unchanged (the existing ciphertext is kept). Returns the saved
     * profile (password encrypted). Throws if [password] is null for a brand-new id.
     */
    suspend fun upsert(
        id: String,
        name: String,
        baseUrl: String,
        username: String,
        password: String?,
        wifiOnly: Boolean,
    ): WebDavServerProfile {
        lateinit var saved: WebDavServerProfile
        dataStore.edit { prefs ->
            val current = read(prefs)
            val existing = current.firstOrNull { it.id == id }
            val encrypted = when {
                password != null -> cipher.encrypt(password)
                existing != null -> existing.encryptedPassword  // unchanged on edit
                else -> throw IllegalArgumentException("a new server ($id) requires a password")
            }
            saved = WebDavServerProfile(id, name, baseUrl, username, encrypted, wifiOnly)
            val next = current.filterNot { it.id == id } + saved
            prefs[KEY] = json.encodeToString(next)
        }
        return saved
    }

    /** Removes a profile (no-op if absent). */
    suspend fun delete(id: String) {
        dataStore.edit { prefs ->
            val next = read(prefs).filterNot { it.id == id }
            prefs[KEY] = json.encodeToString(next)
        }
    }

    /** The decrypted password for [id], or null if the profile doesn't exist. */
    suspend fun password(id: String): String? =
        list().firstOrNull { it.id == id }?.let { cipher.decrypt(it.encryptedPassword) }

    private fun read(prefs: Preferences): List<WebDavServerProfile> {
        val raw = prefs[KEY] ?: return emptyList()
        return runCatching { json.decodeFromString<List<WebDavServerProfile>>(raw) }.getOrDefault(emptyList())
    }

    companion object {
        private val KEY = stringPreferencesKey("webdav_servers_json")
    }
}
