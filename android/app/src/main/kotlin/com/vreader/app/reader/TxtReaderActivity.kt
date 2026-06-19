// Purpose: TXT reader host — feature #111 WI-2 (#110 Phase 3). Renders a decoded
// .txt in a Compose LazyColumn over the WI-1 TxtDocument chunk ranges, with the
// shared reader chrome (back + title) from vreader-reader.jsx (rule-51 reuse). Opens
// from app-private storage off the main thread. Resume (charOffsetUTF16 save/restore
// via the legacy ResumeResolver path) is WI-3.
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
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.VReaderApp
import com.vreader.app.ui.theme.VReaderColors
import com.vreader.app.ui.theme.VReaderFonts
import com.vreader.app.ui.theme.VReaderTheme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

private sealed interface TxtUiState {
    data object Loading : TxtUiState
    data object Failed : TxtUiState
    data class Loaded(val title: String, val document: TxtDocument) : TxtUiState
}

class TxtReaderActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val key = intent.getStringExtra(EXTRA_FINGERPRINT_KEY)
        if (key == null) { finish(); return }
        val container = (application as VReaderApp).container

        setContent {
            VReaderTheme {
                val state by produceState<TxtUiState>(TxtUiState.Loading, key) {
                    value = withContext(Dispatchers.IO) {
                        // A missing/unreadable file or any I/O error must take the
                        // failed-close path, not crash the activity.
                        runCatching {
                            val book = container.repository.findBook(key)
                            val path = book?.localFilePath
                            if (book == null || path == null) {
                                TxtUiState.Failed
                            } else {
                                val decoded = TxtDecoder.decode(File(path))
                                val document = TxtDocument.of(decoded.text)
                                container.repository.markOpened(key, System.currentTimeMillis())
                                TxtUiState.Loaded(book.title, document)
                            }
                        }.getOrDefault(TxtUiState.Failed)
                    }
                }
                when (val s = state) {
                    is TxtUiState.Failed -> LaunchedEffect(Unit) { finish() }   // side effect, not in render
                    is TxtUiState.Loading -> TxtReaderScaffold("", ::finish) {}
                    is TxtUiState.Loaded -> TxtReaderScaffold(s.title, ::finish) { TxtBody(s.document) }
                }
            }
        }
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
            Text(
                title,
                Modifier.padding(start = 8.dp),
                color = VReaderColors.Ink,
                fontSize = 16.sp,
                maxLines = 1,
            )
        }
        body()
    }
}

/** The reading body — a LazyColumn over the document's chunk ranges (serif, reading margins). */
@Composable
private fun TxtBody(document: TxtDocument) {
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 24.dp, vertical = 16.dp),
    ) {
        // Count-based: indices generated on demand (a newline-dense 14MB file can be
        // 100k+ chunks — don't allocate a boxed index list).
        items(count = document.chunkCount, key = { it }) { i ->
            Text(
                text = document.textForChunk(i).toString(),
                color = VReaderColors.Ink,
                fontFamily = VReaderFonts.Serif,
                fontWeight = FontWeight.Normal,
                fontSize = 18.sp,
                lineHeight = 29.sp,
            )
        }
    }
}
