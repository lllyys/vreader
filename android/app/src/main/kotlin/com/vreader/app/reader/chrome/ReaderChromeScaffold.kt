// Purpose: feature #132 WI-5 (#110 Phase 3) — the host-agnostic reader chrome scaffold that stitches
// the designed reader chrome + modal sheets over any reader body. It stacks [ReaderTopChrome] (WI-2) at
// the top, the host's [body] filling the middle, and the host's [bottomChrome] at the bottom — passing
// the Contents/Notes open callbacks INTO the bottom-chrome slot so the host wires them without reaching
// into scaffold state. A center-tap on the body toggles chrome visibility (the top + bottom bars hide
// together). It hosts the modal sheets driven by the hoisted [ReaderChromeState.sheet]:
// [ReaderSheet.Toc] → the WI-3 [TocContentsSheet], [ReaderSheet.Notes] → the WI-4 [AnnotationsReviewSheet],
// and — feature #134 WI-5 — [ReaderSheet.Details] → the WI-4 [BookDetailsSheet]. The top-bar More button
// (rendered iff [bookDetails] is non-null) toggles the WI-3 [MorePopup] carrying ONLY the Details + Share
// rows (the §more-row-ownership contract — TTS/Auto-turn/Bilingual/Export belong to other features):
// Details opens the Details sheet, Share fires [onShareBook], and the Details sheet's copy-fingerprint
// mini-action fires [onCopyFingerprint] (the host copies to the OS clipboard — no invented toast, rule 51).
// The Contents control is HIDDEN when [tocEntries] is empty (the scaffold passes a null open callback,
// so the bottom chrome omits it — the no-dead-controls rule). NO bookmark route/params (#135). Pure
// function of hoisted state + callbacks (rule 50 §4); same [ReaderTheme] token map as the reader chrome.
package com.vreader.app.reader.chrome

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Share
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import com.vreader.app.annotations.AnnotationItem
import com.vreader.app.annotations.AnnotationsReviewSheet
import com.vreader.app.annotations.AnnotationsSnapshot
import com.vreader.app.reader.details.BookDetailsSheet
import com.vreader.app.reader.details.BookDetailsUiModel
import com.vreader.app.reader.more.MoreActionId
import com.vreader.app.reader.more.MorePopup
import com.vreader.app.reader.more.MoreRow
import com.vreader.app.reader.nav.TocContentsSheet
import com.vreader.app.reader.nav.TocEntry
import com.vreader.app.reader.settings.ReaderTheme

/**
 * The host-agnostic reader chrome scaffold. [chromeState] is the hoisted [ReaderChromeState]
 * (visibility + open sheet). [title] fills the top bar; [onBack] fires the "‹ Library" control;
 * [onOpenSearch] populates the top-bar Search slot (null → omitted; #133); [topBookmarkSlot] fills the
 * top-bar bookmark slot (null in #132; #135). [tocEntries]/[currentTocIndex] drive the Contents sheet
 * (empty entries → the Contents control is hidden). [annotations] is the one-shot snapshot for the Notes
 * sheet; [onJumpToc] performs a TOC jump (returns success for dismiss-on-success); [onJumpToAnnotation] is
 * the capability-based nullable annotation jump; [onShareAnnotations] is the Notes sheet-level Share.
 *
 * feature #134 WI-5 — the top-bar More menu + Book Details: when [bookDetails] is non-null the top-bar
 * More button appears and toggles the WI-3 [MorePopup] carrying ONLY the Details + Share rows; tapping
 * Details opens the [ReaderSheet.Details] sheet (the WI-4 [BookDetailsSheet] over [bookDetails]), tapping
 * Share fires [onShareBook], and the Details sheet's copy-fingerprint mini-action fires [onCopyFingerprint]
 * (the host copies to the OS clipboard — no invented copy-confirmation UI, rule 51). When [bookDetails] is
 * null the More button is omitted (no dead control) — a caller-supplied [onOpenMore] still populates the
 * More slot for hosts that want a different More action.
 *
 * [bottomChrome] receives the Contents/Notes open callbacks (a null Contents callback when [tocEntries] is
 * empty) and renders the reader's bottom chrome. [body] is the reader content; a center-tap on it toggles
 * [ReaderChromeState.chromeVisible].
 */
