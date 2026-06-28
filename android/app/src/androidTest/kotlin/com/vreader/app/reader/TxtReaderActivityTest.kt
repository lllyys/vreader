package com.vreader.app.reader

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
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
    fun longPressOnText_selectsWord_showsSelectionPopover() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val appContext = instrumentation.targetContext
        val app = appContext.applicationContext as VReaderApp

        val staged = File(appContext.cacheDir, "sample-sel-${System.nanoTime()}.txt")
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
                compose.onAllNodesWithText("quick brown fox", substring = true).fetchSemanticsNodes().isNotEmpty()
            }
            // a long-press on the text drives detectDragGesturesAfterLongPress → word selection → popover.
            compose.onNodeWithText("quick brown fox", substring = true).performTouchInput { longClick() }
            compose.waitUntil(5_000) {
                compose.onAllNodesWithTag("selection-popover").fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithTag("selection-popover").assertIsDisplayed()
            compose.onNodeWithText("Highlight").assertIsDisplayed()
        }
    }

    @Test
    fun longPress_thenTapColor_createsAndPersistsHighlight() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val appContext = instrumentation.targetContext
        val app = appContext.applicationContext as VReaderApp

        val staged = File(appContext.cacheDir, "sample-create-${System.nanoTime()}.txt")
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
                compose.onAllNodesWithText("quick brown fox", substring = true).fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithText("quick brown fox", substring = true).performTouchInput { longClick() }
            compose.waitUntil(5_000) {
                compose.onAllNodesWithTag("popover-color-yellow").fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithTag("popover-color-yellow").performClick()

            // createTxtHighlight runs on appScope (async) → poll Room for the persisted highlight.
            var count = 0
            repeat(50) {
                count = runBlocking { app.container.annotationsRepository.highlightsForBook(book.fingerprintKey).size }
                if (count >= 1) return@repeat
                Thread.sleep(150)
            }
            org.junit.Assert.assertTrue("a highlight was created + persisted from the selection", count >= 1)
        }
    }

    @Test
    fun rendersWithSeededHighlight_drawsWash_noCrash() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val appContext = instrumentation.targetContext
        val app = appContext.applicationContext as VReaderApp

        val staged = File(appContext.cacheDir, "sample-hl-${System.nanoTime()}.txt")
        instrumentation.context.assets.open("sample.txt").use { input ->
            staged.outputStream().use { output -> input.copyTo(output) }
        }
        val book = runBlocking {
            app.container.importer.importStream("content://test/sample.txt", "sample.txt", staged.inputStream())
        }
        // seed a highlight over the first few source chars → the wash drawBehind path runs for chunk 0.
        runBlocking {
            val loc = Locator(book.contentSHA256, book.fileByteCount, "txt", charRangeStartUTF16 = 0, charRangeEndUTF16 = 8, textQuote = "seed")
            app.container.annotationsRepository.addHighlight(
                book.fingerprintKey, com.vreader.app.annotations.AnnotationColor.yellow, "seed", loc,
                com.vreader.app.annotations.AnnotationAnchor.Text("text-document:${book.fingerprintKey}", 0, 8),
            )
        }

        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(appContext, book.fingerprintKey),
        ).use {
            // render completes with the highlight present → the getPathForRange/drawWashes path executed.
            compose.waitUntil(5_000) {
                compose.onAllNodesWithText("quick brown fox", substring = true).fetchSemanticsNodes().isNotEmpty()
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
