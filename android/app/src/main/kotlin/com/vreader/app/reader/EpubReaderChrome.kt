// Purpose: feature #132 WI-7-EPUB (#110 Phase 3) — the Compose chrome CONTENT for the EPUB reader host
// (ReaderActivity). The EPUB host is the outlier: a Readium EpubNavigatorFragment (a View) renders the
// page under the chrome, so — unlike the Compose-native TXT/PDF/AZW3 hosts — it CANNOT wrap the
// full-screen ReaderChromeScaffold (which owns a `weight(1f)` composable body). Instead the host stacks
// THREE separately-sized ComposeViews over the fragment's FrameLayout, each rendered by one composable
// here and each fed the persistent MutableStateFlow<ReaderChromeModel> + a hoisted ReaderChromeState:
//   • [EpubTopBand]    — the top ComposeView (title + "‹ Library" + — feature #134 WI-5 — the More button
//                         that toggles the WI-3 MorePopup); sized to the top chrome only.
//   • [EpubBottomBand] — the bottom ComposeView (progress + Contents/Notes/Display toolbar); sized to the
//                         bottom chrome only. Contents shown only when the model's TOC is non-empty.
//   • [EpubReaderSheets] — a full-screen ComposeView that is EMPTY (renders nothing, so it does not cover
//                         the fragment) until a sheet is open, at which point it lays a full-screen dismiss
//                         overlay + the Contents/Notes/Details ModalBottomSheet. This "open-only"
//                         full-screen posture is what keeps the Readium fragment's scroll/selection/link
//                         input working while no sheet is up — the top/bottom bands only cover the chrome
//                         regions.
// Contents onJump → the host's `navigator.go(entry.epubReadiumLocator)` (Boolean): dismiss on success,
// stay-open on false, NO invented error surface (rule 51 §nav-error-presentation). Notes → the WI-4 review
// sheet with onJumpToAnnotation NULL (EPUB review-only, cards non-clickable, until #135 supplies the nav
// seam). feature #134 WI-5 — Details → the WI-4 BookDetailsSheet over the host-supplied [bookDetails];
// the More menu carries ONLY Details + Share (Share → the host's book-share flow; copy-fingerprint → the
// host's OS clipboard copy, no invented toast — rule 51). Pure functions of state + callbacks (rule 50 §4);
// same ReaderTheme token map as the other hosts.
// @coordinates-with: ReaderActivity.kt (owns the StateFlow + the ComposeViews + the navigator jump + the
//   Book-details model/share/copy wiring), ReaderChromeModel.kt (the collected model), chrome/ReaderTopChrome
//   + chrome/ReaderBottomChrome (the reused designed bands), chrome/BookmarkToggleButton (the #135 top-bar
//   bookmark toggle filling the top band's bookmark slot), chrome/ReaderChromeState (the hoisted
//   sheet/visibility state incl. the #135 Bookmarks route), chrome/ReaderChromeScaffold (the shared
//   readerMoreRows assembler), more/MorePopup + details/BookDetailsSheet + nav/TocBookmarksSheet (the #135
//   WI-6 promoted two-tab Contents|Bookmarks sheet, which reuses nav/TocContentsSheet's Contents body) +
//   annotations/AnnotationsReviewSheet (the popup + modal sheets).
package com.vreader.app.reader

import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.vreader.app.annotations.AnnotationsReviewSheet
import com.vreader.app.reader.chrome.BilingualMoreRow
import com.vreader.app.reader.chrome.BookmarkToggleButton
import com.vreader.app.reader.chrome.ReaderBottomChrome
import com.vreader.app.reader.chrome.ReaderChromeState
import com.vreader.app.reader.chrome.ReaderSheet
import com.vreader.app.reader.chrome.ReaderTopChrome
import com.vreader.app.reader.chrome.dismissingWith
import com.vreader.app.reader.chrome.readerMoreRows
import com.vreader.app.annotations.BookmarkRecord
import com.vreader.app.reader.details.BookDetailsSheet
import com.vreader.app.reader.details.BookDetailsUiModel
import com.vreader.app.reader.more.MorePopup
import com.vreader.app.reader.nav.BookmarkRowItem
import com.vreader.app.reader.nav.JumpResult
import com.vreader.app.reader.nav.TocBookmarksSheet
import com.vreader.app.reader.nav.TocTab
import com.vreader.app.reader.settings.ReaderTheme
import kotlinx.coroutines.flow.StateFlow

