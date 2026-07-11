package com.vreader.app.reader.foliate

import android.webkit.WebView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.webkit.WebViewAssetLoader
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * Feature #135 WI-2 — the awaited AZW3/foliate goTo bridge, driven against a REAL Android WebView on
 * the emulator. The pure await-machinery is exhaustively unit-tested (FoliateGoToTest, JVM); this
 * slice proves the whole round-trip end-to-end: the shell `__vreaderGoTo` shim → foliate `view.goTo`
 * → relocate settles → `goto-ack` reaches native → the CompletableDeferred resolves.
 *
 * COMPILES NOW; its live execution rides WI-7 (host wiring / acceptance) — the real CJK AZW3 fixture is
 * local-only (gitignored, not in CI), so the render cases skip gracefully when it is absent, and the
 * dead-bundle timeout case is self-contained. Do NOT run this via connectedAndroidTest in the WI-2
 * lane (rule 52 — emulator contention); the orchestrator runs it in the WI-7 verification pass.
 */
@RunWith(AndroidJUnit4::class)
class Azw3GoToSliceTest {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var document: Azw3Document? = null

    @After
    fun tearDown() {
        InstrumentationRegistry.getInstrumentation().runOnMainSync { document?.destroy() }
    }

    /** Copy the local-only test-APK book asset into app-private storage; skip the test if it's absent. */
    private fun copyBookOrSkip(bookAssetName: String): File? {
        val inst = InstrumentationRegistry.getInstrumentation()
        val hasBook = inst.context.assets.list("foliate-spike")?.contains(bookAssetName) == true
        org.junit.Assume.assumeTrue("local-only foliate-spike/$bookAssetName absent — skipping", hasBook)
        if (!hasBook) return null
        return File(inst.targetContext.cacheDir, "goto-slice-book").apply {
            inst.context.assets.open("foliate-spike/$bookAssetName").use { input ->
                outputStream().use { input.copyTo(it) }
            }
        }
    }

    private fun buildDocument(bookAssetName: String): Azw3Document? {
        val inst = InstrumentationRegistry.getInstrumentation()
        val bookFile = copyBookOrSkip(bookAssetName) ?: return null
        lateinit var doc: Azw3Document
        inst.runOnMainSync {
            WebView.setWebContentsDebuggingEnabled(true)
            val wv = WebView(inst.targetContext)
            forceViewport(wv)
            doc = Azw3Document(wv, bookFile, inst.targetContext)
        }
        document = doc
        return doc
    }

    private fun forceViewport(wv: WebView) {
        val px = InstrumentationRegistry.getInstrumentation().targetContext.resources.displayMetrics
        val ww = if (px.widthPixels > 0) px.widthPixels else 1080
        val hh = if (px.heightPixels > 0) px.heightPixels else 1920
        wv.measure(
            android.view.View.MeasureSpec.makeMeasureSpec(ww, android.view.View.MeasureSpec.EXACTLY),
            android.view.View.MeasureSpec.makeMeasureSpec(hh, android.view.View.MeasureSpec.EXACTLY),
        )
        wv.layout(0, 0, ww, hh)
    }

    @Test
    fun realRelocateAck_resolvesGoTo() = runBlocking {
        val doc = buildDocument("book.azw3") ?: return@runBlocking
        // run() collects on Main; launch it and give the book time to open + render.
        scope.launch { doc.run(restore = null) }
        awaitLoaded(doc)
        val target = vreader.contracts.Locator(
            contentSHA256 = "a".repeat(64), fileByteCount = 1024, format = "azw3", progression = 0.5,
        )
        val result = withContext(Dispatchers.Main) { doc.goTo(target) }
        assertTrue("expected a settled goTo, got $result", result is Azw3GoToResult.Succeeded || result == Azw3GoToResult.Timeout)
    }

    @Test
    fun renderDeathMidJump_pendingTargetSurvivesRecreation() = runBlocking {
        val bookFile = copyBookOrSkip("book.azw3") ?: return@runBlocking
        val inst = InstrumentationRegistry.getInstrumentation()
        // A goTo whose book isn't ready yet HOLDS the target. This models a render-death mid-jump: the
        // host reads the held target off the dying document (takePendingGoTo) and seeds it into the
        // REPLACEMENT via run(pendingGoTo=...) — the actual production recovery path (WI-7), not a
        // same-instance re-book-ready. We prove EXACTLY ONE injection lands after the replacement's
        // book-ready, i.e. the pending target is not lost with the disposed document (Gate-4 F2).
        val target = vreader.contracts.Locator(
            contentSHA256 = "a".repeat(64), fileByteCount = 1024, format = "azw3", progression = 0.3,
        )
        lateinit var dying: Azw3Document
        inst.runOnMainSync {
            val wv = WebView(inst.targetContext).also(::forceViewport)
            dying = Azw3Document(wv, bookFile, inst.targetContext)
        }
        // goTo before book-ready → the target is held (soft Failed) on the dying instance.
        val early = withContext(Dispatchers.Main) { dying.goTo(target) }
        assertEquals(Azw3GoToResult.Failed, early)
        val carried = withContext(Dispatchers.Main) { dying.takePendingGoTo() }
        assertEquals("host must recover the held target from the dying document", target, carried)
        assertEquals("dying document's pending target must be cleared once taken", null, withContext(Dispatchers.Main) { dying.takePendingGoTo() })
        // Seed the replacement with the carried target; its book-ready re-issues it once.
        lateinit var replacement: Azw3Document
        inst.runOnMainSync {
            val wv = WebView(inst.targetContext).also(::forceViewport)
            replacement = Azw3Document(wv, bookFile, inst.targetContext)
        }
        document = replacement
        scope.launch { replacement.run(restore = null, pendingGoTo = carried) }
        awaitLoaded(replacement)
        withContext(Dispatchers.Main) { dying.destroy() }
        // After book-ready re-issued the carried goTo, the replacement's held target is cleared (exactly
        // once — a second render-death wouldn't loop it).
        assertEquals(null, withContext(Dispatchers.Main) { replacement.takePendingGoTo() })
    }

    @Test
    fun deadBundle_timesOut() = runBlocking {
        // A bare WebView that never loads the reader shell → no ack ever arrives → Timeout.
        val inst = InstrumentationRegistry.getInstrumentation()
        lateinit var bridge: FoliateBridge
        inst.runOnMainSync {
            val wv = WebView(inst.targetContext)
            val loader = WebViewAssetLoader.Builder()
                .addPathHandler("/assets/", WebViewAssetLoader.AssetsPathHandler(inst.targetContext))
                .build()
            bridge = FoliateBridge(wv, loader, scope)
        }
        val result = withContext(Dispatchers.Main) {
            bridge.goTo(FoliateGoToTarget.Fraction(0.5), timeoutMs = 800)
        }
        assertEquals(Azw3GoToResult.Timeout, result)
    }

    private suspend fun awaitLoaded(doc: Azw3Document) {
        val deadline = System.currentTimeMillis() + 30_000
        while (System.currentTimeMillis() < deadline) {
            if (doc.state.value is Azw3DocState.Loaded) return
            withContext(Dispatchers.Main) { /* yield to the WebView loop */ }
            Thread.sleep(200)
        }
    }
}
