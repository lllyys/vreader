// Purpose: feature #115 WI-2 / #129 WI-7 (#110 Phase 3) — the PDF reader Compose surface (implements
// the committed design vreader-pdf-reader.jsx PdfContinuousReader). Extracted from PdfReaderActivity
// (WI-7 kept the Activity under the ~300-line limit). Renders a LazyColumn of page items on the
// theme-derived viewer backdrop (feature #129 WI-7: the backdrop = the global ReaderSettingsStore
// theme background; PDF applies NO other typography since it's rasterized — see PdfDisplayBackdrop).
// Each page lazily renders its ONE bitmap (keyed on page index + measured width); off-screen page
// bitmaps are left for GC — NOT manually recycled (recycling at the composable boundary races
// Compose's draw and crashes); lazy per-visible render + a capped width bounds memory. A floating
// "Page N of M" pill tracks the top-visible page; the shared reader chrome (back "Library" + serif
// title + PDF tag). The `backdrop` is threaded by the Activity — mandatory, no fallback (WI-7).
//
// @coordinates-with: PdfReaderActivity.kt (hosts these composables, threads the theme backdrop +
//   PdfDocument + list state), PdfDocument.kt (the renderer), PdfDisplayBackdrop.kt (the mapping).
package com.vreader.app.reader

import android.graphics.Bitmap
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
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBackIos
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
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
import com.vreader.app.ui.theme.VReaderFonts

/** Reader chrome (back + serif title + PDF tag) over the body, on the theme-derived viewer [backdrop]
 *  (feature #129 WI-7 — the backdrop is always the global theme background; no fallback). */
@Composable
internal fun PdfScaffold(title: String, onBack: () -> Unit, backdrop: Color, body: @Composable () -> Unit) {
    Column(Modifier.fillMaxSize().background(backdrop).systemBarsPadding()) {
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
internal fun PdfContinuousReader(title: String, document: PdfDocument, listState: LazyListState, backdrop: Color, onBack: () -> Unit) {
    Box(Modifier.fillMaxSize()) {
        PdfScaffold(title, onBack, backdrop) {
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
internal fun CenterMessage(title: String, detail: String? = null) {
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
