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
import android.os.SystemClock
import android.view.MotionEvent
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
        const val UI_TIMEOUT_MS = 180_000L
        // Generous on purpose: a first-import of the 14 MB CJK TXT (no cached index) can take well over
        // 90s on the emulator, and a too-short budget reports it as "never rendered" — a harness failure
        // dressed up as a product one.
        const val SETTLE_TIMEOUT_MS = 240_000L
        /**
         * Minimum fraction of non-background pixels IN THE READING AREA before a capture counts as
         * "text rendered". A blank page scores ~0; a page of body text scores well above this. The
         * previous whole-screen 0.005 floor was satisfied by the reader chrome alone, which is how a
         * blank AZW3 loading overlay got captured and saved as evidence.
         */
        const val MIN_INK_FRACTION = 0.008
    }

    private fun shotsDir(): File {
        val dir = File(requireNotNull(inst.targetContext.getExternalFilesDir(null)) { "no external files dir" }, "justify-shots")
        dir.mkdirs()
        return dir
    }

    // ---- captures -------------------------------------------------------------------------------

    // `preSwipes` scrolls PAST front matter before capturing: an EPUB opens on its cover, and a picture
    // of cover art evidences nothing about justified body prose. The TXT books open directly on chapter
    // text and need none.
    //
    // TWO NAVIGATION LIMITS, recorded rather than hidden, because they bound what these images prove:
    //  - AZW3: injected page-turn taps DO advance the foliate paginator, but the pages just past the
    //    front matter render blank in a screenshot (ink 0.0 at 4, 7 and 12 taps), so a capture there
    //    fails loudly instead of saving an empty frame. The AZW3 image is therefore the book's opening
    //    page; the BODY-PROSE claim for AZW3 rests on Azw3JustifyConnectedTest's computed-style +
    //    line-geometry measurement of `p.normaltext` in the live DOM, not on this image.
    //  - EPUB: neither injected taps nor injected swipes moved the Readium host off its cover, so the
    //    EPUB images show cover art. EPUB justification evidence remains WI-2's computed-style matrix.
    @Test fun azw3Cjk() = captureBook(importAsset("foliate-spike/book.azw3", "azw3-cjk-real.azw3"), "azw3-cjk")

    @Test fun txtLatin() = captureBook(importAsset("latin-justify-book.txt", "txt-latin-synth.txt"), "txt-latin")

    @Test fun txtCjk() = captureBook(importPushed("perf-cjk.txt", "txt-cjk-real.txt"), "txt-cjk")

    @Test fun epubLatin() = captureBook(importPushed("m3-en.epub", "epub-latin-real.epub"), "epub-latin", preSwipes = 10)

    @Test fun epubCjk() = captureBook(importPushed("m3-zh.epub", "epub-cjk-real.epub"), "epub-cjk", preSwipes = 10)

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
    private fun captureBook(title: String, name: String, preSwipes: Int = 0) {
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.waitUntil(UI_TIMEOUT_MS) {
                compose.onAllNodesWithText(title, substring = true).fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithText(title, substring = true).performClick()
            if (preSwipes > 0) {
                // Let the book finish opening before navigating, or the gestures land on a loading overlay.
                compose.waitUntil(UI_TIMEOUT_MS) {
                    inst.uiAutomation.takeScreenshot()?.let { inkFraction(it) >= MIN_INK_FRACTION } == true
                }
                repeat(preSwipes) { swipeUp(); compose.waitForIdle(); Thread.sleep(350) }
            }
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
                // Deliberately NO page-turning here. An earlier revision tapped the next zone whenever
                // the reading area looked empty, which turned a still-LOADING AZW3 into a paginator that
                // had been advanced past its content before it ever painted — the capture then failed at
                // ink 0.0 on a book that renders fine when left alone. Navigation belongs in `preSwipes`,
                // which runs only after the reader has painted; this loop only waits.
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
     * The fraction of pixels that differ from the page background, sampled over the READING AREA only.
     *
     * Measuring the whole screen was a false-green machine: the reader chrome (top bar, Notes/Display
     * bar, status bar) carries plenty of non-background pixels, so a reader still showing its blank
     * loading overlay scored 0.12 "ink" and was captured as if it were a rendered page. Excluding the
     * chrome bands means the floor is a claim about BODY TEXT, which is what the screenshot exists to
     * show. The background is the most common colour in the sample, so the measure holds across the
     * five reader themes rather than assuming a white page.
     */
    private fun inkFraction(bmp: Bitmap): Double {
        val x0 = (bmp.width * 0.05).toInt()
        val x1 = (bmp.width * 0.95).toInt()
        val y0 = (bmp.height * 0.18).toInt()
        val y1 = (bmp.height * 0.72).toInt()
        val stepX = maxOf(1, (x1 - x0) / 120)
        val stepY = maxOf(1, (y1 - y0) / 160)
        val counts = HashMap<Int, Int>()
        var total = 0
        var x = x0
        while (x < x1) {
            var y = y0
            while (y < y1) {
                val p = bmp.getPixel(x, y)
                counts[p] = (counts[p] ?: 0) + 1
                total++
                y += stepY
            }
            x += stepX
        }
        if (total == 0) return 0.0
        val background = counts.maxByOrNull { it.value }?.value ?: 0
        return (total - background).toDouble() / total
    }

    /**
     * A real touch in the right third — the production page-turn zone. Used only to page PAST front
     * matter: a Kindle book opens on a cover / copyright page, and a screenshot of that evidences
     * nothing about justified prose. Injected through [Instrumentation.sendPointerSync], i.e. an actual
     * MotionEvent, not a test-tag click, so it does not depend on the `azw3-next-zone` tag that open
     * bug #369 reports as intermittently not-displayed.
     */
    /**
     * A real upward swipe — the production scroll gesture. The EPUB and TXT hosts open in SCROLL layout,
     * where a right-third TAP does nothing at all (it is the paginated hosts that page on tap), so the
     * first attempt to page past the EPUB cover with taps moved nothing and re-captured the cover art.
     */
    private fun swipeUp() {
        val dm = inst.targetContext.resources.displayMetrics
        val x = dm.widthPixels / 2f
        val yStart = dm.heightPixels * 0.75f
        val yEnd = dm.heightPixels * 0.28f
        val t = SystemClock.uptimeMillis()
        MotionEvent.obtain(t, t, MotionEvent.ACTION_DOWN, x, yStart, 0).also { inst.sendPointerSync(it); it.recycle() }
        val steps = 12
        for (i in 1..steps) {
            val y = yStart + (yEnd - yStart) * i / steps
            MotionEvent.obtain(t, t + i * 16L, MotionEvent.ACTION_MOVE, x, y, 0)
                .also { inst.sendPointerSync(it); it.recycle() }
        }
        MotionEvent.obtain(t, t + steps * 16L + 16, MotionEvent.ACTION_UP, x, yEnd, 0)
            .also { inst.sendPointerSync(it); it.recycle() }
    }
}
