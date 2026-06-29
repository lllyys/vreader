package com.vreader.app.reader.settings

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
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
}
