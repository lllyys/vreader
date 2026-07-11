// Purpose: feature #133 WI-9 (#110 Phase 3) — the row/section composables for the in-book-search sheet
// (vreader-search.jsx `SearchSheet`, 'This book' scope). One [InBookGroupHeader] per [InBookGroup] (serif
// chapter title + a per-group "N match(es)" count — the design's group header), and one [InBookHitRow] per
// [InBookHit] (the snippet with the matched sub-spans rendered BOLD from the hit's inclusive [matchRanges]
// — the design's `SnippetText` **bold** rendering, projected from our model's ranges instead of `**` markers,
// + a trailing chevron). [InBookRecentRow] is a recents entry (the design's `SearchEmptyState` Recent list),
// and [InBookIndexingHint] / [InBookNoResults] are the Indexing hint + the design's `NoResults` empty state.
// Colors come from the active [ReaderTheme] token map (the same local `sub` derivations the Contents sheet
// uses); pure functions of state + callbacks (rule 50 §4).
package com.vreader.app.search

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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.reader.settings.ReaderTheme
import com.vreader.app.ui.theme.VReaderFonts

/**
 * The design's overall results summary line above the groups: "N matches in M chapters" (the design's
 * `{results.length} matches in {…} chapters`). Rendered in the muted sub color. testTag
 * `inbook-results-summary`.
 */
@Composable
fun InBookResultsSummary(theme: ReaderTheme, matchCount: Int, chapterCount: Int) {
    val sub = theme.ink.copy(alpha = 0.55f)
    val matches = if (matchCount == 1) "1 match" else "$matchCount matches"
    val chapters = if (chapterCount == 1) "1 chapter" else "$chapterCount chapters"
    Text(
        "$matches in $chapters",
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 4.dp, vertical = 6.dp)
            .testTag("inbook-results-summary"),
        color = sub,
        fontFamily = VReaderFonts.Sans,
        fontSize = 12.sp,
    )
}

/**
 * A group header for [group] at [groupIndex]: the serif chapter title (the design's group name; a null
 * title falls back to a neutral "Untitled section" label) plus the per-group "N match(es)" count on the
 * trailing edge (the design's `{rs.length} match{es}`). testTag `inbook-group-$groupIndex`.
 */
@Composable
fun InBookGroupHeader(theme: ReaderTheme, group: InBookGroup, groupIndex: Int) {
    val ink = theme.ink
    val sub = ink.copy(alpha = 0.55f)
    val title = group.title?.takeIf { it.isNotBlank() } ?: "Untitled section"
    val n = group.hits.size
    val countLabel = if (n == 1) "1 match" else "$n matches"

    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 4.dp, vertical = 8.dp)
            .testTag("inbook-group-$groupIndex")
            .semantics { contentDescription = "$title, $countLabel" },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            title,
            modifier = Modifier.weight(1f),
            color = ink,
            fontFamily = VReaderFonts.Serif,
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            countLabel,
            color = sub,
            fontFamily = VReaderFonts.Sans,
            fontSize = 11.sp,
        )
    }
}

/**
 * One hit row for [hit] at ([groupIndex], [hitIndex]). Renders the snippet with the matched sub-spans BOLD
 * (the design's `SnippetText` **bold** term, projected from [InBookHit.matchRanges] — inclusive
 * `IntRange`s — instead of `**` markers) in the theme accent, plus a trailing chevron. When [showTopSeparator]
 * the design's 0.5px hairline is drawn above the row (rows after the first within a group's tinted
 * container — the design's `borderTop: i===0 ? 'none' : 0.5px`). Tapping calls [onClick]. testTag
 * `inbook-result-$groupIndex-$hitIndex`; the row is a ≥48dp tap target.
 */
@Composable
fun InBookHitRow(
    theme: ReaderTheme,
    hit: InBookHit,
    groupIndex: Int,
    hitIndex: Int,
    showTopSeparator: Boolean,
    onClick: () -> Unit,
) {
    val ink = theme.ink
    val sub = ink.copy(alpha = 0.55f)
    val annotated = boldedSnippet(hit.snippet, hit.matchRanges, theme.accent)

    Column(Modifier.fillMaxWidth()) {
        if (showTopSeparator) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(0.5.dp)
                    .background(ink.copy(alpha = 0.08f)),
            )
        }
        Row(
            Modifier
                .fillMaxWidth()
                .clickable { onClick() }
                .heightIn(min = 48.dp)
                .padding(horizontal = 12.dp, vertical = 12.dp)
                .testTag("inbook-result-$groupIndex-$hitIndex")
                .semantics { contentDescription = "Search result: ${hit.snippet}" },
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(
                annotated,
                modifier = Modifier.weight(1f),
                color = ink,
                fontFamily = VReaderFonts.Serif,
                fontSize = 13.5.sp,
                maxLines = 3,
                overflow = TextOverflow.Ellipsis,
            )
            Icon(
                Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = sub,
                modifier = Modifier.size(16.dp),
            )
        }
    }
}

