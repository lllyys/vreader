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
//
// feature #131 WI-9: the bilingual entry is USER-REACHABLE for EPUB — the top band mounts the WI-7a
// BilingualPill (while ON) + the More-menu Bilingual Toggle/Disabled row wired to the VM; the setup sheet
// (first-enable / pill-tap) routes "Set up"/"Change…" to the Variant A ReaderAiProvidersSheet, and a
// mid-book language change reconciles the CURRENT resource's DOM via the controller's reconcile entry.
//
// feature #133 WI-11: in-book search reachable from the top bar. A per-session InBookSearchViewModel is built
// over the LIVE Readium publication (Readium's own SearchService — NOT the #128 FTS index), its state feeds
// the top band's Search-icon presence (hidden when the publication is not searchable → hidesSearchEntry), and
// the InBookSearchSheet renders in the sheetLayer ComposeView (open-only → touch-through preserved). A tapped
// hit jumps via Locator.fromJSON(readiumLocatorJson) → navigator.go (Succeeded dismisses / Failed keeps open,
// no invented error surface); a null/malformed locator is un-jumpable (Failed, not a crash). The VM is
// disposed in onDestroy (onCleared → closeAllEpubCursors) BEFORE the publication closes, so the live Readium
// SearchIterator never leaks.
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
import com.vreader.app.annotations.BookmarkRecord
import com.vreader.app.annotations.EpubAnnotationMapper
import com.vreader.app.annotations.PopoverMode
import com.vreader.app.annotations.SelectionPopover
import com.vreader.app.annotations.SelectionPopoverActions
import com.vreader.app.annotations.SelectionPopoverViewModel
import com.vreader.app.data.Book
import com.vreader.app.data.LibraryRepository
import com.vreader.app.diagnostics.DiagnosticsCategory
import com.vreader.app.diagnostics.VLog
import com.vreader.app.reader.chrome.ReaderChromeState
import com.vreader.app.reader.chrome.ReaderSheet
import com.vreader.app.reader.nav.BookmarkDateRenderer
import com.vreader.app.reader.nav.BookmarkPresentation
import com.vreader.app.reader.nav.BookmarkPreviewProvider
import com.vreader.app.reader.nav.BookmarkRowItem
import com.vreader.app.reader.nav.BookmarkTocIndex
import com.vreader.app.reader.nav.JumpResult
import com.vreader.app.reader.nav.ReadiumTocProvider
import com.vreader.app.reader.settings.ReaderTheme
import com.vreader.app.search.InBookHit
import com.vreader.app.search.InBookSearchSheet
import com.vreader.app.search.InBookSearchViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import org.json.JSONObject
import org.readium.r2.navigator.epub.EpubNavigatorFactory
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.AbsoluteUrl
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.io.File
import vreader.contracts.Locator as CanonicalLocator

@OptIn(ExperimentalReadiumApi::class)
class ReaderActivity : AppCompatActivity() {

    private val container get() = (application as VReaderApp).container
    private val repository: LibraryRepository get() = container.repository
    private val bridge = ReadiumLocatorBridge()

    private val annotations: AnnotationsRepository get() = container.annotationsRepository

    // feature #165 WI-7 — the annotation import/export SAF boundary, behind the app-wide
    // BoundedCallGate (never a fresh gate — one abandoned-call ledger, plan section 8.5). The
    // APPLICATION resolver, not this Activity's: the approved merge runs on `container.appScope` and
    // a bounded provider call can outlive the reader, so an Activity-bound resolver would keep a
    // finished Activity alive for the length of an untrusted provider's park (Gate-4 round 2,
    // Medium). Lazy so a reader that never opens the Details sheet pays nothing.
    private val annotationsIo by lazy { container.annotationsIoController(applicationContext.contentResolver) }

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
    // feature #134 WI-5 — the More menu's Book-details model (null until the book loads AND its collection
    // names are read → the More button is omitted until then; no dead control). Rebuilt on collection change.
    private val chromeBookDetails = mutableStateOf<com.vreader.app.reader.details.BookDetailsUiModel?>(null)

    // feature #135 WI-7 — the top-bar bookmark toggle state + the Bookmarks-tab rows the chrome bands read.
    // isCurrentBookmarked drives the filled/outline glyph; it is refreshed on every position change AND right
    // after a toggle. currentCanonical is the live reading position mapped to canonical (the equality basis
    // for presence/create). bookmarkRows is the projected List<BookmarkRowItem> (observeBookmarks → WI-4
    // projection with a BookmarkTocIndex built ONCE per TOC). All in-memory for the reader's lifetime.
    private val isCurrentBookmarked = mutableStateOf(false)
    private val bookmarkRows = mutableStateOf<List<BookmarkRowItem>>(emptyList())
    // The live reading position as a canonical Locator (null until the navigator has a locator). Read on the
    // main thread; the toggle/presence reads snapshot it.
    @Volatile private var currentCanonical: CanonicalLocator? = null
    // The bookmark TOC index, built ONCE from the flattened TOC when the publication opens (WI-4 design —
    // the host owns index construction), reused across every projected row.
    @Volatile private var bookmarkTocIndex: BookmarkTocIndex? = null
    private val bookmarkDate = bookmarkDateRenderer()

    // feature #133 WI-11 — the in-book search VM (ONE per reader session), built once the publication opens
    // over the LIVE Readium publication (Readium's own SearchService — NOT the FTS index). Disposed in
    // onDestroy (`onCleared` → closeAllEpubCursors, so the live Readium SearchIterator never leaks). The sheet
    // renders in the sheetLayer ComposeView; the Search-icon presence follows the VM's `hidesSearchEntry`.
    private var inBookSearchVm: InBookSearchViewModel? = null
    private val inBookSearchState = mutableStateOf<com.vreader.app.search.InBookSearchScreenState?>(null)
    private val showSearchSheet = mutableStateOf(false)
    // How many times the per-session search VM has been constructed — a test seam proving exactly ONE is
    // built per reader open (never a fresh one per query/recomposition — the WI-8 one-per-session contract).
    @Volatile private var inBookSearchVmBuildCount: Int = 0

    // feature #131 WI-7b — the EPUB bilingual DOM controller (the single owner of this book's
    // interlinear decorations, over Readium's `evaluateJavascript`). Built once per open book
    // when bilingual is ENABLED for an EPUB; null otherwise (non-EPUB / bilingual-off → zero
    // overhead beyond the idle position observer's fast-path guard). The controller enumerates
    // leaf blocks, restores from cache / translates via the direct-block path, and injects the
    // DOM — all main-thread, session-token guarded. `bilingualUnit` is the current resource's
    // href unit + `bilingualExpectedCount` its last-applied block count (drives the probe-gated
    // re-apply); `bilingualProvider` maps the live `currentLocator.href` → the epubHref unit.
    private var bilingualController: com.vreader.app.bilingual.EpubBilingualController? = null
    private var bilingualProvider: com.vreader.app.bilingual.EpubChapterTextProvider? = null
    private var bilingualViewModel: com.vreader.app.bilingual.BilingualViewModel? = null
    private var bilingualUnit: com.vreader.app.bilingual.TranslationUnitId? = null
    // The last-applied target language — a change clears the old-language DOM before the new apply
    // (so a failed/blank new-language apply never leaves the previous language visible — Gate-4 High).
    private var bilingualLang: String? = null
    // The dedicated re-apply job: a NEW resource/enable cancels the prior in-flight apply so a
    // slow chapter-A translation can't inject into chapter B (Gate-4 High). The position observer
    // NEVER suspends on translation — it schedules onto this job (chrome updates stay responsive).
    private var bilingualJob: kotlinx.coroutines.Job? = null

