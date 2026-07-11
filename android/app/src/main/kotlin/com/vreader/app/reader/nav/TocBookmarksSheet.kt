// Purpose: feature #135 WI-6 (#110 Phase 3) — the reader `TocBookmarksSheet`, the promotion of #132's
// single-pane Contents sheet to the DESIGNED two-tab `TOCSheet` (vreader-panels.jsx `TOCSheet` —
// `Contents | Bookmarks` segmented tab bar). This is a NEW WRAPPER file: it hosts the tab bar and REUSES
// #132's [TocContentsSheetContent] UNCHANGED as the Contents tab body (one-writer serialization — WI-6
// does NOT edit `TocContentsSheet.kt` in place, so #132's file stays untouched). The Bookmarks tab renders
// rows from a `List<BookmarkRowItem>` (WI-4's [BookmarkRowUi] paired with its source [BookmarkRecord]):
// each row is the design's OUTLINE bookmark icon (accent, the design's stroked `Icons.Bookmark`) · italic
// serif preview · `chapter · p.N · date` sub-line · chevron. Tap-to-jump is capability-gated (a null
// [onJumpBookmark] leaves rows review-only, non-clickable) and dismisses ONLY on [JumpResult.Succeeded]; a
// [JumpResult.Failed] keeps the sheet open with NO invented error surface (the #132 §navigation-outcome
// posture). Empty bookmarks → the `bookmarks-empty` state. Bookmark row DELETION is DEFERRED to a follow-up
// WI (rule 51 — the delete surface is not built here); there is NO swipe/long-press/confirm delete control.
// Params fed by WI-7's host wiring; the scaffold + EPUB chrome route `ReaderSheet.Toc` here. Pure function
// of state (rule 50 §4); same [ReaderTheme] token map as the Contents sheet.
// @coordinates-with: nav/TocContentsSheet.kt (the REUSED Contents tab body — composed, never modified),
//   nav/BookmarkPresentation.kt (WI-4's BookmarkRowUi projection), annotations/Annotation.kt (BookmarkRecord),
//   chrome/ReaderChromeScaffold.kt + reader/EpubReaderChrome.kt (the Toc route call sites).
package com.vreader.app.reader.nav

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.annotations.BookmarkRecord
import com.vreader.app.reader.settings.ReaderTheme
import com.vreader.app.ui.theme.VReaderFonts

/**
 * The outcome of a bookmark jump. A jump can fail (EPUB `toReadium` null / `navigator.go` false; AZW3
 * goTo timeout/`ok=false`; TXT/PDF offset/page out of range). The Bookmarks tab dismisses the sheet ONLY
 * on [Succeeded]; on [Failed] it stays open with NO invented error surface (the #132 §navigation-outcome
 * posture; rule 51). Declared here (no `JumpResult` existed in the tree) as the shared jump-result type.
 */
enum class JumpResult { Succeeded, Failed }

/**
 * One Bookmarks-tab row: a stored [BookmarkRecord] paired with WI-4's per-format [BookmarkRowUi] display
 * projection. The host (WI-7) builds this list (projecting each record via [BookmarkPresentation.bookmarkRow]);
 * the sheet renders [ui] and passes [record] back to `onJumpBookmark` on a tap.
 */
data class BookmarkRowItem(
    val record: BookmarkRecord,
    val ui: BookmarkRowUi,
)

/** Which tab of the two-tab TOC sheet is active. Persisted across config change via [rememberSaveable]. */
enum class TocTab { Contents, Bookmarks }

/**
 * The two-tab reader TOC sheet as a [ModalBottomSheet]. [bookTitle] is the sheet header (the design's
 * book-title `Sheet` title). [entries]/[currentTocIndex] drive the Contents tab (the REUSED
 * [TocContentsSheetContent]); [bookmarks] drive the Bookmarks tab. [onJumpToc] performs a TOC jump
 * (returns success for dismiss-on-success); [onJumpBookmark] is the capability-based nullable bookmark
 * jump — a non-null callback makes bookmark rows clickable + dismisses on [JumpResult.Succeeded], a null
 * one leaves them review-only, non-clickable (the §review-sheet-contract gate — an unwired host passes
 * null; NO clickable dead rows). [onDismiss] closes the sheet. Renders in [theme]'s colors.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TocBookmarksSheet(
    theme: ReaderTheme,
    bookTitle: String,
    entries: List<TocEntry>,
    currentTocIndex: Int,
    bookmarks: List<BookmarkRowItem>,
    onJumpToc: (Int) -> Boolean,
    onJumpBookmark: ((BookmarkRecord) -> JumpResult)?,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
    initialTab: TocTab = TocTab.Contents,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = theme.background,
        modifier = modifier.testTag("toc-sheet"),
    ) {
        TocBookmarksSheetContent(
            theme = theme,
            bookTitle = bookTitle,
            entries = entries,
            currentTocIndex = currentTocIndex,
            bookmarks = bookmarks,
            onJumpToc = onJumpToc,
            onJumpBookmark = onJumpBookmark,
            onDismiss = onDismiss,
            initialTab = initialTab,
        )
    }
}

/**
 * The two-tab sheet's content, extracted from the [ModalBottomSheet] wrapper so it's directly UI-testable
 * (the `TocContentsSheetContent` precedent — a modal sheet's content renders in a separate window that
 * instrumented clicks reach unreliably). Renders the segmented `Contents | Bookmarks` tab bar, then the
 * active tab's body: Contents = #132's REUSED [TocContentsSheetContent] (unchanged); Bookmarks = the
 * bookmark rows or the `bookmarks-empty` state. Owns the active-tab state (survives config change via
 * [rememberSaveable]) and the dismiss-on-success/dismiss-on-Succeeded decision.
 */
