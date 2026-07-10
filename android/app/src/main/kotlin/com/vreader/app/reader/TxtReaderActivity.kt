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
import com.vreader.app.reader.chrome.ReaderBottomChrome
import com.vreader.app.reader.settings.ReaderSettings
import com.vreader.app.reader.settings.ReaderSettingsSheet
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
                    is TxtUiState.Loading -> TxtReaderScaffold("", ::finish, (settingsOrNull ?: ReaderSettings()).theme) {}
                    is TxtUiState.Loaded -> {
                        // non-null by the gate above (Loaded is unreachable pre-emission).
                        val displaySettings = checkNotNull(settingsOrNull)
                        val listState = rememberLazyListState(initialFirstVisibleItemIndex = s.initialIndex)
                        // onStop flush — captures the live list state + book/document.
                        SideEffect {
                            flushPosition = { savePosition(s.book, s.document, listState.firstVisibleItemIndex) }
                        }
                        // Debounced steady-state save as the user scrolls.
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
                        // auto-scroll ONLY when the spoken chunk is off-screen — so a small manual scroll
                        // while listening isn't fought on every sentence.
                        LaunchedEffect(spokenChunk) {
                            if (spokenChunk >= 0 && listState.layoutInfo.visibleItemsInfo.none { it.index == spokenChunk }) {
                                runCatching { listState.animateScrollToItem(spokenChunk) }
                            }
                        }
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

                        TxtReaderScaffold(
                            title = s.title, onBack = ::finish, theme = displaySettings.theme,
                            bottom = {
                                if (active) TtsControlBar(
                                    tts,
                                    onPlayPause = { if (tts.phase == TtsPhase.speaking) ttsVm.pause() else ttsVm.play() },
                                    onPrevious = ttsVm::previous, onNext = ttsVm::next, onStop = ttsVm::stop,
                                    onSpeed = { showSpeed = true }, onVoice = { showVoice = true },
                                    onInstallVoice = ttsVm::installVoiceData, onSystemTts = ttsVm::openSystemTts,
                                ) else ReaderBottomChrome(
                                    theme = displaySettings.theme,
                                    progress = TxtProgress.fraction(
                                        s.document.offsetForChunk(listState.firstVisibleItemIndex),
                                        s.document.text.length,
                                    ),
                                    displayPage = 0, totalPages = 0,   // TXT/MD scroll-only — no page labels
                                    onScrub = { f ->
                                        ttsScope.launch {
                                            val target = (f * s.document.text.length).toInt()
                                                .coerceIn(0, (s.document.text.length - 1).coerceAtLeast(0))
                                            listState.scrollToItem(s.document.chunkForOffset(target))
                                        }
                                    },
                                    onOpenDisplay = { showDisplaySheet = true },
                                    extraSlot = {
                                        ReadAloudChromeSlot(
                                            theme = displaySettings.theme,
                                            enabled = !starting && s.document.text.isNotBlank(),
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
                        ) {
                            var boxOriginWindow by remember { mutableStateOf(androidx.compose.ui.geometry.Offset.Zero) }
                            var boxSize by remember { mutableStateOf(androidx.compose.ui.unit.IntSize.Zero) }
                            Box(Modifier.fillMaxSize().onGloballyPositioned { boxOriginWindow = it.localToWindow(androidx.compose.ui.geometry.Offset.Zero); boxSize = it.size }) {
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
                                )
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
                        }
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
        val initial = computeInitialIndex(key, document)
        return TxtUiState.Loaded(book.title, document, book, initial)
    }

    /** Restore: the saved legacy locator's charOffsetUTF16 → the chunk containing it. */
    private suspend fun computeInitialIndex(key: String, document: TxtDocument): Int {
        // In-memory cache first — a fast rotation / reopen sees the latest offset even
        // before the prior instance's async Room flush commits. Falls to durable Room.
        container.cachedOffset(key)?.let { return document.chunkForOffset(it) }
        val saved = container.repository.loadPosition(key) ?: return 0
        // ResumeResolver/ResumeTarget are in this package. A TXT position is a legacy
        // (non-Readium) envelope → Canonical; its charOffsetUTF16 is the anchor.
        val offset = (ResumeResolver.resolve(saved) as? ResumeTarget.Canonical)
            ?.locator?.charOffsetUTF16 ?: return 0
        return document.chunkForOffset(offset)
    }

    /** Enqueue the top-visible chunk's char offset; the lone writer persists it (latest-wins). */
    private fun savePosition(book: Book, document: TxtDocument, topIndex: Int) {
        val offset = document.offsetForChunk(topIndex)
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

    companion object {
        const val EXTRA_FINGERPRINT_KEY = "fingerprintKey"

        fun intent(context: android.content.Context, fingerprintKey: String): android.content.Intent =
            android.content.Intent(context, TxtReaderActivity::class.java)
                .putExtra(EXTRA_FINGERPRINT_KEY, fingerprintKey)
    }
}

/** Shared reader chrome (back + title) over the reading body, with a bottom slot for the reader
 *  chrome / TTS control bar — the vreader-reader.jsx subset. Renders in the active [theme]'s colors. */
@Composable
private fun TxtReaderScaffold(
    title: String, onBack: () -> Unit, theme: ReaderTheme = ReaderTheme.Paper,
    bottom: @Composable () -> Unit = {}, body: @Composable () -> Unit,
) {
    Column(Modifier.fillMaxSize().background(theme.background).systemBarsPadding()) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                Icons.AutoMirrored.Filled.ArrowBack,
                contentDescription = "Back",
                tint = theme.ink,
                modifier = Modifier.size(28.dp).clickable(onClick = onBack).padding(2.dp),
            )
            Text(title, Modifier.padding(start = 8.dp), color = theme.ink, fontSize = 16.sp, maxLines = 1)
        }
        Box(Modifier.weight(1f).fillMaxWidth()) { body() }
        bottom()
    }
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

/** The reading body — a LazyColumn over the document's chunk ranges. For BookFormat.md each chunk
 *  renders through MarkdownRenderer (styled); else verbatim. [textStyle] + [marginDp] come from the
 *  #129 Display settings (bodyTextStyle + the margin slider). */
@Composable
private fun TxtBody(
    document: TxtDocument, listState: LazyListState, format: BookFormat,
    // feature #125 — the single render owner. MD chunks render via mapper.renderedText so the body's
    // TextLayoutResult matches the controller/wash's offset map exactly (no double render, no drift).
    mapper: ChunkTextMapper,
    textStyle: TextStyle, marginDp: Float,
    highlightSpan: (chunkIndex: Int) -> IntRange? = { null },
    // feature #124 — annotation highlight washes per chunk (TXT only; the activity passes empty for MD).
    washesForChunk: (chunkIndex: Int) -> List<WashSpan> = { emptyList() },
    // feature #124 — TXT custom selection (null = no selection, e.g. MD). onSelectionFinalized fires on
    // long-press-drag release so the host can show the popover.
    selectionController: TxtSelectionController? = null,
    onSelectionFinalized: () -> Unit = {},
    // feature #124 WI-4 — a tap (LazyColumn-local point) → host hit-tests an existing highlight to edit.
    onTapAt: (androidx.compose.ui.geometry.Offset) -> Unit = {},
) {
    val isMarkdown = format == BookFormat.md
    val wash = VReaderColors.Accent.copy(alpha = 0.18f)
    val selectionAccent = Color(0x575C8FC4)   // design selection bg rgba(92,143,196,0.34)
    val selection by (selectionController?.selection ?: flowOf(null)).collectAsState(null)
    // the pointerInput block keys on selectionController (stable), so without this it would capture the
    // INITIAL onTapAt/onSelectionFinalized closures (stale highlightsList → tap-to-edit never hits).
    val currentOnTap by androidx.compose.runtime.rememberUpdatedState(onTapAt)
    val currentOnFinalize by androidx.compose.runtime.rememberUpdatedState(onSelectionFinalized)
    LazyColumn(
        Modifier
            .fillMaxSize()
            .onGloballyPositioned { selectionController?.setLazyCoords(it) }
            .then(
                if (selectionController != null) {
                    // ONE detector distinguishes a TAP (edit an existing highlight) from a LONG-PRESS+drag
                    // (new selection) — two separate pointerInput detectors conflict over the same down event.
                    Modifier.pointerInput(selectionController) {
                        awaitEachGesture {
                            val down = awaitFirstDown(requireUnconsumed = false)
                            val longPress = awaitLongPressOrCancellation(down.id)
                            if (longPress != null) {
                                // long-press → selection; finalize only on a COMPLETED drag/up (not a cancel).
                                selectionController.beginAt(longPress.position)
                                val completed = drag(longPress.id) { change -> selectionController.extendTo(change.position); change.consume() }
                                if (completed) currentOnFinalize() else selectionController.clear()
                            } else if (!down.isConsumed) {
                                // null also means cancel (e.g. a scroll won) — only a TAP leaves the down
                                // unconsumed; a scroll consumes it, so it won't be misread as tap-to-edit.
                                currentOnTap(down.position)
                            }
                        }
                    }
                } else {
                    Modifier
                },
            ),
        state = listState,
        contentPadding = PaddingValues(horizontal = marginDp.dp, vertical = 16.dp),
    ) {
        // Count-based: indices on demand (a newline-dense 14MB file can be 100k+ chunks).
        items(count = document.chunkCount, key = { it }) { i ->
            val raw = document.textForChunk(i).toString()
            // .md → styled markdown spans (no read-aloud span wash — markers shift offsets, plan §OOS).
            // .txt → raw verbatim, with the spoken-sentence span washed when read-aloud is active.
            val span = if (isMarkdown) null else highlightSpan(i)
            val text = when {
                isMarkdown -> mapper.renderedText(i)   // #125: the mapper is the single render owner
                span != null -> buildAnnotatedString {
                    append(raw)
                    val a = span.first.coerceIn(0, raw.length); val b = (span.last + 1).coerceIn(a, raw.length)
                    if (b > a) addStyle(SpanStyle(background = wash), a, b)
                }
                else -> AnnotatedString(raw)
            }
            // annotation washes drawn BEHIND the text (getPathForRange) — separate from the read-aloud span.
            val washes = washesForChunk(i)
            var layout by remember(i) { mutableStateOf<TextLayoutResult?>(null) }
            var coords by remember(i) { mutableStateOf<androidx.compose.ui.layout.LayoutCoordinates?>(null) }
            if (selectionController != null) {
                LaunchedEffect(i, layout, coords) {
                    val l = layout; val c = coords
                    if (l != null && c != null) selectionController.registerChunk(i, l, c)
                }
                DisposableEffect(selectionController, i) { onDispose { selectionController.unregisterChunk(i) } }
            }
            // read `selection` (a State) so a selection change recomposes + redraws the accent.
            val selRange = if (selection != null) selectionController?.selectionForChunk(i) else null
            Text(
                text = text,
                // merge over the material default (the pre-#129 explicit-param behavior) so platform
                // text defaults (letterSpacing etc.) are kept — only the Display settings change.
                style = androidx.compose.material3.LocalTextStyle.current.merge(textStyle),
                onTextLayout = { layout = it },
                modifier = Modifier
                    .onGloballyPositioned { coords = it }
                    .drawBehind {
                        layout?.let { l ->
                            drawWashes(l, washes)
                            selRange?.let { drawRangeFill(l, it, selectionAccent) }
                        }
                    },
            )
        }
    }
}