    // feature #131 WI-9 — the live bilingual UI state the top band's pill + More-menu row read (mirrored
    // off the VM's StateFlow so the ComposeViews recompose on change), plus the two host-owned sheet flags:
    // the setup sheet (raised on first-enable OR a pill tap) and the Variant A AI Providers sheet (opened
    // from the setup sheet's "Set up"/"Change…"). All in-memory for the reader's lifetime.
    private val bilingualUiState = mutableStateOf(com.vreader.app.bilingual.BilingualUiState())
    private val showBilingualSetup = mutableStateOf(false)
    private val showAiProviders = mutableStateOf(false)

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
            // non-default theme/typography renders on first paint, no flash). feature #137 WI-3 — the
            // OVERFLOW follows the stored layout: Scroll → Readium scroll (the default), Paged → Readium
            // native pagination (horizontal page-turn). The mapper leaves `scroll` unset, so the left
            // operand's scroll wins the `+` merge.
            val current = container.readerSettingsStore.current()
            val initialPrefs =
                EpubPreferences(scroll = current.layout == com.vreader.app.reader.settings.ReaderLayout.Scroll) +
                    current.toEpubPreferences()
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
            // feature #135 WI-7 — build the bookmark TOC index ONCE from the flattened TOC (WI-4 design),
            // then observe this book's bookmarks (project → rows) + keep the top-bar presence in sync.
            bookmarkTocIndex = BookmarkTocIndex.build(chromeModel.value.tocEntries)
            observeBookmarks(loaded)
            observePosition(nav, loaded)
            observeDisplaySettings(nav)
            observeHighlights(loaded, controller)
            observeAnnotationsSnapshot(loaded)
            observeBookDetails(loaded)
            controller.observeActivations { id, rect -> onHighlightTapped(id, rect) }
            // feature #133 WI-11 — build the per-session in-book search VM over the LIVE publication (Readium
            // SearchService) + observe its state for the top-bar Search-icon presence + the sheet.
            buildInBookSearch(key, pub)
            // feature #131 WI-7b — build the EPUB bilingual controller (single-owner DOM injection over
            // the live navigator) + drive it from the position observer. Gated by originalFormat==EPUB AND
            // bilingual-enabled — a non-EPUB or bilingual-off book pays only the observer's fast-path guard.
            buildBilingual(key, pub, nav, loaded)
        }
    }

    /** feature #131 WI-7b — construct the per-session EPUB bilingual controller + provider + VM (over the
     *  live [nav] / [pub]) and, when bilingual is ENABLED for this book, apply the interlinear decorations
     *  for the current resource. The controller keys the current unit off `currentLocator.href` (the EPUB
     *  divergence — an href, not a char offset); `evaluateJavascript` is dispatched on the MAIN thread via
     *  [evalOnMain] (a Readium `R2BasicWebView.checkThread` throws off-main). The re-apply signal (scroll
     *  round-trip / href change / reflow / activity recreate) is `currentLocator` in [observePosition]. */
    private fun buildBilingual(bookKey: String, pub: Publication, nav: EpubNavigatorFragment, current: Book) {
        if (current.originalFormat != vreader.contracts.BookFormat.epub) return
        val spineHrefs = runCatching { pub.readingOrder.map { it.href.toString() } }.getOrDefault(emptyList())
        val provider = com.vreader.app.bilingual.EpubChapterTextProvider(spineHrefs)
        // Host the VM in THIS activity's ViewModelStore (via a one-shot factory) so Android clears it
        // — and cancels its viewModelScope — automatically on destroy (no manual dispose needed; the
        // VM's onCleared is protected). A fresh store key per book keeps re-opens independent.
        val vm = androidx.lifecycle.ViewModelProvider(
            this,
            object : androidx.lifecycle.ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T =
                    container.bilingualViewModel(bookKey, provider) as T
            },
        )[com.vreader.app.bilingual.BilingualViewModel::class.java]
        val prefetcher = container.chapterTranslationPrefetcher(bookKey, provider)
        bilingualProvider = provider
        bilingualViewModel = vm
        bilingualController = com.vreader.app.bilingual.EpubBilingualController(
            evaluateJavascript = { js -> evalOnMain(nav, js) },
            prefetcher = prefetcher,
            onEpubBlocksEnumerated = vm::onEpubBlocksEnumerated,
            // Read the CURRENT language script fresh per apply so a language change is reflected.
            targetIsCjk = { vm.state.value.targetLanguage.script == com.vreader.app.bilingual.BilingualScript.cjk },
            targetIsRtl = { vm.state.value.targetLanguage.script == com.vreader.app.bilingual.BilingualScript.rtl },
        )
        // feature #131 WI-9 — mirror the VM state into the Compose-observable snapshot the top band's pill
        // + More-menu row read (the ComposeViews recompose when this snapshot changes).
        lifecycleScope.launch { vm.state.collect { bilingualUiState.value = it } }
        // feature #131 WI-9 — schedule the interlinear apply on the ENABLED false→true transition (Gate-4
        // High-2). The More-menu toggle's `setEnabled(true)` only ENQUEUES an async VM command, so calling
        // scheduleBilingual immediately would see enabled=false and no-op with nothing to reschedule. This
        // state-driven observer (the EPUB analog of TXT's enabled-keyed LaunchedEffect) reschedules once the
        // command settles enabled=true. `drop(1)` skips the initial emission (open-time apply covers it).
        lifecycleScope.launch {
            vm.state
                .map { it.enabled }
                .distinctUntilChanged()
                .drop(1)
                .collect { enabled -> if (enabled) scheduleBilingual(force = true) }
        }
        // feature #131 WI-9 — a MID-BOOK language change on a stationary EPUB: the position/display
        // re-apply signals fire only on scroll / settings changes, so reconcile the CURRENT resource's DOM
        // directly when the VM's target language changes while enabled + open. `drop(1)` skips the initial
        // hydration emission (the open-time apply already covers it); a change reconciles the visible DOM
        // (bump + full re-enumerate/re-inject, reaping stale-language decorations) on the dedicated job.
        lifecycleScope.launch {
            vm.state
                .map { it.targetLanguage.key }
                .distinctUntilChanged()
                .drop(1)
                .collect { newLang -> reconcileBilingualLanguage(newLang) }
        }
        // If bilingual is already on for this book (persisted), apply for the opening resource — AFTER
        // the VM hydrates (both enabled + language), so the open-time apply uses the correct language.
        scheduleBilingual(force = true, awaitHydration = true)
    }

    /** feature #131 WI-9 — reconcile the CURRENT EPUB resource's DOM to [newLang] after a mid-book language
     *  change (the deferred WI-7b finding b). Runs on the dedicated [bilingualJob] (cancelling any in-flight
     *  apply so a slow old-language translation can't inject into the new-language DOM) and calls the
     *  controller's single reconcile entry (bump + re-enumerate/re-inject the current resource). A no-op
     *  when bilingual is off / the navigator or a resolvable unit is absent; the record of the new language
     *  advances only through this path so a later scroll re-apply keys off the reconciled language. */
    private fun reconcileBilingualLanguage(newLang: String) {
        val controller = bilingualController ?: return
        val provider = bilingualProvider ?: return
        val vm = bilingualViewModel ?: return
        if (!vm.state.value.enabled) return
        bilingualJob?.cancel()
        bilingualJob = lifecycleScope.launch {
            val nav = navigator ?: return@launch
            val unit = provider.unitForHref(nav.currentLocator.value.href.toString()) ?: return@launch
            // Advance the recorded language/unit ONLY on a successful reconcile (verified clear + apply), so
            // a failed clear leaves the transition pending for the next schedule (Gate-4 High-3).
            val ok = controller.reconcileLanguageChange(unit, newLang)
            if (ok) { bilingualUnit = unit; bilingualLang = newLang }
        }
    }

    /** feature #131 WI-9 — the More-menu Bilingual toggle. Enabling flips the VM enabled (persisted),
     *  raises the setup sheet (the first-enable sheet; a re-enable also re-opens it so the user can confirm
     *  the language), and schedules the interlinear apply for the current resource; disabling flips it off
     *  and clears the DOM decorations. The VM's setEnabled is the single source of truth; the schedule /
     *  shutdown drive the live navigator. */
    private fun onBilingualToggle(on: Boolean) {
        val vm = bilingualViewModel ?: return
        vm.setEnabled(on)
        if (on) {
            // The VM raises needsSetupSheet AFTER the serial enable command settles → that drives the setup
            // sheet (BilingualSheets). We do NOT set showBilingualSetup here (it would race the enable
            // command and re-open the sheet after the user's Turn-on dismiss). The apply is scheduled by the
            // enabled false→true observer (buildBilingual), NOT here — calling scheduleBilingual now would
            // no-op against the not-yet-applied enabled state (Gate-4 High-2).
        } else {
            bilingualJob?.cancel()
            bilingualJob = lifecycleScope.launch {
                bilingualController?.shutdown()
                bilingualUnit = null
                bilingualLang = null
            }
        }
    }

    /** feature #131 WI-9 — the host-owned bilingual modal sheets (rendered in the sheet-layer ComposeView's
     *  tree, over the fragment). The setup sheet (first-enable OR pill/toggle-opened) drives language +
     *  turn-on; its "Set up"/"Change…" opens the Variant A AI Providers sheet, which on Save activates the
     *  provider, pops back, and refreshes the VM's aiConfigured (so the engine strip flips to configured). */
    @androidx.compose.runtime.Composable
    private fun BilingualSheets() {
        val vm = bilingualViewModel ?: return
        val state = bilingualUiState.value
        val setupVisible = state.needsSetupSheet || showBilingualSetup.value
        if (setupVisible) {
            com.vreader.app.bilingual.BilingualSetupSheet(
                theme = chromeTheme.value,
                selectedLanguage = state.targetLanguage,
                aiConfigured = state.aiConfigured,
                onSelectLanguage = { vm.setTargetLanguage(it.key) },
                onSetUp = { showAiProviders.value = true },
                onTurnOn = { vm.dismissSetupSheet(); showBilingualSetup.value = false },
                onDismiss = { vm.dismissSetupSheet(); showBilingualSetup.value = false },
            )
        }
        if (showAiProviders.value) {
            val aiVm = androidx.compose.runtime.remember { container.aiSettingsViewModel() }
            // Wrap in a BackupSurface so the reused list/editor's LocalBackupTokens follow the active reader
            // theme (Gate-4 Medium-1 — otherwise the sheet is always Light).
            com.vreader.app.backup.BackupSurface(darkOverride = chromeTheme.value.isDark) {
                com.vreader.app.bilingual.ReaderAiProvidersSheet(
                    vm = aiVm,
                    onDone = { showAiProviders.value = false; vm.refreshAiConfigured() },
                )
            }
        }
    }

    /** feature #131 WI-7b — evaluate [js] against the live navigator ON THE MAIN THREAD (Readium's
     *  `R2BasicWebView.checkThread` throws off-main). A non-cancellation failure (a torn-down navigator)
     *  is swallowed to null; a cooperative [kotlinx.coroutines.CancellationException] propagates (so a
     *  teardown/cancel is not misread as a benign null). */
    private suspend fun evalOnMain(nav: EpubNavigatorFragment, js: String): String? =
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Main.immediate) {
            try {
                nav.evaluateJavascript(js)
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Throwable) {
                null
            }
        }

    /** feature #131 WI-7b — schedule a bilingual re-apply on the DEDICATED [bilingualJob], cancelling any
     *  prior in-flight apply so a slow chapter-A translation can't inject into chapter B (Gate-4 High). The
     *  position/display observers call this and return immediately — they NEVER suspend on translation, so
     *  chrome/progress/bookmark updates stay responsive. [force] applies unconditionally (open-time / an
     *  explicit enable); otherwise the controller's probe gates the re-inject. [awaitHydration] waits for
     *  the VM's persisted enabled+language to hydrate before the open-time apply (Gate-4 High). */
    private fun scheduleBilingual(force: Boolean, awaitHydration: Boolean = false) {
        val controller = bilingualController ?: return
        val provider = bilingualProvider ?: return
        val vm = bilingualViewModel ?: return
        bilingualJob?.cancel()
        bilingualJob = lifecycleScope.launch {
            if (awaitHydration) awaitBilingualHydration(vm)
            if (!vm.state.value.enabled) return@launch
            val nav = navigator ?: return@launch
            val href = nav.currentLocator.value.href.toString()
            val unit = provider.unitForHref(href) ?: return@launch
            val lang = vm.state.value.targetLanguage.key
            // A LANGUAGE CHANGE clears the old-language DOM first (bump + verified clear) so a
            // failed/blank new-language apply never leaves the previous language visible (Gate-4
            // High). Only advance `bilingualLang`/`bilingualUnit` once the clear VERIFIED 0
            // remaining decorations — a cancelled/failed clear leaves the transition pending so the
            // next schedule retries (never records the new language over an un-cleared old DOM).
            val languageChanged = bilingualLang != null && bilingualLang != lang
            if (languageChanged) {
                val cleared = controller.shutdown()   // bump session + verified clear
                if (!cleared) return@launch           // clear did not finish — retry on the next schedule
                bilingualUnit = null
            }
            bilingualLang = lang
            when {
                unit != bilingualUnit -> { bilingualUnit = unit; controller.apply(unit, lang) }
                force -> controller.apply(unit, lang)
                else -> controller.reapplyIfNeeded(unit, lang, expectedCount = controller.expectedCountFor(unit))
            }
        }
    }

    /** feature #131 WI-7b — wait until the VM has hydrated its persisted config (the `init` store read
     *  flips enabled/language). Bounded so a never-hydrating VM doesn't hang the open-time apply; the
     *  persisted store value is authoritative on the first frame after hydration. */
    private suspend fun awaitBilingualHydration(vm: com.vreader.app.bilingual.BilingualViewModel) {
        val persisted = runCatching { container.perBookBilingualStore.read(book?.fingerprintKey ?: return) }
            .getOrNull() ?: return
        // Wait until the VM's live enabled matches the persisted enabled (hydration finished).
        for (i in 0 until 100) {
            if (vm.state.value.enabled == persisted.enabled) return
            kotlinx.coroutines.delay(20)
        }
    }

    /** feature #133 WI-11 — construct the ONE per-session in-book search VM (over the live Readium
     *  [publication], Readium's own SearchService — NOT the FTS index) and collect its state into
     *  [inBookSearchState] so the top band knows whether to show the Search icon and the sheet layer can
     *  render the sheet. The VM's collectors run on [lifecycleScope]; it is disposed in [onDestroy]
     *  (`onCleared` → closeAllEpubCursors → no leaked Readium SearchIterator). */
    private fun buildInBookSearch(bookKey: String, publication: Publication) {
        val vm = container.epubInBookSearchViewModel(
            bookKey = bookKey,
            publication = publication,
            coroutineScope = lifecycleScope,
        )
        inBookSearchVm = vm
        inBookSearchVmBuildCount += 1
        lifecycleScope.launch { vm.state.collect { inBookSearchState.value = it } }
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

    /** feature #165 WI-7 — reload the Notes snapshot after an annotation import merged rows.
     *  [observeAnnotationsSnapshot]'s Flow fires on HIGHLIGHT changes only, so a file that brought only
     *  notes (or only bookmarks) would otherwise stay invisible until the book was reopened. */
    private fun refreshAnnotationsSnapshot() {
        val current = book ?: return
        lifecycleScope.launch {
            val snapshot = runCatching { annotations.annotationsForBook(current.fingerprintKey) }
                .getOrDefault(AnnotationsSnapshot(emptyList(), emptyList()))
            chromeModel.value = chromeModel.value.copy(annotations = snapshot)
        }
    }

    /** feature #134 WI-5 — build + keep the More menu's Book-details model in sync with this book's live
     *  collection names (EPUB supplies no page count → the Pages row is omitted). The mapped model appears
     *  on the [chromeBookDetails] state the top band/sheet layer read, so the More button appears once the
     *  book + its collections are known (null until then — no dead control). */
    private fun observeBookDetails(current: Book) {
        lifecycleScope.launch {
            container.collectionRepository.observeCollectionNamesForBook(current.fingerprintKey).collect { names ->
                chromeBookDetails.value =
                    com.vreader.app.reader.details.BookDetailsMapper.map(current, names, pageCount = null)
            }
        }
    }

    /** feature #134 WI-5 — copy the FULL canonical fingerprint to the OS clipboard (the Book Details
     *  copy-fingerprint mini-action). Rely on the OS copy confirmation — no invented toast (rule 51). */
    private fun copyFingerprint(fingerprintFull: String) {
        val clip = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clip.setPrimaryClip(ClipData.newPlainText("fingerprint", fingerprintFull))
    }

    /** feature #134 WI-5 — the More menu's Share book action: launch the WI-2 book-file share chooser for
     *  the current book (a missing/out-of-scope file or no receiver is a silent no-op — WI-2 handles it). */
    private fun shareBookFile() {
        val current = book ?: return
        com.vreader.app.reader.share.shareBook(this, current)
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
        // feature #131 WI-7b — invalidate the bilingual session AND cancel the in-flight re-apply job
        // BEFORE the fragment/publication teardown so no late apply reaches the torn-down navigator (a
        // JS eval against it throws; the bump makes the next token re-check discard, the job cancel stops
        // a suspended apply). Done before super, which tears the fragment. The VM is cleared by Android
        // (it lives in this activity's ViewModelStore); we drop the references so a re-open is fresh.
        bilingualJob?.cancel()
        bilingualJob = null
        bilingualController?.bumpSession()
        bilingualController = null
        bilingualViewModel = null
        bilingualProvider = null
        super.onDestroy()
        // feature #133 WI-11 — dispose the in-book search VM (its onCleared disposes the live Readium
        // SearchIterator via closeAllEpubCursors) BEFORE releasing the publication it searches over — the
        // iterator is a view over the publication, so it must go first (no leak, no use-after-close).
        inBookSearchVm?.onCleared()
        inBookSearchVm = null
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
     *  open reader immediately. feature #137 WI-3 — the OVERFLOW now follows the live layout too:
     *  Scroll → Readium scroll (the default), Paged → Readium native pagination (horizontal page-turn),
     *  so the Display-sheet Layout toggle flips scroll↔paged on the open reader. Readium fires
     *  `currentLocator` on each page turn in paginated mode (the save/progress feed — [observePosition]).
     *  The open-time value is already applied via `initialPrefs`; re-submitting the same value is a cheap
     *  no-op, so we don't drop the first emission (keeps the render authoritative). */
    private fun observeDisplaySettings(nav: EpubNavigatorFragment) {
        lifecycleScope.launch {
            container.readerSettingsStore.settings.collect { settings ->
                val prefs = EpubPreferences(scroll = settings.layout == com.vreader.app.reader.settings.ReaderLayout.Scroll) +
                    settings.toEpubPreferences()
                runCatching { nav.submitPreferences(prefs) }
                    .onFailure {
                        VLog.w(
                            DiagnosticsCategory.READER,
                            "ReaderActivity",
                            "submitPreferences failed; display change not applied",
                            it,
                        )
                    }
                // feature #131 WI-7b — a `submitPreferences` reflow can drop the injected decorations
                // (a CSS/typography reflow re-renders the resource DOM). Schedule a probe-gated re-inject
                // (on the dedicated job — never suspend this settings collector) so the interlinear
                // survives a Display-settings change (spike finding c-ii). A no-op when the decorations
                // survived, and when bilingual is off / non-EPUB.
                scheduleBilingual(force = false)
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
                // feature #135 WI-7 — map the live Readium position to canonical (the toggle's equality
                // basis) + refresh the top-bar filled/outline presence as the reader scrolls.
                val canonical = canonicalForCurrent(locator, current)
                currentCanonical = canonical
                isCurrentBookmarked.value = canonical != null &&
                    runCatching { annotations.isBookmarked(current.fingerprintKey, canonical) }.getOrDefault(false)
                // feature #131 WI-7b — the universal re-apply signal for ALL four EPUB recreation
                // cases (scroll round-trip / href change / fragment recreation / activity recreate):
                // schedule a probe-gated re-apply on the DEDICATED job (never suspend this collector on
                // translation — chrome/progress/bookmark updates above stay responsive). A unit CHANGE
                // applies fresh; a same-unit reflow re-injects ONLY if the DOM lost the decorations.
                scheduleBilingual(force = false)
            }
        }
    }

    /** feature #135 WI-7 — the live Readium position → canonical [CanonicalLocator] (the bookmark equality
     *  basis). Extracts the plain values (href + progression + totalProgression + cfi) off the Readium
     *  locator here (the thin Readium hop) and hands them to the pure [epubBookmarkLocator]. */
    private fun canonicalForCurrent(locator: Locator, current: Book): CanonicalLocator? {
        val href = locator.href.toString().takeIf { it.isNotBlank() } ?: return null
        val cfi = locator.locations.fragments.firstOrNull { it.startsWith("epubcfi(") }
        return runCatching {
            epubBookmarkLocator(
                href = href,
                progression = locator.locations.progression,
                totalProgression = locator.locations.totalProgression,
                cfi = cfi,
                contentSHA256 = current.contentSHA256,
                fileByteCount = current.fileByteCount,
                format = current.originalFormat.name,
            ).validatedOrNull()
        }.getOrNull()
    }

    /** feature #135 WI-7 — observe this book's bookmarks and project them to the Bookmarks-tab rows (WI-4
     *  projection over the once-built [bookmarkTocIndex]). EPUB has no preview provider (no arbitrary body
     *  extraction — chapter/page come from the TOC). Lifecycle-scoped so the collector is cancelled with
     *  the reader (no leak). */
    private fun observeBookmarks(current: Book) {
        lifecycleScope.launch {
            annotations.bookmarks(current.fingerprintKey).collect { records ->
                bookmarkRows.value = bookmarkRowItems(
                    records = records,
                    format = current.originalFormat,
                    tocIndex = bookmarkTocIndex,
                    previewProvider = null,
                    dateRenderer = bookmarkDate,
                )
            }
        }
    }

    /** feature #135 WI-7 — the top-bar bookmark toggle: create-or-remove the bookmark at the live reading
     *  position (the canonical equality basis), then refresh the filled/outline presence. A no-op when the
     *  navigator has no locator yet (currentCanonical null → no dead toggle). */
    private fun toggleCurrentBookmark() {
        val current = book ?: return
        val canonical = currentCanonical ?: return
        lifecycleScope.launch {
            runCatching { annotations.toggleBookmark(current.fingerprintKey, title = null, locator = canonical) }
            isCurrentBookmarked.value =
                runCatching { annotations.isBookmarked(current.fingerprintKey, canonical) }.getOrDefault(false)
        }
    }

    /** feature #135 WI-7 — jump to a persisted bookmark. A bookmark carries ONLY a canonical [CanonicalLocator]
     *  (no precise Readium JSON), so reconstruct a Readium locator via [ReadiumLocatorReconstructor] then
     *  `navigator.go`. A null reconstruction (malformed/unresolvable/renamed href, or a different-book
     *  locator) OR a false `go` → [JumpResult.Failed] (the sheet stays open, NO invented error surface —
     *  rule 51). This is exactly the fresh-process / backup-restored canonical-only jump path. */
    private fun jumpToBookmark(record: BookmarkRecord): JumpResult {
        val nav = navigator ?: return JumpResult.Failed
        val pub = publication ?: return JumpResult.Failed
        val current = book ?: return JumpResult.Failed
        val readium = ReadiumLocatorReconstructor(current.fingerprintKey, pub).toReadium(record.locator)
            ?: return JumpResult.Failed
        val landed = runCatching { nav.go(readium) }.getOrDefault(false)
        return if (landed) JumpResult.Succeeded else JumpResult.Failed
    }

    /** feature #133 WI-11 — jump to a tapped in-book search hit. An EPUB hit carries a NAVIGABLE Readium
     *  locator serialized to JSON ([InBookHit.readiumLocatorJson]); reconstruct it via
     *  `Locator.fromJSON(JSONObject(json))` and `navigator.go`. A null/blank/malformed JSON (an un-jumpable
     *  hit — e.g. a Readium locator that failed to serialize) OR a false `go` → [JumpResult.Failed] (the sheet
     *  stays open, NO invented error surface — rule 51 §nav-error-presentation), NEVER a crash. On a landed
     *  jump the query is committed to the GLOBAL recents (the WI-8 commitSearch contract). This mirrors
     *  [jumpToBookmark]'s Succeeded/Failed contract. */
    private fun jumpToSearchHit(hit: InBookHit): JumpResult {
        val nav = navigator ?: return JumpResult.Failed
        val json = hit.readiumLocatorJson?.takeIf { it.isNotBlank() } ?: return JumpResult.Failed
        val readium = runCatching { Locator.fromJSON(JSONObject(json)) }.getOrNull() ?: return JumpResult.Failed
        val landed = runCatching { nav.go(readium) }.getOrDefault(false)
        if (landed) inBookSearchVm?.commitSearch()
        return if (landed) JumpResult.Succeeded else JumpResult.Failed
    }

    /** feature #133 WI-11 — dismiss the in-book search sheet: run the VM's dismiss (invalidates the active
     *  session + disposes the live Readium SearchIterator via closeAllEpubCursors — no leak) then hide it. */
    private fun dismissInBookSearch() {
        inBookSearchVm?.onDismiss()
        showSearchSheet.value = false
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
                // feature #165 WI-7 — the production annotation-import entry: the SAF launcher + the
                // designed preview sheet, built HERE because this is the ComposeView that renders the
                // Details sheet the row lives in. The Details route is closed before the picker opens
                // (one modal at a time), and a successful merge forces a snapshot refresh — the live
                // `highlights` Flow only fires for highlights, so a notes-only import would otherwise
                // not appear until a reopen.
                val details = chromeBookDetails.value
                val importEntry = rememberAnnotationImportEntry(
                    controller = annotationsIo,
                    bookKey = book?.fingerprintKey.orEmpty(),
                    bookTitle = chromeModel.value.title,
                    // The MERGE must survive this reader being finished/rotated: once the user has
                    // tapped `Import N items` the work is committed as far as they are concerned,
                    // and the applier rethrows CancellationException (Gate-4 round 1, High).
                    applyScope = container.appScope,
                    onLaunching = { chromeState.value = chromeState.value.copy(sheet = ReaderSheet.None) },
                    onApplied = ::refreshAnnotationsSnapshot,
                )
                EpubReaderSheets(
                    model = chromeModel,
                    theme = chromeTheme.value,
                    chromeState = chromeState,
                    onJumpToc = ::jumpToTocEntry,
                    onShareAnnotations = { shareAnnotations(chromeModel.value.annotations) },
                    // feature #134 WI-5 — the Book Details route + its Share / copy-fingerprint actions.
                    bookDetails = details,
                    onShareBook = ::shareBookFile,
                    onCopyFingerprint = ::copyFingerprint,
                    // feature #135 WI-7 — the Bookmarks-tab rows + the per-bookmark jump (canonical → Readium).
                    bookmarks = bookmarkRows.value,
                    onJumpBookmark = ::jumpToBookmark,
                    // feature #165 WI-7 — gated on the SAME model that gates the More button, so the row can
                    // never appear before this book's key is known.
                    onImportAnnotations = if (details != null) importEntry.launch else null,
                    importSheet = importEntry.sheetSlot(chromeTheme.value),
                )
                // feature #133 WI-11 — the in-book search sheet renders in the SAME sheet-layer ComposeView
                // (open-only, so it does not cover the fragment while closed → touch-through preserved). It is
                // a ModalBottomSheet (its own window), driven by the per-session VM's live Readium search;
                // tapping a hit → jumpToSearchHit (Locator.fromJSON → nav.go), dismiss disposes the iterator.
                InBookSearchLayer()
            }
        }
        val topBand = ComposeView(this).apply {
            setContent {
                // feature #133 WI-11 — the Search icon is shown UNLESS the VM reports the entry is hidden (a
                // non-searchable publication → Unsupported → hidesSearchEntry). A null onSearch omits the icon
                // (no dead control). feature #134 WI-5 — the top-bar More button (shown once chromeBookDetails
                // is populated) toggles the More popup; Details writes ReaderSheet.Details, Share launches share.
                val searchState = inBookSearchState.value
                val onSearch: (() -> Unit)? =
                    if (searchState != null && !searchState.hidesSearchEntry) ({ showSearchSheet.value = true }) else null
                // feature #131 WI-9 — the bilingual pill (only while ON; tap → setup sheet) + the More-menu
                // Bilingual row (Toggle when AI configured / Disabled "Configure AI provider first" when not),
                // supplied only for an EPUB book with a built controller (no dead control on non-EPUB).
                val bili = bilingualUiState.value
                val bilingualReachable = bilingualController != null
                EpubTopBand(
                    model = chromeModel,
                    theme = chromeTheme.value,
                    onBack = { finish() },
                    chromeState = chromeState,
                    bookDetails = chromeBookDetails.value,
                    onShareBook = ::shareBookFile,
                    onSearch = onSearch,
                    // feature #135 WI-7 — the top-bar bookmark toggle (filled/outline by presence).
                    isCurrentBookmarked = isCurrentBookmarked.value,
                    onToggleBookmark = ::toggleCurrentBookmark,
                    pillSlot = if (bilingualReachable && bili.enabled) {
                        {
                            androidx.compose.foundation.layout.Box(
                                Modifier.clickable { showBilingualSetup.value = true },
                            ) {
                                com.vreader.app.bilingual.BilingualPill(theme = chromeTheme.value, language = bili.targetLanguage)
                            }
                        }
                    } else null,
                    bilingualMoreRow = if (!bilingualReachable) null
                        else if (!bili.aiConfigured) com.vreader.app.reader.chrome.BilingualMoreRow.NeedsConfig
                        else com.vreader.app.reader.chrome.BilingualMoreRow.Ready(
                            on = bili.enabled,
                            languageKey = bili.targetLanguage.key,
                            onToggle = { on -> onBilingualToggle(on) },
                        ),
                )
                BilingualSheets()
            }
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
                    onLayout = { v -> val o = store.nextSeq(); container.appScope.launch { store.setLayout(v, o) } },
                    onFontFamily = { v -> val o = store.nextSeq(); container.appScope.launch { store.setFontFamily(v, o) } },
                    onFontSize = { v -> val o = store.nextSeq(); container.appScope.launch { store.setFontSize(v, o) } },
                    onLineSpacing = { v -> val o = store.nextSeq(); container.appScope.launch { store.setLineSpacing(v, o) } },
                    onMargin = { v -> val o = store.nextSeq(); container.appScope.launch { store.setMargin(v, o) } },
                    onDismiss = { showDisplaySheet.value = false },
                )
            }
        }
    }

    /** feature #133 WI-11 — the in-book search sheet overlay (a ModalBottomSheet in its own window). Renders
     *  ONLY while [showSearchSheet] is set (open-only, so the closed state leaves the fragment fully
     *  touch-through). Driven by the per-session VM's live Readium search state; a tapped hit resolves through
     *  [jumpToSearchHit] (Locator.fromJSON → nav.go; Succeeded dismisses, Failed keeps it open — no error
     *  surface). Dismiss disposes the live Readium SearchIterator (closeAllEpubCursors) via the VM's onDismiss. */
    @androidx.compose.runtime.Composable
    private fun InBookSearchLayer() {
        val show by showSearchSheet
        if (!show) return
        val vm = inBookSearchVm ?: return
        val screen by vm.state.collectAsStateWithLifecycle()
        InBookSearchSheet(
            theme = chromeTheme.value,
            bookTitle = chromeModel.value.title,
            state = screen,
            query = screen.query,
            onQueryChange = vm::onQueryChange,
            onPickRecent = vm::onPickRecent,
            // The tapped hit → the live Readium-locator jump. The WI-9 sheet's onJump is NON-suspend
            // (JumpResult returns synchronously), and nav.go itself is synchronous here, so the result is
            // authoritative (Succeeded dismisses via the sheet's dismiss-on-success; Failed keeps it open).
            onJump = ::jumpToSearchHit,
            onLoadMore = vm::loadMore,
            onDismiss = ::dismissInBookSearch,
        )
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

    // feature #135 WI-7 test hooks — assert the bookmark wiring against the live host without driving Compose
    // gestures (the live toggle-tap + list-tap + fresh-process reopen ride WI-9 acceptance).
    /** Whether the current reading position is bookmarked (the top-bar filled/outline state). */
    @androidx.annotation.VisibleForTesting
    fun isCurrentBookmarkedForTest(): Boolean = isCurrentBookmarked.value

    /** The projected Bookmarks-tab rows the sheet renders. */
    @androidx.annotation.VisibleForTesting
    fun bookmarkRowsForTest(): List<BookmarkRowItem> = bookmarkRows.value

    /** Toggle the bookmark at the current position through the SAME seam the top-bar button uses. */
    @androidx.annotation.VisibleForTesting
    fun toggleCurrentBookmarkForTest() = toggleCurrentBookmark()

    /** Jump to a bookmark through the SAME canonical-reconstruction seam the sheet uses; returns the
     *  JumpResult so a connected test can assert the fresh-process reconstruction landed (Succeeded) and,
     *  with an unresolvable canonical, that a Failed leaves the sheet open. */
    @androidx.annotation.VisibleForTesting
    fun jumpToBookmarkForTest(record: BookmarkRecord): JumpResult = jumpToBookmark(record)

    /** Test hook (feature #129 WI-5): the background ARGB the live navigator has *accepted/computed*
     *  for its EpubSettings (the applied theme background), or null before the navigator/settings exist.
     *  Proves the Display setting reached and was resolved by the live EpubNavigatorFragment — it does
     *  NOT assert the WebView painted that pixel (a CSS/pixel assertion would; that's WI-8 acceptance). */
    @androidx.annotation.VisibleForTesting
    fun appliedBackgroundArgb(): Int? = navigator?.settings?.value?.backgroundColor?.int

    /** Test hook (feature #137 WI-3): the overflow mode the live navigator has *resolved* — `true` when
     *  Readium is scrolling (layout==Scroll), `false` when paginated (layout==Paged), or null before the
     *  navigator/settings exist. Proves the layout toggle reached and was resolved by the live
     *  EpubNavigatorFragment (scroll↔paged overflow), not that the WebView repainted the columns. */
    @androidx.annotation.VisibleForTesting
    fun appliedScroll(): Boolean? = navigator?.settings?.value?.scroll

    /** Test hook (feature #137 WI-3): advance one page/screen forward through the SAME navigator seam
     *  Readium's native horizontal page-turn uses; returns Readium's Boolean (false at the last page).
     *  Lets a connected test drive a real page turn and assert `currentLocator` (position/progress)
     *  advanced on the turn — the Gate-2 High-4 requirement. */
    @androidx.annotation.VisibleForTesting
    fun goForwardForTest(): Boolean = navigator?.goForward(false) ?: false

    /** Test hook (feature #137 WI-3): a comparable position key for the CURRENT reading position —
     *  `href#progression` (within-resource, present as soon as a page renders in paginated mode; a
     *  horizontal page turn changes progression or href). Proves a page turn advanced `currentLocator`
     *  (the save/progress feed) without depending on the book-level `totalProgression`, which Readium
     *  may recompute lazily after a reflow. Null before the navigator has rendered. */
    @androidx.annotation.VisibleForTesting
    fun currentPositionKeyForTest(): String? {
        val loc = navigator?.currentLocator?.value ?: return null
        val href = loc.href.toString().takeIf { it.isNotBlank() } ?: return null
        return "$href#${loc.locations.progression ?: 0.0}"
    }

    // feature #133 WI-11 test hooks — assert the in-book search wiring against the live host + live Readium
    // publication without driving Compose gestures (the live Search-icon / sheet taps ride WI-12 acceptance
    // on the real CJK EPUB).
    /** The current in-book search screen state (query + recents + the content region), or null until the VM
     *  is built (which happens once the publication opens). Proves the per-session VM exists for THIS book. */
    @androidx.annotation.VisibleForTesting
    fun inBookSearchStateForTest(): com.vreader.app.search.InBookSearchScreenState? = inBookSearchState.value

    /** Drive a live Readium search for [query] through the SAME seam the sheet's field uses. */
    @androidx.annotation.VisibleForTesting
    fun runSearchForTest(query: String) { inBookSearchVm?.onQueryChange(query) }

    /** Jump to a search hit through the SAME seam the sheet uses; returns the JumpResult so a connected test
     *  can assert a Readium-locator hit lands (Succeeded) and a null/malformed-locator hit fails gracefully
     *  (Failed) without crashing. */
    @androidx.annotation.VisibleForTesting
    fun jumpToSearchHitForTest(hit: InBookHit): JumpResult = jumpToSearchHit(hit)

    /** Dismiss the search sheet through the SAME seam (VM.onDismiss → closeAllEpubCursors), so a test can
     *  assert the VM survives + returns to Idle (the live Readium SearchIterator was disposed, no leak). */
    @androidx.annotation.VisibleForTesting
    fun dismissSearchForTest() = dismissInBookSearch()

    /** The number of times the per-session search VM has been constructed — a test seam proving exactly ONE
     *  is built per reader open (never a fresh one per query/recomposition — the WI-8 one-per-session contract). */
    @androidx.annotation.VisibleForTesting
    fun inBookSearchVmBuildCountForTest(): Int = inBookSearchVmBuildCount

    // feature #131 WI-7b test hooks — assert the bilingual DOM injection against the live navigator
    // without driving Compose gestures (the live More-menu enable ride WI-9 acceptance). The seams
    // drive the SAME controller/provider the production position observer uses.

    /** Whether the EPUB bilingual controller was built for this book (EPUB + reachable). */
    @androidx.annotation.VisibleForTesting
    fun bilingualControllerBuiltForTest(): Boolean = bilingualController != null

    /** Enable bilingual for this book (the store/VM seam the connected test drives — the More-menu
     *  entry is WI-9), then apply the interlinear for the current resource. Awaits BOTH the requested
     *  language AND enabled before applying (so the apply uses the intended language, not a stale one)
     *  and drives the controller directly (deterministic vs the scheduled job). Returns after the apply. */
    @androidx.annotation.VisibleForTesting
    suspend fun enableBilingualForTest(languageKey: String? = null) {
        val vm = bilingualViewModel ?: return
        val controller = bilingualController ?: return
        val provider = bilingualProvider ?: return
        languageKey?.let { vm.setTargetLanguage(it) }
        vm.setEnabled(true)
        awaitBilingualState(enabled = true, language = languageKey)
        controller.bumpSession()   // fresh session for the enable (matches WI-9 wiring)
        val nav = navigator ?: return
        val unit = provider.unitForHref(nav.currentLocator.value.href.toString()) ?: return
        bilingualUnit = unit
        val lang = vm.state.value.targetLanguage.key
        bilingualLang = lang
        controller.apply(unit, lang)
    }

    /** Disable bilingual + clear the decorations. */
    @androidx.annotation.VisibleForTesting
    suspend fun disableBilingualForTest() {
        val vm = bilingualViewModel ?: return
        vm.setEnabled(false)
        awaitBilingualState(enabled = false, language = null)
        bilingualController?.shutdown()
        bilingualUnit = null
        bilingualLang = null
    }

    /** Force a probe-gated re-apply for the current resource through the SAME controller seam (proves the
     *  recreation re-apply restores from cache with zero provider calls, no dup). */
    @androidx.annotation.VisibleForTesting
    suspend fun reapplyBilingualForTest() {
        val vm = bilingualViewModel ?: return
        val controller = bilingualController ?: return
        val provider = bilingualProvider ?: return
        val nav = navigator ?: return
        val unit = provider.unitForHref(nav.currentLocator.value.href.toString()) ?: return
        controller.reapplyIfNeeded(unit, vm.state.value.targetLanguage.key, controller.expectedCountFor(unit))
    }

    /** The CURRENT decoration count in the live resource DOM (via the probe script) — proves the
     *  inject/clear ran against the real WebView. -1 when the controller/nav is absent. */
    @androidx.annotation.VisibleForTesting
    suspend fun bilingualDecorationCountForTest(): Int {
        val nav = navigator ?: return -1
        val raw = evalOnMain(nav, com.vreader.app.bilingual.EpubBilingualJs.decorationCountScript)
        return com.vreader.app.bilingual.EpubBilingualJs.parseCountResult(raw, default = -1)
    }

    /** Await the VM's serial command consumer flipping BOTH `enabled` to [enabled] AND (when non-null)
     *  the target [language]. Throws on timeout so a test fails explicitly rather than silently applying
     *  with stale state (Gate-4 Low). */
    private suspend fun awaitBilingualState(enabled: Boolean, language: String?) {
        val vm = bilingualViewModel ?: return
        for (i in 0 until 150) {
            val s = vm.state.value
            if (s.enabled == enabled && (language == null || s.targetLanguage.key == language)) return
            kotlinx.coroutines.delay(20)
        }
        throw AssertionError("bilingual state (enabled=$enabled, language=$language) not reached in time")
    }

    /** Enumerate the CURRENT resource's leaf blocks against the live navigator (the SAME enumerate
     *  the controller runs) — so a connected test can seed a cache row of the exact block count and
     *  then prove the enable restores from cache with ZERO provider calls. */
    @androidx.annotation.VisibleForTesting
    suspend fun bilingualEnumerateForTest(): List<com.vreader.app.bilingual.EpubBilingualJs.Block> {
        val nav = navigator ?: return emptyList()
        val raw = evalOnMain(nav, com.vreader.app.bilingual.EpubBilingualJs.enumScript)
        return com.vreader.app.bilingual.EpubBilingualJs.parseEnumResult(raw).blocks
    }

    /** The current EPUB resource href (for building the epubHref unit a test seeds the cache under). */
    @androidx.annotation.VisibleForTesting
    fun bilingualCurrentHrefForTest(): String? = navigator?.currentLocator?.value?.href?.toString()

    /** The bilingual VM's current target-language key (the cache-row language a test seeds under). */
    @androidx.annotation.VisibleForTesting
    fun bilingualTargetLanguageForTest(): String? = bilingualViewModel?.state?.value?.targetLanguage?.key

    /** feature #131 WI-9 — whether the VM's `translationsByUnit` carries [unit] (proves the controller's
     *  `onEpubBlocksEnumerated` fed the VM render state for the EPUB unit — finding a). */
    @androidx.annotation.VisibleForTesting
    fun bilingualVmTranslationsContainsForTest(unit: com.vreader.app.bilingual.TranslationUnitId): Boolean =
        bilingualViewModel?.state?.value?.translationsByUnit?.containsKey(unit) == true

    /** feature #131 WI-9 — drive the mid-book language-change reconcile deterministically: set the VM's
     *  target language then run the controller reconcile entry for the current resource (the SAME seam the
     *  production language-change observer uses). Awaits the language flip + the reconcile (finding b). */
    @androidx.annotation.VisibleForTesting
    suspend fun reconcileBilingualLanguageForTest(languageKey: String) {
        val vm = bilingualViewModel ?: return
        val controller = bilingualController ?: return
        val provider = bilingualProvider ?: return
        vm.setTargetLanguage(languageKey)
        awaitBilingualState(enabled = true, language = languageKey)
        val nav = navigator ?: return
        val unit = provider.unitForHref(nav.currentLocator.value.href.toString()) ?: return
        val ok = controller.reconcileLanguageChange(unit, languageKey)
        if (ok) { bilingualUnit = unit; bilingualLang = languageKey }
    }

    companion object {
        const val EXTRA_FINGERPRINT_KEY = "fingerprintKey"
        private const val READER_TAG = "reader-navigator"

        fun intent(context: android.content.Context, fingerprintKey: String): Intent =
            Intent(context, ReaderActivity::class.java).putExtra(EXTRA_FINGERPRINT_KEY, fingerprintKey)
    }
}

