// Purpose: feature #132 WI-4 (#110 Phase 3) — the annotations review sheet (design
// vreader-android-annotations.jsx `AnnotationsSheet`, the reader's "Notes" surface) as a
// `ModalBottomSheet` over WI-6b's [AnnotationsSnapshot]. Renders `All / Highlights / Notes` filter
// chips (NO Bookmarks chip — that arrives with #135), a `HighlightCard` per highlight + a
// `StandaloneNoteCard` per note (NO `BookmarkCard` — #135), an empty state, and the design's
// sheet-level trailing Share control (`onShareAll`, `AnnotationsSheet trailing={<Share/>}`). Tap-to-jump
// on the card body is capability-based: a non-null `onJumpToAnnotation` makes cards clickable and jumps;
// a null one leaves them review-only, non-clickable (§review-sheet-contract — EPUB/AZW3 pass null before
// #135 supplies their nav seam). Per-card Copy/Share and the `⋯` Edit/Delete menu are NOT depicted on the
// Android cards and are NOT built (rule 51 gate). Pure function of state (rule 50 §4); same [ReaderTheme]
// token map as the reader chrome / Contents sheet.
package com.vreader.app.annotations

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.reader.settings.ReaderTheme
import com.vreader.app.ui.theme.VReaderFonts

/** The review sheet's filter chips (design `FilterChips` minus the `Bookmarks` chip — that is #135). */
enum class AnnotationFilter(val label: String) {
    All("All"),
    Highlights("Highlights"),
    Notes("Notes"),
    ;

    /** The stable testTag suffix (`annot-filter-all` / `-highlights` / `-notes`). */
    val tag: String get() = name.lowercase()
}

/**
 * The annotations review sheet as a [ModalBottomSheet]. [snapshot] is WI-6b's one-shot read of a book's
 * highlights + notes. [onShareAll] is the design's sheet-level trailing Share. [onJumpToAnnotation] is
 * the capability-based nullable tap-to-jump (null → cards are review-only, non-clickable). [onDismiss]
 * closes the sheet. Renders in [theme]'s colors.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AnnotationsReviewSheet(
    theme: ReaderTheme,
    snapshot: AnnotationsSnapshot,
    onShareAll: () -> Unit,
    onJumpToAnnotation: ((AnnotationItem) -> Unit)?,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = theme.background,
        modifier = modifier.testTag("annotations-sheet"),
    ) {
        AnnotationsReviewSheetContent(
            theme = theme,
            snapshot = snapshot,
            onShareAll = onShareAll,
            onJumpToAnnotation = onJumpToAnnotation,
        )
    }
}

/**
 * The review sheet's content, extracted from the [ModalBottomSheet] wrapper so it's directly UI-testable
 * (the `TocContentsSheetContent` precedent — a modal sheet's content renders in a separate window that
 * instrumented clicks reach unreliably). Owns the filter state (survives config change via
 * [rememberSaveable]). Renders the filter chip row, then the filtered cards or the empty state, with the
 * sheet-level Share pinned in the header.
 */
@Composable
fun AnnotationsReviewSheetContent(
    theme: ReaderTheme,
    snapshot: AnnotationsSnapshot,
    onShareAll: () -> Unit,
    onJumpToAnnotation: ((AnnotationItem) -> Unit)?,
) {
    var filter by rememberSaveable { mutableStateOf(AnnotationFilter.All) }
    val items = remember(snapshot, filter) { itemsFor(snapshot, filter) }

    Column(
        Modifier
            .fillMaxWidth()
            .background(theme.background)
            .testTag("annotations-sheet-content"),
    ) {
        Header(theme = theme, onShareAll = onShareAll)
        FilterChipRow(theme = theme, active = filter, onSelect = { filter = it })

        if (items.isEmpty()) {
            AnnotationsEmptyState(theme)
            return@Column
        }

        Column(
            Modifier
                .fillMaxWidth()
                .heightIn(max = 560.dp)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 8.dp),
        ) {
            items.forEach { item ->
                when (item) {
                    is AnnotationItem.Highlight -> HighlightCard(theme, item.record, onJumpToAnnotation)
                    is AnnotationItem.Note -> StandaloneNoteCard(theme, item.record, onJumpToAnnotation)
                }
            }
        }
    }
}

/** The filtered, deterministically-ordered items for [filter]. All = highlights then notes. */
private fun itemsFor(snapshot: AnnotationsSnapshot, filter: AnnotationFilter): List<AnnotationItem> {
    val highlights = snapshot.highlights.map { AnnotationItem.Highlight(it) }
    val notes = snapshot.notes.map { AnnotationItem.Note(it) }
    return when (filter) {
        AnnotationFilter.All -> highlights + notes
        AnnotationFilter.Highlights -> highlights
        AnnotationFilter.Notes -> notes
    }
}

/** The sheet header: the title + the design's trailing Share (`AnnotationsSheet trailing={<Share/>}`). */
@Composable
private fun Header(theme: ReaderTheme, onShareAll: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(start = 18.dp, end = 8.dp, top = 12.dp, bottom = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            "Annotations",
            modifier = Modifier.weight(1f),
            color = theme.ink,
            fontFamily = VReaderFonts.Serif,
            fontSize = 17.sp,
            fontWeight = FontWeight.SemiBold,
        )
        Box(
            Modifier
                .clip(RoundedCornerShape(50))
                .clickable { onShareAll() }
                .size(44.dp)
                .testTag("annot-share")
                .semantics { contentDescription = "Share all annotations" },
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.Share, contentDescription = null, tint = theme.accent)
        }
    }
}

/** The `All / Highlights / Notes` chip row (design `FilterChips`, minus the #135 Bookmarks chip). */
@Composable
private fun FilterChipRow(theme: ReaderTheme, active: AnnotationFilter, onSelect: (AnnotationFilter) -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        AnnotationFilter.entries.forEach { chip ->
            val on = chip == active
            Text(
                chip.label,
                modifier = Modifier
                    .clip(RoundedCornerShape(100))
                    .clickable { onSelect(chip) }
                    .background(if (on) theme.ink else theme.ink.copy(alpha = if (theme.isDark) 0.06f else 0.05f))
                    .heightIn(min = 34.dp)
                    .padding(horizontal = 14.dp, vertical = 7.dp)
                    .testTag("annot-filter-${chip.tag}")
                    .semantics { contentDescription = "${chip.label} filter${if (on) ", selected" else ""}" },
                color = if (on) theme.background else theme.ink,
                fontFamily = VReaderFonts.Sans,
                fontSize = 13.sp,
                fontWeight = if (on) FontWeight.SemiBold else FontWeight.Medium,
            )
        }
    }
}

/** The empty state — shown when the selected filter yields no cards (design's "Nothing saved yet"). */
@Composable
private fun AnnotationsEmptyState(theme: ReaderTheme) {
    Column(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 160.dp)
            .padding(horizontal = 30.dp, vertical = 48.dp)
            .testTag("annot-empty"),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            "Nothing saved yet",
            color = theme.ink,
            fontFamily = VReaderFonts.Serif,
            fontSize = 19.sp,
        )
        Text(
            "Press and hold a passage to highlight it, or jot a standalone note.",
            modifier = Modifier.padding(top = 8.dp),
            color = theme.ink.copy(alpha = 0.62f),
            fontFamily = VReaderFonts.Sans,
            fontSize = 14.sp,
        )
    }
}
