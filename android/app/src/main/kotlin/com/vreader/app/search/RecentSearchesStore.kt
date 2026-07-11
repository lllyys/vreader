// Purpose: Device-local recent-search history for the library search screen — feature #128 WI-6.
// Stores an MRU list of recent query strings as JSON in a Preferences DataStore under
// noBackupFilesDir (recents are per-device, NOT in the backup contract — the ReaderSettingsStore /
// OpdsSourceStore precedent). `record` is atomic (DataStore.edit) so concurrent records never lose an
// MRU entry, case-insensitively de-duplicates, caps the list, ignores blank queries, and caps each
// stored query's length by CODE POINT (so a paste of a huge string can't bloat the store).
//
// Robustness: a malformed or oversized stored payload decodes to an empty list rather than crashing —
// recents are advisory UI, never load-bearing.
package com.vreader.app.search

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.serialization.json.Json

class RecentSearchesStore(
    private val dataStore: DataStore<Preferences>,
    private val json: Json = Json { ignoreUnknownKeys = true },
) {
    /** The MRU recent queries (most-recent first), capped at [MAX_RECENTS]. */
    fun recents(): Flow<List<String>> = dataStore.data.map(::read)

    /**
     * Records [query] as the most-recent search. Atomic (DataStore.edit) so overlapping records keep a
     * coherent MRU. Blank/whitespace-only queries are ignored; the stored form is the TRIMMED query
     * capped at [MAX_QUERY_CODE_POINTS] code points. A case-insensitive duplicate is moved to the front
     * (not duplicated); the list is capped at [MAX_RECENTS].
     */
    suspend fun record(query: String) {
        val trimmed = query.trim()
        if (trimmed.isEmpty()) return
        val capped = capByCodePoints(trimmed, MAX_QUERY_CODE_POINTS)
        dataStore.edit { prefs ->
            val current = read(prefs)
            // Case-insensitive dedupe (drop any prior spelling that matches), then prepend, then cap.
            val deduped = current.filterNot { it.equals(capped, ignoreCase = true) }
            val next = (listOf(capped) + deduped).take(MAX_RECENTS)
            prefs[KEY] = json.encodeToString(next)
        }
    }

    /** Clears the recent-search history. */
    suspend fun clear() {
        dataStore.edit { prefs -> prefs.remove(KEY) }
    }

    /** Decode the stored JSON list; a missing/malformed/oversized payload → empty (never crash). */
    private fun read(prefs: Preferences): List<String> {
        val raw = prefs[KEY] ?: return emptyList()
        return runCatching { json.decodeFromString<List<String>>(raw) }
            .getOrDefault(emptyList())
            // Defensive: drop blanks + re-cap in case an older/corrupt payload violated the invariants.
            .asSequence()
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .map { capByCodePoints(it, MAX_QUERY_CODE_POINTS) }
            .distinctBy { it.lowercase() }
            .take(MAX_RECENTS)
            .toList()
    }

    /** Truncates [s] to at most [max] Unicode code points (never splitting a surrogate pair). */
    private fun capByCodePoints(s: String, max: Int): String {
        if (s.length <= max) return s   // fast path: char count ≤ max ⇒ code points ≤ max
        val cpCount = s.codePointCount(0, s.length)
        if (cpCount <= max) return s
        val endIndex = s.offsetByCodePoints(0, max)
        return s.substring(0, endIndex)
    }

    companion object {
        const val MAX_RECENTS: Int = 8
        const val MAX_QUERY_CODE_POINTS: Int = 200
        private val KEY = stringPreferencesKey("recent_searches_json")
    }
}
