package com.vreader.app.reader

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.VReaderApp
import com.vreader.app.data.Book
import kotlinx.coroutines.runBlocking
import org.junit.Test
import org.junit.Rule
import org.junit.runner.RunWith
import vreader.contracts.BookFormat
import java.io.File

/**
 * Feature #115 WI-2 — the PDF reader renders a synthetic PDF (chrome + "Page 1 of N" pill + a
 * page bitmap) and shows the Corrupt / Empty / Protected state surfaces. Imports through the
 * real BookImporter so routing + `BookFormat.pdf` are exercised.
 */
@RunWith(AndroidJUnit4::class)
class PdfReaderActivityTest {
    @get:Rule val compose = createEmptyComposeRule()

    private fun importAsset(asset: String, displayName: String): Book {
        val inst = InstrumentationRegistry.getInstrumentation()
        val app = inst.targetContext.applicationContext as VReaderApp
        val staged = File(inst.targetContext.cacheDir, "$asset-${System.nanoTime()}")
        inst.context.assets.open(asset).use { input -> staged.outputStream().use { input.copyTo(it) } }
        return runBlocking {
            app.container.importer.importStream("content://test/$asset", displayName, staged.inputStream())
        }
    }

    @Test
    fun opensPdf_rendersChrome_pagePill_andAPage() {
        val book = importAsset("sample-3page.pdf", "sample-3page.pdf")
        // Deterministic start at page 0 (a stale saved position from a prior run can't shift it).
        runBlocking {
            val app = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as VReaderApp
            app.container.cachePage(book.fingerprintKey, 0)
        }
        ActivityScenario.launch<PdfReaderActivity>(
            PdfReaderActivity.intent(InstrumentationRegistry.getInstrumentation().targetContext, book.fingerprintKey),
        ).use {
            // Wait for an actually-rendered page Image (contentDescription "Page 1"), not the pill.
            compose.waitUntil(8_000) {
                compose.onAllNodesWithContentDescription("Page 1").fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithText("Library").assertIsDisplayed()
            compose.onNodeWithText("of 3", substring = true).assertIsDisplayed()  // "Page 1 of 3" pill
            compose.onNodeWithContentDescription("Page 1").assertIsDisplayed()    // the rendered page bitmap
        }
    }

    @Test
    fun resumesToSavedPage() {
        // A distinct fixture (different content ⇒ different fingerprintKey) so this test's saved
        // position + in-memory page cache don't collide with the render test's book.
        // An 8-page fixture so the content exceeds the viewport (a short doc would clamp the
        // initial scroll index to 0). Seed page index 5 → the pill must show "Page 6".
        val book = importAsset("sample-resume.pdf", "sample-resume.pdf")
        runBlocking {
            val app = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as VReaderApp
            app.container.cachePage(book.fingerprintKey, 5)   // computeInitialPage reads the cache first
            val locator = vreader.contracts.Locator(
                contentSHA256 = book.contentSHA256, fileByteCount = book.fileByteCount, format = "pdf", page = 5,
            )
            app.container.repository.savePosition(vreader.contracts.VReaderLocator.wrapLegacy(locator), 1L)
        }
        ActivityScenario.launch<PdfReaderActivity>(
            PdfReaderActivity.intent(InstrumentationRegistry.getInstrumentation().targetContext, book.fingerprintKey),
        ).use {
            // Reopened at page index 5 → the pill shows "Page 6 of 8"; page 1 is NOT at the top.
            compose.waitUntil(8_000) {
                compose.onAllNodesWithText("Page 6", substring = true).fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithText("Page 6", substring = true).assertIsDisplayed()
        }
    }

    @Test
    fun resumesFromDurableRoom_withoutCachePrime() {
        // A distinct fixture + NO cachePage prime → exercises the durable Room fallback in
        // computeInitialPage (loadPosition → ResumeResolver → Canonical → page), not the cache.
        val book = importAsset("sample-resume-room.pdf", "sample-resume-room.pdf")
        runBlocking {
            val app = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as VReaderApp
            val locator = vreader.contracts.Locator(
                contentSHA256 = book.contentSHA256, fileByteCount = book.fileByteCount, format = "pdf", page = 5,
            )
            app.container.repository.savePosition(vreader.contracts.VReaderLocator.wrapLegacy(locator), 1L)
        }
        ActivityScenario.launch<PdfReaderActivity>(
            PdfReaderActivity.intent(InstrumentationRegistry.getInstrumentation().targetContext, book.fingerprintKey),
        ).use {
            compose.waitUntil(8_000) {
                compose.onAllNodesWithText("Page 6", substring = true).fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithText("Page 6", substring = true).assertIsDisplayed()
        }
    }

    @Test
    fun corruptPdf_showsCorruptState() {
        val book = importAsset("not-a.pdf", "not-a.pdf")
        ActivityScenario.launch<PdfReaderActivity>(
            PdfReaderActivity.intent(InstrumentationRegistry.getInstrumentation().targetContext, book.fingerprintKey),
        ).use {
            compose.waitUntil(8_000) {
                compose.onAllNodesWithText("Couldn’t open this PDF", substring = true).fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithText("Couldn’t open this PDF").assertIsDisplayed()
        }
    }
}
