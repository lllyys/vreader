package com.vreader.app.reader

import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.VReaderApp
import com.vreader.app.reader.settings.ReaderFontFamily
import com.vreader.app.reader.settings.ReaderLayout
import com.vreader.app.reader.settings.ReaderSettings
import com.vreader.app.reader.settings.ReaderTheme
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * Feature #137 WI-6a — connected proof that the paged renderer (TxtPagedBody: a HorizontalPager over
 * the off-main TxtPageIndex, lazily rendering each page via TxtPaginator.renderPage, with page-start
 * save/restore + reflow) is wired into the TXT/MD host and behaves:
 *   • paged mode renders real page text (TXT + MD);
 *   • a horizontal page turn (driven via the navigator's programmatic jump) advances the visible page;
 *   • RESUME lands on the right page — a saved page-start source offset reopens on the page containing
 *     it (pageContaining), not page 0;
 *   • off-screen pages are NOT retained (the lazy render window holds a bounded number of pages);
 *   • the SCROLL path still renders when layout == Scroll (no regression from the body branch).
 *
 * Uses createEmptyComposeRule + ActivityScenario (the TxtDisplaySettingsUiTest precedent) and
 * compose.waitUntil polling (NOT bare waitForIdle — it does not await the off-main pagination pass).
 * The 100-line resume fixtures (resume-sample.txt / md-resume.md) span many pages so page turns +
 * resume are observable. Run ONE class per connected invocation (MEMORY #129/#133).
 */
@RunWith(AndroidJUnit4::class)
class TxtPagedBodyConnectedTest {
    @get:Rule val compose = createEmptyComposeRule()

    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val app get() = instrumentation.targetContext.applicationContext as VReaderApp

    /** The DataStore is shared across test classes — pin display defaults + the layout each test needs
     *  BEFORE the launch, and confirm the store has actually committed it (store.current() reflects the
     *  latest write) so the reader's settings collection opens on the intended layout (no Paged↔Scroll
     *  emission race across the batch). Restore Scroll (the product default) after each test. */
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

    /** Commit [layout] and confirm the store reflects it before the caller launches the reader. */
    private fun setLayoutAndConfirm(layout: ReaderLayout) = runBlocking<Unit> {
        val store = app.container.readerSettingsStore
        store.setLayout(layout)
        // store.current() is a one-shot read of the latest committed value — poll until it settles.
        for (i in 0 until 50) {
            if (store.current().layout == layout) return@runBlocking
            kotlinx.coroutines.delay(20)
        }
        throw AssertionError("layout $layout not committed to the store in time")
    }

    private fun importAsset(asset: String): String {
        val staged = File(instrumentation.targetContext.cacheDir, "paged-${System.nanoTime()}-$asset")
        instrumentation.context.assets.open(asset).use { input ->
            staged.outputStream().use { output -> input.copyTo(output) }
        }
        val book = runBlocking {
            app.container.importer.importStream("content://test/$asset", asset, staged.inputStream())
        }
        // The same asset content-addresses to the SAME fingerprint across tests, so a prior test's
        // paged forward-turns leave a non-zero saved offset in the in-memory position cache (read FIRST
        // by the reader's resume). Zero it so each open that asserts page 0 is independent of test order.
        app.container.cacheOffset(book.fingerprintKey, 0)
        return book.fingerprintKey
    }

    /** True once the paged body has published a non-null page index for this open (phase-1 finished). */
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

    @Test
    fun pagedMode_rendersFirstPage_txt() {
        setLayoutAndConfirm(ReaderLayout.Paged)
        val key = importAsset("resume-sample.txt")
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            scenario.awaitPageIndex()
            // The first page shows the opening lines (not the whole 100-line file — proof it paginated).
            compose.waitUntil(15_000) {
                compose.onAllNodesWithText("Line 001", substring = true).fetchSemanticsNodes().isNotEmpty()
            }
            // Many pages, not one giant scrolling chunk (100 short lines cannot fit a single screen page).
            assertTrue("100 lines must span > 1 page", scenario.pageCount() > 1)
            assertEquals("opens on page 0", 0, scenario.currentPage())
        }
    }

    @Test
    fun pagedMode_rendersFirstPage_md() {
        setLayoutAndConfirm(ReaderLayout.Paged)
        val key = importAsset("md-resume.md")
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            scenario.awaitPageIndex()
            compose.waitUntil(15_000) {
                compose.onAllNodesWithText("Line 001", substring = true).fetchSemanticsNodes().isNotEmpty()
            }
            assertTrue("MD 100 lines must span > 1 page", scenario.pageCount() > 1)
        }
    }

    @Test
    fun horizontalTurn_advancesTheVisiblePage() {
        setLayoutAndConfirm(ReaderLayout.Paged)
        val key = importAsset("resume-sample.txt")
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            scenario.awaitPageIndex()
            compose.waitUntil(15_000) {
                compose.onAllNodesWithText("Line 001", substring = true).fetchSemanticsNodes().isNotEmpty()
            }
            assertEquals(0, scenario.currentPage())
            val startOffset = run {
                var o = -1; scenario.onActivity { o = it.pagedCurrentSourceOffsetForTest() ?: -1 }; o
            }
            // Turn to the next page (programmatic pager scroll via the navigator jump seam — the harness
            // cannot express a horizontal swipe on the virtual display; the jump drives the SAME seam).
            scenario.onActivity { it.turnToNextPageForTest() }
            compose.waitUntil(15_000) { scenario.currentPage() >= 1 }
            assertTrue("page advanced past 0", scenario.currentPage() >= 1)
            // The current page's start source offset advanced too (progress moved forward, not stuck).
            var nextOffset = -1
            scenario.onActivity { nextOffset = it.pagedCurrentSourceOffsetForTest() ?: -1 }
            assertTrue("source offset advanced with the page turn", nextOffset > startOffset)
        }
    }

    @Test
    fun resume_landsOnTheRightPage() {
        setLayoutAndConfirm(ReaderLayout.Paged)
        val key = importAsset("resume-sample.txt")
        // First open: page forward a few times, capture the current page-start source offset that the
        // host saves, then close.
        var savedPage = -1
        var savedOffset = -1
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            scenario.awaitPageIndex()
            compose.waitUntil(15_000) {
                compose.onAllNodesWithText("Line 001", substring = true).fetchSemanticsNodes().isNotEmpty()
            }
            repeat(3) { turn ->
                scenario.onActivity { it.turnToNextPageForTest() }
                compose.waitUntil(15_000) { scenario.currentPage() >= turn + 1 }
            }
            scenario.onActivity {
                savedPage = it.pagedCurrentPageForTest() ?: -1
                savedOffset = it.pagedCurrentSourceOffsetForTest() ?: -1
                it.flushPagedPositionForTest()   // persist the current page-start offset synchronously-ish
            }
            assertTrue("advanced to a non-zero page", savedPage >= 1)
            assertTrue("captured a non-zero source offset", savedOffset > 0)
        }
        // Reopen: the saved offset must restore onto the page containing it (not page 0).
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            scenario.awaitPageIndex()
            compose.waitUntil(15_000) {
                (scenario.pageCount() > 0) && scenario.currentPage() > 0
            }
            assertTrue("resume restored past page 0", scenario.currentPage() > 0)
            // The restored page must contain the saved source offset.
            var containing = -1
            scenario.onActivity { containing = it.pagedPageContainingForTest(savedOffset) ?: -1 }
            assertEquals("restored page contains the saved offset", containing, scenario.currentPage())
        }
    }

    @Test
    fun offScreenPages_areNotRetained() {
        setLayoutAndConfirm(ReaderLayout.Paged)
        val key = importAsset("resume-sample.txt")
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            scenario.awaitPageIndex()
            compose.waitUntil(15_000) {
                compose.onAllNodesWithText("Line 001", substring = true).fetchSemanticsNodes().isNotEmpty()
            }
            // Turn several pages; the rendered-page cache must stay bounded (a small window), never
            // grow to pageCount (the whole book rendered).
            repeat(6) { i ->
                scenario.onActivity { it.turnToNextPageForTest() }
                compose.waitUntil(15_000) { scenario.currentPage() >= i + 1 }
            }
            var cacheSize = 0
            var pageCount = 0
            scenario.onActivity {
                cacheSize = it.pagedRenderedCacheSizeForTest() ?: 0
                pageCount = it.pagedPageCountForTest() ?: 0
            }
            assertTrue("visited > cache-window pages", pageCount > 6)
            assertTrue("rendered-page cache stays bounded (window << pageCount)", cacheSize in 1..8)
        }
    }

    @Test
    fun scrollPath_stillRenders_whenLayoutIsScroll() {
        setLayoutAndConfirm(ReaderLayout.Scroll)
        val key = importAsset("resume-sample.txt")
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            // The scroll body renders the LazyColumn — the first lines are visible, and NO paged index
            // is built (the paged body is never mounted).
            compose.waitUntil(15_000) {
                compose.onAllNodesWithText("Line 001", substring = true).fetchSemanticsNodes().isNotEmpty()
            }
            var pagedMounted: Boolean? = null
            scenario.onActivity { pagedMounted = it.pagedBodyMountedForTest() }
            assertNotNull(pagedMounted)
            assertTrue("scroll layout must NOT mount the paged body", pagedMounted == false)
        }
    }
}
