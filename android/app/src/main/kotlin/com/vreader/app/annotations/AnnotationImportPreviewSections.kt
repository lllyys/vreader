// Purpose: feature #165 WI-5 — the three sections of the designed annotations-import preview sheet
// (`dev-docs/designs/vreader-fidelity-v1/project/vreader-annotation-import.jsx` `ImportPreviewSheet`,
// `:425-558`): the file header + source badge, the error blob, and the count chips + sample list +
// merge-policy line. Composed by `AnnotationImportPreviewSheet.kt` (which owns the sheet's state and
// action pair) out of the leaf pieces in `AnnotationImportPreviewParts.kt`. Pure functions of
// ([ReaderTheme], data) — no state, no I/O.
//
// Key decision: the file name is re-sanitized HERE, at the pixel, not only at the reader. It is
// provider-controlled, and only the `Ready` arm's name has provably been through
// `AnnotationsImportReader.parse`; a `Failed` state is constructed by the I/O layer from a name the
// reader may never have seen. `sanitizeDisplayName` is idempotent, so paying it twice costs nothing
// and removes the "did that caller remember?" question entirely — the reader's own header states
// this doctrine, and Gate-4 round 1 found the failure arm bypassing it.
//
// RULE-51 FIDELITY LEDGER for this surface (absences are recorded, never invented around):
//  - RENDERED AS DEPICTED: the file header with the artboard's own JSON glyph and source badge
//    (`:449-475`), the Highlights / Notes / Skipped count chips (`:488-492`), the
//    "Preview · first three" sample list (`:495-530`), the merge-policy line (`:531-533`) and the
//    error blob (`:477-484`). The error branch REPLACES the chips + sample + merge line exactly as
//    the artboard's ternary does, and the header survives it.
//  - ABSENT (plan §3.3 A-3): the sample row's `<chapter> · p. <page>` meta text. The wire row
//    carries only `locatorJSON`; chapter titles are not derivable at import time and `page` exists
//    only for PDF. The depicted color dot is kept; only the un-derivable TEXT is dropped.
//  - ABSENT (recorded by this WI): a **Bookmarks** count chip. The artboard draws exactly three
//    chips and bookmarks are not one of them, so a fourth would be invented UI. Bookmarks are still
//    counted in `ImportPreview.importable`, i.e. in the primary button's number — the total the
//    user approves stays true; only the breakdown is partial. Pinned by
//    `AnnotationImportPreviewSheetTest.noBookmarksCountChip` so a stray addition goes RED.
//  - BLOCKED: needs-design (#2099) — the zero-importable state. The artboard's two states are
//    mutually exclusive on one `error` prop, so "read fine, nothing left to import" (a re-import,
//    an all-foreign-book file, a valid empty envelope) is a THIRD state it does not draw. Plan C-8
//    asks for the disabled primary "plus the designed error blob explaining why", but no artboard
//    and no shipped string supplies that copy, and the blob would HIDE the `Skipped` chip that is
//    the explanation. Until #2099 lands this renders only depicted elements: the chips, the merge
//    line and the depicted disabled `Import 0 items` — so the no-op is provably uncommittable and
//    nothing is invented. The empty sample list's heading + card are omitted for the same reason
//    (a heading promising three rows above nothing is worse than its absence); both absences are
//    pinned by tests.
//
// @coordinates-with AnnotationImportPreviewSheet (the only caller), AnnotationImportPreviewParts
// (the leaf pieces), AnnotationImportModels (ImportPreview / ImportFailure),
// IncomingBookResolver.sanitizeDisplayName (the shared, idempotent name sanitizer).
package com.vreader.app.annotations

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.imports.IncomingBookResolver
import com.vreader.app.reader.settings.ReaderTheme
import com.vreader.app.ui.theme.VReaderFonts

/** The design's error tint triplet (`:480-482`) — literal artboard values, not theme tokens. */
private val ERROR_FILL = Color(0x14C44A1A)
private val ERROR_STROKE = Color(0x55C44A1A)
private val ERROR_INK = Color(0xFFA43A14)

/** The artboard's `sources.vreader.label`, rendered uppercase as the badge's CSS does (`:469-474`).
 *  Exactly one format is importable, so the badge is a constant rather than a per-source lookup. */
private const val SOURCE_BADGE = "VREADER JSON"

