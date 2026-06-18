// Purpose: EPUB reader host — feature #106 WI-9 (#1745). Hosts Readium's
// EpubNavigatorFragment in scroll mode (Spike-B-verified), opening the stored EPUB
// via the WI-5 BookOpener and saving/restoring the reading position through the
// WI-6 ReadiumLocatorBridge + ResumeResolver → Room. Minimal chrome (back + title)
// — the foundation-bar subset of dev-docs/designs/.../vreader-reader.jsx; the rich
// reader controls (TOC/AI/highlights/settings) are Phase-3 features.
package com.vreader.app.reader

import android.content.Intent
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.fragment.app.commitNow
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.withStarted
import com.vreader.app.VReaderApp
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

    private var containerId: Int = 0
    private var navigator: EpubNavigatorFragment? = null
    private var publication: Publication? = null   // host-owned; closed in onDestroy
    private var book: Book? = null
    private lateinit var titleView: TextView

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
                )
                supportFragmentManager.commitNow {
                    add(containerId, EpubNavigatorFragment::class.java, Bundle(), READER_TAG)
                }
                supportFragmentManager.findFragmentByTag(READER_TAG) as EpubNavigatorFragment
            }
            if (nav == null) { finish(); return@launch }
            navigator = nav
            repository.markOpened(key, System.currentTimeMillis())
            observePosition(nav, loaded)
        }
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

        root.addView(bar, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
        root.addView(frame, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
        return root
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
