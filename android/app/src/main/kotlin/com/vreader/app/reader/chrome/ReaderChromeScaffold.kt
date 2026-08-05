// Purpose: feature #132 WI-5 (#110 Phase 3) — the host-agnostic reader chrome scaffold that stitches
// the designed reader chrome + modal sheets over any reader body. It stacks [ReaderTopChrome] (WI-2) at
// the top, the host's [body] filling the middle, and the host's [bottomChrome] at the bottom — passing
// the Contents/Notes open callbacks INTO the bottom-chrome slot so the host wires them without reaching
// into scaffold state. A center-tap on the body toggles chrome visibility (the top + bottom bars hide
// together). It hosts the modal sheets driven by the hoisted [ReaderChromeState.sheet]:
// [ReaderSheet.Toc] → the #135 WI-6 [TocBookmarksSheet] (the promoted two-tab Contents|Bookmarks sheet,
// which REUSES #132's Contents body), [ReaderSheet.Notes] → the WI-4 [AnnotationsReviewSheet], and —
// feature #134 WI-5 — [ReaderSheet.Details] → the WI-4 [BookDetailsSheet]. The top-bar More button
// (rendered iff [bookDetails] is non-null) toggles the WI-3 [MorePopup] carrying ONLY the Details + Share
// rows (the §more-row-ownership contract — TTS/Auto-turn/Bilingual/Export belong to other features):
// Details opens the Details sheet, Share fires [onShareBook], and the Details sheet's copy-fingerprint
// mini-action fires [onCopyFingerprint] (the host copies to the OS clipboard — no invented toast, rule 51).
// The Contents control is HIDDEN when [tocEntries] is empty (the scaffold passes a null open callback,
// so the bottom chrome omits it — the no-dead-controls rule). feature #135 WI-5 — the top-bar bookmark
// toggle: when [onToggleBookmark] is non-null the scaffold fills [ReaderTopChrome]'s reserved bookmark
// slot with the WI-5 [BookmarkToggleButton] (filled/outline by [isCurrentBookmarked]); a null callback
// omits it (the #129 no-dead-control rule → #132 Contents/Notes-only callers stay back-compatible). feature
// #135 WI-6 — the promoted two-tab TOC sheet: the [ReaderSheet.Toc] route now renders [TocBookmarksSheet]
// (Contents|Bookmarks), and [bookmarks]/[onJumpBookmark] feed its Bookmarks tab (nullable/defaulted → #132
// Contents/Notes-only callers stay valid); the [ReaderSheet.Bookmarks] route opens the SAME two-tab sheet
// (host wiring feeds the data in WI-7). [currentLocator] is threaded for the host to derive presence but the
// scaffold does not read it. Pure function of hoisted state + callbacks (rule 50 §4); same [ReaderTheme]
// token map as the reader chrome.
package com.vreader.app.reader.chrome

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
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
import com.vreader.app.annotations.BookmarkRecord
import com.vreader.app.reader.more.MorePopup
import com.vreader.app.reader.nav.BookmarkRowItem
import com.vreader.app.reader.nav.JumpResult
import com.vreader.app.reader.nav.TocBookmarksSheet
import com.vreader.app.reader.nav.TocEntry
import com.vreader.app.reader.nav.TocTab
import com.vreader.app.reader.settings.ReaderTheme
import vreader.contracts.Locator

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
 * feature #135 WI-5 — the top-bar bookmark toggle: when [onToggleBookmark] is non-null the scaffold fills
 * [ReaderTopChrome]'s reserved bookmark slot with the WI-5 [BookmarkToggleButton], rendered filled/outline
 * by [isCurrentBookmarked]; a null callback omits the slot (the #129 no-dead-control rule → #132
 * Contents/Notes-only callers stay valid). [currentLocator] is the current reading position the host uses
 * to derive presence + create the bookmark (threaded through for WI-7's host wiring; the scaffold itself
 * does not read it). A host that passes [topBookmarkSlot] directly overrides the built toggle (kept for
 * symmetry with [onOpenMore]).
 *
 * feature #135 WI-6 — the promoted two-tab TOC sheet: [ReaderSheet.Toc] renders [TocBookmarksSheet]
 * (Contents|Bookmarks, the Contents tab REUSING #132's body), and [ReaderSheet.Bookmarks] opens the same
 * sheet with the Bookmarks tab pre-selected. [bookmarks] are the projected Bookmarks-tab rows (default
 * empty); [onJumpBookmark] is the capability-based nullable bookmark jump (non-null → clickable rows +
 * dismiss-on-Succeeded; null → review-only, non-clickable rows, NO dead no-op). Both are nullable/defaulted
 * so #132 Contents/Notes-only callers stay valid (WI-7 feeds them per host).
 *
 * feature #165 WI-6 — annotation import on the Details sheet: a non-null [onImportAnnotations] adds the
 * designed accent `Import annotations…` row + B1's merge-policy footnote to the sheet's ActionList and is
 * invoked on tap; null (the default) renders neither (the capability gate — no dead no-op). The paired
 * `Export annotations…` row is NOT built here: it is `BLOCKED: needs-design (#2085)` and lands in WI-8.
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
    isCurrentBookmarked: Boolean = false,
    onToggleBookmark: (() -> Unit)? = null,
    currentLocator: Locator? = null,
    topBookmarkSlot: (@Composable () -> Unit)? = null,
    bookmarks: List<BookmarkRowItem> = emptyList(),
    onJumpBookmark: ((BookmarkRecord) -> JumpResult)? = null,
    bookDetails: BookDetailsUiModel? = null,
    onShareBook: () -> Unit = {},
    onCopyFingerprint: (String) -> Unit = {},
    // feature #165 WI-6 — the annotation-import entry on the Details sheet. Capability-gated: null (the
    // default) renders NO Import row and NO merge-policy footnote, so #132/#134/#135 callers are unchanged.
    // WI-7 supplies the real launcher; the paired Export entry is BLOCKED on needs-design #2085 (WI-8).
    onImportAnnotations: (() -> Unit)? = null,
    // feature #131 WI-9 — the bilingual entry: [pillSlot] fills the top-chrome pill next to the title
    // (WI-7a BilingualPill; null → no pill, bilingual off), and [bilingualMoreRow] supplies the More-menu
    // Bilingual Toggle/Disabled row (null → no row — the #132/#134-only callers stay valid).
    pillSlot: (@Composable () -> Unit)? = null,
    bilingualMoreRow: BilingualMoreRow? = null,
) {
    val state = chromeState.value

    // feature #135 WI-5 — build the top-bar bookmark slot from the WI-5 [BookmarkToggleButton] when the
    // host opts in via [onToggleBookmark]. An explicit [topBookmarkSlot] (rare) wins; otherwise a non-null
    // toggle synthesizes the button, and a null toggle leaves the slot empty (no dead control).
    val bookmarkSlot: (@Composable () -> Unit)? = when {
        topBookmarkSlot != null -> topBookmarkSlot
        onToggleBookmark != null -> {
            { BookmarkToggleButton(theme = theme, isBookmarked = isCurrentBookmarked, onToggle = onToggleBookmark) }
        }
        else -> null
    }

    // Sheet transitions read `chromeState.value` FRESH (never the composed-time [state] snapshot) so a
    // rapid open/dismiss can't clobber a concurrent visibility toggle.
    fun openSheet(sheet: ReaderSheet) { chromeState.value = chromeState.value.copy(sheet = sheet) }

    // Contents is available only when there IS a table of contents; an empty TOC hides the control
    // (the scaffold hands the bottom chrome a null open callback, so it omits it — no dead control).
    val onOpenContents: (() -> Unit)? =
        if (tocEntries.isEmpty()) null else { { openSheet(ReaderSheet.Toc) } }
    val onOpenNotes: () -> Unit = { openSheet(ReaderSheet.Notes) }

    // feature #134 WI-5 — the More menu is available when this host has a Book-details data source OR
    // (feature #131 WI-9) a Bilingual row to offer. The scaffold owns the popup-open state so the More
    // button toggles it; when neither source is present the button is omitted (no dead control), falling
    // back to any caller-supplied [onOpenMore].
    var showMore by remember { mutableStateOf(false) }
    val hasMoreRows = bookDetails != null || bilingualMoreRow != null
    val onMore: (() -> Unit)? = when {
        hasMoreRows -> { { showMore = true } }
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
                bookmarkSlot = bookmarkSlot,
                pillSlot = pillSlot,
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

    // feature #134 WI-5 / #131 WI-9 — the More popover. #134's Details + Share rows (Details opens the
    // Details sheet, Share fires the host's book-share flow) + #131's Bilingual Toggle/Disabled row when
    // supplied. The toggle/configure callbacks are the host's (they route to the setup / AI-providers
    // sheets); toggling/configuring dismisses the popup. Dismisses on a backdrop tap or after any action.
    if (showMore && hasMoreRows) {
        MorePopup(
            theme = theme,
            rows = readerMoreRows(
                onDetails = { showMore = false; openSheet(ReaderSheet.Details) },
                onShare = { showMore = false; onShareBook() },
                bilingual = bilingualMoreRow?.dismissingWith { showMore = false },
                includeDetailsShare = bookDetails != null,
            ),
            onDismiss = { showMore = false },
        )
    }

    // Modal sheets — driven by the hoisted open-sheet state. Dismiss returns to [ReaderSheet.None].
    // feature #135 WI-6 — [onJumpBookmark] is passed through nullable (capability-gated); an unwired host
    // (#132/#134/#135-WI-5 callers) passes null → the Bookmarks-tab rows are review-only, NOT clickable
    // dead rows (WI-7 supplies the real per-host jump).
    when (state.sheet) {
        ReaderSheet.None -> Unit
        // feature #135 WI-6 — the promoted two-tab TOC sheet (Contents|Bookmarks). The Contents tab REUSES
        // #132's TocContentsSheet body unchanged; the Bookmarks tab renders [bookmarks].
        ReaderSheet.Toc -> TocBookmarksSheet(
            theme = theme,
            bookTitle = title,
            entries = tocEntries,
            currentTocIndex = currentTocIndex,
            bookmarks = bookmarks,
            onJumpToc = onJumpToc,
            onJumpBookmark = onJumpBookmark,
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
            onImportAnnotations = onImportAnnotations,
        )
        // feature #135 WI-6 — the Bookmarks route opens the SAME two-tab sheet with the Bookmarks tab
        // pre-selected (the designed [TocBookmarksSheet]; rule 51 — no invented list surface).
        ReaderSheet.Bookmarks -> TocBookmarksSheet(
            theme = theme,
            bookTitle = title,
            entries = tocEntries,
            currentTocIndex = currentTocIndex,
            bookmarks = bookmarks,
            onJumpToc = onJumpToc,
            onJumpBookmark = onJumpBookmark,
            onDismiss = { openSheet(ReaderSheet.None) },
            initialTab = TocTab.Bookmarks,
        )
    }
}

// feature #134 WI-5 / #131 WI-9 — the More-menu row assembly ([readerMoreRows] + [BilingualMoreRow] +
// [dismissingWith]) lives in BilingualMoreRow.kt (split to keep this file under the ~300-line bar).
