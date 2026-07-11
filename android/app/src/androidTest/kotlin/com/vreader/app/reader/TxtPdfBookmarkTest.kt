package com.vreader.app.reader

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.VReaderApp
import com.vreader.app.data.Book
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * Feature #135 WI-7 — the TXT + PDF host bookmark wiring lit up: the top-bar bookmark TOGGLE now RENDERS
 * (WI-5's [chrome-bookmark-toggle] filling the top-bar slot), where before WI-7 the host passed null and the
 * slot stayed absent. RENDER assertions (not gestures — render/click chrome tests are not emulator-flaky;
 * only long-press/selection is), so they ride the connected gate cheaply. The PDF slice additionally drives
 * the top-bar toggle CLICK and confirms the create seam wrote a bookmark row through the repository (the PDF
 * host's onToggleBookmark → annotationsRepository.toggleBookmark at the current-page canonical locator). The
 * list-tap/jump-on-page behaviors are covered by the JVM host-helper suite ([pdfBookmarkPageTarget]) + ride
 * WI-9 acceptance.
 *
 * Real-books-first: the TXT slice uses the bundled `sample.txt`; the PDF slice uses the synthetic
 * `sample-3page.pdf` (feature #115 fixture) — NO real PDF exists in test-books (the documented "no real
 * PDF today" exception, per AGENTS Real-books-first).
 */
@RunWith(AndroidJUnit4::class)
class TxtPdfBookmarkTest {
    @get:Rule val compose = createEmptyComposeRule()

    @Test
    fun txtHost_rendersTopBarBookmarkToggle() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val appContext = instrumentation.targetContext
        val app = appContext.applicationContext as VReaderApp

        val staged = File(appContext.cacheDir, "bookmark-txt-${System.nanoTime()}.txt")
        instrumentation.context.assets.open("sample.txt").use { input ->
            staged.outputStream().use { output -> input.copyTo(output) }
        }
        val book = runBlocking {
            app.container.importer.importStream("content://test/sample.txt", "sample.txt", staged.inputStream())
        }

        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(appContext, book.fingerprintKey),
        ).use {
            // The bookmark toggle appears once the reader chrome renders (WI-7 wired the non-null toggle).
            compose.waitUntil(5_000) {
                compose.onAllNodesWithTag("chrome-bookmark-toggle").fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithTag("chrome-bookmark-toggle").assertIsDisplayed()
        }
    }

    @Test
    fun pdfHost_rendersTopBarBookmarkToggle() {
        val book = importPdf()
        // Deterministic start at page 0 (a stale saved position from a prior run can't shift the toggle).
        runBlocking { app().container.cachePage(book.fingerprintKey, 0) }

        ActivityScenario.launch<PdfReaderActivity>(
            PdfReaderActivity.intent(targetContext(), book.fingerprintKey),
        ).use {
            // The bookmark toggle appears once the PDF Loaded chrome renders (WI-7 wired the non-null toggle
            // on PdfReaderChrome exactly as the reflowable hosts do).
            compose.waitUntil(8_000) {
                compose.onAllNodesWithTag("chrome-bookmark-toggle").fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithTag("chrome-bookmark-toggle").assertIsDisplayed()
        }
    }

    @Test
    fun pdfHost_topBarToggle_createsBookmarkRow_atCurrentPage() {
        val book = importPdf()
        runBlocking { app().container.cachePage(book.fingerprintKey, 0) }

        // The bookmark equality basis the PDF host uses for the top-visible page (page 0 on open) — the SAME
        // canonical [pdfBookmarkLocator] builds, so the presence read below matches what the toggle wrote.
        val currentCanonical = pdfBookmarkLocator(book, 0)
        // Isolate from any prior run's row at this position (the repository is a process singleton).
        runBlocking {
            if (app().container.annotationsRepository.isBookmarked(book.fingerprintKey, currentCanonical)) {
                app().container.annotationsRepository.toggleBookmark(book.fingerprintKey, title = null, locator = currentCanonical)
            }
        }

        ActivityScenario.launch<PdfReaderActivity>(
            PdfReaderActivity.intent(targetContext(), book.fingerprintKey),
        ).use {
            // Wait for the rendered page + the top-bar toggle, then TAP it (the create seam).
            compose.waitUntil(8_000) {
                compose.onAllNodesWithContentDescription("Page 1").fetchSemanticsNodes().isNotEmpty() &&
                    compose.onAllNodesWithTag("chrome-bookmark-toggle").fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithTag("chrome-bookmark-toggle").performClick()

            // onToggleBookmark writes on the app scope (async) → poll the repository for the created row at
            // the current-page canonical. The Bookmarks list is a projection of exactly these rows.
            var bookmarked = false
            repeat(40) {
                bookmarked = runBlocking {
                    app().container.annotationsRepository.isBookmarked(book.fingerprintKey, currentCanonical)
                }
                if (bookmarked) return@repeat
                Thread.sleep(200)
            }
            assertTrue("the top-bar toggle created a bookmark row at the current page", bookmarked)

            // The created row is jumpable ON its page: pdfBookmarkPageTarget returns page 0 (in range), while
            // an out-of-range page → null (→ JumpResult.Failed, the sheet stays open — rule 51). Assert both
            // ends of the host's jump decision on the same live document's page count.
            assertTrue("the created bookmark's page (0) is a valid in-range jump target",
                pdfBookmarkPageTarget(0, pageCount = 3) == 0)
            assertTrue("a page past the end is out of range → the jump fails (sheet stays open)",
                pdfBookmarkPageTarget(99, pageCount = 3) == null)

            // Clean up so a re-run starts from a known-unbookmarked position.
            runBlocking {
                app().container.annotationsRepository.toggleBookmark(book.fingerprintKey, title = null, locator = currentCanonical)
            }
        }
    }

    // ---- helpers ----

    private fun targetContext(): android.content.Context =
        InstrumentationRegistry.getInstrumentation().targetContext

    private fun app(): VReaderApp = targetContext().applicationContext as VReaderApp

    /** Import the synthetic 3-page PDF fixture through the real importer (routes as `BookFormat.pdf`,
     *  copies into app-private storage so the PDF host's disk-read `load()` finds it). */
    private fun importPdf(): Book {
        val inst = InstrumentationRegistry.getInstrumentation()
        val staged = File(inst.targetContext.cacheDir, "bookmark-pdf-${System.nanoTime()}.pdf")
        inst.context.assets.open("sample-3page.pdf").use { input ->
            staged.outputStream().use { output -> input.copyTo(output) }
        }
        return runBlocking {
            app().container.importer.importStream("content://test/sample-3page.pdf", "sample-3page.pdf", staged.inputStream())
        }
    }
}
