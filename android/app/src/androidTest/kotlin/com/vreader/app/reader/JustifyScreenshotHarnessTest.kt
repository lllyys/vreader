// Purpose: feature #156 Gate-5 — the SCREENSHOT pass for justified text across the three reflowable
// engines, Latin and CJK. Computed style and line geometry are the assertions; a right-edge alignment
// change is ultimately a PIXEL fact, and a screenshot is the only artefact that shows what a user sees.
// If the pixels and the computed style ever disagree, the pixels win and that is a finding.
//
// Every capture goes through the PRODUCTION entry point — app launch → `MainActivity` (the manifest
// LAUNCHER activity) → the Library grid → tap the book's tile → the format's reader — mirroring the
// `Azw3TocAcceptanceTest.openThroughLibrary` precedent. Importing the book beforehand is a SETUP
// mechanism (rule 47 permits seeding); the tap is the entry point.
//
// Run this through `am instrument`, NOT `connectedDebugAndroidTest`: the Gradle task uninstalls the app
// at run end, which wipes the scoped external files dir the PNGs are written to.
package com.vreader.app.reader

import android.graphics.Bitmap
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.MainActivity
import com.vreader.app.VReaderApp
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class JustifyScreenshotHarnessTest {

    @get:Rule val compose = createEmptyComposeRule()

    private val inst get() = InstrumentationRegistry.getInstrumentation()
    private val app get() = inst.targetContext.applicationContext as VReaderApp

    private companion object {
        const val UI_TIMEOUT_MS = 90_000L
        const val SETTLE_TIMEOUT_MS = 90_000L
        /** Minimum fraction of non-background pixels before a capture counts as "text rendered". */
        const val MIN_INK_FRACTION = 0.005
    }

    private fun shotsDir(): File {
        val dir = File(requireNotNull(inst.targetContext.getExternalFilesDir(null)) { "no external files dir" }, "justify-shots")
        dir.mkdirs()
        return dir
    }

    // ---- captures -------------------------------------------------------------------------------

    @Test fun azw3Cjk() = captureBook(importAsset("foliate-spike/book.azw3", "azw3-cjk-real.azw3"), "azw3-cjk")

    @Test fun txtLatin() = captureBook(importAsset("latin-justify-book.txt", "txt-latin-synth.txt"), "txt-latin")

    @Test fun txtCjk() = captureBook(importPushed("perf-cjk.txt", "txt-cjk-real.txt"), "txt-cjk")

    @Test fun epubLatin() = captureBook(importPushed("m3-en.epub", "epub-latin-real.epub"), "epub-latin")

    @Test fun epubCjk() = captureBook(importPushed("m3-zh.epub", "epub-cjk-real.epub"), "epub-cjk")

    // ---- fixtures -------------------------------------------------------------------------------

    /** An androidTest asset (the AZW3 real book; the synthetic Latin TXT). */
    private fun importAsset(asset: String, displayName: String): String {
        val present = runCatching {
            val dir = asset.substringBeforeLast('/', "")
            val leaf = asset.substringAfterLast('/')
            inst.context.assets.list(dir)?.contains(leaf) == true
        }.getOrDefault(false)
        assertTrue("androidTest asset '$asset' is absent — the screenshot pass cannot use a stand-in", present)
        val staged = File(inst.targetContext.cacheDir, "shot-${System.nanoTime()}-$displayName")
        inst.context.assets.open(asset).use { input -> staged.outputStream().use { input.copyTo(it) } }
        return importStaged(staged, displayName)
    }

    /**
     * A REAL book pushed to the app's scoped external files dir before the run (the connected task and
     * an uninstall both wipe that dir, so it is re-pushed every run). A missing file is a hard failure:
     * a synthetic stand-in would make the screenshot claim about real-world content hollow.
     */
    private fun importPushed(pushedName: String, displayName: String): String {
        val dir = requireNotNull(inst.targetContext.getExternalFilesDir(null)) { "no external files dir" }
        val f = File(dir, pushedName)
        assertTrue(
            "the REAL book '$pushedName' is not present in the app's external files dir — push it from " +
                "test-books/ before this run; a synthetic stand-in would not evidence real content",
            f.exists() && f.canRead() && f.length() > 0,
        )
        return importStaged(f, displayName)
    }

    private fun importStaged(file: File, displayName: String): String {
        val book = runBlocking {
            app.container.importer.importStream("content://test/$displayName", displayName, file.inputStream())
        }
        // Start every capture at the document head, so a leftover position from another run cannot put
        // the screenshot on a blank/graphical page.
        runCatching { app.container.cacheOffset(book.fingerprintKey, 0) }
        runBlocking { runCatching { app.container.repository.clearPosition(book.fingerprintKey) } }
        return displayName.substringBeforeLast('.')
    }

    // ---- the production path + capture ------------------------------------------------------------

    /**
     * PRODUCTION ENTRY POINT: launch the LAUNCHER activity, find the book in the Library grid by its
     * visible title, tap it, let the reader settle, and save a PNG of what the user is looking at.
     */
    private fun captureBook(title: String, name: String) {
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.waitUntil(UI_TIMEOUT_MS) {
                compose.onAllNodesWithText(title, substring = true).fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithText(title, substring = true).performClick()
            val file = File(shotsDir(), "$name.png")
            captureSettled(file, name)
            assertTrue("no screenshot written for $name", file.exists() && file.length() > 0)
        }
    }

    /**
     * Poll the screen until it STOPS CHANGING and actually carries text, then write it.
     *
     * Both conditions matter and neither alone is enough: a still-loading reader is stable-but-blank
     * (so the ink floor rejects it), and a mid-reflow frame carries ink but is not what the user ends up
     * looking at (so the stability check rejects it). Capturing either would put a picture in the
     * evidence file that does not show the thing being claimed.
     */
    private fun captureSettled(file: File, name: String) {
        var previous: Bitmap? = null
        var settledShot: Bitmap? = null
        var lastInk = 0.0
        // The polling MUST go through compose.waitUntil, not a bare Thread.sleep loop: with a
        // ComposeTestRule installed the Compose clock only advances while the framework pumps, so a
        // sleeping test thread starves composition and the reader never renders at all.
        try {
            compose.waitUntil(SETTLE_TIMEOUT_MS) {
                val shot = inst.uiAutomation.takeScreenshot() ?: return@waitUntil false
                lastInk = inkFraction(shot)
                val stable = lastInk >= MIN_INK_FRACTION && previous?.sameAs(shot) == true
                if (stable) {
                    settledShot = shot
                } else {
                    previous?.recycle()
                    previous = shot
                }
                stable
            }
        } catch (e: Throwable) {
            throw AssertionError(
                "the $name reader never settled into a rendered page within ${SETTLE_TIMEOUT_MS}ms " +
                    "(last ink fraction=$lastInk, floor=$MIN_INK_FRACTION) — a blank or still-reflowing " +
                    "capture would not evidence justified text",
                e,
            )
        }
        val shot = requireNotNull(settledShot) { "settled without a bitmap for $name" }
        file.outputStream().use { shot.compress(Bitmap.CompressFormat.PNG, 100, it) }
        android.util.Log.i(
            "JustifyShots",
            "CAPTURED $name -> ${file.absolutePath} ${shot.width}x${shot.height} ink=$lastInk",
        )
    }

    /**
     * The fraction of pixels that differ from the page background. The background is taken as the
     * most common colour in a coarse sample, which is robust across the five reader themes and the
     * per-format chrome (a fixed white/black threshold would misjudge Sepia and Dark).
     */
    private fun inkFraction(bmp: Bitmap): Double {
        val stepX = maxOf(1, bmp.width / 120)
        val stepY = maxOf(1, bmp.height / 200)
        val counts = HashMap<Int, Int>()
        var total = 0
        var x = 0
        while (x < bmp.width) {
            var y = 0
            while (y < bmp.height) {
                counts[bmp.getPixel(x, y)] = (counts[bmp.getPixel(x, y)] ?: 0) + 1
                total++
                y += stepY
            }
            x += stepX
        }
        if (total == 0) return 0.0
        val background = counts.maxByOrNull { it.value }?.value ?: 0
        return (total - background).toDouble() / total
    }
}
