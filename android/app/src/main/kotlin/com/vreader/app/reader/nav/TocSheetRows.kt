// Purpose: feature #132 WI-3 (#110 Phase 3) — the row composables for the reader Contents sheet
// (vreader-panels.jsx `TOCSheet` Contents tab). One [TocContentsRow] per [TocEntry]: a right-aligned
// chapter number (the 1-based row position — our model carries no explicit `ch`), the section title
// (serif; accent + heavier weight when it is the current chapter, per the design's highlighted row),
// and a trailing "p. N" page label rendered ONLY when the entry has one. [TocEmptyState] is the
// no-contents fallback. Colors come from the active [ReaderTheme] token map (the same local `sub`/
// tint derivations `ReaderTopChrome` uses); pure functions of state + an `onJump` callback.
package com.vreader.app.reader.nav

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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.reader.settings.ReaderTheme
import com.vreader.app.ui.theme.VReaderFonts

/**
 * One Contents row for [entry] at [index]. Shows `chapter# · title · p.N`; when [isCurrent] the row
 * gets the design's accent-tinted background and the title is accent-colored + weight-600 (the
 * highlighted-chapter state). Tapping calls [onClick] with [index]. testTags: `toc-row-$index` (+
 * the extra `toc-row-current` on the current row so the highlight is assertable without pixels).
 */
@Composable
fun TocContentsRow(
    theme: ReaderTheme,
    entry: TocEntry,
    index: Int,
    isCurrent: Boolean,
    onClick: (Int) -> Unit,
) {
    val ink = theme.ink
    val accent = theme.accent
    val sub = ink.copy(alpha = 0.55f)
    // The design's per-scheme highlighted-row tint: the theme accent (light oxblood 8C2F2F,
    // dark amber D6885A — matching vreader-panels.jsx's rgba(140,47,47,0.08)/rgba(214,136,90,0.12))
    // at the design's exact alphas: 0.08 in light schemes, 0.12 in dark.
    val highlight = accent.copy(alpha = if (theme.isDark) 0.12f else 0.08f)

    val title = entry.title?.takeIf { it.isNotBlank() } ?: "Untitled"
    // A11y: announce the chapter number, the title, the page label, and the current-chapter state —
    // not just the title (so the row is not collapsed to a single word for screen readers).
    val a11yLabel = buildString {
        append("Chapter ${index + 1}, ")
        append(title)
        entry.pageLabel?.let { append(", page $it") }
        if (isCurrent) append(", current chapter")
    }

    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .clickable { onClick(index) }
            .background(if (isCurrent) highlight else Color.Transparent)
            .heightIn(min = 48.dp)
            .padding(horizontal = 14.dp, vertical = 10.dp)
            .testTag("toc-row-$index")
            .semantics { contentDescription = a11yLabel },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        // A zero-footprint marker so the highlighted row is assertable by an exact tag (the design's
        // accent bg + accent/600 title is the visible form of the same "current chapter" state).
        // Named off the `toc-row-` prefix so a row-count query (substring "toc-row-") isn't inflated.
        if (isCurrent) {
            Box(Modifier.size(0.dp).testTag("toc-current-marker"))
        }
        // Chapter number — right-aligned, serif, sub color (the design's `c.ch` column).
        Text(
            "${index + 1}",
            modifier = Modifier.width(24.dp),
            color = sub,
            fontFamily = VReaderFonts.Serif,
            fontSize = 12.sp,
            fontWeight = FontWeight.Medium,
            textAlign = TextAlign.End,
        )
        // Title — the highlighted chapter is accent + weight-600; nested entries indent by depth.
        Text(
            title,
            modifier = Modifier
                .weight(1f)
                .padding(start = (entry.depth.coerceIn(0, 4) * 12).dp),
            color = if (isCurrent) accent else ink,
            fontFamily = VReaderFonts.Serif,
            fontSize = 16.sp,
            fontWeight = if (isCurrent) FontWeight.SemiBold else FontWeight.Normal,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        // Page label — "p. N", only when present (no stray "p. " for label-less entries).
        entry.pageLabel?.let { label ->
            Text(
                "p. $label",
                modifier = Modifier.testTag("toc-page-$index"),
                color = sub,
                fontFamily = VReaderFonts.Sans,
                fontSize = 12.sp,
            )
        }
    }
}

/** The Contents empty state — shown when a book has no table of contents (e.g. a plain TXT). */
@Composable
fun TocEmptyState(theme: ReaderTheme) {
    Box(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 120.dp)
            .padding(24.dp)
            .testTag("toc-empty"),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            "No contents",
            color = theme.ink.copy(alpha = 0.55f),
            fontFamily = VReaderFonts.Sans,
            fontSize = 15.sp,
        )
    }
}
