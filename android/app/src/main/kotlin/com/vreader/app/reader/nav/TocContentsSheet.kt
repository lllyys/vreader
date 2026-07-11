// Purpose: feature #132 WI-3 (#110 Phase 3) — the reader Contents sheet (vreader-panels.jsx
// `TOCSheet` **Contents tab**) as a SINGLE-PANE `ModalBottomSheet`. #132 renders ONLY the Contents
// pane — NOT a two-tab sheet with a dead Bookmarks tab; #135 promotes this to the full two-tab
// `TOCSheet` when it has a Bookmarks data source (documented handoff, the #129 no-dead-controls rule).
// Faithful to the design's `Sheet` chrome: a centered serif header showing the BOOK TITLE (the design's
// `title="Pride and Prejudice"`), a bottom rule, then [TocEntry] rows (chapter# · title · p.N) with the
// [currentTocIndex] row highlighted. Tapping a row calls `onJump(index)` which returns a `Boolean` —
// the sheet dismisses ONLY on a successful jump (true), and on a failed/stale jump (false) STAYS OPEN
// with NO invented error surface (rule 51 §nav-error-presentation). Empty entries → the `toc-empty`
// state. The sibling of the #129 reader chrome; same [ReaderTheme] token map. Pure fn of state (rule 50 §4).
package com.vreader.app.reader.nav

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.reader.settings.ReaderTheme
import com.vreader.app.ui.theme.VReaderFonts

/**
 * The reader Contents sheet. [bookTitle] is the sheet header (the design's book-title `Sheet` title).
 * [entries] are the flattened TOC (WI-1's [TocEntry]); the row at [currentTocIndex] is highlighted.
 * [onJump] receives the tapped row index and returns whether the navigation succeeded — the sheet
 * dismisses (calls [onDismiss]) ONLY when it returns `true`; a `false` return keeps the sheet open
 * (no invented error surface). Renders in [theme]'s colors.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TocContentsSheet(
    theme: ReaderTheme,
    bookTitle: String,
    entries: List<TocEntry>,
    currentTocIndex: Int,
    onJump: (Int) -> Boolean,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = theme.background,
        modifier = modifier.testTag("toc-sheet"),
    ) {
        TocContentsSheetContent(
            theme = theme,
            bookTitle = bookTitle,
            entries = entries,
            currentTocIndex = currentTocIndex,
            onJump = onJump,
            onDismiss = onDismiss,
        )
    }
}

/**
 * The Contents sheet's content, extracted from the [ModalBottomSheet] wrapper so it's directly
 * UI-testable (the `AssignSheetContent` precedent — the wrapper drives the same content). [bookTitle]
 * is the centered serif header (the design's `Sheet` book-title). Owns the **dismiss-on-success**
 * decision: tapping a row calls [onJump]; when it returns `true` the sheet dismisses via [onDismiss];
 * when it returns `false` NOTHING happens — the sheet stays open, no invented error surface (rule 51
 * §nav-error-presentation). Renders the empty state when [entries] is empty. [onDismiss] defaults to a
 * no-op so a caller that only wants to render rows can omit it.
 */
@Composable
fun TocContentsSheetContent(
    theme: ReaderTheme,
    bookTitle: String,
    entries: List<TocEntry>,
    currentTocIndex: Int,
    onJump: (Int) -> Boolean,
    onDismiss: () -> Unit = {},
) {
    Column(
        Modifier
            .fillMaxWidth()
            .background(theme.background)
            .testTag("toc-sheet-content"),
    ) {
        // The design's `Sheet` header — the BOOK TITLE, centered serif with a bottom rule. #132 is
        // Contents-only; there is NO Bookmarks tab bar (that arrives with #135), so no dead/disabled
        // tab selector is rendered (the design's tab bar lights up only when both tabs have data).
        Text(
            bookTitle,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 18.dp, vertical = 12.dp)
                .testTag("toc-title"),
            color = theme.ink,
            fontFamily = VReaderFonts.Serif,
            fontSize = 17.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
        )
        // Header bottom rule (the design's `Sheet` divider).
        Box(
            Modifier
                .fillMaxWidth()
                .height(0.5.dp)
                .background(theme.ink.copy(alpha = 0.08f)),
        )

        if (entries.isEmpty()) {
            TocEmptyState(theme)
            return@Column
        }

        Column(
            Modifier
                .fillMaxWidth()
                .heightIn(max = 560.dp)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 10.dp, vertical = 8.dp),
        ) {
            entries.forEachIndexed { index, entry ->
                TocContentsRow(
                    theme = theme,
                    entry = entry,
                    index = index,
                    isCurrent = index == currentTocIndex,
                    // Dismiss-on-success: dismiss ONLY when the jump reports success. On a failed/stale
                    // jump the sheet stays open (no snackbar / error copy — rule 51 §nav-error-presentation).
                    onClick = { tapped -> if (onJump(tapped)) onDismiss() },
                )
            }
        }
    }
}