@Composable
fun ReaderChromeScaffold(
    theme: ReaderTheme,
    title: String,
    chromeState: MutableState<ReaderChromeState>,
    onBack: () -> Unit,
    tocEntries: List<TocEntry>,
    currentTocIndex: Int,
    annotations: AnnotationsSnapshot,
    onJumpToc: (Int) -> Boolean,
    onJumpToAnnotation: ((AnnotationItem) -> Unit)?,
    onShareAnnotations: () -> Unit,
    bottomChrome: @Composable (onOpenContents: (() -> Unit)?, onOpenNotes: (() -> Unit)?) -> Unit,
    body: @Composable () -> Unit,
    modifier: Modifier = Modifier,
    onOpenSearch: (() -> Unit)? = null,
    onOpenMore: (() -> Unit)? = null,
    topBookmarkSlot: (@Composable () -> Unit)? = null,
    bookDetails: BookDetailsUiModel? = null,
    onShareBook: () -> Unit = {},
    onCopyFingerprint: (String) -> Unit = {},
) {
    val state = chromeState.value

    // Sheet transitions read `chromeState.value` FRESH (never the composed-time [state] snapshot) so a
    // rapid open/dismiss can't clobber a concurrent visibility toggle.
    fun openSheet(sheet: ReaderSheet) { chromeState.value = chromeState.value.copy(sheet = sheet) }

    // Contents is available only when there IS a table of contents; an empty TOC hides the control
    // (the scaffold hands the bottom chrome a null open callback, so it omits it — no dead control).
    val onOpenContents: (() -> Unit)? =
        if (tocEntries.isEmpty()) null else { { openSheet(ReaderSheet.Toc) } }
    val onOpenNotes: () -> Unit = { openSheet(ReaderSheet.Notes) }

    // feature #134 WI-5 — the More menu is available only when this host has a Book-details data source.
    // The scaffold owns the popup-open state so the More button toggles it; a null [bookDetails] omits the
    // button (no dead control), falling back to any caller-supplied [onOpenMore].
    var showMore by remember { mutableStateOf(false) }
    val onMore: (() -> Unit)? = when {
        bookDetails != null -> { { showMore = true } }
        else -> onOpenMore
    }

    Column(modifier.fillMaxSize().background(theme.background)) {
        if (state.chromeVisible) {
            ReaderTopChrome(
                theme = theme,
                title = title,
                onBack = onBack,
                onSearch = onOpenSearch,
                onMore = onMore,
                bookmarkSlot = topBookmarkSlot,
            )
        }

        // Body — fills the space between the bars; a center-tap toggles the chrome visibility.
        Box(
            Modifier
                .fillMaxWidth()
                .weight(1f)
                .pointerInput(Unit) {
                    detectTapGestures { chromeState.value = chromeState.value.copy(chromeVisible = !chromeState.value.chromeVisible) }
                },
        ) {
            body()
        }

        if (state.chromeVisible) {
            bottomChrome(onOpenContents, onOpenNotes)
        }
    }

    // feature #134 WI-5 — the More popover (Details + Share only). Details opens the Details sheet; Share
    // fires the host's book-share flow. Dismisses on a backdrop tap or after either action.
    if (showMore && bookDetails != null) {
        MorePopup(
            theme = theme,
            rows = readerMoreRows(
                onDetails = { showMore = false; openSheet(ReaderSheet.Details) },
                onShare = { showMore = false; onShareBook() },
            ),
            onDismiss = { showMore = false },
        )
    }

    // Modal sheets — driven by the hoisted open-sheet state. Dismiss returns to [ReaderSheet.None].
    when (state.sheet) {
        ReaderSheet.None -> Unit
        ReaderSheet.Toc -> TocContentsSheet(
            theme = theme,
            bookTitle = title,
            entries = tocEntries,
            currentTocIndex = currentTocIndex,
            onJump = onJumpToc,
            onDismiss = { openSheet(ReaderSheet.None) },
        )
        ReaderSheet.Notes -> AnnotationsReviewSheet(
            theme = theme,
            snapshot = annotations,
            onShareAll = onShareAnnotations,
            onJumpToAnnotation = onJumpToAnnotation,
            onDismiss = { openSheet(ReaderSheet.None) },
        )
        // Render the Details sheet only when there IS a model; a Details route with no model (should not
        // happen — the route is only reachable when [bookDetails] fed the More menu) is a safe no-op.
        ReaderSheet.Details -> if (bookDetails != null) BookDetailsSheet(
            theme = theme,
            model = bookDetails,
            onCopyFingerprint = onCopyFingerprint,
            onShare = onShareBook,
            onDismiss = { openSheet(ReaderSheet.None) },
        )
    }
}

/**
 * feature #134 WI-5 — the reader More-menu rows the scaffold + the EPUB chrome feed to the WI-3
 * [MorePopup]. #134 owns ONLY the Details + Share rows (the design's `vreader-more.jsx` `Book details` /
 * `Share book` actions); TTS / Auto-turn / Bilingual / Export are OTHER features' rows and are never
 * invented here (the §more-row-ownership contract + the #129 no-dead-control rule — the popup renders only
 * the rows it is given). Pure function of its two callbacks (no Compose runtime beyond the icon refs).
 */
internal fun readerMoreRows(onDetails: () -> Unit, onShare: () -> Unit): List<MoreRow> = listOf(
    MoreRow.Action(id = MoreActionId.DETAILS, label = "Book details", icon = Icons.Filled.Info, onTap = onDetails),
    MoreRow.Action(id = MoreActionId.SHARE, label = "Share book", icon = Icons.Filled.Share, onTap = onShare),
)
