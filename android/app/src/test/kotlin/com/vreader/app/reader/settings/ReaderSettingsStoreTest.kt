package com.vreader.app.reader.settings

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.File

/**
 * Feature #129 WI-1 — [ReaderSettingsStore] persists the reader Display settings in DataStore: defaults
 * when unset, round-trips each field, clamps out-of-range writes, and the reactive [settings] flow emits
 * the latest. Robolectric (DataStore needs a real file + context); a fresh file per test.
 */
@RunWith(RobolectricTestRunner::class)
class ReaderSettingsStoreTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private lateinit var dataStore: DataStore<Preferences>
    private lateinit var store: ReaderSettingsStore

    @Before fun setUp() {
        val file = File(context.cacheDir, "reader-settings-${System.nanoTime()}.preferences_pb")
        dataStore = PreferenceDataStoreFactory.create { file }
        store = ReaderSettingsStore(dataStore)
    }

    @Test fun default_whenUnset() = runBlocking {
        assertEquals(ReaderSettings(), store.current())
    }

    @Test fun roundTrips_eachField() = runBlocking {
        store.setTheme(ReaderTheme.Dark)
        store.setFontFamily(ReaderFontFamily.Sans)
        store.setFontSize(22f)
        store.setLineSpacing(1.8f)
        store.setMargin(30f)

        val s = store.current()
        assertEquals(ReaderTheme.Dark, s.theme)
        assertEquals(ReaderFontFamily.Sans, s.fontFamily)
        assertEquals(22f, s.fontSizeSp, 1e-4f)
        assertEquals(1.8f, s.lineSpacing, 1e-4f)
        assertEquals(30f, s.marginDp, 1e-4f)
    }

    @Test fun clamps_outOfRange() = runBlocking {
        store.setFontSize(99f); assertEquals(26f, store.current().fontSizeSp, 1e-4f)   // max
        store.setFontSize(5f);  assertEquals(13f, store.current().fontSizeSp, 1e-4f)   // min
        store.setLineSpacing(3f);   assertEquals(2.0f, store.current().lineSpacing, 1e-4f)
        store.setLineSpacing(1.0f); assertEquals(1.3f, store.current().lineSpacing, 1e-4f)
        store.setMargin(100f); assertEquals(48f, store.current().marginDp, 1e-4f)
        store.setMargin(1f);   assertEquals(16f, store.current().marginDp, 1e-4f)
    }

    @Test fun clamp_sanitizesNonFinite() = runBlocking {
        // NaN/±Inf must not corrupt the store — they fall back to the defaults (the clamp is total).
        store.setFontSize(Float.NaN);                  assertEquals(ReaderSettings.DEFAULT_FONT_SIZE, store.current().fontSizeSp, 1e-4f)
        store.setLineSpacing(Float.POSITIVE_INFINITY); assertEquals(ReaderSettings.DEFAULT_LINE_SPACING, store.current().lineSpacing, 1e-4f)
        store.setMargin(Float.NaN);                    assertEquals(ReaderSettings.DEFAULT_MARGIN, store.current().marginDp, 1e-4f)
    }

    @Test fun settingsFlow_emitsTheLatest() = runBlocking {
        assertEquals(ReaderTheme.Paper, store.settings.first().theme)   // default
        store.setTheme(ReaderTheme.Sepia)
        assertEquals(ReaderTheme.Sepia, store.settings.first().theme)
    }

    // feature #129 WI-4 (Gate-4 High) — the store's write Mutex + DataStore make each setter's internal
    // read-modify-write atomic and serialized, so a burst of concurrent DIFFERENT-field writes (the exact
    // shape the reader produces — each sheet edit fires on its own appScope coroutine) can NEVER tear the
    // stored JSON: the final decode always holds a valid value for EVERY field, never a half-written blob
    // that falls back to defaults. Without serialization, two concurrent read-modify-write edits could
    // interleave and one clobbers the other's field.
    @Test fun concurrentDifferentFieldWrites_allLand_noTornState() = runBlocking {
        withContext(Dispatchers.Default) {
            listOf(
                async { store.setTheme(ReaderTheme.Dark) },
                async { store.setFontFamily(ReaderFontFamily.Sans) },
                async { store.setFontSize(24f) },
                async { store.setLineSpacing(1.9f) },
                async { store.setMargin(40f) },
            ).awaitAll()
        }
        // Every field committed — no interleaved edit dropped another field back to its default.
        val s = store.current()
        assertEquals(ReaderTheme.Dark, s.theme)
        assertEquals(ReaderFontFamily.Sans, s.fontFamily)
        assertEquals(24f, s.fontSizeSp, 1e-4f)
        assertEquals(1.9f, s.lineSpacing, 1e-4f)
        assertEquals(40f, s.marginDp, 1e-4f)
    }

    @Test fun concurrentSameFieldBurst_leavesAValidSubmittedValue() = runBlocking {
        // A rapid slider burst on ONE field: every write is a valid submitted value, and the committed
        // result is always one of them (never a garbage decode / lost enum). Serialized writes can't tear.
        val sizes = listOf(13f, 16f, 20f, 24f, 26f)
        withContext(Dispatchers.Default) {
            (0 until 40).map { i -> async { store.setFontSize(sizes[i % sizes.size]) } }.awaitAll()
        }
        assertTrue("committed size must be one of the submitted values", store.current().fontSizeSp in sizes)
    }

    // feature #129 WI-4 (Gate-4 High r2/r3) — latest-submission-wins for a same-field write regardless of
    // execution/lock-acquisition order. The submission order is a caller-supplied `order` (the reader
    // stamps it synchronously in the UI callback); inside the store a same-field write is DROPPED when a
    // newer `order` already committed. This test EXECUTES the writes in INVERTED order (the newer-order
    // write commits FIRST, then the older-order write runs LAST) and proves the older one is dropped —
    // exactly the multi-threaded-dispatcher reorder the reader can hit.
    @Test fun staleSameFieldWrite_isDropped_evenWhenItRunsLast() = runBlocking {
        // order=2 (newer) commits first; order=1 (older) runs AFTER and must be dropped.
        store.setFontSize(26f, order = 2L)
        assertEquals(26f, store.current().fontSizeSp, 1e-4f)
        store.setFontSize(13f, order = 1L)               // older submission, executed last
        assertEquals("the stale (lower-order) write must not overwrite the newer one",
            26f, store.current().fontSizeSp, 1e-4f)

        // And a strictly-newer write (order=3) DOES commit — the high-water only blocks OLDER ones.
        store.setFontSize(20f, order = 3L)
        assertEquals(20f, store.current().fontSizeSp, 1e-4f)
    }

    @Test fun perFieldHighWater_isIndependent_aStaleWriteInOneFieldDoesNotBlockAnother() = runBlocking {
        store.setFontSize(24f, order = 5L)               // font-size high-water = 5
        store.setMargin(40f, order = 2L)                 // margin high-water = 2 (its own track)
        // margin's older order (2) must NOT be blocked by font-size's newer order (5) — fields are independent.
        assertEquals(24f, store.current().fontSizeSp, 1e-4f)
        assertEquals(40f, store.current().marginDp, 1e-4f)
    }

    // feature #137 WI-1 — the reader "layout" (scroll vs paged) preference is wired exactly like `theme`:
    // stored by enum name (forward-compat), latest-submission-wins per field, and reflected in the flow.
    // Default is Scroll (iOS parity — the pre-#137 renderer is scroll-only; adding paged must NOT change
    // an untouched install's layout on upgrade).

    @Test fun layout_defaultsToScroll_whenUnset() = runBlocking {
        // Pinned product decision: absent any persisted value, the reader stays in scroll mode.
        assertEquals(ReaderLayout.Scroll, store.current().layout)
    }

    @Test fun setLayout_persistsAndRoundTrips() = runBlocking {
        store.setLayout(ReaderLayout.Paged)
        assertEquals(ReaderLayout.Paged, store.current().layout)
        store.setLayout(ReaderLayout.Scroll)
        assertEquals(ReaderLayout.Scroll, store.current().layout)
    }

    @Test fun settingsFlow_reflectsLayout() = runBlocking {
        assertEquals(ReaderLayout.Scroll, store.settings.first().layout)   // default
        store.setLayout(ReaderLayout.Paged)
        assertEquals(ReaderLayout.Paged, store.settings.first().layout)
    }

    @Test fun layout_unknownPersistedName_decodesToScrollDefault() = runBlocking {
        // Forward-compat: a garbage / older layout name (hand-edited or from a future build) must decode
        // to the default rather than throwing — mirror the theme enum-by-name behavior.
        store.setLayout(ReaderLayout.Paged)
        assertEquals(ReaderLayout.Paged, store.current().layout)
        // Simulate a future/garbage value landing in the persisted JSON via a valid write path first,
        // then corrupt the stored name and confirm it heals to the default on read.
        dataStore.edit { prefs ->
            val raw = prefs[stringPreferencesKey("reader_settings_json")]
            require(raw != null) { "expected persisted settings after setLayout" }
            prefs[stringPreferencesKey("reader_settings_json")] =
                raw.replace("\"${ReaderLayout.Paged.name}\"", "\"NoSuchLayout\"")
        }
        assertEquals(ReaderLayout.Scroll, store.current().layout)
    }

    @Test fun layout_staleSameFieldWrite_isDropped_evenWhenItRunsLast() = runBlocking {
        // order=2 (newer) commits first; order=1 (older) runs AFTER and must be dropped (latest-wins).
        store.setLayout(ReaderLayout.Paged, order = 2L)
        assertEquals(ReaderLayout.Paged, store.current().layout)
        store.setLayout(ReaderLayout.Scroll, order = 1L)          // older submission, executed last
        assertEquals("the stale (lower-order) layout write must not overwrite the newer one",
            ReaderLayout.Paged, store.current().layout)
        // A strictly-newer write (order=3) DOES commit — the high-water only blocks OLDER ones.
        store.setLayout(ReaderLayout.Scroll, order = 3L)
        assertEquals(ReaderLayout.Scroll, store.current().layout)
    }

    @Test fun layout_highWater_isIndependentOfOtherFields() = runBlocking {
        store.setTheme(ReaderTheme.Dark, order = 5L)              // theme high-water = 5
        store.setLayout(ReaderLayout.Paged, order = 2L)          // layout high-water = 2 (its own track)
        // layout's older order (2) must NOT be blocked by theme's newer order (5) — fields are independent.
        assertEquals(ReaderTheme.Dark, store.current().theme)
        assertEquals(ReaderLayout.Paged, store.current().layout)
    }
}
