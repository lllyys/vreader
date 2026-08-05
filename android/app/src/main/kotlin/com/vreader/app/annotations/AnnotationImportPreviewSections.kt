// Purpose: feature #165 WI-5 — the presentational sections of the designed annotations-import
// preview sheet (`dev-docs/designs/vreader-fidelity-v1/project/vreader-annotation-import.jsx`
// `ImportPreviewSheet`, `:425-558`): the file header + source badge, the error blob, the count
// chips, the "Preview · first three" sample list and the merge-policy line. Composed by
// `AnnotationImportPreviewSheet.kt`, which owns the sheet's state and action pair. Every function
// here is a pure function of ([ReaderTheme], data) — no state, no I/O.
//
// RULE-51 FIDELITY LEDGER for this surface (absences are recorded, never invented around):
//  - RENDERED AS DEPICTED: the file header + source badge (`:449-475`), the Highlights / Notes /
//    Skipped count chips (`:488-492`), the "Preview · first three" sample list (`:495-530`), the
//    merge-policy line (`:531-533`) and the error blob (`:477-484`). The error branch REPLACES the
//    chips + sample + merge line exactly as the artboard's ternary does, and the header survives it.
//  - ABSENT (plan §3.3 A-3): the sample row's `<chapter> · p. <page>` meta text. The wire row
//    carries only `locatorJSON`; chapter titles are not derivable at import time and `page` exists
//    only for PDF. The depicted color dot is kept; only the un-derivable TEXT is dropped.
//  - ABSENT (recorded by this WI): a **Bookmarks** count chip. The artboard draws exactly three
//    chips and bookmarks are not one of them, so a fourth would be invented UI. Bookmarks are still
//    counted in `ImportPreview.importable`, i.e. in the primary button's number — the total the
//    user approves stays true; only the breakdown is partial. Pinned by
//    `AnnotationImportPreviewSheetTest.noBookmarksCountChip` so a stray addition goes RED.
//  - ABSENT (recorded by this WI): a distinct explanatory blob for the zero-importable case. Plan
//    C-8 describes "the disabled primary plus the designed error blob explaining why", but no
//    committed artboard and no shipped string supplies that copy, and the artboard's error branch
//    would HIDE the `Skipped` chip that is the explanation. So a zero-importable OK preview renders
//    the depicted chips plus the depicted disabled `Import 0 items`; only a file-level
//    [ImportFailure] renders the blob. This is an absence of TEXT whose source does not exist (the
//    §3.3 A-1/A-2/A-3 class), not an omitted state — the state itself IS drawn.
//
// @coordinates-with AnnotationImportPreviewSheet (the only caller), AnnotationImportModels
// (ImportPreview / ImportPreviewRow / ImportFailure), AnnotationColor (the sample dot palette).
package com.vreader.app.annotations

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.reader.settings.ReaderTheme
import com.vreader.app.ui.theme.VReaderFonts

/** The design's error tint triplet (`:480-482`) — literal artboard values, not theme tokens. */
private val ERROR_FILL = Color(0x14C44A1A)
private val ERROR_STROKE = Color(0x55C44A1A)
private val ERROR_INK = Color(0xFFA43A14)

/** The artboard's `sources.vreader.label`, rendered uppercase as the badge's CSS does (`:469-474`).
 *  Exactly one format is importable, so the badge is a constant rather than a per-source lookup. */
private const val SOURCE_BADGE = "VREADER JSON"

/** Secondary text (the design's `t.sub`). */
internal fun ReaderTheme.sub(): Color = ink.copy(alpha = 0.62f)

/** Hairline rule (the design's `t.rule`). */
internal fun ReaderTheme.rule(): Color = ink.copy(alpha = 0.10f)

/** Card fill (the design's white-on-light / raised-panel-on-dark). */
internal fun ReaderTheme.card(): Color = if (isDark) ink.copy(alpha = 0.05f) else Color.White

/** The muted chip's fill (`:565-566`). */
internal fun ReaderTheme.mutedFill(): Color = ink.copy(alpha = if (isDark) 0.03f else 0.025f)

/** The neutral action-button fill (`:544`), reused as the disabled primary's fill (`:550`). */
internal fun ReaderTheme.neutralButton(): Color = ink.copy(alpha = if (isDark) 0.07f else 0.06f)

/** The designed file header (`:449-475`): tinted document glyph, title, file name, source badge. */
@Composable
internal fun ImportFileHeader(theme: ReaderTheme, fileName: String) {
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
            Icon(
                Icons.Outlined.Description,
                contentDescription = null,
                tint = theme.accent,
                modifier = Modifier.size(20.dp),
            )
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
                fileName,
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
        if (preview.sample.isNotEmpty()) {
            Text(
                "PREVIEW · FIRST THREE",
                modifier = Modifier.padding(bottom = 8.dp),
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

/**
 * One designed sample row (`:504-529`): the color dot, then the quoted text clamped to two lines.
 * The depicted `<chapter> · p. <page>` meta text is ABSENT — see this file's ledger (A-3).
 */
@Composable
private fun SampleRow(theme: ReaderTheme, row: ImportPreviewRow) {
    // The artboard falls back to its default swatch when a row carries no color
    // (`row.color || '#f0d25a'`); AnnotationColor.DEFAULT is this palette's equivalent, and the
    // reader has already folded any unknown provider string down to a known key.
    val color = AnnotationColor.from(row.colorKey) ?: AnnotationColor.DEFAULT
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 14.dp, vertical = 10.dp)
            .testTag("annot-import-sample-row"),
    ) {
        Box(
            Modifier
                .padding(bottom = 4.dp)
                .clip(RoundedCornerShape(2.dp))
                .background(Color(android.graphics.Color.parseColor(color.dotHex)))
                .size(8.dp),
        )
        Text(
            "\"" + row.text + "\"",
            color = theme.ink,
            fontFamily = VReaderFonts.Serif,
            fontStyle = FontStyle.Italic,
            fontSize = 13.sp,
            lineHeight = 18.sp,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/** One designed count chip (`:560-581`). [tag] yields `annot-import-chip-<tag>` (+ `-value`). */
@Composable
private fun RowScope.CountChip(
    theme: ReaderTheme,
    label: String,
    value: Int,
    tag: String,
    accented: Boolean = false,
    muted: Boolean = false,
) {
    val fill = when {
        accented -> theme.accent.copy(alpha = 0.08f)
        muted -> theme.mutedFill()
        else -> theme.card()
    }
    Column(
        Modifier
            .weight(1f)
            .clip(RoundedCornerShape(10.dp))
            .background(fill)
            .border(
                if (accented) 1.dp else 0.5.dp,
                if (accented) theme.accent.copy(alpha = 0.19f) else theme.rule(),
                RoundedCornerShape(10.dp),
            )
            .padding(horizontal = 12.dp, vertical = 10.dp)
            .testTag("annot-import-chip-$tag"),
    ) {
        Text(
            value.toString(),
            modifier = Modifier.testTag("annot-import-chip-$tag-value"),
            color = when {
                muted -> theme.sub()
                accented -> theme.accent
                else -> theme.ink
            },
            fontFamily = VReaderFonts.Serif,
            fontSize = 22.sp,
            fontWeight = FontWeight.Bold,
        )
        Text(
            label,
            modifier = Modifier.padding(top = 4.dp),
            color = theme.sub(),
            fontFamily = VReaderFonts.Sans,
            fontSize = 10.5.sp,
            fontWeight = FontWeight.SemiBold,
        )
    }
}
