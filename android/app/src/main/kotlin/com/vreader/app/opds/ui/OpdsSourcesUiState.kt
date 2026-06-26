// Purpose: feature #120 WI-2 (#110 Phase 3) — UI state for the OPDS source-list + add/edit surfaces
// (design `vreader-opds.jsx` `OpdsSourceList` + `OpdsAddSheet`). Stateless composables render a pure
// function of these; the ViewModel owns them. The password is never held here in plaintext beyond
// the live edit form (mirrors the #118 `AiEditState` contract).
package com.vreader.app.opds.ui

/** Test-connection state for the add sheet's Connection section (the design's idle/testing/ok/fail). */
enum class OpdsConnTest { idle, testing, ok, fail }

/** A saved-catalog row's last-known reachability dot. `unknown` = not yet tested this session. */
enum class OpdsSourceStatus { ok, auth, off, unknown }

/** One row in the catalog list: name + host (or the rejection reason) + a status dot. */
data class OpdsSourceRow(
    val id: String,
    val name: String,
    val host: String,          // host+path, e.g. "standardebooks.org/opds"
    val status: OpdsSourceStatus,
    val detail: String,        // host when ok/unknown, e.g. "401 — sign-in required" when auth
)

/** The catalog-list screen state. */
data class OpdsSourceListState(
    val sources: List<OpdsSourceRow> = emptyList(),
) {
    val empty: Boolean get() = sources.isEmpty()
}

/** The add/edit catalog form state (the `OpdsAddSheet` contract). */
data class OpdsEditState(
    val editMode: Boolean = false,
    val id: String? = null,
    val name: String = "",
    val url: String = "",
    val requiresAuth: Boolean = false,
    val username: String = "",
    val password: String = "",            // entered now (blank in edit = keep existing)
    val keyAlreadySaved: Boolean = false, // edit mode with a stored password
    val test: OpdsConnTest = OpdsConnTest.idle,
    val testMessage: String = "",
) {
    /** canSave = a name and a URL. (Auth is optional — a user may save a public catalog, or save
     *  one needing sign-in and add the password later.) */
    val canSave: Boolean get() = name.isNotBlank() && url.isNotBlank()
    /** Test is enabled once a URL is present — auth is optional (browse a public feed). */
    val canTest: Boolean get() = url.isNotBlank() && test != OpdsConnTest.testing
}
