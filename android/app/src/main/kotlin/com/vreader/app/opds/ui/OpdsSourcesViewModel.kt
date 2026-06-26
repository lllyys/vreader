// Purpose: feature #120 WI-2 (#110 Phase 3) — drives the OPDS catalog list + add/edit sheet: observes
// OpdsSourceStore for the list, owns the editor form, runs Test Connection against the LIVE form
// (a transient origin-scoped OpdsClient built from the form + creds, no save first — mirrors the
// #118 AiSettingsViewModel test path), and saves/deletes. The password is never logged.
package com.vreader.app.opds.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.vreader.app.opds.OpdsClient
import com.vreader.app.opds.OpdsError
import com.vreader.app.opds.OpdsSource
import com.vreader.app.opds.OpdsSourceStore
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import com.vreader.app.opds.OpdsFeed
import java.net.URL
import java.util.UUID

/** The Test-Connection fetch seam — a transient feed fetch. Production wraps an origin-scoped
 *  OpdsClient; tests supply a fake. (OpdsClient is final, so the VM depends on this seam, not it.) */
fun interface OpdsFeedTester {
    suspend fun fetchFeed(url: String): OpdsFeed
}

class OpdsSourcesViewModel(
    private val store: OpdsSourceStore,
    private val clientDispatcher: CoroutineDispatcher = Dispatchers.IO,
    // A transient fetcher for Test Connection — origin-scoped, so the entered credential is sent only
    // same-origin (the #117/WI-1 contract). Injected so tests can supply a fake.
    private val testerFactory: (username: String?, password: String?, authOrigin: String?) -> OpdsFeedTester =
        { u, p, o -> OpdsFeedTester { url -> OpdsClient(username = u, password = p, authOrigin = o).fetchFeed(url) } },
) : ViewModel() {

    val listState: StateFlow<OpdsSourceListState> = store.observe()
        .map { sources -> OpdsSourceListState(sources.map(::toRow)) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), OpdsSourceListState())

    private val _edit = MutableStateFlow<OpdsEditState?>(null)
    val editState: StateFlow<OpdsEditState?> = _edit

    // Bumped whenever the editor opens/closes or a new test starts — an in-flight test result is
    // applied only if its generation still matches (so a stale Ok/Fail can't land on a re-opened or
    // closed form). Mirrors AiSettingsViewModel.testGen.
    private var testGen = 0

    /** Open the add sheet, optionally prefilled (the empty-state "Try one of these" shortcuts). */
    fun openAdd(name: String = "", url: String = "") {
        testGen++
        _edit.value = OpdsEditState(editMode = false, name = name, url = url)
    }

    fun openEdit(id: String) = viewModelScope.launch {
        val s = store.list().firstOrNull { it.id == id } ?: return@launch
        testGen++
        _edit.value = OpdsEditState(
            editMode = true, id = s.id, name = s.name, url = s.url,
            requiresAuth = s.requiresAuth, username = s.username,
            keyAlreadySaved = s.requiresAuth && s.encryptedPassword.isNotBlank(),
        )
    }

    fun close() { testGen++; _edit.value = null }

    fun update(transform: (OpdsEditState) -> OpdsEditState) { _edit.value = _edit.value?.let(transform) }

    fun test() {
        val s = _edit.value ?: return
        if (!s.canTest) return
        val gen = ++testGen
        // Snapshot the identifying inputs this test exercises. A result is applied only if these are
        // unchanged when it returns — so a stale Ok/Fail for catalog A can't land after the user has
        // edited the form to catalog B. (Setting test/testMessage doesn't touch these fields, so the
        // `testing` mutation below never invalidates its own test.)
        val url = s.url.trim()
        val sig = TestSignature(url, s.requiresAuth, s.username, s.password)
        update { it.copy(test = OpdsConnTest.testing, testMessage = "") }
        viewModelScope.launch {
            val outcome = withContext(clientDispatcher) {
                val user = if (s.requiresAuth && s.username.isNotBlank()) s.username else null
                val pass = if (user != null) resolveTestPassword(s) else null  // no creds → don't decrypt
                val origin = if (user != null) originOf(url) else null
                runCatching { testerFactory(user, pass, origin).fetchFeed(url) }
            }
            if (gen != testGen) return@launch  // superseded by a newer test / form open / close
            val cur = _edit.value ?: return@launch
            if (signatureOf(cur) != sig) {     // the form's inputs changed mid-test → discard
                update { it.copy(test = OpdsConnTest.idle, testMessage = "") }
                return@launch
            }
            update { st ->
                outcome.fold(
                    onSuccess = { st.copy(test = OpdsConnTest.ok, testMessage = "Connected — the catalog responded successfully.") },
                    onFailure = { e -> st.copy(test = OpdsConnTest.fail, testMessage = failureMessage(e)) },
                )
            }
        }
    }

    private data class TestSignature(val url: String, val requiresAuth: Boolean, val username: String, val password: String)
    private fun signatureOf(s: OpdsEditState) = TestSignature(s.url.trim(), s.requiresAuth, s.username, s.password)

    fun save() {
        val s = _edit.value ?: return
        if (!s.canSave) return
        viewModelScope.launch {
            store.upsert(
                id = s.id ?: UUID.randomUUID().toString(),
                name = s.name.trim(), url = s.url.trim(),
                requiresAuth = s.requiresAuth, username = s.username.trim(),
                password = s.password.ifBlank { null },  // blank on edit = keep existing
            )
            _edit.value = null
        }
    }

    fun delete() {
        val id = _edit.value?.id ?: return
        viewModelScope.launch { store.delete(id); _edit.value = null }
    }

    // ── helpers ──────────────────────────────────────────────────────

    /** The password to test with: the freshly-entered one, else (edit) the stored one, else null. */
    private suspend fun resolveTestPassword(s: OpdsEditState): String? = when {
        !s.requiresAuth -> null
        s.password.isNotBlank() -> s.password
        s.id != null -> store.list().firstOrNull { it.id == s.id }?.let { store.password(it) }
        else -> null
    }

    private fun toRow(s: OpdsSource): OpdsSourceRow {
        val host = hostOf(s.url)
        // v1 has no persisted per-source reachability probe (a follow-on). The dot reflects CONFIG,
        // not a live status: a sign-in catalog gets the amber auth dot + a "Sign-in required · <host>"
        // detail (honest — we don't claim a 401 we haven't observed); a public catalog gets a muted
        // dot + the host. Once persisted test status lands, ok/off replace this config-derived state.
        val status = if (s.requiresAuth) OpdsSourceStatus.auth else OpdsSourceStatus.unknown
        val detail = if (s.requiresAuth) "Sign-in required · $host" else host
        return OpdsSourceRow(id = s.id, name = s.name, host = host, status = status, detail = detail)
    }

    private fun hostOf(url: String): String = runCatching {
        val u = URL(url)
        val port = if (u.port != -1 && u.port != u.defaultPort) ":${u.port}" else ""
        val path = u.path.trimEnd('/')
        (u.host + port + path).ifBlank { url }
    }.getOrDefault(url)

    private fun originOf(url: String): String? = runCatching {
        val u = URL(url); val port = if (u.port == -1) u.defaultPort else u.port
        "${u.protocol.lowercase()}://${u.host.lowercase()}:$port"
    }.getOrNull()

    private fun failureMessage(e: Throwable): String = when (e) {
        is OpdsError.Http -> when (e.code) {
            401, 403 -> "Failed: ${e.code} — sign-in required or rejected."
            404 -> "Failed: 404 — no catalog at this URL."
            else -> "Failed: HTTP ${e.code}."
        }
        is OpdsError.InsecureAuth -> "Sign-in needs https or a local-network address."
        is OpdsError.InvalidUrl -> "That doesn't look like a valid URL."
        is OpdsError.InvalidXml, is OpdsError.EmptyData -> "That URL didn't return an OPDS feed."
        is OpdsError.Network -> "Couldn't reach the catalog — check the URL and your connection."
        else -> e.message ?: "Connection failed."
    }
}
