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
//
// Feature #139 WI-6 made the row list LAZY (a `LazyColumn` scrolled to the current chapter on open,
// replacing a non-lazy `Column(verticalScroll)` + `forEachIndexed`): TXT/MD books reach ~1 859 TOC
// rows where an EPUB has ~30, and composing all of them ANRs. Zero visual delta — same rows, same
// chrome, same tokens, same testTags. Row titles are single-lined at this presentation layer because
// a TXT heading rule can match across a line terminator (#139 WI-2).
package com.vreader.app.reader.nav

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
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
 *
 * The rows are LAZY (#139 WI-6): only the visible window is composed, and the list opens scrolled to
 * [currentTocIndex], so a 1 859-row TXT TOC costs the same as a 30-row EPUB one.
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

        val listState = rememberLazyListState()
        // Open scrolled to the current chapter, so the designed highlighted row is actually on screen
        // for a book whose current chapter is row 1 500 of 1 859. `scrollToItem` is an INDEX JUMP: the
        // lazy layout composes the target window only, never the rows in between (an ANIMATED scroll
        // would walk all of them and defeat the LazyColumn). Keys are the cheap size + index — NEVER
        // `entries` itself: `List.equals` is O(n), so keying on a 1 859-entry list would re-walk it on
        // every recomposition, re-introducing the very cost this WI removes.
        LaunchedEffect(entries.size, currentTocIndex, listState) {
            if (currentTocIndex in entries.indices) listState.scrollToItem(currentTocIndex)
        }
        LazyColumn(
            state = listState,
            modifier = Modifier
                .fillMaxWidth()
                // The bounded height is LOAD-BEARING, not cosmetic: this list sits inside an outer
                // Column that offers an infinite max height, and a scrollable measured with infinite
                // vertical constraints THROWS ("Vertically scrollable component was measured with an
                // infinity maximum height constraints").
                .heightIn(max = 560.dp)
                .testTag("toc-list"),
            // The row inset moved from a `.padding(...)` MODIFIER to contentPadding: as a modifier it
            // would eat into the bounded height and sit outside the scrolling area, clipping the first
            // and last rows instead of scrolling with them.
            contentPadding = PaddingValues(horizontal = 10.dp, vertical = 8.dp),
        ) {
            itemsIndexed(entries) { index, entry ->
                // Single-line the title HERE, per visible row — off-screen entries are never touched.
                // A TXT rule can legitimately match across a line terminator (#139 WI-2), so a TXT
                // chapter title can carry an embedded newline; left alone it renders a taller row than
                // its neighbours. MD titles never can (WI-3), and EPUB titles are unaffected.
                val row = remember(entry) { entry.singleLinedTitle() }
                TocContentsRow(
                    theme = theme,
                    entry = row,
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

/**
 * This entry with its [TocEntry.title] rendered on a single line (see [collapseLineBreaks]).
 * Returns the receiver unchanged when nothing needed collapsing — the common case allocates nothing.
 */
private fun TocEntry.singleLinedTitle(): TocEntry {
    val raw = title ?: return this
    val collapsed = raw.collapseLineBreaks()
    return if (collapsed == raw) this else copy(title = collapsed)
}

/**
 * Every character that starts a new rendered line: LF, CR, VT, FF, NEL, LINE SEPARATOR, PARAGRAPH
 * SEPARATOR. Written as code points because NEL (U+0085) is NOT in Java's `Character.isWhitespace`,
 * so `isWhitespace()` alone would miss it.
 */
private fun Char.isLineBreak(): Boolean = when (code) {
    0x0A, 0x0D, 0x0B, 0x0C, 0x85, 0x2028, 0x2029 -> true
    else -> false
}

private fun Char.isSpaceOrBreak(): Boolean = isWhitespace() || isLineBreak()

/**
 * Collapse every whitespace run that SPANS a line break down to one space, and trim the ends.
 *
 * Deliberately narrower than the usual `replace(Regex("\\s+"), " ")`: a run with no line break — a
 * U+3000 IDEOGRAPHIC SPACE between CJK words, a tab — is left byte-for-byte alone. This normalizes a
 * rendering artifact (a title that would wrap), not the author's spacing, so no existing EPUB/MD/CJK
 * title changes appearance.
 */
private fun String.collapseLineBreaks(): String {
    if (none { it.isLineBreak() }) return trim { it.isSpaceOrBreak() }
    val out = StringBuilder(length)
    var i = 0
    while (i < length) {
        if (!this[i].isSpaceOrBreak()) {
            out.append(this[i])
            i++
            continue
        }
        var end = i
        var spansBreak = false
        while (end < length && this[end].isSpaceOrBreak()) {
            if (this[end].isLineBreak()) spansBreak = true
            end++
        }
        if (spansBreak) out.append(' ') else out.append(this, i, end)
        i = end
    }
    return out.toString().trim { it.isSpaceOrBreak() }
}
