// Purpose: the AZW3/MOBI/KF8 (Kindle) reader screen. Hosts an Android WebView running the
// security-patched foliate-js bundle (via Azw3Document + FoliateBridge) in the committed shared
// reader chrome — design `vreader-fidelity-v1/project/vreader-reader.jsx` (the SAME chrome subset
// TxtReaderActivity / PdfReaderActivity implement; per feature #106 the iOS-authored fidelity bundle
// is a valid Android design source — rule 51). Persists the reading position (conflated, latest-wins)
// + flushes on onStop, and recreates the WebView on render-process death.
// Feature #126 WI-4 + WI-6. Routing from MainActivity; AZW3 import already exists.
//
// feature #132 WI-7-hosts: the Ready state renders the shared ReaderChromeScaffold via Azw3ReaderChrome
// (top bar + the Contents|Bookmarks and Notes sheets) over the WebView body. AZW3 has no Display control
// (the #129 CSS is applied live from the store with no control surface), so the bottom chrome is the
// Contents · Notes subset of the designed toolbar. onJumpToAnnotation is NULL (review-only capability
// gate; FoliateBridge/Azw3Document/foliate-js stay UNTOUCHED, and the MATCH_PARENT WebView sizing
// (bug #357) is undisturbed).
//
// feature #140 WI-6: AZW3 now HAS a table of contents. The `book-ready` TOC tree — which the bundle has
// always posted and Kotlin used to discard — is hoisted out of Azw3ReaderHost (onToc, mirroring
// onRelocate/onDocument), flattened by FoliateTocProvider into `tocEntries`, and handed to the chrome
// together with `currentTocIndex` (foliateTocIndexFor over the live relocate.tocHref) and `onJumpToc`
// (the EXISTING #135 azw3JumpDecision + awaited goTo seam, reused unchanged). Nothing is persisted, and
// a book whose file carries no usable TOC yields an empty list — i.e. exactly the pre-#140 behaviour,
// Contents control hidden.
package com.vreader.app.reader

