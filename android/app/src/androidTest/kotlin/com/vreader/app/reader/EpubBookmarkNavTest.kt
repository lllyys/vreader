package com.vreader.app.reader

import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.VReaderApp
import com.vreader.app.annotations.BookmarkRecord
import com.vreader.app.data.Book
import com.vreader.app.reader.nav.JumpResult
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import vreader.contracts.Locator
import java.io.File

/**
 * Feature #135 WI-7 — the EPUB bookmark host wiring, instrumented because Readium's EpubNavigatorFragment
 * renders in a REAL WebView (not Robolectric). Exercises the integrator that lights up create/toggle/list/
 * jump on the EPUB host:
 *  - toggle at the live position → the top-bar filled state flips + the Bookmarks list gains the row;
 *  - a PERSISTED bookmark (the fresh-process / backup-restored path — canonical-only) → jump reconstructs a
 *    Readium locator via [ReadiumLocatorReconstructor] and lands ([JumpResult.Succeeded] → the sheet dismisses);
 *  - an unresolvable-href canonical → [JumpResult.Failed] (the sheet stays open, no invented error surface).
 * Uses the host's @VisibleForTesting seams (the live Compose toggle/list taps ride WI-9 acceptance).
 */
@RunWith(AndroidJUnit4::class)
class EpubBookmarkNavTest {

    @Test
    fun toggleAtLivePosition_flipsPresence_andAddsRow() {
        val (app, book) = stage()
        ActivityScenario.launch<ReaderActivity>(ReaderActivity.intent(app.appContext, book.fingerprintKey)).use { scenario ->
            awaitRender(scenario)

            // Before any toggle: not bookmarked, no rows.
            var before = true
            scenario.onActivity { before = it.isCurrentBookmarkedForTest() }
            assertTrue("no bookmark at the live position yet", !before)

            // Toggle ON through the same seam the top-bar button uses.
            scenario.onActivity { it.toggleCurrentBookmarkForTest() }

            var bookmarked = false
            var rows = 0
            repeat(50) {
                scenario.onActivity {
                    bookmarked = it.isCurrentBookmarkedForTest()
                    rows = it.bookmarkRowsForTest().size
                }
                if (bookmarked && rows >= 1) return@repeat
                Thread.sleep(200)
            }
            assertTrue("the top-bar toggle now shows filled (bookmarked)", bookmarked)
            assertTrue("the Bookmarks list gained the row", rows >= 1)
        }
    }

    @Test
    fun jumpToPersistedBookmark_reconstructsCanonical_andLands() {
        val (app, book) = stage()
        ActivityScenario.launch<ReaderActivity>(ReaderActivity.intent(app.appContext, book.fingerprintKey)).use { scenario ->
            val href = awaitRender(scenario)

            // Seed a PERSISTED bookmark with ONLY a canonical Locator (no precise Readium JSON) at the
            // rendered href — exactly the fresh-process / backup-restored shape. The jump must reconstruct.
            val canonical = Locator(
                contentSHA256 = book.contentSHA256, fileByteCount = book.fileByteCount,
                format = book.originalFormat.name, href = href, progression = 0.0,
            )
            val record = BookmarkRecord(
                id = "bm-1", bookKey = book.fingerprintKey, title = null, locator = canonical,
                createdAt = 1L, updatedAt = 1L,
            )
            var result: JumpResult? = null
            scenario.onActivity { result = it.jumpToBookmarkForTest(record) }
            assertEquals("the canonical-only bookmark reconstructed + landed", JumpResult.Succeeded, result)
        }
    }

    @Test
    fun jumpToUnresolvableBookmark_failsAndSheetStaysOpen() {
        val (app, book) = stage()
        ActivityScenario.launch<ReaderActivity>(ReaderActivity.intent(app.appContext, book.fingerprintKey)).use { scenario ->
            awaitRender(scenario)
            val canonical = Locator(
                contentSHA256 = book.contentSHA256, fileByteCount = book.fileByteCount,
                format = book.originalFormat.name, href = "does-not-exist.xhtml", progression = 0.0,
            )
            val record = BookmarkRecord(
                id = "bm-x", bookKey = book.fingerprintKey, title = null, locator = canonical,
                createdAt = 1L, updatedAt = 1L,
            )
            var result: JumpResult? = null
            scenario.onActivity { result = it.jumpToBookmarkForTest(record) }
            assertEquals("an unresolvable href fails → the sheet stays open (rule 51)", JumpResult.Failed, result)
        }
    }

    // ---- helpers ----

    private val VReaderApp.appContext get() = this.applicationContext as android.content.Context

    private fun stage(): Pair<VReaderApp, Book> {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val appContext = instrumentation.targetContext
        val app = appContext.applicationContext as VReaderApp
        val staged = File(appContext.cacheDir, "bookmark-test-${System.nanoTime()}.epub")
        instrumentation.context.assets.open("minimal.epub").use { input ->
            staged.outputStream().use { input.copyTo(it) }
        }
        val book = runBlocking {
            app.container.importer.importStream("content://test/minimal.epub", "minimal.epub", staged.inputStream())
        }
        return app to book
    }

    /** Poll the navigator's rendered locator; returns the rendered href (asserts it rendered). */
    private fun awaitRender(scenario: ActivityScenario<ReaderActivity>): String {
        var href: String? = null
        repeat(50) {
            scenario.onActivity { href = it.currentHref() }
            if (href != null) return@repeat
            Thread.sleep(200)
        }
        assertNotNull("the navigator rendered a reading locator", href)
        return href!!
    }
}
