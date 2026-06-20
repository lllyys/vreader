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
