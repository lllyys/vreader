// Purpose: feature #133 WI-9 (#110 Phase 3) — the in-book-search sheet (vreader-search.jsx `SearchSheet`,
// 'This book' scope) as a `ModalBottomSheet` that renders the WI-8 [InBookSearchScreenState]. Faithful to
// the design's `SearchSheet`: an AUTOFOCUS query field (a rounded pill with a search glyph, an inline clear
// button, and the design's trailing "Cancel") followed by a body that dispatches on the state's
// [InBookSearchContent] region — Idle → the design's Recent list; Indexing → the "still building" hint;
// Results → grouped chapter headers + snippet rows (append-on-scroll — `onLoadMore` fires when the last
// group nears the viewport, NO Load-More disclosure row, §8/§9); NoResults → the design's `NoResults` empty
// state. Loading/Unsupported/Error are host-guarded terminals (Unsupported hides the entry entirely) that
// render nothing user-facing here. Tapping a hit calls `onJump(hit)`: the sheet dismisses ONLY on
// [JumpResult.Succeeded]; a [JumpResult.Failed] jump keeps it open with NO invented error surface (rule 51
// §nav-error-presentation, the `TocContentsSheet` dismiss-on-success precedent). The design's "All books"
// scope toggle is OUT of #133 scope (plan §2 — this is the 'This book' sheet only), so no scope selector is
// rendered (no dead control). Same [ReaderTheme] token map as the reader chrome / Contents sheet. Pure fn of
// state (rule 50 §4).
package com.vreader.app.search

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.reader.nav.JumpResult
import com.vreader.app.reader.settings.ReaderTheme
import com.vreader.app.ui.theme.VReaderFonts
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filter

/**
 * The in-book-search sheet as a [ModalBottomSheet]. [bookTitle] hints the field placeholder; [state] is the
 * WI-8 [InBookSearchScreenState] (query + recents + the [InBookSearchContent] region); [query] is the live
 * field text (hoisted, so the host owns it). Callbacks: [onQueryChange] (field edit), [onPickRecent] (a
 * recents row → fill the query), [onJump] (a hit tapped → the host navigates and returns [JumpResult];
 * the sheet dismisses only on [JumpResult.Succeeded]), [onLoadMore] (append-on-scroll — fetch the next
 * page), [onDismiss] (Cancel / scrim). Renders in [theme]'s colors.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InBookSearchSheet(
    theme: ReaderTheme,
    bookTitle: String,
    state: InBookSearchScreenState,
    query: String,
    onQueryChange: (String) -> Unit,
    onPickRecent: (String) -> Unit,
    onJump: (InBookHit) -> JumpResult,
    onLoadMore: () -> Unit,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = theme.background,
        modifier = modifier.testTag("inbook-search-sheet"),
    ) {
        InBookSearchSheetContent(
            theme = theme,
            bookTitle = bookTitle,
            state = state,
            query = query,
            onQueryChange = onQueryChange,
            onPickRecent = onPickRecent,
            onJump = onJump,
            onLoadMore = onLoadMore,
            onDismiss = onDismiss,
        )
    }
}

/**
 * The sheet's content, extracted from the [ModalBottomSheet] wrapper so it's directly UI-testable (the
 * `TocContentsSheetContent` precedent — a modal sheet's content renders in a separate window instrumented
 * clicks reach unreliably on a loaded host). Renders the autofocus query field + Cancel, then dispatches
 * the body on [state]'s content region. Owns the **dismiss-on-success** decision: tapping a hit calls
 * [onJump]; on [JumpResult.Succeeded] it dismisses via [onDismiss], on [JumpResult.Failed] NOTHING happens
 * (the sheet stays open, no invented error surface — rule 51 §nav-error-presentation).
 */
@Composable
fun InBookSearchSheetContent(
    theme: ReaderTheme,
    bookTitle: String,
    state: InBookSearchScreenState,
    query: String,
    onQueryChange: (String) -> Unit,
    onPickRecent: (String) -> Unit,
    onJump: (InBookHit) -> JumpResult,
    onLoadMore: () -> Unit,
    onDismiss: () -> Unit = {},
) {
    Column(
        Modifier
            .fillMaxWidth()
            .background(theme.background)
            .testTag("inbook-search-sheet-content"),
    ) {
        InBookSearchField(
            theme = theme,
            bookTitle = bookTitle,
            query = query,
            onQueryChange = onQueryChange,
            onDismiss = onDismiss,
        )
        // Header bottom rule (the design's `Sheet` divider under the search bar).
        Box(
            Modifier
                .fillMaxWidth()
                .height(0.5.dp)
                .background(theme.ink.copy(alpha = 0.08f)),
        )

        when (val content = state.content) {
            is InBookSearchContent.Results ->
                ResultsBody(
                    theme = theme,
                    results = content,
                    onJump = onJump,
                    onLoadMore = onLoadMore,
                    onDismiss = onDismiss,
                )
            InBookSearchContent.Indexing -> InBookIndexingHint(theme)
            InBookSearchContent.NoResults -> InBookNoResults(theme, query)
            InBookSearchContent.Idle -> RecentsBody(theme, state.recents, onPickRecent)
            // Loading (transient, between debounced query settle and the results/no-results resolution),
            // Error (a rare backend failure), and Unsupported (the host hides the Search entry entirely for
            // these) render NO distinct body: the design's SearchSheet depicts no Loading/Error surface, and
            // the sibling library `SearchScreen` likewise suppresses rather than invent one (rule 51 — no
            // self-designed state). The field stays live so the user can keep typing; a new query supersedes
            // the transient/failed state.
            InBookSearchContent.Loading -> Unit
            is InBookSearchContent.Error -> Unit
            InBookSearchContent.Unsupported -> Unit
        }
    }
}

