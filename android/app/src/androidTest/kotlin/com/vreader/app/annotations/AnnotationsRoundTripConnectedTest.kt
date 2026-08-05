package com.vreader.app.annotations

import android.net.Uri
import android.os.SystemClock
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.core.content.FileProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.annotations.AnnotationImportProductionPath.UI_TIMEOUT_MS
import com.vreader.app.annotations.AnnotationImportProductionPath.app
import com.vreader.app.annotations.AnnotationImportProductionPath.importReal
import com.vreader.app.annotations.AnnotationImportProductionPath.instrumentation
import com.vreader.app.annotations.AnnotationImportProductionPath.nodeCount
import com.vreader.app.annotations.AnnotationImportProductionPath.openThroughLibrary
import com.vreader.app.annotations.AnnotationImportProductionPath.requireRealFile
import com.vreader.app.annotations.AnnotationImportProductionPath.tapImportRowThroughMoreMenu
import com.vreader.app.data.Book
import com.vreader.app.reader.ReaderActivity
import com.vreader.app.reader.TxtReaderActivity
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.FixMethodOrder
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.MethodSorters
import vreader.contracts.Locator
import java.io.File
import android.util.Log

/**
 * Feature #165 WI-7 — the **export -> import round trip**, driven through the production entry point.
 *
 * The round trip that matters is not "a file was written" and not "no exception was thrown": it is
 * *the annotations land where they were*. Three ways this test could pass while wrong, and what is
 * done about each:
 *
 *  - **Counts alone.** A merge that put every row at the wrong position keeps the count. So every
 *    assertion below compares the FULL `HighlightRecord` / `NoteRecord` / `BookmarkRecord` — id,
 *    colour, text, note, **the decoded `Locator`**, `createdAt` and `updatedAt` — as sets, and the
 *    locators are additionally asserted on their own so a failure names the position, not the row.
 *  - **A file the test wrote itself.** The imported bytes are produced by the SHIPPED
 *    `AnnotationsExportWriter` over the real repository (reachable in-process even though its ROW is
 *    `BLOCKED: needs-design #2085`, WI-8), not hand-assembled here — otherwise the "round trip"
 *    would never touch the export half at all.
 *  - **A stubbed import path.** The picked `Uri` arrives through the app's own SAF launcher
 *    (intercepted by [AnnotationImportPickerMonitor]), is read through the app's own
 *    `ContentResolver` + a REAL `content://` FileProvider document, and is applied by the user
 *    tapping the designed `Import N items` button. Nothing in the chain is called directly.
 *
 * Fixtures: the real EPUB for the headline round trip and the real 14 MB CJK TXT for the CJK payload
 * leg (CJK `selectedText` must survive UTF-8 encode -> SAF write -> SAF read -> decode -> Room
 * byte-for-byte, which a Latin fixture cannot prove). Both are `require`-d, never `assumeTrue`-d.
 * Push before EVERY run (the connected task uninstalls the app at the end):
 *
 * ```
 * adb -s emulator-5554 shell mkdir -p /sdcard/Android/data/com.vreader.app/files
 * adb -s emulator-5554 push 'test-books/books/epub/The Half Second - Li Xiaolai.epub' \
 *     /sdcard/Android/data/com.vreader.app/files/wi7-real.epub
 * adb -s emulator-5554 push 'test-books/books/txt/黑暗血时代.txt' \
 *     /sdcard/Android/data/com.vreader.app/files/wi7-real.txt
 * ```
 *
 * Run ONE class per connected invocation; never drive the emulator while it runs.
 */
