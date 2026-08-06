package com.vreader.app.annotations

import android.os.SystemClock
import android.util.Log
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.annotations.AnnotationImportProductionPath.REAL_EPUB_DISPLAY_NAME
import com.vreader.app.annotations.AnnotationImportProductionPath.REAL_EPUB_FILE
import com.vreader.app.annotations.AnnotationImportProductionPath.REAL_EPUB_SHA256
import com.vreader.app.annotations.AnnotationImportProductionPath.REAL_TXT_DISPLAY_NAME
import com.vreader.app.annotations.AnnotationImportProductionPath.REAL_TXT_FILE
import com.vreader.app.annotations.AnnotationImportProductionPath.REAL_TXT_SHA256
import com.vreader.app.annotations.AnnotationImportProductionPath.UI_TIMEOUT_MS
import com.vreader.app.annotations.AnnotationImportProductionPath.app
import com.vreader.app.annotations.AnnotationImportProductionPath.importReal
import com.vreader.app.annotations.AnnotationImportProductionPath.instrumentation
import com.vreader.app.annotations.AnnotationImportProductionPath.nodeCount
import com.vreader.app.annotations.AnnotationImportProductionPath.openThroughLibrary
import com.vreader.app.annotations.AnnotationImportProductionPath.requireRealFile
import com.vreader.app.annotations.AnnotationImportProductionPath.tapImportRowThroughMoreMenu
import com.vreader.app.annotations.AnnotationsRoundTripFixtures.assertRoundTripEquality
import com.vreader.app.annotations.AnnotationsRoundTripFixtures.awaitStore
import com.vreader.app.annotations.AnnotationsRoundTripFixtures.exportToProviderFile
import com.vreader.app.annotations.AnnotationsRoundTripFixtures.exportedText
import com.vreader.app.annotations.AnnotationsRoundTripFixtures.firstIdeographRun
import com.vreader.app.annotations.AnnotationsRoundTripFixtures.importThroughProductionPath
import com.vreader.app.annotations.AnnotationsRoundTripFixtures.secondPrecision
import com.vreader.app.annotations.AnnotationsRoundTripFixtures.seedEpubAnnotations
import com.vreader.app.annotations.AnnotationsRoundTripFixtures.snapshot
import com.vreader.app.annotations.AnnotationsRoundTripFixtures.stagedFiles
import com.vreader.app.annotations.AnnotationsRoundTripFixtures.txtLocator
import com.vreader.app.annotations.AnnotationsRoundTripFixtures.wipeAnnotations
import com.vreader.app.annotations.AnnotationsRoundTripFixtures.writeLargestImportableFile
import com.vreader.app.data.Book
import com.vreader.app.reader.ReaderActivity
import com.vreader.app.reader.TxtReaderActivity
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.FixMethodOrder
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.MethodSorters

/**
 * Feature #165 WI-7 — the **export -> import round trip**, driven through the production entry point.
 *
 * The round trip that matters is not "a file was written" and not "no exception was thrown": it is
 * *the annotations land where they were*. Three ways this could pass while wrong, and what is done
 * about each:
 *
 *  - **Counts alone.** A merge that put every row at the wrong position keeps the count. So the
 *    assertions compare the FULL record — id, colour, text, note, **the decoded `Locator`**,
 *    `createdAt` and `updatedAt` — as sets, and the locators are asserted on their own first so a
 *    failure names the position rather than the row.
 *  - **A file the test wrote itself.** The imported bytes come from the SHIPPED
 *    `AnnotationsExportWriter` over the real repository, not from hand-assembled JSON — otherwise
 *    the "round trip" would never touch the export half and a writer/reader disagreement would
 *    sail through. **This does NOT discharge A-1/A-2's end-to-end leg or A-10b**: the export
 *    *entry point* (the designed `Export annotations…` row) does not exist and is
 *    `BLOCKED: needs-design #2085` — the writer is exercised IN-PROCESS, which is exactly the
 *    reach the export half has in this pass, and no more.
 *  - **A stubbed import path.** The picked `Uri` arrives through the app's own SAF launcher
 *    (intercepted by [AnnotationImportPickerMonitor]), is read through the app's own
 *    `ContentResolver` + a REAL `content://` FileProvider document, and is applied by the user
 *    tapping the designed `Import N items` button. Nothing in the chain is called directly.
 *
 * Fixtures: the real EPUB for the headline round trip and the real 14 MB CJK TXT for the CJK payload
 * leg (CJK `selectedText` must survive UTF-8 encode -> SAF write -> SAF read -> decode -> Room
 * byte-for-byte, which a Latin fixture cannot prove). Both are `require`-d, never `assumeTrue`-d —
 * a skipped instrumentation method exits 0 exactly like a passing one. The `adb push` commands live
 * once, on [AnnotationImportProductionPath]; the connected task uninstalls the app at the end, so
 * re-push before EVERY run.
 *
 * Run ONE class per connected invocation; never drive the emulator while it runs.
 */