// ---- feature #135 WI-7 — shared pure host wiring helpers (package-shared across the 5 reader hosts) ----

/**
 * feature #135 WI-7 — the deterministic date renderer every host uses for its bookmark rows. A fixed
 * medium-date format in the device's default zone (a bookmark's date is a user-facing "when did I mark
 * this" label — day-precision, locale-formatted). Extracted here so it is built ONCE per host and shared
 * across every projected row (and is the same shape the WI-4 [BookmarkPresentation] projection consumes).
 */
fun bookmarkDateRenderer(): BookmarkDateRenderer =
    BookmarkDateRenderer(
        ZoneId.systemDefault(),
        DateTimeFormatter.ofLocalizedDate(java.time.format.FormatStyle.MEDIUM).withLocale(Locale.getDefault()),
    )

/**
 * feature #135 WI-7 — map an EPUB reader's LIVE reading position (extracted from the navigator's Readium
 * `currentLocator` as plain values so this stays pure/JVM-testable — the same thin-Readium-hop posture as
 * [tocPositions]) to a canonical vreader [CanonicalLocator]. This is the equality basis for the top-bar
 * toggle's presence read + create (via `profileKeyFor`), and the canonical the reconstructor turns back
 * into a Readium locator on jump. A bookmark is a POSITION, not a selection → NO text quote is carried
 * (distinct from a highlight, which the [EpubAnnotationMapper] fills). Mirrors that mapper's canonical
 * construction (href + progression + totalProgression + cfi), minus the text.
 */