/**
 * The snippet as an [AnnotatedString] with each range in [matchRanges] (inclusive UTF-16 `IntRange`s, per
 * `SnippetBuilder`) rendered bold + [accent]-colored. Defensive against corrupt input: ranges are clamped
 * to the snippet bounds (no `substring` OOB / no `r.last + 1` overflow), out-of-order/overlapping ranges are
 * tolerated (the matcher emits non-overlapping start-ordered ranges), and every span boundary is SNAPPED
 * off a UTF-16 surrogate-pair interior so a highlight can never split a supplementary code point (CJK-B /
 * emoji) into malformed halves.
 */
internal fun boldedSnippet(snippet: String, matchRanges: List<IntRange>, accent: Color): AnnotatedString {
    if (matchRanges.isEmpty()) return AnnotatedString(snippet)
    val len = snippet.length
    // Clamp each range to a valid half-open [start, endExclusive) inside the snippet, snap both boundaries
    // off any surrogate interior, then sort by start so the append-in-order walk never goes backwards.
    val clamped = matchRanges
        .mapNotNull { r ->
            val start = snippet.snapBoundary(r.first.coerceIn(0, len))
            // r.last is inclusive; the exclusive end is r.last + 1, guarded against Int overflow.
            val rawEnd = if (r.last >= len) len else (r.last + 1).coerceIn(0, len)
            val endExclusive = snippet.snapBoundary(rawEnd)
            if (endExclusive > start) start until endExclusive else null
        }
        .sortedBy { it.first }
    if (clamped.isEmpty()) return AnnotatedString(snippet)
    return buildAnnotatedString {
        var cursor = 0
        for (range in clamped) {
            val start = range.first.coerceAtLeast(cursor)
            val end = range.last + 1
            if (end <= cursor) continue // fully covered by a prior (overlapping) span
            if (start > cursor) append(snippet.substring(cursor, start))
            withStyle(SpanStyle(color = accent, fontWeight = FontWeight.SemiBold)) {
                append(snippet.substring(start, end))
            }
            cursor = end
        }
        if (cursor < len) append(snippet.substring(cursor))
    }
}

/** Snaps [index] (already in `0..length`) off a UTF-16 surrogate-pair interior: if it lands between a high
 *  and its low surrogate, move it back to the pair's start so a slice never splits a supplementary code
 *  point. Boundaries at 0 / length or on a BMP char are returned unchanged. */
private fun String.snapBoundary(index: Int): Int {
    if (index <= 0 || index >= length) return index
    return if (this[index - 1].isHighSurrogate() && this[index].isLowSurrogate()) index - 1 else index
}

/**
 * One recents row for [text] at [index] (the design's `SearchEmptyState` Recent list): a search glyph + the
 * recent query + a "Tap to repeat" affordance hint, with the design's 0.5px hairline below every row but the
 * last ([showBottomSeparator], the design's `borderBottom: i < recent.length-1 ? 0.5px : 'none'`). Tapping
 * calls [onPick] with [text] (fills the query). testTag `inbook-recent-$index`; a ≥48dp tap target.
 */
@Composable
fun InBookRecentRow(
    theme: ReaderTheme,
    text: String,
    index: Int,
    showBottomSeparator: Boolean,
    onPick: (String) -> Unit,
) {
    val ink = theme.ink
    val sub = ink.copy(alpha = 0.55f)
    Column(Modifier.fillMaxWidth()) {
        Row(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(8.dp))
                .clickable { onPick(text) }
                .heightIn(min = 48.dp)
                .padding(horizontal = 4.dp, vertical = 10.dp)
                .testTag("inbook-recent-$index")
                .semantics { contentDescription = "Recent search: $text, tap to repeat" },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Icon(Icons.Filled.Search, contentDescription = null, tint = sub, modifier = Modifier.size(15.dp))
            Text(
                text,
                modifier = Modifier.weight(1f),
                color = ink,
                fontFamily = VReaderFonts.Sans,
                fontSize = 14.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                "Tap to repeat",
                color = sub,
                fontFamily = VReaderFonts.Sans,
                fontSize = 11.sp,
            )
        }
        if (showBottomSeparator) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(0.5.dp)
                    .background(ink.copy(alpha = 0.08f)),
            )
        }
    }
}

// The Indexing hint + NoResults empty state live in InBookSearchStates.kt (this file owns the list rows).