/**
 * The EPUB top chrome band — the title + "‹ Library" back control (the WI-2 [ReaderTopChrome]) + —
 * feature #134 WI-5 — the More button. Rendered in its OWN top ComposeView sized to WRAP_CONTENT so it
 * covers only the top strip; the Readium fragment fills the rest. [model] supplies the live title;
 * [onBack] fires the back control. The More button appears ONLY when [bookDetails] is non-null (no dead
 * control) and toggles the WI-3 [MorePopup] carrying ONLY the Details + Share rows: Details writes
 * [ReaderSheet.Details] onto [chromeState] (so [EpubReaderSheets] shows the Book Details sheet), Share
 * fires [onShareBook]. The popup renders in its own window (a full-screen backdrop) so the WRAP_CONTENT
 * band height doesn't clip it. feature #133 WI-11 — the top-bar Search slot is now WIRED: [onSearch] fills
 * [ReaderTopChrome]'s Search slot (null → the icon is omitted — the #129 no-dead-control rule; a host whose
 * publication is not searchable / whose index-state gate reports Unsupported passes null so the icon
 * disappears). feature #135 WI-5 — the top-bar bookmark toggle: when [onToggleBookmark] is non-null the
 * band fills [ReaderTopChrome]'s bookmark slot with the WI-5 [BookmarkToggleButton] (filled/outline by
 * [isCurrentBookmarked]); a null callback leaves the slot empty (no dead control).
 */
@Composable
fun EpubTopBand(
    model: StateFlow<ReaderChromeModel>,
    theme: ReaderTheme,
    onBack: () -> Unit,
    chromeState: MutableState<ReaderChromeState>,
    bookDetails: BookDetailsUiModel?,
    onShareBook: () -> Unit,
    // feature #133 WI-11 — the in-book Search entry. A null [onSearch] omits the top-bar Search icon
    // (a non-searchable publication / Unsupported gate — no dead control). Nullable/default so #132/#134/#135
    // callers stay valid.
    onSearch: (() -> Unit)? = null,
    isCurrentBookmarked: Boolean = false,
    onToggleBookmark: (() -> Unit)? = null,
    // feature #131 WI-9 — the bilingual entry: [pillSlot] fills the top-chrome pill next to the title
    // (WI-7a BilingualPill; null → bilingual off / non-EPUB — no pill) and [bilingualMoreRow] supplies the
    // More-menu Bilingual Toggle/Disabled row (null → non-EPUB — no row). Nullable/default so the #132/#134/
    // #135 EPUB callers stay valid.
    pillSlot: (@Composable () -> Unit)? = null,
    bilingualMoreRow: BilingualMoreRow? = null,
) {
    val chrome by model.collectAsStateWithLifecycle()
    var showMore by remember { mutableStateOf(false) }
    // More is available when this book has a Book-details data source OR (#131 WI-9) a Bilingual row.
    val hasMoreRows = bookDetails != null || bilingualMoreRow != null
    val onMore: (() -> Unit)? = if (hasMoreRows) ({ showMore = true }) else null
    // feature #135 WI-5 — the bookmark slot is built only when the host opts in via [onToggleBookmark].
    val bookmarkSlot: (@Composable () -> Unit)? =
        if (onToggleBookmark != null) {
            { BookmarkToggleButton(theme = theme, isBookmarked = isCurrentBookmarked, onToggle = onToggleBookmark) }
        } else {
            null
        }
    ReaderTopChrome(
        theme = theme,
        title = chrome.title,
        onBack = onBack,
        onSearch = onSearch,
        onMore = onMore,
        bookmarkSlot = bookmarkSlot,
        pillSlot = pillSlot,
    )
    if (showMore && hasMoreRows) {
        MorePopup(
            theme = theme,
            rows = readerMoreRows(
                onDetails = { showMore = false; chromeState.value = chromeState.value.copy(sheet = ReaderSheet.Details) },
                onShare = { showMore = false; onShareBook() },
                bilingual = bilingualMoreRow?.dismissingWith { showMore = false },
                includeDetailsShare = bookDetails != null,
            ),
            onDismiss = { showMore = false },
        )
    }
}

/**
 * The EPUB bottom chrome band — the progress scrubber + the Contents/Notes/Display toolbar (the extended
 * WI-5 [ReaderBottomChrome]). Rendered in its OWN bottom ComposeView sized to WRAP_CONTENT so it covers
 * only the bottom strip. Contents opens the TOC sheet ONLY when the model has a non-empty TOC (else the
 * control is omitted — no dead control); Notes opens the review sheet; Display opens the #129 settings
 * sheet ([onOpenDisplay], preserved). [progress] is 0..1 (the host's live reading fraction); [onScrub]
 * seeks. Opening a sheet writes [chromeState] so [EpubReaderSheets] shows it.
 */
