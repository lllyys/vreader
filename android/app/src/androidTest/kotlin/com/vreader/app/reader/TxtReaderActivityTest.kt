package com.vreader.app.reader

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.VReaderApp
import com.vreader.app.data.Book
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import vreader.contracts.Locator
import vreader.contracts.VReaderLocator
import java.io.File

/**
 * TXT reader render (feature #111 WI-2) — instrumented Compose UI test. Imports the
 * bundled sample.txt through the real WI-4 pipeline, launches TxtReaderActivity, and
 * asserts the decoded text renders in the LazyColumn body.
 */
@RunWith(AndroidJUnit4::class)
class TxtReaderActivityTest {
    @get:Rule val compose = createEmptyComposeRule()

    @Test
    fun opensStoredTxt_rendersDecodedText() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val appContext = instrumentation.targetContext
        val app = appContext.applicationContext as VReaderApp

        val staged = File(appContext.cacheDir, "sample-${System.nanoTime()}.txt")
        instrumentation.context.assets.open("sample.txt").use { input ->
            staged.outputStream().use { output -> input.copyTo(output) }
        }
        val book = runBlocking {
            app.container.importer.importStream("content://test/sample.txt", "sample.txt", staged.inputStream())
        }

        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(appContext, book.fingerprintKey),
        ).use {
            compose.waitUntil(5_000) {
                compose.onAllNodesWithText("quick brown fox", substring = true)
                    .fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithText("quick brown fox", substring = true).assertIsDisplayed()
        }
    }

    @Test
    fun resumesToSavedCharOffset() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val appContext = instrumentation.targetContext
        val app = appContext.applicationContext as VReaderApp

        // Import the tall 100-line fixture (each line "Line NNN of the resume fixture.\n"
        // = 32 UTF-16 units; line 080 starts at 79*32 = 2528).
        val staged = File(appContext.cacheDir, "resume-${System.nanoTime()}.txt")
        instrumentation.context.assets.open("resume-sample.txt").use { input ->
            staged.outputStream().use { output -> input.copyTo(output) }
        }
        val book: Book = runBlocking {
            app.container.importer.importStream("content://test/resume-sample.txt", "resume-sample.txt", staged.inputStream())
        }
        // Seed a saved position at line 080's offset (a legacy charOffsetUTF16 locator).
        runBlocking {
            val locator = Locator(
                contentSHA256 = book.contentSHA256, fileByteCount = book.fileByteCount,
                format = "txt", charOffsetUTF16 = 2528,
            )
            app.container.repository.savePosition(VReaderLocator.wrapLegacy(locator), 1L)
        }

        ActivityScenario.launch<TxtReaderActivity>(TxtReaderActivity.intent(appContext, book.fingerprintKey)).use {
            compose.waitUntil(5_000) {
                compose.onAllNodesWithText("Line 080", substring = true).fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithText("Line 080", substring = true).assertIsDisplayed()
            // Opened scrolled to the saved offset, so line 001 is NOT on screen.
            assertEquals(
                "reopened past the top — line 001 not visible",
                0,
                compose.onAllNodesWithText("Line 001 of", substring = true).fetchSemanticsNodes().size,
            )
        }
    }
}
