package com.vreader.app.reader

import androidx.compose.ui.graphics.toArgb
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.VReaderApp
import com.vreader.app.reader.settings.ReaderSettings
import com.vreader.app.reader.settings.ReaderTheme
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * feature #129 WI-5 — the EPUB (Readium) reader applies the "Display" settings. Instrumented because
 * EpubNavigatorFragment resolves its settings against a real WebView (not Robolectric). Seeds a
 * non-default theme in the global ReaderSettingsStore, opens the reader, and asserts the navigator's
 * ACCEPTED background ARGB matches that theme (open-time application via initialPrefs), then changes the
 * theme mid-read and asserts the accepted background updates (live re-submission via submitPreferences).
 * This proves the setting reached + was resolved by the live navigator — not that the WebView painted
 * the pixel (that is WI-8 acceptance).
 */
@RunWith(AndroidJUnit4::class)
class EpubDisplaySettingsConnectedTest {

    @Test
    fun storedTheme_appliesToNavigatorOnOpen_andUpdatesLive() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val appContext = instrumentation.targetContext
        val app = appContext.applicationContext as VReaderApp
        val store = app.container.readerSettingsStore

        // Capture the pre-test settings so failures never leak persisted global state into later tests.
        val original: ReaderSettings = runBlocking { store.current() }
        try {
            // Seed a non-default theme BEFORE opening so the open-time initialPrefs carry it.
            runBlocking { store.setTheme(ReaderTheme.Dark) }
            val book = stageBook(appContext, instrumentation.context, app)

            ActivityScenario.launch<ReaderActivity>(ReaderActivity.intent(appContext, book.fingerprintKey)).use { scenario ->
                val applied = pollForActivity(scenario) { it.appliedBackgroundArgb() != null }?.let {
                    var v: Int? = null; scenario.onActivity { v = it.appliedBackgroundArgb() }; v
                }
                assertNotNull("navigator accepted a background color", applied)
                assertEquals(
                    "the stored Dark theme background reached the live navigator",
                    ReaderTheme.Dark.background.toArgb(),
                    applied,
                )

                // Change the theme mid-read → the live observer re-submits; the accepted bg updates.
                runBlocking { store.setTheme(ReaderTheme.Sepia) }
                val updated = pollForActivity(scenario) {
                    it.appliedBackgroundArgb() == ReaderTheme.Sepia.background.toArgb()
                }
                assertEquals(
                    "a live theme change re-submitted to the navigator",
                    ReaderTheme.Sepia.background.toArgb(),
                    updated?.let { var v: Int? = null; scenario.onActivity { v = it.appliedBackgroundArgb() }; v },
                )
            }
        } finally {
            // Restore the exact pre-test settings (not a forced default) so this test leaves no residue.
            runBlocking {
                store.setTheme(original.theme)
                store.setFontFamily(original.fontFamily)
                store.setFontSize(original.fontSizeSp)
                store.setLineSpacing(original.lineSpacing)
                store.setMargin(original.marginDp)
            }
        }
    }

    /** Poll the activity until [predicate] holds (max ~12s). Returns Unit on success or null on timeout,
     *  breaking out of the loop the instant the predicate is met (unlike a bare `return@repeat`). */
    private fun pollForActivity(
        scenario: ActivityScenario<ReaderActivity>,
        predicate: (ReaderActivity) -> Boolean,
    ): Unit? {
        repeat(60) {
            var ok = false
            scenario.onActivity { ok = predicate(it) }
            if (ok) return Unit
            Thread.sleep(200)
        }
        return null
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
