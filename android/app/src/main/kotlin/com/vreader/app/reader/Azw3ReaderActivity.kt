// Purpose: the AZW3/MOBI/KF8 (Kindle) reader screen. Hosts an Android WebView running the
// security-patched foliate-js bundle (via Azw3Document + FoliateBridge) in the committed shared
// reader chrome — design `vreader-fidelity-v1/project/vreader-reader.jsx` (the SAME chrome subset
// TxtReaderActivity / PdfReaderActivity implement; per feature #106 the iOS-authored fidelity bundle
// is a valid Android design source — rule 51). Persists the reading position (conflated, latest-wins)
// + flushes on onStop, and recreates the WebView on render-process death.
// Feature #126 WI-4 + WI-6. Routing from MainActivity; AZW3 import already exists.
//
// feature #132 WI-7-hosts: the Ready state now renders the shared ReaderChromeScaffold via
// Azw3ReaderChrome (top bar + Notes review sheet) over the WebView body. AZW3 has no reader TOC →
// Contents is hidden (empty tocEntries / EmptyTocProvider posture); it has no Display control (the #129
// CSS is applied live from the store with no control surface), so the bottom chrome is Notes-only.
// onJumpToAnnotation is NULL (review-only capability gate — no in-session goTo until #135; FoliateBridge/
// Azw3Document/foliate-js stay UNTOUCHED, and the MATCH_PARENT WebView sizing (bug #357) is undisturbed).
package com.vreader.app.reader

import android.os.Bundle
import android.webkit.WebView
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBackIos
import androidx.compose.material.icons.outlined.BorderColor
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.vreader.app.VReaderApp
import com.vreader.app.annotations.AnnotationsSnapshot
import com.vreader.app.annotations.BookmarkRecord
import com.vreader.app.data.Book
import com.vreader.app.reader.chrome.ReaderChromeScaffold
import com.vreader.app.reader.chrome.ReaderChromeState
import com.vreader.app.reader.chrome.ReaderChromeStateSaver
import com.vreader.app.reader.foliate.Azw3DocState
import com.vreader.app.reader.foliate.Azw3Document
import com.vreader.app.reader.foliate.Azw3GoToResult
import com.vreader.app.reader.foliate.Azw3LocatorBridge
import com.vreader.app.reader.foliate.FoliateMessage
import com.vreader.app.reader.nav.BookmarkRowItem
import com.vreader.app.reader.nav.BookmarkTocIndex
import com.vreader.app.reader.nav.JumpResult
import com.vreader.app.reader.settings.ReaderTheme
import com.vreader.app.ui.theme.VReaderFonts
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.launch
import vreader.contracts.BookFormat
import vreader.contracts.Locator
import vreader.contracts.VReaderLocator
import java.io.File

class Azw3ReaderActivity : ComponentActivity() {

    private val container get() = (application as VReaderApp).container

    // Hoisted so onStop can flush the latest position synchronously (mirrors PdfReaderActivity).
    private var currentBook: Book? = null
    private var latestRelocate: FoliateMessage.Relocate? = null
    private val saveRequests = Channel<VReaderLocator>(Channel.CONFLATED) // latest-wins, lone writer

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val key = intent.getStringExtra(EXTRA_FINGERPRINT_KEY)
        if (key == null) { finish(); return }

        // The lone position writer — drains in order on the process scope so an onStop save survives
        // this Activity's teardown.
        container.appScope.launch {
            for (locator in saveRequests) container.repository.savePosition(locator, System.currentTimeMillis())
        }

