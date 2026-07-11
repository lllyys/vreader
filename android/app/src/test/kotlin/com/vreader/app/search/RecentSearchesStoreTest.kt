package com.vreader.app.search

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.cancel
import kotlinx.coroutines.job
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Feature #128 WI-6 — [RecentSearchesStore] MRU history: most-recent-first ordering, case-insensitive
 * dedupe, cap 8, blank/whitespace no-op, oversized-query cap, atomic MRU under concurrent record,
 * malformed-payload safety, and persistence across store instances (same backing file).
 */
@RunWith(RobolectricTestRunner::class)
class RecentSearchesStoreTest {
    @get:Rule val tmp = TemporaryFolder()

    private lateinit var file: java.io.File
    private lateinit var scope: CoroutineScope
    private lateinit var dataStore: DataStore<Preferences>
    private lateinit var store: RecentSearchesStore

    @Before fun setUp() {
        file = tmp.newFile("recent_searches.preferences_pb")
        scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        dataStore = PreferenceDataStoreFactory.create(scope = scope) { file }
        store = RecentSearchesStore(dataStore)
    }

    @org.junit.After fun tearDown() { scope.cancel() }

    @Test fun record_prependsMostRecent() = runTest {
        store.record("alpha")
        store.record("beta")
        store.record("gamma")
        assertEquals(listOf("gamma", "beta", "alpha"), store.recents().first())
    }

    @Test fun record_caseInsensitiveDedupe_movesToFront() = runTest {
        store.record("Pride")
        store.record("prejudice")
        store.record("PRIDE")   // dupe of "Pride" (case-insensitive) — moved to front, not duplicated
        assertEquals(listOf("PRIDE", "prejudice"), store.recents().first())
    }

    @Test fun record_capsAtEight() = runTest {
        (1..12).forEach { store.record("q$it") }
        val recents = store.recents().first()
        assertEquals("capped at 8", 8, recents.size)
        assertEquals("most recent first", "q12", recents.first())
        assertFalse("oldest dropped", recents.contains("q1"))
    }

    @Test fun record_blankOrWhitespace_isNoOp() = runTest {
        store.record("")
        store.record("   ")
        store.record("\t\n")
        assertTrue("no blank recents recorded", store.recents().first().isEmpty())
    }

    @Test fun record_trimsQuery() = runTest {
        store.record("  spaced query  ")
        assertEquals(listOf("spaced query"), store.recents().first())
    }

    @Test fun record_oversizedQuery_isCappedNotCrashing() = runTest {
        val huge = "x".repeat(5000)
        store.record(huge)
        val stored = store.recents().first().single()
        assertEquals("capped to the code-point cap", RecentSearchesStore.MAX_QUERY_CODE_POINTS, stored.length)
    }

    @Test fun record_oversizedSurrogatePairs_neverSplitAPair() = runTest {
        // Non-BMP code points (surrogate pairs) — capping by CODE POINT must not slice a pair in half.
        val emoji = "😀"   // one code point, two chars
        val huge = emoji.repeat(300)  // 300 code points, 600 chars
        store.record(huge)
        val stored = store.recents().first().single()
        // Must be a valid string of whole code points, ≤ the cap.
        assertTrue("no dangling surrogate", stored.codePointCount(0, stored.length) <= RecentSearchesStore.MAX_QUERY_CODE_POINTS)
        assertEquals("capped to MAX code points (each 2 chars)", RecentSearchesStore.MAX_QUERY_CODE_POINTS * 2, stored.length)
    }

    @Test fun recents_persistAcrossInstances() = runTest {
        store.record("persisted-query")
        // Close the first DataStore (DataStore forbids two active instances on one file) before opening
        // a NEW store over the SAME backing file — it must see the recorded recents from disk. Join the
        // cancelled scope's job so DataStore's active-file registration is fully released first.
        scope.cancel()
        scope.coroutineContext.job.join()
        val scope2 = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        try {
            val store2 = RecentSearchesStore(PreferenceDataStoreFactory.create(scope = scope2) { file })
            assertEquals(listOf("persisted-query"), store2.recents().first())
        } finally {
            scope2.cancel()
        }
    }

    @Test fun record_concurrent_keepsAllAsMru() = runTest {
        // Atomic updateData must not lose an MRU entry under concurrent record.
        (1..8).map { i -> async { store.record("c$i") } }.awaitAll()
        val recents = store.recents().first()
        assertEquals("all 8 concurrent records survive (no lost update)", 8, recents.size)
        assertEquals("no duplicates", 8, recents.toSet().size)
        assertEquals("each concurrent query present", (1..8).map { "c$it" }.toSet(), recents.toSet())
    }

    @Test fun malformedStoredPayload_decodesToEmpty_noCrash() = runTest {
        // Write garbage directly under the store's key.
        dataStore.edit { it[stringPreferencesKey("recent_searches_json")] = "not-json-at-all {[" }
        assertTrue("malformed payload → empty, no crash", store.recents().first().isEmpty())
    }

    @Test fun clear_emptiesHistory() = runTest {
        store.record("a")
        store.record("b")
        store.clear()
        assertTrue(store.recents().first().isEmpty())
    }
}
