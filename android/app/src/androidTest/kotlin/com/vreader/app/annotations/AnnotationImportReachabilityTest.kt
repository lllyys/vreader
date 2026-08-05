package com.vreader.app.annotations

import android.content.Intent
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.annotations.AnnotationImportProductionPath.PDF_ASSET
import com.vreader.app.annotations.AnnotationImportProductionPath.REAL_AZW3_DISPLAY_NAME
import com.vreader.app.annotations.AnnotationImportProductionPath.REAL_AZW3_FILE
import com.vreader.app.annotations.AnnotationImportProductionPath.REAL_AZW3_SHA256
import com.vreader.app.annotations.AnnotationImportProductionPath.REAL_EPUB_DISPLAY_NAME
import com.vreader.app.annotations.AnnotationImportProductionPath.REAL_EPUB_FILE
import com.vreader.app.annotations.AnnotationImportProductionPath.REAL_EPUB_SHA256
import com.vreader.app.annotations.AnnotationImportProductionPath.REAL_TXT_DISPLAY_NAME
import com.vreader.app.annotations.AnnotationImportProductionPath.REAL_TXT_FILE
import com.vreader.app.annotations.AnnotationImportProductionPath.REAL_TXT_SHA256
import com.vreader.app.annotations.AnnotationImportProductionPath.importAsset
import com.vreader.app.annotations.AnnotationImportProductionPath.importReal
import com.vreader.app.annotations.AnnotationImportProductionPath.openThroughLibrary
import com.vreader.app.annotations.AnnotationImportProductionPath.requireRealFile
import com.vreader.app.annotations.AnnotationImportProductionPath.tapImportRowThroughMoreMenu
import com.vreader.app.data.Book
import com.vreader.app.reader.Azw3ReaderActivity
import com.vreader.app.reader.PdfReaderActivity
import com.vreader.app.reader.ReaderActivity
import com.vreader.app.reader.TxtReaderActivity
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.FixMethodOrder
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.MethodSorters

/**
 * Feature #165 WI-7 — **acceptance criterion A-10a: the Import row is reachable by a real user**, on
 * every one of the four reader hosts.
 *
 * WI-6 threaded `onImportAnnotations` through both chrome hosts and proved the row fires a callback,
 * but the four PRODUCTION call sites still passed nothing — so before this WI there was no path from
 * app launch to an annotations import. That is precisely the #114/#118/#120/#122 shape rule 47's
 * Gate-5 "production reachability" clause exists to stop, and it is why each test here starts at
 * [com.vreader.app.MainActivity] and walks the shipped UI:
 *
 * > Library -> tap the book -> the reader -> top-bar `...` More -> **Details** -> **Import annotations…**
 *
 * and then asserts the app really started a document picker
 * (`Intent.ACTION_OPEN_DOCUMENT`), captured off the app's own `startActivityForResult` by
 * [AnnotationImportPickerMonitor]. "The launcher was registered" is not "a user can import"; the
 * discriminating assertion is that the intent leaves the app after a tap on the designed row.
 *
 * The stub answers `RESULT_CANCELED`, because THIS class is about reachability only — the merge
 * itself, with locator-level assertions, is [AnnotationsRoundTripConnectedTest]. A cancelled pick is
 * also the silent path (no designed "you cancelled" state), so each test additionally asserts no
 * preview sheet appeared: a host that showed one would be inventing UI.
 *
 * **Fixtures — real books first, and the fallback is FAILURE, not a skip.** EPUB / TXT / AZW3 use the
 * real local books, digest-pinned; PDF uses the committed 3-page asset under the stated exception
 * (`test-books/books/` holds no PDF at all). Nothing here calls `assumeTrue` — an absent fixture must
 * go RED, not exit 0 like a pass (bug #369's shape). The connected task uninstalls the app at run
 * end, so re-push before EVERY run:
 *
 * ```
 * adb -s emulator-5554 shell mkdir -p /sdcard/Android/data/com.vreader.app/files
 * adb -s emulator-5554 push 'test-books/books/epub/The Half Second - Li Xiaolai.epub' \
 *     /sdcard/Android/data/com.vreader.app/files/wi7-real.epub
 * adb -s emulator-5554 push 'test-books/books/txt/黑暗血时代.txt' \
 *     /sdcard/Android/data/com.vreader.app/files/wi7-real.txt
 * adb -s emulator-5554 push 'test-books/books/azw3/Bei Tao Yan De Yong Qi - Zi Wo.azw3' \
 *     /sdcard/Android/data/com.vreader.app/files/wi7-real.azw3
 * ```
 *
 * Run ONE class per connected invocation (a comma-joined `class=A,B` fast-fails with `tests=0`), and
 * never drive the emulator while the run is in flight (rule 52 Cause D).
 *
 * **Build configuration — the same bounded deviation #139's acceptance recorded.** Gate 5 asks for a
 * release-configured build; this module declares no `buildTypes` block, so `release` is unsigned and
 * there is no instrumentable release variant — `connectedAndroidTest` runs `debug`. The gap is closed
 * on the other axis instead: every file on the path walked here (`MainActivity` -> `LibraryScreen` ->
 * the four reader activities -> `ReaderChromeScaffold` / `EpubReaderSheets` -> `BookDetailsSheet` ->
 * `AnnotationImportEntry`) lives in `src/main`, so nothing on it comes from a `src/debug` source set
 * the release APK would drop. That is honest supporting evidence, not an equivalent.
 */