@Composable
fun EpubBottomBand(
    model: StateFlow<ReaderChromeModel>,
    theme: ReaderTheme,
    chromeState: MutableState<ReaderChromeState>,
    progress: Float,
    onScrub: (Float) -> Unit,
    onOpenDisplay: () -> Unit,
) {
    val chrome by model.collectAsStateWithLifecycle()
    // Contents available only when there IS a TOC — an empty TOC hides the control (no dead control).
    val onOpenContents: (() -> Unit)? =
        if (chrome.tocEntries.isEmpty()) null
        else { { chromeState.value = chromeState.value.copy(sheet = ReaderSheet.Toc) } }
    ReaderBottomChrome(
        theme = theme,
        progress = progress,
        displayPage = 0,
        totalPages = 0, // EPUB scroll layout — no page labels (Spike-B scroll mode)
        onScrub = onScrub,
        onOpenDisplay = onOpenDisplay,
        onOpenContents = onOpenContents,
        onOpenNotes = { chromeState.value = chromeState.value.copy(sheet = ReaderSheet.Notes) },
    )
}

/**
 * The EPUB modal-sheet layer — the open-only full-screen dismiss overlay + the Contents / Notes / Details
 * sheets. Rendered in a FULL-SCREEN ComposeView that renders NOTHING while [ReaderChromeState.sheet] is
 * [ReaderSheet.None] (so it does not cover the fragment); the instant a sheet opens it lays a full-screen
 * dismiss overlay (a transparent scrim that dismisses the sheet on an outside tap) beneath the
 * ModalBottomSheet. This keeps the Readium fragment's scroll/selection/link input alive whenever no sheet
 * is up.
 *
 * [onJumpToc] performs the native-locator TOC jump (returns success → the Contents tab dismisses on
 * success, stays open on false — no invented error surface). [onShareAnnotations] is the Notes sheet-level
 * Share. EPUB Notes cards are review-only (onJumpToAnnotation NULL) until #135's nav seam lands. feature
 * #135 WI-6 — the Toc route renders the promoted two-tab [TocBookmarksSheet]; [bookmarks] feed its
 * Bookmarks tab and [onJumpBookmark] is the capability-based nullable bookmark jump (non-null → clickable
 * rows + dismiss-on-Succeeded; null → review-only, non-clickable rows before WI-7 lights up the EPUB jump);
 * the Bookmarks route opens the same sheet on its Bookmarks tab. feature #134 WI-5 — [bookDetails] drives the Details sheet
 * (the WI-4 [BookDetailsSheet]); [onShareBook] is its Share flow and [onCopyFingerprint] its copy-fingerprint
 * mini-action (the host copies to the OS clipboard — no invented toast, rule 51). A Details route with no
 * [bookDetails] (should not happen — the route is only reachable when the More menu was fed a model) treats
 * the scrim as present but shows no sheet (a safe no-op). feature #165 WI-6 — a non-null
 * [onImportAnnotations] adds the designed accent `Import annotations…` row + B1's merge-policy footnote to
 * the Details sheet's ActionList and is invoked on tap; null (the default) renders neither. The paired
 * `Export annotations…` row is NOT built here — `BLOCKED: needs-design (#2085)`, WI-8.
 */
