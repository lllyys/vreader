// Purpose: feature #115 WI-2 (#110 Phase 3) — the PDF reader host (implements the committed
// design vreader-pdf-reader.jsx PdfContinuousReader). Opens the book's PDF via PdfDocument off
// the main thread → Loading / ProtectedOrUnsupported / Corrupt / Empty / Loaded. Loaded renders
// a LazyColumn of page items on a neutral viewer backdrop; each page lazily renders its ONE
// bitmap (keyed on page index + measured width). Off-screen page bitmaps are left for GC — they
// are NOT manually recycled (recycling at the composable boundary races Compose's draw and
// crashes); lazy per-visible render + a capped width bounds memory. A
// floating "Page N of M" pill tracks the top-visible page; the shared reader chrome (back
// "Library" + serif title + PDF tag). The PdfDocument is closed in a DisposableEffect.
// Resume (save/restore the page index) lands in WI-3.
package com.vreader.app.reader

import android.graphics.Bitmap
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBackIos
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import com.vreader.app.data.Book
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.drop
import androidx.compose.runtime.snapshotFlow
import vreader.contracts.Locator
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.VReaderApp
import com.vreader.app.ui.theme.VReaderFonts
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
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

    // Hoisted so onStop can flush the latest page synchronously (mirrors TxtReaderActivity).
    private var flushPosition: (() -> Unit)? = null

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
            when (val s = state) {
                is PdfUiState.Loading -> PdfScaffold("", ::finish) { CenterMessage("Opening…") }
                is PdfUiState.Protected -> PdfScaffold("", ::finish) {
                    CenterMessage("This PDF is protected", "It's password-protected or uses a security scheme this reader can't open.")
                }
                is PdfUiState.Corrupt -> PdfScaffold("", ::finish) {
                    CenterMessage("Couldn’t open this PDF", "The file appears to be damaged or uses a format the reader can’t decode.")
                }
                is PdfUiState.Empty -> PdfScaffold("", ::finish) {
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
                    PdfContinuousReader(s.title, s.document, listState, ::finish)
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

// Neutral viewer backdrop the page bitmaps float on (distinct from the reader paper tone).
private val PdfBackdrop = Color(0xFFCDC7BA)

/** Reader chrome (back + serif title + PDF tag) over the body, on the viewer backdrop. */
@Composable
private fun PdfScaffold(title: String, onBack: () -> Unit, body: @Composable () -> Unit) {
    Column(Modifier.fillMaxSize().background(PdfBackdrop).systemBarsPadding()) {
        Row(
            Modifier.fillMaxWidth().background(Color(0xFFF7F4EE)).padding(horizontal = 4.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // The back affordance is one ≥48dp clickable element (icon + "Library").
            Row(
                Modifier.heightIn(min = 48.dp).clip(RoundedCornerShape(8.dp)).clickable(onClickLabel = "Library", onClick = onBack).padding(horizontal = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.AutoMirrored.Filled.ArrowBackIos, contentDescription = null, tint = Color(0xFF8C2F2F), modifier = Modifier.size(18.dp))
                Text("Library", color = Color(0xFF8C2F2F), fontSize = 14.sp, fontWeight = FontWeight.Medium)
            }
            Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(title, color = Color(0xFF1D1A14), fontFamily = VReaderFonts.Serif, fontSize = 13.5.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                    Text(" PDF", color = Color(0xFF7A6A4A), fontSize = 9.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(start = 6.dp))
                }
            }
            Box(Modifier.size(60.dp))
        }
        Box(Modifier.weight(1f)) { body() }
    }
}

@Composable
private fun PdfContinuousReader(title: String, document: PdfDocument, listState: androidx.compose.foundation.lazy.LazyListState, onBack: () -> Unit) {
    Box(Modifier.fillMaxSize()) {
        PdfScaffold(title, onBack) {
            LazyColumn(
                Modifier.fillMaxSize(),
                state = listState,
                contentPadding = PaddingValues(horizontal = 18.dp, vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                items(count = document.pageCount, key = { it }) { i -> PdfPage(document, i) }
            }
        }
        // Floating "Page N of M" pill — tracks the top-visible page (1-based).
        PageProgressPill(
            page = listState.firstVisibleItemIndex + 1,
            total = document.pageCount,
            modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 24.dp),
        )
    }
}

/** One PDF page — lazily renders ONE bitmap at the measured width (only visible pages render;
 *  off-screen page bitmaps are reclaimed by GC when their composable + reference go away).
 *  NOTE: synchronous `Bitmap.recycle()` in a DisposableEffect was rejected — it races Compose's
 *  draw at teardown/recompose ("trying to use a recycled bitmap"). Lazy per-visible render + a
 *  capped width bounds memory; GC handles reclamation safely. */
@Composable
private fun PdfPage(document: PdfDocument, pageIndex: Int) {
    val density = LocalDensity.current
    // Cap the render width to the typical phone content width (the LazyColumn fills width).
    val widthPx = remember(density) { with(density) { 360.dp.toPx() }.toInt().coerceAtLeast(1) }
    val bitmap by produceState<Bitmap?>(initialValue = null, document, pageIndex, widthPx) {
        value = runCatching { document.renderPage(pageIndex, widthPx) }.getOrNull()
    }
    Box(
        Modifier.fillMaxWidth().aspectRatio(if (bitmap != null) bitmap!!.width.toFloat() / bitmap!!.height else 0.72f)
            .background(Color.White),
        contentAlignment = Alignment.Center,
    ) {
        bitmap?.let { Image(it.asImageBitmap(), contentDescription = "Page ${pageIndex + 1}", modifier = Modifier.fillMaxSize()) }
    }
}

@Composable
private fun PageProgressPill(page: Int, total: Int, modifier: Modifier = Modifier) {
    Row(
        modifier.clip(RoundedCornerShape(100.dp)).background(Color(0xC7282014)).padding(horizontal = 13.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text("Page $page", color = Color(0xFFF3EDE0), fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
        Text(" of $total", color = Color(0x80F3EDE0), fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun CenterMessage(title: String, detail: String? = null) {
    Column(
        Modifier.fillMaxSize().padding(40.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(title, color = Color(0xFF1D1A14), fontFamily = VReaderFonts.Serif, fontSize = 18.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
        if (detail != null) {
            Text(detail, color = Color(0xFF7A6A4A), fontSize = 13.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp))
        }
    }
}