        setContent {
            val outer by produceState<OuterState>(OuterState.Loading, key) { value = loadOuter(key) }
            when (val o = outer) {
                OuterState.Loading -> ReaderScaffold("", ::finish) { Centered { CircularProgressIndicator() } }
                OuterState.NoBook -> ReaderScaffold("", ::finish) { Centered { Text("This book can’t be opened.", color = Ink) } }
                is OuterState.Ready -> {
                    currentBook = o.book
                    // feature #132 WI-7-hosts — the shared reader chrome. State persists across rotation /
                    // process death via ReaderChromeStateSaver (keyed on the book).
                    val bookKey = o.book.fingerprintKey
                    val chromeState = rememberSaveable(bookKey, stateSaver = ReaderChromeStateSaver) {
                        mutableStateOf(ReaderChromeState())
                    }
                    val displayTheme by container.readerSettingsStore.settings
                        .collectAsStateWithLifecycle(initialValue = com.vreader.app.reader.settings.ReaderSettings())
                    // The Notes review sheet's one-shot snapshot of this book's highlights + notes.
                    val annotationsSnapshot by produceState(
                        AnnotationsSnapshot(emptyList(), emptyList()), bookKey,
                    ) {
                        value = runCatching { container.annotationsRepository.annotationsForBook(bookKey) }
                            .getOrDefault(AnnotationsSnapshot(emptyList(), emptyList()))
                    }
                    // feature #134 WI-5 — the More menu's Book-details model (mapped from the book + its
                    // live collection names). AZW3 supplies no page count (pageCount=null).
                    val collectionNames by container.collectionRepository
                        .observeCollectionNamesForBook(bookKey)
                        .collectAsStateWithLifecycle(initialValue = emptyList())
                    val bookDetails = remember(o.book, collectionNames) {
                        com.vreader.app.reader.details.BookDetailsMapper.map(o.book, collectionNames, pageCount = null)
                    }

                    // feature #135 WI-7 — the bookmark wiring. AZW3 has no reader TOC, so the row projection
                    // has no chapter/page (the WI-4 EPUB/AZW3 branch degrades to null fields — no crash) — a
                    // null tocIndex. The current position comes from the relocate-derived canonical Locator;
                    // the jump uses Azw3Document.goTo (CFI-first→fraction, render-death carry-across).
                    val bookmarkRecords by container.annotationsRepository.bookmarks(bookKey)
                        .collectAsStateWithLifecycle(initialValue = emptyList())
                    val dateRenderer = remember { bookmarkDateRenderer() }
                    val bookmarkRows = remember(bookmarkRecords) {
                        bookmarkRowItems(bookmarkRecords, BookFormat.azw3, tocIndex = null, previewProvider = null, dateRenderer = dateRenderer)
                    }
                    // The live position + the document to jump into, hoisted from the body so the chrome-level
                    // toggle/jump can reach them. currentCanonical is null until foliate's first relocate.
                    var currentCanonical by remember { mutableStateOf<Locator?>(null) }
                    var liveDocument by remember { mutableStateOf<Azw3Document?>(null) }
                    // Presence — refreshed on every relocate AND right after a toggle.
                    val isBookmarked by produceState(false, currentCanonical, bookmarkRecords) {
                        val c = currentCanonical
                        value = c != null && runCatching { container.annotationsRepository.isBookmarked(bookKey, c) }.getOrDefault(false)
                    }
                    val jumpScope = rememberCoroutineScope()

                    Azw3ReaderChrome(
                        theme = displayTheme.theme,
                        title = o.book.title,
                        chromeState = chromeState,
                        annotations = annotationsSnapshot,
                        onBack = ::finish,
                        onShareAnnotations = { shareAnnotations(annotationsSnapshot) },
                        bookDetails = bookDetails,
                        onShareBook = { com.vreader.app.reader.share.shareBook(this@Azw3ReaderActivity, o.book) },
                        onCopyFingerprint = { copyFingerprint(it) },
                        // feature #135 WI-7 — the top-bar bookmark toggle + Bookmarks-tab rows + AZW3 jump.
                        isCurrentBookmarked = isBookmarked,
                        onToggleBookmark = if (currentCanonical != null) {
                            {
                                val c = currentCanonical
                                if (c != null) container.appScope.launch {
                                    runCatching { container.annotationsRepository.toggleBookmark(bookKey, title = null, locator = c) }
                                }
                            }
                        } else null,
                        currentLocator = currentCanonical,
                        bookmarks = bookmarkRows,
                        onJumpBookmark = { record ->
                            val doc = liveDocument
                            // Decide the sheet's dismiss SYNCHRONOUSLY from target validity: an unjumpable
                            // bookmark (no cfi + no finite progression) → Failed (sheet stays open, no
                            // invented error surface — rule 51); a jumpable one → Succeeded (dismiss). The
                            // ACTUAL landing is the awaited Azw3Document.goTo (CFI-first→fraction) launched
                            // off the jump scope — it blocks ~3s on the bundle relocate ack, so it CANNOT run
                            // on the tap thread (that would ANR). render-death mid-jump is carried across by
                            // the host's recreate path (takePendingGoTo → run(pendingGoTo=)); goTo re-lands once.
                            val decision = azw3JumpDecision(doc, record.locator)
                            if (decision == JumpResult.Succeeded && doc != null) {
                                jumpScope.launch {
                                    // The awaited landing (mapped for symmetry with the plan's Succeeded/
                                    // Timeout/Failed contract); a landed jump relocates → presence refreshes.
                                    val landed = runCatching { doc.goTo(record.locator) }
                                        .getOrDefault(Azw3GoToResult.Failed)
                                    if (azw3JumpResult(landed) == JumpResult.Succeeded && currentCanonical != null) {
                                        currentCanonical = record.locator // reflect the reached position promptly
                                    }
                                }
                            }
                            decision
                        },
                        body = {
                            Azw3ReaderHost(
                                book = o.book,
                                bookFile = File(o.path),
                                restore = o.restore,
                                settings = container.readerSettingsStore.settings,
                                onRelocate = { rel ->
                                    enqueueSave(o.book, rel)
                                    currentCanonical = Azw3LocatorBridge
                                        .toEnvelope(rel, o.book.contentSHA256, o.book.fileByteCount)
                                        .legacyLocator?.copy(format = BookFormat.azw3.name)?.validatedOrNull()
                                },
                                onDocument = { doc -> liveDocument = doc },
                            )
                        },
                    )
                }
            }
        }
    }

    private suspend fun loadOuter(key: String): OuterState {
        val book = container.repository.findBook(key) ?: return OuterState.NoBook
        val path = book.localFilePath ?: return OuterState.NoBook
        if (!File(path).isFile) return OuterState.NoBook
        container.repository.markOpened(key, System.currentTimeMillis())
        return OuterState.Ready(book, path, container.repository.loadPosition(key))
    }

    private fun enqueueSave(book: Book, relocate: FoliateMessage.Relocate) {
        currentBook = book
        latestRelocate = relocate
        saveRequests.trySend(Azw3LocatorBridge.toEnvelope(relocate, book.contentSHA256, book.fileByteCount))
    }

    override fun onStop() {
        super.onStop()
        val book = currentBook
        val relocate = latestRelocate
        if (book != null && relocate != null) {
            saveRequests.trySend(Azw3LocatorBridge.toEnvelope(relocate, book.contentSHA256, book.fileByteCount))
        }
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

    private sealed interface OuterState {
        data object Loading : OuterState
        data object NoBook : OuterState
        data class Ready(val book: Book, val path: String, val restore: VReaderLocator?) : OuterState
    }

    companion object {
        const val EXTRA_FINGERPRINT_KEY = "fingerprintKey"
        fun intent(context: android.content.Context, fingerprintKey: String): android.content.Intent =
            android.content.Intent(context, Azw3ReaderActivity::class.java).putExtra(EXTRA_FINGERPRINT_KEY, fingerprintKey)
    }
}