@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class AnnotationImportReachabilityTest {

    @get:Rule val compose = createEmptyComposeRule()

    @After
    fun drainReaders() {
        AnnotationImportProductionPath.finishLiveReaders()
    }

    // ---- the four production hosts --------------------------------------------------------------

    @Test
    fun aEpubHost_libraryToReaderToDetails_launchesTheDocumentPicker() {
        val book = importReal(
            requireRealFile(REAL_EPUB_FILE, REAL_EPUB_SHA256, "test-books/books/epub/$REAL_EPUB_DISPLAY_NAME"),
            REAL_EPUB_DISPLAY_NAME, REAL_EPUB_SHA256,
        )
        assertPickerReachable<ReaderActivity>(book, ReaderActivity.EXTRA_FINGERPRINT_KEY)
    }

    @Test
    fun bTxtHost_libraryToReaderToDetails_launchesTheDocumentPicker() {
        val book = importReal(
            requireRealFile(REAL_TXT_FILE, REAL_TXT_SHA256, "test-books/books/txt/$REAL_TXT_DISPLAY_NAME"),
            REAL_TXT_DISPLAY_NAME, REAL_TXT_SHA256,
        )
        assertPickerReachable<TxtReaderActivity>(book, TxtReaderActivity.EXTRA_FINGERPRINT_KEY)
    }

    @Test
    fun cPdfHost_libraryToReaderToDetails_launchesTheDocumentPicker() {
        val book = importAsset(PDF_ASSET)
        assertPickerReachable<PdfReaderActivity>(book, PdfReaderActivity.EXTRA_FINGERPRINT_KEY)
    }

    @Test
    fun dAzw3Host_libraryToReaderToDetails_launchesTheDocumentPicker() {
        val book = importReal(
            requireRealFile(REAL_AZW3_FILE, REAL_AZW3_SHA256, "test-books/books/azw3/$REAL_AZW3_DISPLAY_NAME"),
            REAL_AZW3_DISPLAY_NAME, REAL_AZW3_SHA256,
        )
        assertPickerReachable<Azw3ReaderActivity>(book, Azw3ReaderActivity.EXTRA_FINGERPRINT_KEY)
    }

    // ---- the shared assertion --------------------------------------------------------------------

    private inline fun <reified T : android.app.Activity> assertPickerReachable(book: Book, extraName: String) {
        val monitor = AnnotationImportPickerMonitor.install(uri = null)
        try {
            openThroughLibrary<T>(compose, book.title, book.fingerprintKey, extraName) {
                tapImportRowThroughMoreMenu(compose)

                // THE criterion: the app started a document picker because the user tapped the
                // designed row. A registered-but-unwired launcher counts zero here.
                compose.waitUntil(AnnotationImportProductionPath.UI_TIMEOUT_MS) { monitor.launchCount > 0 }
                assertEquals(
                    "exactly one document picker launch per tap of the Import row",
                    1, monitor.launchCount,
                )
                val launched = requireNotNull(monitor.launchedIntent) { "no picker intent captured" }
                assertEquals(Intent.ACTION_OPEN_DOCUMENT, launched.action)
                // The MIME hint is `application/json` + the `* / *` fallback (plan R-7: providers
                // routinely mislabel a .json, and a strict filter would make it unpickable). It is a
                // HINT, never a gate — validation is by content (D-4).
                val mimes = launched.getStringArrayExtra(Intent.EXTRA_MIME_TYPES)?.toList().orEmpty()
                assertTrue(
                    "the picker must offer JSON without excluding mislabelled documents (was $mimes)",
                    mimes.contains("application/json") && mimes.contains("*/*"),
                )

                // A cancelled pick is SILENT — the design draws no "you cancelled" state, so a host
                // that raised the preview sheet here would be inventing one (rule 51).
                compose.waitForIdle()
                assertEquals(
                    "a cancelled pick must raise no sheet",
                    0, AnnotationImportProductionPath.nodeCount(compose, "annot-import-sheet-content"),
                )
            }
        } finally {
            monitor.remove()
        }
    }
}
