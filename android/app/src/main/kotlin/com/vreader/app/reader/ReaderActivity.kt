// Purpose: EPUB reader host — feature #106 WI-9 (#1745). Hosts Readium's
// EpubNavigatorFragment in scroll mode (Spike-B-verified), opening the stored EPUB
// via the WI-5 BookOpener and saving/restoring the reading position through the
// WI-6 ReadiumLocatorBridge + ResumeResolver → Room.
//
// feature #132 WI-7-EPUB: the full reader nav chrome. The EPUB host is the outlier (a Readium
// EpubNavigatorFragment View under the chrome, not a Compose body) and the ONLY TOC-supplying host, so it
// cannot reuse the Compose-native ReaderChromeScaffold. Instead ReaderActivity owns a persistent
// MutableStateFlow<ReaderChromeModel> (title + flattened TOC via ReadiumTocProvider + currentTocIndex +
// the Notes snapshot), fed as the async open completes and on every position change (tocIndexFor maps the
// live Readium locator to the nearest TOC entry). Three ComposeViews over the fragment's FrameLayout — a
// top band, a bottom band, and an open-only full-screen sheet layer (EpubReaderChrome.kt) — collect the
// model. The top/bottom bands cover only the chrome regions so the fragment underneath keeps scroll /
// selection / link input (touch-through); the sheet layer renders nothing until a sheet opens. Contents
// onJump → navigator.go(entry.epubReadiumLocator):Boolean (dismiss on success, stay-open on false, no
// invented error surface). Notes → the review sheet with jump-to-annotation null (EPUB review-only until
// #135). The #129 Display settings, the selection popover, highlight decorations, position save, and the
// publication close are all preserved.
package com.vreader.app.reader

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.ActionMode
import android.view.Gravity
import android.view.Menu
import android.view.MenuItem
import android.view.View
import android.widget.FrameLayout
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.fragment.app.commitNow
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.withStarted
import com.vreader.app.VReaderApp
import com.vreader.app.annotations.AnnotationColor
import com.vreader.app.annotations.AnnotationsRepository
import com.vreader.app.annotations.AnnotationsSnapshot
import com.vreader.app.annotations.EpubAnnotationMapper
import com.vreader.app.annotations.PopoverMode
import com.vreader.app.annotations.SelectionPopover
import com.vreader.app.annotations.SelectionPopoverActions
import com.vreader.app.annotations.SelectionPopoverViewModel
import com.vreader.app.data.Book
import com.vreader.app.data.LibraryRepository
import com.vreader.app.reader.chrome.ReaderChromeState
import com.vreader.app.reader.chrome.ReaderSheet
import com.vreader.app.reader.nav.ReadiumTocProvider
import com.vreader.app.reader.settings.ReaderTheme
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch
import org.json.JSONObject
import org.readium.r2.navigator.epub.EpubNavigatorFactory
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.AbsoluteUrl
import java.io.File

@OptIn(ExperimentalReadiumApi::class)
class ReaderActivity : AppCompatActivity() {

    private val container get() = (application as VReaderApp).container
    private val repository: LibraryRepository get() = container.repository
    private val bridge = ReadiumLocatorBridge()

    private val annotations: AnnotationsRepository get() = container.annotationsRepository

    private var containerId: Int = 0
    private var navigator: EpubNavigatorFragment? = null
    private var publication: Publication? = null   // host-owned; closed in onDestroy
    private var book: Book? = null

    // feature #132 WI-7-EPUB — the persistent chrome model the top/bottom bands + sheet layer collect,
    // populated as the async open completes and updated on every position change. The active Display
    // theme (also read by the chrome bands' colors) is mirrored so the ComposeViews can render immediately.
    private val chromeModel = MutableStateFlow(ReaderChromeModel())
    private val chromeTheme = mutableStateOf(ReaderTheme.Paper)
    // The hoisted top/bottom-visibility + open-sheet state (a Compose snapshot state, so the ComposeViews
    // recompose on change). Kept in-memory for the reader's lifetime (rotation always starts fresh — see
    // onCreate's super.onCreate(null)).
    private val chromeState = mutableStateOf(ReaderChromeState())
    // feature #129 — whether the Display settings sheet is open (opened from the bottom band's Aa slot).
    private val showDisplaySheet = mutableStateOf(false)
    // feature #132 WI-7-EPUB — the live reading fraction (0..1) for the bottom band's progress scrubber,
    // read from the navigator's currentLocator totalProgression (EPUB scroll mode).
    private val chromeProgress = mutableStateOf(0f)