// ---- feature #135 WI-7 — AZW3 pure host wiring helpers ----

/**
 * feature #135 WI-7 — map an awaited [Azw3GoToResult] (the settled outcome of [Azw3Document.goTo]) to the
 * sheet's [JumpResult]. [Azw3GoToResult.Succeeded] landed → [JumpResult.Succeeded]; Timeout / Failed
 * (unresolvable target or dead bundle) / Superseded (a newer jump replaced this one) are all NON-landings
 * → [JumpResult.Failed] (no invented error surface — rule 51). Pure/JVM-testable. Used to surface the
 * awaited landing outcome off the background jump (the SYNCHRONOUS sheet-dismiss decision is
 * [azw3JumpDecision], since the awaited goTo cannot run on the tap thread).
 */
fun azw3JumpResult(result: Azw3GoToResult): JumpResult = when (result) {
    is Azw3GoToResult.Succeeded -> JumpResult.Succeeded
    Azw3GoToResult.Timeout, Azw3GoToResult.Failed, Azw3GoToResult.Superseded -> JumpResult.Failed
}

/**
 * feature #135 WI-7 — the SYNCHRONOUS dismiss decision for an AZW3 bookmark jump. Because the actual
 * [Azw3Document.goTo] is awaited (~3s on the bundle relocate ack — it cannot run on the tap thread), the
 * sheet decides dismiss-vs-stay up front from target validity: a null document (nothing loaded) OR a
 * canonical with no jumpable target (no cfi + no finite progression, per [FoliateGoToTarget.from]) →
 * [JumpResult.Failed] (the sheet stays open — rule 51); an otherwise-jumpable target → [JumpResult.Succeeded]
 * (dismiss; the awaited goTo then lands the position off-thread, re-issued once on render death).
 * Pure/JVM-testable ([document] is only null-checked).
 */
