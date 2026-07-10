package com.vreader.app.reader

import androidx.compose.ui.graphics.toArgb
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.VReaderApp
import com.vreader.app.reader.settings.ReaderTheme
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * feature #129 WI-5 — the EPUB (Readium) reader applies the "Display" settings live. Instrumented
 * because EpubNavigatorFragment renders in a real WebView (not Robolectric). Seeds a non-default theme
 * in the global ReaderSettingsStore, opens the reader, and asserts the navigator's applied background
 * ARGB matches that theme (open-time application), then changes the theme mid-read and asserts the
 * applied background updates (live re-submission via submitPreferences).
 */
@RunWith(AndroidJUnit4::class)
class EpubDisplaySettingsConnectedTest {

    @Test
    fun storedTheme_appliesToNavigatorOnOpen_andUpdatesLive() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val appContext = instrumentation.targetContext
        val app = appContext.applicationContext as VReaderApp
        val store = app.container.readerSettingsStore

        // Seed a non-default theme BEFORE opening so the open-time initialPrefs carry it.
        runBlocking { store.setTheme(ReaderTheme.Dark) }
        val book = stageBook(appContext, instrumentation.context, app)

        ActivityScenario.launch<ReaderActivity>(ReaderActivity.intent(appContext, book.fingerprintKey)).use { scenario ->
            // wait for the navigator to render + apply settings
            var applied: Int? = null
            repeat(60) {
                scenario.onActivity { applied = it.appliedBackgroundArgb() }
                if (applied != null) return@repeat
                Thread.sleep(200)
            }
            assertNotNull("navigator applied a background color", applied)
            assertEquals(
                "the stored Dark theme background reached the live navigator",
                ReaderTheme.Dark.background.toArgb(),
                applied,
            )

            // Change the theme mid-read → the live observer re-submits; the applied bg updates.
            runBlocking { store.setTheme(ReaderTheme.Sepia) }
            var updated: Int? = null
            repeat(60) {
                scenario.onActivity { updated = it.appliedBackgroundArgb() }
                if (updated == ReaderTheme.Sepia.background.toArgb()) return@repeat
                Thread.sleep(200)
            }
            assertEquals(
                "a live theme change re-submitted to the navigator",
                ReaderTheme.Sepia.background.toArgb(),
                updated,
            )
        }

        // reset the store so the test leaves no persisted non-default state for other tests.
        runBlocking { store.setTheme(ReaderTheme.Paper) }
    }

    private fun stageBook(appContext: android.content.Context, testContext: android.content.Context, app: VReaderApp) =
        runBlocking {
            val staged = File(appContext.cacheDir, "epub-display-test-${System.nanoTime()}.epub")
            testContext.assets.open("minimal.epub").use { input ->
                staged.outputStream().use { input.copyTo(it) }
            }
            app.container.importer.importStream("content://test/minimal.epub", "minimal.epub", staged.inputStream())
        }
}
