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
// Feature #139 WI-6 made the row list LAZY (a `LazyColumn` opened AT the current chapter, replacing a
// non-lazy `Column(verticalScroll)` + `forEachIndexed`): TXT/MD books reach ~1 859 TOC rows where an
// EPUB has ~30, and composing all of them ANRs. Same rows, same chrome, same tokens, same testTags —
// the only intended visible deltas are that the list opens at the (already-designed) highlighted row
// instead of at the top, and that a title's embedded line breaks are removed, because a TXT heading
// rule can legitimately match across a line terminator (#139 WI-2).
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
import androidx.compose.runtime.key
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

        // OPEN AT the current chapter, so the designed highlighted row is actually on screen for a book
        // whose current chapter is row 1 500 of 1 859. SEEDING the first visible index (rather than
        // composing at the top and then jumping in a LaunchedEffect) means the very first measurement
        // starts at the target: the lazy layout composes exactly one window, never the top one as well,
        // and never the 1 499 rows in between.
        //
        // CONTRACT — the list is positioned ONCE, per (book, TOC). It deliberately does NOT follow a
        // later [currentTocIndex] change: this sheet is modal over the reader, so the reading position
        // cannot advance behind it, and re-positioning could only yank a user who is browsing the list.
        // A same-book index change therefore moves the highlight, never the viewport.
        //
        // Identity is the book's fingerprintKey (`format:sha256:byteCount`, baked into every WI-1
        // canonical locator) plus the row count — O(1). It is NEVER the list itself: `List.equals` is
        // O(n), so keying on a 1 859-entry list would re-walk it on every recomposition, re-introducing
        // the cost this WI removes.
        //
        // fingerprintKey rather than contentSHA256 alone (Gate-4 Low): the sha is not by itself a book
        // identity — the same bytes imported under a different format are a DIFFERENT book with a
        // different TOC, and would otherwise collide and wrongly inherit the previous book's scroll
        // position. fingerprintKey carries format + byteCount, so it cannot.
        val tocIdentity = entries[0].canonicalLocator.fingerprintKey
        val listState = key(tocIdentity, entries.size) {
            rememberLazyListState(
                initialFirstVisibleItemIndex = if (currentTocIndex in entries.indices) currentTocIndex else 0,
            )
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
                // Normalize the title HERE, per visible row — off-screen entries are never touched.
                // A TXT rule can legitimately match across a line terminator (#139 WI-2), so a TXT
                // chapter title can carry an embedded newline, which would otherwise spend one of the
                // row's two wrap lines on a hard break. MD titles never can (WI-3); EPUB titles have no
                // breaks either, but every title IS trimmed (see [withoutEmbeddedLineBreaks]).
                val row = remember(entry) { entry.withoutEmbeddedLineBreaks() }
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
 * This entry with its [TocEntry.title] normalized by [collapseLineBreaks] — no embedded line break,
 * and trimmed at both ends. NOT a promise of one RENDERED line: `TocContentsRow` wraps a long title
 * to `maxLines = 2` and that is unchanged; this only removes hard breaks from the string.
 *
 * Returns the receiver unchanged when normalization was a no-op, so an already-clean title (every
 * EPUB title, every MD title) allocates nothing.
 */
private fun TocEntry.withoutEmbeddedLineBreaks(): TocEntry {
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
 * Two deliberate scope decisions:
 * - **Interior spacing is preserved.** Narrower than the usual `replace(Regex("\\s+"), " ")`: a run
 *   with no line break — a U+3000 IDEOGRAPHIC SPACE between CJK words, a tab — is left byte-for-byte
 *   alone. Only the rendering artifact (a hard break inside a row's title) is normalized.
 * - **The ends ARE trimmed, for every title, break or no break.** That is intentional and matches the
 *   iOS port, whose TXT rules consume up to four leading spaces/U+3000/tabs into the matched line
 *   before it becomes a title. So an ordinary EPUB/MD title with stray leading or trailing whitespace
 *   does change: it loses that whitespace. Nothing else about it does.
 *
 * `internal` rather than `private` (feature #141 WI-1) so [TocTitleFilter.matchTitle] can be its
 * single other caller: the filter's ranges index the NORMALIZED title, so the predicate and the
 * renderer must consume the very same normalization — not two copies of it. Behavior is unchanged.
 */
internal fun String.collapseLineBreaks(): String {
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
