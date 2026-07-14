package com.vreader.app.reader

import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.VReaderApp
import com.vreader.app.annotations.BookmarkToggleResult
import com.vreader.app.reader.settings.ReaderFontFamily
import com.vreader.app.reader.settings.ReaderLayout
import com.vreader.app.reader.settings.ReaderSettings
import com.vreader.app.reader.settings.ReaderTheme
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * feature #137 WI-8 — connected proof that BOOKMARKS work in PAGED mode:
 *   • toggling a bookmark records the CURRENT paged page's START source offset as the bookmark locator
 *     (the SAME offset paged save/restore uses — `txtBookmarkLocator(book, currentPageStartOffset)`),
 *     and the presence read (`isBookmarked`) reflects it — never the hidden scroll list;
 *   • the bookmark's recorded position lands on a DIFFERENT page after a page turn (so a bookmark on
 *     page N is not confused with page 0);
 *   • jump-to-bookmark lands on the page CONTAINING the bookmark's offset (pageContaining), driven
 *     through the SAME pager-jump seam the top-bar bookmark jump routes to in paged mode;
 *   • a scrubber jump maps a 0..1 fraction to the correct page (`pageContaining(fraction * length)`).
 *
 * Uses createEmptyComposeRule + ActivityScenario (the TxtPagedBodyConnectedTest precedent) and
 * compose.waitUntil polling (NOT bare waitForIdle — it does not await the off-main pagination pass).
 * Run ONE class per connected invocation (MEMORY #129/#133).
 */
@RunWith(AndroidJUnit4::class)
class TxtPagedBookmarkConnectedTest {
    @get:Rule val compose = createEmptyComposeRule()

    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val app get() = instrumentation.targetContext.applicationContext as VReaderApp

    @Before
    fun pinDefaults() = runBlocking<Unit> {
        val store = app.container.readerSettingsStore
        store.setTheme(ReaderTheme.Paper)
        store.setFontFamily(ReaderFontFamily.Serif)
        store.setFontSize(ReaderSettings.DEFAULT_FONT_SIZE)
        store.setLineSpacing(ReaderSettings.DEFAULT_LINE_SPACING)
        store.setMargin(ReaderSettings.DEFAULT_MARGIN)
    }

    @After
    fun restoreScroll() = runBlocking<Unit> {
        app.container.readerSettingsStore.setLayout(ReaderLayout.Scroll)
    }

    private fun setLayoutAndConfirm(layout: ReaderLayout) = runBlocking<Unit> {
        val store = app.container.readerSettingsStore
        store.setLayout(layout)
        for (i in 0 until 50) {
            if (store.current().layout == layout) return@runBlocking
            kotlinx.coroutines.delay(20)
        }
        throw AssertionError("layout $layout not committed to the store in time")
    }

    private fun importAsset(asset: String): String {
        val staged = File(instrumentation.targetContext.cacheDir, "pgbm-${System.nanoTime()}-$asset")
        instrumentation.context.assets.open(asset).use { input ->
            staged.outputStream().use { output -> input.copyTo(output) }
        }
        val book = runBlocking {
            app.container.importer.importStream("content://test/$asset", asset, staged.inputStream())
        }
        app.container.cacheOffset(book.fingerprintKey, 0)
        return book.fingerprintKey
    }

    private fun ActivityScenario<TxtReaderActivity>.awaitPageIndex(timeoutMs: Long = 15_000) {
        compose.waitUntil(timeoutMs) {
            var ready = false
            onActivity { ready = it.pagedPageCountForTest()?.let { c -> c > 0 } == true }
            ready
        }
    }

    private fun ActivityScenario<TxtReaderActivity>.currentPage(): Int {
        var page = -1
        onActivity { page = it.pagedCurrentPageForTest() ?: -1 }
        return page
    }

    private fun ActivityScenario<TxtReaderActivity>.pageCount(): Int {
        var count = 0
        onActivity { count = it.pagedPageCountForTest() ?: 0 }
        return count
    }

    private fun ActivityScenario<TxtReaderActivity>.sourceOffset(): Int {
        var o = -1
        onActivity { o = it.pagedCurrentSourceOffsetForTest() ?: -1 }
        return o
    }

    /** Run a suspend host seam on the Activity's scope, blocking for its result. */
    private fun <T> ActivityScenario<TxtReaderActivity>.blocking(block: suspend (TxtReaderActivity) -> T): T {
        val latch = CountDownLatch(1)
        val result = arrayOfNulls<Any?>(1)
        val error = arrayOfNulls<Throwable>(1)
        onActivity { activity ->
            activity.lifecycleScope.launch {
                try { result[0] = block(activity) } catch (t: Throwable) { error[0] = t } finally { latch.countDown() }
            }
        }
        if (!latch.await(30, TimeUnit.SECONDS)) throw AssertionError("host seam timed out")
        error[0]?.let { throw it }
        @Suppress("UNCHECKED_CAST")
        return result[0] as T
    }

    @Test
    fun toggleBookmark_recordsCurrentPageStartOffset_andPresenceReflectsIt() {
        setLayoutAndConfirm(ReaderLayout.Paged)
        val key = importAsset("resume-sample.txt")
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            scenario.awaitPageIndex()
            compose.waitUntil(15_000) {
                compose.onAllNodesWithText("Line 001", substring = true).fetchSemanticsNodes().isNotEmpty()
            }
            // Turn to a non-zero page so the bookmark records a page-start offset > 0.
            scenario.onActivity { it.turnToNextPageForTest() }
            compose.waitUntil(15_000) { scenario.currentPage() >= 1 }
            val pageOffset = scenario.sourceOffset()
            assertTrue("on a non-zero page-start offset", pageOffset > 0)

            // Not bookmarked yet; the toggle records the CURRENT page's start offset.
            assertFalse("page starts un-bookmarked", scenario.blocking { it.pagedIsBookmarkedForTest() })
            val result = scenario.blocking { it.pagedToggleBookmarkForTest() }
            assertEquals("toggle ADDED the bookmark", BookmarkToggleResult.Added, result)
            // The locator the toggle used is the current page-start offset (mode-aware).
            var recorded = -1
            scenario.onActivity { recorded = it.pagedBookmarkLocatorForTest()?.charOffsetUTF16 ?: -1 }
            assertEquals("bookmark locator == current page-start offset", pageOffset, recorded)
            // Presence now true for THIS page.
            assertTrue("current page reads bookmarked", scenario.blocking { it.pagedIsBookmarkedForTest() })

            // Toggle again removes it (idempotent alternate) — presence flips back to false.
            val result2 = scenario.blocking { it.pagedToggleBookmarkForTest() }
            assertEquals("second toggle REMOVED", BookmarkToggleResult.Removed, result2)
            assertFalse("presence cleared after remove", scenario.blocking { it.pagedIsBookmarkedForTest() })
        }
    }

    @Test
    fun jumpToBookmarkOffset_landsOnPageContainingIt() {
        setLayoutAndConfirm(ReaderLayout.Paged)
        val key = importAsset("resume-sample.txt")
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            scenario.awaitPageIndex()
            compose.waitUntil(15_000) {
                compose.onAllNodesWithText("Line 001", substring = true).fetchSemanticsNodes().isNotEmpty()
            }
            // Advance a few pages, capture that page's start offset (the "bookmark"), then jump back to 0.
            repeat(3) { turn ->
                scenario.onActivity { it.turnToNextPageForTest() }
                compose.waitUntil(15_000) { scenario.currentPage() >= turn + 1 }
            }
            val bookmarkOffset = scenario.sourceOffset()
            val bookmarkPage = scenario.currentPage()
            assertTrue("bookmark on a non-zero page", bookmarkPage >= 1)

            // Jump to page 0 first.
            scenario.onActivity { it.pagedJumpToOffsetForTest(0) }
            compose.waitUntil(15_000) { scenario.currentPage() == 0 }
            assertEquals(0, scenario.currentPage())

            // Jump to the bookmark's offset → lands on the page CONTAINING it.
            scenario.onActivity { it.pagedJumpToOffsetForTest(bookmarkOffset) }
            var containing = -1
            scenario.onActivity { containing = it.pagedPageContainingForTest(bookmarkOffset) ?: -1 }
            compose.waitUntil(15_000) { scenario.currentPage() == containing }
            assertEquals("jump landed on the page containing the bookmark offset", containing, scenario.currentPage())
            assertEquals("and that IS the page the bookmark was made on", bookmarkPage, scenario.currentPage())
        }
    }

    @Test
    fun scrubberFraction_mapsToTheCorrectPage() {
        setLayoutAndConfirm(ReaderLayout.Paged)
        val key = importAsset("resume-sample.txt")
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            scenario.awaitPageIndex()
            compose.waitUntil(15_000) {
                compose.onAllNodesWithText("Line 001", substring = true).fetchSemanticsNodes().isNotEmpty()
            }
            val length = run { var l = 0; scenario.onActivity { l = it.pagedDocLengthForTest() }; l }
            assertTrue("document has text", length > 0)
            // Scrub to ~60% — the SAME offset the chrome's onScrub computes ((f * length).toInt()).
            val fraction = 0.6f
            val target = (fraction * length).toInt().coerceIn(0, (length - 1).coerceAtLeast(0))
            val expectedPage = run { var p = -1; scenario.onActivity { p = it.pagedPageContainingForTest(target) ?: -1 }; p }
            assertTrue("mid-book scrub is a non-zero page", expectedPage > 0)

            scenario.onActivity { it.pagedJumpToOffsetForTest(target) }
            compose.waitUntil(15_000) { scenario.currentPage() == expectedPage }
            assertEquals("scrubber fraction mapped to pageContaining(fraction*length)", expectedPage, scenario.currentPage())
        }
    }
}
