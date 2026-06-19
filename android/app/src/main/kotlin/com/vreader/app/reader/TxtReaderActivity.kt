// Purpose: plain-text + Markdown reader host — feature #111 (TXT) + #112 (MD), #110
// Phase 3. Renders a decoded .txt/.md in a Compose LazyColumn over the WI-1 TxtDocument
// chunk ranges, with the shared reader chrome (vreader-reader.jsx subset). For BookFormat.md
// each line-chunk renders through MarkdownRenderer (styled AnnotatedString); .txt renders
// the chunk verbatim. WI-3 adds resume via the LEGACY locator
// path (NOT the Readium bridge): save the top-visible chunk's charOffsetUTF16 as a
// VReaderLocator.wrapLegacy envelope (debounced + onStop flush) and restore it via
// ResumeResolver → Canonical → chunkForOffset.
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
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import vreader.contracts.BookFormat
import vreader.contracts.Locator
import java.io.File

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
                when (val s = state) {
                    is TxtUiState.Failed -> LaunchedEffect(Unit) { finish() }
                    is TxtUiState.Loading -> TxtReaderScaffold("", ::finish) {}
                    is TxtUiState.Loaded -> {
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
                        TxtReaderScaffold(s.title, ::finish) {
                            TxtBody(s.document, listState, s.book.originalFormat)
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

    companion object {
        const val EXTRA_FINGERPRINT_KEY = "fingerprintKey"

        fun intent(context: android.content.Context, fingerprintKey: String): android.content.Intent =
            android.content.Intent(context, TxtReaderActivity::class.java)
                .putExtra(EXTRA_FINGERPRINT_KEY, fingerprintKey)
    }
}

/** Shared reader chrome (back + title) over the reading body — the vreader-reader.jsx subset. */
@Composable
private fun TxtReaderScaffold(title: String, onBack: () -> Unit, body: @Composable () -> Unit) {
    Column(Modifier.fillMaxSize().background(VReaderColors.Background).systemBarsPadding()) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                Icons.AutoMirrored.Filled.ArrowBack,
                contentDescription = "Back",
                tint = VReaderColors.Ink,
                modifier = Modifier.size(28.dp).clickable(onClick = onBack).padding(2.dp),
            )
            Text(title, Modifier.padding(start = 8.dp), color = VReaderColors.Ink, fontSize = 16.sp, maxLines = 1)
        }
        body()
    }
}

/** The reading body — a LazyColumn over the document's chunk ranges (serif, reading margins).
 *  For BookFormat.md each chunk renders through MarkdownRenderer (styled); else verbatim. */
@Composable
private fun TxtBody(document: TxtDocument, listState: LazyListState, format: BookFormat) {
    val isMarkdown = format == BookFormat.md
    LazyColumn(
        Modifier.fillMaxSize(),
        state = listState,
        contentPadding = PaddingValues(horizontal = 24.dp, vertical = 16.dp),
    ) {
        // Count-based: indices on demand (a newline-dense 14MB file can be 100k+ chunks).
        items(count = document.chunkCount, key = { it }) { i ->
            val raw = document.textForChunk(i).toString()
            Text(
                // .md → styled markdown spans; .txt → the raw text verbatim (markers literal).
                text = if (isMarkdown) MarkdownRenderer.render(raw) else AnnotatedString(raw),
                color = VReaderColors.Ink,
                fontFamily = VReaderFonts.Serif,
                fontWeight = FontWeight.Normal,
                fontSize = 18.sp,
                lineHeight = 29.sp,
            )
        }
    }
}
