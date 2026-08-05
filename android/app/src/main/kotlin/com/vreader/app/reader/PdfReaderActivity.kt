// Purpose: feature #115 WI-2 / WI-3 (#110 Phase 3) — the PDF reader HOST Activity. Opens the book's
// PDF via PdfDocument off the main thread → Loading / ProtectedOrUnsupported / Corrupt / Empty /
// Loaded, gates composition on the store's first settings emission (WI-7), then hands off to the
// PdfReaderScreen composables (PdfScaffold + CenterMessage for the pre-Loaded states; PdfReaderChrome
// wrapping PdfReaderBody for Loaded — feature #132 WI-7-hosts). The PdfDocument is closed in a
// DisposableEffect; the page index is saved (debounced + onStop flush) via a conflated,
// single-consumer channel (WI-3 resume).
//
// feature #129 WI-7: PDF is rasterized (can't reflow), so it inherits ONLY the theme background from
// the global ReaderSettingsStore — no font/size/spacing, and NO Display sheet / NO Aa slot (a
// theme-only reduced sheet would be undesigned — rule 51). The host collects the store's settings
// live (GATED — nothing painted until the first emission, so a stored dark theme never flashes a
// bright frame) and threads `ReaderSettings.pdfBackdrop()` (= theme.background) to the viewer backdrop.
//
// feature #132 WI-7-hosts: the Loaded state now renders the shared ReaderChromeScaffold via
// PdfReaderChrome (top bar + Notes review sheet; Contents hidden — no PDF TOC; NO Display control — the
// #129 theme-only affordance is preserved as a live backdrop with no control surface). onJumpToAnnotation
// is NON-null: it scrolls the page list to the annotation's page (pdfAnnotationPage, clamped). The chrome
// state is persisted across rotation via ReaderChromeStateSaver; the Notes snapshot is a one-shot read
// of this book's annotationsForBook (empty pre-Loaded states keep the bare PdfScaffold messages).
//
// @coordinates-with: PdfReaderScreen.kt (the Compose surface it hosts + PdfReaderChrome), PdfDisplayBackdrop.kt
//   (the settings→backdrop mapping), ReaderSettingsStore (the live settings source), AnnotationsRepository
//   (the review-sheet snapshot), ReaderChromeScaffold/ReaderChromeState (the shared chrome).
package com.vreader.app.reader

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toArgb
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.vreader.app.VReaderApp
import com.vreader.app.annotations.AnnotationsSnapshot
import com.vreader.app.data.Book
import com.vreader.app.reader.chrome.ReaderChromeState
import com.vreader.app.reader.chrome.ReaderChromeStateSaver
import com.vreader.app.reader.chrome.ReaderSheet
import com.vreader.app.reader.nav.JumpResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import vreader.contracts.Locator
import java.io.File

private sealed interface PdfUiState {
    data object Loading : PdfUiState
    data object Protected : PdfUiState
    data object Corrupt : PdfUiState
    data object Empty : PdfUiState
    data class Loaded(val title: String, val document: PdfDocument, val book: Book, val initialPage: Int) : PdfUiState
}

class PdfReaderActivity : ComponentActivity() {

    private val container get() = (application as VReaderApp).container

    // feature #165 WI-7 — the annotation import/export SAF boundary for THIS activity: this activity's
    // ContentResolver behind the app-wide BoundedCallGate (never a fresh gate — one abandoned-call
    // ledger, plan section 8.5).
    private val annotationsIo by lazy { container.annotationsIoController(contentResolver) }

    // Hoisted so onStop can flush the latest page synchronously (mirrors TxtReaderActivity).
    private var flushPosition: (() -> Unit)? = null

    // feature #129 WI-7 test hook — the ARGB last applied to the viewer backdrop (null until the
    // store's first emission). Mirrors ReaderActivity.appliedBackgroundArgb(): the connected smoke
    // asserts the theme background reached the host, not that pixels painted (WI-8 covers pixels).
    @Volatile private var appliedBackdropArgb: Int? = null
    fun appliedBackdropArgb(): Int? = appliedBackdropArgb

