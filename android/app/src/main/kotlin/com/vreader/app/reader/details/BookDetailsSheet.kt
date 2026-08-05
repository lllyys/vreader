// Purpose: feature #134 WI-4 — the Book Details sheet (`vreader-book-details.jsx` `BookDetailsSheet`,
// Android stacked layout only) as a `ModalBottomSheet` over WI-1's [BookDetailsUiModel]. A non-interactive
// detail surface: the centered title/author block, tag chips, a `MetaList` of the rows Android has a data
// source for, a copy-fingerprint mini-action (payload = the FULL canonical key — §fingerprint), and a
// Share action (in the sheet's trailing control AND the ActionList). Rule-51 ABSENCE invariants held
// (Design-gate #1): NO cover art, NO "Tap to add cover" placeholder, NO Export, no author-when-null, no
// tag-when-empty, no Pages-when-null; Location is a read-only label with no mini-action. The content is
// split into a directly-composable [BookDetailsSheetContent] (the modal renders in a separate window
// instrumented clicks reach unreliably — the AnnotationsReviewSheetContent precedent). Reuses the
// [ReaderTheme] token map; pure function of state (rule 50 §4). The host (WI-5) routes `ReaderSheet.Details`
// here and supplies onCopyFingerprint (clipboard) / onShare (BookShareIntent) / onDismiss.
//
// feature #165 WI-6 — the sheet threads an OPTIONAL [onImportAnnotations] to the ActionList's designed
// `Import annotations…` row + merge-policy footnote (null → neither renders; the #134 capability-gate).
// The **NO Export invariant above STILL HOLDS** and is deliberately left standing — its reason is now
// `needs-design` #2085 (export FAILURE feedback is undepicted and no shipped string fits: all three of
// MainActivity's describe *import*, and "Couldn't open the file" is factually wrong for a write), not
// #134's original "no Android export subsystem" scope call. WI-8 retires the invariant when it builds
// the row. Adding an export affordance here before #2085 lands is self-designed UI (rule 51).
package com.vreader.app.reader.details

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.reader.settings.ReaderTheme
import com.vreader.app.ui.theme.VReaderFonts

// The design's derived tokens off [ReaderTheme.ink]/[isDark], shared with BookDetailsRows: secondary text
// (`t.sub`), the hairline divider (`t.rule`), and the card surface (`t.isDark ? rgba(...,0.04) : #fff`).
internal fun ReaderTheme.subColor(): Color = ink.copy(alpha = 0.62f)
internal fun ReaderTheme.ruleColor(): Color = ink.copy(alpha = if (isDark) 0.10f else 0.08f)
internal fun ReaderTheme.cardColor(): Color = if (isDark) Color(0x0AFFFFFF) else Color(0xFFFFFFFF)

/**
 * The Book Details sheet as a [ModalBottomSheet]. [model] is WI-1's assembled metadata. [onCopyFingerprint]
 * receives the FULL canonical key (the copy payload); [onShare] fires the share flow; [onDismiss] closes the
 * sheet. Renders in [theme]'s colors. Stacked layout only (no split / remote-only state). No cover art (the
 * missing-cover fallback is Design-gate #1) and **no Export action** — `BLOCKED: needs-design (#2085)`,
 * built in WI-8.
 *
 * feature #165 WI-6 — [onImportAnnotations] is the capability-gated annotation-import entry: non-null adds
 * the designed accent `Import annotations…` row + B1's merge-policy footnote to the ActionList; null (the
 * default) renders neither, so every pre-#165 caller keeps the exact card #134 shipped.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BookDetailsSheet(
    theme: ReaderTheme,
    model: BookDetailsUiModel,
    onCopyFingerprint: (String) -> Unit,
    onShare: () -> Unit,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
    onImportAnnotations: (() -> Unit)? = null,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = theme.background,
        modifier = modifier.testTag("book-details-sheet"),
    ) {
        BookDetailsSheetContent(
            theme = theme,
            model = model,
            onCopyFingerprint = onCopyFingerprint,
            onShare = onShare,
            onImportAnnotations = onImportAnnotations,
        )
    }
}

/**
 * The sheet's content, extracted from the [ModalBottomSheet] wrapper so it's directly UI-testable (the
 * `AnnotationsReviewSheetContent` precedent — a modal sheet's content renders in a separate window that
 * instrumented clicks reach unreliably). Renders: a header with the sheet-level trailing Share, the
 * scrollable stacked body (title/author + tag chips + `MetaList` + `ActionList`). NO cover art leads the
 * body — the title/author block does (Design-gate #1). [onImportAnnotations] is passed straight through to
 * [BookActionList]'s capability gate (#165 WI-6).
 */
@Composable
fun BookDetailsSheetContent(
    theme: ReaderTheme,
    model: BookDetailsUiModel,
    onCopyFingerprint: (String) -> Unit,
    onShare: () -> Unit,
    onImportAnnotations: (() -> Unit)? = null,
) {
    Column(
        Modifier
            .fillMaxWidth()
            .background(theme.background)
            .testTag("book-details-sheet-content"),
    ) {
        DetailsHeader(theme = theme, onShare = onShare)
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(start = 22.dp, end = 22.dp, top = 4.dp, bottom = 32.dp),
        ) {
            // No cover art (Design-gate #1) — the title/author block leads.
            BookTitleBlock(theme = theme, title = model.title, author = model.author)
            BookTagChips(theme = theme, tags = model.tags)
            BookMetaList(
                theme = theme,
                formatLabel = model.formatLabel,
                sizeLabel = model.sizeLabel,
                pagesLabel = model.pagesLabel,
                fingerprintDisplay = model.fingerprintDisplay,
                fingerprintFull = model.fingerprintFull,
                locationLabel = model.locationLabel,
                onCopyFingerprint = onCopyFingerprint,
            )
            BookActionList(
                theme = theme,
                onShare = onShare,
                onImportAnnotations = onImportAnnotations,
            )
        }
    }
}

/** The sheet header: the "Book details" title + the design's trailing Share (`trailing={<Share/>}`). */
@Composable
private fun DetailsHeader(theme: ReaderTheme, onShare: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(start = 22.dp, end = 8.dp, top = 12.dp, bottom = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            "Book details",
            modifier = Modifier.weight(1f),
            color = theme.ink,
            fontFamily = VReaderFonts.Serif,
            fontSize = 17.sp,
            fontWeight = FontWeight.SemiBold,
        )
        Box(
            Modifier
                .clip(RoundedCornerShape(50))
                .clickable(onClick = onShare)
                .size(44.dp)
                .testTag("details-share-header")
                .semantics { contentDescription = "Share book" },
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.Share, contentDescription = null, tint = theme.ink)
        }
    }
}
