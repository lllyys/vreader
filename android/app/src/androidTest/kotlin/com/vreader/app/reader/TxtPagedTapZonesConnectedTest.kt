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
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * Feature #137 WI-6b — connected proof of the designed page-turn affordances on [TxtPagedBody]
 * (vreader-tap-zones.jsx / vreader-reader.jsx `handleTap`):
 *   • a tap in the RIGHT 30% zone advances the page (pager.animateScrollToPage(current+1));
 *   • a tap in the LEFT 30% zone goes back a page;
 *   • a tap in the CENTER 40% zone toggles the reader chrome (REUSING the scaffold's existing
 *     center-tap chrome toggle — no new chrome mechanism);
 *   • the first-open TapZoneHint shows once on the first paged open, is GONE after a first
 *     interaction, and does NOT reappear on a reopen (persisted via ReaderSettingsStore).
 *
 * Drives the REAL activity (ActivityScenario) so the scaffold + paged body are wired exactly as
 * shipped; taps land through `performTouchInput { click(Offset(...)) }` at zone-relative x so the
 * 30/40/30 split is exercised for real. compose.waitUntil polling (NOT bare waitForIdle — it does
 * not await the off-main pagination pass). Tap gestures (not long-press) are lower-flake, but run
 * ONE class per connected invocation with adb hygiene on a TIMEOUT (MEMORY #129/#133).
 */
@RunWith(AndroidJUnit4::class)
class TxtPagedTapZonesConnectedTest {
    @get:Rule val compose = createEmptyComposeRule()

    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val app get() = instrumentation.targetContext.applicationContext as VReaderApp

    /** Pin display defaults + Paged layout, and RESET the tap-hint-seen flag so each run starts with
     *  the hint eligible (first-open). Restore Scroll + hint-seen after. */
    @Before
    fun pinDefaults() = runBlocking<Unit> {
        val store = app.container.readerSettingsStore
        store.setTheme(ReaderTheme.Paper)
        store.setFontFamily(ReaderFontFamily.Serif)
        store.setFontSize(ReaderSettings.DEFAULT_FONT_SIZE)
        store.setLineSpacing(ReaderSettings.DEFAULT_LINE_SPACING)
        store.setMargin(ReaderSettings.DEFAULT_MARGIN)
        store.setLayout(ReaderLayout.Paged)
        store.resetTapHintSeenForTest()
        for (i in 0 until 50) {
            if (store.current().layout == ReaderLayout.Paged && !store.tapHintSeen()) return@runBlocking
            kotlinx.coroutines.delay(20)
        }
    }

    @After
    fun restore() = runBlocking<Unit> {
        app.container.readerSettingsStore.setLayout(ReaderLayout.Scroll)
    }

    private fun importAsset(asset: String): String {
        val staged = File(instrumentation.targetContext.cacheDir, "tapzone-${System.nanoTime()}-$asset")
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

    private fun chromeVisible(): Boolean =
        compose.onAllNodesWithTag("reader-top-chrome", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    private fun hintShowing(): Boolean =
        compose.onAllNodesWithTag("tap-zone-hint", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    /** Tap the pager at [percentX] of its width (mid-height). */
    private fun tapPagerAt(percentX: Float) {
        compose.onNodeWithTag("txt-pager", useUnmergedTree = true).performTouchInput {
            click(Offset(width * percentX, height * 0.5f))
        }
    }

    private fun awaitFirstPage(scenario: ActivityScenario<TxtReaderActivity>) {
        scenario.awaitPageIndex()
        compose.waitUntil(15_000) {
            compose.onAllNodesWithText("Line 001", substring = true).fetchSemanticsNodes().isNotEmpty()
        }
    }

    @Test
    fun rightZoneTap_advancesThePage() {
        val key = importAsset("resume-sample.txt")
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            awaitFirstPage(scenario)
            assertTrue("multi-page fixture", scenario.currentPage() == 0)
            tapPagerAt(0.85f)   // right zone → next page
            compose.waitUntil(15_000) { scenario.currentPage() >= 1 }
            assertTrue("right-zone tap advanced the page", scenario.currentPage() >= 1)
        }
    }

    @Test
    fun leftZoneTap_goesBackAPage() {
        val key = importAsset("resume-sample.txt")
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            awaitFirstPage(scenario)
            // advance twice first so a back-tap has somewhere to go
            tapPagerAt(0.85f)
            compose.waitUntil(15_000) { scenario.currentPage() >= 1 }
            tapPagerAt(0.85f)
            compose.waitUntil(15_000) { scenario.currentPage() >= 2 }
            val before = scenario.currentPage()
            tapPagerAt(0.15f)   // left zone → previous page
            compose.waitUntil(15_000) { scenario.currentPage() < before }
            assertTrue("left-zone tap went back a page", scenario.currentPage() < before)
        }
    }

    @Test
    fun centerZoneTap_togglesChrome() {
        val key = importAsset("resume-sample.txt")
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            awaitFirstPage(scenario)
            // The reader opens with chrome visible.
            compose.waitUntil(15_000) { chromeVisible() }
            val page0 = scenario.currentPage()
            tapPagerAt(0.5f)    // center zone → toggle chrome (hides it), never a page turn
            compose.waitUntil(15_000) { !chromeVisible() }
            assertTrue("center tap hid the chrome", !chromeVisible())
            assertTrue("center tap did NOT turn the page", scenario.currentPage() == page0)
            tapPagerAt(0.5f)    // toggle back on
            compose.waitUntil(15_000) { chromeVisible() }
            assertTrue("center tap re-showed the chrome", chromeVisible())
        }
    }

    @Test
    fun tapHint_showsOnFirstOpen_dismissesOnInteraction_persistsAcrossReopen() {
        val key = importAsset("resume-sample.txt")
        // First open — hint eligible (reset in @Before). It shows, then is gone after a tap.
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            awaitFirstPage(scenario)
            compose.waitUntil(15_000) { hintShowing() }
            assertTrue("hint shows on first paged open", hintShowing())
            tapPagerAt(0.5f)    // any interaction dismisses it
            compose.waitUntil(15_000) { !hintShowing() }
            assertTrue("hint dismissed after first interaction", !hintShowing())
        }
        // Reopen — the persisted seen flag must keep the hint from reappearing.
        ActivityScenario.launch<TxtReaderActivity>(
            TxtReaderActivity.intent(instrumentation.targetContext, key),
        ).use { scenario ->
            awaitFirstPage(scenario)
            // The hint's would-be enter+hold window is ~2.7s; poll ACROSS it (the emulator runs a real
            // clock) and assert it never appears — a meaningful wait, not an immediately-true predicate.
            val deadline = System.currentTimeMillis() + 3_500
            while (System.currentTimeMillis() < deadline) {
                assertTrue("hint must NOT reappear once persisted-dismissed", !hintShowing())
                Thread.sleep(150)
            }
        }
    }
}