@Composable
fun TocBookmarksSheetContent(
    theme: ReaderTheme,
    bookTitle: String,
    entries: List<TocEntry>,
    currentTocIndex: Int,
    bookmarks: List<BookmarkRowItem>,
    onJumpToc: (Int) -> Boolean,
    onJumpBookmark: ((BookmarkRecord) -> JumpResult)?,
    onDismiss: () -> Unit = {},
    initialTab: TocTab = TocTab.Contents,
) {
    var tab by rememberSaveable { mutableStateOf(initialTab) }

    Column(
        Modifier
            .fillMaxWidth()
            .background(theme.background)
            .testTag("toc-bookmarks-sheet-content"),
    ) {
        TocTabBar(theme = theme, active = tab, onSelect = { tab = it })
        when (tab) {
            // The Contents tab body is #132's TocContentsSheet, REUSED UNCHANGED (composed, not modified).
            TocTab.Contents -> TocContentsSheetContent(
                theme = theme,
                bookTitle = bookTitle,
                entries = entries,
                currentTocIndex = currentTocIndex,
                onJump = onJumpToc,
                onDismiss = onDismiss,
            )
            TocTab.Bookmarks -> BookmarksTab(
                theme = theme,
                bookmarks = bookmarks,
                onJumpBookmark = onJumpBookmark,
                onDismiss = onDismiss,
            )
        }
    }
}

/**
 * The `Contents | Bookmarks` segmented tab bar (the design's rounded pill container with an active-tab
 * raised chip). Each tab is a full-width equal button; the active one gets the raised/highlighted
 * background. testTags: `toc-tab-contents` / `toc-tab-bookmarks`.
 */
