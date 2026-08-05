package com.vreader.app.annotations

import android.net.Uri
import androidx.compose.ui.test.junit4.ComposeTestRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.core.content.FileProvider
import com.vreader.app.annotations.AnnotationImportProductionPath.UI_TIMEOUT_MS
import com.vreader.app.annotations.AnnotationImportProductionPath.app
import com.vreader.app.annotations.AnnotationImportProductionPath.instrumentation
import com.vreader.app.annotations.AnnotationImportProductionPath.nodeCount
import com.vreader.app.annotations.AnnotationImportProductionPath.openThroughLibrary
import com.vreader.app.annotations.AnnotationImportProductionPath.tapImportRowThroughMoreMenu
import com.vreader.app.backup.AnnotationBackupMapper
import com.vreader.app.data.Book
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import vreader.contracts.Locator
import java.io.File
import java.util.UUID

/**
 * Feature #165 WI-7 — the seeding, export, provider-document and navigation helpers
 * [AnnotationsRoundTripConnectedTest] drives. Split out so the test class stays about the
 * ASSERTIONS (the repo's ~300-line file bar; Gate-4 round 1, Low).
 */
object AnnotationsRoundTripFixtures {

    private val repo get() = app.container.annotationsRepository

    /** Files written into `filesDir/books` for the FileProvider; deleted by the test's `@After`. */
    val stagedFiles = mutableListOf<File>()

    data class Snap(
        val highlights: List<HighlightRecord>,
        val notes: List<NoteRecord>,
        val bookmarks: List<BookmarkRecord>,
    ) {
        val total: Int get() = highlights.size + notes.size + bookmarks.size
    }

    fun snapshot(bookKey: String): Snap = runBlocking {
        Snap(
            highlights = repo.highlightsForBook(bookKey),
            notes = repo.notes(bookKey).first(),
            bookmarks = repo.bookmarks(bookKey).first(),
        )
    }

    fun wipeAnnotations(bookKey: String) = runBlocking {
        snapshot(bookKey).let { s ->
            s.highlights.forEach { repo.removeHighlight(it.id) }
            s.notes.forEach { repo.removeNote(it.id) }
            s.bookmarks.forEach { repo.removeBookmark(it.id) }
        }
    }

    // ---- wire precision -------------------------------------------------------------------------

    /**
     * Epoch millis as the backup wire can carry them.
     *
     * `BackupJson` serialises `Instant`s as ISO-8601 UTC at SECOND precision, for byte parity with
     * Swift's `Codable` encoder — so milliseconds are lost by construction on any path through the
     * `annotations.json` contract, including the WebDAV restore this feature reuses. Not a defect of
     * the import path and not something WI-7 may "fix": changing it would change a versioned
     * cross-platform format. OBSERVED on the emulator, not assumed in advance.
     */
    fun secondPrecision(epochMillis: Long): Long = epochMillis / 1000L * 1000L

    fun HighlightRecord.atWirePrecision() =
        copy(createdAt = secondPrecision(createdAt), updatedAt = secondPrecision(updatedAt))

    fun NoteRecord.atWirePrecision() =
        copy(createdAt = secondPrecision(createdAt), updatedAt = secondPrecision(updatedAt))

    fun BookmarkRecord.atWirePrecision() =
        copy(createdAt = secondPrecision(createdAt), updatedAt = secondPrecision(updatedAt))

    // ---- seeding ---------------------------------------------------------------------------------

    fun epubLocator(book: Book, href: String, progression: Double) = Locator(
        contentSHA256 = book.contentSHA256,
        fileByteCount = book.fileByteCount,
        format = book.originalFormat.name,
        href = href,
        progression = progression,
        totalProgression = progression,
    )

    fun txtLocator(book: Book, charOffset: Int, start: Int, end: Int) = Locator(
        contentSHA256 = book.contentSHA256,
        fileByteCount = book.fileByteCount,
        format = book.originalFormat.name,
        charOffsetUTF16 = charOffset,
        charRangeStartUTF16 = start,
        charRangeEndUTF16 = end,
    )

