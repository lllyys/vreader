// Purpose: feature #165 WI-5 — the leaf pieces of the designed annotations-import preview sheet
// (`dev-docs/designs/vreader-fidelity-v1/project/vreader-annotation-import.jsx`): the theme token
// derivations, the artboard's JSON-file glyph, one sample row and one count chip. Composed by
// `AnnotationImportPreviewSections.kt`, which carries this surface's rule-51 fidelity ledger.
// Every function here is a pure function of ([ReaderTheme], data) — no state, no I/O.
//
// @coordinates-with AnnotationImportPreviewSections (the only caller), AnnotationImportModels
// (ImportPreviewRow), AnnotationColor (the sample dot palette).
package com.vreader.app.annotations

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.reader.settings.ReaderTheme
import com.vreader.app.ui.theme.VReaderFonts

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

/**
 * The artboard's own `IconFileJson` path data (`vreader-annotation-import.jsx:44-50`) — the page
 * outline, the folded corner, and the two braces. Copied verbatim from the design rather than
 * substituted with a Material document glyph: the braces are what say "this is a JSON file", and
 * swapping in a different glyph would be a self-directed design choice on a depicted element.
 */
private val JSON_GLYPH_PATHS = listOf(
    "M7 3h8l4 4v14H7z",
    "M15 3v4h4",
    "M10 13c-1 0-1 2-2 2M14 13c1 0 1 2 2 2",
)

/** The artboard's 24-unit viewBox; the paths above are expressed in it. */
private const val JSON_GLYPH_VIEWPORT = 24f

/** The artboard's `stroke={1.7}`, in viewport units — the draw-scope transform scales it. */
private const val JSON_GLYPH_STROKE = 1.7f

/** The designed JSON-file glyph (`:44-50`, used by the sheet header at `:455`), stroked in [tint]. */
@Composable
internal fun ImportJsonFileIcon(tint: Color, size: Dp) {
    val paths = remember { JSON_GLYPH_PATHS.map { PathParser().parsePathString(it).toPath() } }
    val stroke = remember {
        Stroke(width = JSON_GLYPH_STROKE, cap = StrokeCap.Round, join = StrokeJoin.Round)
    }
    Canvas(
        Modifier
            .size(size)
            .testTag("annot-import-file-icon"),
    ) {
        val factor = this.size.minDimension / JSON_GLYPH_VIEWPORT
        scale(factor, factor, pivot = Offset.Zero) {
            paths.forEach { drawPath(it, color = tint, style = stroke) }
        }
    }
}

/**
 * One designed sample row (`:504-529`): the color dot, then the quoted text clamped to two lines.
 * The depicted `<chapter> · p. <page>` meta text is ABSENT — see the ledger in
 * `AnnotationImportPreviewSections.kt` (A-3).
 */
@Composable
internal fun SampleRow(theme: ReaderTheme, row: ImportPreviewRow) {
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
internal fun RowScope.CountChip(
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