/** The designed file header (`:449-475`): tinted JSON glyph, title, file name, source badge. */
@Composable
internal fun ImportFileHeader(theme: ReaderTheme, fileName: String) {
    // Provider-controlled text on its way to a pixel — sanitize regardless of which arm built it.
    val safeName = remember(fileName) {
        IncomingBookResolver.sanitizeDisplayName(fileName, format = null)
    }
    Row(
        Modifier
            .fillMaxWidth()
            .padding(start = 22.dp, end = 22.dp, top = 12.dp, bottom = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .clip(RoundedCornerShape(10.dp))
                .background(theme.accent.copy(alpha = 0.10f))
                .size(40.dp),
            contentAlignment = Alignment.Center,
        ) {
            ImportJsonFileIcon(tint = theme.accent, size = 20.dp)
        }
        Column(
            Modifier
                .weight(1f)
                .padding(horizontal = 12.dp),
        ) {
            Text(
                "Import annotations",
                color = theme.ink,
                fontFamily = VReaderFonts.Serif,
                fontSize = 17.sp,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                safeName,
                modifier = Modifier
                    .padding(top = 2.dp)
                    .testTag("annot-import-filename"),
                color = theme.sub(),
                fontFamily = FontFamily.Monospace,
                fontSize = 11.5.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Text(
            SOURCE_BADGE,
            modifier = Modifier
                .clip(RoundedCornerShape(100))
                .background(theme.ink.copy(alpha = if (theme.isDark) 0.06f else 0.05f))
                .padding(horizontal = 9.dp, vertical = 3.dp)
                .testTag("annot-import-source"),
            color = theme.sub(),
            fontFamily = VReaderFonts.Sans,
            fontSize = 10.5.sp,
            fontWeight = FontWeight.SemiBold,
        )
    }
}

/** The designed error blob (`:477-484`) — fixed shipped copy, never a path or provider detail. */
@Composable
internal fun ImportErrorBlob(theme: ReaderTheme, reason: ImportFailure) {
    Box(
        Modifier
            .fillMaxWidth()
            .padding(start = 22.dp, end = 22.dp, bottom = 16.dp),
    ) {
        Text(
            reason.userMessage,
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(12.dp))
                .background(ERROR_FILL)
                .border(1.dp, ERROR_STROKE, RoundedCornerShape(12.dp))
                .padding(horizontal = 14.dp, vertical = 12.dp)
                .testTag("annot-import-error"),
            color = ERROR_INK,
            fontFamily = VReaderFonts.Sans,
            fontSize = 12.5.sp,
            lineHeight = 18.sp,
        )
    }
}

/** Count chips + the "Preview · first three" list + the merge-policy line (`:486-534`). */
@Composable
internal fun ImportPreviewBody(theme: ReaderTheme, preview: ImportPreview) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(start = 22.dp, end = 22.dp, bottom = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        CountChip(theme, "HIGHLIGHTS", preview.highlights, "highlights", accented = true)
        CountChip(theme, "NOTES", preview.notes, "notes")
        CountChip(theme, "SKIPPED", preview.skipped, "skipped", muted = true)
    }
    Column(
        Modifier
            .fillMaxWidth()
            .padding(start = 22.dp, end = 22.dp, bottom = 12.dp),
    ) {
        // Omitted when there is nothing to preview — see this file's ledger (needs-design #2099).
        if (preview.sample.isNotEmpty()) {
            Text(
                "PREVIEW · FIRST THREE",
                modifier = Modifier
                    .padding(bottom = 8.dp)
                    .testTag("annot-import-sample-label"),
                color = theme.sub(),
                fontFamily = VReaderFonts.Sans,
                fontSize = 10.5.sp,
                fontWeight = FontWeight.SemiBold,
            )
            Column(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(12.dp))
                    .background(theme.card())
                    .testTag("annot-import-sample"),
            ) {
                preview.sample.forEachIndexed { index, row ->
                    if (index > 0) {
                        Box(
                            Modifier
                                .fillMaxWidth()
                                .height(0.5.dp)
                                .background(theme.rule()),
                        )
                    }
                    SampleRow(theme, row)
                }
            }
        }
        Text(
            buildAnnotatedString {
                append("Imports merge into ")
                withStyle(SpanStyle(color = theme.ink, fontWeight = FontWeight.Medium)) {
                    append(preview.bookTitle)
                }
                append(" by passage match. Existing notes are not overwritten.")
            },
            modifier = Modifier
                .padding(top = 8.dp)
                .testTag("annot-import-merge"),
            color = theme.sub(),
            fontFamily = VReaderFonts.Sans,
            fontSize = 11.sp,
            lineHeight = 16.sp,
        )
    }
}