fun azw3JumpDecision(document: Azw3Document?, canonical: Locator): JumpResult {
    if (document == null) return JumpResult.Failed
    return if (com.vreader.app.reader.foliate.FoliateGoToTarget.from(canonical) != null) {
        JumpResult.Succeeded
    } else {
        JumpResult.Failed
    }
}

private val Ink = Color(0xFF1D1A14)
private val ChromeFill = Color(0xFFF7F4EE)
private val Accent = Color(0xFF8C2F2F)

/** The reader BODY: the WebView fills it; a state overlay covers it until Loaded (feature #132 WI-7-hosts
 *  moved the top bar into the shared [Azw3ReaderChrome], so this composable no longer wraps its own
 *  ReaderScaffold — it renders directly into the scaffold's body slot). The MATCH_PARENT WebView sizing
 *  (bug #357) + the page-turn tap zones + FoliateBridge/Azw3Document wiring are UNCHANGED. */
@Composable
private fun Azw3ReaderHost(
    book: Book,
    bookFile: File,
    restore: VReaderLocator?,
    settings: kotlinx.coroutines.flow.Flow<com.vreader.app.reader.settings.ReaderSettings>,
    onRelocate: (FoliateMessage.Relocate) -> Unit,
    // feature #135 WI-7 — hoist the CURRENT document up so the chrome-level bookmark jump can reach it. Fired
    // with the fresh document on each (re)create (render-death recovery swaps the WebView + document), and
    // with null on dispose — so the chrome always jumps into the live document, never a dead one.
    onDocument: (Azw3Document?) -> Unit = {},
) {
    val context = LocalContext.current
    var reloadKey by remember { mutableIntStateOf(0) }
    // Latest known position, for render-death resume (starts at the persisted restore point).
    var resume by remember { mutableStateOf(restore) }
    // feature #129 WI-6 — the live "Display" settings; applied as foliate CSS on every change AND on a
    // fresh render (the document re-applies pendingStylesCss at book-ready, incl. after render-death).
    val displaySettings by settings.collectAsStateWithLifecycle(initialValue = com.vreader.app.reader.settings.ReaderSettings())

    // A fresh WebView + document each reloadKey (render-process-death recovery). The WebView needs
    // MATCH_PARENT layout params — a default WRAP_CONTENT WebView measures its content height (0 before
    // content fills) → a 0-height viewport → foliate paginates to 1 page → next() no-ops (bug #357).
    val holder = remember(reloadKey) {
        val wv = WebView(context).apply {
            layoutParams = android.view.ViewGroup.LayoutParams(
                android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                android.view.ViewGroup.LayoutParams.MATCH_PARENT,
            )
        }
        Holder(wv, bookFile, context)
    }
    val state by holder.document.state.collectAsState()
    // feature #135 WI-7 — a bookmark goTo pending across a render-death recreate. On render death the host
    // reads it OFF the dying document (takePendingGoTo) BEFORE the reloadKey bump destroys it, then seeds it
    // into the replacement via run(pendingGoTo=) so an in-flight jump re-lands exactly once (WI-2's seam).
    var carriedGoTo by remember { mutableStateOf<Locator?>(null) }

    DisposableEffect(holder) {
        val doc = holder.document
        onDocument(doc)   // hoist the live document up for the chrome-level bookmark jump
        doc.onRelocate = { rel ->
            onRelocate(rel)
            resume = Azw3LocatorBridge.toEnvelope(rel, book.contentSHA256, book.fileByteCount)
        }
        doc.onRenderProcessGone = {
            // Carry any in-flight bookmark jump across the recreate (read + clear it off the dying document),
            // then recreate — the fresh document re-issues it once after book-ready (WI-2 render-death path).
            carriedGoTo = doc.takePendingGoTo()
            reloadKey++
        }
        onDispose { onDocument(null); doc.destroy() }
    }

    // Holder-scoped: the collector lives exactly as long as this holder (cancelled on reload/dispose). Seed
    // any carried bookmark goTo so a render death mid-jump re-lands the position once on the replacement.
    LaunchedEffect(holder) { holder.document.run(resume, pendingGoTo = carriedGoTo) }

    // feature #129 WI-6 — apply the Display CSS to the current document. Re-keyed on `holder` so a fresh
    // render (reload / render-death recovery) re-records the CSS, and on `displaySettings` so a live
    // settings change re-injects. `setStyles` is a no-op-until-book-ready record inside the document, so
    // an early apply is safe; the document re-applies at book-ready.
    LaunchedEffect(holder, displaySettings) { holder.document.setStyles(displaySettings.foliateDisplayCss()) }

    // The body renders directly into the shared scaffold's body slot (no own top bar). The WebView keeps
    // its MATCH_PARENT sizing (bug #357) — the scaffold's body Box fills the space between the chrome bars.
    Box(Modifier.fillMaxSize().testTag("azw3-webview")) {
        // Keyed on reloadKey so render-death recovery swaps in the NEW WebView node (not the dead one).
        key(reloadKey) { AndroidView(factory = { holder.webView }, modifier = Modifier.fillMaxSize()) }
        // Host-driven page-turn tap zones (design vreader-tap-zones.jsx: left third = prev, right third
        // = next, centre reserved). foliate is paginated, so the host drives next/prev like iOS — there
        // is no scroll gesture to preserve. Contract: WebView-native interactions (link/footnote taps,
        // and text selection once the Foliate annotation adapter lands — deferred from the AZW3 MVP)
        // are reachable in the CENTRE third; the side thirds are page-turn only. The zones use
        // detectTapGestures (confirmed tap only) so a stray move isn't read as a turn. A tap on the centre
        // (reserved) third is not consumed here → it bubbles to the scaffold's center-tap chrome toggle.
        if (state is Azw3DocState.Loaded) {
            Row(Modifier.fillMaxSize()) {
                TapZone(Modifier.weight(1f).testTag("azw3-prev-zone"), holder) { it.prev() }
                Box(Modifier.weight(1f).fillMaxHeight()) // centre — reserved
                TapZone(Modifier.weight(1f).testTag("azw3-next-zone"), holder) { it.next() }
            }
        }
        when (state) {
            Azw3DocState.Loading -> Centered { CircularProgressIndicator() }
            Azw3DocState.WebViewUnsupported -> Centered { Text("Update Android System WebView to read this format.", color = Ink) }
            Azw3DocState.Corrupt -> Centered { Text("This book can’t be opened.", color = Ink) }
            Azw3DocState.Empty -> Centered { Text("This book has no readable content.", color = Ink) }
            is Azw3DocState.Loaded -> Unit // the WebView shows the book
        }
    }
}

