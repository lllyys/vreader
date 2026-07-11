package com.vreader.app.reader

import android.webkit.WebView
import androidx.room.Room
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.webkit.WebViewAssetLoader
import com.vreader.app.annotations.AnnotationsRepository
import com.vreader.app.annotations.BookmarkToggleResult
import com.vreader.app.data.BookEntity
import com.vreader.app.data.VReaderDatabase
import com.vreader.app.reader.foliate.Azw3DocState
import com.vreader.app.reader.foliate.Azw3Document
import com.vreader.app.reader.foliate.Azw3GoToResult
import com.vreader.app.reader.foliate.FoliateBridge
import com.vreader.app.reader.foliate.FoliateGoToTarget
import com.vreader.app.reader.nav.JumpResult
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
import vreader.contracts.Locator
import java.io.File

/**
 * Feature #135 WI-8 — the AZW3/foliate bookmark navigation HOST behavior, per the plan's test catalogue
 * row `Azw3BookmarkNavTest`: toggle + list + jump on the AZW3 host, render-death mid-jump recovers, and a
 * dead-bundle timeout leaves the sheet open. It complements #135 WI-2's [com.vreader.app.reader.foliate.
 * Azw3GoToSliceTest] (which proves the low-level bridge round-trip) by driving the SAME seams the
 * [Azw3ReaderActivity] host uses to light up create/toggle/list/jump for AZW3:
 *  - the repository toggle (create/remove at a canonical position, one row per position) + presence read;
 *  - the SYNCHRONOUS sheet-dismiss decision [azw3JumpDecision] (a jumpable target → Succeeded/dismiss; an
 *    un-jumpable one → Failed/sheet-stays-open, rule 51) and the awaited-landing map [azw3JumpResult];
 *  - the render-death carry-across (`takePendingGoTo` off the dying document → `run(pendingGoTo=)` on the
 *    replacement → the jump re-issued EXACTLY ONCE), against a REAL Android WebView + `Azw3Document`;
 *  - a dead bundle (no ack) → `Timeout` → the sheet stays open.
 *
 * The repository + host-decision assertions run unconditionally (no book needed); the two REAL-WebView cases
 * skip gracefully when the local-only `foliate-spike/book.azw3` fixture is absent (gitignored, not in CI),
 * mirroring the WI-2 slice. COMPILES NOW; the live emulator execution rides WI-9 acceptance — do NOT run
 * this via connectedAndroidTest in the WI-8 lane (rule 52 — emulator contention).
 */
@RunWith(AndroidJUnit4::class)
class Azw3BookmarkNavTest {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var document: Azw3Document? = null

    @After
    fun tearDown() {
        InstrumentationRegistry.getInstrumentation().runOnMainSync { document?.destroy() }
    }

    // ---- toggle + list + presence (the host's create/remove seam) ----

    @Test
    fun toggleAtAzw3Position_createsThenRemoves_oneRowPerPosition() = runBlocking {
        val ctx = InstrumentationRegistry.getInstrumentation().targetContext
        val db = Room.inMemoryDatabaseBuilder(ctx, VReaderDatabase::class.java).build()
        try {
            val annotations = AnnotationsRepository(db.annotationDao())
            val bookKey = Locator("a".repeat(64), 2048, "azw3").fingerprintKey
            val at = Locator("a".repeat(64), 2048, "azw3", progression = 0.4)

            // Seed the PARENT book row so the `bookmarks.bookKey -> books.fingerprintKey` FK is satisfied
            // (in-memory Room enforces FKs; without this the first toggle's insert aborts with a
            // SQLiteConstraintException before any of the create/remove assertions below can run). The
            // BookEntity carries the SAME synthetic identity triple the `at` locator's fingerprintKey encodes.
            db.bookDao().upsert(
                BookEntity(
                    fingerprintKey = bookKey,
                    title = "Synthetic AZW3",
                    originalFormat = "azw3",
                    contentSHA256 = "a".repeat(64),
                    fileByteCount = 2048L,
                    localFilePath = null,
                    sourceUri = null,
                    addedAt = 1L,
                    lastOpenedAt = null,
                ),
            )

            assertTrue("nothing bookmarked at the position yet", !annotations.isBookmarked(bookKey, at))

            // First toggle → Added, one row, presence flips.
            assertEquals(BookmarkToggleResult.Added, annotations.toggleBookmark(bookKey, title = null, locator = at))
            val listed = annotations.allBookmarks().single()
            assertEquals("the listed bookmark row is at the toggled position", at, listed.locator)
            assertTrue("the position now reads bookmarked", annotations.isBookmarked(bookKey, at))

            // The FULL workflow: the created+listed bookmark's OWN locator is what the host would jump on.
            // A live (real-WebView) document with the listed row's locator → Succeeded (dismiss); a null
            // document (nothing loaded, the pre-render state) → Failed (the sheet stays open, rule 51).
            val ctxForDoc = ctx
            lateinit var live: Azw3Document
            InstrumentationRegistry.getInstrumentation().runOnMainSync {
                live = Azw3Document(WebView(ctxForDoc), File(ctxForDoc.cacheDir, "azw3-toggle-jump-noop"), ctxForDoc)
            }
            document = live
            assertEquals("jump on the listed bookmark → dismiss", JumpResult.Succeeded, azw3JumpDecision(live, listed.locator))
            assertEquals("no document loaded → the sheet stays open", JumpResult.Failed, azw3JumpDecision(null, listed.locator))

            // A repeat toggle at the SAME position → Removed (toggle alternates); no duplicate row.
            assertEquals(BookmarkToggleResult.Removed, annotations.toggleBookmark(bookKey, title = null, locator = at))
            assertEquals("the row is gone after toggle-off", 0, annotations.allBookmarks().size)
            assertTrue("presence cleared", !annotations.isBookmarked(bookKey, at))
        } finally {
            db.close()
        }
    }

