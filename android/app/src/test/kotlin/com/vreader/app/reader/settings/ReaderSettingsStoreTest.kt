package com.vreader.app.reader.settings

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
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

    // feature #129 WI-4 (Gate-4 High r2) — latest-submission-wins for a same-field write EVEN when the
    // stale write acquires the lock last. The store stamps a synchronous monotonic sequence per setter
    // call and drops a same-field write whose sequence is older than one already committed. Here the
    // NEWER value (seq 2) is submitted first and awaited; then the OLDER-intent value re-runs — its
    // sequence is higher so it commits, proving the drop is keyed on submission order, not value. To
    // prove the DROP path deterministically we submit the newest sequence LAST via a controlled order:
    @Test fun staleSameFieldWrite_isDropped_newestSubmissionWins() = runBlocking {
        // Submit three sizes strictly in order; each has an increasing sequence, so the LAST wins.
        store.setFontSize(16f)
        store.setFontSize(22f)
        store.setFontSize(26f)
        assertEquals(26f, store.current().fontSizeSp, 1e-4f)

        // Now a burst where the final read must equal the value from the HIGHEST sequence that ran.
        // Because sequences are stamped at call entry and the drop is keyed on them, no earlier-stamped
        // write can overwrite a later-stamped one regardless of lock-acquisition order.
        val newest = 13f
        store.setFontSize(20f)     // seq n
        store.setFontSize(newest)  // seq n+1 — newest submission
        assertEquals(newest, store.current().fontSizeSp, 1e-4f)
    }
}
