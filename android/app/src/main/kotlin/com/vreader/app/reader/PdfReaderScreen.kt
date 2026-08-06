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
// feature #132 WI-7-hosts: the PDF host renders the shared ReaderChromeScaffold (top bar + the Notes
// review sheet) via the extracted [PdfReaderChrome]. PDF has no TOC → Contents is hidden (empty
// tocEntries / EmptyTocProvider posture); PDF is rasterized → NO Display control (the #129 theme-only
// backdrop is applied live from the store, with no control surface — a reduced Display sheet would be
// undesigned, rule 51). So the bottom chrome is Notes-only ([PdfNotesBottomChrome], the designed Notes
// toolbar button). PDF tap-to-jump is NON-null: [pdfAnnotationPage] resolves the annotation locator's
// page (clamped) and the host scrolls the page list to it.
//
// @coordinates-with: PdfReaderActivity.kt (hosts these composables, threads the theme backdrop +
//   PdfDocument + list state, wires onJumpToAnnotation to the page-scroll seam), PdfDocument.kt (the
//   renderer), PdfDisplayBackdrop.kt (the mapping), ReaderChromeScaffold.kt (the shared chrome).
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
import androidx.compose.material.icons.outlined.BorderColor
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.annotations.AnnotationItem
import com.vreader.app.annotations.AnnotationsSnapshot
import com.vreader.app.annotations.BookmarkRecord
import com.vreader.app.reader.chrome.ReaderChromeScaffold
import com.vreader.app.reader.chrome.ReaderChromeState
import com.vreader.app.reader.nav.BookmarkRowItem
import com.vreader.app.reader.nav.JumpResult
import com.vreader.app.reader.settings.ReaderTheme
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

/**
 * The PDF reading BODY — the continuous page list on the [backdrop] + the floating "Page N of M" pill —
 * WITHOUT any chrome. Used inside [PdfReaderChrome]'s scaffold body slot (feature #132 WI-7-hosts): the
 * shared [ReaderChromeScaffold] now owns the top bar, so the body no longer stacks its own [PdfScaffold].
 */
@Composable
internal fun PdfReaderBody(document: PdfDocument, listState: LazyListState, backdrop: Color) {
    Box(Modifier.fillMaxSize().background(backdrop)) {
        LazyColumn(
            Modifier.fillMaxSize(),
            state = listState,
            contentPadding = PaddingValues(horizontal = 18.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            items(count = document.pageCount, key = { it }) { i -> PdfPage(document, i) }
        }
        // Floating "Page N of M" pill — tracks the top-visible page (1-based).
        PageProgressPill(
            page = listState.firstVisibleItemIndex + 1,
            total = document.pageCount,
            modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 24.dp),
        )
    }
}

/**
 * The PDF reader host chrome — feature #132 WI-7-hosts (mirror of WI-6's [TxtReaderChrome]). Renders the
 * shared [ReaderChromeScaffold] (top bar + the Notes review sheet) over the PDF [body] (the page list).
 * PDF has no TOC → `tocEntries` is EMPTY (the EmptyTocProvider posture) → the scaffold hides the Contents
 * control. PDF is rasterized → NO Display control (the #129 theme backdrop applies live from the store with
 * no control surface); the bottom chrome is a Notes-only toolbar ([PdfNotesBottomChrome]). The top bar's
 * Search/More/bookmark slots are omitted (null — #133/#134/#135; no dead controls). [onJumpToAnnotation] is
 * NON-null (PDF jumps via the annotation's page). Wrapped in a `systemBarsPadding()` Column so the chrome
 * clears the status/nav bars. Extracted (internal) so the host wiring is directly testable.
 */
@Composable
internal fun PdfReaderChrome(
    theme: ReaderTheme,
    title: String,
    chromeState: MutableState<ReaderChromeState>,
    annotations: AnnotationsSnapshot,
    onBack: () -> Unit,
    onJumpToAnnotation: (AnnotationItem) -> Unit,
    onShareAnnotations: () -> Unit,
    body: @Composable () -> Unit,
    // feature #134 WI-5 — the More menu's Book-details model + Share/copy actions (null model → no More).
    bookDetails: com.vreader.app.reader.details.BookDetailsUiModel? = null,
    onShareBook: () -> Unit = {},
    onCopyFingerprint: (String) -> Unit = {},
    // feature #135 WI-7 — the top-bar bookmark toggle + Bookmarks-tab rows + PDF page jump (all nullable/
    // default so #132/#134 callers stay valid). The Bookmarks-tab row shows "p. N" (no preview/chapter).
    isCurrentBookmarked: Boolean = false,
    onToggleBookmark: (() -> Unit)? = null,
    currentLocator: vreader.contracts.Locator? = null,
    bookmarks: List<BookmarkRowItem> = emptyList(),
    onJumpBookmark: ((BookmarkRecord) -> JumpResult)? = null,
    // feature #165 WI-7 — the Details sheet's annotation-import entry: the row's launcher (null → no row,
    // the capability gate) + the host-owned post-pick preview sheet overlay. Nullable/default so every
    // pre-#165 caller stays valid.
    onImportAnnotations: (() -> Unit)? = null,
    importSheet: (@Composable () -> Unit)? = null,
) {
    Column(Modifier.fillMaxSize().background(theme.background).systemBarsPadding()) {
        ReaderChromeScaffold(
            theme = theme,
            title = title,
            chromeState = chromeState,
            onBack = onBack,
            tocEntries = emptyList(),           // no TOC → the scaffold hides the Contents control
            currentTocIndex = 0,
            annotations = annotations,
            onJumpToc = { false },              // unreachable: Contents is hidden with an empty TOC
            onJumpToAnnotation = onJumpToAnnotation,
            onShareAnnotations = onShareAnnotations,
            // Search top-bar slot stays null (#133 — no dead control). feature #134 WI-5:
            // the More button + Book Details / Share are wired through the scaffold's More menu below.
            bottomChrome = { _, onOpenNotes ->
                // PDF has no Contents (empty TOC) + no Display control → Notes only.
                PdfNotesBottomChrome(theme = theme, onOpenNotes = onOpenNotes)
            },
            body = body,
            bookDetails = bookDetails,
            onShareBook = onShareBook,
            onCopyFingerprint = onCopyFingerprint,
            // feature #135 WI-7 — the bookmark toggle + Bookmarks tab, now lit up for PDF.
            isCurrentBookmarked = isCurrentBookmarked,
            onToggleBookmark = onToggleBookmark,
            currentLocator = currentLocator,
            bookmarks = bookmarks,
            onJumpBookmark = onJumpBookmark,
            // feature #165 WI-7 — the annotation-import row + its post-pick preview sheet.
            onImportAnnotations = onImportAnnotations,
            importSheet = importSheet,
        )
    }
}

