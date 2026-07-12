// Purpose: feature #131 WI-5 — RED-first JVM tests for PerBookBilingualStore, the
// per-book bilingual config DataStore (enabled / targetLanguage / granularity, keyed by
// the book fingerprint key). Asserts: defaults when unset; each field round-trips; two
// books are isolated; granularity ALWAYS persists as `paragraph` in v1 (a `sentence`
// write is normalized to `paragraph`); there is NO `style` field (the persisted shape
// carries exactly enabled/targetLanguage/granularity). Robolectric (DataStore needs a
// real file + context); a fresh file per test (the ReaderSettingsStoreTest precedent).
package com.vreader.app.bilingual

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.edit
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.File

@RunWith(RobolectricTestRunner::class)
class PerBookBilingualStoreTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private lateinit var dataStore: DataStore<Preferences>
    private lateinit var store: PerBookBilingualStore

    @Before fun setUp() {
        val file = File(context.cacheDir, "per-book-bilingual-${System.nanoTime()}.preferences_pb")
        dataStore = PreferenceDataStoreFactory.create { file }
        store = PerBookBilingualStore(dataStore)
    }

    // ── defaults when unset ──

    @Test fun default_whenUnset() = runBlocking {
        val cfg = store.read("book-a")
        assertFalse("bilingual is off by default", cfg.enabled)
        assertEquals("Chinese", cfg.targetLanguage)                       // BILINGUAL_LANGS[0]
        assertEquals(TranslationGranularity.paragraph, cfg.granularity)
    }

    // ── each field round-trips ──

    @Test fun roundTrips_eachField() = runBlocking {
        store.write("book-a", PerBookBilingualConfig(enabled = true, targetLanguage = "Japanese", granularity = TranslationGranularity.paragraph))
        val cfg = store.read("book-a")
        assertTrue(cfg.enabled)
        assertEquals("Japanese", cfg.targetLanguage)
        assertEquals(TranslationGranularity.paragraph, cfg.granularity)
    }

    // ── two books are isolated by their fingerprint key ──

    @Test fun perBookIsolation() = runBlocking {
        store.write("book-a", PerBookBilingualConfig(enabled = true, targetLanguage = "French", granularity = TranslationGranularity.paragraph))
        store.write("book-b", PerBookBilingualConfig(enabled = false, targetLanguage = "German", granularity = TranslationGranularity.paragraph))

        val a = store.read("book-a")
        val b = store.read("book-b")
        assertTrue(a.enabled)
        assertEquals("French", a.targetLanguage)
        assertFalse(b.enabled)
        assertEquals("German", b.targetLanguage)
    }

    // ── granularity is PINNED to paragraph in v1: a `sentence` write is normalized ──

    @Test fun granularityPinnedParagraph_evenIfSentenceRequested() = runBlocking {
        store.write("book-a", PerBookBilingualConfig(enabled = true, targetLanguage = "Chinese", granularity = TranslationGranularity.sentence))
        // The store NEVER persists `sentence` in v1 (round-4 H3): it is normalized to paragraph.
        assertEquals(TranslationGranularity.paragraph, store.read("book-a").granularity)
    }

    // ── a raw hand-edited / older on-disk `sentence` value decodes to paragraph (Gate-4 Low) ──

    @Test fun rawSentenceOnDisk_decodesToParagraph() = runBlocking {
        // Write a legacy/hand-edited JSON blob carrying granularity="sentence" DIRECTLY into
        // the DataStore key (bypassing the store's write normalization) to prove the READ path
        // also forces paragraph.
        val key = androidx.datastore.preferences.core.stringPreferencesKey("bilingual_per_book_json:book-a")
        dataStore.edit { it[key] = """{"enabled":true,"targetLanguage":"Chinese","granularity":"sentence"}""" }
        assertEquals(TranslationGranularity.paragraph, store.read("book-a").granularity)
    }

    // ── the reactive flow emits per-book updates ──

    @Test fun observe_emitsLatestForBook() = runBlocking {
        assertFalse(store.observe("book-a").first().enabled)                 // default
        store.write("book-a", PerBookBilingualConfig(enabled = true, targetLanguage = "Korean", granularity = TranslationGranularity.paragraph))
        val cfg = store.observe("book-a").first()
        assertTrue(cfg.enabled)
        assertEquals("Korean", cfg.targetLanguage)
    }

    // ── no `style` field: the config's declared members are exactly enabled/targetLanguage/granularity ──

    @Test fun noStyleField() {
        // Reflection guard: the persisted config carries NO `style` member (Style descoped, §3).
        val members = PerBookBilingualConfig::class.members.map { it.name }.toSet()
        assertFalse("PerBookBilingualConfig must NOT carry a `style` field", members.contains("style"))
        assertTrue(members.contains("enabled"))
        assertTrue(members.contains("targetLanguage"))
        assertTrue(members.contains("granularity"))
    }
}