    // ALL position writes funnel through this CONFLATED channel + a SINGLE consumer so saves are
    // serialized (latest-wins) — the debounced save + the onStop flush never land out of order.
    private val saveRequests = Channel<PendingSave>(Channel.CONFLATED)
    private data class PendingSave(val book: Book, val page: Int)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val key = intent.getStringExtra(EXTRA_FINGERPRINT_KEY)
        if (key == null) { finish(); return }

        // The lone writer — drains in order; runs on the process scope so an onStop save
        // completes through teardown; ends when onDestroy closes the channel.
        container.appScope.launch {
            for ((book, page) in saveRequests) {
                val locator = Locator(
                    contentSHA256 = book.contentSHA256,
                    fileByteCount = book.fileByteCount,
                    format = book.originalFormat.name,
                    page = page,
                )
                container.repository.savePosition(
                    vreader.contracts.VReaderLocator.wrapLegacy(locator),
                    System.currentTimeMillis(),
                )
            }
        }

        setContent {
            val state by produceState<PdfUiState>(PdfUiState.Loading, key) {
                value = withContext(Dispatchers.IO) { load(key) }
            }
            // feature #129 WI-7 — the live Display settings; PDF reads ONLY the theme background. NULL
            // until the DataStore's first emission — the composition is GATED on it (like the reflowable
            // readers) so a user with a stored dark theme never sees a wrong bright frame on open/rotation.
            val settingsOrNull by container.readerSettingsStore.settings.collectAsStateWithLifecycle(initialValue = null)
            val settings = settingsOrNull
            if (settings == null) {
                // Pre-emission: nothing painted (an empty full-screen surface), the test hook stays null.
                Box(Modifier.fillMaxSize())
            } else {
                val backdrop = settings.pdfBackdrop()
                SideEffect { appliedBackdropArgb = backdrop.toArgb() }
                when (val s = state) {
                    is PdfUiState.Loading -> PdfScaffold("", ::finish, backdrop) { CenterMessage("Opening…") }
                    is PdfUiState.Protected -> PdfScaffold("", ::finish, backdrop) {
                        CenterMessage("This PDF is protected", "It's password-protected or uses a security scheme this reader can't open.")
                    }
                    is PdfUiState.Corrupt -> PdfScaffold("", ::finish, backdrop) {
                        CenterMessage("Couldn’t open this PDF", "The file appears to be damaged or uses a format the reader can’t decode.")
                    }
                    is PdfUiState.Empty -> PdfScaffold("", ::finish, backdrop) {
                        CenterMessage("This PDF has no pages", null)
                    }
                    is PdfUiState.Loaded -> {
                        val listState = rememberLazyListState(initialFirstVisibleItemIndex = s.initialPage)
                        // Close the renderer when the reader leaves composition — launched on the
                        // process scope (NOT runBlocking on main: close() awaits the doc mutex behind
                        // any in-flight render, which could ANR the teardown/rotation frame).
                        DisposableEffect(s.document) {
                            onDispose { container.appScope.launch { s.document.close() } }
                        }
                        SideEffect { flushPosition = { savePage(s.book, listState.firstVisibleItemIndex) } }
                        LaunchedEffect(listState) {
                            snapshotFlow { listState.firstVisibleItemIndex }
                                .drop(1).debounce(800).collect { savePage(s.book, it) }
                        }
                        // feature #132 WI-7-hosts — the shared reader chrome. State persists across
                        // rotation / process death via ReaderChromeStateSaver (keyed on the book).
                        val bookKey = s.book.fingerprintKey
                        val chromeState = rememberSaveable(bookKey, stateSaver = ReaderChromeStateSaver) {
                            mutableStateOf(ReaderChromeState())
                        }
                        // feature #165 WI-7 — the extra key that makes a merged annotations import show up
                        // in the one-shot snapshot without reopening the reader.
                        var annotationsRefresh by androidx.compose.runtime.remember(bookKey) {
                            mutableStateOf(0)
                        }
                        // The Notes review sheet's one-shot snapshot of this book's highlights + notes.
                        val annotationsSnapshot by produceState(
                            AnnotationsSnapshot(emptyList(), emptyList()), bookKey, annotationsRefresh,
                        ) {
                            value = runCatching { container.annotationsRepository.annotationsForBook(bookKey) }
                                .getOrDefault(AnnotationsSnapshot(emptyList(), emptyList()))
                        }
                        val jumpScope = rememberCoroutineScope()
                        // feature #134 WI-5 — the More menu's Book-details model (mapped from the book + its
                        // live collection names + the real PDF page count → the Pages row).
                        val collectionNames by container.collectionRepository
                            .observeCollectionNamesForBook(bookKey)
                            .collectAsStateWithLifecycle(initialValue = emptyList())
                        val bookDetails = androidx.compose.runtime.remember(s.book, collectionNames, s.document.pageCount) {
                            com.vreader.app.reader.details.BookDetailsMapper.map(s.book, collectionNames, pageCount = s.document.pageCount)
                        }

                        // feature #135 WI-7 — the bookmark wiring. PDF has no TOC or preview (null tocIndex +
                        // null provider → the WI-4 projection shows just "p. N"). The current position is the
                        // top-visible page → a plain canonical Locator; the jump scrolls to the page.
                        val dateRenderer = androidx.compose.runtime.remember { bookmarkDateRenderer() }
                        val bookmarkRecords by androidx.compose.runtime.remember(bookKey) {
                            container.annotationsRepository.bookmarks(bookKey)
                        }.collectAsStateWithLifecycle(emptyList())
                        val bookmarkRows = androidx.compose.runtime.remember(bookmarkRecords, s.book) {
                            bookmarkRowItems(bookmarkRecords, s.book.originalFormat, tocIndex = null, previewProvider = null, dateRenderer = dateRenderer)
                        }
                        val livePage = listState.firstVisibleItemIndex
                        val liveCanonical = androidx.compose.runtime.remember(s.book, livePage) { pdfBookmarkLocator(s.book, livePage) }
                        val isBookmarked by produceState(false, liveCanonical, bookmarkRecords) {
                            value = runCatching { container.annotationsRepository.isBookmarked(bookKey, liveCanonical) }.getOrDefault(false)
                        }

                        // feature #165 WI-7 — the production annotation-import entry (SAF launcher +
                        // designed preview sheet); the Details sheet closes before the picker opens.
                        val importEntry = rememberAnnotationImportEntry(
                            controller = annotationsIo,
                            bookKey = bookKey,
                            bookTitle = s.book.title,
                            // The MERGE must survive this reader being finished/rotated (Gate-4
                            // round 1, High) — the applier rethrows CancellationException, so a
                            // composition-scoped apply would roll the transaction back silently.
                            applyScope = container.appScope,
                            onLaunching = { chromeState.value = chromeState.value.copy(sheet = ReaderSheet.None) },
                            onApplied = { annotationsRefresh++ },
                        )

                        PdfReaderChrome(
                            theme = settings.theme,
                            title = s.title,
                            chromeState = chromeState,
                            annotations = annotationsSnapshot,
                            onBack = ::finish,
                            // PDF tap-to-jump: scroll the page list to the annotation's clamped page —
                            // the existing resume/save page-scroll seam (listState.firstVisibleItemIndex).
                            onJumpToAnnotation = { item ->
                                jumpScope.launch { listState.scrollToItem(pdfAnnotationPage(item, s.document.pageCount)) }
                            },
                            onShareAnnotations = { shareAnnotations(annotationsSnapshot) },
                            body = { PdfReaderBody(s.document, listState, backdrop) },
                            bookDetails = bookDetails,
                            onShareBook = { com.vreader.app.reader.share.shareBook(this@PdfReaderActivity, s.book) },
                            onCopyFingerprint = { copyFingerprint(it) },
                            // feature #165 WI-7 — the designed Import row's launcher + the post-pick sheet.
                            onImportAnnotations = importEntry.launch,
                            importSheet = importEntry.sheetSlot(settings.theme),
                            // feature #135 WI-7 — the top-bar bookmark toggle + Bookmarks-tab rows + PDF jump.
                            isCurrentBookmarked = isBookmarked,
                            onToggleBookmark = {
                                container.appScope.launch {
                                    runCatching { container.annotationsRepository.toggleBookmark(bookKey, title = null, locator = liveCanonical) }
                                }
                            },
                            currentLocator = liveCanonical,
                            bookmarks = bookmarkRows,
                            // PDF jump: scroll to the bookmark's page; out-of-range → Failed (sheet stays open).
                            onJumpBookmark = { record ->
                                val target = pdfBookmarkPageTarget(record.locator.page, s.document.pageCount)
                                if (target == null) {
                                    JumpResult.Failed
                                } else {
                                    jumpScope.launch { listState.scrollToItem(target) }
                                    JumpResult.Succeeded
                                }
                            },
                        )
                    }
                }
            }
        }
    }

    override fun onStop() {
        super.onStop()
        flushPosition?.invoke()
    }

    override fun onDestroy() {
        super.onDestroy()
        saveRequests.close()
    }

    /** feature #134 WI-5 — copy the FULL canonical fingerprint to the OS clipboard (the Book Details
     *  copy-fingerprint mini-action). Rely on the OS copy confirmation — no invented toast (rule 51). */
    private fun copyFingerprint(fingerprintFull: String) {
        val clip = getSystemService(android.content.Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
        clip.setPrimaryClip(android.content.ClipData.newPlainText("fingerprint", fingerprintFull))
    }

    /** feature #132 WI-7-hosts — share ALL reviewed annotations as one plain-text blob (the review sheet's
     *  trailing Share → ACTION_SEND). Reuses the shared [annotationsShareText] formatter; no-op when empty. */
    private fun shareAnnotations(snapshot: AnnotationsSnapshot) {
        val text = annotationsShareText(snapshot)
        if (text.isBlank()) return
        val send = android.content.Intent(android.content.Intent.ACTION_SEND).apply {
            type = "text/plain"; putExtra(android.content.Intent.EXTRA_TEXT, text)
        }
        startActivity(android.content.Intent.createChooser(send, null))
    }

    private suspend fun load(key: String): PdfUiState {
        val book = container.repository.findBook(key) ?: return PdfUiState.Corrupt
        val path = book.localFilePath ?: return PdfUiState.Corrupt
        return when (val r = PdfDocument.open(File(path))) {
            is PdfOpenResult.Ok -> {
                container.repository.markOpened(key, System.currentTimeMillis())
                if (r.document.pageCount == 0) {
                    r.document.close(); PdfUiState.Empty
                } else PdfUiState.Loaded(book.title, r.document, book, computeInitialPage(key, r.document.pageCount))
            }
            PdfOpenResult.ProtectedOrUnsupported -> PdfUiState.Protected
            PdfOpenResult.Corrupt -> PdfUiState.Corrupt
        }
    }

    /** Restore the saved page index, clamped to a valid page (cache-first for fast reopen). */
    private suspend fun computeInitialPage(key: String, pageCount: Int): Int {
        val cached = container.cachedPage(key)
        val page = cached ?: run {
            val saved = container.repository.loadPosition(key) ?: return 0
            (ResumeResolver.resolve(saved) as? ResumeTarget.Canonical)?.locator?.page ?: 0
        }
        return page.coerceIn(0, (pageCount - 1).coerceAtLeast(0))
    }

    /** Cache synchronously (fast reopen) + enqueue the durable save (latest-wins). */
    private fun savePage(book: Book, page: Int) {
        container.cachePage(book.fingerprintKey, page)
        saveRequests.trySend(PendingSave(book, page))
    }

    companion object {
        const val EXTRA_FINGERPRINT_KEY = "fingerprintKey"
        fun intent(context: android.content.Context, fingerprintKey: String): android.content.Intent =
            android.content.Intent(context, PdfReaderActivity::class.java)
                .putExtra(EXTRA_FINGERPRINT_KEY, fingerprintKey)
    }
}
