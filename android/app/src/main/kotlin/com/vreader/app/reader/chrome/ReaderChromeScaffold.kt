// Purpose: feature #132 WI-5 (#110 Phase 3) — the host-agnostic reader chrome scaffold that stitches
// the designed reader chrome + modal sheets over any reader body. It stacks [ReaderTopChrome] (WI-2) at
// the top, the host's [body] filling the middle, and the host's [bottomChrome] at the bottom — passing
// the Contents/Notes open callbacks INTO the bottom-chrome slot so the host wires them without reaching
// into scaffold state. A center-tap on the body toggles chrome visibility (the top + bottom bars hide
// together). It hosts the two #132 modal sheets driven by the hoisted [ReaderChromeState.sheet]:
// [ReaderSheet.Toc] → the WI-3 [TocContentsSheet], [ReaderSheet.Notes] → the WI-4 [AnnotationsReviewSheet].
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
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import com.vreader.app.annotations.AnnotationItem
import com.vreader.app.annotations.AnnotationsReviewSheet
import com.vreader.app.annotations.AnnotationsSnapshot
import com.vreader.app.reader.nav.TocContentsSheet
import com.vreader.app.reader.nav.TocEntry
import com.vreader.app.reader.settings.ReaderTheme

/**
 * The host-agnostic reader chrome scaffold. [chromeState] is the hoisted [ReaderChromeState]
 * (visibility + open sheet). [title] fills the top bar; [onBack] fires the "‹ Library" control;
 * [onOpenSearch]/[onOpenMore] populate the top-bar trailing cluster (null → omitted; #133/#134);
 * [topBookmarkSlot] fills the top-bar bookmark slot (null in #132; #135). [tocEntries]/[currentTocIndex]
 * drive the Contents sheet (empty entries → the Contents control is hidden). [annotations] is the
 * one-shot snapshot for the Notes sheet; [onJumpToc] performs a TOC jump (returns success for
 * dismiss-on-success); [onJumpToAnnotation] is the capability-based nullable annotation jump;
 * [onShareAnnotations] is the sheet-level Share. [bottomChrome] receives the Contents/Notes open
 * callbacks (a null Contents callback when [tocEntries] is empty) and renders the reader's bottom chrome.
 * [body] is the reader content; a center-tap on it toggles [ReaderChromeState.chromeVisible].
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
) {
    val state = chromeState.value

    // Contents is available only when there IS a table of contents; an empty TOC hides the control
    // (the scaffold hands the bottom chrome a null open callback, so it omits it — no dead control).
    val onOpenContents: (() -> Unit)? =
        if (tocEntries.isEmpty()) null
        else { { chromeState.value = state.copy(sheet = ReaderSheet.Toc) } }
    val onOpenNotes: () -> Unit = { chromeState.value = state.copy(sheet = ReaderSheet.Notes) }

    Column(modifier.fillMaxSize().background(theme.background)) {
        if (state.chromeVisible) {
            ReaderTopChrome(
                theme = theme,
                title = title,
                onBack = onBack,
                onSearch = onOpenSearch,
                onMore = onOpenMore,
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

    // Modal sheets — driven by the hoisted open-sheet state. Dismiss returns to [ReaderSheet.None].
    when (state.sheet) {
        ReaderSheet.None -> Unit
        ReaderSheet.Toc -> TocContentsSheet(
            theme = theme,
            bookTitle = title,
            entries = tocEntries,
            currentTocIndex = currentTocIndex,
            onJump = onJumpToc,
            onDismiss = { chromeState.value = state.copy(sheet = ReaderSheet.None) },
        )
        ReaderSheet.Notes -> AnnotationsReviewSheet(
            theme = theme,
            snapshot = annotations,
            onShareAll = onShareAnnotations,
            onJumpToAnnotation = onJumpToAnnotation,
            onDismiss = { chromeState.value = state.copy(sheet = ReaderSheet.None) },
        )
    }
}
