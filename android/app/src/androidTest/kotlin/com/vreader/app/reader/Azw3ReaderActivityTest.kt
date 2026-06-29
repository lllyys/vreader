package com.vreader.app.reader

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.test.uiautomator.UiDevice
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.VReaderApp
import com.vreader.app.data.Book
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Ignore
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import vreader.contracts.Locator
import vreader.contracts.VReaderLocator
import java.io.File

/**
 * Feature #126 WI-6 — the AZW3 reader renders a REAL Kindle book end-to-end through the real
 * FoliateBridge + the production `assets/foliate/` bundle, and persists a position. Reaching a saved
 * `azw3` position proves the full path: import → Activity → secure bridge → patched bundle → book-ready
 * → init renders the first page in a `blob:` SUBFRAME (the WI-3 subframe-nav fix) → relocate → save.
 * This discharges the on-device render verification deferred from WI-3.
 *
 * The real 6 MB CJK AZW3 fixture is local-only (gitignored, not in CI); the test self-skips if absent.
 */
@RunWith(AndroidJUnit4::class)
class Azw3ReaderActivityTest {

    @get:Rule val compose = createEmptyComposeRule()

    private fun importAzw3OrSkip(): Book {
        val inst = InstrumentationRegistry.getInstrumentation()
        val present = inst.context.assets.list("foliate-spike")?.contains("book.azw3") == true
        assumeTrue("local-only foliate-spike/book.azw3 absent — skipping AZW3 render test", present)
        val app = inst.targetContext.applicationContext as VReaderApp
        val staged = File(inst.targetContext.cacheDir, "azw3-${System.nanoTime()}")
        inst.context.assets.open("foliate-spike/book.azw3").use { input -> staged.outputStream().use { input.copyTo(it) } }
        // The importer detects format from the display name's extension — keep `.azw3`.
        return runBlocking { app.container.importer.importStream("content://test/book.azw3", "Bei Tao Yan.azw3", staged.inputStream()) }
    }

    @Test
    fun opensAzw3_rendersThroughRealBridge_andSavesPosition() {
        val book = importAzw3OrSkip()
        val app = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as VReaderApp
        val key = book.fingerprintKey

        ActivityScenario.launch<Azw3ReaderActivity>(
            Azw3ReaderActivity.intent(InstrumentationRegistry.getInstrumentation().targetContext, key),
        ).use {
            // The designed reader chrome is up.
            compose.waitUntil(10_000) { compose.onAllNodesWithText("Library").fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithText("Library").assertIsDisplayed()

            // The book rendered through the real bridge → a relocate fired → a position was saved.
            compose.waitUntil(40_000) { runBlocking { app.container.repository.loadPosition(key) != null } }
            val saved = runBlocking { app.container.repository.loadPosition(key) }
            assertNotNull("no position saved — the AZW3 did not render through the real FoliateBridge", saved)
            assertEquals("azw3", saved!!.legacyLocator?.format)
        }
    }

    @Test
    fun reopen_restoresSavedPosition() {
        val book = importAzw3OrSkip()
        val app = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as VReaderApp
        val key = book.fingerprintKey

        // Seed a mid-book position (fraction only → forces the initAtFraction restore path).
        runBlocking {
            val seeded = VReaderLocator.wrapLegacy(
                Locator(book.contentSHA256, book.fileByteCount, "azw3", progression = 0.5),
            )
            app.container.repository.savePosition(seeded, System.currentTimeMillis())
        }

        ActivityScenario.launch<Azw3ReaderActivity>(
            Azw3ReaderActivity.intent(InstrumentationRegistry.getInstrumentation().targetContext, key),
        ).use {
            // Wait until the reader's OWN relocate save REPLACES the exact 0.5 seed (its rendered
            // fraction snaps to a page boundary, so it won't equal 0.5 exactly). A restoring reader
            // re-saves near 0.5; a NON-restoring reader would overwrite with ~0 — so the assertion
            // below catches a regression, not just the seed.
            compose.waitUntil(40_000) {
                val p = runBlocking { app.container.repository.loadPosition(key)?.legacyLocator?.progression }
                p != null && p != 0.5
            }
            val restored = runBlocking { app.container.repository.loadPosition(key)?.legacyLocator?.progression }
            assertNotNull("no position after reopen", restored)
            assertTrue("restored position should resume near the seeded 0.5, got $restored", restored!! > 0.25)
        }
    }

    /**
     * KNOWN-FAILING verification target for the reading-interaction bug: the AZW3 reader renders +
     * resumes, but NO user interaction advances the content — neither `next()` (paginated) nor a real
     * swipe (scrolled, via UiDevice), with the patched OR unpatched bundle (so it is NOT the
     * security patch, and NOT Compose touch-routing — real touches reach the WebView). foliate's
     * content does not scroll/paginate via touch in Android System WebView. Tracked as a bug; un-`@Ignore`
     * when fixed. Exhaustively isolated 2026-06-29 (logged in the bug + dev-docs).
     */
    @Ignore("AZW3 reading-interaction bug #357 (GH #1860) — foliate content renders + goToFraction seeks, but next()/scroll do not advance in Android WebView; un-ignore when fixed")
    @Test
    fun scrollingForward_advancesReadingPosition() {
        val book = importAzw3OrSkip()
        val app = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as VReaderApp
        val key = book.fingerprintKey
        val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
        ActivityScenario.launch<Azw3ReaderActivity>(
            Azw3ReaderActivity.intent(InstrumentationRegistry.getInstrumentation().targetContext, key),
        ).use {
            compose.waitUntil(40_000) { runBlocking { app.container.repository.loadPosition(key) != null } }
            val before = runBlocking { app.container.repository.loadPosition(key)?.legacyLocator?.progression ?: 0.0 }
            val w = device.displayWidth
            val h = device.displayHeight
            repeat(5) {
                device.swipe(w / 2, (h * 0.75).toInt(), w / 2, (h * 0.25).toInt(), 12)
                Thread.sleep(500)
            }
            compose.waitUntil(20_000) {
                runBlocking { (app.container.repository.loadPosition(key)?.legacyLocator?.progression ?: 0.0) > before + 1e-6 }
            }
            val after = runBlocking { app.container.repository.loadPosition(key)?.legacyLocator?.progression!! }
            assertTrue("scrolling should advance the reading position (before=$before, after=$after)", after > before)
        }
    }
}
