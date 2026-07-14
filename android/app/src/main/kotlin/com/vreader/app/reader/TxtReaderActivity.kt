// Purpose: plain-text + Markdown reader host — feature #111 (TXT) + #112 (MD), #110
// Phase 3. Renders a decoded .txt/.md in a Compose LazyColumn over the WI-1 TxtDocument
// chunk ranges, with the shared reader chrome (vreader-reader.jsx subset). For BookFormat.md
// each line-chunk renders through MarkdownRenderer (styled AnnotatedString); .txt renders
// the chunk verbatim. WI-3 adds resume via the LEGACY locator
// path (NOT the Readium bridge): save the top-visible chunk's charOffsetUTF16 as a
// VReaderLocator.wrapLegacy envelope (debounced + onStop flush) and restore it via
// ResumeResolver → Canonical → chunkForOffset.
//
// feature #129 WI-4: the reader collects ReaderSettingsStore.settings live and applies them —
// theme background/ink on the scaffold, bodyTextStyle (size/family/lineHeight/ink) + margin padding
// on the body — and hosts the designed ReaderBottomChrome (scrubber + Display slot + the read-aloud
// slot, replacing the pre-chrome TtsEntryBar) which opens the ReaderSettingsSheet.
//
// feature #132 WI-6: the FIRST host to render the shared ReaderChromeScaffold (ReaderTopChrome +
// the extended ReaderBottomChrome Contents/Notes/Display toolbar + the Notes review sheet). TXT/MD has
// no TOC → Contents is hidden (EmptyTocProvider / empty tocEntries). Notes opens the
// AnnotationsReviewSheet over this book's annotationsForBook snapshot; onJumpToAnnotation is non-null
// (TXT/MD jump via the plain Locator's charRangeStartUTF16/charOffsetUTF16 → the existing chunk scroll
// seam). The #129 Display sheet + the #121 TTS bar are preserved unchanged inside the scaffold's bottom
// slot. The More/bookmark top-bar slots are wired by #134/#135.
//
// feature #133 WI-10: the top-bar Search slot is now WIRED for TXT/MD — the host owns a per-session
// InBookSearchViewModel (built from the already-decoded reader text; ONE per reader open, disposed via
// onCleared on reader teardown) and mounts the InBookSearchSheet when the Search icon is tapped. A tapped
// hit's canonical charOffsetUTF16 resolves to a scroll via the EXISTING chunk-scroll seam
// (chunkForOffset), returning Succeeded (sheet dismisses) or Failed (out-of-range → sheet stays open). The
// icon is hidden only when the WI-7 index-state gate reports Unsupported (no dead control).
//
// feature #131 WI-8: bilingual interlinear, ADDITIVE + strictly TXT/MD-gated. A per-session
// BilingualViewModel (over the real TxtChapterTextProvider, WI-4b DI) drives position-based prefetch
// (onPositionChanged on the top-visible char offset) + the first-enable setup sheet. Each source chunk's
// lazy item wraps its byte-UNCHANGED source `Text` and the muted, NON-registered interlinear translation
// slot(s) anchored to that chunk (BilingualTxtAnchors) in ONE `Column` — the items(count=chunkCount,
// key={it}) loop + keys are UNCHANGED so lazy-index==chunk-index (position-save/every jump) is preserved
// (round-4 H2). The translation slots' window bounds are pushed to the selection controller so a
// long-press on translation is excluded from the nearest-source-chunk fallback (gesture exclusion). TTS
// auto-scroll visibility now keys off the registered SOURCE `Text` bounds (isSourceChunkInViewport), not
// the item index, since an in-item translation makes items taller than their source line (round-5/6).
package com.vreader.app.reader

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.VReaderApp
import com.vreader.app.data.Book
import com.vreader.app.ui.theme.VReaderColors
import com.vreader.app.ui.theme.VReaderFonts
import com.vreader.app.ui.theme.VReaderTheme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import vreader.contracts.BookFormat
import vreader.contracts.Locator
import java.io.File
import android.speech.tts.TextToSpeech
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.awaitLongPressOrCancellation
import androidx.compose.foundation.gestures.drag
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.offset
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntOffset
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.launch
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import androidx.compose.ui.text.TextStyle
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.saveable.rememberSaveable
import com.vreader.app.annotations.AnnotationItem
import com.vreader.app.annotations.AnnotationsSnapshot
import com.vreader.app.annotations.BookmarkRecord
import com.vreader.app.reader.chrome.ReaderBottomChrome
import com.vreader.app.reader.chrome.ReaderChromeScaffold
import com.vreader.app.reader.chrome.ReaderChromeState
import com.vreader.app.reader.chrome.ReaderChromeStateSaver
import com.vreader.app.reader.nav.BookmarkPreviewProvider
import com.vreader.app.reader.nav.BookmarkRowItem
import com.vreader.app.reader.nav.JumpResult
import com.vreader.app.reader.settings.ReaderSettings
import com.vreader.app.reader.settings.ReaderSettingsSheet
import com.vreader.app.search.InBookSearchSheet
import com.vreader.app.reader.settings.ReaderTheme
import com.vreader.app.reader.settings.bodyTextStyle
import com.vreader.app.tts.AndroidTtsEngine
import com.vreader.app.tts.TtsChunker
import com.vreader.app.tts.TtsControlBar
import com.vreader.app.tts.TtsHighlight
import com.vreader.app.tts.TtsIntent
import com.vreader.app.tts.TtsPhase
import com.vreader.app.tts.TtsSpeedSheet
import com.vreader.app.tts.TtsViewModel
import com.vreader.app.tts.TtsVoiceSheet
import com.vreader.app.stats.InReaderSessionPill
import kotlinx.coroutines.delay

private sealed interface TxtUiState {
    data object Loading : TxtUiState
    data object Failed : TxtUiState
    data class Loaded(
        val title: String,
        val document: TxtDocument,
        val book: Book,
        val initialIndex: Int,
        // feature #137 WI-6a — the resume anchor as a raw source-UTF-16 offset (the paged body restores
        // to pageContaining(initialOffset); the scroll body uses initialIndex = chunkForOffset(offset)).
        val initialOffset: Int,
    ) : TxtUiState
}

class TxtReaderActivity : ComponentActivity() {

    private val container get() = (application as VReaderApp).container

    // Hoisted out of composition so onStop can flush the latest position synchronously
    // (mirrors ReaderActivity's onStop flush). Set once the document is loaded.
    private var flushPosition: (() -> Unit)? = null

    // feature #124 WI-4 — the existing TXT highlight being edited (set on a tap; null = create context)
    // + the text to copy/share (the selection's, or the tapped highlight's).
    private var pendingTxtHighlightId: String? = null
    private var pendingTxtText: String? = null

    // ALL position writes funnel through this CONFLATED channel + a SINGLE consumer, so
    // saves are serialized (latest-wins) — the debounced save and the onStop flush can
    // never land out of order and regress the position (Gate-4 High).
    private val saveRequests = Channel<PendingSave>(Channel.CONFLATED)
    private data class PendingSave(val book: Book, val offsetUtf16: Int)

    // feature #131 WI-8 — the per-session bilingual VM (TXT/MD only; null for any non-TXT/MD open,
    // and until the composition builds it). Held so the @VisibleForTesting seams can drive
    // enable/disable + read state deterministically (the live More-menu entry is WI-9).
    private var bilingualViewModel: com.vreader.app.bilingual.BilingualViewModel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val key = intent.getStringExtra(EXTRA_FINGERPRINT_KEY)
        if (key == null) { finish(); return }

        // The lone writer — drains requests in order; CONFLATED keeps only the latest
        // pending one. Runs on the process scope so an onStop save completes through
        // teardown; ends when onDestroy closes the channel.
        container.appScope.launch {
            for ((book, offset) in saveRequests) {
                val locator = Locator(
                    contentSHA256 = book.contentSHA256,
                    fileByteCount = book.fileByteCount,
                    format = book.originalFormat.name,
                    charOffsetUTF16 = offset,
                )
                container.repository.savePosition(
                    vreader.contracts.VReaderLocator.wrapLegacy(locator),
                    System.currentTimeMillis(),
                )
            }
        }

