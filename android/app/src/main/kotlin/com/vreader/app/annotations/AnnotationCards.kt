// Purpose: feature #132 WI-4 — the two annotation review cards (design vreader-android-annotations.jsx
// `HighlightCard` + `StandaloneNoteCard`). A [HighlightCard] shows a color left-rule + the quote + an
// optional attached-note line + a meta footer; a [StandaloneNoteCard] shows a dashed left-rule + the
// note body + a "STANDALONE" tag + meta. Both are pure functions of a record + a nullable jump
// callback: the card body is clickable ONLY when [onJump] is non-null (the §review-sheet-contract
// capability gate — EPUB/AZW3 hosts pass null so their cards are review-only, not silent no-ops).
// The Android design depicts NO per-card Copy/Share button and NO `⋯` menu (those live on the in-reader
// SelectionPopover / the iOS notes-delete surface) — so neither is rendered here (rule 51 gate).
// Colors are derived from the active [ReaderTheme] token map (the same local `sub`/`sep` derivation the
// nav sheet rows use). ~one file; each card <100 lines.
package com.vreader.app.annotations

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
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

private fun colorOf(hex: String): Color = Color(android.graphics.Color.parseColor(hex))

/** Card background derived from the theme (the design's `ui.card`: white on light, a raised panel on dark). */
private fun ReaderTheme.cardBackground(): Color =
    if (isDark) ink.copy(alpha = 0.08f) else Color.White

/** Secondary text color (the design's `ui.sec` — the attached-note / subtitle tone). */
private fun ReaderTheme.secondary(): Color = ink.copy(alpha = 0.62f)

/** Tertiary text color (the design's `ui.ter` — the meta footer tone). */
private fun ReaderTheme.tertiary(): Color = ink.copy(alpha = 0.45f)

/** Hairline separator (the design's `ui.sep`). */
private fun ReaderTheme.separator(): Color = ink.copy(alpha = 0.10f)

/**
 * A highlight review card (design `HighlightCard`): a [record]'s color left-rule, the quote, an optional
 * attached-note line, and a meta footer with a "· Note" marker when a note is attached. The card body is
 * clickable → [onJump] with the item ONLY when [onJump] is non-null (capability gate: a null callback
 * leaves the card non-clickable, no ripple, no dead no-op). testTag `annot-card-${record.id}`. No per-card
 * Copy/Share button and no `⋯` menu (the Android design depicts neither).
 */
@Composable
fun HighlightCard(theme: ReaderTheme, record: HighlightRecord, onJump: ((AnnotationItem) -> Unit)?) {
    val ruleColor = colorOf(record.color.ruleHex)
    val a11y = buildString {
        append("Highlight: ${record.selectedText}")
        record.note?.let { append(", note: $it") }
    }
    AnnotationCardShell(
        theme = theme,
        testTag = "annot-card-${record.id}",
        contentDescription = a11y,
        onClick = onJump?.let { cb -> { cb(AnnotationItem.Highlight(record)) } },
        rule = { RuleBar(color = ruleColor) },
    ) {
        Text(
            record.selectedText,
            color = theme.ink,
            fontFamily = VReaderFonts.Serif,
            fontSize = 15.5.sp,
            lineHeight = 23.sp,
        )
        record.note?.takeIf { it.isNotBlank() }?.let { note ->
            Box(
                Modifier
                    .fillMaxWidth()
                    .padding(top = 9.dp)
                    .height(0.5.dp)
                    .background(theme.separator()),
            )
            Text(
                note,
                modifier = Modifier.padding(top = 9.dp),
                color = theme.secondary(),
                fontFamily = VReaderFonts.Sans,
                fontSize = 13.5.sp,
                lineHeight = 20.sp,
            )
        }
        MetaFooter(theme = theme, hasNote = record.note?.isNotBlank() == true)
    }
}

/**
 * A standalone-note review card (design `StandaloneNoteCard`): a dashed-style left-rule (approximated with
 * the theme accent), the note body, a "STANDALONE" tag, and a meta line. Clickable → [onJump] only when
 * [onJump] is non-null (same capability gate as [HighlightCard]). testTag `annot-card-${record.id}`.
 */
@Composable
fun StandaloneNoteCard(theme: ReaderTheme, record: NoteRecord, onJump: ((AnnotationItem) -> Unit)?) {
    AnnotationCardShell(
        theme = theme,
        testTag = "annot-card-${record.id}",
        contentDescription = "Note: ${record.content}",
        onClick = onJump?.let { cb -> { cb(AnnotationItem.Note(record)) } },
        rule = { RuleBar(color = theme.accent.copy(alpha = 0.7f)) },
    ) {
        Text(
            record.content,
            color = theme.ink,
            fontFamily = VReaderFonts.Serif,
            fontSize = 15.5.sp,
            lineHeight = 23.sp,
        )
        Row(
            Modifier.padding(top = 9.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                "STANDALONE",
                modifier = Modifier
                    .clip(RoundedCornerShape(5.dp))
                    .background(theme.accent.copy(alpha = if (theme.isDark) 0.18f else 0.10f))
                    .padding(horizontal = 6.dp, vertical = 2.dp)
                    .testTag("annot-note-tag-${record.id}"),
                color = theme.accent,
                fontFamily = VReaderFonts.Sans,
                fontSize = 9.5.sp,
                fontWeight = FontWeight.Bold,
            )
        }
    }
}

/** The shared card chrome: a rounded panel, an optional clickable body, a left [rule] bar + [content]. */
@Composable
private fun AnnotationCardShell(
    theme: ReaderTheme,
    testTag: String,
    contentDescription: String,
    onClick: (() -> Unit)?,
    rule: @Composable () -> Unit,
    content: @Composable () -> Unit,
) {
    val base = Modifier
        .fillMaxWidth()
        .padding(bottom = 10.dp)
        .clip(RoundedCornerShape(14.dp))
    // Capability gate: only attach a click action when a jump callback exists. A null callback leaves
    // the card non-clickable — no ripple, no dead no-op (§review-sheet-contract).
    val clickable = if (onClick != null) base.clickable { onClick() } else base
    Row(
        clickable
            .background(theme.cardBackground())
            .heightIn(min = 48.dp)
            .padding(14.dp)
            .testTag(testTag)
            .semantics { this.contentDescription = contentDescription },
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        rule()
        Column(Modifier.weight(1f)) { content() }
    }
}

/** The color left-rule (design `c.rule` / the note's dashed rule). */
@Composable
private fun RuleBar(color: Color) {
    Box(
        Modifier
            .width(4.dp)
            .fillMaxHeight()
            .heightIn(min = 20.dp)
            .clip(RoundedCornerShape(2.dp))
            .background(color),
    )
}

/** The highlight meta footer with a "· Note" marker when the highlight carries an attached note. */
@Composable
private fun MetaFooter(theme: ReaderTheme, hasNote: Boolean) {
    if (!hasNote) return
    Text(
        "· Note",
        modifier = Modifier.padding(top = 9.dp),
        color = theme.accent,
        fontFamily = VReaderFonts.Sans,
        fontSize = 12.sp,
        fontWeight = FontWeight.SemiBold,
    )
}
