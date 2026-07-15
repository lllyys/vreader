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
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * feature #138 WI-5a — connected proof that the EXTERNAL JUMP SEAM now routes a SOURCE OFFSET (not a
 * pre-computed page), behavior-PRESERVING on the whole-doc (complete) WI-4 index:
 *   • a source-offset jump (bookmark / search / scrubber / TTS-follow feeders) through the retyped seam
 *     (`pagedJumpToOffsetForTest`, which now raises a SOURCE offset into the body's `jumpToSourceOffset`)
 *     STILL lands on `pageContaining(offset)` — the pager reaches the exact page it does today;
 *   • an in-body (near) offset AND a far (mid-book) offset both land exactly, because the WI-5a index is
 *     COMPLETE (no partial frontier — the async beyond-frontier EVENTUAL path is WI-5b, NOT tested here);
 *   • the source offset is resolved SYNCHRONOUSLY by the body via the navigator's synchronous
 *     `jumpToOffset(offset)` overload → `pageContaining` — the seam no longer converts source→page on the
 *     UI thread.
 *
 * createEmptyComposeRule + ActivityScenario + compose.waitUntil polling (the TxtPaged*ConnectedTest
 * precedent — bare waitForIdle does NOT await the off-main pagination pass, and the paged body settles
 * across frames — MEMORY #133). Run ONE class per connected invocation (MEMORY #129/#133).
 */
@RunWith(AndroidJUnit4::class)
class TxtPagedSourceOffsetJumpConnectedTest {
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
        val staged = File(instrumentation.targetContext.cacheDir, "pgsoj-${System.nanoTime()}-$asset")
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

    private fun ActivityScenario<TxtReaderActivity>.pageContaining(offset: Int): Int {
        var p = -1
        onActivity { p = it.pagedPageContainingForTest(offset) ?: -1 }
        return p
    }

    private fun ActivityScenario<TxtReaderActivity>.pageCount(): Int {
        var c = 0; onActivity { c = it.pagedPageCountForTest() ?: 0 }; return c
    }

    /** feature #138 WI-5b — the paged index is now published WINDOWED: at open it may be PARTIAL (only the
     *  first sealed window), so `pageContaining(farOffset)` clamps to the last sealed page until the
     *  background completion pass finishes. Poll until the sealed count STOPS growing so a far offset
     *  resolves to its FINAL page (a fresh open on a loaded class run stretches that window — MEMORY #133). */
    private fun ActivityScenario<TxtReaderActivity>.awaitCompleteIndex(timeoutMs: Long = 20_000): Int {
        var stable = 0
        var lastSeen = -1
        compose.waitUntil(timeoutMs) {
            val now = pageCount()
            if (now > 0 && now == lastSeen) stable++ else stable = 0
            lastSeen = now
            stable >= 3
        }
        return lastSeen
    }

    private fun ActivityScenario<TxtReaderActivity>.docLength(): Int {
        var l = 0
        onActivity { l = it.pagedDocLengthForTest() }
        return l
    }

    private fun openPaged(): ActivityScenario<TxtReaderActivity> {
        setLayoutAndConfirm(ReaderLayout.Paged)
        val key = importAsset("resume-sample.txt")
        val scenario = ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        )
        scenario.awaitPageIndex()
        compose.waitUntil(15_000) {
            compose.onAllNodesWithText("Line 001", substring = true).fetchSemanticsNodes().isNotEmpty()
        }
        return scenario
    }

    /** A NEAR (in-body, still non-zero) source offset lands on pageContaining(offset) through the seam. */
    @Test
    fun nearSourceOffsetJump_landsOnPageContaining() {
        openPaged().use { scenario ->
            assertEquals("opens on page 0", 0, scenario.currentPage())
            scenario.awaitCompleteIndex()   // WI-5b: resolve pageContaining on the COMPLETE (not partial) index
            val length = scenario.docLength()
            assertTrue("document has text", length > 0)
            // ~15% in — a modest offset that still resolves to a page beyond 0 for this sample.
            val offset = (length * 15) / 100
            val expected = scenario.pageContaining(offset)
            assertTrue("a modest offset resolves to a real page", expected >= 0)

            scenario.onActivity { it.pagedJumpToOffsetForTest(offset) }
            compose.waitUntil(25_000) { scenario.currentPage() == expected }
            assertEquals("source-offset jump landed on pageContaining(offset)", expected, scenario.currentPage())
        }
    }

    /** A FAR (mid/late-book) source offset lands EXACTLY on pageContaining(offset) — the WI-5a index is
     *  COMPLETE, so a far jump is exact, not eventual (the eventual beyond-frontier case is WI-5b). */
    @Test
    fun farSourceOffsetJump_landsExactlyOnPageContaining() {
        openPaged().use { scenario ->
            // WI-5b: the index is now published WINDOWED, so a far offset's page is only known once the
            // background completion (or the jump's own ensureMeasuredThrough) has sealed through it. Wait
            // for the complete index so `expected` is the FINAL page, then jump + poll for convergence.
            scenario.awaitCompleteIndex()
            val length = scenario.docLength()
            // ~80% in — a deep offset; on the complete index it maps to a definite non-zero page.
            val offset = (length * 80) / 100
            val expected = scenario.pageContaining(offset)
            assertTrue("a deep offset is a non-zero page", expected > 0)

            scenario.onActivity { it.pagedJumpToOffsetForTest(offset) }
            compose.waitUntil(25_000) { scenario.currentPage() == expected }
            assertEquals("far source-offset jump landed exactly on pageContaining(offset)", expected, scenario.currentPage())
        }
    }

    /** Round-trip: jump far, then jump BACK to offset 0 — page 0 via the same source-offset seam. */
    @Test
    fun sourceOffsetJumpRoundTrip_returnsToPageZero() {
        openPaged().use { scenario ->
            scenario.awaitCompleteIndex()   // WI-5b: resolve the far page on the COMPLETE index
            val length = scenario.docLength()
            val offset = (length * 70) / 100
            val expected = scenario.pageContaining(offset)
            assertTrue("deep offset is a non-zero page", expected > 0)

            scenario.onActivity { it.pagedJumpToOffsetForTest(offset) }
            compose.waitUntil(25_000) { scenario.currentPage() == expected }
            assertEquals(expected, scenario.currentPage())

            // Jump back to the document start (offset 0) → page 0.
            scenario.onActivity { it.pagedJumpToOffsetForTest(0) }
            compose.waitUntil(15_000) { scenario.currentPage() == 0 }
            assertEquals("jump to offset 0 returned to page 0", 0, scenario.currentPage())
        }
    }
}