    // ---- the host's SYNCHRONOUS dismiss decision + awaited-landing map ----

    @Test
    fun jumpDecision_dismissesOnJumpableTarget_staysOpenOnUnjumpable() = runBlocking {
        // A null document (nothing loaded) → Failed (sheet stays open).
        val jumpable = Locator("a".repeat(64), 2048, "azw3", progression = 0.5)
        assertEquals(JumpResult.Failed, azw3JumpDecision(document = null, canonical = jumpable))

        // A real WebView-backed document with a jumpable canonical → Succeeded (the sheet dismisses; the
        // awaited goTo lands off-thread). An un-jumpable canonical (no cfi + no finite progression) → Failed.
        val ctx = InstrumentationRegistry.getInstrumentation().targetContext
        lateinit var doc: Azw3Document
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            doc = Azw3Document(WebView(ctx), File(ctx.cacheDir, "azw3-decision-noop"), ctx)
        }
        document = doc
        assertEquals("a finite-progression target is jumpable → dismiss", JumpResult.Succeeded, azw3JumpDecision(doc, jumpable))
        val unjumpable = Locator("a".repeat(64), 2048, "azw3") // no cfi, no progression
        assertEquals("nothing to jump to → Failed (sheet stays open, rule 51)", JumpResult.Failed, azw3JumpDecision(doc, unjumpable))
        // A cfi-only canonical is jumpable even without a fraction.
        val cfiOnly = Locator("a".repeat(64), 2048, "azw3", cfi = "epubcfi(/6/4!/4/2/2[c1]/2/1:0)")
        assertEquals("a cfi target is jumpable → dismiss", JumpResult.Succeeded, azw3JumpDecision(doc, cfiOnly))
    }

    @Test
    fun jumpResult_mapsAwaitedOutcomes_landingDismisses_nonLandingStaysOpen() {
        assertEquals(JumpResult.Succeeded, azw3JumpResult(Azw3GoToResult.Succeeded(cfi = null, fraction = 0.5)))
        // Timeout / Failed (dead bundle / unresolvable) / Superseded are all NON-landings → sheet stays open.
        assertEquals(JumpResult.Failed, azw3JumpResult(Azw3GoToResult.Timeout))
        assertEquals(JumpResult.Failed, azw3JumpResult(Azw3GoToResult.Failed))
        assertEquals(JumpResult.Failed, azw3JumpResult(Azw3GoToResult.Superseded))
    }

    // ---- render-death mid-jump recovers (the host's takePendingGoTo → run(pendingGoTo=) carry) ----

    @Test
    fun renderDeathMidJump_carriesPendingBookmark_toReplacement_reissuedOnce() = runBlocking {
        val bookFile = copyBookOrSkip("book.azw3") ?: return@runBlocking
        val inst = InstrumentationRegistry.getInstrumentation()
        // Model a render-death mid-jump: a bookmark goTo issued before the book is ready HOLDS its target;
        // the host reads it off the dying document (takePendingGoTo) and seeds the REPLACEMENT via
        // run(pendingGoTo=) — the production recovery path (Azw3ReaderActivity's onRenderProcessGone).
        val target = Locator("a".repeat(64), 1024, "azw3", progression = 0.3)

        lateinit var dying: Azw3Document
        inst.runOnMainSync {
            val wv = WebView(inst.targetContext).also(::forceViewport)
            dying = Azw3Document(wv, bookFile, inst.targetContext)
        }
        // goTo before book-ready → the bookmark target is held (soft Failed) on the dying instance.
        val early = withContext(Dispatchers.Main) { dying.goTo(target) }
        assertEquals(Azw3GoToResult.Failed, early)
        val carried = withContext(Dispatchers.Main) { dying.takePendingGoTo() }
        assertEquals("the host recovers the held bookmark target from the dying document", target, carried)
        assertEquals(
            "the dying document's pending target is cleared once taken (no double-issue)",
            null, withContext(Dispatchers.Main) { dying.takePendingGoTo() },
        )

        // Seed the replacement with the carried bookmark target; its book-ready re-issues it once.
        lateinit var replacement: Azw3Document
        inst.runOnMainSync {
            val wv = WebView(inst.targetContext).also(::forceViewport)
            replacement = Azw3Document(wv, bookFile, inst.targetContext)
        }
        document = replacement
        scope.launch { replacement.run(restore = null, pendingGoTo = carried) }
        val loaded = awaitLoaded(replacement)
        withContext(Dispatchers.Main) { dying.destroy() }
        // The replacement must actually reach book-ready — that is the branch that re-issues the carried
        // bookmark jump. Asserting takePendingGoTo()==null on a NEVER-loaded document would be vacuous (the
        // target would just still be held), so the load itself is the precondition for the cleared-target
        // assertion below to mean anything.
        assertTrue("the replacement document reached book-ready (where the carried jump is re-issued)", loaded)
        // After book-ready re-issued the carried bookmark jump, the replacement's held target is cleared
        // (exactly once — a second render-death would not loop it).
        assertEquals(null, withContext(Dispatchers.Main) { replacement.takePendingGoTo() })
    }

    // ---- dead bundle → timeout → sheet stays open ----

    @Test
    fun deadBundle_bookmarkJump_timesOut_andSheetStaysOpen() = runBlocking {
        val inst = InstrumentationRegistry.getInstrumentation()
        lateinit var bridge: FoliateBridge
        inst.runOnMainSync {
            val wv = WebView(inst.targetContext)
            val loader = WebViewAssetLoader.Builder()
                .addPathHandler("/assets/", WebViewAssetLoader.AssetsPathHandler(inst.targetContext))
                .build()
            bridge = FoliateBridge(wv, loader, scope)
        }
        // A bare WebView that never loads the reader shell → no goto-ack ever arrives → Timeout, which the
        // host maps to JumpResult.Failed (the Bookmarks sheet stays open — rule 51, no invented error).
        val result = withContext(Dispatchers.Main) { bridge.goTo(FoliateGoToTarget.Fraction(0.5), timeoutMs = 800) }
        assertEquals(Azw3GoToResult.Timeout, result)
        assertEquals("a timed-out bookmark jump keeps the sheet open", JumpResult.Failed, azw3JumpResult(result))
    }

    // ---- helpers (mirroring Azw3GoToSliceTest) ----

    /** Copy the local-only test-APK book asset into app-private storage; skip the test if it's absent. */
    private fun copyBookOrSkip(bookAssetName: String): File? {
        val inst = InstrumentationRegistry.getInstrumentation()
        val hasBook = inst.context.assets.list("foliate-spike")?.contains(bookAssetName) == true
        org.junit.Assume.assumeTrue("local-only foliate-spike/$bookAssetName absent — skipping", hasBook)
        if (!hasBook) return null
        return File(inst.targetContext.cacheDir, "azw3-bookmark-nav-book").apply {
            inst.context.assets.open("foliate-spike/$bookAssetName").use { input ->
                outputStream().use { input.copyTo(it) }
            }
        }
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

    /** Poll the document's state until Loaded (the WebView renders off the main loop, so a foreground poll
     *  is the observable — mirrors [com.vreader.app.reader.foliate.Azw3GoToSliceTest]). Returns whether it
     *  reached book-ready within the deadline so the caller can assert on it (not a silent return). */
    private fun awaitLoaded(doc: Azw3Document): Boolean {
        val deadline = System.currentTimeMillis() + 30_000
        while (System.currentTimeMillis() < deadline) {
            if (doc.state.value is Azw3DocState.Loaded) return true
            Thread.sleep(200)
        }
        return false
    }
}
