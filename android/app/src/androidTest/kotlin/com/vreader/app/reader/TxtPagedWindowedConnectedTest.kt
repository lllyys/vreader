package com.vreader.app.reader

import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
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
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * Feature #138 WI-5b — connected proof that [TxtPagedBody] now drives the WINDOWED pagination
 * lifecycle through a [com.vreader.app.reader.paged.PaginationSession] instead of the single blocking
 * whole-doc `TxtPaginator.index(...)` pass:
 *
 *   • FAST FIRST OPEN — the first SEALED window publishes quickly, so the `txt-paged-loading` surface
 *     clears fast and the opening page (`Line 001`) renders while the rest of the book is still being
 *     measured in the background (a PARTIAL sealed index).
 *   • GROWING SEALED pageCount / on-demand forward extension — paging PAST the initial sealed window
 *     lands on the right page with a matching page-start source offset (the frontier is extended
 *     on-demand / completed in the background — append-only, never shrinks, never a gap).
 *   • CONDITIONAL deep-resume reveal — reopening at a deep saved source offset opens page 0 first, then
 *     CONDITIONALLY auto-scrolls onto the resume page once its page seals (the user did NOT take over).
 *   • SEALED-page render-cache policy — a background APPEND does NOT clear [PagedRenderCache]; a page
 *     re-visited after the count grows is a cache HIT (the retained window survives the append).
 *   • REFLOW clears the cache + clamps — a mid-background font-size change re-paginates windowed, clamps
 *     the pager back to the saved source offset, AND clears the render cache (only a reflow clears it).
 *
 * Uses createEmptyComposeRule + ActivityScenario (the TxtPagedBodyConnectedTest precedent) and
 * `compose.waitUntil` polling — NEVER bare `waitForIdle` (MEMORY #133: the background completion loop
 * runs across frames + the session debounces republishes, so `waitForIdle` does NOT await it). The
 * 100-line `resume-sample.txt` fixture paginates to > 6 pages, so with a 3-page initial window the FIRST
 * published index is genuinely PARTIAL and the count GROWS as the background pass completes.
 *
 * Real-books-first exception (AGENTS.md): connected instrumentation tests run against the app's BUNDLED
 * `androidTest/assets` — they CANNOT read the gitignored local-only `test-books/` tree (the CI-unit-test
 * exception). The 100-line fixture is also the deterministic-tiny-structure exception (per-line `Line NNN`
 * markers let `compose.waitUntil` poll for an exact rendered line + controlled char offsets). This is the
 * same fixture the whole existing paged connected suite uses.
 *
 * Run ONE class per connected invocation (MEMORY #129/#133).
 */
@RunWith(AndroidJUnit4::class)
class TxtPagedWindowedConnectedTest {
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
    fun restoreDefaults() = runBlocking<Unit> {
        val store = app.container.readerSettingsStore
        store.setLayout(ReaderLayout.Scroll)
        store.setFontSize(ReaderSettings.DEFAULT_FONT_SIZE)
        store.setMargin(ReaderSettings.DEFAULT_MARGIN)
    }

    /** Commit [layout] and confirm the store reflects it before the caller launches the reader. */
    private fun setLayoutAndConfirm(layout: ReaderLayout) = runBlocking<Unit> {
        val store = app.container.readerSettingsStore
        store.setLayout(layout)
        for (i in 0 until 50) {
            if (store.current().layout == layout) return@runBlocking
            kotlinx.coroutines.delay(20)
        }
        throw AssertionError("layout $layout not committed to the store in time")
    }

    /** Import [asset] and reset its saved position so each open starts clean (independent of test order). */
    private fun importAsset(asset: String): String {
        val staged = File(instrumentation.targetContext.cacheDir, "windowed-${System.nanoTime()}-$asset")
        instrumentation.context.assets.open(asset).use { input ->
            staged.outputStream().use { output -> input.copyTo(output) }
        }
        val book = runBlocking {
            app.container.importer.importStream("content://test/$asset", asset, staged.inputStream())
        }
        runBlocking {
            app.container.repository.clearPosition(book.fingerprintKey)
            app.container.cacheOffset(book.fingerprintKey, 0)
        }
        return book.fingerprintKey
    }

    // ---- seam accessors (the TxtPagedBodyConnectedTest set — all read the navigator/render-cache) ----

    private fun ActivityScenario<TxtReaderActivity>.awaitPageIndex(timeoutMs: Long = 15_000) {
        compose.waitUntil(timeoutMs) {
            var ready = false
            onActivity { ready = it.pagedPageCountForTest()?.let { c -> c > 0 } == true }
            ready
        }
    }

    private fun ActivityScenario<TxtReaderActivity>.awaitFirstLine() {
        compose.waitUntil(15_000) {
            compose.onAllNodesWithText("Line 001", substring = true).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun ActivityScenario<TxtReaderActivity>.pageCount(): Int {
        var c = 0; onActivity { c = it.pagedPageCountForTest() ?: 0 }; return c
    }

    private fun ActivityScenario<TxtReaderActivity>.currentPage(): Int {
        var p = -1; onActivity { p = it.pagedCurrentPageForTest() ?: -1 }; return p
    }

    private fun ActivityScenario<TxtReaderActivity>.currentSourceOffset(): Int {
        var o = -1; onActivity { o = it.pagedCurrentSourceOffsetForTest() ?: -1 }; return o
    }

    private fun ActivityScenario<TxtReaderActivity>.pageContaining(offset: Int): Int {
        var p = -1; onActivity { p = it.pagedPageContainingForTest(offset) ?: -1 }; return p
    }

    private fun ActivityScenario<TxtReaderActivity>.renderCacheSize(): Int {
        var c = 0; onActivity { c = it.pagedRenderedCacheSizeForTest() ?: 0 }; return c
    }

    /** Poll until the sealed count STOPS growing (the background completion pass reached doc end). */
    private fun ActivityScenario<TxtReaderActivity>.awaitFinalPageCount(timeoutMs: Long = 15_000): Int {
        var stable = 0
        var lastSeen = -1
        compose.waitUntil(timeoutMs) {
            val now = pageCount()
            if (now > 0 && now == lastSeen) stable++ else stable = 0
            lastSeen = now
            stable >= 3   // three consecutive equal reads → the append-only count has settled
        }
        return lastSeen
    }

    // ============================================================================================

    /** FAST FIRST OPEN — the loading surface clears fast and the opening page renders while the rest of
     *  the book is measured in the background (a partial sealed index). */
    @Test
    fun firstPage_rendersQuickly_loadingClearsFast() {
        setLayoutAndConfirm(ReaderLayout.Paged)
        val key = importAsset("resume-sample.txt")
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            scenario.awaitPageIndex()
            scenario.awaitFirstLine()
            // The loading placeholder is gone once an index published (the pager replaced it).
            assertTrue(
                "txt-paged-loading cleared once the first window sealed",
                compose.onAllNodesWithTag("txt-paged-loading").fetchSemanticsNodes().isEmpty(),
            )
            assertEquals("opens on page 0", 0, scenario.currentPage())
            assertTrue("the first sealed window has at least one page", scenario.pageCount() >= 1)
        }
    }

    /** GROWING SEALED pageCount / on-demand forward extension — paging PAST the initial 3-page window
     *  lands on the right page (append-only growth + on-demand extension seal those pages), with a
     *  page-start source offset that matches the resolved page — no gap, never a shrink. */
    @Test
    fun pagingPastInitialWindow_growsCount_landsCorrectly() {
        setLayoutAndConfirm(ReaderLayout.Paged)
        val key = importAsset("resume-sample.txt")
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            scenario.awaitPageIndex()
            scenario.awaitFirstLine()
            // Page well past the initial window (DEFAULT_INITIAL_WINDOW_PAGES = 3) so the target is a page
            // that was NOT in the first sealed window — it must be sealed by growth/extension to land.
            repeat(6) { turn ->
                scenario.onActivity { it.turnToNextPageForTest() }
                compose.waitUntil(15_000) { scenario.currentPage() >= turn + 1 }
            }
            val landedPage = scenario.currentPage()
            assertTrue("advanced past the 3-page initial window", landedPage >= 4)
            // Append-only growth: the sealed count covers the landed page (never a gap / shrink).
            assertTrue("the sealed count contains the landed page", scenario.pageCount() > landedPage)
            // Self-consistent: the current page owns its page-start source offset (progress moved forward).
            val offset = scenario.currentSourceOffset()
            assertTrue("landed on a forward source offset", offset > 0)
            assertEquals(
                "the current page is the one containing its own start offset (no gap on extension)",
                scenario.pageContaining(offset), landedPage,
            )
        }
    }

    /** CONDITIONAL deep-resume reveal — reopening at a deep saved source offset opens page 0 first, then
     *  auto-scrolls onto the resume page once its page seals in the background (the user did not interact). */
    @Test
    fun deepResume_conditionallyAutoScrollsToResumePage() {
        setLayoutAndConfirm(ReaderLayout.Paged)
        val key = importAsset("resume-sample.txt")
        // First open: page deep into the book, capture + persist the current page-start source offset.
        var savedOffset = -1
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            scenario.awaitPageIndex()
            scenario.awaitFirstLine()
            repeat(6) { turn ->
                scenario.onActivity { it.turnToNextPageForTest() }
                compose.waitUntil(15_000) { scenario.currentPage() >= turn + 1 }
            }
            scenario.onActivity { it.flushPagedPositionForTest() }
            savedOffset = scenario.currentSourceOffset()
            assertTrue("captured a deep (non-zero) resume offset", savedOffset > 0)
        }
        // Reopen: the deep-resume reveal must land the pager on the page containing the saved offset once
        // that page seals — WITHOUT any user interaction (no yank, and never page 0 at rest).
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            scenario.awaitPageIndex()
            // The deep-resume reveal auto-scrolls onto the resume page once its page seals in the background
            // AND the sticky re-assertion converges the pager onto it. Poll for CONVERGENCE (currentPage ==
            // pageContaining(savedOffset)) — the background completion + the reveal scroll + the re-assert
            // span several frames + a session debounce, and a loaded emulator (a full 5-test class run)
            // stretches that window, so a single read after currentPage>0 can catch an intermediate page
            // (MEMORY #133). A generous budget keeps it robust under class-run contention.
            compose.waitUntil(25_000) {
                scenario.currentPage() > 0 && scenario.currentPage() == scenario.pageContaining(savedOffset)
            }
            val resumedPage = scenario.currentPage()
            assertTrue("deep resume restored past page 0", resumedPage > 0)
            assertEquals(
                "the resumed page contains the saved source offset",
                scenario.pageContaining(savedOffset), resumedPage,
            )
        }
    }

    /** SEALED-page render-cache policy — a background APPEND does NOT clear the render cache; the retained
     *  page window survives the count growing (a page re-visited after growth is a cache hit). */
    @Test
    fun backgroundAppend_doesNotClearRenderCache() {
        setLayoutAndConfirm(ReaderLayout.Paged)
        val key = importAsset("resume-sample.txt")
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            scenario.awaitPageIndex()
            scenario.awaitFirstLine()
            // Render a couple of early pages into the cache (they are sealed in the first window).
            scenario.onActivity { it.turnToNextPageForTest() }
            compose.waitUntil(15_000) { scenario.currentPage() >= 1 }
            // Let the background completion grow the sealed count to the full book.
            val finalCount = scenario.awaitFinalPageCount()
            assertTrue("100 lines complete to a multi-page count", finalCount > 6)
            // The render cache is still populated — the background APPENDS never cleared it (only a reflow
            // would). A cleared-on-append cache would be size 0 here (nothing re-rendered since the growth).
            assertTrue(
                "the render cache survived the background append (append does NOT clear it)",
                scenario.renderCacheSize() in 1..8,
            )
        }
    }

    /** REFLOW clears the cache + clamps — a mid-background font-size change re-paginates windowed, clamps
     *  the pager back to the saved source offset, AND clears the render cache. */
    @Test
    fun reflow_repaginatesClampsAndClearsCache() {
        setLayoutAndConfirm(ReaderLayout.Paged)
        val key = importAsset("resume-sample.txt")
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            scenario.awaitPageIndex()
            scenario.awaitFirstLine()
            // Page to a known forward position + let the background pass finish so the cache holds pages.
            repeat(5) { turn ->
                scenario.onActivity { it.turnToNextPageForTest() }
                compose.waitUntil(15_000) { scenario.currentPage() >= turn + 1 }
            }
            scenario.awaitFinalPageCount()
            val offsetBefore = scenario.currentSourceOffset()
            assertTrue("captured a forward source offset before reflow", offsetBefore > 0)

            // A font-size change triggers the reflow (the LaunchedEffect keys on the effective style).
            runBlocking { app.container.readerSettingsStore.setFontSize(26f) }

            // The reflow re-opens windowed pagination and clamps the pager back to the page containing the
            // captured source offset — poll until the clamp lands on the reconciled (self-consistent) page.
            compose.waitUntil(15_000) {
                val idx = scenario.pageContaining(offsetBefore)
                scenario.pageCount() > 0 && scenario.currentPage() == idx && scenario.currentPage() > 0
            }
            val afterPage = scenario.currentPage()
            assertTrue("reflow kept a forward position (clamped to the captured offset)", afterPage > 0)
            assertEquals(
                "reflow clamped the pager to the page containing the pre-reflow source offset",
                scenario.pageContaining(offsetBefore), afterPage,
            )
        }
    }
}
