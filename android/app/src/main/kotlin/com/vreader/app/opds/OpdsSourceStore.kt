// Purpose: feature #120 WI-1 (#110 Phase 3) — persists saved OPDS catalogs. Name/URL/requiresAuth/
// username live in DataStore as a JSON list; the optional password is kept ONLY as a SecretCipher
// token (a DISTINCT AndroidKeyStore alias from WebDAV/AI — `vreader.opds.password`). Reuses the #116
// WebDavServerStore DataStore+cipher pattern. `clientFor(source)` builds an origin-scoped #117
// OpdsClient. The password is never logged.
package com.vreader.app.opds

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.vreader.app.backup.net.KeystoreSecretCipher
import com.vreader.app.backup.net.SecretCipher
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.net.URL

/** A saved OPDS catalog. `encryptedPassword` is a [SecretCipher] token (blank when no auth). */
@Serializable
data class OpdsSource(
    val id: String,
    val name: String,
    val url: String,
    val requiresAuth: Boolean = false,
    val username: String = "",
    val encryptedPassword: String = "",
)

class OpdsSourceStore(
    private val dataStore: DataStore<Preferences>,
    private val cipher: SecretCipher = KeystoreSecretCipher(ALIAS),
    private val json: Json = Json { ignoreUnknownKeys = true; encodeDefaults = true },
) {
    suspend fun list(): List<OpdsSource> = read(dataStore.data.first())
    fun observe(): Flow<List<OpdsSource>> = dataStore.data.map(::read)

    /**
     * Insert/update by [id]. [password] is the PLAINTEXT to encrypt; pass null to keep the existing
     * (edit without changing it). When [requiresAuth] is false the username/password are CLEARED.
     */
    suspend fun upsert(
        id: String,
        name: String,
        url: String,
        requiresAuth: Boolean,
        username: String,
        password: String?,
    ): OpdsSource {
        lateinit var saved: OpdsSource
        dataStore.edit { prefs ->
            val cur = read(prefs)
            val existing = cur.firstOrNull { it.id == id }
            saved = if (!requiresAuth) {
                OpdsSource(id, name, url, requiresAuth = false)  // auth off → no creds stored
            } else {
                val enc = when {
                    password != null -> cipher.encrypt(password)
                    existing != null && existing.requiresAuth -> existing.encryptedPassword
                    else -> ""  // auth on but no password yet (the user can still browse public sections)
                }
                OpdsSource(id, name, url, requiresAuth = true, username = username, encryptedPassword = enc)
            }
            prefs[KEY] = json.encodeToString(cur.filterNot { it.id == id } + saved)
        }
        return saved
    }

    suspend fun delete(id: String) {
        dataStore.edit { prefs -> prefs[KEY] = json.encodeToString(read(prefs).filterNot { it.id == id }) }
    }

    /** The decrypted password for [source], or null if it has no auth / no password. */
    fun password(source: OpdsSource): String? =
        if (source.requiresAuth && source.encryptedPassword.isNotBlank()) cipher.decrypt(source.encryptedPassword) else null

    /** Build a #117 OpdsClient scoped to this catalog's origin (so auth never leaks cross-origin). */
    fun clientFor(source: OpdsSource): OpdsClient {
        val user = if (source.requiresAuth && source.username.isNotBlank()) source.username else null
        // Decrypt ONLY when a usable auth client will actually be built — a corrupt/stale token on a
        // source with no username would otherwise throw even though no auth header would be sent.
        val pass = if (user != null) password(source) else null
        return OpdsClient(username = user, password = pass, authOrigin = if (user != null) originOf(source.url) else null)
    }

    private fun originOf(url: String): String? = runCatching {
        val u = URL(url); val port = if (u.port == -1) u.defaultPort else u.port
        "${u.protocol.lowercase()}://${u.host.lowercase()}:$port"
    }.getOrNull()

    private fun read(prefs: Preferences): List<OpdsSource> {
        val raw = prefs[KEY] ?: return emptyList()
        return runCatching { json.decodeFromString<List<OpdsSource>>(raw) }.getOrDefault(emptyList())
    }

    companion object {
        const val ALIAS = "vreader.opds.password"
        private val KEY = stringPreferencesKey("opds_sources_json")
    }
}
