// Purpose: Library search takeover screen — feature #128 WI-7. A Compose recreation of the committed
// design dev-docs/designs/vreader-fidelity-v1/project/vreader-library-android.jsx, "C. Search" (the
// shared visual identity; ADR-0001). Renders the three designed states as a PURE function of
// [SearchUiState] + event callbacks (unidirectional data flow, rule 50 §4):
//   • EMPTY    — a "Recent" list (only when non-empty) + "Browse collections" chips (only when non-empty).
//   • RESULTS  — per SearchResultRow: fallback cover + serif title with the query WASH-highlighted +
//                author subtitle + (when present) an italic in-text snippet with wash + chapter attribution.
//   • NO-RESULTS — a circled search icon + serif heading + the DEFINITIVE copy, rendered ONLY when
//                `indexComplete && searched && results.isEmpty()` (plan §honest-empty-state: the copy
//                claims "searched the text", so it must wait for the whole indexable corpus to settle).
// Sections render only when their backing list is non-empty (no invented "no recents" / "no chips"
// chrome — rule 51).
//
// @coordinates-with: MainActivity.kt (hosts this behind a saveable search route), search/SearchViewModel.kt
//   (SearchUiState / SearchResultRow / TextHit shapes), library/LibraryScreen.kt (the FallbackCover
//   fallback-cover visual identity is mirrored here for result rows).
package com.vreader.app.search

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.NorthEast
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.ui.theme.VReaderColors
import com.vreader.app.ui.theme.VReaderFonts

/** The wash-highlight fill — the design's `rgba(140,47,47,0.16)` = [VReaderColors.Accent] at 16% alpha. */
private val Wash = VReaderColors.Accent.copy(alpha = 0.16f)

private val CoverTints = listOf(
    Color(0xFF5A4632), Color(0xFF4A5240), Color(0xFF5B3A3A), Color(0xFF3A4A5A), Color(0xFF504030),
)

/**
 * The search takeover. Pure function of [state]; every mutation flows out through a callback.
 *
 * @param onQueryChange the query text changed (drives the debounced search in the ViewModel).
 * @param onCancel dismiss the search takeover (back to the library).
 * @param onRecentTap a recent-search row was tapped — re-run that query.
 * @param onPickCollection a browse-collections chip was tapped (its id).
 * @param onOpenResult a result row was tapped — open the book (the host also records the query as recent).
 */
@Composable
fun SearchScreen(
    state: SearchUiState,
    onQueryChange: (String) -> Unit,
    onCancel: () -> Unit,
    onRecentTap: (String) -> Unit,
    onPickCollection: (String) -> Unit,
    onOpenResult: (SearchResultRow) -> Unit,
) {
    Column(
        Modifier.fillMaxSize().background(VReaderColors.Background).systemBarsPadding(),
    ) {
        SearchField(query = state.query, onQueryChange = onQueryChange, onCancel = onCancel)

        val body = Modifier.padding(horizontal = 18.dp).fillMaxSize()
        when {
            // A non-blank query that has settled with zero rows → results/no-results branch.
            state.searched -> {
                if (state.results.isEmpty()) {
                    // The definitive text-inclusive copy is truthful only once the corpus is settled.
                    if (state.indexComplete) NoResults(query = state.query, modifier = body)
                    // else: indexing still in flight — show nothing (metadata results would be here if any);
                    // suppress the definitive copy rather than invent a "still indexing" state (rule 51).
                } else {
                    Results(state = state, onOpenResult = onOpenResult, modifier = body)
                }
            }
            // Empty query (or not yet searched) → the designed empty state (recents + collection chips).
            else -> EmptyState(
                recents = state.recents,
                collections = state.collections,
                onRecentTap = onRecentTap,
                onPickCollection = onPickCollection,
                modifier = body,
            )
        }
    }
}

// ── search field ───────────────────────────────────────────────────

