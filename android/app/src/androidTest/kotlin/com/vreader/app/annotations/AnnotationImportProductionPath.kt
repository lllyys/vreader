package com.vreader.app.annotations

import android.app.Activity
import android.os.SystemClock
import androidx.compose.ui.test.junit4.ComposeTestRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
import com.vreader.app.MainActivity
import com.vreader.app.VReaderApp
import com.vreader.app.data.Book
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import java.io.File

/**
 * Feature #165 WI-7 — THE PRODUCTION ENTRY POINT for the annotation-import acceptance, shared by
 * [AnnotationImportReachabilityTest] and [AnnotationsRoundTripConnectedTest].
 *
 * Rule 47 Gate-5 "production reachability": every navigation below starts at the app's real
 * LAUNCHER activity ([MainActivity]) and walks the shipped UI — Library grid -> tap the book ->
 * the reader -> top-bar `...` More -> *Details* -> **Import annotations…**. No
 * `<Reader>Activity.intent(...)` shortcut, no `src/debug` launcher, no composable invoked directly.
 * Every file on that path lives in `src/main`.
 *
 * Two things this file refuses to do, because both are ways an acceptance run passes while wrong:
 *
 *  - **It never skips.** A missing fixture throws (`requireNotNull` / `require`), it does not
 *     `assumeTrue`. A skipped instrumentation method exits 0 exactly like a passing one (bug #369's
 *     shape), so an absent real book would otherwise read as a green acceptance.
 *  - **It checks WHICH book the tap opened**, not merely that a reader appeared: the resumed
 *     activity must carry the expected fingerprint key in the very intent extra the production
 *     Library route put there. A title-substring match against the wrong row would otherwise assert
 *     against a different document.
 */
object AnnotationImportProductionPath {

    /** Generous: a 14 MB import + decode + first paint on a loaded emulator is slow, not hung. */
    const val UI_TIMEOUT_MS = 180_000L

    val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    val app get() = instrumentation.targetContext.applicationContext as VReaderApp

    // ---- real fixtures (AGENTS.md "real books first"), each identity-pinned by content digest ----

    const val REAL_EPUB_FILE = "wi7-real.epub"
    const val REAL_EPUB_SHA256 = "71fa5b7d2bef5879497a21fa145134707ab8b7c432af5760881d5da816774a31"
    const val REAL_EPUB_DISPLAY_NAME = "The Half Second - Li Xiaolai.epub"

    const val REAL_TXT_FILE = "wi7-real.txt"
    const val REAL_TXT_SHA256 = "04d60f6d93256c0d82f714ad1237a57ca88dcd469fb37bef231af062c543cfe4"
    const val REAL_TXT_DISPLAY_NAME = "黑暗血时代.txt"

    const val REAL_AZW3_FILE = "wi7-real.azw3"
    const val REAL_AZW3_SHA256 = "39826bfdbcd776ce3a6bc512158f6a5240aefadb188e07b0d86a996489c01c95"
    const val REAL_AZW3_DISPLAY_NAME = "Bei Tao Yan De Yong Qi - Zi Wo.azw3"

    /**
     * PDF is the ONE stated exception to "real books first": `test-books/books/` holds no PDF at
     * all (verified 2026-08-06 — it holds one txt, two epub, one azw3), so the format has no real
     * book to prefer. The committed 3-page asset is used instead, and the exception is named here
     * rather than left for a reader to infer.
     */
    const val PDF_ASSET = "sample-3page.pdf"

    /**
     * The pushed real book, or a LOUD failure naming the exact `adb push` that fixes it. The
     * connected task uninstalls the app at run end, which wipes
     * `/sdcard/Android/data/com.vreader.app/`, so every fixture must be re-pushed per run.
     */
    fun requireRealFile(name: String, expectedSha256: String, source: String): File {
        val dir = requireNotNull(instrumentation.targetContext.getExternalFilesDir(null)) {
            "no external files dir on this device"
        }
        val file = File(dir, name)
        require(file.exists() && file.canRead()) {
            "Gate-5b acceptance requires the REAL fixture at getExternalFilesDir(null)/$name. " +
                "Push it before the run: adb -s emulator-5554 push '$source' " +
                "/sdcard/Android/data/com.vreader.app/files/$name"
        }
        return file
    }

    /** Import [file] through the REAL importer, then assert the stored artifact IS that book. */
    fun importReal(file: File, displayName: String, expectedSha256: String): Book {
        val book = importFile(file, displayName)
        assertEquals(
            "the imported artifact must BE $displayName (content digest), not merely a same-sized stand-in",
            expectedSha256, book.contentSHA256,
        )
        return book
    }