/**
 * The AZW3 reader host chrome — feature #132 WI-7-hosts (mirror of WI-6's [TxtReaderChrome]). Renders the
 * shared [ReaderChromeScaffold] (top bar + the Notes review sheet) over the AZW3 [body] (the WebView). AZW3
 * has no reader TOC → `tocEntries` is EMPTY (the EmptyTocProvider posture) → the scaffold hides the Contents
 * control. It has no Display control (the #129 CSS applies live from the store with no control surface); the
 * bottom chrome is a Notes-only toolbar ([Azw3NotesBottomChrome]). The top bar's Search/More/bookmark slots
 * are omitted (null — #133/#134/#135; no dead controls). [onJumpToAnnotation] is NULL — AZW3 review is
 * review-only (no in-session goTo until #135; the card is non-clickable, a capability gate — FoliateBridge/
 * Azw3Document/foliate-js stay untouched). Wrapped in a `systemBarsPadding()` Column so the chrome clears
 * the status/nav bars. Extracted (internal) so the host wiring is directly testable.
 */
@Composable
internal fun Azw3ReaderChrome(
    theme: ReaderTheme,
    title: String,
    chromeState: MutableState<ReaderChromeState>,
    annotations: AnnotationsSnapshot,
    onBack: () -> Unit,
    onShareAnnotations: () -> Unit,
    body: @Composable () -> Unit,
    // feature #134 WI-5 — the More menu's Book-details model + Share/copy actions (null model → no More).
    bookDetails: com.vreader.app.reader.details.BookDetailsUiModel? = null,
    onShareBook: () -> Unit = {},
    onCopyFingerprint: (String) -> Unit = {},
    // feature #135 WI-7 — the top-bar bookmark toggle + Bookmarks-tab rows + AZW3 jump (all nullable/default
    // so #132/#134 callers stay valid). A non-null onToggleBookmark fills the toggle; onJumpBookmark makes
    // the Bookmarks-tab rows clickable + dismiss-on-Succeeded (null → review-only rows).
    isCurrentBookmarked: Boolean = false,
    onToggleBookmark: (() -> Unit)? = null,
    currentLocator: Locator? = null,
    bookmarks: List<BookmarkRowItem> = emptyList(),
    onJumpBookmark: ((BookmarkRecord) -> JumpResult)? = null,
) {
    Column(Modifier.fillMaxSize().background(theme.background).systemBarsPadding()) {
        ReaderChromeScaffold(
            theme = theme,
            title = title,
            chromeState = chromeState,
            onBack = onBack,
            tocEntries = emptyList(),           // no TOC → the scaffold hides the Contents control
            currentTocIndex = 0,
            annotations = annotations,
            onJumpToc = { false },              // unreachable: Contents is hidden with an empty TOC
            // AZW3 tap-to-jump is NULL — review-only capability gate (no goTo until #135); cards non-clickable.
            onJumpToAnnotation = null,
            onShareAnnotations = onShareAnnotations,
            // Search top-bar slot stays null (#133 — no dead control). feature #134 WI-5:
            // the More button + Book Details / Share are wired through the scaffold's More menu below.
            bottomChrome = { _, onOpenNotes ->
                // AZW3 has no Contents (empty TOC) + no Display control → Notes only.
                Azw3NotesBottomChrome(theme = theme, onOpenNotes = onOpenNotes)
            },
            body = body,
            bookDetails = bookDetails,
            onShareBook = onShareBook,
            onCopyFingerprint = onCopyFingerprint,
            // feature #135 WI-7 — the bookmark toggle + Bookmarks tab, now lit up for AZW3.
            isCurrentBookmarked = isCurrentBookmarked,
            onToggleBookmark = onToggleBookmark,
            currentLocator = currentLocator,
            bookmarks = bookmarks,
            onJumpBookmark = onJumpBookmark,
        )
    }
}