@Composable
private fun TocTabBar(theme: ReaderTheme, active: TocTab, onSelect: (TocTab) -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(start = 18.dp, end = 18.dp, top = 10.dp, bottom = 2.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(theme.ink.copy(alpha = if (theme.isDark) 0.06f else 0.05f))
            .padding(3.dp),
        horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        TocTabButton(theme, "Contents", TocTab.Contents, active, onSelect, "toc-tab-contents")
        TocTabButton(theme, "Bookmarks", TocTab.Bookmarks, active, onSelect, "toc-tab-bookmarks")
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.TocTabButton(
    theme: ReaderTheme,
    label: String,
    tab: TocTab,
    active: TocTab,
    onSelect: (TocTab) -> Unit,
    testTag: String,
) {
    val on = tab == active
    // The active chip is a raised panel (design: `#fff` light / `#3a3530` dark); inactive is transparent.
    val chipBg = if (on) {
        if (theme.isDark) theme.ink.copy(alpha = 0.18f) else theme.background
    } else {
        androidx.compose.ui.graphics.Color.Transparent
    }
    Box(
        Modifier
            .weight(1f)
            .clip(RoundedCornerShape(8.dp))
            .background(chipBg)
            .clickable { onSelect(tab) }
            .heightIn(min = 40.dp)
            .padding(vertical = 7.dp)
            .testTag(testTag)
            .semantics { contentDescription = "$label tab${if (on) ", selected" else ""}" },
        contentAlignment = Alignment.Center,
    ) {
        Text(
            label,
            color = theme.ink,
            fontFamily = VReaderFonts.Sans,
            fontSize = 13.sp,
            fontWeight = if (on) FontWeight.SemiBold else FontWeight.Medium,
        )
    }
}

/**
 * The Bookmarks tab body — the bookmark rows or the `bookmarks-empty` state. Tap-to-jump is capability-based:
 * a non-null [onJumpBookmark] makes each row clickable and dismisses the sheet ONLY when the jump returns
 * [JumpResult.Succeeded] (a [JumpResult.Failed] keeps the sheet open — rule 51 §nav-error-presentation); a
 * null callback leaves rows review-only, NOT clickable (the §review-sheet-contract gate — NO clickable dead
 * rows for an unwired host). NO delete affordance (deferred).
 */
@Composable
private fun BookmarksTab(
    theme: ReaderTheme,
    bookmarks: List<BookmarkRowItem>,
    onJumpBookmark: ((BookmarkRecord) -> JumpResult)?,
    onDismiss: () -> Unit,
) {
    if (bookmarks.isEmpty()) {
        BookmarksEmptyState(theme)
        return
    }
    Column(
        Modifier
            .fillMaxWidth()
            .heightIn(max = 560.dp)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 18.dp, vertical = 8.dp),
    ) {
        bookmarks.forEach { item ->
            BookmarkRow(
                theme = theme,
                item = item,
                // Capability gate: only a non-null jump makes the row clickable. Dismiss-on-Succeeded — a
                // Failed jump keeps the sheet open (no error surface — rule 51 §nav-error-presentation).
                onClick = onJumpBookmark?.let { jump ->
                    { if (jump(item.record) == JumpResult.Succeeded) onDismiss() }
                },
            )
        }
    }
}

/**
 * One Bookmarks-tab row (vreader-panels.jsx `TOCSheet` Bookmarks tab): a leading OUTLINE bookmark icon
 * (accent, matching the design's stroked `Icons.Bookmark`), a column with the italic serif
 * [BookmarkRowUi.preview] and the `chapter · p.N · date` meta sub-line, and a trailing chevron. The row is
 * clickable → [onClick] ONLY when [onClick] is non-null (the capability gate — a null callback leaves it
 * review-only, no ripple, no dead no-op). testTag `bookmark-row-${record.id}`. NO delete control.
 */
@Composable
private fun BookmarkRow(theme: ReaderTheme, item: BookmarkRowItem, onClick: (() -> Unit)?) {
    val ui = item.ui
    val sub = theme.ink.copy(alpha = 0.55f)
    // The design's primary line is the italic preview; when a bookmark has no preview (EPUB/AZW3/PDF) the
    // chapter — else "Bookmark" — stands in so the row is never blank (still italic serif, per the design).
    val primary = ui.preview ?: ui.chapter ?: "Bookmark"
    val meta = bookmarkMeta(ui)
    val a11y = buildString {
        append("Bookmark: $primary")
        if (meta.isNotEmpty()) append(", $meta")
    }
    val base = Modifier
        .fillMaxWidth()
    // Capability gate: attach a click only when a jump callback exists — a null callback leaves the row
    // non-clickable (no ripple, no dead no-op — matches the review BookmarkCard).
    val rowModifier = (if (onClick != null) base.clickable { onClick() } else base)
        .heightIn(min = 48.dp)
        .padding(vertical = 14.dp)
        .testTag("bookmark-row-${item.record.id}")
        .semantics { contentDescription = a11y }
    Row(
        rowModifier,
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(
            Icons.Outlined.BookmarkBorder,
            contentDescription = null,
            tint = theme.accent,
            modifier = Modifier.size(18.dp),
        )
        Column(Modifier.weight(1f)) {
            Text(
                primary,
                color = theme.ink,
                fontFamily = VReaderFonts.Serif,
                fontStyle = FontStyle.Italic,
                fontSize = 14.sp,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            if (meta.isNotEmpty()) {
                Text(
                    meta,
                    modifier = Modifier.padding(top = 4.dp),
                    color = sub,
                    fontFamily = VReaderFonts.Sans,
                    fontSize = 11.sp,
                )
            }
        }
        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = sub,
            modifier = Modifier.size(16.dp),
        )
    }
    // The design's per-row bottom hairline rule.
    Box(
        Modifier
            .fillMaxWidth()
            .height(0.5.dp)
            .background(theme.ink.copy(alpha = 0.10f)),
    )
}

/**
 * The design's `chapter · p.N · date` meta sub-line — only the present parts, joined by " · ". A row
 * with no chapter/page (TXT/MD, which carry a preview instead) shows just the date; nothing is fabricated.
 */
private fun bookmarkMeta(ui: BookmarkRowUi): String =
    listOfNotNull(ui.chapter, ui.pageLabel, ui.dateLabel.takeIf { it.isNotBlank() })
        .joinToString(" · ")

/** The Bookmarks-tab empty state — shown when the book has no bookmarks. */
@Composable
private fun BookmarksEmptyState(theme: ReaderTheme) {
    Box(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 120.dp)
            .padding(24.dp)
            .testTag("bookmarks-empty"),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            "No bookmarks",
            color = theme.ink.copy(alpha = 0.55f),
            fontFamily = VReaderFonts.Sans,
            fontSize = 15.sp,
        )
    }
}
