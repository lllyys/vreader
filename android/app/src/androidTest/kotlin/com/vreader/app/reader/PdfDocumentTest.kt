package com.vreader.app.reader

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * Feature #115 WI-1 — PdfDocument over android.graphics.pdf.PdfRenderer (device-only, so
 * instrumented). Proves: a synthetic 3-page PDF opens with pageCount==3 and renders a non-blank
 * bitmap of the requested width; concurrent renders serialize without crashing; close() during
 * a render doesn't throw; a garbage file maps to Corrupt.
 */
@RunWith(AndroidJUnit4::class)
class PdfDocumentTest {

    private fun stage(asset: String): File {
        val ctx = InstrumentationRegistry.getInstrumentation().context
        val target = InstrumentationRegistry.getInstrumentation().targetContext
        val out = File(target.cacheDir, "$asset-${System.nanoTime()}")
        ctx.assets.open(asset).use { input -> out.outputStream().use { input.copyTo(it) } }
        return out
    }

    @Test
    fun opensMultiPagePdf_reportsPageCount() {
        val result = PdfDocument.open(stage("sample-3page.pdf"))
        assertTrue("a valid PDF opens Ok", result is PdfOpenResult.Ok)
        val doc = (result as PdfOpenResult.Ok).document
        try {
            assertEquals(3, doc.pageCount)
        } finally {
            runBlocking { doc.close() }
        }
    }

    @Test
    fun rendersNonBlankBitmapOfRequestedWidth() = runBlocking {
        val doc = (PdfDocument.open(stage("sample-3page.pdf")) as PdfOpenResult.Ok).document
        try {
            val bmp = doc.renderPage(0, targetWidthPx = 240)
            assertEquals(240, bmp.width)
            assertTrue("height derived from aspect", bmp.height > 0)
            // Non-uniform pixels ⇒ actually rendered text, not a blank sheet.
            val corner = bmp.getPixel(0, 0)
            var differs = false
            for (x in 0 until bmp.width step 7) {
                for (y in 0 until bmp.height step 7) {
                    if (bmp.getPixel(x, y) != corner) { differs = true; break }
                }
                if (differs) break
            }
            assertTrue("rendered page has non-uniform pixels", differs)
            bmp.recycle()
        } finally {
            doc.close()
        }
    }

    @Test
    fun concurrentRenders_serialize_withoutCrash() = runBlocking {
        val doc = (PdfDocument.open(stage("sample-3page.pdf")) as PdfOpenResult.Ok).document
        try {
            val a = async { doc.renderPage(0, 120) }
            val b = async { doc.renderPage(1, 120) }
            val c = async { doc.renderPage(2, 120) }
            listOf(a.await(), b.await(), c.await()).forEach { it.recycle() }
        } finally {
            doc.close()
        }
    }

    @Test
    fun close_isSafeUnderConcurrentRenders_andIdempotent() {
        // close() must be SAFE regardless of how it interleaves with renders — whether it wins
        // the mutex first (queued renders then fail check(!closed)) or a render holds it (close
        // waits). A busy 40-render loop keeps the mutex contended so close() lands mid-loop; the
        // invariant proven is "close never throws / corrupts the renderer, and is idempotent",
        // which holds for ALL interleavings. (A render-critical-path test probe would prove the
        // exact ordering but couples production code to the test — declined; the serialization is
        // structurally guaranteed by both paths sharing one Mutex.)
        runBlocking {
            val doc = (PdfDocument.open(stage("sample-3page.pdf")) as PdfOpenResult.Ok).document
            val started = kotlinx.coroutines.CompletableDeferred<Unit>()
            val render = async {
                runCatching {
                    started.complete(Unit)
                    repeat(40) { doc.renderPage(it % 3, 200).recycle() }
                }
            }
            started.await()
            doc.close()                     // must not throw
            render.await()                  // Result — never rethrows
            doc.close()                     // idempotent — no double-free
        }
    }

    @Test
    fun garbageFile_mapsToCorrupt() {
        assertTrue(PdfDocument.open(stage("not-a.pdf")) is PdfOpenResult.Corrupt)
    }
}