        setContent {
            VReaderTheme {
                val state by produceState<TxtUiState>(TxtUiState.Loading, key) {
                    value = withContext(Dispatchers.IO) {
                        runCatching { load(key) }.getOrDefault(TxtUiState.Failed)
                    }
                }
                // feature #129 — the live Display settings (theme/font/size/spacing/margin). NULL until
                // the DataStore's first emission; the reader body is withheld until then (Gate-4 Medium:
                // rendering defaults first would flash the wrong theme/typography for a user with stored
                // non-default settings). The empty loading scaffold is the only pre-emission surface.
                val settingsOrNull by container.readerSettingsStore.settings
                    .collectAsStateWithLifecycle(initialValue = null)
                val gated = if (settingsOrNull == null && state !is TxtUiState.Failed) TxtUiState.Loading else state
                when (val s = gated) {
                    is TxtUiState.Failed -> LaunchedEffect(Unit) { finish() }
                    is TxtUiState.Loading -> TxtLoadingScaffold((settingsOrNull ?: ReaderSettings()).theme)
                    is TxtUiState.Loaded -> {
                        // non-null by the gate above (Loaded is unreachable pre-emission).
                        val displaySettings = checkNotNull(settingsOrNull)
                        val listState = rememberLazyListState(initialFirstVisibleItemIndex = s.initialIndex)

                        // feature #137 WI-6a — the paged renderer's per-open state: the WI-4 paginator +
                        // WI-5 navigator (offset↔page + reflow reconciliation) + a small page-render LRU.
                        // Held here (not inside TxtPagedBody) so the flush/restore seams + the connected
                        // test seams read them; a fresh set per document keeps re-opens independent.
                        val pagedPaginator = remember(s.document) { com.vreader.app.reader.paged.TxtPaginator() }
                        val pagedNavigator = remember(s.document) { com.vreader.app.reader.paged.TxtPageNavigator(pagedPaginator) }
                        val pagedRenderCache = remember(s.document) { PagedRenderCache() }
                        // The current page's START source offset — updated by the paged body's save callback
                        // so onStop can flush it. -1 = the paged body hasn't published a page yet.
                        val pagedOffset = remember(s.document) { mutableStateOf(-1) }
                        // Whether the paged body is the one mounted (layout == Paged && !bilingual). Read by
                        // the test seam + the flush branch so onStop saves the right position source.
                        val pagedBodyMounted = remember(s.document) { mutableStateOf(false) }
                        // An external programmatic page-jump request (the connected test's page turn; future
                        // bookmark/search jumps land here). The paged body observes it, scrolls, then clears
                        // it via onJumpConsumed. -1 / null-equivalent = nothing pending.
                        val pagedJumpRequest = remember(s.document) { mutableStateOf<Int?>(null) }
                        SideEffect {
                            testPagedNavigator = pagedNavigator
                            testPagedRenderCache = pagedRenderCache
                            testPagedOffset = pagedOffset
                            testPagedBodyMounted = pagedBodyMounted
                            testPagedJumpRequest = pagedJumpRequest
                            testPagedBook = s.book
                        }

                        // onStop flush — the PAGED body flushes its current page-start offset; the scroll
                        // body flushes the top-visible chunk's offset. One seam, two sources.
                        SideEffect {
                            flushPosition = {
                                if (pagedBodyMounted.value && pagedOffset.value >= 0) {
                                    savePositionOffset(s.book, pagedOffset.value)
                                } else {
                                    savePosition(s.book, s.document, listState.firstVisibleItemIndex)
                                }
                            }
                        }
                        // Debounced steady-state save as the user scrolls (SCROLL body only; the paged body
                        // saves on each settled page turn via its onSaveSourceOffset callback).
                        LaunchedEffect(listState, s.document) {
                            snapshotFlow { listState.firstVisibleItemIndex }
                                .drop(1)
                                .debounce(1_000)
                                .collect { savePosition(s.book, s.document, it) }
                        }
                        // feature #121 — read-aloud. The VM drives the designed control bar; the spoken
                        // sentence is washed + auto-scrolled (TXT). Chunking is LAZY + off-main (only
                        // on Read aloud) so a large book never scans the whole text on composition.
                        val ttsVm: TtsViewModel = viewModel(factory = viewModelFactory {
                            initializer { TtsViewModel(AndroidTtsEngine(applicationContext)) }
                        })
                        val tts by ttsVm.state.collectAsStateWithLifecycle()
                        val ttsScope = rememberCoroutineScope()
                        LaunchedEffect(ttsVm) { ttsVm.intents.collect { launchTtsIntent(it) } }
                        // pause read-aloud when the reader is backgrounded (no MediaSession by design —
                        // plan §OOS); the engine is shut down on Activity finish via the VM's onCleared.
                        val lifecycleOwner = LocalLifecycleOwner.current
                        DisposableEffect(lifecycleOwner) {
                            // guard against ON_STOP firing on a rotation (config change) — the VM is
                            // retained across rotation, so don't pause when we're just reconfiguring.
                            val obs = LifecycleEventObserver { _, e -> if (e == Lifecycle.Event.ON_STOP && !isChangingConfigurations) ttsVm.pause() }
                            lifecycleOwner.lifecycle.addObserver(obs)
                            onDispose { lifecycleOwner.lifecycle.removeObserver(obs) }
                        }
                        val active = tts.phase != TtsPhase.idle
                        val spokenChunk = if (tts.phase == TtsPhase.speaking) s.document.chunkForOffset(tts.charStart) else -1
                        // The TTS auto-scroll effect is installed BELOW, after selectionController is
                        // declared — feature #131 WI-8 keys visibility off the registered SOURCE `Text`
                        // bounds (an in-item translation child makes the item taller than its source line,
                        // so item-index visibility no longer proves the source is on-screen).
                        var showSpeed by remember { mutableStateOf(false) }
                        var showVoice by remember { mutableStateOf(false) }
                        var starting by remember { mutableStateOf(false) }   // guards double-tap → double-chunk
                        // snapshot the voice options once when the sheet opens (not every recomposition).
                        val voiceList = remember(showVoice) { if (showVoice) ttsVm.voiceListState() else com.vreader.app.tts.TtsVoiceListState() }

                        // feature #122 — reading-stats: track this session (the process-singleton tracker
                        // survives rotation) + show the auto-fading session pill.
                        val tracker = container.readingTimeTracker
                        val bookKey = s.book.fingerprintKey
                        val sessionSeconds by tracker.sessionSeconds.collectAsStateWithLifecycle()

                        // feature #124/#125 — stored highlights → per-chunk washes. Enabled for TXT AND MD
                        // (#125 added the MarkdownChunkTextMapper source-offset map, so MD is no longer
                        // render-only). The mapper is the single rendered↔source bridge + render owner,
                        // shared by the wash, the selection controller, and the body.
                        val annotatable = s.book.originalFormat == BookFormat.txt || s.book.originalFormat == BookFormat.md
                        val chunkMapper = remember(s.document, s.book.originalFormat) {
                            if (s.book.originalFormat == BookFormat.md) MarkdownChunkTextMapper(s.document)
                            else IdentityChunkTextMapper(s.document)
                        }
                        val highlightsList by remember(bookKey, annotatable) {
                            if (annotatable) container.annotationsRepository.highlights(bookKey) else flowOf(emptyList())
                        }.collectAsStateWithLifecycle(emptyList())
                        val washMap = remember(highlightsList, s.document, chunkMapper) { TxtWashMapper.washesByChunk(s.document, highlightsList, chunkMapper) }

                        // feature #124/#125 — custom selection + popover (TXT + MD).
                        val selectionController = remember(s.document, chunkMapper) { if (annotatable) TxtSelectionController(s.document, chunkMapper) else null }
                        // feature #131 WI-8 — expose the live controller + list state to the connected test
                        // seams (the TTS source-visibility query drives against real laid-out coordinates).
                        SideEffect { testSelectionController = selectionController; testListState = listState }
                        // feature #131 WI-8 — TTS auto-scroll: keep the spoken SOURCE on screen. Visibility
                        // keys off the registered source `Text` bounds (isSourceChunkInViewport), NOT the
                        // lazy-item index — an in-item translation child makes the item taller than its
                        // source line, so `visibleItemsInfo.index == spokenChunk` can be true while the
                        // SOURCE has scrolled above the viewport (only the translation is visible). A null
                        // controller (never for TXT/MD, which is always annotatable) or a not-yet-laid-out /
                        // detached source chunk counts as NOT visible → scroll (the safe default, round-6 Low).
                        // Recomputes on scroll — keyed on BOTH firstVisibleItemIndex AND
                        // firstVisibleItemScrollOffset (round-4 audit High-2): scrolling WITHIN a tall
                        // source+translation item changes the offset while the index stays put, and that is
                        // exactly the translation-only-visible case where the SOURCE has left the viewport.
                        LaunchedEffect(spokenChunk, listState.firstVisibleItemIndex, listState.firstVisibleItemScrollOffset) {
                            if (spokenChunk < 0) return@LaunchedEffect
                            val visible = selectionController?.isSourceChunkInViewport(spokenChunk)
                                ?: listState.layoutInfo.visibleItemsInfo.any { it.index == spokenChunk }
                            if (!visible) runCatching { listState.animateScrollToItem(spokenChunk) }
                        }
                        val popoverVm = remember(bookKey) { com.vreader.app.annotations.SelectionPopoverViewModel() }
                        val popoverState by popoverVm.state.collectAsStateWithLifecycle()
                        DisposableEffect(lifecycleOwner, bookKey) {
                            val obs = LifecycleEventObserver { _, e ->
                                when (e) {
                                    // start/stop on the PROCESS scope (not the composition-scoped ttsScope) so the
                                    // durable bank in stop()/flush() can't be cancelled by the reader's teardown.
                                    Lifecycle.Event.ON_RESUME -> container.appScope.launch { tracker.start(bookKey) }
                                    // don't end the session on a rotation (config change) — only a real background.
                                    // keyed stop: a no-op unless THIS book is the active session (stale-Activity safe).
                                    Lifecycle.Event.ON_STOP -> if (!isChangingConfigurations) container.appScope.launch { tracker.stop(bookKey) }
                                    else -> Unit
                                }
                            }
                            // addObserver replays lifecycle events up to the current state — so a Loaded
                            // composition that arrives AFTER ON_RESUME still receives ON_RESUME here and the
                            // initial open is tracked (no missed first session).
                            lifecycleOwner.lifecycle.addObserver(obs)
                            onDispose { lifecycleOwner.lifecycle.removeObserver(obs) }
                        }
                        // live pill + periodic bank — gated to RESUMED so neither loop wakes while backgrounded.
                        LaunchedEffect(Unit) { lifecycleOwner.repeatOnLifecycle(Lifecycle.State.RESUMED) { while (true) { delay(1_000); tracker.tickSessionSeconds() } } }
                        LaunchedEffect(Unit) { lifecycleOwner.repeatOnLifecycle(Lifecycle.State.RESUMED) { while (true) { delay(60_000); tracker.flush() } } }
                        var pillVisible by remember { mutableStateOf(true) }
                        LaunchedEffect(Unit) { delay(5_000); pillVisible = false }                             // auto-fade

                        // feature #129 WI-4 — the Display sheet, opened from the chrome's Aa slot.
                        var showDisplaySheet by remember { mutableStateOf(false) }

                        // feature #132 WI-6 — the shared reader-chrome state (top/bottom visibility + open
                        // sheet), persisted across rotation / process death via ReaderChromeStateSaver.
                        val chromeState = rememberSaveable(bookKey, stateSaver = ReaderChromeStateSaver) {
                            mutableStateOf(ReaderChromeState())
                        }
                        // The Notes review sheet's one-shot snapshot. Reloads whenever this book's stored
                        // highlights change (a fresh highlight/edit/remove OR a #124/#125 wash) so a newly
                        // added annotation appears in the sheet without reopening the reader.
                        val annotationsSnapshot by produceState(
                            AnnotationsSnapshot(emptyList(), emptyList()), bookKey, annotatable, highlightsList,
                        ) {
                            value = if (!annotatable) AnnotationsSnapshot(emptyList(), emptyList())
                            else runCatching { container.annotationsRepository.annotationsForBook(bookKey) }
                                .getOrDefault(AnnotationsSnapshot(emptyList(), emptyList()))
                        }

                        // feature #134 WI-5 — the More menu's Book-details model (mapped from the loaded
                        // book + its live collection names via BookDetailsMapper). TXT/MD supplies no page
                        // count (pageCount=null). Rebuilds when the book's collection membership changes.
                        val collectionNames by container.collectionRepository
                            .observeCollectionNamesForBook(bookKey)
                            .collectAsStateWithLifecycle(initialValue = emptyList())
                        val bookDetails = remember(s.book, collectionNames) {
                            com.vreader.app.reader.details.BookDetailsMapper.map(s.book, collectionNames, pageCount = null)
                        }

                        // feature #135 WI-7 — the bookmark wiring. TXT/MD has no TOC (null tocIndex → the WI-4
                        // projection degrades chapter/page to null) but DOES supply a preview provider (a bounded
                        // snippet around the stored char offset — the host owns the decoded text). The current
                        // position is the top-visible chunk's char offset → a plain canonical Locator.
                        val previewProvider = remember(s.document) { txtBookmarkPreviewProvider(s.document) }
                        val dateRenderer = remember { bookmarkDateRenderer() }
                        val currentCanonical = remember(s.book) {
                            { off: Int -> txtBookmarkLocator(s.book, off) }
                        }
                        val bookmarkRecords by remember(bookKey) { container.annotationsRepository.bookmarks(bookKey) }
                            .collectAsStateWithLifecycle(emptyList())
                        val bookmarkRows = remember(bookmarkRecords, s.book) {
                            bookmarkRowItems(bookmarkRecords, s.book.originalFormat, tocIndex = null, previewProvider = previewProvider, dateRenderer = dateRenderer)
                        }
                        // NOTE: the live bookmark offset (liveCanonical/isBookmarked) is derived below, AFTER
                        // usePaged is known, so the top-bar bookmark toggle/presence uses the PAGED current
                        // page-start offset in paged mode (not the hidden scroll list — Gate-4 R2 High).

                        // feature #133 WI-10 — the in-book search VM (ONE per reader session): built from the
                        // ALREADY-decoded reader text so a search never re-reads the file, scoped to a
                        // composition-lifetime scope so its collectors stop when the reader leaves. onDispose
                        // runs the VM's documented lifecycle (closeAllEpubCursors via onCleared) — TXT has no
                        // EPUB cursors, but the contract holds uniformly. Hidden only when the index-state gate
                        // reports Unsupported (a TXT/MD book skipped as unsupported); otherwise the Search icon
                        // is present.
                        val searchScope = rememberCoroutineScope()
                        val inBookSearchVm = remember(bookKey, s.book.originalFormat) {
                            container.inBookSearchViewModel(
                                bookKey = bookKey,
                                format = s.book.originalFormat,
                                decodedText = s.document.text,
                                contentSHA256 = s.book.contentSHA256,
                                fileByteCount = s.book.fileByteCount,
                                coroutineScope = searchScope,
                            )
                        }
                        DisposableEffect(inBookSearchVm) { onDispose { inBookSearchVm.onCleared() } }
                        val inBookSearchState by inBookSearchVm.state.collectAsStateWithLifecycle()
                        var showSearch by remember(bookKey) { mutableStateOf(false) }

                        // feature #131 WI-8 — the bilingual interlinear wiring, STRICTLY gated to TXT/MD
                        // (annotatable == txt || md). For any other format the VM is null and the whole
                        // bilingual path (render, position-driven prefetch, setup sheet, TTS-visibility
                        // change) is inert — the reader is byte-identical to #129/#132/#133/#134/#135.
                        val bilingualKind = when (s.book.originalFormat) {
                            BookFormat.txt -> com.vreader.app.bilingual.TranslationUnitId.Kind.txtDocSegmentWindow
                            BookFormat.md -> com.vreader.app.bilingual.TranslationUnitId.Kind.mdDocSegmentWindow
                            else -> null
                        }
                        // ONE VM per reader open, hosted in this Activity's ViewModelStore (via a one-shot
                        // factory) so Android clears it — and cancels its viewModelScope — on destroy; a
                        // fresh store key per book keeps re-opens independent. The provider is a LAZY
                        // decorator so the whole-document segmentation scan is deferred off the reader-open
                        // path until bilingual actually prefetches (round-4 audit High-3).
                        val bilingualVm: com.vreader.app.bilingual.BilingualViewModel? =
                            if (bilingualKind == null) null else viewModel(
                                key = "bilingual-$bookKey",
                                factory = viewModelFactory {
                                    initializer {
                                        container.bilingualViewModel(
                                            bookKey,
                                            LazyTxtChapterTextProvider(s.document, bilingualKind),
                                        )
                                    }
                                },
                            )
                        SideEffect { bilingualViewModel = bilingualVm }
                        val bilingualState by (bilingualVm?.state ?: flowOf(com.vreader.app.bilingual.BilingualUiState()))
                            .collectAsStateWithLifecycle(com.vreader.app.bilingual.BilingualUiState())
                        // feature #137 WI-6a — whether the PAGED body is the mounted one (layout == Paged AND
                        // bilingual OFF; the #131 interlinear contract has no paged analog → bilingual-on
                        // renders scroll; WI-10 formalizes the gate). Hoisted here (above the chrome) so the
                        // scroll-listState-driven chrome controls (TTS read-aloud, in-book search jump,
                        // scrubber, bookmark/annotation jump) are made INERT/ABSENT in paged mode — those all
                        // scroll the hidden LazyListState, which does nothing visible in paged mode and is a
                        // dead control (Gate-4 High-2). Their paged re-integration is WI-8/WI-9.
                        val usePaged = displaySettings.layout == com.vreader.app.reader.settings.ReaderLayout.Paged &&
                            !bilingualState.enabled

                        // The live bookmark position → canonical (the top-bar toggle/presence read it). Mode-
                        // aware (Gate-4 R2 High): in PAGED mode the current page's START offset (pagedOffset);
                        // in scroll mode the top-visible chunk's offset. So the bookmark toggle bookmarks the
                        // PAGE the user is on, and the bookmarked-state reflects it — never the hidden list.
                        val liveOffset = if (usePaged && pagedOffset.value >= 0) pagedOffset.value
                            else s.document.offsetForChunk(listState.firstVisibleItemIndex)
                        val liveCanonical = remember(s.book, liveOffset) { txtBookmarkLocator(s.book, liveOffset) }
                        val isBookmarked by produceState(false, liveCanonical, bookmarkRecords) {
                            value = runCatching { container.annotationsRepository.isBookmarked(bookKey, liveCanonical) }.getOrDefault(false)
                        }

                        // The source-chunk → translation-unit anchor map. Constructed cheaply per doc/kind;
                        // its whole-document scan is itself LAZY (runs on first unitsForChunk, only while
                        // enabled + rendering — round-4 audit High-3), so a disabled open pays nothing.
                        val bilingualAnchors = remember(s.document, bilingualKind) {
                            bilingualKind?.let { BilingualTxtAnchors(s.document, it) }
                        }
                        // Position-driven prefetch: feed the top-visible chunk's char offset to the VM.
                        // Keyed ALSO on the target language (round-4 audit High-1) so a language change while
                        // enabled re-submits the CURRENT position immediately (the VM invalidates its cache
                        // on a language change; without re-submitting, the visible unit would stay untranslated
                        // until the user scrolls). Only active when enabled (onPositionChanged is itself a
                        // no-op while disabled). The snapshotFlow's first emission IS the current position, so
                        // a re-key re-dispatches the current unit without waiting for a scroll.
                        LaunchedEffect(bilingualVm, s.document, bilingualState.enabled, bilingualState.targetLanguage.key) {
                            val vm = bilingualVm ?: return@LaunchedEffect
                            if (!bilingualState.enabled) return@LaunchedEffect
                            snapshotFlow { listState.firstVisibleItemIndex }
                                .map { s.document.offsetForChunk(it) }
                                .collect { vm.onPositionChanged(it) }
                        }
                        // feature #131 WI-9 — the bilingual setup sheet is shown when EITHER the VM's
                        // needsSetupSheet flag is raised (first was-off→on enable) OR the user re-opens it
                        // from the pill (an already-enabled book). One host-owned flag ORs the two so the
                        // sheet's dismiss path is uniform; a first-enable ALSO lowers the VM flag. The
                        // engine strip's "Set up"/"Change…" opens the Variant A AI Providers sheet.
                        var showBilingualSetup by remember(bookKey) { mutableStateOf(false) }
                        var showAiProviders by remember(bookKey) { mutableStateOf(false) }
                        val setupVisible = bilingualVm != null && (bilingualState.needsSetupSheet || showBilingualSetup)
                        if (setupVisible) {
                            com.vreader.app.bilingual.BilingualSetupSheet(
                                theme = displaySettings.theme,
                                selectedLanguage = bilingualState.targetLanguage,
                                aiConfigured = bilingualState.aiConfigured,
                                onSelectLanguage = { bilingualVm!!.setTargetLanguage(it.key) },
                                onSetUp = { showAiProviders = true },
                                onTurnOn = { bilingualVm!!.dismissSetupSheet(); showBilingualSetup = false },
                                onDismiss = { bilingualVm!!.dismissSetupSheet(); showBilingualSetup = false },
                            )
                        }
                        // feature #131 WI-9 — the Variant A AI Providers sheet, pushed inside the bilingual
                        // flow (WI-AIP). One AiSettingsViewModel per reader session; on a Save it activates
                        // the saved provider then pops back (the sheet's onDone), and refreshes the VM's
                        // aiConfigured so the engine strip flips to configured without reopening.
                        if (showAiProviders) {
                            val aiVm = remember(bookKey) { container.aiSettingsViewModel() }
                            // Wrap in a BackupSurface so the reused list/editor's LocalBackupTokens follow the
                            // active reader theme (Gate-4 Medium-1 — otherwise the sheet is always Light).
                            com.vreader.app.backup.BackupSurface(darkOverride = displaySettings.theme.isDark) {
                                com.vreader.app.bilingual.ReaderAiProvidersSheet(
                                    vm = aiVm,
                                    onDone = { showAiProviders = false; bilingualVm?.refreshAiConfigured() },
                                )
                            }
                        }

                        // feature #137 WI-6a — a MODE-AWARE offset jump: in PAGED mode a chrome jump
                        // (bookmark / annotation / search / scrubber) must move the PAGER (via the navigator's
                        // pageContaining + the paged body's jump seam), NOT the hidden scroll LazyListState —
                        // else the control is dead (Gate-4 High-2). In scroll mode it uses the existing chunk
                        // scroll seam. This is the ONLY chrome↔paged glue in WI-6a (uses just the navigator's
                        // existing pageContaining + jumpRequest — no feature re-integration; full paged
                        // bookmarks/find/TTS are WI-8/WI-9).
                        val jumpToOffset: (Int) -> Unit = { offset ->
                            if (usePaged) {
                                // Before the first page index publishes, pageContaining() returns 0 for ANY
                                // offset — so a jump during the sub-second paged-load window would collapse to
                                // page 0. Skip it while there is no index yet (the control is barely visible
                                // then); once the index exists the jump lands on the right page (Gate-4 R2 Low).
                                if (pagedNavigator.index != null) {
                                    val target = offset.coerceIn(0, (s.document.text.length - 1).coerceAtLeast(0))
                                    pagedJumpRequest.value = pagedNavigator.pageContaining(target)
                                }
                            } else {
                                ttsScope.launch { runCatching { listState.scrollToItem(s.document.chunkForOffset(offset)) } }
                            }
                        }

                        TxtReaderChrome(
                            theme = displaySettings.theme,
                            title = s.title,
                            chromeState = chromeState,
                            annotations = annotationsSnapshot,
                            onBack = ::finish,
                            bookDetails = bookDetails,
                            onShareBook = { com.vreader.app.reader.share.shareBook(this@TxtReaderActivity, s.book) },
                            onCopyFingerprint = { copyFingerprint(it) },
                            // feature #135 WI-7 — the top-bar bookmark toggle + Bookmarks-tab rows + TXT jump.
                            isCurrentBookmarked = isBookmarked,
                            onToggleBookmark = {
                                container.appScope.launch {
                                    runCatching { container.annotationsRepository.toggleBookmark(bookKey, title = null, locator = liveCanonical) }
                                }
                            },
                            currentLocator = liveCanonical,
                            bookmarks = bookmarkRows,
                            // TXT jump: scroll to the bookmark's char offset via the existing chunk scroll seam
                            // (the same path resume + the annotation jump use). Out-of-range → Failed (sheet stays open).
                            onJumpBookmark = { record ->
                                val target = txtBookmarkScrollTarget(record.locator.charOffsetUTF16, s.document.text.length)
                                if (target == null) {
                                    JumpResult.Failed
                                } else {
                                    jumpToOffset(target)   // pager in paged mode, list in scroll mode
                                    JumpResult.Succeeded
                                }
                            },
                            // TXT/MD jump: move to the annotation's UTF-16 offset (pager in paged mode, chunk
                            // scroll in scroll mode — the same path resume + scrubber use).
                            onJumpToAnnotation = { item ->
                                val target = annotationScrollOffset(item)
                                    .coerceIn(0, (s.document.text.length - 1).coerceAtLeast(0))
                                jumpToOffset(target)
                            },
                            onShareAnnotations = { shareAnnotations(annotationsSnapshot) },
                            // feature #131 WI-9 — the top-chrome pill (only while bilingual is ON; tapping it
                            // opens the setup sheet) + the More-menu Bilingual row (Toggle when AI is
                            // configured / Disabled "Configure AI provider first" when not). Only supplied
                            // for a TXT/MD book (bilingualVm != null); a null pill/row for any other format.
                            pillSlot = if (bilingualVm != null && bilingualState.enabled) {
                                {
                                    Box(Modifier.clickable { showBilingualSetup = true }) {
                                        com.vreader.app.bilingual.BilingualPill(theme = displaySettings.theme, language = bilingualState.targetLanguage)
                                    }
                                }
                            } else null,
                            bilingualMoreRow = if (bilingualVm == null) null
                                else if (!bilingualState.aiConfigured) com.vreader.app.reader.chrome.BilingualMoreRow.NeedsConfig
                                else com.vreader.app.reader.chrome.BilingualMoreRow.Ready(
                                    on = bilingualState.enabled,
                                    languageKey = bilingualState.targetLanguage.key,
                                    onToggle = { on ->
                                        // Nav model: first toggle ON → the setup sheet. Enabling raises the
                                        // VM's needsSetupSheet AFTER the serial enable command settles, which
                                        // drives the sheet — so we do NOT also set showBilingualSetup here
                                        // (that would race the enable command and re-open the sheet after the
                                        // user's Turn-on dismiss). OFF → disable. The VM is the source of truth.
                                        bilingualVm!!.setEnabled(on)
                                    },
                                ),
                            // feature #133 WI-10 — the Search entry + sheet. The icon is hidden only when the
                            // index-state gate says Unsupported (a skipped-unsupported TXT/MD book — no dead
                            // control); otherwise tapping it opens the sheet for THIS book.
                            onOpenSearch = if (inBookSearchState.hidesSearchEntry) null else { { showSearch = true } },
                            searchSheet = if (!showSearch) null else {
                                {
                                    InBookSearchSheet(
                                        theme = displaySettings.theme,
                                        bookTitle = s.title,
                                        state = inBookSearchState,
                                        query = inBookSearchState.query,
                                        onQueryChange = inBookSearchVm::onQueryChange,
                                        onPickRecent = inBookSearchVm::onPickRecent,
                                        // Resolve the tapped hit's canonical charOffsetUTF16 → scroll via the
                                        // EXISTING chunk-scroll seam (the same path resume / annotation / bookmark
                                        // jumps use). The WI-9 sheet's onJump is NON-suspend (JumpResult returns
                                        // synchronously), so — like the sibling annotation/bookmark jumps — the
                                        // range is validated UP FRONT (out-of-range/null → Failed, sheet stays
                                        // open, rule 51) and a valid target returns Succeeded optimistically while
                                        // the actual scroll runs on ttsScope; the launch is runCatching-guarded so
                                        // a scroll cancelled during teardown can't crash. The recent is committed
                                        // only on a valid result-open (the VM's commitSearch contract).
                                        onJump = { hit ->
                                            val off = hit.canonicalLocator?.charOffsetUTF16
                                            val target = txtBookmarkScrollTarget(off, s.document.text.length)
                                            if (target == null) {
                                                JumpResult.Failed
                                            } else {
                                                inBookSearchVm.commitSearch()
                                                jumpToOffset(target)   // pager in paged mode, list in scroll mode
                                                JumpResult.Succeeded
                                            }
                                        },
                                        onLoadMore = inBookSearchVm::loadMore,
                                        onDismiss = { inBookSearchVm.onDismiss(); showSearch = false },
                                    )
                                }
                            },
                            bottomBar = { (openContents, openNotes) ->
                                if (active) TtsControlBar(
                                    tts,
                                    onPlayPause = { if (tts.phase == TtsPhase.speaking) ttsVm.pause() else ttsVm.play() },
                                    onPrevious = ttsVm::previous, onNext = ttsVm::next, onStop = ttsVm::stop,
                                    onSpeed = { showSpeed = true }, onVoice = { showVoice = true },
                                    onInstallVoice = ttsVm::installVoiceData, onSystemTts = ttsVm::openSystemTts,
                                ) else ReaderBottomChrome(
                                    theme = displaySettings.theme,
                                    // feature #137 WI-6a — progress source is mode-aware: the PAGED body's
                                    // current page-start offset (so the scrubber fraction tracks the pager),
                                    // else the scroll top-visible chunk. Page labels stay 0 (page count is
                                    // shown by WI-6b's chrome footer, not this WI).
                                    progress = TxtProgress.fraction(
                                        if (usePaged) pagedOffset.value.coerceAtLeast(0)
                                        else s.document.offsetForChunk(listState.firstVisibleItemIndex),
                                        s.document.text.length,
                                    ),
                                    displayPage = 0, totalPages = 0,   // page labels are WI-6b
                                    // Scrub moves the PAGER in paged mode, the list in scroll mode (via the
                                    // shared jumpToOffset seam) — never the hidden list in paged mode.
                                    onScrub = { f ->
                                        val target = (f * s.document.text.length).toInt()
                                            .coerceIn(0, (s.document.text.length - 1).coerceAtLeast(0))
                                        jumpToOffset(target)
                                    },
                                    onOpenDisplay = { showDisplaySheet = true },
                                    // #132 WI-6: the scaffold hands the Contents/Notes open callbacks in.
                                    // TXT/MD has no TOC → openContents is null (Contents control hidden);
                                    // openNotes opens the review sheet.
                                    onOpenContents = openContents,
                                    onOpenNotes = openNotes,
                                    extraSlot = {
                                        ReadAloudChromeSlot(
                                            theme = displaySettings.theme,
                                            // feature #137 WI-6a — read-aloud (TTS) stays INERT in paged mode
                                            // (WI-9 re-integrates it); disabling the entry avoids starting TTS
                                            // that would drive the hidden scroll list (Gate-4 High-2).
                                            enabled = !usePaged && !starting && s.document.text.isNotBlank(),
                                        ) {
                                            starting = true
                                            ttsScope.launch {
                                                try {
                                                    val sentences = withContext(Dispatchers.Default) {
                                                        TtsChunker.chunk(s.document.text, TextToSpeech.getMaxSpeechInputLength())
                                                    }
                                                    ttsVm.start(sentences)
                                                } finally { starting = false }
                                            }
                                        }
                                    },
                                )
                            },
                            body = {
                            var boxOriginWindow by remember { mutableStateOf(androidx.compose.ui.geometry.Offset.Zero) }
                            var boxSize by remember { mutableStateOf(androidx.compose.ui.unit.IntSize.Zero) }
                            Box(Modifier.fillMaxSize().onGloballyPositioned { boxOriginWindow = it.localToWindow(androidx.compose.ui.geometry.Offset.Zero); boxSize = it.size }) {
                                // feature #137 WI-6a — the body branch (usePaged hoisted above): PAGED
                                // renderer when the Display layout is Paged AND bilingual is OFF; otherwise the
                                // pre-#137 continuous-scroll TxtBody (byte-identical behavior — selection/
                                // washes/TTS/bilingual). The scroll path keeps EVERY existing feature; paged
                                // mode leaves selection/highlights/bookmarks/TTS/find inert for now (WI-7a/7b/8/9).
                                SideEffect { pagedBodyMounted.value = usePaged }
                                if (usePaged) {
                                    TxtPagedBody(
                                        document = s.document,
                                        format = s.book.originalFormat,
                                        mapper = chunkMapper,
                                        textStyle = displaySettings.bodyTextStyle(),
                                        marginDp = displaySettings.marginDp,
                                        navigator = pagedNavigator,
                                        paginator = pagedPaginator,
                                        renderCache = pagedRenderCache,
                                        initialSourceOffset = s.initialOffset,
                                        // Persist the CURRENT page's start source offset on each settled
                                        // page turn (the page-start save; R1 Medium-8) — through the SAME
                                        // conflated writer the scroll save uses.
                                        onSaveSourceOffset = { offset ->
                                            pagedOffset.value = offset
                                            savePositionOffset(s.book, offset)
                                        },
                                        // feature #137 WI-6b — the CENTER tap-zone reuses the EXISTING chrome
                                        // toggle (the SAME chromeState flip the scaffold's own center-tap
                                        // does), routed here because detectTapGestures consumes the tap.
                                        onToggleChrome = {
                                            chromeState.value = chromeState.value.copy(chromeVisible = !chromeState.value.chromeVisible)
                                        },
                                        jumpRequest = pagedJumpRequest.value,
                                        onJumpConsumed = { pagedJumpRequest.value = null },
                                        // feature #137 WI-7b — wire the SAME selection controller + persisted
                                        // highlights the scroll body receives, so paged SELECTION (WI-7a) and
                                        // paged WASH (this WI) are LIVE in-app. Selection long-press-drag begins
                                        // a source selection through the controller; a finalize opens the
                                        // create popover; a settled tap resolves tap-to-edit against an existing
                                        // highlight (returns true → the classifier suppresses page-turn/chrome
                                        // for that tap). Washes are drawn per page from `highlights`.
                                        selectionController = selectionController,
                                        onSelectionFinalized = { finalizeTxtSelection(selectionController, popoverVm) },
                                        onTapEditAt = { point -> onTxtTapEditPaged(point, s.book, highlightsList, selectionController, popoverVm) },
                                        highlights = highlightsList,
                                    )
                                } else {
                                    TxtBody(
                                        s.document, listState, s.book.originalFormat, chunkMapper,
                                        textStyle = displaySettings.bodyTextStyle(),
                                        marginDp = displaySettings.marginDp,
                                        highlightSpan = { chunkIndex ->
                                            if (!active) null
                                            else {
                                                val cs = s.document.offsetForChunk(chunkIndex)
                                                val ce = if (chunkIndex + 1 < s.document.chunkCount) s.document.offsetForChunk(chunkIndex + 1) else s.document.text.length
                                                TtsHighlight.localSpan(cs, ce, tts.charStart, tts.charEnd)
                                            }
                                        },
                                        washesForChunk = { washMap[it] ?: emptyList() },
                                        selectionController = selectionController,
                                        onSelectionFinalized = { finalizeTxtSelection(selectionController, popoverVm) },
                                        onTapAt = { point -> onTxtTap(point, s.book, highlightsList, selectionController, popoverVm) },
                                        // feature #131 WI-8 — interlinear translation slot(s) per chunk. Only
                                        // drawn while bilingual is enabled; each returned state is derived from
                                        // the VM's shaped render slice for a unit anchored to this chunk (round-4
                                        // H2). Empty when off / no unit anchored here → the item's Column holds
                                        // only the unchanged source Text (behaviorally identical to today).
                                        bilingualRenderStates = { chunkIndex ->
                                            if (bilingualVm == null || !bilingualState.enabled) emptyList()
                                            else bilingualAnchors?.unitsForChunk(chunkIndex).orEmpty().map { unit ->
                                                com.vreader.app.bilingual.BilingualRenderState.forUnit(bilingualState, unit)
                                            }
                                        },
                                        bilingualLanguage = bilingualState.targetLanguage,
                                        bilingualTheme = displaySettings.theme,
                                        bilingualSourceFontSizeSp = displaySettings.fontSizeSp,
                                        // The translation slots report their window bounds so the selection
                                        // controller can exclude a long-press on translation from the
                                        // nearest-source-chunk fallback (round-4 H2 gesture exclusion).
                                        onBilingualSlotBounds = { bounds ->
                                            selectionController?.setExcludedBounds(bounds)
                                        },
                                    )
                                }
                                AnimatedVisibility(pillVisible, modifier = Modifier.align(Alignment.TopEnd).padding(12.dp)) {
                                    InReaderSessionPill(sessionSeconds)
                                }
                                // the selection popover, anchored under the selection end. anchorX/anchorY
                                // carry WINDOW px (set by finalizeTxtSelection); convert to box-local + clamp.
                                if (popoverState.visible) {
                                    val density = LocalDensity.current.density
                                    val half = 150f * density
                                    val popW = 320f * density
                                    val popH = 130f * density
                                    val margin = 8f * density
                                    val maxX = (boxSize.width - popW - margin).coerceAtLeast(margin)
                                    val xPx = (popoverState.anchorX - boxOriginWindow.x - half).coerceIn(margin, maxX)
                                    // below the selection by default; flip above when it would overflow the bottom.
                                    val belowY = popoverState.anchorY - boxOriginWindow.y + margin
                                    val yPx = if (belowY + popH <= boxSize.height) belowY
                                        else (popoverState.anchorY - boxOriginWindow.y - popH - margin).coerceAtLeast(margin)
                                    com.vreader.app.annotations.SelectionPopover(
                                        state = popoverState,
                                        actions = txtPopoverActions(s.book, selectionController, popoverVm),
                                        modifier = Modifier.offset { IntOffset(xPx.toInt(), yPx.toInt()) },
                                    )
                                }
                            }
                            },
                        )
                        if (showSpeed) TtsSpeedSheet(tts.rate, onRate = ttsVm::setRate, onDone = { showSpeed = false })
                        if (showVoice) TtsVoiceSheet(
                            voiceList,
                            onVoice = { ttsVm.selectVoice(it); showVoice = false },
                            onInstall = { ttsVm.installVoiceData() },
                            onDone = { showVoice = false },
                        )
                        // feature #129 — the designed Display sheet; setters persist on the process
                        // scope (so a write survives sheet dismissal / Activity teardown). The submission
                        // sequence is stamped SYNCHRONOUSLY here in the sheet callback (main thread, in
                        // slider order) via nextSeq() and passed into the setter — so the store's per-field
                        // latest-wins drop reflects the user's true edit order, NOT the multi-threaded
                        // dispatcher's coroutine-start order. A fire-and-forget launch per edit is then
                        // safe across rapid edits + rotation: a stale value can never win (Gate-4 High).
                        if (showDisplaySheet) {
                            val store = container.readerSettingsStore
                            ReaderSettingsSheet(
                                settings = displaySettings,
                                onTheme = { v -> val o = store.nextSeq(); container.appScope.launch { store.setTheme(v, o) } },
                                onLayout = { v -> val o = store.nextSeq(); container.appScope.launch { store.setLayout(v, o) } },
                                onFontFamily = { v -> val o = store.nextSeq(); container.appScope.launch { store.setFontFamily(v, o) } },
                                onFontSize = { v -> val o = store.nextSeq(); container.appScope.launch { store.setFontSize(v, o) } },
                                onLineSpacing = { v -> val o = store.nextSeq(); container.appScope.launch { store.setLineSpacing(v, o) } },
                                onMargin = { v -> val o = store.nextSeq(); container.appScope.launch { store.setMargin(v, o) } },
                                onDismiss = { showDisplaySheet = false },
                            )
                        }
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
        saveRequests.close()   // the writer drains the final (conflated) save, then ends
    }

    /** Load + decode the book and compute the initial scroll index from the saved position. */
    private suspend fun load(key: String): TxtUiState {
        val book = container.repository.findBook(key)
        val path = book?.localFilePath ?: return TxtUiState.Failed
        if (book == null) return TxtUiState.Failed
        val decoded = TxtDecoder.decode(File(path))
        val document = TxtDocument.of(decoded.text)
        container.repository.markOpened(key, System.currentTimeMillis())
        val initialOffset = computeInitialOffset(key)
        val initial = document.chunkForOffset(initialOffset)
        return TxtUiState.Loaded(book.title, document, book, initial, initialOffset)
    }

    /** Restore: the saved legacy locator's charOffsetUTF16 (the raw source-UTF-16 anchor). The scroll
     *  body maps it to a chunk (chunkForOffset); the paged body to a page (pageContaining). */
    private suspend fun computeInitialOffset(key: String): Int {
        // In-memory cache first — a fast rotation / reopen sees the latest offset even
        // before the prior instance's async Room flush commits. Falls to durable Room.
        container.cachedOffset(key)?.let { return it }
        val saved = container.repository.loadPosition(key) ?: return 0
        // ResumeResolver/ResumeTarget are in this package. A TXT position is a legacy
        // (non-Readium) envelope → Canonical; its charOffsetUTF16 is the anchor.
        return (ResumeResolver.resolve(saved) as? ResumeTarget.Canonical)
            ?.locator?.charOffsetUTF16 ?: return 0
    }

    /** Enqueue the top-visible chunk's char offset; the lone writer persists it (latest-wins). */
    private fun savePosition(book: Book, document: TxtDocument, topIndex: Int) {
        savePositionOffset(book, document.offsetForChunk(topIndex))
    }

    /** feature #137 WI-6a — enqueue a raw source-UTF-16 [offset] (the paged body saves the CURRENT
     *  page's START offset, already a source offset; the scroll body maps a chunk index first). Both
     *  funnel through the same conflated writer so a paged save and a scroll save can't interleave. */
    private fun savePositionOffset(book: Book, offset: Int) {
        // Cache synchronously so an immediate reopen/rotation reads the latest position
        // even before the async Room write below commits.
        container.cacheOffset(book.fingerprintKey, offset)
        saveRequests.trySend(PendingSave(book, offset))
    }

    /** Launch a system intent for a read-aloud one-shot, guarded by resolveActivity with fallbacks
     *  (there is no public Settings.ACTION_TTS_SETTINGS — fall back to accessibility / settings). */
    private fun launchTtsIntent(i: TtsIntent) {
        val candidates = when (i) {
            TtsIntent.InstallVoiceData -> listOf(android.content.Intent(TextToSpeech.Engine.ACTION_INSTALL_TTS_DATA))
            TtsIntent.OpenSystemTts -> listOf(
                android.content.Intent("com.android.settings.TTS_SETTINGS"),
                android.content.Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS),
                android.content.Intent(android.provider.Settings.ACTION_SETTINGS),
            )
        }
        // Try each in order, catching ActivityNotFoundException — resolveActivity() is unreliable on
        // API 30+ package visibility, so an actual startActivity attempt is the robust preflight.
        for (intent in candidates) {
            try { startActivity(intent); return } catch (_: android.content.ActivityNotFoundException) { /* next */ }
        }
    }

    // ---- feature #124 TXT selection-popover side effects ----

    private fun finalizeTxtSelection(controller: TxtSelectionController?, vm: com.vreader.app.annotations.SelectionPopoverViewModel) {
        val c = controller ?: return
        if (c.selectedVisibleText().isNullOrBlank() || !c.isCurrentSelectionValid()) { c.clear(); return }
        pendingTxtHighlightId = null   // a fresh selection is CREATE context
        pendingTxtText = c.selectedVisibleText()
        val anchor = c.selectionEndAnchorWindow() ?: androidx.compose.ui.geometry.Offset.Zero
        vm.showForSelection(anchor.x, anchor.y)   // WINDOW px
    }

    /** A tap on the body → if it lands inside an existing highlight, open the EDIT popover; else dismiss. */
    private fun onTxtTap(
        localPoint: androidx.compose.ui.geometry.Offset,
        book: com.vreader.app.data.Book,
        highlights: List<com.vreader.app.annotations.HighlightRecord>,
        controller: TxtSelectionController?,
        vm: com.vreader.app.annotations.SelectionPopoverViewModel,
    ) {
        val c = controller ?: return
        val off = c.resolveSourceOffset(localPoint)
        val hit = off?.let { TxtHighlightHitTester.highlightAt(it, highlights) }
        if (hit == null) { clearTxtSelection(c, vm); return }
        c.clear()
        pendingTxtHighlightId = hit.id
        pendingTxtText = hit.selectedText
        val anchor = c.toWindow(localPoint) ?: androidx.compose.ui.geometry.Offset.Zero
        vm.showForExisting(hit.color, hit.note, anchor.x, anchor.y)
    }

    /** feature #137 WI-7b — the PAGED tap-to-edit. Resolves the tap → source offset (page registry) →
     *  the hit highlight; if one is hit, opens the EDIT popover and RETURNS true so the unified
     *  pagedTapZones classifier SUPPRESSES page-turn/chrome navigation for that tap (no navigate+edit
     *  double-fire, Gate-4 R1 Critical). Returns false when no highlight is hit (the tap navigates as
     *  WI-6b) — and does NOT dismiss the selection there, so a plain reading tap still turns the page. */
    private fun onTxtTapEditPaged(
        localPoint: androidx.compose.ui.geometry.Offset,
        book: com.vreader.app.data.Book,
        highlights: List<com.vreader.app.annotations.HighlightRecord>,
        controller: TxtSelectionController?,
        vm: com.vreader.app.annotations.SelectionPopoverViewModel,
    ): Boolean {
        val c = controller ?: return false
        val off = c.resolveSourceOffset(localPoint)
        val hit = off?.let { TxtHighlightHitTester.highlightAt(it, highlights) } ?: return false
        c.clear()
        pendingTxtHighlightId = hit.id
        pendingTxtText = hit.selectedText
        val anchor = c.toWindow(localPoint) ?: androidx.compose.ui.geometry.Offset.Zero
        vm.showForExisting(hit.color, hit.note, anchor.x, anchor.y)
        return true
    }

    private fun txtPopoverActions(
        book: com.vreader.app.data.Book,
        controller: TxtSelectionController?,
        vm: com.vreader.app.annotations.SelectionPopoverViewModel,
    ) = com.vreader.app.annotations.SelectionPopoverActions(
        onColor = { color ->
            when (vm.state.value.mode) {
                com.vreader.app.annotations.PopoverMode.SELECT -> createTxtHighlight(book, controller, vm, color, null)
                com.vreader.app.annotations.PopoverMode.EDIT -> editTxtHighlightColor(controller, vm, color)
                com.vreader.app.annotations.PopoverMode.NOTE -> vm.selectColor(color)
            }
        },
        onHighlight = { createTxtHighlight(book, controller, vm, vm.state.value.activeColor, null) },
        onNote = { vm.beginNote() },
        onCopy = { copyTxtTextForAction(controller); clearTxtSelection(controller, vm) },
        onShare = { shareTxtTextForAction(controller); clearTxtSelection(controller, vm) },
        onRemove = { removeTxtHighlight(controller, vm) },
        onNoteDraftChange = { vm.updateNoteDraft(it) },
        onSaveNote = { saveTxtNote(book, controller, vm, vm.state.value.noteDraft.ifBlank { null }) },
        onCancelNote = { clearTxtSelection(controller, vm) },
    )

    /** Persist a note: update the existing highlight (EDIT) or create one from the selection (SELECT). */
    private fun saveTxtNote(
        book: com.vreader.app.data.Book,
        controller: TxtSelectionController?,
        vm: com.vreader.app.annotations.SelectionPopoverViewModel,
        note: String?,
    ) {
        val id = pendingTxtHighlightId
        if (id != null) {
            container.appScope.launch { container.annotationsRepository.updateHighlight(id, vm.state.value.activeColor, note) }
            clearTxtSelection(controller, vm)
        } else {
            createTxtHighlight(book, controller, vm, vm.state.value.activeColor, note)
        }
    }

    private fun editTxtHighlightColor(
        controller: TxtSelectionController?,
        vm: com.vreader.app.annotations.SelectionPopoverViewModel,
        color: com.vreader.app.annotations.AnnotationColor,
    ) {
        val id = pendingTxtHighlightId ?: return
        val note = vm.state.value.noteDraft.ifBlank { null }
        container.appScope.launch { container.annotationsRepository.updateHighlight(id, color, note) }
        clearTxtSelection(controller, vm)
    }

    private fun removeTxtHighlight(controller: TxtSelectionController?, vm: com.vreader.app.annotations.SelectionPopoverViewModel) {
        val id = pendingTxtHighlightId ?: return
        container.appScope.launch { container.annotationsRepository.removeHighlight(id) }
        clearTxtSelection(controller, vm)
    }

    private fun createTxtHighlight(
        book: com.vreader.app.data.Book,
        controller: TxtSelectionController?,
        vm: com.vreader.app.annotations.SelectionPopoverViewModel,
        color: com.vreader.app.annotations.AnnotationColor,
        note: String?,
    ) {
        val c = controller ?: return
        val range = c.currentRange()
        val visible = c.selectedVisibleText()   // #125: stored selectedText = what the user sees (rendered)
        val source = c.selectedSourceText()      // #125: textQuote + anchor = the markdown/raw source span
        if (range == null || visible.isNullOrBlank() || source.isNullOrBlank() || !c.isCurrentSelectionValid()) { clearTxtSelection(c, vm); return }
        val locator = vreader.contracts.Locator(
            book.contentSHA256, book.fileByteCount, book.originalFormat.name,   // #125: NOT hardcoded "txt" — MD key is "md:…"
            charRangeStartUTF16 = range.startInclusive, charRangeEndUTF16 = range.endExclusive, textQuote = source,
        )
        val anchor = com.vreader.app.annotations.AnnotationAnchor.Text("text-document:${book.fingerprintKey}", range.startInclusive, range.endExclusive)
        container.appScope.launch {
            container.annotationsRepository.addHighlight(book.fingerprintKey, color, visible, locator, anchor, note)
        }
        clearTxtSelection(c, vm)
    }

    /** The text for copy/share — the live selection's, or (EDIT) the tapped highlight's. */
    private fun txtTextForAction(controller: TxtSelectionController?): String? =
        pendingTxtText ?: controller?.selectedVisibleText()

    private fun copyTxtTextForAction(controller: TxtSelectionController?) {
        val text = txtTextForAction(controller) ?: return
        val clip = getSystemService(android.content.Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
        clip.setPrimaryClip(android.content.ClipData.newPlainText("vreader", text))
    }

    private fun shareTxtTextForAction(controller: TxtSelectionController?) {
        val text = txtTextForAction(controller) ?: return
        val send = android.content.Intent(android.content.Intent.ACTION_SEND).apply {
            type = "text/plain"; putExtra(android.content.Intent.EXTRA_TEXT, text)
        }
        startActivity(android.content.Intent.createChooser(send, null))
    }

    private fun clearTxtSelection(controller: TxtSelectionController?, vm: com.vreader.app.annotations.SelectionPopoverViewModel) {
        controller?.clear()
        pendingTxtHighlightId = null
        pendingTxtText = null
        vm.dismiss()
    }

    /** feature #134 WI-5 — copy the FULL canonical fingerprint to the OS clipboard (the Book Details
     *  copy-fingerprint mini-action). Rely on the OS copy confirmation — no invented toast (rule 51). */
    private fun copyFingerprint(fingerprintFull: String) {
        val clip = getSystemService(android.content.Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
        clip.setPrimaryClip(android.content.ClipData.newPlainText("fingerprint", fingerprintFull))
    }

    // ---- feature #132 WI-6: the review sheet's sheet-level Share (ACTION_SEND) ----

    /** Share ALL reviewed annotations (the review sheet's trailing Share) as one plain-text blob — the
     *  design's `AnnotationsSheet trailing={<Share/>}`. Highlights first, then standalone notes; no-op
     *  when nothing is saved (an empty share intent has nothing to offer). */
    private fun shareAnnotations(snapshot: AnnotationsSnapshot) {
        val text = annotationsShareText(snapshot)
        if (text.isBlank()) return
        val send = android.content.Intent(android.content.Intent.ACTION_SEND).apply {
            type = "text/plain"; putExtra(android.content.Intent.EXTRA_TEXT, text)
        }
        startActivity(android.content.Intent.createChooser(send, null))
    }

    // ---- feature #131 WI-8 bilingual test seams (the live More-menu entry is WI-9) ----
    // These drive the SAME VM the render/prefetch use, so a connected test can enable/disable + read
    // state deterministically without a designed entry toggle. Null-safe until the composition builds the
    // VM (a non-TXT/MD open, or before the first frame).

    /** Whether the bilingual VM was built for this book (TXT/MD only). */
    @androidx.annotation.VisibleForTesting
    fun bilingualViewModelBuiltForTest(): Boolean = bilingualViewModel != null

    /** Enable bilingual for this book via the VM (optionally set the target language first), then await
     *  the serial command consumer flipping `enabled` (and the language, when set) so the caller sees a
     *  settled state. */
    @androidx.annotation.VisibleForTesting
    suspend fun enableBilingualForTest(languageKey: String? = null) {
        val vm = bilingualViewModel ?: return
        languageKey?.let { vm.setTargetLanguage(it) }
        vm.setEnabled(true)
        awaitBilingualState(enabled = true, language = languageKey)
    }

    /** Disable bilingual + await the flip. */
    @androidx.annotation.VisibleForTesting
    suspend fun disableBilingualForTest() {
        val vm = bilingualViewModel ?: return
        vm.setEnabled(false)
        awaitBilingualState(enabled = false, language = null)
    }

    /** The VM's current bilingual state (or null if not built). */
    @androidx.annotation.VisibleForTesting
    fun bilingualStateForTest(): com.vreader.app.bilingual.BilingualUiState? = bilingualViewModel?.state?.value

    // The live selection controller + list state, so a connected test can drive the TTS source-visibility
    // seam (isSourceChunkInViewport) against real laid-out coordinates and scroll the source off-screen —
    // covering round-5/6 (the translation-only-visible → scroll case) deterministically (round-4 audit
    // Medium-2). Set by the composition alongside the bilingual VM.
    @Volatile private var testSelectionController: TxtSelectionController? = null
    @Volatile private var testListState: androidx.compose.foundation.lazy.LazyListState? = null

    /** Whether source chunk [index]'s registered `Text` bounds are in the list viewport (the SAME query
     *  the TTS auto-scroll guard uses). Null when the controller isn't laid out yet. */
    @androidx.annotation.VisibleForTesting
    fun isSourceChunkInViewportForTest(index: Int): Boolean? = testSelectionController?.isSourceChunkInViewport(index)

    /** Scroll the reader so [index] is the first visible item (drives the source of a distant chunk off
     *  the viewport). Suspends until the scroll settles. */
    @androidx.annotation.VisibleForTesting
    suspend fun scrollToItemForTest(index: Int) {
        testListState?.scrollToItem(index)
    }

    /** The current first-visible item index (== the top source chunk index — lazy-index==chunk-index). */
    @androidx.annotation.VisibleForTesting
    fun firstVisibleChunkForTest(): Int? = testListState?.firstVisibleItemIndex

    /** Await the VM's serial consumer flipping `enabled` to [enabled] AND (when non-null) the language.
     *  Throws on timeout so a test fails explicitly rather than proceeding with stale state. */
    private suspend fun awaitBilingualState(enabled: Boolean, language: String?) {
        val vm = bilingualViewModel ?: return
        for (i in 0 until 150) {
            val st = vm.state.value
            if (st.enabled == enabled && (language == null || st.targetLanguage.key == language)) return
            delay(20)
        }
        throw AssertionError("bilingual state (enabled=$enabled, language=$language) not reached in time")
    }

    // ---- feature #137 WI-6a — paged-body test seams (the connected TxtPagedBodyConnectedTest reads
    // page-index state + drives programmatic page turns; there is no CU-drivable horizontal-swipe gesture
    // in the harness, so the turn is exercised via the navigator's page jump). Set by the composition. ----
    @Volatile private var testPagedNavigator: com.vreader.app.reader.paged.TxtPageNavigator? = null
    @Volatile private var testPagedRenderCache: PagedRenderCache? = null
    @Volatile private var testPagedOffset: androidx.compose.runtime.MutableState<Int>? = null
    @Volatile private var testPagedBodyMounted: androidx.compose.runtime.MutableState<Boolean>? = null
    @Volatile private var testPagedJumpRequest: androidx.compose.runtime.MutableState<Int?>? = null
    @Volatile private var testPagedBook: Book? = null

    /** The published page count (0 before phase-1 finishes, or when the paged body isn't mounted). */
    @androidx.annotation.VisibleForTesting
    fun pagedPageCountForTest(): Int? = testPagedNavigator?.index?.pageCount

    /** The pager's current page (null before an index publishes). */
    @androidx.annotation.VisibleForTesting
    fun pagedCurrentPageForTest(): Int? = testPagedNavigator?.let { if (it.index == null) null else it.currentPage }

    /** The current page's START source offset (the value the host persists). */
    @androidx.annotation.VisibleForTesting
    fun pagedCurrentSourceOffsetForTest(): Int? = testPagedNavigator?.let { if (it.index == null) null else it.currentSourceOffset() }

    /** The page containing source [offset] in the current index (null if no index yet). */
    @androidx.annotation.VisibleForTesting
    fun pagedPageContainingForTest(offset: Int): Int? = testPagedNavigator?.let { if (it.index == null) null else it.pageContaining(offset) }

    /** The retained rendered-page count (proves the lazy window stays bounded). */
    @androidx.annotation.VisibleForTesting
    fun pagedRenderedCacheSizeForTest(): Int? = testPagedRenderCache?.size

    /** Whether the PAGED body is the mounted one (layout == Paged && !bilingual). */
    @androidx.annotation.VisibleForTesting
    fun pagedBodyMountedForTest(): Boolean? = testPagedBodyMounted?.value

    /** Turn to the next page PROGRAMMATICALLY by raising the paged body's jump request (the harness cannot
     *  express a horizontal swipe on the virtual display; the request drives the SAME scroll+save seam a
     *  settled swipe would, so the pager scrolls, the navigator's currentPage advances, and the new
     *  page-start offset is persisted). */
    @androidx.annotation.VisibleForTesting
    fun turnToNextPageForTest() {
        val nav = testPagedNavigator ?: return
        val idx = nav.index ?: return
        val req = testPagedJumpRequest ?: return
        val next = (nav.currentPage + 1).coerceAtMost((idx.pageCount - 1).coerceAtLeast(0))
        req.value = next
    }

    /** Persist the current paged page-start offset immediately (the connected test's save→reopen proof). */
    @androidx.annotation.VisibleForTesting
    fun flushPagedPositionForTest() {
        val nav = testPagedNavigator ?: return
        val book = testPagedBook ?: return
        if (nav.index == null) return
        savePositionOffset(book, nav.currentSourceOffset())
    }

    companion object {
        const val EXTRA_FINGERPRINT_KEY = "fingerprintKey"

        fun intent(context: android.content.Context, fingerprintKey: String): android.content.Intent =
            android.content.Intent(context, TxtReaderActivity::class.java)
                .putExtra(EXTRA_FINGERPRINT_KEY, fingerprintKey)
    }
}

/**
 * The TXT/MD reader host chrome — feature #132 WI-6. Renders the shared [ReaderChromeScaffold] (top bar +
 * the extended bottom chrome + the Notes review sheet) over the reading [body]. TXT/MD has no TOC, so
 * `tocEntries` is EMPTY (the [EmptyTocProvider] posture) → the scaffold hides the Contents control. The
 * top bar's Search/More/bookmark slots are omitted (null — #133/#134/#135; no dead controls). [bottomBar]
 * receives the scaffold's `(onOpenContents, onOpenNotes)` open callbacks and renders the host's bottom bar
 * — either the #121 TTS control bar (while read-aloud is active) or the #129 [ReaderBottomChrome] (Display
 * slot + read-aloud entry) wired to those callbacks. [onJumpToAnnotation] is NON-null (TXT/MD jump via the
 * Locator offset). Wrapped in a `systemBarsPadding()` Column so the chrome clears the status/nav bars (the
 * former TxtReaderScaffold's behavior). Extracted (internal) so the WI-6 host wiring is directly testable.
 *
 * feature #133 WI-10 — the in-book Search entry + sheet: [onOpenSearch] fills [ReaderTopChrome]'s Search
 * slot (null → the slot is omitted — the #129/#132 no-dead-control rule; a host whose index-state gate says
 * `Unsupported` passes null so the icon disappears). [searchSheet] is the host-supplied overlay that renders
 * the in-book search sheet when the host's search-open state is set; it is layered OVER the scaffold (the
 * sheet is a `ModalBottomSheet`, its own window), null when the sheet is closed. The host owns the
 * search-open state + the VM (one per reader session) so the scaffold stays a pure signal.
 */
@Composable
internal fun TxtReaderChrome(
    theme: ReaderTheme,
    title: String,
    chromeState: MutableState<ReaderChromeState>,
    annotations: AnnotationsSnapshot,
    onBack: () -> Unit,
    onJumpToAnnotation: (AnnotationItem) -> Unit,
    onShareAnnotations: () -> Unit,
    bottomBar: @Composable (Pair<(() -> Unit)?, (() -> Unit)?>) -> Unit,
    body: @Composable () -> Unit,
    // feature #133 WI-10 — the in-book Search entry + sheet overlay (nullable/default so #132/#134/#135
    // callers stay valid). A null [onOpenSearch] omits the top-bar Search icon (Unsupported / no-dead-control).
    onOpenSearch: (() -> Unit)? = null,
    searchSheet: (@Composable () -> Unit)? = null,
    // feature #134 WI-5 — the More menu's Book-details model + Share/copy actions (null model → no More).
    bookDetails: com.vreader.app.reader.details.BookDetailsUiModel? = null,
    onShareBook: () -> Unit = {},
    onCopyFingerprint: (String) -> Unit = {},
    // feature #135 WI-7 — the top-bar bookmark toggle + Bookmarks-tab rows + TXT/MD jump (all nullable/default
    // so #132/#134 callers stay valid). TXT supplies a preview provider (the Bookmarks-tab snippet).
    isCurrentBookmarked: Boolean = false,
    onToggleBookmark: (() -> Unit)? = null,
    currentLocator: vreader.contracts.Locator? = null,
    bookmarks: List<BookmarkRowItem> = emptyList(),
    onJumpBookmark: ((BookmarkRecord) -> JumpResult)? = null,
    // feature #131 WI-9 — the bilingual entry: the top-chrome pill (null → off) + the More-menu Bilingual
    // row (null → non-TXT/MD, no row). Nullable/default so #132/#134/#135 callers stay valid.
    pillSlot: (@Composable () -> Unit)? = null,
    bilingualMoreRow: com.vreader.app.reader.chrome.BilingualMoreRow? = null,
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
            onJumpToAnnotation = onJumpToAnnotation,
            onShareAnnotations = onShareAnnotations,
            // feature #133 WI-10 — the top-bar Search slot is now WIRED (the scaffold forwards it to
            // ReaderTopChrome(onSearch=…)). A null [onOpenSearch] omits the icon (Unsupported / no-dead-
            // control). feature #134 WI-5: the More button + Book Details / Share ride the scaffold's More menu.
            onOpenSearch = onOpenSearch,
            bottomChrome = { onOpenContents, onOpenNotes -> bottomBar(onOpenContents to onOpenNotes) },
            body = body,
            bookDetails = bookDetails,
            onShareBook = onShareBook,
            onCopyFingerprint = onCopyFingerprint,
            // feature #135 WI-7 — the bookmark toggle + Bookmarks tab, now lit up for TXT/MD.
            isCurrentBookmarked = isCurrentBookmarked,
            onToggleBookmark = onToggleBookmark,
            currentLocator = currentLocator,
            bookmarks = bookmarks,
            onJumpBookmark = onJumpBookmark,
            // feature #131 WI-9 — the bilingual pill + More-menu row.
            pillSlot = pillSlot,
            bilingualMoreRow = bilingualMoreRow,
        )
    }
    // feature #133 WI-10 — the in-book search sheet overlay (a ModalBottomSheet; the host renders it when
    // its search-open state is set). Layered outside the chrome Column so it covers the full reader.
    searchSheet?.invoke()
}

// ---- feature #135 WI-7 — TXT/MD pure host wiring helpers ----

/**
 * feature #135 WI-7 — the current TXT/MD reading position (a top-visible char offset) as a plain canonical
 * [vreader.contracts.Locator] (the bookmark equality basis + create/jump anchor). Mirrors the host's
 * save-position construction (identity triple + `charOffsetUTF16`), so a bookmark's position lines up with
 * the resume seam. Pure/JVM-testable.
 */
fun txtBookmarkLocator(book: com.vreader.app.data.Book, charOffsetUTF16: Int): vreader.contracts.Locator =
    vreader.contracts.Locator(
        contentSHA256 = book.contentSHA256,
        fileByteCount = book.fileByteCount,
        format = book.originalFormat.name,
        charOffsetUTF16 = charOffsetUTF16.coerceAtLeast(0),
    )

/**
 * feature #135 WI-7 — the TXT/MD bookmark jump target: the char offset to scroll to, or null when it is out
 * of range (→ [JumpResult.Failed], the sheet stays open — rule 51). A null/negative offset, an offset AT or
 * PAST EOF ([offset] >= [textLength] — a corrupt/cross-file-restored anchor), or an empty document
 * ([textLength] == 0) is out of range; a valid in-range offset is returned as-is (the PDF-page analog —
 * [pdfBookmarkPageTarget] — rejects the same way). Pure/JVM-testable.
 */
fun txtBookmarkScrollTarget(offset: Int?, textLength: Int): Int? {
    if (textLength <= 0) return null
    if (offset == null || offset < 0 || offset >= textLength) return null
    return offset
}

/**
 * feature #135 WI-7 — build the TXT/MD host's [BookmarkPreviewProvider] over the ALREADY-DECODED document
 * text (Risk-7: a plain read against the immutable buffer — no I/O). Returns a snippet starting at the
 * bookmark's char offset, at most `maxLen` chars (the WI-4 projection then single-lines + ellipsizes it);
 * null when the offset is at/past EOF (no meaningful snippet). Pure/JVM-testable (the document is the buffer).
 */
fun txtBookmarkPreviewProvider(document: TxtDocument): BookmarkPreviewProvider =
    BookmarkPreviewProvider { charOffsetUTF16, maxLen ->
        val text = document.text
        val start = charOffsetUTF16.coerceAtLeast(0)
        if (text.isEmpty() || start >= text.length) return@BookmarkPreviewProvider null
        text.substring(start, (start + maxLen).coerceAtMost(text.length))
    }

/** The pre-emission loading surface — a bare theme-colored full-screen fill while the Display settings +
 *  document load (the only pre-emission surface; the reader body is withheld until settings emit — Gate-4
 *  Medium). No chrome yet: chrome renders once the document is Loaded. */
@Composable
private fun TxtLoadingScaffold(theme: ReaderTheme) {
    Box(Modifier.fillMaxSize().background(theme.background).systemBarsPadding())
}

/** The tap-to-jump target UTF-16 offset for an annotation (feature #132 WI-6). A highlight anchors at its
 *  `charRangeStartUTF16`; a standalone note (or a highlight without a range) at `charOffsetUTF16`; a
 *  locator carrying neither, or a negative value, clamps to 0 (a safe scroll target). Pure/JVM-testable. */
internal fun annotationScrollOffset(item: AnnotationItem): Int {
    val loc = item.locator
    return (loc.charRangeStartUTF16 ?: loc.charOffsetUTF16 ?: 0).coerceAtLeast(0)
}

/** The plain-text blob shared by the review sheet's sheet-level Share (feature #132 WI-6): each highlight
 *  quote (with its attached note, if any) then each standalone note, one per line. Pure/JVM-testable. */
internal fun annotationsShareText(snapshot: AnnotationsSnapshot): String {
    val lines = buildList {
        snapshot.highlights.forEach { h ->
            add(if (h.note.isNullOrBlank()) h.selectedText else "${h.selectedText}\n— ${h.note}")
        }
        snapshot.notes.forEach { add(it.content) }
    }
    return lines.joinToString("\n\n").trim()
}

/** The designed read-aloud entry (vreader-tts.jsx `TtsEntry` — the reader bottom-toolbar Read-aloud
 *  / Volume item) as a ReaderBottomChrome toolbar slot (feature #129 WI-4 moved it into the chrome,
 *  the plan's sanctioned TtsEntryBar reconciliation). Tapping it starts read-aloud. */
@Composable
private fun ReadAloudChromeSlot(theme: ReaderTheme, enabled: Boolean, onReadAloud: () -> Unit) {
    val tint = if (enabled) theme.accent else theme.ink.copy(alpha = 0.35f)
    Column(
        Modifier
            .clip(RoundedCornerShape(14.dp))
            .clickable(enabled = enabled, onClick = onReadAloud)
            .padding(horizontal = 12.dp, vertical = 4.dp)
            .testTag("tts-read-aloud-entry"),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Icon(Icons.AutoMirrored.Filled.VolumeUp, contentDescription = "Read aloud", tint = tint, modifier = Modifier.size(24.dp))
        // accent label when enabled — the committed TtsEntry active treatment (pre-#129 TtsEntryBar parity).
        Text("Read aloud", color = tint, fontFamily = VReaderFonts.Sans, fontSize = 10.sp, fontWeight = FontWeight.Medium)
    }
}