fun epubBookmarkLocator(
    href: String,
    progression: Double?,
    totalProgression: Double?,
    cfi: String?,
    contentSHA256: String,
    fileByteCount: Long,
    format: String,
): CanonicalLocator = CanonicalLocator(
    contentSHA256 = contentSHA256,
    fileByteCount = fileByteCount,
    format = format,
    href = href,
    progression = progression,
    totalProgression = totalProgression,
    cfi = cfi?.takeUnless { it.isBlank() },
)

/**
 * feature #135 WI-7 — project a host's stored [BookmarkRecord] list into the WI-6 sheet's
 * `List<BookmarkRowItem>`. Each record is paired with its per-format [BookmarkPresentation.bookmarkRow]
 * projection: EPUB/AZW3 chapter/page from the prevalidated [tocIndex] (built ONCE per host from its TOC),
 * PDF `p. N`, TXT/MD a bounded snippet via the host-supplied [previewProvider]. Order is preserved from the
 * DAO (createdAt-ordered `observeBookmarks`). Pure/JVM-testable — no Android/Compose/IO.
 */
fun bookmarkRowItems(
    records: List<BookmarkRecord>,
    format: vreader.contracts.BookFormat,
    tocIndex: BookmarkTocIndex?,
    previewProvider: BookmarkPreviewProvider?,
    dateRenderer: BookmarkDateRenderer,
): List<BookmarkRowItem> = records.map { record ->
    BookmarkRowItem(
        record = record,
        ui = BookmarkPresentation.bookmarkRow(record, format, tocIndex, previewProvider, dateRenderer),
    )
}
