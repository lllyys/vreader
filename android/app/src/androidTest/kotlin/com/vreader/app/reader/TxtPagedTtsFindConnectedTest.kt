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
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * feature #137 WI-9 — connected proof of the PAGED find jump-to-page + PAGED TTS follow:
 *   • a search-hit source offset (the `hit.canonicalLocator.charOffsetUTF16` the host's `onJump` resolves)
 *     jumps the pager to the page CONTAINING the hit (pageContaining), through the SAME pager-jump seam the
 *     bookmark/annotation jumps use in paged mode — the hit is visible on that page;
 *   • the PAGED TTS follow auto-advances the pager to the page containing the currently-spoken SOURCE
 *     offset (tts.charStart) — driven through the EXACT production decision (pagedTtsFollowTarget) + jump
 *     seam via a simulated spoken offset (a real TTS engine speaking needs voice data unavailable on the
 *     emulator; the decision + jump path IS the production one);
 *   • the follow does NOT fire when the narration is on the page the pager already shows (no yank).
 *
 * createEmptyComposeRule + ActivityScenario + compose.waitUntil polling (the TxtPagedBodyConnectedTest
 * precedent). One class per connected invocation (MEMORY #129/#133).
 */
@RunWith(AndroidJUnit4::class)
class TxtPagedTtsFindConnectedTest {
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
        val staged = File(instrumentation.targetContext.cacheDir, "pgtf-${System.nanoTime()}-$asset")
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

    private fun ActivityScenario<TxtReaderActivity>.sourceOffset(): Int {
        var o = -1
        onActivity { o = it.pagedCurrentSourceOffsetForTest() ?: -1 }
        return o
    }

    @Test
    fun findHit_jumpsToPageContainingTheHit() {
        setLayoutAndConfirm(ReaderLayout.Paged)
        val key = importAsset("resume-sample.txt")
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            scenario.awaitPageIndex()
            compose.waitUntil(15_000) {
                compose.onAllNodesWithText("Line 001", substring = true).fetchSemanticsNodes().isNotEmpty()
            }
            // Pick a hit offset deep in the document (the same value the search sheet's onJump would pass:
            // a hit's canonicalLocator.charOffsetUTF16). Capture the page it should land on.
            val length = run { var l = 0; scenario.onActivity { l = it.pagedDocLengthForTest() }; l }
            val hitOffset = (length * 3) / 4
            val expectedPage = run { var p = -1; scenario.onActivity { p = it.pagedPageContainingForTest(hitOffset) ?: -1 }; p }
            assertTrue("a deep hit is a non-zero page", expectedPage > 0)
            assertEquals("opens on page 0", 0, scenario.currentPage())

            // The host's search onJump routes to jumpToOffset → the pager (the SAME seam under test here).
            scenario.onActivity { it.pagedJumpToOffsetForTest(hitOffset) }
            compose.waitUntil(15_000) { scenario.currentPage() == expectedPage }
            assertEquals("find hit jumped to the page containing it", expectedPage, scenario.currentPage())
        }
    }

    @Test
    fun ttsFollow_advancesPagerToTheSpokenPage() {
        setLayoutAndConfirm(ReaderLayout.Paged)
        val key = importAsset("resume-sample.txt")
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            scenario.awaitPageIndex()
            compose.waitUntil(15_000) {
                compose.onAllNodesWithText("Line 001", substring = true).fetchSemanticsNodes().isNotEmpty()
            }
            assertEquals("opens on page 0", 0, scenario.currentPage())

            // Narration reaches a source offset on a later page → the follow advances the pager there.
            val length = run { var l = 0; scenario.onActivity { l = it.pagedDocLengthForTest() }; l }
            val spokenOffset = length / 2
            val spokenPage = run { var p = -1; scenario.onActivity { p = it.pagedPageContainingForTest(spokenOffset) ?: -1 }; p }
            assertTrue("the spoken sentence is on a later page", spokenPage > 0)

            val followed = run { var f: Int? = -2; scenario.onActivity { f = it.simulatePagedTtsFollowForTest(spokenOffset) }; f }
            assertEquals("the follow chose the spoken page", spokenPage, followed)
            compose.waitUntil(15_000) { scenario.currentPage() == spokenPage }
            assertEquals("the pager auto-advanced to the spoken page", spokenPage, scenario.currentPage())
        }
    }

    @Test
    fun ttsFollow_doesNotYankWhenSpokenOnTheCurrentPage() {
        setLayoutAndConfirm(ReaderLayout.Paged)
        val key = importAsset("resume-sample.txt")
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            scenario.awaitPageIndex()
            compose.waitUntil(15_000) {
                compose.onAllNodesWithText("Line 001", substring = true).fetchSemanticsNodes().isNotEmpty()
            }
            // Turn to a known page, then "speak" a sentence that starts on THAT SAME page → no follow.
            scenario.onActivity { it.turnToNextPageForTest() }
            compose.waitUntil(15_000) { scenario.currentPage() >= 1 }
            val page = scenario.currentPage()
            val pageStart = scenario.sourceOffset()
            // A spoken offset just inside the current page (still on this page) → the follow returns null.
            val onPageOffset = pageStart + 1
            // Confirm the offset is genuinely on the current page (not the next).
            val onPage = run { var p = -1; scenario.onActivity { p = it.pagedPageContainingForTest(onPageOffset) ?: -1 }; p }
            assertEquals("the probe offset is on the current page", page, onPage)

            val followed = run { var f: Int? = -2; scenario.onActivity { f = it.simulatePagedTtsFollowForTest(onPageOffset) }; f }
            assertNull("narration on the current page must NOT jump", followed)
            assertEquals("the pager stayed on the reading page", page, scenario.currentPage())
        }
    }

    @Test
    fun userSwipeWhileNarrationSteady_doesNotGetYankedBack() {
        // Gate-4 R1 High (no-fight): after the follow lands on a page, a user swipe AWAY holds — no jump
        // back. This drives the follow via the seam (a real TTS engine can't speak without emulator voice
        // data), so it proves the no-fight END STATE, not the effect's restart keys directly; the pure
        // PagedTtsFollowTest + the reviewed effect keys (tts.phase + tts.charStart, NOT pagedOffset) cover
        // that a swipe cannot re-invoke the follow. Strengthening the seam to drive live TTS state is a
        // named follow-up (Gate-4 R2 test-quality caveat, accepted).
        setLayoutAndConfirm(ReaderLayout.Paged)
        val key = importAsset("resume-sample.txt")
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            scenario.awaitPageIndex()
            compose.waitUntil(15_000) {
                compose.onAllNodesWithText("Line 001", substring = true).fetchSemanticsNodes().isNotEmpty()
            }
            // Narration reaches a mid-book sentence → the follow (one narration update) lands there.
            val length = run { var l = 0; scenario.onActivity { l = it.pagedDocLengthForTest() }; l }
            val spokenOffset = length / 3
            val spokenPage = run { var p = -1; scenario.onActivity { p = it.pagedPageContainingForTest(spokenOffset) ?: -1 }; p }
            assertTrue("narration is on a later page", spokenPage > 0)
            scenario.onActivity { it.simulatePagedTtsFollowForTest(spokenOffset) }
            compose.waitUntil(15_000) { scenario.currentPage() == spokenPage }
            assertEquals(spokenPage, scenario.currentPage())

            // The USER now pages forward (a swipe) while the narration's charStart is unchanged. Because the
            // production follow effect does NOT key on the page offset, no auto-follow is triggered by the
            // swipe — the pager holds the user's page.
            scenario.onActivity { it.turnToNextPageForTest() }
            compose.waitUntil(15_000) { scenario.currentPage() == spokenPage + 1 }
            // Give any (incorrectly-keyed) effect a chance to yank back — the page must STAY put.
            compose.waitForIdle()
            assertEquals("a user swipe (narration steady) is NOT yanked back to the spoken page", spokenPage + 1, scenario.currentPage())
        }
    }
}
