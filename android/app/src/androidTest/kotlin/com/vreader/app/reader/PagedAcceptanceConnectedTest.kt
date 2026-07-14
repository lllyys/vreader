package com.vreader.app.reader

import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.lifecycle.lifecycleScope
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.VReaderApp
import com.vreader.app.reader.settings.ReaderFontFamily
import com.vreader.app.reader.settings.ReaderLayout
import com.vreader.app.reader.settings.ReaderSettings
import com.vreader.app.reader.settings.ReaderTheme
import kotlinx.coroutines.launch
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
 * Feature #137 WI-11 (final acceptance) — the CONSOLIDATED cross-cutting acceptance test that the
 * per-WI connected tests do NOT cover as one flow:
 *
 *  (1) LAYOUT TOGGLE ON 3 FORMATS — TXT and MD (the two NEW Compose paged formats this feature built) are
 *      asserted HERE: paged mode requires a mounted paginator with > 1 page, and scroll mode requires the
 *      paged body to report NOT mounted with body text present. The THIRD format, EPUB, is proven by the
 *      companion class `EpubPagedToggleConnectedTest` (Readium's real WebView columns: fresh-Paged open
 *      resolves paginated overflow, a horizontal page turn advances `currentLocator`, and the live Layout
 *      toggle flips overflow both ways). WI-11's Gate-5 connected invocation runs BOTH classes — this one
 *      for TXT/MD, `EpubPagedToggleConnectedTest` for EPUB — so all 3 formats' toggles are exercised. This
 *      class does NOT re-run the EPUB WebView flow (it would duplicate `EpubPagedToggleConnectedTest`, and
 *      per the WI-3 discovery a mid-read scroll→paged reflow does not reliably relayout the offscreen
 *      instrumentation WebView — a FRESH Paged open is what `EpubPagedToggleConnectedTest` exercises).
 *
 *  (2) POSITION SURVIVES BOTH DIRECTIONS — open at a known source offset in Paged, cross into Scroll and
 *      back to Paged (Paged→Scroll→Paged), and the reverse (Scroll→Paged→Scroll), asserting the reading
 *      position (the page-start / top-visible-chunk SOURCE offset) is PRESERVED in BOTH directions. This
 *      exercises the WI-6a page-start save (`onSaveSourceOffset`/`flushPagedPositionForTest`) + the
 *      layout-independent `charOffsetUTF16` restore (`computeInitialOffset`) + the WI-5 reflow
 *      reconciliation (`pageContaining`) as a round-trip across a layout change — the seam that makes the
 *      toggle non-destructive. A cross-layout re-open (not a live in-activity flip) is the deterministic
 *      driver: the scroll body's initial index is fixed at open, so the save→reopen path is where the
 *      cross-layout position contract actually lives.
 *
 * Reuses the `TxtPaged*ConnectedTest` seams: createEmptyComposeRule + ActivityScenario + compose.waitUntil
 * polling (NOT bare waitForIdle — it does not await the off-main pagination pass; MEMORY #125/#133). Run
 * ONE class per connected invocation (MEMORY #129/#133).
 */
@RunWith(AndroidJUnit4::class)
class PagedAcceptanceConnectedTest {
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

    /** Import [asset]; [resetPosition] zeroes BOTH the durable Room position AND the in-memory offset cache
     *  so an open that asserts a CLEAN start (page/chunk 0) is independent of test order. The
     *  position-survives tests pass resetPosition=true ONCE at their baseline open, then let the save flow
     *  persist the reading position across the cross-layout reopens. */
    private fun importAsset(asset: String, resetPosition: Boolean = true): String {
        val staged = File(instrumentation.targetContext.cacheDir, "accept-${System.nanoTime()}-$asset")
        instrumentation.context.assets.open(asset).use { input ->
            staged.outputStream().use { output -> input.copyTo(output) }
        }
        val book = runBlocking {
            app.container.importer.importStream("content://test/$asset", asset, staged.inputStream())
        }
        if (resetPosition) runBlocking {
            app.container.repository.clearPosition(book.fingerprintKey)
            app.container.cacheOffset(book.fingerprintKey, 0)   // clear the fast-path cache read first by resume
        }
        return book.fingerprintKey
    }

    // ---- seam accessors -------------------------------------------------------------------------

    /** For a BASELINE open at the START of the book (page/chunk 0): the opening "Line 001" is visible. */
    private fun ActivityScenario<TxtReaderActivity>.awaitBodyText() {
        compose.waitUntil(15_000) {
            compose.onAllNodesWithText("Line 001", substring = true).fetchSemanticsNodes().isNotEmpty()
        }
    }

    /** Format-agnostic "reader is up" signal for a REOPEN that RESUMES to a forward position (where "Line 001"
     *  is NOT on screen): the always-present read-aloud chrome entry (the TxtPagedBilingualGateConnectedTest
     *  precedent). Used after a cross-layout reopen where the body has scrolled/paged past the book start. */
    private fun ActivityScenario<TxtReaderActivity>.awaitReaderUp() {
        compose.waitUntil(15_000) {
            compose.onAllNodesWithTag("tts-read-aloud-entry").fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun ActivityScenario<TxtReaderActivity>.awaitPageIndex(timeoutMs: Long = 15_000) {
        compose.waitUntil(timeoutMs) {
            var ready = false
            onActivity { ready = it.pagedPageCountForTest()?.let { c -> c > 0 } == true }
            ready
        }
    }

    private fun ActivityScenario<TxtReaderActivity>.pagedMounted(): Boolean? {
        var v: Boolean? = null
        onActivity { v = it.pagedBodyMountedForTest() }
        return v
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

    private fun ActivityScenario<TxtReaderActivity>.firstVisibleChunk(): Int {
        var i = -1; onActivity { i = it.firstVisibleChunkForTest() ?: -1 }; return i
    }

    // ============================================================================================
    // (1) LAYOUT TOGGLE ON THE TWO NEW COMPOSE FORMATS (TXT + MD)
    // ============================================================================================

    @Test
    fun toggle_txt_pagedMountsAndPaginates_scrollDoesNot() {
        val key = importAsset("resume-sample.txt")

        // Paged: the paged body mounts and phase-1 paginates the 100-line file into > 1 page.
        setLayoutAndConfirm(ReaderLayout.Paged)
        ActivityScenario.launch<TxtReaderActivity>(TxtReaderActivity.intent(instrumentation.targetContext, key)).use { s ->
            s.awaitPageIndex()
            s.awaitBodyText()
            assertTrue("TXT paged: paged body mounts", s.pagedMounted() == true)
            assertTrue("TXT paged: 100 lines paginate > 1 page", s.pageCount() > 1)
        }

        // Scroll: the SAME book renders the LazyColumn; the paged body is NOT mounted.
        setLayoutAndConfirm(ReaderLayout.Scroll)
        ActivityScenario.launch<TxtReaderActivity>(TxtReaderActivity.intent(instrumentation.targetContext, key)).use { s ->
            s.awaitBodyText()
            assertNotNull(s.pagedMounted())
            assertTrue("TXT scroll: paged body NOT mounted", s.pagedMounted() == false)
        }
    }

    @Test
    fun toggle_md_pagedMountsAndPaginates_scrollDoesNot() {
        val key = importAsset("md-resume.md")

        setLayoutAndConfirm(ReaderLayout.Paged)
        ActivityScenario.launch<TxtReaderActivity>(TxtReaderActivity.intent(instrumentation.targetContext, key)).use { s ->
            s.awaitPageIndex()
            s.awaitBodyText()
            assertTrue("MD paged: paged body mounts", s.pagedMounted() == true)
            assertTrue("MD paged: 100 lines paginate > 1 page", s.pageCount() > 1)
        }

        setLayoutAndConfirm(ReaderLayout.Scroll)
        ActivityScenario.launch<TxtReaderActivity>(TxtReaderActivity.intent(instrumentation.targetContext, key)).use { s ->
            s.awaitBodyText()
            assertNotNull(s.pagedMounted())
            assertTrue("MD scroll: paged body NOT mounted", s.pagedMounted() == false)
        }
    }

    // ============================================================================================
    // (2) POSITION SURVIVES BOTH DIRECTIONS (Paged→Scroll→Paged  AND  Scroll→Paged→Scroll)
    // ============================================================================================

    @Test
    fun position_survives_pagedToScrollToPaged() {
        // Baseline: fresh Paged open at page 0, page forward a few times, capture + persist the page-start
        // SOURCE offset (the layout-independent charOffsetUTF16 anchor).
        val key = importAsset("resume-sample.txt", resetPosition = true)
        setLayoutAndConfirm(ReaderLayout.Paged)
        var savedOffset = -1
        var savedPage = -1
        ActivityScenario.launch<TxtReaderActivity>(TxtReaderActivity.intent(instrumentation.targetContext, key)).use { s ->
            s.awaitPageIndex()
            s.awaitBodyText()
            repeat(4) { turn ->
                s.onActivity { it.turnToNextPageForTest() }
                compose.waitUntil(15_000) { s.currentPage() >= turn + 1 }
            }
            s.onActivity { it.flushPagedPositionForTest() }   // persist the current page-start offset
            savedOffset = s.currentSourceOffset()
            savedPage = s.currentPage()
            assertTrue("advanced past page 0", savedPage >= 1)
            assertTrue("captured a non-zero source offset", savedOffset > 0)
        }

        // DIRECTION A — Paged → Scroll: reopen in Scroll; the top-visible chunk must be a real forward
        // position (NOT chunk 0) — the saved paged offset restored the scroll body past the start of the
        // book (position preserved crossing INTO scroll).
        setLayoutAndConfirm(ReaderLayout.Scroll)
        ActivityScenario.launch<TxtReaderActivity>(TxtReaderActivity.intent(instrumentation.targetContext, key)).use { s ->
            // Reader RESUMES to a forward position — "Line 001" is NOT on screen; wait on the format-agnostic
            // reader-up signal instead. The scroll body restores to initialIndex = chunkForOffset(savedOffset).
            s.awaitReaderUp()
            compose.waitUntil(15_000) { s.firstVisibleChunk() >= 1 }
            assertTrue("scroll restored past chunk 0 (position crossed into scroll)", s.firstVisibleChunk() >= 1)
        }

        // DIRECTION B — Scroll → Paged: reopen in Paged. The restored page must be a real forward page (NOT
        // page 0), be SELF-CONSISTENT (currentPage == pageContaining(the restored source offset)), and NOT
        // have drifted FORWARD past the original page. The "position preserved" contract is: the paged reopen
        // lands on the page that OWNS the persisted offset, never page 0 and never ahead of the original read.
        // We do NOT assert exact equality to pageContaining(savedOffset): the intermediate scroll reopen
        // re-saved the top-chunk START offset (≤ savedOffset by up to a chunk), so the restored page may be at
        // or a few pages BEHIND the original — but never AHEAD (that would be a real regression) and never 0.
        setLayoutAndConfirm(ReaderLayout.Paged)
        ActivityScenario.launch<TxtReaderActivity>(TxtReaderActivity.intent(instrumentation.targetContext, key)).use { s ->
            s.awaitPageIndex()
            compose.waitUntil(15_000) { (s.pageCount() > 0) && s.currentPage() > 0 }
            val restoredPage = s.currentPage()
            val originalPage = s.pageContaining(savedOffset)
            assertTrue("paged restored past page 0 (position crossed back into paged)", restoredPage > 0)
            assertEquals(
                "restored page is the one containing the restored source offset (self-consistent)",
                s.pageContaining(s.currentSourceOffset()), restoredPage,
            )
            assertTrue(
                "paged round-trip preserved position — at or behind the original page, never ahead, never 0 " +
                    "(restored=$restoredPage originalPage=$originalPage)",
                restoredPage in 1..originalPage,
            )
        }
    }

    @Test
    fun position_survives_scrollToPagedToScroll() {
        // Baseline: fresh SCROLL open, scroll down to a known chunk, persist its source offset (the scroll
        // body's flush saves offsetForChunk(topIndex)). The chunk index round-trips because chunk offsets
        // are stable: chunkForOffset(offsetForChunk(N)) == N.
        val key = importAsset("resume-sample.txt", resetPosition = true)
        setLayoutAndConfirm(ReaderLayout.Scroll)
        // Scroll well past the first screenful (chunk 60 of the 100-line file) so the containing PAGE is
        // guaranteed non-zero regardless of emulator dimensions/density/font metrics/chrome height (Gate-4
        // High-3 — a small target like 12 could fit on page 0 on some devices).
        val targetChunk = 60
        var savedChunk = -1
        ActivityScenario.launch<TxtReaderActivity>(TxtReaderActivity.intent(instrumentation.targetContext, key)).use { s ->
            s.awaitBodyText()
            runScrollTo(s, targetChunk)
            compose.waitUntil(15_000) { s.firstVisibleChunk() >= 1 }
            savedChunk = s.firstVisibleChunk()
            assertTrue("scrolled past chunk 0", savedChunk >= 1)
            // The SCROLL body persists the top-visible chunk's source offset on its own onStop flush AND its
            // 1s-debounced steady-state save; move the scenario to STOPPED so the onStop flush runs
            // deterministically (flushPagedPositionForTest is a paged-only seam — a no-op here), then the
            // cache holds offsetForChunk(savedChunk) for the next open's resume.
            s.moveToState(androidx.lifecycle.Lifecycle.State.CREATED)
            compose.waitUntil(5_000) {
                app.container.cachedOffset(key)?.let { it > 0 } == true
            }
        }

        // DIRECTION A — Scroll → Paged: reopen in Paged; the restored page must NOT be page 0 AND must be
        // self-consistent (currentPage == pageContaining(currentSourceOffset)) — the scroll position
        // (charOffsetUTF16) crossed non-destructively into paged.
        setLayoutAndConfirm(ReaderLayout.Paged)
        ActivityScenario.launch<TxtReaderActivity>(TxtReaderActivity.intent(instrumentation.targetContext, key)).use { s ->
            s.awaitPageIndex()
            compose.waitUntil(15_000) { (s.pageCount() > 0) && s.currentPage() > 0 }
            val restoredPage = s.currentPage()
            assertTrue("paged restored past page 0 (scroll position crossed into paged)", restoredPage > 0)
            assertEquals(
                "restored page is the one containing the current source offset (self-consistent restore)",
                s.pageContaining(s.currentSourceOffset()), restoredPage,
            )
        }

        // DIRECTION B — Paged → Scroll: reopen in Scroll. The round-trip is non-destructive: the top-visible
        // chunk must land back on a real forward position (NOT chunk 0) at or BEHIND the saved chunk, never
        // AHEAD of it. Exact equality is NOT asserted — the paged reopen in direction A re-saved the RESTORED
        // PAGE-START offset (the paged body saves on settle — TxtReaderBody:344-348), and a page spans MANY of
        // this fixture's one-line chunks, so the page start can fall several chunks before the saved one
        // (Gate-4 High-2 — a fixed savedChunk-1 window is too tight). The invariant that must hold: preserved
        // to page-start granularity — in [1, savedChunk], never forward past the saved position, never reset to 0.
        setLayoutAndConfirm(ReaderLayout.Scroll)
        ActivityScenario.launch<TxtReaderActivity>(TxtReaderActivity.intent(instrumentation.targetContext, key)).use { s ->
            // Reader RESUMES to a forward position — wait on the reader-up signal, not "Line 001".
            s.awaitReaderUp()
            compose.waitUntil(15_000) { s.firstVisibleChunk() >= 0 }
            val finalChunk = s.firstVisibleChunk()
            assertTrue("scroll restored past chunk 0 on the round-trip back", finalChunk >= 1)
            assertTrue(
                "scroll round-trip preserved position at page-start granularity — at or behind the saved chunk, " +
                    "never ahead (final=$finalChunk saved=$savedChunk)",
                finalChunk in 1..savedChunk,
            )
        }
    }

    /** Scroll the SCROLL body to [index] on the activity's thread (the WI-6a firstVisibleChunk seam has a
     *  matching scrollToItemForTest). Blocks until it lands. */
    private fun runScrollTo(scenario: ActivityScenario<TxtReaderActivity>, index: Int) {
        val latch = java.util.concurrent.CountDownLatch(1)
        val error = arrayOfNulls<Throwable>(1)
        scenario.onActivity { activity ->
            activity.lifecycleScope.launch {
                try { activity.scrollToItemForTest(index) } catch (t: Throwable) { error[0] = t } finally { latch.countDown() }
            }
        }
        if (!latch.await(20, java.util.concurrent.TimeUnit.SECONDS)) throw AssertionError("scrollTo timed out")
        error[0]?.let { throw it }
    }
}
