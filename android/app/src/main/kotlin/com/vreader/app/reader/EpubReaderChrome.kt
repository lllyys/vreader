// Purpose: feature #132 WI-7-EPUB (#110 Phase 3) — the Compose chrome CONTENT for the EPUB reader host
// (ReaderActivity). The EPUB host is the outlier: a Readium EpubNavigatorFragment (a View) renders the
// page under the chrome, so — unlike the Compose-native TXT/PDF/AZW3 hosts — it CANNOT wrap the
// full-screen ReaderChromeScaffold (which owns a `weight(1f)` composable body). Instead the host stacks
// THREE separately-sized ComposeViews over the fragment's FrameLayout, each rendered by one composable
// here and each fed the persistent MutableStateFlow<ReaderChromeModel> + a hoisted ReaderChromeState:
//   • [EpubTopBand]    — the top ComposeView (title + "‹ Library"); sized to the top chrome only.
//   • [EpubBottomBand] — the bottom ComposeView (progress + Contents/Notes/Display toolbar); sized to the
//                         bottom chrome only. Contents shown only when the model's TOC is non-empty.
//   • [EpubReaderSheets] — a full-screen ComposeView that is EMPTY (renders nothing, so it does not cover
//                         the fragment) until a sheet is open, at which point it lays a full-screen dismiss
//                         overlay + the Contents/Notes ModalBottomSheet. This "open-only" full-screen
//                         posture is what keeps the Readium fragment's scroll/selection/link input working
//                         while no sheet is up — the top/bottom bands only cover the chrome regions.
// Contents onJump → the host's `navigator.go(entry.epubReadiumLocator)` (Boolean): dismiss on success,
// stay-open on false, NO invented error surface (rule 51 §nav-error-presentation). Notes → the WI-4 review
// sheet with onJumpToAnnotation NULL (EPUB review-only, cards non-clickable, until #135 supplies the nav
// seam). Pure functions of state + callbacks (rule 50 §4); same ReaderTheme token map as the other hosts.
// @coordinates-with: ReaderActivity.kt (owns the StateFlow + the ComposeViews + the navigator jump),
//   ReaderChromeModel.kt (the collected model), chrome/ReaderTopChrome + chrome/ReaderBottomChrome
//   (the reused designed bands), chrome/ReaderChromeState (the hoisted sheet/visibility state),
//   nav/TocContentsSheet + annotations/AnnotationsReviewSheet (the two modal sheets).
package com.vreader.app.reader

import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.vreader.app.annotations.AnnotationsReviewSheet
import com.vreader.app.reader.chrome.ReaderBottomChrome
import com.vreader.app.reader.chrome.ReaderChromeState
import com.vreader.app.reader.chrome.ReaderSheet
import com.vreader.app.reader.chrome.ReaderTopChrome
import com.vreader.app.reader.nav.TocContentsSheet
import com.vreader.app.reader.settings.ReaderTheme
import kotlinx.coroutines.flow.StateFlow

/**
 * The EPUB top chrome band — the title + "‹ Library" back control (the WI-2 [ReaderTopChrome]). Rendered
 * in its OWN top ComposeView sized to WRAP_CONTENT so it covers only the top strip; the Readium fragment
 * fills the rest. [model] supplies the live title; [onBack] fires the back control. Search/More/bookmark
 * top-bar slots stay null (#133/#134/#135 — no dead controls).
 */
@Composable
fun EpubTopBand(
    model: StateFlow<ReaderChromeModel>,
    theme: ReaderTheme,
    onBack: () -> Unit,
) {
    val chrome by model.collectAsStateWithLifecycle()
    ReaderTopChrome(theme = theme, title = chrome.title, onBack = onBack)
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
 * The EPUB modal-sheet layer — the open-only full-screen dismiss overlay + the Contents / Notes sheets.
 * Rendered in a FULL-SCREEN ComposeView that renders NOTHING while [ReaderChromeState.sheet] is
 * [ReaderSheet.None] (so it does not cover the fragment); the instant a sheet opens it lays a full-screen
 * dismiss overlay (a transparent scrim that dismisses the sheet on an outside tap) beneath the
 * ModalBottomSheet. This keeps the Readium fragment's scroll/selection/link input alive whenever no sheet
 * is up.
 *
 * [onJumpToc] performs the native-locator TOC jump (returns success → the Contents sheet dismisses on
 * success, stays open on false — no invented error surface). [onShareAnnotations] is the sheet-level Share.
 * EPUB Notes cards are review-only (onJumpToAnnotation NULL) until #135.
 */
@Composable
fun EpubReaderSheets(
    model: StateFlow<ReaderChromeModel>,
    theme: ReaderTheme,
    chromeState: MutableState<ReaderChromeState>,
    onJumpToc: (Int) -> Boolean,
    onShareAnnotations: () -> Unit,
) {
    val chrome by model.collectAsStateWithLifecycle()
    val sheet = chromeState.value.sheet
    if (sheet is ReaderSheet.None) return // render nothing → the fragment keeps all input

    fun closeSheet() { chromeState.value = chromeState.value.copy(sheet = ReaderSheet.None) }

    // The open-only full-screen dismiss overlay — a transparent scrim under the sheet. An outside tap
    // (a tap that reaches the scrim, not the sheet) closes the sheet. Present ONLY while a sheet is open.
    Box(
        Modifier
            .fillMaxSize()
            .testTag("epub-sheet-dismiss-overlay")
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { closeSheet() },
    )

    when (sheet) {
        ReaderSheet.None -> Unit
        ReaderSheet.Toc -> TocContentsSheet(
            theme = theme,
            bookTitle = chrome.title,
            entries = chrome.tocEntries,
            currentTocIndex = chrome.currentTocIndex,
            // Dismiss-on-success: TocContentsSheet dismisses ONLY when onJump returns true; a false return
            // keeps the sheet open with NO invented error surface (rule 51 §nav-error-presentation).
            onJump = onJumpToc,
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
    }
}