@Composable
private fun SearchField(query: String, onQueryChange: (String) -> Unit, onCancel: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val hasQuery = query.isNotEmpty()
        // The rounded field. The design draws an accent inset ring while a query is present; we render an
        // accent border while there's text to mirror that focused affordance (the caret is the TextField's).
        val fieldShape = RoundedCornerShape(12.dp)
        Row(
            Modifier.weight(1f).height(42.dp).clip(fieldShape)
                .background(VReaderColors.PillFill)
                .then(
                    if (hasQuery) {
                        Modifier.border(1.5.dp, VReaderColors.Accent, fieldShape)
                    } else {
                        Modifier
                    },
                )
                .padding(horizontal = 13.dp),
            horizontalArrangement = Arrangement.spacedBy(9.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Filled.Search, contentDescription = "Search", tint = VReaderColors.InkMuted, modifier = Modifier.size(19.dp))
            BasicTextField(
                value = query,
                onValueChange = onQueryChange,
                modifier = Modifier.weight(1f),
                singleLine = true,
                textStyle = TextStyle(
                    color = VReaderColors.Ink,
                    fontFamily = VReaderFonts.Sans,
                    fontSize = 15.5.sp,
                ),
                cursorBrush = SolidColor(VReaderColors.Accent),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                decorationBox = { inner ->
                    if (!hasQuery) {
                        Text(
                            "Search title, author, or text…",
                            color = VReaderColors.InkMuted,
                            fontFamily = VReaderFonts.Sans,
                            fontSize = 15.5.sp,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                    inner()
                },
            )
            if (hasQuery) {
                Icon(
                    Icons.Filled.Close,
                    contentDescription = "Clear search",
                    tint = VReaderColors.InkMuted,
                    modifier = Modifier.size(18.dp).clickable { onQueryChange("") },
                )
            }
        }
        Text(
            "Cancel",
            Modifier.clickable(onClick = onCancel),
            color = VReaderColors.Accent,
            fontFamily = VReaderFonts.Sans,
            fontSize = 15.sp,
            fontWeight = FontWeight.Medium,
        )
    }
}

// ── empty state ────────────────────────────────────────────────────

@Composable
private fun EmptyState(
    recents: List<String>,
    collections: List<com.vreader.app.data.Collection>,
    onRecentTap: (String) -> Unit,
    onPickCollection: (String) -> Unit,
    modifier: Modifier,
) {
    LazyColumn(modifier, contentPadding = PaddingValues(bottom = 40.dp)) {
        if (recents.isNotEmpty()) {
            item { SectionLabel("Recent", topPadding = 6.dp) }
            items(recents, key = { "recent-$it" }) { r -> RecentRow(query = r, onTap = { onRecentTap(r) }) }
        }
        if (collections.isNotEmpty()) {
            item { SectionLabel("Browse collections", topPadding = if (recents.isNotEmpty()) 20.dp else 6.dp) }
            item { CollectionChips(collections = collections, onPick = onPickCollection) }
        }
    }
}

@Composable
private fun SectionLabel(text: String, topPadding: androidx.compose.ui.unit.Dp) {
    // The design applies `textTransform: uppercase` to the section labels (RECENT / BROWSE COLLECTIONS).
    Text(
        text.uppercase(),
        Modifier.padding(start = 2.dp, end = 2.dp, top = topPadding, bottom = 10.dp),
        color = VReaderColors.InkMuted,
        fontFamily = VReaderFonts.Sans,
        fontSize = 12.sp,
        fontWeight = FontWeight.SemiBold,
        letterSpacing = 0.5.sp,
    )
}

@Composable
private fun RecentRow(query: String, onTap: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onTap).padding(horizontal = 2.dp, vertical = 11.dp),
        horizontalArrangement = Arrangement.spacedBy(11.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Filled.Schedule, contentDescription = null, tint = VReaderColors.InkMuted, modifier = Modifier.size(18.dp))
        Text(
            query,
            Modifier.weight(1f),
            color = VReaderColors.Ink,
            fontFamily = VReaderFonts.Sans,
            fontSize = 15.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        // The design's up-right arrow — tap fills the field with the recent query.
        Icon(Icons.Filled.NorthEast, contentDescription = null, tint = VReaderColors.InkMuted, modifier = Modifier.size(15.dp))
    }
}