@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class AnnotationsRoundTripConnectedTest {

    @get:Rule val compose = createEmptyComposeRule()

    private val repo get() = app.container.annotationsRepository
    private val stagedFiles = mutableListOf<File>()

    @After
    fun cleanUp() {
        AnnotationImportProductionPath.finishLiveReaders()
        stagedFiles.forEach { it.delete() }
    }

    // ---- 1. the headline: export -> wipe -> import through the production path -------------------

    @Test
    fun aEpub_exportThenImport_restoresEveryRowAtItsOwnLocator() {
        val book = importReal(
            requireRealFile(
                AnnotationImportProductionPath.REAL_EPUB_FILE,
                AnnotationImportProductionPath.REAL_EPUB_SHA256,
                "test-books/books/epub/${AnnotationImportProductionPath.REAL_EPUB_DISPLAY_NAME}",
            ),
            AnnotationImportProductionPath.REAL_EPUB_DISPLAY_NAME,
            AnnotationImportProductionPath.REAL_EPUB_SHA256,
        )
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
            book, ReaderActivity.EXTRA_FINGERPRINT_KEY, exported, expectedImportable = 7,
        )

        val after = snapshot(book.fingerprintKey)
        assertEquals("every row came back", 7, after.total)

        // The discriminating assertion: LOCATOR equality, kind by kind. A merge that landed all seven
        // rows at a default or reconstructed position passes a count check and fails right here.
        assertEquals(
            "highlight locators must be the ones exported",
            before.highlights.map { it.locator }.toSet(),
            after.highlights.map { it.locator }.toSet(),
        )
        assertEquals(
            "note locators must be the ones exported",
            before.notes.map { it.locator }.toSet(),
            after.notes.map { it.locator }.toSet(),
        )
        assertEquals(
            "bookmark locators must be the ones exported",
            before.bookmarks.map { it.locator }.toSet(),
            after.bookmarks.map { it.locator }.toSet(),
        )

        // …and then the WHOLE row, so colour / text / note / UUID / both timestamps are pinned too.
        //
        // TWO normalisations are applied to the EXPECTED side, and both are contract behaviour that
        // this run OBSERVED rather than assumptions written in advance:
        //  - `anchor` is dropped: the backup wire carries no anchor field at all (K-5), asserted on
        //    its own below rather than hidden here.
        //  - timestamps are truncated to the SECOND: `BackupJson` emits ISO-8601 UTC at second
        //    precision for Swift `Codable` parity (`AnnotationBackupMapper`'s header states it), so
        //    an export/import round trip cannot carry milliseconds. Expressed as the exact expected
        //    TRANSFORM, not by dropping the fields — a regression that zeroed the timestamps or
        //    re-minted them at `now()` still fails here.
        assertEquals(
            before.highlights.map { it.copy(anchor = null).atWirePrecision() }.toSet(),
            after.highlights.map { it.copy(anchor = null) }.toSet(),
        )
        assertEquals(
            before.notes.map { it.copy(anchor = null).atWirePrecision() }.toSet(),
            after.notes.map { it.copy(anchor = null) }.toSet(),
        )
        assertEquals(
            before.bookmarks.map { it.atWirePrecision() }.toSet(),
            after.bookmarks.toSet(),
        )
        // The truncation is real, not a rounding artefact of the assertion above: at least one
        // seeded row had sub-second precision to lose.
        assertTrue(
            "the seeded timestamps must actually carry milliseconds, or the check above proves nothing",
            before.highlights.any { it.createdAt % 1000L != 0L },
        )

        // K-5, OBSERVED not assumed: the seeded row carried a text anchor; the restored one cannot,
        // so it re-anchors by locator. Identical to what a WebDAV restore already does.
        val restoredAnchored = after.highlights.single { it.id == anchored.id }
        assertNull("K-5: an imported highlight's engine anchor is null", restoredAnchored.anchor)
        assertEquals("…and its locator is untouched", anchored.locator, restoredAnchored.locator)
    }

    // ---- 2. idempotency, at the surface the user actually sees ----------------------------------

    @Test
    fun bEpub_reImportingTheSameFile_offersNothingAndChangesNothing() {
        val book = importReal(
            requireRealFile(
                AnnotationImportProductionPath.REAL_EPUB_FILE,
                AnnotationImportProductionPath.REAL_EPUB_SHA256,
                "test-books/books/epub/${AnnotationImportProductionPath.REAL_EPUB_DISPLAY_NAME}",
            ),
            AnnotationImportProductionPath.REAL_EPUB_DISPLAY_NAME,
            AnnotationImportProductionPath.REAL_EPUB_SHA256,
        )
        wipeAnnotations(book.fingerprintKey)
        seedEpubAnnotations(book)
        val exported = exportToProviderFile(book.fingerprintKey, "wi7-epub-idempotent.json")
        val before = snapshot(book.fingerprintKey)

        // The rows are ALREADY in the database, so the reader's already-present filter must collapse
        // the whole file to nothing and the designed primary must be DISABLED (C-8 + C-11). The user
        // cannot commit a no-op — which is a stronger statement than "a second apply inserted 0".
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
            AnnotationImportProductionPath.REAL_TXT_FILE,
            AnnotationImportProductionPath.REAL_TXT_SHA256,
            "test-books/books/txt/${AnnotationImportProductionPath.REAL_TXT_DISPLAY_NAME}",
        )
        val book = importReal(
            file,
            AnnotationImportProductionPath.REAL_TXT_DISPLAY_NAME,
            AnnotationImportProductionPath.REAL_TXT_SHA256,
        )
        wipeAnnotations(book.fingerprintKey)

        // Real text from the real book, not a hand-typed sample: whatever this novel actually
        // contains is what has to survive. A CONTIGUOUS ideograph run is taken (rather than a fixed
        // slice) for one reason worth stating: an arbitrary slice of prose usually contains a
        // newline or a quotation mark, which JSON legitimately escapes — and the byte-level
        // assertion at the end of this test would then fail for a formatting reason instead of an
        // encoding one, which is not the property under test.
        val decoded = file.readText(Charsets.UTF_16LE).drop(1).take(200_000)
        val cjk = requireNotNull(firstIdeographRun(decoded, length = 20)) {
            "no 20-character ideograph run in the first 200 000 characters of the real CJK novel"
        }
        assertTrue("the sampled fixture text must be all CJK", cjk.all { it.code in 0x4E00..0x9FFF })

        val seeded = runBlocking {
            repo.addHighlight(
                bookKey = book.fingerprintKey,
                color = AnnotationColor.blue,
                selectedText = cjk,
                locator = txtLocator(book, charOffset = 2000, start = 2000, end = 2024),
                anchor = null,
                note = "笔记：这一段很重要",
            )
        }
        val exported = exportToProviderFile(book.fingerprintKey, "wi7-txt-export.json")
        wipeAnnotations(book.fingerprintKey)

        importThroughProductionPath<TxtReaderActivity>(
            book, TxtReaderActivity.EXTRA_FINGERPRINT_KEY, exported, expectedImportable = 1,
        )

        val restored = snapshot(book.fingerprintKey).highlights.single()
        assertEquals("the CJK selection must survive byte-for-byte", seeded.selectedText, restored.selectedText)
        assertEquals("…and so must a CJK note", seeded.note, restored.note)
        assertEquals(seeded.locator, restored.locator)
        assertEquals(seeded.id, restored.id)
        // Second precision, for the reason recorded in the EPUB test: the cross-platform wire is
        // ISO-8601 at second precision. Asserted as the transform, so a lost or re-minted timestamp
        // still fails.
        assertEquals(secondPrecision(seeded.createdAt), restored.createdAt)
        assertEquals(secondPrecision(seeded.updatedAt), restored.updatedAt)
        // A byte-level check on top of the string compare: an encoding round trip that silently
        // replaced a character would still compare equal if BOTH sides were corrupted identically,
        // so pin the exported BYTES too.
        assertTrue(
            "the exported file must carry the CJK text as UTF-8, not as escapes or replacement chars",
            exportedText("wi7-txt-export.json").contains(cjk),
        )
    }

    // ---- 4. A-9 — the largest importable file, measured ON TARGET --------------------------------

    @Test
    fun dLargestImportableFile_previewAndApply_stayWithinTheStatedCeiling() {
        val book = importReal(
            requireRealFile(
                AnnotationImportProductionPath.REAL_EPUB_FILE,
                AnnotationImportProductionPath.REAL_EPUB_SHA256,
                "test-books/books/epub/${AnnotationImportProductionPath.REAL_EPUB_DISPLAY_NAME}",
            ),
            AnnotationImportProductionPath.REAL_EPUB_DISPLAY_NAME,
            AnnotationImportProductionPath.REAL_EPUB_SHA256,
        )
        wipeAnnotations(book.fingerprintKey)

        // A-9 asks for a MAX-SIZE file. The plan's parenthetical "10 000-row file" is not reachable:
        // MAX_IMPORT_ROWS is 10 000 but MAX_IMPORT_JSON_BYTES is 2 MiB, and a single wire highlight
        // (uuid + a 75-char book key + a locator JSON + text + two timestamps) does not fit in the
        // ~210 bytes that budget would need. So the fixture is grown to just under the BYTE cap and
        // the row count it reaches is measured and logged, rather than asserted to a number the
        // bounds forbid.
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

    // ---- helpers ---------------------------------------------------------------------------------

    private data class Snap(
        val highlights: List<HighlightRecord>,
        val notes: List<NoteRecord>,
        val bookmarks: List<BookmarkRecord>,
    ) {
        val total: Int get() = highlights.size + notes.size + bookmarks.size
    }

    /**
     * Epoch millis as the backup wire can carry them.
     *
     * `BackupJson` serialises `Instant`s as ISO-8601 UTC at SECOND precision, for byte parity with
     * Swift's `Codable` encoder — so milliseconds are lost by construction on any path through the
     * `annotations.json` contract, including the WebDAV restore this feature reuses. Not a defect of
     * the import path and not something WI-7 may "fix": changing it would change a versioned
     * cross-platform format.
     */
    private fun secondPrecision(epochMillis: Long): Long = epochMillis / 1000L * 1000L

    /** The first run of [length] consecutive CJK ideographs in [text], or null. */
    private fun firstIdeographRun(text: String, length: Int): String? {
        var run = 0
        for (i in text.indices) {
            run = if (text[i].code in 0x4E00..0x9FFF) run + 1 else 0
            if (run == length) return text.substring(i - length + 1, i + 1)
        }
        return null
    }

    private fun HighlightRecord.atWirePrecision() =
        copy(createdAt = secondPrecision(createdAt), updatedAt = secondPrecision(updatedAt))

    private fun NoteRecord.atWirePrecision() =
        copy(createdAt = secondPrecision(createdAt), updatedAt = secondPrecision(updatedAt))

    private fun BookmarkRecord.atWirePrecision() =
        copy(createdAt = secondPrecision(createdAt), updatedAt = secondPrecision(updatedAt))

    private fun snapshot(bookKey: String): Snap = runBlocking {
        Snap(
            highlights = repo.highlightsForBook(bookKey),
            notes = repo.notes(bookKey).first(),
            bookmarks = repo.bookmarks(bookKey).first(),
        )
    }

    private fun wipeAnnotations(bookKey: String) = runBlocking {
        snapshot(bookKey).let { s ->
            s.highlights.forEach { repo.removeHighlight(it.id) }
            s.notes.forEach { repo.removeNote(it.id) }
            s.bookmarks.forEach { repo.removeBookmark(it.id) }
        }
    }

    private fun epubLocator(book: Book, href: String, progression: Double) = Locator(
        contentSHA256 = book.contentSHA256,
        fileByteCount = book.fileByteCount,
        format = book.originalFormat.name,
        href = href,
        progression = progression,
        totalProgression = progression,
    )

    private fun txtLocator(book: Book, charOffset: Int, start: Int, end: Int) = Locator(
        contentSHA256 = book.contentSHA256,
        fileByteCount = book.fileByteCount,
        format = book.originalFormat.name,
        charOffsetUTF16 = charOffset,
        charRangeStartUTF16 = start,
        charRangeEndUTF16 = end,
    )

    /** Seed a mixed set — three colours, a note-bearing highlight, two notes, two bookmarks — and
     *  return the ONE highlight that carries an engine anchor (the K-5 probe). */
    private fun seedEpubAnnotations(book: Book): HighlightRecord = runBlocking {
        val key = book.fingerprintKey
        val anchored = repo.addHighlight(
            key, AnnotationColor.yellow, "it is a truth universally acknowledged",
            epubLocator(book, "chapter1.xhtml", 0.10),
            AnnotationAnchor.Text("text-document:$key", 100, 138), note = null,
        )
        repo.addHighlight(
            key, AnnotationColor.green, "a single man in possession of a good fortune",
            epubLocator(book, "chapter1.xhtml", 0.22), null, note = "the famous opening",
        )
        repo.addHighlight(
            key, AnnotationColor.pink, "must be in want of a wife",
            epubLocator(book, "chapter2.xhtml", 0.05), null, note = null,
        )
        repo.addNote(key, "a standalone note", epubLocator(book, "chapter2.xhtml", 0.40))
        repo.addNote(key, "a second note at another place", epubLocator(book, "chapter3.xhtml", 0.60))
        repo.addBookmark(key, title = null, locator = epubLocator(book, "chapter1.xhtml", 0.0))
        repo.addBookmark(key, title = "where I stopped", locator = epubLocator(book, "chapter3.xhtml", 0.9))
        anchored
    }

    /**
     * Export through the SHIPPED writer and expose the bytes as a REAL `content://` document via the
     * app's own FileProvider — so the import side exercises a genuine provider (a cursor that answers
     * DISPLAY_NAME and SIZE, and a provider-owned stream), not a `file://` shortcut.
     */
    private fun exportToProviderFile(bookKey: String, name: String): Uri {
        val json = runBlocking { app.container.annotationsExportWriter.exportJson(bookKey) }
        return writeProviderFile(name, json)
    }

    private fun writeProviderFile(name: String, json: String): Uri {
        val booksDir = File(instrumentation.targetContext.filesDir, "books").apply { mkdirs() }
        val file = File(booksDir, name)
        file.writeText(json)
        stagedFiles += file
        return FileProvider.getUriForFile(
            instrumentation.targetContext,
            "${instrumentation.targetContext.packageName}.fileprovider",
            file,
        )
    }

    private fun exportedText(name: String): String =
        File(File(instrumentation.targetContext.filesDir, "books"), name).readText()

    /** Grow a valid single-book annotations file until it is just under the reader's BYTE cap. */
    private fun writeLargestImportableFile(book: Book, name: String): Pair<Uri, Int> {
        val key = book.fingerprintKey
        var rows = 0
        var json = ""
        // Binary-search-free but bounded: add rows in blocks, re-encoding after each block, and stop
        // at the last block that still fits. The reader's cap is measured over the BYTES it reads.
        val block = 250
        val rowsList = mutableListOf<HighlightRecord>()
        while (rows + block <= AnnotationsImportReader.MAX_IMPORT_ROWS) {
            val candidate = rowsList + (rows until rows + block).map { i ->
                HighlightRecord(
                    id = java.util.UUID.nameUUIDFromBytes("wi7-$i".toByteArray()).toString(),
                    bookKey = key,
                    color = AnnotationColor.yellow,
                    selectedText = "row $i",
                    note = null,
                    locator = epubLocator(book, "c.xhtml", i / 100_000.0),
                    anchor = null,
                    createdAt = 1_700_000_000_000L + i,
                    updatedAt = 1_700_000_000_000L + i,
                )
            }
            val candidateJson = com.vreader.app.backup.AnnotationBackupMapper.json(
                highlights = candidate, notes = emptyList(), bookmarks = emptyList(),
            )
            if (candidateJson.toByteArray().size >= AnnotationsImportReader.MAX_IMPORT_JSON_BYTES) break
            rowsList.clear()
            rowsList += candidate
            rows += block
            json = candidateJson
        }
        assertNotEquals("the generated fixture must not be empty", 0, rows)
        return writeProviderFile(name, json) to rows
    }

    /**
     * Drive the WHOLE production import: Library -> reader -> `...` More -> Details -> Import
     * annotations… -> the (intercepted) system picker answers [uri] -> the designed preview sheet ->
     * the user taps `Import N items`.
     */
    private inline fun <reified T : android.app.Activity> importThroughProductionPath(
        book: Book,
        extraName: String,
        uri: Uri,
        expectedImportable: Int,
    ) {
        val monitor = AnnotationImportPickerMonitor.install(uri)
        try {
            openThroughLibrary<T>(compose, book.title, book.fingerprintKey, extraName) {
                tapImportRowThroughMoreMenu(compose)
                compose.waitUntil(UI_TIMEOUT_MS) { monitor.launchCount > 0 }
                compose.waitUntil(UI_TIMEOUT_MS) { nodeCount(compose, "annot-import-sheet-content") > 0 }
                // The designed primary names the number the user is approving; it must be the number
                // the merge then inserts (section 6.4's preview == apply invariant, at the surface).
                compose.onNodeWithText("Import $expectedImportable items", useUnmergedTree = true).assertExists()
                compose.onNodeWithTag("annot-import-confirm", useUnmergedTree = true).performClick()
                // The sheet dismisses on success; the observable result is the merged list itself.
                compose.waitUntil(UI_TIMEOUT_MS) { nodeCount(compose, "annot-import-sheet-content") == 0 }
                compose.waitUntil(UI_TIMEOUT_MS) {
                    runBlocking { app.container.annotationsRepository.highlightsForBook(book.fingerprintKey) }
                        .isNotEmpty()
                }
            }
        } finally {
            monitor.remove()
        }
    }

    private companion object {
        const val TAG = "WI165-ROUNDTRIP"
    }
}