/**
 * The grouped results body: a [LazyColumn] of chapter-group headers + hit rows, with append-on-scroll.
 * When [InBookSearchContent.Results.moreAvailable] is true and the LAST group is composed (i.e. the user has
 * scrolled the tail near the viewport), [onLoadMore] fires exactly once per new tail — there is NO Load-More
 * disclosure row (§8/§9). Tapping a hit calls [onJump]; a [JumpResult.Succeeded] dismisses via [onDismiss],
 * a [JumpResult.Failed] keeps the sheet open (no error surface — rule 51).
 */
@Composable
private fun ResultsBody(
    theme: ReaderTheme,
    results: InBookSearchContent.Results,
    onJump: (InBookHit) -> JumpResult,
    onLoadMore: () -> Unit,
    onDismiss: () -> Unit,
) {
    val groups = results.groups
    val listState = rememberLazyListState()
    val lastGroupIndex = groups.lastIndex
    // The tail identity that must change when a new page arrives. `loadMore()` coalesces adjacent same-section
    // results, so a page can extend the CURRENT last group's hit count WITHOUT adding a new group — keying the
    // re-arm on `(lastGroupIndex, lastGroupHitCount)` restarts the trigger in that case too, so the next page
    // is still requested (round-2 audit Medium).
    val lastGroupHitCount = groups.lastOrNull()?.hits?.size ?: 0

    val matchCount = remember(groups) { groups.sumOf { it.hits.size } }
    // A group's hits are wrapped in the design's tinted rounded container.
    val containerFill = theme.ink.copy(alpha = if (theme.isDark) 0.03f else 0.02f)

    // Append-on-scroll: fire onLoadMore once each time the tail group becomes the last-visible item AND more
    // pages are available. Keyed on (moreAvailable, lastGroupIndex, lastGroupHitCount) so a new page — whether
    // it adds a group OR grows the last one — resets the trigger; `distinctUntilChanged` collapses the burst
    // of layout emissions into one fire per tail; `filter { it }` fires only on the edge into the tail.
    LaunchedEffect(results.moreAvailable, lastGroupIndex, lastGroupHitCount, listState) {
        if (!results.moreAvailable || lastGroupIndex < 0) return@LaunchedEffect
        snapshotFlow {
            // The tail is reached once the last group's container is the last laid-out item.
            listState.layoutInfo.visibleItemsInfo.lastOrNull()?.key == "group-$lastGroupIndex"
        }
            .distinctUntilChanged()
            .filter { it }
            .collect { onLoadMore() }
    }

    LazyColumn(
        state = listState,
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(max = 560.dp)
            .padding(horizontal = 12.dp, vertical = 8.dp)
            .testTag("inbook-results"),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        // The design's overall summary line above the groups.
        item(key = "summary") {
            InBookResultsSummary(theme = theme, matchCount = matchCount, chapterCount = groups.size)
        }
        groups.forEachIndexed { gi, group ->
            // One LazyColumn item per group (header + its tinted-container of hit rows), so the append-on-
            // scroll trigger can key on the tail group container `group-$lastGroupIndex`.
            item(key = "group-$gi") {
                Column(Modifier.fillMaxWidth()) {
                    InBookGroupHeader(theme = theme, group = group, groupIndex = gi)
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(containerFill),
                    ) {
                        group.hits.forEachIndexed { hi, hit ->
                            InBookHitRow(
                                theme = theme,
                                hit = hit,
                                groupIndex = gi,
                                hitIndex = hi,
                                showTopSeparator = hi > 0,
                                // Dismiss-on-success: dismiss ONLY when the jump reports Succeeded.
                                onClick = { if (onJump(hit) == JumpResult.Succeeded) onDismiss() },
                            )
                        }
                    }
                }
            }
        }
    }
}

/** The Idle body — the design's Recent list. Renders a [InBookRecentRow] per recent (nothing when empty; no
 *  invented "no recents" chrome — rule 51). Tapping a recent fills the query via [onPickRecent]. */
@Composable
private fun RecentsBody(theme: ReaderTheme, recents: List<String>, onPickRecent: (String) -> Unit) {
    if (recents.isEmpty()) {
        Box(Modifier.testTag("inbook-idle-empty"))
        return
    }
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .testTag("inbook-recents"),
    ) {
        Text(
            "Recent",
            modifier = Modifier.padding(horizontal = 4.dp, vertical = 6.dp),
            color = theme.ink.copy(alpha = 0.55f),
            fontFamily = VReaderFonts.Sans,
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
        )
        recents.forEachIndexed { index, text ->
            InBookRecentRow(
                theme = theme,
                text = text,
                index = index,
                showBottomSeparator = index < recents.lastIndex,
                onPick = onPickRecent,
            )
        }
    }
}
