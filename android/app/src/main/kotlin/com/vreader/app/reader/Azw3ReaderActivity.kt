// Purpose: the AZW3/MOBI/KF8 (Kindle) reader screen. Hosts an Android WebView running the
// security-patched foliate-js bundle (via Azw3Document + FoliateBridge) in the committed shared
// reader chrome — design `vreader-fidelity-v1/project/vreader-reader.jsx` (the SAME chrome subset
// TxtReaderActivity / PdfReaderActivity implement; per feature #106 the iOS-authored fidelity bundle
// is a valid Android design source — rule 51). Persists the reading position (conflated, latest-wins)
// + flushes on onStop, and recreates the WebView on render-process death.
// Feature #126 WI-4 + WI-6. Routing from MainActivity; AZW3 import already exists.
package com.vreader.app.reader

import android.os.Bundle
import android.webkit.WebView
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
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
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import com.vreader.app.VReaderApp
import com.vreader.app.data.Book
import com.vreader.app.reader.foliate.Azw3DocState
import com.vreader.app.reader.foliate.Azw3Document
import com.vreader.app.reader.foliate.Azw3LocatorBridge
import com.vreader.app.reader.foliate.FoliateMessage
import com.vreader.app.ui.theme.VReaderFonts
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.launch
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
                    Azw3ReaderHost(
                        book = o.book,
                        bookFile = File(o.path),
                        restore = o.restore,
                        onBack = ::finish,
                        onRelocate = { rel -> enqueueSave(o.book, rel) },
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

/** The reader screen: the WebView fills the body; a state overlay covers it until Loaded. */
@Composable
private fun Azw3ReaderHost(
    book: Book,
    bookFile: File,
    restore: VReaderLocator?,
    onBack: () -> Unit,
    onRelocate: (FoliateMessage.Relocate) -> Unit,
) {
    val context = LocalContext.current
    var reloadKey by remember { mutableIntStateOf(0) }
    // Latest known position, for render-death resume (starts at the persisted restore point).
    var resume by remember { mutableStateOf(restore) }

    // A fresh WebView + document each reloadKey (render-process-death recovery).
    val holder = remember(reloadKey) { Holder(WebView(context), bookFile, context) }
    val state by holder.document.state.collectAsState()

    DisposableEffect(holder) {
        val doc = holder.document
        doc.onRelocate = { rel ->
            onRelocate(rel)
            resume = Azw3LocatorBridge.toEnvelope(rel, book.contentSHA256, book.fileByteCount)
        }
        doc.onRenderProcessGone = { reloadKey++ }
        onDispose { doc.destroy() }
    }

    // Holder-scoped: the collector lives exactly as long as this holder (cancelled on reload/dispose).
    LaunchedEffect(holder) { holder.document.run(resume) }

    ReaderScaffold(book.title, onBack) {
        Box(Modifier.fillMaxSize().testTag("azw3-webview")) {
            // Keyed on reloadKey so render-death recovery swaps in the NEW WebView node (not the dead one).
            // foliate renders in scrolled mode — the WebView receives touches directly so the reader scrolls.
            key(reloadKey) { AndroidView(factory = { holder.webView }, modifier = Modifier.fillMaxSize()) }
            when (state) {
                Azw3DocState.Loading -> Centered { CircularProgressIndicator() }
                Azw3DocState.WebViewUnsupported -> Centered { Text("Update Android System WebView to read this format.", color = Ink) }
                Azw3DocState.Corrupt -> Centered { Text("This book can’t be opened.", color = Ink) }
                Azw3DocState.Empty -> Centered { Text("This book has no readable content.", color = Ink) }
                is Azw3DocState.Loaded -> Unit // the WebView shows the book
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

@Composable
private fun Centered(content: @Composable () -> Unit) =
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { content() }