    fun importFile(file: File, displayName: String): Book = runBlocking {
        app.container.importer.importStream(
            "content://test/$displayName", displayName, file.inputStream(),
        )
    }

    fun importAsset(asset: String): Book {
        val staged = File(instrumentation.targetContext.cacheDir, "wi7-${System.nanoTime()}-$asset")
        instrumentation.context.assets.open(asset).use { input ->
            staged.outputStream().use { output -> input.copyTo(output) }
        }
        require(staged.length() > 0) { "the committed asset $asset staged empty" }
        return importFile(staged, asset)
    }

    // ---- the production navigation ---------------------------------------------------------------

    /**
     * Launch the app, tap [title] in the Library grid, and hand [block] the reader that tap opened.
     *
     * [extraName] is the host's own `EXTRA_FINGERPRINT_KEY`; the opened reader must carry
     * [expectedKey] under it.
     */
    inline fun <reified T : Activity> openThroughLibrary(
        compose: ComposeTestRule,
        title: String,
        expectedKey: String,
        extraName: String,
        crossinline block: (T) -> Unit,
    ) {
        assertTrue(
            "a reader from an earlier test is still on the stack — this test's lookup would be ambiguous",
            finishLiveReaders(),
        )
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.waitUntil(UI_TIMEOUT_MS) {
                compose.onAllNodesWithText(title, substring = true).fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithText(title, substring = true).performClick()
            compose.waitUntil(UI_TIMEOUT_MS) { resumed<T>() != null }
            val reader = requireNotNull(resumed<T>()) { "no ${T::class.java.simpleName} resumed" }
            try {
                var actual: String? = null
                instrumentation.runOnMainSync { actual = reader.intent.getStringExtra(extraName) }
                assertEquals(
                    "the Library tap must have opened THIS book (production intent extra)",
                    expectedKey, actual,
                )
                block(reader)
            } finally {
                finishLiveReaders()
            }
        }
    }

    /** Walk the shipped chrome: top-bar `...` More -> *Details* -> **Import annotations…**. */
    fun tapImportRowThroughMoreMenu(compose: ComposeTestRule) {
        compose.waitUntil(UI_TIMEOUT_MS) { nodeCount(compose, "chrome-more") > 0 }
        compose.onNodeWithTag("chrome-more", useUnmergedTree = true).performClick()
        compose.waitUntil(UI_TIMEOUT_MS) { nodeCount(compose, "more-row-details") > 0 }
        compose.onNodeWithTag("more-row-details", useUnmergedTree = true).performClick()
        compose.waitUntil(UI_TIMEOUT_MS) { nodeCount(compose, "details-import-annotations") > 0 }
        // The absent Export row is WI-6's load-bearing guard and it must still hold from the REAL
        // production sheet, not only from a directly-composed one (BLOCKED: needs-design #2085).
        assertEquals(
            "an Export annotations row appeared on the production Details sheet — it is BLOCKED on #2085",
            0, nodeCount(compose, "details-export-annotations"),
        )
        compose.onNodeWithTag("details-import-annotations", useUnmergedTree = true).performClick()
    }

    fun nodeCount(compose: ComposeTestRule, tag: String): Int =
        compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().size

    inline fun <reified T : Activity> resumed(): T? {
        var found: T? = null
        instrumentation.runOnMainSync {
            found = ActivityLifecycleMonitorRegistry.getInstance()
                .getActivitiesInStage(Stage.RESUMED)
                .filterIsInstance<T>()
                .firstOrNull()
        }
        return found
    }

    /**
     * Finish every reader activity that is not yet DESTROYED and wait for the stack to drain.
     * ALL non-terminal stages are included: a reader sitting in CREATED or STOPPED is still on the
     * stack and would still be found by a later lookup.
     */
    fun finishLiveReaders(): Boolean {
        fun live(): List<Activity> {
            var found: List<Activity> = emptyList()
            instrumentation.runOnMainSync {
                val monitor = ActivityLifecycleMonitorRegistry.getInstance()
                found = listOf(
                    Stage.PRE_ON_CREATE, Stage.CREATED, Stage.STARTED,
                    Stage.RESUMED, Stage.PAUSED, Stage.STOPPED, Stage.RESTARTED,
                ).flatMap { monitor.getActivitiesInStage(it) }
                    .filter { it !is MainActivity }
                    .distinct()
            }
            return found
        }
        val readers = live()
        if (readers.isEmpty()) return true
        instrumentation.runOnMainSync { readers.forEach { it.finish() } }
        val deadline = SystemClock.elapsedRealtime() + 20_000
        while (live().isNotEmpty() && SystemClock.elapsedRealtime() < deadline) Thread.sleep(50)
        return live().isEmpty()
    }
}