    // feature #123 — in-reader highlighting
    private var highlightController: ReaderHighlightController? = null
    private val popoverVm = SelectionPopoverViewModel()
    // the Readium locator of the live selection (create context: set on a fresh selection)
    private var pendingSelection: Locator? = null
    // edit context: the existing highlight being edited (set on a decoration tap) + its text for copy/share
    private var pendingHighlightId: String? = null
    private var pendingSelectedText: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // The navigator fragment can't be restored before its FragmentFactory is set,
        // and we set the factory only after the async open completes — so always start
        // fresh (the saved reading position is what actually persists across recreation).
        super.onCreate(null)

        val key = intent.getStringExtra(EXTRA_FINGERPRINT_KEY)
        if (key == null) { finish(); return }
        setContentView(buildChrome())

        // feature #132 WI-7-EPUB — the chrome band colors follow the user's stored Display theme (open-time
        // value + live updates), mirroring how observeDisplaySettings feeds the navigator.
        lifecycleScope.launch {
            container.readerSettingsStore.settings.collect { chromeTheme.value = it.theme }
        }

        lifecycleScope.launch {
            val loaded = repository.findBook(key)
            if (loaded?.localFilePath == null) { finish(); return@launch }
            book = loaded
            // Seed the chrome model title immediately (TOC + annotations arrive once the publication opens).
            chromeModel.value = chromeModel.value.copy(title = loaded.title)

            val pub = try {
                BookOpener(this@ReaderActivity).open(File(loaded.localFilePath!!))
            } catch (e: BookOpenException) {
                finish(); return@launch
            }
            publication = pub

            val initial = computeInitialLocator(key)
            // feature #129 WI-5 — open with the user's stored Display settings already applied (so a
            // non-default theme/typography renders on first paint, no flash), keeping the scroll layout.
            val initialPrefs = EpubPreferences(scroll = true) + container.readerSettingsStore.current().toEpubPreferences()
            val factory = EpubNavigatorFactory(pub)
            // Attach only when the activity is at least STARTED AND its fragment state
            // isn't already saved — `commitNow` against a state-saved manager throws
            // IllegalStateException. If we can't commit, abort (the publication is
            // released in onDestroy; the activity recreates fresh on return).
            val nav: EpubNavigatorFragment? = withStarted {
                if (supportFragmentManager.isStateSaved) return@withStarted null
                supportFragmentManager.fragmentFactory = factory.createFragmentFactory(
                    initialLocator = initial,
                    initialPreferences = initialPrefs,
                    listener = object : EpubNavigatorFragment.Listener {
                        override fun onExternalLinkActivated(url: AbsoluteUrl) {}
                    },
                    configuration = EpubNavigatorFragment.Configuration().apply {
                        // intercept the system selection menu → show the designed floating popover instead.
                        selectionActionModeCallback = selectionCallback()
                    },
                )
                supportFragmentManager.commitNow {
                    add(containerId, EpubNavigatorFragment::class.java, Bundle(), READER_TAG)
                }
                supportFragmentManager.findFragmentByTag(READER_TAG) as EpubNavigatorFragment
            }
            if (nav == null) { finish(); return@launch }
            navigator = nav
            val controller = ReaderHighlightController(nav)
            highlightController = controller
            repository.markOpened(key, System.currentTimeMillis())
            // feature #132 WI-7-EPUB — build the chrome model once the publication is open: the flattened
            // TOC (each entry retaining its native Readium locator for the jump), the Notes snapshot, and
            // the initial highlighted-chapter index for the current reading position.
            populateChromeModel(pub, loaded, nav)
            observePosition(nav, loaded)
            observeDisplaySettings(nav)
            observeHighlights(loaded, controller)
            observeAnnotationsSnapshot(loaded)
            controller.observeActivations { id, rect -> onHighlightTapped(id, rect) }
        }
    }

    /** feature #132 WI-7-EPUB — populate the persistent chrome model after open: title + flattened TOC
     *  (ReadiumTocProvider) + the Notes snapshot + the initial currentTocIndex. Failures are tolerated (a
     *  book with no/broken TOC still renders the chrome with an empty Contents control). */
    private suspend fun populateChromeModel(pub: Publication, current: Book, nav: EpubNavigatorFragment) {
        val entries = runCatching { ReadiumTocProvider(pub, current).toc() }.getOrDefault(emptyList())
        val snapshot = runCatching { annotations.annotationsForBook(current.fingerprintKey) }
            .getOrDefault(AnnotationsSnapshot(emptyList(), emptyList()))
        val locator = nav.currentLocator.value
        val index = tocIndexFor(locator.href.toString(), locator.locations.progression, tocPositions(entries))
        chromeModel.value = chromeModel.value.copy(
            title = current.title,
            tocEntries = entries,
            annotations = snapshot,
            currentTocIndex = index,
        )
    }

    /** feature #132 WI-7-EPUB — reload the Notes snapshot whenever this book's stored highlights change (a
     *  fresh highlight/edit/remove), so a newly added annotation appears in the review sheet without a
     *  reopen. Notes are review-only for EPUB (no jump-to-annotation) until #135. */
    private fun observeAnnotationsSnapshot(current: Book) {
        lifecycleScope.launch {
            annotations.highlights(current.fingerprintKey).collect {
                val snapshot = runCatching { annotations.annotationsForBook(current.fingerprintKey) }
                    .getOrDefault(AnnotationsSnapshot(emptyList(), emptyList()))
                chromeModel.value = chromeModel.value.copy(annotations = snapshot)
            }
        }
    }

    /** A tap on an existing highlight decoration → open the popover in EDIT mode (Note/Copy/Share/Remove). */
    private fun onHighlightTapped(id: String, rect: android.graphics.RectF?) {
        lifecycleScope.launch {
            val h = annotations.findHighlight(id) ?: return@launch
            pendingHighlightId = id
            pendingSelectedText = h.selectedText
            pendingSelection = null
            val d = resources.displayMetrics.density
            popoverVm.showForExisting(h.color, h.note, (rect?.centerX() ?: 0f) / d, (rect?.bottom ?: 0f) / d)
        }
    }

    /** Re-apply the book's stored highlights as Readium decorations whenever the set changes. */
    private fun observeHighlights(current: Book, controller: ReaderHighlightController) {
        lifecycleScope.launch {
            annotations.highlights(current.fingerprintKey).collect { highlights ->
                runCatching { controller.applyHighlights(highlights) }
                    .onSuccess { built -> appliedHighlightCount = built }   // decorations actually built/applied
            }
        }
    }

    @Volatile private var appliedHighlightCount: Int = -1

    /** Test hook: the count of highlights applied as decorations on the live navigator (-1 until the
     *  first apply). Proves the reopen-render path ran against the real EpubNavigatorFragment. */
    @androidx.annotation.VisibleForTesting
    fun appliedHighlightCount(): Int = appliedHighlightCount

    /** The selection action-mode callback. We KEEP the action mode alive (return true) with an emptied
     *  menu so the WebView selection survives the suspend `currentSelection()` read, capture the
     *  selection (text + rect) → show the floating popover, then `finish()` to drop the (empty) system
     *  bar. Reading the selection while the mode is still alive avoids the "cancellation clears the
     *  selection" race of a bare `return false`. The empty bar is transient (gone the same tick the
     *  suspend read resolves), not persistent undesigned chrome. */
    private fun selectionCallback(): ActionMode.Callback = object : ActionMode.Callback {
        override fun onCreateActionMode(mode: ActionMode?, menu: Menu?): Boolean {
            menu?.clear()
            lifecycleScope.launch {
                val nav = navigator ?: run { mode?.finish(); return@launch }
                val selection = nav.currentSelection()
                if (selection == null || selection.locator.text.highlight.isNullOrBlank()) {
                    mode?.finish(); return@launch
                }
                pendingSelection = selection.locator
                pendingHighlightId = null       // entering CREATE context — drop any stale EDIT context
                pendingSelectedText = null
                val rect = selection.rect
                val density = resources.displayMetrics.density
                popoverVm.showForSelection((rect?.centerX() ?: 0f) / density, (rect?.bottom ?: 0f) / density)
                mode?.finish()   // captured — drop the empty system bar; the floating popover is the menu
            }
            return true
        }

        override fun onPrepareActionMode(mode: ActionMode?, menu: Menu?): Boolean { menu?.clear(); return true }
        override fun onActionItemClicked(mode: ActionMode?, item: MenuItem?): Boolean = false
        override fun onDestroyActionMode(mode: ActionMode?) {}
    }

    // ---- popover side effects ----

    private fun createHighlight(color: AnnotationColor, note: String?) {
        val current = book ?: return
        val locator = pendingSelection ?: return
        val inputs = EpubAnnotationMapper.selectionToInputs(locator, current) ?: return
        container.appScope.launch {
            annotations.addHighlight(current.fingerprintKey, color, inputs.selectedText, inputs.locator, inputs.anchor, note)
        }
        clearSelectionAndDismiss()
    }

    /** Update an existing highlight's color (EDIT context). */
    private fun editHighlightColor(color: AnnotationColor) {
        val id = pendingHighlightId ?: return
        val note = popoverVm.state.value.noteDraft.ifBlank { null }
        container.appScope.launch { annotations.updateHighlight(id, color, note) }
        clearSelectionAndDismiss()
    }

    /** Persist a note: update the existing highlight (EDIT) or create one from the selection (SELECT). */
    private fun saveNote(note: String?) {
        val id = pendingHighlightId
        if (id != null) {
            container.appScope.launch { annotations.updateHighlight(id, popoverVm.state.value.activeColor, note) }
            clearSelectionAndDismiss()
        } else {
            createHighlight(popoverVm.state.value.activeColor, note)
        }
    }

    private fun removeCurrentHighlight() {
        val id = pendingHighlightId ?: return
        container.appScope.launch { annotations.removeHighlight(id) }
        clearSelectionAndDismiss()
    }

    /** Copy/share work in both contexts — the live selection's text or the tapped highlight's text. */
    private fun selectedTextForAction(): String? = pendingSelectedText ?: pendingSelection?.text?.highlight

    private fun copySelection() {
        val text = selectedTextForAction() ?: return
        val clip = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clip.setPrimaryClip(ClipData.newPlainText("vreader", text))
        clearSelectionAndDismiss()
    }

    private fun shareSelection() {
        val text = selectedTextForAction() ?: return
        val send = Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, text) }
        startActivity(Intent.createChooser(send, null))
        clearSelectionAndDismiss()
    }

    private fun clearSelectionAndDismiss() {
        highlightController?.clearSelection()
        pendingSelection = null
        pendingHighlightId = null
        pendingSelectedText = null
        popoverVm.dismiss()
    }

    override fun onStop() {
        super.onStop()
        // Synchronous-intent flush: the last movement inside the debounce window would
        // otherwise be lost on back/home/rotation. Launched on the process scope so it
        // completes even as this activity is torn down.
        val nav = navigator ?: return
        val current = book ?: return
        val locator = nav.currentLocator.value
        container.appScope.launch { persist(locator, current) }
    }

    override fun onDestroy() {
        super.onDestroy()
        // Host owns the Publication (Readium's navigator does not close it). The
        // fragment is torn down by super.onDestroy() above, then we release it.
        publication?.close()
        publication = null
    }

    /** Restore precisely from the saved Readium locator; canonical-fallback (progression) is a follow-on. */
    private suspend fun computeInitialLocator(key: String): Locator? {
        val saved = repository.loadPosition(key) ?: return null
        return when (val target = ResumeResolver.resolve(saved)) {
            is ResumeTarget.Precise -> runCatching { Locator.fromJSON(JSONObject(target.readiumLocatorJSON)) }.getOrNull()
            else -> null
        }
    }

    /** feature #129 WI-5 — apply the live "Display" settings to the navigator: re-submit Readium
     *  EpubPreferences (typography + per-theme colors) on every change so a settings edit updates the
     *  open reader immediately. Scroll layout is preserved (WI-5 owns typography/theme only). The
     *  open-time value is already applied via `initialPrefs`; re-submitting the same value is a cheap
     *  no-op, so we don't drop the first emission (keeps the render authoritative). */
    private fun observeDisplaySettings(nav: EpubNavigatorFragment) {
        lifecycleScope.launch {
            container.readerSettingsStore.settings.collect { settings ->
                runCatching { nav.submitPreferences(EpubPreferences(scroll = true) + settings.toEpubPreferences()) }
                    .onFailure { android.util.Log.w("ReaderActivity", "submitPreferences failed; display change not applied", it) }
            }
        }
    }

    /** Save the current Readium position as a VReaderLocator envelope (debounced steady-state) AND keep the
     *  chrome model's highlighted-chapter index in sync as the reader scrolls (prompt, un-debounced — the
     *  Contents-sheet highlight should track the live position, and tocIndexFor is a cheap pure map). */
    private fun observePosition(nav: EpubNavigatorFragment, current: Book) {
        lifecycleScope.launch {
            nav.currentLocator
                .drop(1)            // skip the initial emission
                .debounce(1_000)
                .collect { locator -> persist(locator, current) }
        }
        lifecycleScope.launch {
            nav.currentLocator.collect { locator ->
                val model = chromeModel.value
                val index = tocIndexFor(locator.href.toString(), locator.locations.progression, tocPositions(model.tocEntries))
                if (index != model.currentTocIndex) {
                    chromeModel.value = chromeModel.value.copy(currentTocIndex = index)
                }
                chromeProgress.value = (locator.locations.totalProgression ?: 0.0).toFloat().coerceIn(0f, 1f)
            }
        }
    }

    private suspend fun persist(locator: Locator, current: Book) {
        val envelope = runCatching {
            bridge.toEnvelope(
                readiumLocatorJSON = locator.toJSON().toString(),
                bookContentSHA256 = current.contentSHA256,
                bookFileByteCount = current.fileByteCount,
                bookFormat = current.originalFormat,
            )
        }.getOrNull() ?: return
        repository.savePosition(envelope, System.currentTimeMillis())
    }

    /** feature #132 WI-7-EPUB — the full reader nav chrome over the Readium fragment. Because the reader
     *  body is a View (EpubNavigatorFragment), NOT a composable, the chrome cannot use the Compose-native
     *  ReaderChromeScaffold. Instead a single root FrameLayout stacks, bottom-to-top:
     *    1. the fragment container — MATCH_PARENT (the reading area fills the WHOLE screen, under the bands);
     *    2. the selection-popover overlay — MATCH_PARENT (unchanged; renders nothing unless a selection);
     *    3. the sheet layer — MATCH_PARENT but EMPTY until a sheet opens (so it's touch-through: the
     *       fragment keeps scroll/selection/link input whenever no sheet is up), then a full-screen dismiss
     *       overlay + the Contents/Notes ModalBottomSheet;
     *    4. the top band — WRAP_CONTENT, gravity TOP (covers only the top chrome strip);
     *    5. the bottom band — WRAP_CONTENT, gravity BOTTOM (covers only the bottom chrome strip).
     *  The two bands sit ON TOP of the fragment but occupy only their own height, so the reading area
     *  between them stays the fragment's — touch-through by construction. */
    private fun buildChrome(): View {
        val root = FrameLayout(this).apply { setBackgroundColor(chromeTheme.value.background.toArgb()) }

        val frame = FrameLayout(this).apply { id = View.generateViewId() }
        containerId = frame.id

        val popoverOverlay = ComposeView(this).apply { setContent { PopoverOverlay() } }
        val sheetLayer = ComposeView(this).apply {
            setContent {
                EpubReaderSheets(
                    model = chromeModel,
                    theme = chromeTheme.value,
                    chromeState = chromeState,
                    onJumpToc = ::jumpToTocEntry,
                    onShareAnnotations = { shareAnnotations(chromeModel.value.annotations) },
                )
            }
        }
        val topBand = ComposeView(this).apply {
            setContent { EpubTopBand(model = chromeModel, theme = chromeTheme.value, onBack = { finish() }) }
        }
        val bottomBand = ComposeView(this).apply {
            setContent {
                DisplaySettingsHost {
                    EpubBottomBand(
                        model = chromeModel,
                        theme = chromeTheme.value,
                        chromeState = chromeState,
                        progress = chromeProgress.value,
                        onScrub = ::scrubTo,
                        onOpenDisplay = { showDisplaySheet.value = true },
                    )
                }
            }
        }

        val match = FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)
        root.addView(frame, FrameLayout.LayoutParams(match))
        root.addView(popoverOverlay, FrameLayout.LayoutParams(match))
        root.addView(sheetLayer, FrameLayout.LayoutParams(match))
        root.addView(
            topBand,
            FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT).apply { gravity = Gravity.TOP },
        )
        root.addView(
            bottomBand,
            FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT).apply { gravity = Gravity.BOTTOM },
        )
        return root
    }

    /** The Contents TOC jump — feed the tapped entry's RETAINED native Readium locator straight to
     *  `navigator.go` (zero reconstruction). Returns Readium's Boolean success so the Contents sheet
     *  dismisses on success and stays open on a false/stale jump (rule 51 §nav-error-presentation, no
     *  invented error surface). An out-of-range index or a missing native locator → false (stay open). */
    private fun jumpToTocEntry(index: Int): Boolean {
        val nav = navigator ?: return false
        val entry = chromeModel.value.tocEntries.getOrNull(index) ?: return false
        val native = entry.epubReadiumLocator ?: return false
        return runCatching { nav.go(native) }.getOrDefault(false)
    }

    /** The bottom band's progress scrubber → seek. Maps the 0..1 fraction to a Readium locator on the
     *  current href and navigates there. A tolerated no-op when the navigator/publication isn't ready. */
    private fun scrubTo(fraction: Float) {
        val nav = navigator ?: return
        val current = nav.currentLocator.value
        val target = current.copyWithLocations(
            progression = fraction.toDouble().coerceIn(0.0, 1.0),
            totalProgression = fraction.toDouble().coerceIn(0.0, 1.0),
        )
        runCatching { nav.go(target) }
    }

    /** feature #132 WI-7-EPUB — the Notes review sheet's sheet-level Share (the design's
     *  `AnnotationsSheet trailing={<Share/>}`): share ALL reviewed annotations as one plain-text blob via
     *  ACTION_SEND. Reuses the shared [annotationsShareText] formatter (highlights then standalone notes);
     *  a no-op when nothing is saved. */
    private fun shareAnnotations(snapshot: AnnotationsSnapshot) {
        val text = annotationsShareText(snapshot)
        if (text.isBlank()) return
        val send = Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, text) }
        startActivity(Intent.createChooser(send, null))
    }

    /** Host the #129 Display settings sheet inside the bottom band's Compose tree so the Aa slot can open
     *  it. The sheet renders over the band; its setters persist on the process scope (surviving dismissal). */
    @androidx.compose.runtime.Composable
    private fun DisplaySettingsHost(content: @androidx.compose.runtime.Composable () -> Unit) {
        content()
        val show by showDisplaySheet
        if (show) {
            val settings = container.readerSettingsStore.settings.collectAsStateWithLifecycle(initialValue = null).value
            if (settings != null) {
                val store = container.readerSettingsStore
                com.vreader.app.reader.settings.ReaderSettingsSheet(
                    settings = settings,
                    onTheme = { v -> val o = store.nextSeq(); container.appScope.launch { store.setTheme(v, o) } },
                    onFontFamily = { v -> val o = store.nextSeq(); container.appScope.launch { store.setFontFamily(v, o) } },
                    onFontSize = { v -> val o = store.nextSeq(); container.appScope.launch { store.setFontSize(v, o) } },
                    onLineSpacing = { v -> val o = store.nextSeq(); container.appScope.launch { store.setLineSpacing(v, o) } },
                    onMargin = { v -> val o = store.nextSeq(); container.appScope.launch { store.setMargin(v, o) } },
                    onDismiss = { showDisplaySheet.value = false },
                )
            }
        }
    }

    /** The floating selection popover, positioned near the selection's anchor with a viewport clamp
     *  and an above/below flip. The full-screen scrim dismisses the popover on an outside tap. */
    @androidx.compose.runtime.Composable
    private fun PopoverOverlay() {
        val state by popoverVm.state.collectAsStateWithLifecycle()
        if (!state.visible) return
        androidx.compose.foundation.layout.BoxWithConstraints(
            Modifier.fillMaxSize().clickable(
                interactionSource = androidx.compose.runtime.remember { androidx.compose.foundation.interaction.MutableInteractionSource() },
                indication = null,
            ) { clearSelectionAndDismiss() },
        ) {
            val maxWPx = with(androidx.compose.ui.platform.LocalDensity.current) { maxWidth.toPx() }
            val maxHPx = with(androidx.compose.ui.platform.LocalDensity.current) { maxHeight.toPx() }
            val density = androidx.compose.ui.platform.LocalDensity.current.density
            val popW = 320f * density // approx popover width px for centering/clamp
            val popH = 120f * density // approx popover height px for the above/below flip
            // center on the selection's x, clamp into the viewport
            val xPx = (state.anchorX * density - popW / 2f).coerceIn(8f * density, (maxWPx - popW - 8f * density).coerceAtLeast(8f * density))
            // below the selection by default; flip above if it would overflow the bottom
            val belowY = state.anchorY * density + 8f * density
            val yPx = if (belowY + popH <= maxHPx) belowY else (state.anchorY * density - popH - 8f * density).coerceAtLeast(8f * density)
            SelectionPopover(
                state = state,
                actions = SelectionPopoverActions(
                    onColor = { c ->
                        when (popoverVm.state.value.mode) {
                            PopoverMode.SELECT -> createHighlight(c, null)   // one-tap highlight (iOS-like)
                            PopoverMode.EDIT -> editHighlightColor(c)         // recolor the tapped highlight
                            PopoverMode.NOTE -> popoverVm.selectColor(c)
                        }
                    },
                    onHighlight = { createHighlight(popoverVm.state.value.activeColor, null) },
                    onNote = { popoverVm.beginNote() },
                    onCopy = { copySelection() },
                    onShare = { shareSelection() },
                    onRemove = { removeCurrentHighlight() },
                    onNoteDraftChange = { popoverVm.updateNoteDraft(it) },
                    onSaveNote = { saveNote(popoverVm.state.value.noteDraft.ifBlank { null }) },
                    onCancelNote = { clearSelectionAndDismiss() },
                ),
                modifier = Modifier.offset(
                    x = with(androidx.compose.ui.platform.LocalDensity.current) { xPx.toDp() },
                    y = with(androidx.compose.ui.platform.LocalDensity.current) { yPx.toDp() },
                ),
            )
        }
    }

    /** Test hook: the current reading href, or null until the navigator has rendered. */
    @androidx.annotation.VisibleForTesting
    fun currentHref(): String? = navigator?.currentLocator?.value?.href?.toString()

    // feature #132 WI-7-EPUB test hooks — assert the chrome model + jump behavior against the live host
    // without driving Compose gestures (the live Compose render + tap ride WI-9 acceptance).
    /** The current chrome model (title/TOC/index/annotations) the bands collect. */
    @androidx.annotation.VisibleForTesting
    fun chromeModelSnapshot(): ReaderChromeModel = chromeModel.value

    /** The currently open reader sheet (None/Toc/Notes) — proves open/dismiss + touch-through posture. */
    @androidx.annotation.VisibleForTesting
    fun openSheet(): ReaderChromeState = chromeState.value

    /** Open the Contents sheet programmatically (the live Compose tap on the toolbar rides WI-9). */
    @androidx.annotation.VisibleForTesting
    fun openContentsForTest() { chromeState.value = chromeState.value.copy(sheet = ReaderSheet.Toc) }

    /** Open the Notes sheet programmatically. */
    @androidx.annotation.VisibleForTesting
    fun openNotesForTest() { chromeState.value = chromeState.value.copy(sheet = ReaderSheet.Notes) }

    /** Perform a TOC jump by index through the SAME seam the Contents sheet uses; returns Readium's
     *  Boolean (dismiss-on-success is the sheet's contract). Lets a connected test assert the native jump
     *  changed `currentHref` on true, and — with an out-of-range index — that a false leaves the sheet open. */
    @androidx.annotation.VisibleForTesting
    fun jumpToTocEntryForTest(index: Int): Boolean = jumpToTocEntry(index)

    /** Test hook (feature #129 WI-5): the background ARGB the live navigator has *accepted/computed*
     *  for its EpubSettings (the applied theme background), or null before the navigator/settings exist.
     *  Proves the Display setting reached and was resolved by the live EpubNavigatorFragment — it does
     *  NOT assert the WebView painted that pixel (a CSS/pixel assertion would; that's WI-8 acceptance). */
    @androidx.annotation.VisibleForTesting
    fun appliedBackgroundArgb(): Int? = navigator?.settings?.value?.backgroundColor?.int

    companion object {
        const val EXTRA_FINGERPRINT_KEY = "fingerprintKey"
        private const val READER_TAG = "reader-navigator"

        fun intent(context: android.content.Context, fingerprintKey: String): Intent =
            Intent(context, ReaderActivity::class.java).putExtra(EXTRA_FINGERPRINT_KEY, fingerprintKey)
    }
}