import android.os.Bundle
import android.webkit.WebView
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
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
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.vreader.app.VReaderApp
import com.vreader.app.annotations.AnnotationsSnapshot
import com.vreader.app.data.Book
import com.vreader.app.reader.chrome.ReaderChromeState
import com.vreader.app.reader.chrome.ReaderChromeStateSaver
import com.vreader.app.reader.foliate.Azw3DocState
import com.vreader.app.reader.foliate.Azw3Document
import com.vreader.app.reader.foliate.Azw3GoToResult
import com.vreader.app.reader.foliate.Azw3LocatorBridge
import com.vreader.app.reader.foliate.FoliateMessage
import com.vreader.app.reader.foliate.FoliateTocItem
import com.vreader.app.reader.nav.BookmarkTocIndex
import com.vreader.app.reader.nav.FoliateTocProvider
import com.vreader.app.reader.nav.JumpResult
import com.vreader.app.reader.nav.TocEntry
import com.vreader.app.reader.nav.foliateTocIndexFor
import com.vreader.app.ui.theme.VReaderFonts
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
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

                    // feature #135 WI-7 — the bookmark wiring. Bookmark ROWS still project no chapter/page
                    // label: the row projection needs a bookmark's position mapped onto a chapter, and this
                    // host's TOC is keyed by href while a bookmark anchors on a cfi/fraction, so there is no
                    // mapping to feed it — hence a null tocIndex (the WI-4 EPUB/AZW3 branch degrades to null
                    // fields, no crash) even though the READER now has a TOC (#140 WI-6, below). Projecting
                    // one would need an href↔position bridge, which is the tracked bookmark-from-TOC
                    // follow-up. The current position comes from the relocate-derived canonical Locator;
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

                    // feature #140 WI-6 — the table of contents. The tree arrives on `book-ready` and is
                    // hoisted out of the body host (onToc, mirroring onRelocate/onDocument); the provider
                    // flattens it on its OWN injected dispatcher (the host never wraps the call — rule 50
                    // §12.1). Nothing is persisted: the TOC is derived from a message already in flight.
                    var tocItems by remember(bookKey) { mutableStateOf<List<FoliateTocItem>>(emptyList()) }
                    // Empty until the flatten publishes → the scaffold hides Contents → the pre-publish
                    // frame is byte-identical to pre-#140. Entries are KEPT across a render-process death
                    // (onToc only ever fires with a loaded book's tree), so the control never blinks.
                    val tocEntriesState = remember(bookKey) { mutableStateOf(emptyList<TocEntry>()) }
                    LaunchedEffect(tocItems, o.book) {
                        if (tocItems.isEmpty()) return@LaunchedEffect
                        val provider = FoliateTocProvider(
                            items = tocItems, book = o.book, dispatcher = Dispatchers.Default,
                        )
                        // NOT runCatching (Gate-4 R1 Medium): it swallows CancellationException too, so a
                        // flatten cancelled by a book change or by this effect leaving composition would
                        // publish an EMPTY list — blinking the Contents control off, or clobbering the next
                        // book's rows. Cancellation must propagate; only a genuine failure degrades to "no
                        // TOC", which is the same hide-the-control signal a book without one produces.
                        val flattened = try {
                            provider.toc()
                        } catch (cancellation: CancellationException) {
                            throw cancellation
                        } catch (failure: Exception) {
                            emptyList()
                        }
                        tocEntriesState.value = flattened
                    }
                    val tocEntries = tocEntriesState.value
                    // The highlighted row: foliate's OWN current-chapter answer (relocate.tocHref), matched
                    // byte-exactly against the row hrefs. -1 only when there is no TOC at all.
                    val tocHrefs = remember(tocEntries) { tocEntries.map { it.canonicalLocator.href } }
                    var currentTocHref by remember(bookKey) { mutableStateOf<String?>(null) }
                    val currentTocIndex = foliateTocIndexFor(currentTocHref, tocHrefs)
                    // A tapped row reuses the EXISTING #135 jump seam verbatim: the synchronous
                    // [azw3TocJumpDecision] drives the sheet's dismiss from target validity, while the
                    // awaited goTo — which blocks on the bundle's ack and so CANNOT run on the tap thread —
                    // is ISSUED off the jump scope. Note what the decision does NOT claim: foliate's
                    // view.goTo swallows a failed resolution and acks anyway, so neither the decision nor
                    // the ack is evidence the reader moved (WI-7's real-book round-trip is). An
                    // out-of-range row, or the document-less window right after a render-process death,
                    // degrades to false → the sheet stays open, no invented error surface (rule 51).
                    val onJumpToc: (Int) -> Boolean = { index ->
                        val decision = azw3TocJumpDecision(liveDocument, tocEntries, index)
                        val doc = liveDocument
                        val entry = tocEntries.getOrNull(index)
                        if (decision == JumpResult.Succeeded && doc != null && entry != null) {
                            jumpScope.launch { runCatching { doc.goTo(entry.canonicalLocator) } }
                        }
                        decision == JumpResult.Succeeded
                    }

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
                        // feature #140 WI-6 — the book's real chapters + the live highlight + the row
                        // jump. An EMPTY list keeps the Contents control hidden (the scaffold's rule).
                        tocEntries = tocEntries,
                        currentTocIndex = currentTocIndex,
                        onJumpToc = onJumpToc,
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
                                    // feature #140 WI-6 — foliate's own current-chapter href, carried
                                    // verbatim (null = unknown chapter, never "no TOC").
                                    currentTocHref = rel.tocHref
                                },
                                onDocument = { doc -> liveDocument = doc },
                                // feature #140 WI-6 — the book's TOC tree, hoisted out of the body host.
                                onToc = { items -> tocItems = items },
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
    // feature #140 WI-6 — hoist the book's TOC tree up so the chrome can build its Contents rows. Fired
    // ONLY with a LOADED document's tree (never on Loading/Corrupt/Empty), so a render-process death
    // leaves the previously published entries standing rather than blinking the control off and on; the
    // replacement document re-opens the book and re-fires with a fresh tree.
    onToc: (List<FoliateTocItem>) -> Unit = {},
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

    // feature #140 WI-6 — publish the book's TOC once the document reports Loaded. Keyed on the state, so
    // it fires on the first load AND again after a render-death recreate re-opens the book.
    LaunchedEffect(state) {
        (state as? Azw3DocState.Loaded)?.let { onToc(it.toc) }
    }

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
