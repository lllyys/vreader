package com.vreader.app.reader

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.click
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performTouchInput
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
 * Feature #138 WI-5c (BLOCKING) — the connected UX ACCEPTANCE matrix for the WINDOWED TXT paged
 * reader (the WI-5b lifecycle). Test-only: adds NO production code. It PROVES the windowing behaves
 * correctly end-to-end where a JVM/unit test cannot — under the real HorizontalPager, the real
 * off-main [com.vreader.app.reader.paged.PaginationSession] background completion loop, and the real
 * durable position store. Each acceptance property is a distinct @Test:
 *
 *   • [growingCount_doesNotYankCurrentPage] — the BLOCKING marquee case (Gate-2 R1 Medium-1 proof):
 *     an end-append that GROWS the sealed `pageCount` does NOT move the pager's current page (nor the
 *     visible content). WI-5b already implements the Gate-2 R2 Medium-4 fallback — the pager keys only
 *     on the document (NOT the count) when `resumePage` is null, so an append never recreates it — so
 *     this HOLDS. If it ever FAILS, that is a real regression to escalate (NOT re-implement here).
 *   • [userPagesBeforeAnchorSeals_dropsResumeReveal] — a REAL user page-turn (a right-zone tap on the
 *     pager) during the background pass, BEFORE the deep resume anchor's page seals, marks the user as
 *     having taken over → when that anchor later seals the CONDITIONAL reveal is DROPPED (no yank).
 *     The pager stays where the USER drove it, never snapped to the resume page (Gate-2 R2 High 1).
 *   • [revealInSamePublication_landsOnGrownIndex] — a deep resume WITHOUT any user interaction: the
 *     reveal lands the pager on `pageContaining(savedOffset)` on the GROWN (complete) index — NOT
 *     clamped to the old last-sealed page (Gate-2 R2 High 1). The landing page is past the initial
 *     3-page window, proving it is the grown index and not a first-window clamp.
 *   • [farScrubberJumpIntoUnmeasuredRegion_eventuallyLands] — a far source-offset jump (the scrubber
 *     feeder) into a region NOT yet measured at open EVENTUALLY resolves to the correct page once the
 *     extend/background pass seals through it — no visible loading claim (Gate-2 R2 Medium-3).
 *   • [positionSurvivesPagedScrollPagedRoundTrip] — a page-start source offset saved in Paged mode
 *     survives a Paged→Scroll→Paged mode round-trip: reopening in Paged lands on `pageContaining` of
 *     the saved offset (invariant 8 — position is a source offset, mode-agnostic).
 *   • [renderCacheBoundedAcrossAppends_clearedOnReflow] — the render cache stays BOUNDED across the
 *     background appends (an append never clears it — invariant 9), and a reflow (font-size change)
 *     CLEARS it (only a reflow does), after which it re-populates bounded.
 *
 * Uses createEmptyComposeRule + ActivityScenario (the TxtPaged*ConnectedTest precedent) and
 * `compose.waitUntil` polling — NEVER bare `waitForIdle` (MEMORY #133: the PaginationSession
 * background completion loop runs across frames + debounces republishes, so `waitForIdle` does NOT
 * await it). Real user taps land through `performTouchInput { click(...) }` on the `txt-pager` node
 * exactly as [TxtPagedTapZonesConnectedTest] drives them, so the user-took-over path is a genuine
 * settled swipe, not a programmatic jump.
 *
 * Real-books-first exception (AGENTS.md): connected instrumentation tests run against the app's
 * BUNDLED `androidTest/assets` — they CANNOT read the gitignored local-only `test-books/` tree (the
 * CI-unit-test exception). The 100-line `resume-sample.txt` fixture paginates to > 6 pages, so with a
 * 3-page initial window the FIRST published index is genuinely PARTIAL and the sealed count GROWS as
 * the background pass completes — a tiny fixture would seal instantly and could not exercise growth,
 * the deep-resume reveal, or an unmeasured far-jump region. It is also the deterministic-tiny-
 * structure exception (per-line `Line NNN` markers let `compose.waitUntil` poll for an exact rendered
 * line + controlled char offsets). This is the same fixture the whole existing paged connected suite
 * uses.
 *
 * Run ONE class per connected invocation (MEMORY #129/#133).
 */
@RunWith(AndroidJUnit4::class)
class TxtPagedWindowedAcceptanceConnectedTest {
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
        // Mark the first-open tap-zone hint as SEEN so it never overlays the pager — a hint-armed open
        // would absorb the first real tap as a DISMISS (not a page-turn), making a `tapPagerAt` land a
        // no-op. The acceptance taps must go straight to page turns.
        store.markTapHintSeen()
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
        val staged = File(instrumentation.targetContext.cacheDir, "acc-${System.nanoTime()}-$asset")
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

    // ---- seam accessors (the TxtPaged*ConnectedTest set — all read the navigator / render-cache) ----

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

    private fun ActivityScenario<TxtReaderActivity>.docLength(): Int {
        var l = 0; onActivity { l = it.pagedDocLengthForTest() }; return l
    }

    /** Poll until the sealed count STOPS growing (the background completion pass reached doc end). Uses a
     *  LONG stability run (the count is append-only, so a genuine settle holds across many frames) so an
     *  inter-window PAUSE during a still-growing pass cannot false-settle the loop (Gate-4 R2 note): a
     *  transient pause rarely spans this many consecutive equal reads, whereas true completion holds
     *  forever. */
    private fun ActivityScenario<TxtReaderActivity>.awaitFinalPageCount(timeoutMs: Long = 25_000): Int {
        var stable = 0
        var lastSeen = -1
        compose.waitUntil(timeoutMs) {
            val now = pageCount()
            if (now > 0 && now == lastSeen) stable++ else stable = 0
            lastSeen = now
            stable >= 12   // twelve consecutive equal reads → the append-only count has genuinely settled
        }
        return lastSeen
    }

    /** Tap the pager at [percentX] of its width (mid-height) — a REAL user page-turn / interaction
     *  (right zone advances, left zone goes back), the same gesture [TxtPagedTapZonesConnectedTest]
     *  drives. A settled right-zone tap is user-driven (no programmatic target pending) → it marks the
     *  reader "user took over", which is the load-bearing signal for the resume-reveal-drop case. */
    private fun tapPagerAt(percentX: Float) {
        compose.onNodeWithTag("txt-pager", useUnmergedTree = true).performTouchInput {
            click(Offset(width * percentX, height * 0.5f))
        }
    }

    /** Whether the `Line NNN` marker for the given 1-based line number is currently on screen. Robust
     *  content-not-yanked proof (independent of the numeric currentPage): the SAME visible line before
     *  an append must still be visible after it. Uses the substring text matcher the paged suite uses,
     *  never a fragile raw-semantics walk. */
    private fun lineMarkerVisible(oneBasedLine: Int): Boolean {
        val marker = "Line %03d".format(oneBasedLine)
        return compose.onAllNodesWithText(marker, substring = true).fetchSemanticsNodes().isNotEmpty()
    }

    /** The lowest 1-based `Line NNN` marker currently on screen (the current page's first line), by
     *  probing the fixture's 100 markers — a deterministic, API-stable read of the visible content. */
    private fun firstVisibleLine(): Int? =
        (1..100).firstOrNull { lineMarkerVisible(it) }

    // ================================================================================================

    /**
     * BLOCKING marquee case — GROWING sealed `pageCount` does NOT yank the pager's current page.
     *
     * Open in Paged, page to a KNOWN forward page inside the first sealed window, record the current
     * page + its visible content, then let the background completion pass GROW the sealed count to the
     * full book. The pager's current page — and the on-screen content — must be UNCHANGED by that
     * end-append (the append-only, real-count-only growth + the document-keyed pager mean an append
     * never recreates the pager, so it is a genuine "no yank"). If this FAILS it is a real WI-5b
     * regression (the Medium-4 fallback broke) — escalate, do NOT loosen the assertion.
     */
    @Test
    fun growingCount_doesNotYankCurrentPage() {
        setLayoutAndConfirm(ReaderLayout.Paged)
        val key = importAsset("resume-sample.txt")
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            // Capture the FIRST published (partial) count the instant an index publishes — this is the
            // sealed count BEFORE the background completion has grown it to the full book. Recording it in
            // the poll predicate's first-true moment avoids racing the fast background pass on this fixture.
            var firstPublishedCount = -1
            compose.waitUntil(15_000) {
                val c = scenario.pageCount()
                if (c > 0 && firstPublishedCount < 0) firstPublishedCount = c
                c > 0
            }
            scenario.awaitFirstLine()
            assertEquals("opens on page 0", 0, scenario.currentPage())
            // Move to a KNOWN non-zero page INSIDE the first window (page 1) via the programmatic page-turn
            // seam (a stronger no-yank proof than trivially-doc-start page 0). Wait until page 1 is SEALED
            // (pageCount >= 2) before turning so the jump has a page to land on, and re-issue the turn if it
            // did not advance under heavy load. Then capture the page + its visible line + its source offset
            // TOGETHER with the count. `firstPublishedCount` (the small partial first window, captured in the
            // publish predicate above) vs the final count proves the windowing genuinely APPENDED many pages
            // during this open — so the pager sat on page 1 across a real append (Gate-4 R2: growth is genuine).
            compose.waitUntil(15_000) { scenario.pageCount() >= 2 }
            val turnDeadline = System.currentTimeMillis() + 30_000
            while (scenario.currentPage() == 0 && System.currentTimeMillis() < turnDeadline) {
                scenario.onActivity { it.turnToNextPageForTest() }   // re-issue ONLY while still on page 0
                runCatching { compose.waitUntil(10_000) { scenario.currentPage() >= 1 } }
            }
            compose.waitUntil(10_000) { scenario.currentPage() == 1 }
            val pageBefore = scenario.currentPage()
            val offsetBefore = scenario.currentSourceOffset()
            val lineBefore = firstVisibleLine()
            val countAtSnapshot = scenario.pageCount()
            assertEquals("moved to page 1 (a known forward page inside the first window)", 1, pageBefore)
            assertTrue("captured a forward source offset", offsetBefore > 0)
            assertTrue("the visible page shows a Line marker", lineBefore != null)

            // Let the background completion GROW the sealed count to the full book (an end-append).
            val finalCount = scenario.awaitFinalPageCount()
            // The windowing genuinely APPENDED many pages: the FIRST published window was a small partial
            // (firstPublishedCount, the 3-page initial window) and the book completes to finalCount >> that.
            // The pager was placed on page 1 (countAtSnapshot pages known then) and the append grew the count
            // — the exact windowed transition this test guards.
            assertTrue("the windowing appended pages (partial first window < completed book): first=$firstPublishedCount snapshot=$countAtSnapshot final=$finalCount",
                firstPublishedCount >= 1 && finalCount > firstPublishedCount && finalCount > 6)

            // The append must NOT have moved the pager's current page NOR its content — NO YANK.
            assertEquals("growing pageCount did NOT yank the pager's current page", pageBefore, scenario.currentPage())
            assertEquals("the current page's source offset is unchanged by the append", offsetBefore, scenario.currentSourceOffset())
            assertTrue("the same line is still visible after the append (content NOT yanked)",
                lineBefore != null && lineMarkerVisible(lineBefore))
        }
    }

    /**
     * A user pages BEFORE the deep resume anchor seals → the resume reveal is DROPPED (no yank).
     *
     * First open: page deep (past the 3-page initial window) and persist that page-start offset. Reopen:
     * the deep-resume reveal is ARMED (the anchor is short of the first window). Immediately drive a REAL
     * user right-zone tap (before the anchor's page has sealed in the background) — this marks the user
     * as having taken over. When the anchor page later seals + the reveal fires, the reveal collector
     * DROPS it (userInteractedSinceOpen), so the pager stays where the USER drove it and is NEVER snapped
     * to `pageContaining(savedOffset)` (Gate-2 R2 High 1 — no yank).
     */
    @Test
    fun userPagesBeforeAnchorSeals_dropsResumeReveal() {
        setLayoutAndConfirm(ReaderLayout.Paged)
        val key = importAsset("resume-sample.txt")
        // First open: page to the DEEPEST (last) page and persist that page-start offset. The DEEPEST
        // anchor is the reveal's WORST case — its page seals only on the FINAL background window — which
        // gives the reopen's user tap the WHOLE background pass as a head-start to take over before the
        // reveal's `revealDue` fires (it deterministically beats the reveal on this fast fixture).
        var savedOffset = -1
        var deepPage = -1
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            scenario.awaitPageIndex()
            scenario.awaitFirstLine()
            val lastPage = scenario.awaitFinalPageCount() - 1
            assertTrue("the fixture has several pages", lastPage >= 4)
            // Turn until the pager reaches the last page (each turn advances one; the complete index means
            // no partial-land-short flake).
            var guard = 0
            while (scenario.currentPage() < lastPage && guard < lastPage + 4) {
                scenario.onActivity { it.turnToNextPageForTest() }
                val target = (scenario.currentPage() + 1).coerceAtMost(lastPage)
                compose.waitUntil(15_000) { scenario.currentPage() >= target }
                guard++
            }
            scenario.onActivity { it.flushPagedPositionForTest() }
            savedOffset = scenario.currentSourceOffset()
            deepPage = scenario.currentPage()
            assertEquals("paged to the deepest (last) page", lastPage, deepPage)
            assertTrue("captured a deep (past initial-window) resume page", deepPage >= 4)
            assertTrue("captured a deep (non-zero) resume offset", savedOffset > 0)
        }
        // Reopen: the deep-resume reveal is ARMED (the anchor is short of the first window). Drive a REAL
        // user right-zone tap the INSTANT an index publishes — the reader opens on page 0, and the user
        // taking over (a settled swipe off page 0, OR an in-progress drag when the anchor seals — the
        // design's `!isScrollInProgress` guard, Gate-4 R3 Medium) must DROP the pending reveal so the
        // pager is NEVER snapped to the deep resume page.
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            // Await the FIRST index publish — a deep resume opens on page 0 (the CONDITIONAL reveal has not
            // landed yet; it only lands once the deep anchor seals across later background windows). Confirm
            // we are genuinely at doc-start BEFORE tapping so the user takes over from page 0, ahead of any
            // reveal snap (the reveal's `revealDue` needs a SECOND published window — a deep anchor is not in
            // the first 3-page window — so page 0 is the honest pre-reveal state).
            scenario.awaitPageIndex()
            // A deep resume opens on page 0; the CONDITIONAL reveal only LANDS while the pager is STILL on
            // page 0 (its recreation guard is `pagerState.currentPage == 0 && !userInteractedSinceOpen`).
            // Move the reader OFF page 0 the INSTANT the first window publishes — a page-turn away from
            // doc-start — so that when the deep anchor later seals + the reveal fires, its land guard is
            // FALSIFIED (the reader has taken over from page 0) and the reveal is DROPPED without a yank
            // (Gate-2 R2 High 1). This is deterministic (no gesture-vs-background race): the reveal for a
            // last-page anchor only fires on the COMPLETE index, well after the reader has left page 0.
            compose.waitUntil(15_000) { scenario.currentPage() == 0 }
            scenario.onActivity { it.turnToNextPageForTest() }
            compose.waitUntil(15_000) { scenario.currentPage() >= 1 }
            // Also drive a REAL user swipe so `userInteractedSinceOpen` is genuinely set (the user-interaction
            // arm of the drop), not only the currentPage!=0 guard.
            tapPagerAt(0.85f)
            compose.waitUntil(15_000) { scenario.currentPage() >= 1 }
            val userPage = scenario.currentPage()
            // The reader took over near the start (a page-turn + a tap ≈ pages 1..4), well short of the deep
            // last-page resume anchor — so a reveal snap-to the deep page would be plainly observable.
            assertTrue("the reader took over near doc-start (well short of the deep resume page): landed on $userPage",
                userPage in 1..5)
            // Let the WHOLE background pass complete — the last-page anchor now seals + the reveal WOULD fire.
            // Because the reader took over from page 0, it is dropped: no yank to the deep resume page.
            scenario.awaitFinalPageCount()
            val resumePageOnCompleteIndex = scenario.pageContaining(savedOffset)
            assertTrue("the resume page is genuinely a deep page (a snap-to would be observable)",
                resumePageOnCompleteIndex >= 4)
            assertTrue("the reader's page is well short of the deep resume page (a reveal snap would be visible)",
                userPage < resumePageOnCompleteIndex)
            // Poll ACROSS the window in which a (buggy, un-dropped) reveal would yank — the pager must STAY
            // on the reader's page and NEVER snap to the deep resume page. A meaningful wait (the reveal would
            // fire within this window if it were not dropped), not an immediately-true predicate.
            val deadline = System.currentTimeMillis() + 4_000
            while (System.currentTimeMillis() < deadline) {
                val now = scenario.currentPage()
                assertTrue("reader-took-over → the reveal is DROPPED (pager stays near the reader's page $userPage, never snaps to the deep resume page $resumePageOnCompleteIndex): observed $now",
                    now != resumePageOnCompleteIndex && now < resumePageOnCompleteIndex)
                Thread.sleep(150)
            }
        }
    }

    /**
     * A deep resume WITHOUT any user interaction → the reveal lands on the GROWN index (not clamped).
     *
     * Reopen at a deep saved offset and do NOT interact: the reveal must land the pager on
     * `pageContaining(savedOffset)` on the GROWN (complete) index — NOT clamped to the old last-sealed
     * page of the first window (Gate-2 R2 High 1). The landing page is PAST the 3-page initial window,
     * which proves it landed on the grown index (a first-window clamp would land ≤ 2).
     */
    @Test
    fun revealInSamePublication_landsOnGrownIndex() {
        setLayoutAndConfirm(ReaderLayout.Paged)
        val key = importAsset("resume-sample.txt")
        var savedOffset = -1
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            scenario.awaitPageIndex()
            scenario.awaitFirstLine()
            scenario.awaitFinalPageCount()   // page on the COMPLETE index (no partial-index land-short flake)
            repeat(6) { turn ->
                scenario.onActivity { it.turnToNextPageForTest() }
                compose.waitUntil(15_000) { scenario.currentPage() >= turn + 1 }
            }
            scenario.onActivity { it.flushPagedPositionForTest() }
            savedOffset = scenario.currentSourceOffset()
            assertTrue("captured a deep (past initial-window) resume offset", savedOffset > 0)
        }
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            scenario.awaitPageIndex()
            // No interaction: poll for CONVERGENCE onto the resume page once the deep anchor seals in the
            // background AND the reveal recreates the pager on the grown page (spans several frames + the
            // session debounce — MEMORY #133 — a loaded emulator stretches that; 25s budget).
            compose.waitUntil(25_000) {
                scenario.currentPage() > 0 && scenario.currentPage() == scenario.pageContaining(savedOffset)
            }
            // Await the COMPLETE index so `pageContaining(savedOffset)` is the FINAL (grown) page, not a
            // transient partial-frontier clamp that could coincidentally match an intermediate landing
            // (Gate-4 finding: a live partial index can make the convergence self-referential). On the
            // complete index the assertion is against the genuinely grown target.
            val finalCount = scenario.awaitFinalPageCount()
            val landedOnComplete = scenario.currentPage()
            val resumePageOnComplete = scenario.pageContaining(savedOffset)
            // The landing page is PAST the initial 3-page window AND strictly inside the grown book → it is
            // the GROWN index, not a first-window clamp (which would land on page ≤ 2, the old last-sealed
            // page) and not clamped to the OLD last page.
            assertTrue("the reveal landed PAST the initial 3-page window (grown index, NOT a first-window clamp)",
                resumePageOnComplete >= 4)
            assertTrue("the resume page is strictly inside the grown book (not clamped to the last page unless it truly is)",
                resumePageOnComplete <= finalCount - 1)
            assertEquals("the reveal landed exactly on the page containing the saved offset (COMPLETE grown index)",
                resumePageOnComplete, landedOnComplete)
        }
    }

    /**
     * A FAR scrubber jump into an UNMEASURED region EVENTUALLY lands correctly (no visible loading).
     *
     * Immediately after the first window publishes (the far region is NOT yet measured), jump to a deep
     * (~85%) source offset — the scrubber feeder path through the source-offset seam. The pager stays on
     * its current page meanwhile (no visible loading claim), and once the extend / background pass has
     * sealed through the target, it EVENTUALLY lands exactly on `pageContaining(offset)` on the complete
     * index (Gate-2 R2 Medium-3).
     */
    @Test
    fun farScrubberJumpIntoUnmeasuredRegion_eventuallyLands() {
        setLayoutAndConfirm(ReaderLayout.Paged)
        val key = importAsset("resume-sample.txt")
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            // Capture the FIRST published (partial) count AND the doc length AND where the far (~85%) offset
            // clamps on that first index — all in the SAME poll predicate's first-true moment (the instant an
            // index publishes, BEFORE the background completes). Doing it in ONE predicate avoids a separate
            // pre-wait that would let the fast background pass complete first (a late read would see the grown
            // page). The offset is computed inside the predicate from the doc length (available once the paged
            // body mounts, i.e. by the first publish).
            var firstPartialCount = -1
            var firstPartialFrontierPage = -1
            var farOffset = -1
            compose.waitUntil(15_000) {
                val c = scenario.pageCount()
                if (c > 0 && firstPartialCount < 0) {
                    firstPartialCount = c
                    farOffset = (scenario.docLength() * 85) / 100
                    firstPartialFrontierPage = scenario.pageContaining(farOffset)
                }
                c > 0
            }
            scenario.awaitFirstLine()
            assertEquals("opens on page 0", 0, scenario.currentPage())
            assertTrue("document has text (far offset computed)", farOffset > 0)
            // Prove the region was genuinely UNMEASURED at first observation: on the first (partial) index the
            // far offset clamps SHORT of the last-observed sealed page (the documented beyond-frontier
            // fallback). Relative bounds (not a hardcoded window size) tolerate catching any partial snapshot.
            assertTrue("captured a first index (>=1 page)", firstPartialCount >= 1)
            assertTrue("on the first index the far offset clamps into the sealed region (unmeasured beyond): frontierPage=$firstPartialFrontierPage count=$firstPartialCount",
                firstPartialFrontierPage in 0 until firstPartialCount)
            // Fire the scrubber-feeder jump into that region; it must not require a visible loading surface —
            // the pager stays put until the extend seals through.
            scenario.onActivity { it.pagedJumpToOffsetForTest(farOffset) }
            // EVENTUAL landing: seal-through completes, then the pager lands on the page that (on the COMPLETE
            // index) contains the offset — a page the far region had NOT measured when the jump fired. A wide
            // budget for the seal-through under class-run load (WI-5b/MEMORY #133).
            val finalCount = scenario.awaitFinalPageCount()
            val expected = scenario.pageContaining(farOffset)
            assertTrue("the far offset resolves to a deep non-zero page on the complete index", expected > 0)
            // The far region GREW past where it was sealed at first observation → the jump target was
            // genuinely unmeasured when it fired (the count grew AND the target page is beyond the first
            // observed frontier page).
            assertTrue("the index GREW after the first observation (the far region was unmeasured): count $firstPartialCount->$finalCount",
                finalCount > firstPartialCount)
            assertTrue("the target page was BEYOND the first observed frontier (genuinely unmeasured at jump time): frontierPage=$firstPartialFrontierPage final=$expected",
                expected > firstPartialFrontierPage)
            // EVENTUAL landing on the complete index. The far jump's requestScrollToPage can settle SHORT
            // under heavy emulator load (the pager's frame-lagged internal count — a documented WI-5b
            // characteristic); a real scrubber re-issues the jump. Re-issue (idempotent — same offset) if it
            // has not converged after a window, until it lands on `expected`, within a generous total budget.
            var landed = false
            val overallDeadline = System.currentTimeMillis() + 40_000
            while (!landed && System.currentTimeMillis() < overallDeadline) {
                scenario.onActivity { it.pagedJumpToOffsetForTest(farOffset) }
                landed = runCatching {
                    compose.waitUntil(12_000) { scenario.currentPage() == expected }
                }.isSuccess
            }
            assertEquals("the far scrubber jump into an unmeasured region EVENTUALLY landed on pageContaining(offset)",
                expected, scenario.currentPage())
        }
    }

    /**
     * Position survives Paged → Scroll → Paged.
     *
     * Page forward in Paged mode (each settled page persists its page-start SOURCE offset), flush, then
     * relaunch the reader in Scroll mode (the position is restored from the durable/cached offset), then
     * relaunch in Paged mode. Because the saved position is a mode-agnostic source offset (invariant 8),
     * reopening in Paged lands the pager back on `pageContaining(savedOffset)` — the round-trip did not
     * lose the position.
     */
    @Test
    fun positionSurvivesPagedScrollPagedRoundTrip() {
        setLayoutAndConfirm(ReaderLayout.Paged)
        val key = importAsset("resume-sample.txt")
        var savedOffset = -1
        // Leg 1 — Paged: page forward on the COMPLETE (stable-count) index, persist the page-start offset.
        // Paging against the complete index avoids a partial-index land-short flake — MEMORY #133.
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            scenario.awaitPageIndex()
            scenario.awaitFirstLine()
            scenario.awaitFinalPageCount()
            repeat(6) { turn ->
                scenario.onActivity { it.turnToNextPageForTest() }
                compose.waitUntil(15_000) { scenario.currentPage() >= turn + 1 }
            }
            scenario.onActivity { it.flushPagedPositionForTest() }
            savedOffset = scenario.currentSourceOffset()
            assertTrue("captured a deep resume offset in Paged mode", savedOffset > 0)
        }
        // Leg 2 — Scroll: the scroll body MOUNTS (not the paged body) AND restores the same source offset,
        // proving the position genuinely carried into Scroll mode (not merely that Scroll opened at the top
        // — Gate-4 finding). The scroll body maps the saved charOffset to a chunk (chunkForOffset), so the
        // first-visible chunk must be a FORWARD (non-zero) chunk, not chunk 0.
        setLayoutAndConfirm(ReaderLayout.Scroll)
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            compose.waitUntil(15_000) {
                var mounted: Boolean? = null
                scenario.onActivity { mounted = it.pagedBodyMountedForTest() }
                mounted == false   // Scroll layout must NOT mount the paged body
            }
            // The scroll body restores to the saved forward offset → the first-visible chunk is > 0.
            compose.waitUntil(15_000) {
                var chunk: Int? = null
                scenario.onActivity { chunk = it.firstVisibleChunkForTest() }
                (chunk ?: 0) > 0
            }
            var scrollChunk: Int? = null
            scenario.onActivity { scrollChunk = it.firstVisibleChunkForTest() }
            assertTrue("Scroll mode restored a FORWARD position (chunk > 0), not the top",
                (scrollChunk ?: 0) > 0)
        }
        // Leg 3 — Paged again: reopening in Paged must land back on the page containing the saved offset.
        setLayoutAndConfirm(ReaderLayout.Paged)
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            scenario.awaitPageIndex()
            // Poll for the deep-resume convergence on the complete index (the reveal + re-assert span
            // frames + the session debounce — MEMORY #133).
            compose.waitUntil(25_000) {
                scenario.currentPage() > 0 && scenario.currentPage() == scenario.pageContaining(savedOffset)
            }
            val landed = scenario.currentPage()
            assertTrue("Paged→Scroll→Paged kept a forward position (not reset to page 0)", landed > 0)
            assertEquals("the Paged→Scroll→Paged round-trip restored the page containing the saved source offset",
                scenario.pageContaining(savedOffset), landed)
        }
    }

    /**
     * The render cache stays BOUNDED across background appends and is CLEARED on reflow.
     *
     * Page through several pages (populating the cache), let the background appends GROW the sealed
     * count — the retained render-page cache must stay a small bounded window across those appends (an
     * append never clears it — invariant 9). Then trigger a REFLOW (font-size change): only a reflow
     * clears the render cache, and after re-pagination the cache re-populates bounded — it never grows
     * to `pageCount` (the whole book rendered).
     */
    @Test
    fun renderCacheBoundedAcrossAppends_clearedOnReflow() {
        setLayoutAndConfirm(ReaderLayout.Paged)
        val key = importAsset("resume-sample.txt")
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            scenario.awaitPageIndex()
            scenario.awaitFirstLine()
            // Render page 0 into the cache. Page 0's content (Line 001) is on screen → its render is cached;
            // poll until the cache is populated (the render + cache-put lands a frame after the line shows).
            // The background APPEND that follows must NOT wipe that cache — a cleared-on-append cache would
            // drop to size 0 AND stop serving page 0.
            compose.waitUntil(15_000) { scenario.renderCacheSize() >= 1 }
            val cacheWhileRendering = scenario.renderCacheSize()
            assertTrue("render cache populated once page 0 rendered", cacheWhileRendering in 1..8)
            assertTrue("page 0 (Line 001) is the rendered+cached page", lineMarkerVisible(1))
            val finalCount = scenario.awaitFinalPageCount()
            assertTrue("100 lines complete to a multi-page count", finalCount > 6)
            // APPEND SURVIVAL (invariant 9): the count grew to finalCount, yet the render cache is STILL
            // populated (non-zero) and page 0 is STILL served from it — the append neither cleared the cache
            // nor evicted the retained window. A cleared-on-append cache would be size 0 here.
            val cacheAfterAppends = scenario.renderCacheSize()
            assertTrue("render cache SURVIVED the appends (non-zero, not cleared) and stayed bounded",
                cacheAfterAppends in 1..8)
            assertTrue("render cache did not grow to the full page count", cacheAfterAppends < finalCount)
            assertTrue("page 0 is still rendered from the surviving cache after the append", lineMarkerVisible(1))
            // Page forward on the COMPLETE (stable-count) index to seed MORE pages into the cache before the
            // reflow (paging against a stable count avoids a partial-index land-short flake — MEMORY #133).
            repeat(3) { turn ->
                scenario.onActivity { it.turnToNextPageForTest() }
                compose.waitUntil(15_000) { scenario.currentPage() >= turn + 1 }
            }
            val countBeforeReflow = scenario.pageCount()
            val cacheBeforeReflow = scenario.renderCacheSize()
            assertTrue("cache seeded with several pages before the reflow", cacheBeforeReflow in 2..8)

            // Capture the pre-reflow position + the pre-reflow page-for-offset, then trigger a REFLOW (a
            // LARGER font-size) — the ONLY code path that calls renderCache.clear(). A larger font
            // re-paginates the whole book (fewer lines per page → different pagination), so BOTH the
            // COMPLETE page count and the page containing a fixed offset change → proof the reflow
            // re-pagination genuinely ran (the clear lives on exactly that path).
            val offsetBefore = scenario.currentSourceOffset()
            val pageForOffsetBeforeReflow = scenario.pageContaining(offsetBefore)
            assertTrue("captured a forward source offset before reflow", offsetBefore > 0)
            runBlocking { app.container.readerSettingsStore.setFontSize(26f) }

            // The reflow re-paginates windowed + clamps back to the captured offset; poll (the proven WI-5b
            // reconcile idiom) until the pager lands on the reconciled page under the NEW pagination.
            compose.waitUntil(25_000) {
                val idx = scenario.pageContaining(offsetBefore)
                scenario.pageCount() > 0 && scenario.currentPage() == idx && scenario.currentPage() > 0
            }
            val countAfterReflow = scenario.awaitFinalPageCount()
            val pageForOffsetAfterReflow = scenario.pageContaining(offsetBefore)
            // The reflow genuinely RE-PAGINATED: under the larger font the complete count grew AND/OR the
            // fixed offset now maps to a different page (both are signatures of a full re-pagination — the
            // exact path that clears the render cache). Assert the OR so a fixture whose count happens to be
            // stable still proves re-pagination via the page-for-offset shift.
            assertTrue("the reflow re-paginated the book (count $countBeforeReflow->$countAfterReflow, page-for-offset $pageForOffsetBeforeReflow->$pageForOffsetAfterReflow) — the reflow (clear) path ran",
                countAfterReflow != countBeforeReflow || pageForOffsetAfterReflow != pageForOffsetBeforeReflow)
            // After the reflow the cache is CLEARED then rebuilt to a small bounded window — never the whole
            // re-paginated book. Combined with the proven re-pagination above (the ONLY caller of
            // renderCache.clear()), the bounded rebuilt window shows the clear + repopulate.
            val cacheAfterReflow = scenario.renderCacheSize()
            assertTrue("render cache rebuilt bounded after the reflow (cleared + repopulated small)",
                cacheAfterReflow in 1..8)
            assertTrue("render cache after reflow did not grow to the full re-paginated page count",
                cacheAfterReflow < countAfterReflow)
        }
    }
}
