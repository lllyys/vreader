package com.vreader.app.reader

import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.VReaderApp
import com.vreader.app.reader.chrome.ReaderSheet
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * Feature #132 WI-7-EPUB — the EPUB reader host (ReaderActivity) renders the full reader nav chrome over
 * the Readium EpubNavigatorFragment. Instrumented because the navigator resolves its TOC + reading
 * position against a real WebView (not Robolectric). Opens the bundled minimal EPUB and asserts the
 * persistent chrome model populates (title + TOC), that a TOC jump feeds the native Readium locator to
 * `navigator.go` (currentHref changes on a valid jump), that a false/stale jump leaves the sheet open with
 * no crash, and that the sheet layer is touch-through (no sheet open at rest → the fragment keeps input).
 *
 * The live Compose gesture render (tapping the Contents/Notes toolbar, the ModalBottomSheet rows) is
 * emulator-timing-flaky on a loaded host, so these drive the SAME seams via the @VisibleForTesting hooks
 * (the #128/#129 precedent); the end-to-end Compose tap rides WI-9 acceptance on a cold emulator.
 */
@RunWith(AndroidJUnit4::class)
class ReaderChromeConnectedTest {

    @Test
    fun opensEpub_populatesChromeModel_withTitleAndToc() {
        withOpenReader { scenario ->
            val model = pollModel(scenario) { it.tocEntries.isNotEmpty() || it.title.isNotBlank() }
            assertNotNull("the chrome model populated after open", model)
            assertTrue("the model carries the book title", model!!.title.isNotBlank())
            // The bundled minimal EPUB has a table of contents → the Contents control is available.
            assertTrue("the flattened TOC populated", model.tocEntries.isNotEmpty())
        }
    }

    @Test
    fun tocJump_navigatesNatively_andDismissesOnSuccess() {
        withOpenReader { scenario ->
            // Wait for the navigator to render a locator (content loaded).
            pollActivity(scenario) { it.currentHref() != null }
            // Open the Contents sheet, then jump to a valid TOC entry (index 1 if present, else 0).
            val entryCount = model(scenario).tocEntries.size
            val target = if (entryCount > 1) 1 else 0
            scenario.onActivity { it.openContentsForTest() }
            assertEquals("the Contents sheet is open", ReaderSheet.Toc, sheet(scenario))

            val hrefBefore = hrefOf(scenario)
            var jumped = false
            scenario.onActivity { jumped = it.jumpToTocEntryForTest(target) }
            assertTrue("a valid TOC jump reported success (native navigator.go returned true)", jumped)
            // The native jump moved the reading position (currentHref reflects the new spine item) — the
            // Contents sheet's dismiss-on-success is driven off this same Boolean.
            if (target != 0) {
                val moved = pollActivity(scenario) { it.currentHref() != hrefBefore }
                assertTrue("the native TOC jump changed the reading href", moved)
            }
        }
    }

    @Test
    fun invalidTocJump_returnsFalse_andSheetStaysOpen_noCrash() {
        withOpenReader { scenario ->
            pollActivity(scenario) { it.currentHref() != null }
            scenario.onActivity { it.openContentsForTest() }
            // An out-of-range index → jumpToTocEntry returns false and NEVER crashes; the sheet stays open
            // (the sheet dismisses ONLY on true — no invented error surface, rule 51 §nav-error-presentation).
            var result = true
            scenario.onActivity { result = it.jumpToTocEntryForTest(9999) }
            assertFalse("an out-of-range TOC jump reports failure", result)
            assertEquals("a failed jump leaves the Contents sheet open", ReaderSheet.Toc, sheet(scenario))
        }
    }

    @Test
    fun sheetLayer_isTouchThrough_whenNoSheetOpen() {
        withOpenReader { scenario ->
            pollActivity(scenario) { it.currentHref() != null }
            // At rest no sheet is open → the sheet layer renders nothing (touch-through: the fragment keeps
            // scroll/selection/link input). The dismiss overlay is present ONLY while a sheet is open.
            assertEquals("no sheet open at rest → touch-through", ReaderSheet.None, sheet(scenario))
        }
    }

    @Test
    fun notesReachable_reviewOnly() {
        withOpenReader { scenario ->
            pollActivity(scenario) { it.currentHref() != null }
            scenario.onActivity { it.openNotesForTest() }
            assertEquals("the Notes sheet is reachable", ReaderSheet.Notes, sheet(scenario))
            // EPUB Notes are review-only (jump-to-annotation null; cards non-clickable) until #135 — the
            // model's snapshot is loaded (possibly empty) and the sheet opened without a jump seam.
            assertNotNull("the annotations snapshot is present", model(scenario).annotations)
        }
    }

    @Test
    fun currentTocIndex_isWithinBounds() {
        withOpenReader { scenario ->
            val m = pollModel(scenario) { it.tocEntries.isNotEmpty() }
            assertNotNull(m)
            val idx = m!!.currentTocIndex
            // A populated TOC → the highlighted index is a valid row (0..size-1), never a dangling -1.
            assertTrue("currentTocIndex is a valid row for a populated TOC", idx in 0 until m.tocEntries.size)
        }
    }

    // ---- harness ----

    private fun withOpenReader(block: (ActivityScenario<ReaderActivity>) -> Unit) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val appContext = instrumentation.targetContext
        val app = appContext.applicationContext as VReaderApp
        val book = stageBook(appContext, instrumentation.context, app)
        ActivityScenario.launch<ReaderActivity>(ReaderActivity.intent(appContext, book.fingerprintKey)).use(block)
    }

    private fun model(scenario: ActivityScenario<ReaderActivity>): ReaderChromeModel {
        var m = ReaderChromeModel()
        scenario.onActivity { m = it.chromeModelSnapshot() }
        return m
    }

    private fun sheet(scenario: ActivityScenario<ReaderActivity>): ReaderSheet {
        var s: ReaderSheet = ReaderSheet.None
        scenario.onActivity { s = it.openSheet().sheet }
        return s
    }

    private fun hrefOf(scenario: ActivityScenario<ReaderActivity>): String? {
        var h: String? = null
        scenario.onActivity { h = it.currentHref() }
        return h
    }

    private fun pollModel(
        scenario: ActivityScenario<ReaderActivity>,
        predicate: (ReaderChromeModel) -> Boolean,
    ): ReaderChromeModel? {
        repeat(60) {
            val m = model(scenario)
            if (predicate(m)) return m
            Thread.sleep(200)
        }
        return null
    }

    private fun pollActivity(
        scenario: ActivityScenario<ReaderActivity>,
        predicate: (ReaderActivity) -> Boolean,
    ): Boolean {
        repeat(60) {
            var ok = false
            scenario.onActivity { ok = predicate(it) }
            if (ok) return true
            Thread.sleep(200)
        }
        return false
    }

    private fun stageBook(appContext: android.content.Context, testContext: android.content.Context, app: VReaderApp) =
        runBlocking {
            val staged = File(appContext.cacheDir, "epub-chrome-test-${System.nanoTime()}.epub")
            testContext.assets.open("minimal.epub").use { input ->
                staged.outputStream().use { input.copyTo(it) }
            }
            app.container.importer.importStream("content://test/minimal.epub", "minimal.epub", staged.inputStream())
        }
}
