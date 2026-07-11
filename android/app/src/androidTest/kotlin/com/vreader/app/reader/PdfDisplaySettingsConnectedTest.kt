package com.vreader.app.reader

import androidx.compose.ui.graphics.toArgb
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.VReaderApp
import com.vreader.app.data.Book
import com.vreader.app.reader.settings.ReaderSettings
import com.vreader.app.reader.settings.ReaderTheme
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * feature #129 WI-7 — the PDF reader applies the theme background to its viewer backdrop (PDF is
 * rasterized: theme bg ONLY, no font/size/spacing, no Display sheet / Aa slot — rule 51). Seeds a
 * non-default theme in the global ReaderSettingsStore, opens the PDF reader, and asserts the host's
 * applied backdrop ARGB matches that theme's background (open-time application), then changes the
 * theme mid-read and asserts the backdrop updates live (the store's Flow re-emits). Proves the
 * setting reached the host — not that pixels painted (WI-8 acceptance covers pixels). Uses the
 * synthetic PDF fixture #115 shipped (sample-3page.pdf); no real PDF exists in test-books.
 */
@RunWith(AndroidJUnit4::class)
class PdfDisplaySettingsConnectedTest {

    @Test
    fun storedTheme_appliesToBackdropOnOpen_andUpdatesLive() {
        val inst = InstrumentationRegistry.getInstrumentation()
        val appContext = inst.targetContext
        val app = appContext.applicationContext as VReaderApp
        val store = app.container.readerSettingsStore

        // Capture pre-test settings so a failure never leaks persisted global state into later tests.
        val original: ReaderSettings = runBlocking { store.current() }
        try {
            // Seed a non-default theme BEFORE opening so the open-time backdrop carries it.
            runBlocking { store.setTheme(ReaderTheme.Dark) }
            val book = importPdf(appContext, inst.context, app)

            ActivityScenario.launch<PdfReaderActivity>(
                PdfReaderActivity.intent(appContext, book.fingerprintKey),
            ).use { scenario ->
                // The host GATES composition on the first settings emission (WI-7), so the hook stays
                // null until the persisted Dark is applied — it can never latch a Paper fallback first.
                // Poll for the Dark ARGB specifically (not merely non-null) to also prove no wrong frame.
                val applied = pollForActivity(scenario) {
                    it.appliedBackdropArgb() == ReaderTheme.Dark.background.toArgb()
                }?.let {
                    var v: Int? = null; scenario.onActivity { v = it.appliedBackdropArgb() }; v
                }
                assertNotNull("the PDF host applied a backdrop color", applied)
                assertEquals(
                    "the stored Dark theme background reached the PDF backdrop",
                    ReaderTheme.Dark.background.toArgb(),
                    applied,
                )

                // Change the theme mid-read → the live Flow re-emits; the backdrop updates.
                runBlocking { store.setTheme(ReaderTheme.Sepia) }
                val updated = pollForActivity(scenario) {
                    it.appliedBackdropArgb() == ReaderTheme.Sepia.background.toArgb()
                }
                assertEquals(
                    "a live theme change re-applied to the PDF backdrop",
                    ReaderTheme.Sepia.background.toArgb(),
                    updated?.let { var v: Int? = null; scenario.onActivity { v = it.appliedBackdropArgb() }; v },
                )
            }
        } finally {
            // Restore the exact pre-test settings (not a forced default) so this test leaves no residue.
            runBlocking { store.setTheme(original.theme) }
        }
    }

    /** Poll the activity until [predicate] holds (max ~12s). Returns Unit on success or null on timeout. */
    private fun pollForActivity(
        scenario: ActivityScenario<PdfReaderActivity>,
        predicate: (PdfReaderActivity) -> Boolean,
    ): Unit? {
        repeat(60) {
            var ok = false
            scenario.onActivity { ok = predicate(it) }
            if (ok) return Unit
            Thread.sleep(200)
        }
        return null
    }

    private fun importPdf(appContext: android.content.Context, testContext: android.content.Context, app: VReaderApp): Book =
        runBlocking {
            val asset = "sample-3page.pdf"
            val staged = File(appContext.cacheDir, "pdf-display-test-${System.nanoTime()}.pdf")
            testContext.assets.open(asset).use { input -> staged.outputStream().use { input.copyTo(it) } }
            app.container.importer.importStream("content://test/$asset", asset, staged.inputStream())
        }
}