/**
 * The AZW3 host's bottom chrome — the designed reader-toolbar "Notes" button only (feature #132 WI-7-hosts).
 * AZW3 has no reader TOC (Contents hidden) and no Display control surface (#129 applies CSS live from the
 * store), so of the design's Contents · Notes · Display · AI toolbar only the Notes slot applies. Uses the
 * same designed icon-above-label treatment as ReaderBottomChrome's Notes slot (the Highlighter/BorderColor
 * glyph, `chrome-notes` testTag). Rendered ONLY when [onOpenNotes] is non-null (always so for #132).
 */
@Composable
private fun Azw3NotesBottomChrome(theme: ReaderTheme, onOpenNotes: (() -> Unit)?) {
    if (onOpenNotes == null) return
    val ink = theme.ink
    val sub = theme.ink.copy(alpha = 0.6f)
    val rule = theme.ink.copy(alpha = 0.10f)
    Column(
        Modifier.fillMaxWidth().background(theme.background).testTag("azw3-bottom-chrome"),
    ) {
        Box(Modifier.fillMaxWidth().heightIn(min = 0.5.dp, max = 0.5.dp).background(rule))
        Row(
            Modifier.fillMaxWidth().padding(top = 14.dp, bottom = 28.dp),
            horizontalArrangement = Arrangement.Center,
        ) {
            Column(
                Modifier
                    .clip(RoundedCornerShape(14.dp))
                    .clickable(onClick = onOpenNotes)
                    .padding(horizontal = 12.dp, vertical = 4.dp)
                    .testTag("chrome-notes")
                    .semantics { contentDescription = "Notes" },
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(3.dp),
            ) {
                Icon(Icons.Outlined.BorderColor, contentDescription = null, tint = ink, modifier = Modifier.size(22.dp))
                Text("Notes", color = sub, fontSize = 10.sp, fontWeight = FontWeight.Medium)
            }
        }
    }
}


