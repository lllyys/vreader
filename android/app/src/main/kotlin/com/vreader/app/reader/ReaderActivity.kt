// Purpose: EPUB reader host — feature #106 WI-9 (#1745). Hosts Readium's
// EpubNavigatorFragment in scroll mode (Spike-B-verified), opening the stored EPUB
// via the WI-5 BookOpener and saving/restoring the reading position through the
// WI-6 ReadiumLocatorBridge + ResumeResolver → Room. Minimal chrome (back + title)
// — the foundation-bar subset of dev-docs/designs/.../vreader-reader.jsx; the rich
// reader controls (TOC/AI/highlights/settings) are Phase-3 features.
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
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.fragment.app.commitNow
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.withStarted
import com.vreader.app.VReaderApp
import com.vreader.app.annotations.AnnotationColor
import com.vreader.app.annotations.AnnotationsRepository
import com.vreader.app.annotations.EpubAnnotationMapper
import com.vreader.app.annotations.PopoverMode
import com.vreader.app.annotations.SelectionPopover
import com.vreader.app.annotations.SelectionPopoverActions
import com.vreader.app.annotations.SelectionPopoverViewModel
import com.vreader.app.data.Book
import com.vreader.app.data.LibraryRepository
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
    private lateinit var titleView: TextView

    // feature #123 — in-reader highlighting
    private var highlightController: ReaderHighlightController? = null
    private val popoverVm = SelectionPopoverViewModel()
    // the Readium locator of the live selection (set when the popover opens for a fresh selection)
    private var pendingSelection: Locator? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // The navigator fragment can't be restored before its FragmentFactory is set,
        // and we set the factory only after the async open completes — so always start
        // fresh (the saved reading position is what actually persists across recreation).
        super.onCreate(null)

        val key = intent.getStringExtra(EXTRA_FINGERPRINT_KEY)
        if (key == null) { finish(); return }
        setContentView(buildChrome())

        lifecycleScope.launch {
            val loaded = repository.findBook(key)
            if (loaded?.localFilePath == null) { finish(); return@launch }
            book = loaded
            titleView.text = loaded.title

            val pub = try {
                BookOpener(this@ReaderActivity).open(File(loaded.localFilePath!!))
            } catch (e: BookOpenException) {
                finish(); return@launch
            }
            publication = pub

            val initial = computeInitialLocator(key)
            val factory = EpubNavigatorFactory(pub)
            // Attach only when the activity is at least STARTED AND its fragment state
            // isn't already saved — `commitNow` against a state-saved manager throws
            // IllegalStateException. If we can't commit, abort (the publication is
            // released in onDestroy; the activity recreates fresh on return).
            val nav: EpubNavigatorFragment? = withStarted {
                if (supportFragmentManager.isStateSaved) return@withStarted null
                supportFragmentManager.fragmentFactory = factory.createFragmentFactory(
                    initialLocator = initial,
                    initialPreferences = EpubPreferences(scroll = true),
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
            observePosition(nav, loaded)
            observeHighlights(loaded, controller)
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

    private fun copySelection() {
        val text = pendingSelection?.text?.highlight ?: return
        val clip = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clip.setPrimaryClip(ClipData.newPlainText("vreader", text))
        clearSelectionAndDismiss()
    }

    private fun shareSelection() {
        val text = pendingSelection?.text?.highlight ?: return
        val send = Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, text) }
        startActivity(Intent.createChooser(send, null))
        clearSelectionAndDismiss()
    }

    private fun clearSelectionAndDismiss() {
        highlightController?.clearSelection()
        pendingSelection = null
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

    /** Save the current Readium position as a VReaderLocator envelope (debounced steady-state). */
    private fun observePosition(nav: EpubNavigatorFragment, current: Book) {
        lifecycleScope.launch {
            nav.currentLocator
                .drop(1)            // skip the initial emission
                .debounce(1_000)
                .collect { locator -> persist(locator, current) }
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

    /** Minimal reader chrome — a back affordance + the book title over the navigator. */
    private fun buildChrome(): View {
        val ink = 0xFF1D1A14.toInt()
        val bg = 0xFFF7F4EE.toInt()
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(bg) }

        val bar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(8), dp(10), dp(16), dp(10))
            setBackgroundColor(bg)
        }
        val back = TextView(this).apply {
            text = "‹"
            textSize = 28f
            setTextColor(ink)
            setPadding(dp(12), 0, dp(12), 0)
            setOnClickListener { finish() }
        }
        titleView = TextView(this).apply {
            textSize = 16f
            setTextColor(ink)
            maxLines = 1
            setPadding(dp(8), 0, 0, 0)
        }
        bar.addView(back)
        bar.addView(titleView)

        val frame = FrameLayout(this).apply { id = View.generateViewId() }
        containerId = frame.id

        // the navigator fragment + the floating selection-popover overlay share a stack.
        val popoverOverlay = ComposeView(this).apply { setContent { PopoverOverlay() } }
        val readerStack = FrameLayout(this).apply {
            addView(frame, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
            addView(popoverOverlay, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        }

        root.addView(bar, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
        root.addView(readerStack, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
        return root
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
                            else -> popoverVm.selectColor(c)
                        }
                    },
                    onHighlight = { createHighlight(popoverVm.state.value.activeColor, null) },
                    onNote = { popoverVm.beginNote() },
                    onCopy = { copySelection() },
                    onShare = { shareSelection() },
                    onRemove = { /* WI-4: edit/remove an existing highlight */ },
                    onNoteDraftChange = { popoverVm.updateNoteDraft(it) },
                    onSaveNote = {
                        val s = popoverVm.state.value
                        createHighlight(s.activeColor, s.noteDraft.ifBlank { null })
                    },
                    onCancelNote = { clearSelectionAndDismiss() },
                ),
                modifier = Modifier.offset(
                    x = with(androidx.compose.ui.platform.LocalDensity.current) { xPx.toDp() },
                    y = with(androidx.compose.ui.platform.LocalDensity.current) { yPx.toDp() },
                ),
            )
        }
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    /** Test hook: the current reading href, or null until the navigator has rendered. */
    @androidx.annotation.VisibleForTesting
    fun currentHref(): String? = navigator?.currentLocator?.value?.href?.toString()

    companion object {
        const val EXTRA_FINGERPRINT_KEY = "fingerprintKey"
        private const val READER_TAG = "reader-navigator"

        fun intent(context: android.content.Context, fingerprintKey: String): Intent =
            Intent(context, ReaderActivity::class.java).putExtra(EXTRA_FINGERPRINT_KEY, fingerprintKey)
    }
}