    /**
     * Seed a mixed set — three colours, a note-bearing highlight, two standalone notes, two
     * bookmarks — and return the ONE highlight that carries an engine anchor (the K-5 probe).
     */
    fun seedEpubAnnotations(book: Book): HighlightRecord = runBlocking {
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

    /** The first run of [length] consecutive CJK ideographs in [text], or null. */
    fun firstIdeographRun(text: String, length: Int): String? {
        var run = 0
        for (i in text.indices) {
            run = if (text[i].code in 0x4E00..0x9FFF) run + 1 else 0
            if (run == length) return text.substring(i - length + 1, i + 1)
        }
        return null
    }

    // ---- export + the provider document ---------------------------------------------------------

    /**
     * Export through the SHIPPED writer and expose the bytes as a REAL `content://` document via the
     * app's own FileProvider — so the import side exercises a genuine provider (a cursor that answers
     * DISPLAY_NAME and SIZE, and a provider-owned stream), not a `file://` shortcut.
     */
    fun exportToProviderFile(bookKey: String, name: String): Uri {
        val json = runBlocking { app.container.annotationsExportWriter.exportJson(bookKey) }
        return writeProviderFile(name, json)
    }

    fun writeProviderFile(name: String, json: String): Uri {
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

    fun exportedText(name: String): String =
        File(File(instrumentation.targetContext.filesDir, "books"), name).readText()

    /**
     * Grow a valid single-book annotations file until it is just under the reader's BYTE cap, and
     * report how many rows that turned out to be.
     *
     * A-9 asks for a MAX-SIZE file. The plan's parenthetical "10 000-row file" is not reachable:
     * `MAX_IMPORT_ROWS` is 10 000 but `MAX_IMPORT_JSON_BYTES` is 2 MiB, and one wire highlight (a
     * uuid + a 75-character book key + a locator JSON + text + two timestamps) does not fit in the
     * ~210 bytes that budget would need. So the fixture is grown to the BYTE cap and the row count
     * it reaches is measured, rather than asserted to a number the bounds forbid.
     */
    fun writeLargestImportableFile(book: Book, name: String): Pair<Uri, Int> {
        val key = book.fingerprintKey
        var rows = 0
        var json = ""
        val block = 250
        val kept = mutableListOf<HighlightRecord>()
        while (rows + block <= AnnotationsImportReader.MAX_IMPORT_ROWS) {
            val candidate = kept + (rows until rows + block).map { i ->
                HighlightRecord(
                    id = UUID.nameUUIDFromBytes("wi7-$i".toByteArray()).toString(),
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
            val candidateJson = AnnotationBackupMapper.json(candidate, emptyList(), emptyList())
            if (candidateJson.toByteArray().size >= AnnotationsImportReader.MAX_IMPORT_JSON_BYTES) break
            kept.clear()
            kept += candidate
            rows += block
            json = candidateJson
        }
        assertNotEquals("the generated fixture must not be empty", 0, rows)
        return writeProviderFile(name, json) to rows
    }

    // ---- the production import, end to end -------------------------------------------------------

    /**
     * Drive the WHOLE production import: Library -> reader -> `...` More -> Details -> Import
     * annotations… -> the (intercepted) system picker answers [uri] -> the designed preview sheet ->
     * the user taps `Import N items`.
     *
     * [afterConfirm] runs with the reader still on screen, immediately after the confirm tap — the
     * mid-merge-teardown test uses it to finish the activity while the apply is in flight.
     */
    inline fun <reified T : android.app.Activity> importThroughProductionPath(
        compose: ComposeTestRule,
        book: Book,
        extraName: String,
        uri: Uri,
        expectedImportable: Int,
        crossinline afterConfirm: (T) -> Unit = {},
    ) {
        val monitor = AnnotationImportPickerMonitor.install(uri)
        try {
            openThroughLibrary<T>(compose, book.title, book.fingerprintKey, extraName) { reader ->
                tapImportRowThroughMoreMenu(compose)
                compose.waitUntil(UI_TIMEOUT_MS) { monitor.launchCount > 0 }
                compose.waitUntil(UI_TIMEOUT_MS) { nodeCount(compose, "annot-import-sheet-content") > 0 }
                // The designed primary names the number the user is approving; it must be the number
                // the merge then inserts (section 6.4's preview == apply invariant, at the surface).
                compose.onNodeWithText("Import $expectedImportable items", useUnmergedTree = true).assertExists()
                compose.onNodeWithTag("annot-import-confirm", useUnmergedTree = true).performClick()
                afterConfirm(reader)
            }
        } finally {
            monitor.remove()
        }
    }

    /** Poll the store until [predicate] holds, or fail with [message]. */
    fun awaitStore(bookKey: String, timeoutMs: Long, message: String, predicate: (Snap) -> Boolean) {
        val deadline = System.currentTimeMillis() + timeoutMs
        var last: Snap = snapshot(bookKey)
        while (System.currentTimeMillis() < deadline) {
            last = snapshot(bookKey)
            if (predicate(last)) return
            Thread.sleep(100)
        }
        assertEquals("$message (last seen: ${last.total} rows)", true, predicate(last))
    }
}
