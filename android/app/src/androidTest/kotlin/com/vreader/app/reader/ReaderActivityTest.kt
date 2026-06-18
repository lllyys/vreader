package com.vreader.app.reader

import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.VReaderApp
import com.vreader.app.data.Book
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * Reader host (feature #106 WI-9) — instrumented because Readium's
 * EpubNavigatorFragment renders in a real WebView (not Robolectric). Imports the
 * bundled minimal EPUB through the real pipeline, launches ReaderActivity, and
 * asserts the navigator renders a locator (the content loaded) + the open marked
 * the book.
 */
@RunWith(AndroidJUnit4::class)
class ReaderActivityTest {

    @Test
    fun opensStoredEpub_rendersNavigator_andMarksOpened() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val appContext = instrumentation.targetContext
        val app = appContext.applicationContext as VReaderApp
        val book = stageBook(appContext, instrumentation.context, app)

        ActivityScenario.launch<ReaderActivity>(ReaderActivity.intent(appContext, book.fingerprintKey)).use { scenario ->
            // The open + render is async; poll the navigator's current locator.
            var href: String? = null
            repeat(50) {
                scenario.onActivity { href = it.currentHref() }
                if (href != null) return@repeat
                Thread.sleep(200)
            }
            assertNotNull("the navigator rendered a reading locator (content loaded)", href)
        }

        val reopened = runBlocking { app.container.repository.findBook(book.fingerprintKey) }
        assertNotNull("opening the book marked lastOpenedAt", reopened?.lastOpenedAt)
    }

    @Test
    fun backgrounding_flushesReadingPosition() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val appContext = instrumentation.targetContext
        val testContext = instrumentation.context
        val app = appContext.applicationContext as VReaderApp
        val book: Book = stageBook(appContext, testContext, app)

        ActivityScenario.launch<ReaderActivity>(ReaderActivity.intent(appContext, book.fingerprintKey)).use { scenario ->
            var rendered = false
            repeat(50) {
                scenario.onActivity { rendered = it.currentHref() != null }
                if (rendered) return@repeat
                Thread.sleep(200)
            }
            // Background the reader → onStop flushes the current position synchronously.
            scenario.moveToState(Lifecycle.State.CREATED)

            var saved = false
            repeat(50) {
                saved = runBlocking { app.container.repository.loadPosition(book.fingerprintKey) != null }
                if (saved) return@repeat
                Thread.sleep(200)
            }
            assertTrue("onStop flushed a reading position to Room", saved)
        }
    }

    private fun stageBook(appContext: android.content.Context, testContext: android.content.Context, app: VReaderApp): Book {
        val staged = File(appContext.cacheDir, "reader-test-${System.nanoTime()}.epub")
        testContext.assets.open("minimal.epub").use { input ->
            staged.outputStream().use { input.copyTo(it) }
        }
        return runBlocking {
            app.container.importer.importStream("content://test/minimal.epub", "minimal.epub", staged.inputStream())
        }
    }
}