@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class AnnotationsRoundTripConnectedTest {

    @get:Rule val compose = createEmptyComposeRule()

    @After
    fun cleanUp() {
        AnnotationImportProductionPath.finishLiveReaders()
        stagedFiles.forEach { it.delete() }
        stagedFiles.clear()
    }

    // ---- 1. the headline: export -> wipe -> import through the production path -------------------

    @Test
    fun aEpub_exportThenImport_restoresEveryRowAtItsOwnLocator() {
        val book = realEpub()
        wipeAnnotations(book.fingerprintKey)
        val anchored = seedEpubAnnotations(book)

        val before = snapshot(book.fingerprintKey)
        assertEquals("seeded 3 highlights", 3, before.highlights.size)
        assertEquals("seeded 2 notes", 2, before.notes.size)
        assertEquals("seeded 2 bookmarks", 2, before.bookmarks.size)

        val exported = exportToProviderFile(book.fingerprintKey, "wi7-epub-export.json")
        wipeAnnotations(book.fingerprintKey)
        assertEquals("the wipe must really empty the book", 0, snapshot(book.fingerprintKey).total)

        importThroughProductionPath<ReaderActivity>(
            compose, book, ReaderActivity.EXTRA_FINGERPRINT_KEY, exported, expectedImportable = 7,
        ) {
            compose.waitUntil(UI_TIMEOUT_MS) { nodeCount(compose, "annot-import-sheet-content") == 0 }
        }

        val after = snapshot(book.fingerprintKey)
        assertEquals("every row came back", 7, after.total)

        // The discriminating assertions — locators first, then whole rows (see the helper's KDoc for
        // what each normalisation pins and why it is not hiding anything).
        assertRoundTripEquality(before, after)

        // K-5, OBSERVED not assumed: the seeded row carried a text anchor; the restored one cannot,
        // so it re-anchors by locator. Identical to what a WebDAV restore already does.
        val restoredAnchored = after.highlights.single { it.id == anchored.id }
        assertNull("K-5: an imported highlight's engine anchor is null", restoredAnchored.anchor)
        assertEquals("…and its locator is untouched", anchored.locator, restoredAnchored.locator)
    }

    // ---- 2. idempotency, at the surface the user actually sees ----------------------------------

    @Test
    fun bEpub_reImportingTheSameFile_offersNothingAndChangesNothing() {
        val book = realEpub()
        wipeAnnotations(book.fingerprintKey)
        seedEpubAnnotations(book)
        val exported = exportToProviderFile(book.fingerprintKey, "wi7-epub-idempotent.json")
        val before = snapshot(book.fingerprintKey)

        // The rows are ALREADY in the database, so the reader's already-present filter must collapse
        // the whole file to nothing and the designed primary must be DISABLED (C-8 + C-11). The user
        // cannot commit a no-op — a stronger statement than "a second apply inserted 0".
        val monitor = AnnotationImportPickerMonitor.install(exported)
        try {
            openThroughLibrary<ReaderActivity>(
                compose, book.title, book.fingerprintKey, ReaderActivity.EXTRA_FINGERPRINT_KEY,
            ) {
                tapImportRowThroughMoreMenu(compose)
                compose.waitUntil(UI_TIMEOUT_MS) { nodeCount(compose, "annot-import-sheet-content") > 0 }
                compose.onNodeWithText("Import 0 items", useUnmergedTree = true).assertExists()
                compose.onNodeWithTag("annot-import-confirm", useUnmergedTree = true).assertIsNotEnabled()
                compose.onNodeWithTag("annot-import-cancel", useUnmergedTree = true).performClick()
            }
        } finally {
            monitor.remove()
        }

        val after = snapshot(book.fingerprintKey)
        assertEquals("a refused re-import must change nothing", before.highlights.toSet(), after.highlights.toSet())
        assertEquals(before.notes.toSet(), after.notes.toSet())
        assertEquals(before.bookmarks.toSet(), after.bookmarks.toSet())
    }

    // ---- 3. the CJK payload leg ------------------------------------------------------------------

    @Test
    fun cTxt_cjkSelectedText_survivesTheWholeSafRoundTripByteForByte() {
        val file = requireRealFile(
            REAL_TXT_FILE, REAL_TXT_SHA256, "test-books/books/txt/$REAL_TXT_DISPLAY_NAME",
        )
        val book = importReal(file, REAL_TXT_DISPLAY_NAME, REAL_TXT_SHA256)
        wipeAnnotations(book.fingerprintKey)

        // Real text from the real book. A CONTIGUOUS ideograph run is taken (rather than an arbitrary
        // slice) for one reason worth stating: a slice of prose usually contains a newline or a
        // quotation mark, which JSON legitimately escapes — the byte-level assertion at the end would
        // then fail for a formatting reason instead of an encoding one, which is not the property
        // under test.
        val decoded = file.readText(Charsets.UTF_16LE).drop(1).take(200_000)
        val cjk = requireNotNull(firstIdeographRun(decoded, length = 20)) {
            "no 20-character ideograph run in the first 200 000 characters of the real CJK novel"
        }
        assertTrue("the sampled fixture text must be all CJK", cjk.all { it.code in 0x4E00..0x9FFF })

        val seeded = runBlocking {
            app.container.annotationsRepository.addHighlight(
                bookKey = book.fingerprintKey,
                color = AnnotationColor.blue,
                selectedText = cjk,
                locator = txtLocator(book, charOffset = 2000, start = 2000, end = 2020),
                anchor = null,
                note = "笔记：这一段很重要",
            )
        }
        val exported = exportToProviderFile(book.fingerprintKey, "wi7-txt-export.json")
        val exportedBytes = exportedText("wi7-txt-export.json")
        wipeAnnotations(book.fingerprintKey)

        importThroughProductionPath<TxtReaderActivity>(
            compose, book, TxtReaderActivity.EXTRA_FINGERPRINT_KEY, exported, expectedImportable = 1,
        ) {
            compose.waitUntil(UI_TIMEOUT_MS) { nodeCount(compose, "annot-import-sheet-content") == 0 }
        }

        val restored = snapshot(book.fingerprintKey).highlights.single()
        assertEquals("the CJK selection must survive byte-for-byte", seeded.selectedText, restored.selectedText)
        assertEquals("…and so must a CJK note", seeded.note, restored.note)
        assertEquals(seeded.locator, restored.locator)
        assertEquals(seeded.id, restored.id)
        assertEquals(secondPrecision(seeded.createdAt), restored.createdAt)
        assertEquals(secondPrecision(seeded.updatedAt), restored.updatedAt)
        // A byte-level check on top of the string compare: an encoding round trip that replaced a
        // character would still compare equal if BOTH sides were corrupted identically, so pin the
        // exported BYTES too.
        assertTrue(
            "the exported file must carry the CJK text as UTF-8, not as escapes or replacement chars",
            exportedBytes.contains(cjk),
        )
    }

    // ---- 4. A-9 — the largest importable file, measured ON TARGET --------------------------------

    @Test
    fun dLargestImportableFile_previewAndApply_stayWithinTheStatedCeiling() {
        val book = realEpub()
        wipeAnnotations(book.fingerprintKey)

        val (uri, rows) = writeLargestImportableFile(book, "wi7-large-import.json")
        Log.i(TAG, "largest importable file: rows=$rows bytes=${exportedText("wi7-large-import.json").toByteArray().size}")

        val controller = app.container.annotationsIoController(instrumentation.targetContext.contentResolver)
        val previewMs: Long
        val parsed = runBlocking {
            val t0 = SystemClock.elapsedRealtime()
            val r = controller.preview(uri, book.fingerprintKey, book.title)
            previewMs = SystemClock.elapsedRealtime() - t0
            r
        }
        val preview = (parsed as ImportParseResult.Ok).preview
        assertEquals("every generated row must be importable", rows, preview.importable)

        val applyMs: Long
        val report = runBlocking {
            val t0 = SystemClock.elapsedRealtime()
            val r = controller.apply(preview)
            applyMs = SystemClock.elapsedRealtime() - t0
            r
        }
        assertTrue("the apply must succeed", report.isSuccess)
        assertEquals(
            "A-11 on target: the number the user approves is the number they get",
            preview.importable, report.getOrThrow().appliedTotal,
        )

        Log.i(TAG, "A-9 measured on target: preview=${previewMs}ms apply=${applyMs}ms rows=$rows")
        // Asserted AS STATED in the plan, not to a looser ceiling a slow build would still clear.
        assertTrue("A-9: preview of the largest importable file must stay <= 2000 ms (was $previewMs)", previewMs <= 2_000)
        assertTrue("A-9: apply must stay <= 1000 ms (was $applyMs)", applyMs <= 1_000)
    }

    // ---- 5. the merge survives the reader being torn down mid-apply (Gate-4 round 1, High) -------

    @Test
    fun eLargeImport_survivesTheReaderBeingFinishedMidMerge() {
        val book = realEpub()
        wipeAnnotations(book.fingerprintKey)
        val (uri, rows) = writeLargestImportableFile(book, "wi7-teardown-import.json")

        // Deliberately the LARGEST importable file: the same merge measures ~700 ms on this
        // emulator (see the A-9 test), which is the window `finish()` has to land inside. A
        // seven-row import would usually complete first and the test would pass for the wrong
        // reason. That timing is an ASSUMPTION, so the run OBSERVES it rather than trusting it
        // (Gate-4 round 2, Medium) — see `rowsWhenDestroyed` below.
        var rowsWhenDestroyed = -1
        importThroughProductionPath<ReaderActivity>(
            compose, book, ReaderActivity.EXTRA_FINGERPRINT_KEY, uri, expectedImportable = rows,
        ) { reader ->
            // The user taps Import and immediately leaves — a back press, a rotation, a finish. The
            // applier rethrows CancellationException, so an apply on the COMPOSITION scope would be
            // cancelled right here, the transaction would roll back, and nothing would land.
            instrumentation.runOnMainSync { reader.finish() }
            // Destruction is what cancels the composition scope, so THAT is the moment to sample.
            assertTrue(
                "the reader did not reach DESTROYED — the teardown never happened",
                AnnotationImportProductionPath.awaitNoLiveReaders(timeoutMs = 20_000),
            )
            rowsWhenDestroyed = snapshot(book.fingerprintKey).highlights.size
        }

        // The premise, checked: the merge must still have been RUNNING when the composition died.
        // If it had already finished, this run cannot tell a durable scope from a composition one,
        // and saying "passed" would be the false green this whole test exists to prevent — so it
        // fails LOUDLY as inconclusive instead, with the number that says how to widen the window.
        assertTrue(
            "INCONCLUSIVE, not a pass: the merge had already applied $rowsWhenDestroyed of $rows rows " +
                "by the time the reader was DESTROYED, so a composition-scoped apply would have " +
                "survived too. Widen the window (a larger fixture / a slower device) and re-run.",
            rowsWhenDestroyed in 0 until rows,
        )

        awaitStore(book.fingerprintKey, timeoutMs = 60_000, message = "the merge did not survive the teardown") {
            it.highlights.size == rows
        }
        assertEquals(
            "every approved row must have landed even though the reader was finished mid-merge",
            rows, snapshot(book.fingerprintKey).highlights.size,
        )
    }

    // ---- helpers ---------------------------------------------------------------------------------

    private fun realEpub(): Book = importReal(
        requireRealFile(REAL_EPUB_FILE, REAL_EPUB_SHA256, "test-books/books/epub/$REAL_EPUB_DISPLAY_NAME"),
        REAL_EPUB_DISPLAY_NAME,
        REAL_EPUB_SHA256,
    )

    private companion object {
        const val TAG = "WI165-ROUNDTRIP"
    }
}