@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
private fun CollectionChips(collections: List<com.vreader.app.data.Collection>, onPick: (String) -> Unit) {
    androidx.compose.foundation.layout.FlowRow(
        Modifier.fillMaxWidth().padding(top = 2.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        collections.forEach { c ->
            Text(
                c.name,
                Modifier.clip(RoundedCornerShape(100.dp)).background(VReaderColors.PillFill)
                    .clickable { onPick(c.id) }.padding(horizontal = 14.dp, vertical = 8.dp),
                color = VReaderColors.Ink,
                fontFamily = VReaderFonts.Sans,
                fontSize = 13.5.sp,
                fontWeight = FontWeight.Medium,
            )
        }
    }
}

// ── results state ──────────────────────────────────────────────────

@Composable
private fun Results(state: SearchUiState, onOpenResult: (SearchResultRow) -> Unit, modifier: Modifier) {
    LazyColumn(modifier, contentPadding = PaddingValues(bottom = 40.dp)) {
        item {
            Text(
                summaryText(state.bookCount, state.inTextMatchCount),
                Modifier.padding(start = 2.dp, end = 2.dp, top = 4.dp, bottom = 12.dp),
                color = VReaderColors.InkMuted,
                fontFamily = VReaderFonts.Sans,
                fontSize = 12.5.sp,
            )
        }
        items(state.results, key = { it.book.fingerprintKey }) { row ->
            ResultRow(row = row, query = state.query, onOpen = { onOpenResult(row) })
        }
    }
}

@Composable
private fun ResultRow(row: SearchResultRow, query: String, onOpen: () -> Unit) {
    // The design draws a 0.5px rule under each result row with a 12px gap below it.
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onOpen)
            .drawBottomRule(VReaderColors.Ink.copy(alpha = 0.10f))
            .padding(top = 8.dp, bottom = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(13.dp),
    ) {
        SmallCover(book = row.book)
        Column(Modifier.weight(1f)) {
            // Serif title with the query match wash-highlighted (case-insensitive first occurrence).
            Text(
                highlightMatch(row.book.title, query),
                color = VReaderColors.Ink,
                fontFamily = VReaderFonts.Serif,
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            val author = row.book.author?.takeIf { it.isNotBlank() }
            if (author != null) {
                Spacer(Modifier.height(3.dp))
                Text(
                    author,
                    color = VReaderColors.InkMuted,
                    fontFamily = VReaderFonts.Sans,
                    fontSize = 12.5.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            val hit = row.textHit
            if (hit != null) {
                Spacer(Modifier.height(8.dp))
                Text(
                    snippetWithAttribution(hit),
                    color = VReaderColors.InkMuted,
                    fontFamily = VReaderFonts.Serif,
                    fontSize = 13.sp,
                    fontStyle = FontStyle.Italic,
                    maxLines = 3,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
private fun SmallCover(book: com.vreader.app.data.Book) {
    // The design's result Cover is 62 wide at the library's 104:156 (2:3) proportion → ~93 tall.
    val tint = CoverTints[(book.fingerprintKey.hashCode() and 0x7FFFFFFF) % CoverTints.size]
    Box(
        Modifier.size(width = 62.dp, height = 93.dp).clip(RoundedCornerShape(4.dp)).background(tint),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            book.title.trim().take(1).uppercase(),
            color = Color(0xCCFFFFFF),
            fontFamily = VReaderFonts.Serif,
            fontWeight = FontWeight.SemiBold,
            fontSize = 22.sp,
        )
    }
}

/** A 0.5px hairline rule along the bottom edge (the design's `borderBottom: 0.5px solid`). */
private fun Modifier.drawBottomRule(color: Color): Modifier = drawBehind {
    val stroke = 0.5.dp.toPx()
    drawLine(
        color = color,
        start = androidx.compose.ui.geometry.Offset(0f, size.height - stroke / 2),
        end = androidx.compose.ui.geometry.Offset(size.width, size.height - stroke / 2),
        strokeWidth = stroke,
    )
}

// ── no-results state ───────────────────────────────────────────────

@Composable
private fun NoResults(query: String, modifier: Modifier) {
    Box(modifier, contentAlignment = Alignment.TopCenter) {
        Column(
            Modifier.fillMaxWidth().padding(top = 70.dp, start = 30.dp, end = 30.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Box(
                Modifier.size(60.dp).clip(RoundedCornerShape(30.dp)).background(VReaderColors.Ink.copy(alpha = 0.04f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.Search, contentDescription = null, tint = VReaderColors.InkMuted, modifier = Modifier.size(28.dp))
            }
            Spacer(Modifier.height(18.dp))
            Text(
                "No matches for \"$query\"",
                color = VReaderColors.Ink,
                fontFamily = VReaderFonts.Serif,
                fontSize = 19.sp,
            )
            Spacer(Modifier.height(8.dp))
            Text(
                "Search looks across titles, authors, and the text of downloaded books. Try a different term.",
                color = VReaderColors.InkMuted,
                fontFamily = VReaderFonts.Sans,
                fontSize = 14.sp,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
        }
    }
}

// ── helpers ────────────────────────────────────────────────────────

/** "N books · M in-text match" — pluralized honestly. M omitted when zero (design shows it when > 0). */
internal fun summaryText(bookCount: Int, inTextMatchCount: Int): String {
    val books = "$bookCount ${if (bookCount == 1) "book" else "books"}"
    if (inTextMatchCount <= 0) return books
    val matches = "$inTextMatchCount in-text ${if (inTextMatchCount == 1) "match" else "matches"}"
    return "$books · $matches"
}

/** The title with the FIRST case-insensitive occurrence of [query] wash-highlighted (design `hl`). */
private fun highlightMatch(title: String, query: String) = buildAnnotatedString {
    val q = query.trim()
    val idx = if (q.isEmpty()) -1 else title.lowercase().indexOf(q.lowercase())
    if (idx < 0) {
        append(title)
    } else {
        append(title.substring(0, idx))
        withStyle(SpanStyle(background = Wash)) { append(title.substring(idx, idx + q.length)) }
        append(title.substring(idx + q.length))
    }
}

/**
 * The in-text snippet — the WI-3 SnippetBuilder ranges wash-highlighted (drawn upright inside the italic
 * run, the design's `hlPlain`) — plus the chapter attribution suffix (" — <sectionTitle>") when present.
 */
private fun snippetWithAttribution(hit: TextHit) = buildAnnotatedString {
    append("“")
    val text = hit.snippet
    var cursor = 0
    // Apply each match range as an upright wash span; guard ranges to the snippet bounds.
    hit.matchRanges.sortedBy { it.first }.forEach { r ->
        val start = r.first.coerceIn(0, text.length)
        val end = (r.last + 1).coerceIn(start, text.length)
        if (start > cursor) append(text.substring(cursor, start))
        if (end > start) {
            withStyle(SpanStyle(background = Wash, fontStyle = FontStyle.Normal)) { append(text.substring(start, end)) }
        }
        cursor = end
    }
    if (cursor < text.length) append(text.substring(cursor))
    append("”")
    hit.sectionTitle?.takeIf { it.isNotBlank() }?.let { append(" — $it") }
}