/** Bundles the per-session WebView + document so `remember(reloadKey)` recreates both together. */
private class Holder(val webView: WebView, bookFile: File, context: android.content.Context) {
    val document = Azw3Document(webView, bookFile, context)
}

@Composable
private fun ReaderScaffold(title: String, onBack: () -> Unit, body: @Composable () -> Unit) {
    Column(Modifier.fillMaxSize().background(Color.White).systemBarsPadding()) {
        Row(
            Modifier.fillMaxWidth().background(ChromeFill).padding(horizontal = 4.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Row(
                Modifier.heightIn(min = 48.dp).clip(RoundedCornerShape(8.dp)).clickable(onClickLabel = "Library", onClick = onBack).padding(horizontal = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.AutoMirrored.Filled.ArrowBackIos, contentDescription = null, tint = Accent, modifier = Modifier.size(18.dp))
                Text("Library", color = Accent, fontSize = 14.sp, fontWeight = FontWeight.Medium)
            }
            Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(title, color = Ink, fontFamily = VReaderFonts.Serif, fontSize = 13.5.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                    Text(" AZW3", color = Color(0xFF7A6A4A), fontSize = 9.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(start = 6.dp))
                }
            }
            Box(Modifier.size(60.dp))
        }
        Box(Modifier.weight(1f)) { body() }
    }
}

/** A transparent page-turn tap region. Re-keyed on [holder] so it always drives the current document. */
@Composable
private fun TapZone(modifier: Modifier, holder: Holder, onTap: (Azw3Document) -> Unit) {
    Box(modifier.fillMaxHeight().pointerInput(holder) { detectTapGestures { onTap(holder.document) } })
}

@Composable
private fun Centered(content: @Composable () -> Unit) =
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { content() }