/**
 * feature #135 WI-7 — the current PDF reading position (the top-visible page index) as a plain canonical
 * [vreader.contracts.Locator] (the bookmark equality basis + create/jump anchor). Mirrors the host's
 * save-position construction (identity triple + `page`). Pure/JVM-testable.
 */
fun pdfBookmarkLocator(book: com.vreader.app.data.Book, page: Int): vreader.contracts.Locator =
    vreader.contracts.Locator(
        contentSHA256 = book.contentSHA256,
        fileByteCount = book.fileByteCount,
        format = book.originalFormat.name,
        page = page.coerceAtLeast(0),
    )

/**
 * feature #135 WI-7 — the PDF bookmark jump target: the page index to scroll to, or null when it is out of
 * range (→ [JumpResult.Failed], the sheet stays open — rule 51). A null/negative page, a page at/past the
 * end ([page] >= [pageCount]), or an empty document ([pageCount] == 0) is out of range. The PDF analog of
 * [txtBookmarkScrollTarget]. Pure/JVM-testable.
 */
fun pdfBookmarkPageTarget(page: Int?, pageCount: Int): Int? {
    if (pageCount <= 0) return null
    if (page == null || page < 0 || page >= pageCount) return null
    return page
}

/**
 * The PDF host's bottom chrome — the designed reader-toolbar "Notes" button only (feature #132 WI-7-hosts).
 * PDF has no TOC (Contents hidden) and no reflow (#129 gives it NO Display control), so of the design's
 * Contents · Notes · Display · AI toolbar only the Notes slot applies. Uses the same designed icon-above-
 * label treatment as ReaderBottomChrome's Notes slot (the Highlighter/BorderColor glyph, `chrome-notes`
 * testTag) so it reads identically. Rendered ONLY when [onOpenNotes] is non-null (it always is for #132).
 */
@Composable
private fun PdfNotesBottomChrome(theme: ReaderTheme, onOpenNotes: (() -> Unit)?) {
    if (onOpenNotes == null) return
    val ink = theme.ink
    val sub = theme.ink.copy(alpha = 0.6f)
    val rule = theme.ink.copy(alpha = 0.10f)
    Column(
        Modifier.fillMaxWidth().background(theme.background).testTag("pdf-bottom-chrome"),
    ) {
        Box(Modifier.fillMaxWidth().heightIn(min = 0.5.dp, max = 0.5.dp).background(rule))
        Row(
            Modifier.fillMaxWidth().padding(top = 14.dp, bottom = 28.dp),
            horizontalArrangement = Arrangement.Center,
        ) {
            Column(
                Modifier
                    .clip(RoundedCornerShape(14.dp))
                    .clickable(onClick = onOpenNotes)
                    .padding(horizontal = 12.dp, vertical = 4.dp)
                    .testTag("chrome-notes")
                    .semantics { contentDescription = "Notes" },
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(3.dp),
            ) {
                Icon(Icons.Outlined.BorderColor, contentDescription = null, tint = ink, modifier = Modifier.size(22.dp))
                Text("Notes", color = sub, fontSize = 10.sp, fontWeight = FontWeight.Medium)
            }
        }
    }
}

/**
 * The tap-to-jump target PAGE index for an annotation (feature #132 WI-7-hosts), clamped to a valid page
 * of a [pageCount]-page document. A PDF locator carries its position in `Locator.page`; a locator with no
 * page (or a negative one) clamps to 0, and a page past the end clamps to the last page (a safe scroll
 * target). Pure/JVM-testable ([PdfAnnotationPageTest]). The PDF analog of the TXT [annotationScrollOffset].
 */
internal fun pdfAnnotationPage(item: AnnotationItem, pageCount: Int): Int =
    (item.locator.page ?: 0).coerceIn(0, (pageCount - 1).coerceAtLeast(0))

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