@Composable
fun EpubReaderSheets(
    model: StateFlow<ReaderChromeModel>,
    theme: ReaderTheme,
    chromeState: MutableState<ReaderChromeState>,
    onJumpToc: (Int) -> Boolean,
    onShareAnnotations: () -> Unit,
    bookDetails: BookDetailsUiModel? = null,
    onShareBook: () -> Unit = {},
    onCopyFingerprint: (String) -> Unit = {},
    bookmarks: List<BookmarkRowItem> = emptyList(),
    onJumpBookmark: ((BookmarkRecord) -> JumpResult)? = null,
    // feature #165 WI-6 — the annotation-import entry on the Details sheet. Capability-gated: null (the
    // default) renders NO Import row and NO merge-policy footnote, so #132/#134/#135 EPUB callers are
    // unchanged. WI-7 supplies the real launcher; the paired Export entry is BLOCKED on needs-design #2085.
    onImportAnnotations: (() -> Unit)? = null,
    // feature #165 WI-7 — the host-supplied post-pick preview/confirm sheet (the designed
    // [com.vreader.app.annotations.AnnotationImportPreviewSheet]). It is NOT a [ReaderSheet] route: the
    // host closes the Details route before the system picker opens, so this layer must render it even
    // while the route is [ReaderSheet.None]. Null (the default) renders nothing.
    importSheet: (@Composable () -> Unit)? = null,
) {
    val chrome by model.collectAsStateWithLifecycle()
    val sheet = chromeState.value.sheet
    // Render nothing → the fragment keeps all input. The import sheet is checked too, because it can be
    // up with no route open; when it is, this layer hosts it and nothing else (the ModalBottomSheet
    // lives in its own window, so the ComposeView itself still covers nothing).
    if (sheet is ReaderSheet.None && importSheet == null) return

    fun closeSheet() { chromeState.value = chromeState.value.copy(sheet = ReaderSheet.None) }

    // feature #134 WI-5 — a Details route with NO model would render no sheet yet still lay the
    // full-screen dismiss overlay below, silently intercepting Readium scroll/selection/link input (a
    // dead route). Normalize it back to None so touch-through is preserved (Gate-4 P1). In practice this
    // route is only reached once [bookDetails] fed the More menu, so this is a defensive guard.
    val deadDetailsRoute = sheet is ReaderSheet.Details && bookDetails == null
    if (deadDetailsRoute) closeSheet()

    // feature #135 WI-6 — the Bookmarks route now DOES render (the two-tab TocBookmarksSheet with the
    // Bookmarks tab pre-selected), so it is NOT normalized away — it lays the scrim + the sheet like Toc.
    val routeVisible = sheet !is ReaderSheet.None && !deadDetailsRoute

    // The open-only full-screen dismiss overlay — a transparent scrim under the sheet. An outside tap
    // (a tap that reaches the scrim, not the sheet) closes the sheet. Present ONLY while a ROUTE sheet is
    // open: an import sheet alone must not lay a scrim, or dismissing it would be indistinguishable from
    // tapping the fragment.
    if (routeVisible) {
        Box(
            Modifier
                .fillMaxSize()
                .testTag("epub-sheet-dismiss-overlay")
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                ) { closeSheet() },
        )
    }

    if (routeVisible) when (sheet) {
        ReaderSheet.None -> Unit
        // feature #135 WI-6 — the promoted two-tab TOC sheet (Contents|Bookmarks). The Contents tab REUSES
        // #132's TocContentsSheet body unchanged; dismiss-on-success (Contents) / dismiss-on-Succeeded
        // (Bookmarks) — a false/Failed jump keeps the sheet open, NO invented error surface (rule 51).
        ReaderSheet.Toc -> TocBookmarksSheet(
            theme = theme,
            bookTitle = chrome.title,
            entries = chrome.tocEntries,
            currentTocIndex = chrome.currentTocIndex,
            bookmarks = bookmarks,
            onJumpToc = onJumpToc,
            onJumpBookmark = onJumpBookmark,
            onDismiss = { closeSheet() },
        )
        ReaderSheet.Notes -> AnnotationsReviewSheet(
            theme = theme,
            snapshot = chrome.annotations,
            onShareAll = onShareAnnotations,
            // EPUB is review-only until #135 supplies the jump-to-annotation nav seam → cards non-clickable.
            onJumpToAnnotation = null,
            onDismiss = { closeSheet() },
        )
        // feature #134 WI-5 — the Book Details sheet. Rendered only when there IS a model (the Details
        // route is only reachable when [bookDetails] fed the More menu); a null model is a safe no-op.
        ReaderSheet.Details -> if (bookDetails != null) BookDetailsSheet(
            theme = theme,
            model = bookDetails,
            onCopyFingerprint = onCopyFingerprint,
            onShare = onShareBook,
            onDismiss = { closeSheet() },
            onImportAnnotations = onImportAnnotations,
        )
        // feature #135 WI-6 — the Bookmarks route opens the SAME two-tab sheet with the Bookmarks tab
        // pre-selected (the designed [TocBookmarksSheet]; rule 51 — no invented list surface).
        ReaderSheet.Bookmarks -> TocBookmarksSheet(
            theme = theme,
            bookTitle = chrome.title,
            entries = chrome.tocEntries,
            currentTocIndex = chrome.currentTocIndex,
            bookmarks = bookmarks,
            onJumpToc = onJumpToc,
            onJumpBookmark = onJumpBookmark,
            onDismiss = { closeSheet() },
            initialTab = TocTab.Bookmarks,
        )
    }

    // feature #165 WI-7 — the designed import preview/confirm sheet, rendered AFTER the route sheets so a
    // stacked presentation puts it on top.
    importSheet?.invoke()
}
