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
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
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
        SearchField(
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
            is InBookSearchContent.Error -> Unit
            InBookSearchContent.Loading -> Unit
            InBookSearchContent.Unsupported -> Unit
        }
    }
}

/**
 * The design's search bar: a rounded pill (search glyph · autofocus text field · inline clear) + the
 * trailing "Cancel". The field auto-focuses on first composition (the design's `inputRef.focus()`), so the
 * keyboard is up the moment the sheet opens. Clearing (the inline ✕) resets the query via [onQueryChange].
 */
@Composable
private fun SearchField(
    theme: ReaderTheme,
    bookTitle: String,
    query: String,
    onQueryChange: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    val ink = theme.ink
    val sub = ink.copy(alpha = 0.55f)
    val fieldFill = ink.copy(alpha = if (theme.isDark) 0.06f else 0.05f)
    val focusRequester = remember { FocusRequester() }
    val hasQuery = query.isNotEmpty()
    val shape = RoundedCornerShape(12.dp)

    // Autofocus on first composition — the design's `setTimeout(() => inputRef.focus())`.
    LaunchedEffect(Unit) {
        runCatching { focusRequester.requestFocus() }
    }

    Row(
        Modifier
            .fillMaxWidth()
            .padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            Modifier
                .weight(1f)
                .height(42.dp)
                .clip(shape)
                .background(fieldFill)
                .then(if (hasQuery) Modifier.border(1.5.dp, theme.accent, shape) else Modifier)
                .padding(horizontal = 13.dp),
            horizontalArrangement = Arrangement.spacedBy(9.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Filled.Search, contentDescription = null, tint = sub, modifier = Modifier.size(18.dp))
            BasicTextField(
                value = query,
                onValueChange = onQueryChange,
                modifier = Modifier
                    .weight(1f)
                    .focusRequester(focusRequester)
                    .focusable()
                    .testTag("inbook-search-field")
                    .semantics { contentDescription = "Search this book" },
                singleLine = true,
                textStyle = TextStyle(color = ink, fontFamily = VReaderFonts.Sans, fontSize = 15.sp),
                cursorBrush = SolidColor(theme.accent),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                decorationBox = { inner ->
                    if (!hasQuery) {
                        Text(
                            "Search $bookTitle",
                            color = sub,
                            fontFamily = VReaderFonts.Sans,
                            fontSize = 15.sp,
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
                    tint = sub,
                    modifier = Modifier
                        .size(16.dp)
                        .clickable { onQueryChange("") }
                        .testTag("inbook-search-clear"),
                )
            }
        }
        Text(
            "Cancel",
            modifier = Modifier
                .clickable(onClick = onDismiss)
                .padding(vertical = 6.dp)
                .testTag("inbook-search-cancel")
                .semantics { contentDescription = "Cancel search" },
            color = theme.accent,
            fontFamily = VReaderFonts.Sans,
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium,
        )
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

    // Append-on-scroll: fire onLoadMore once each time the tail group becomes the last-visible item AND more
    // pages are available. Keyed on (moreAvailable, lastGroupIndex) so a new page resets the trigger;
    // `distinctUntilChanged` collapses the burst of layout emissions into one fire per tail; `filter { it }`
    // fires only on the edge into the tail (not on the edge back out).
    LaunchedEffect(results.moreAvailable, lastGroupIndex, listState) {
        if (!results.moreAvailable || lastGroupIndex < 0) return@LaunchedEffect
        snapshotFlow {
            val lastKey = listState.layoutInfo.visibleItemsInfo.lastOrNull()?.key
            // The tail is reached once the last group's header (or any of its hits) is the last laid-out item.
            lastKey is String &&
                (lastKey == "header-$lastGroupIndex" || lastKey.startsWith("hit-$lastGroupIndex-"))
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
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        groups.forEachIndexed { gi, group ->
            item(key = "header-$gi") {
                InBookGroupHeader(theme = theme, group = group, groupIndex = gi)
            }
            group.hits.forEachIndexed { hi, hit ->
                item(key = "hit-$gi-$hi") {
                    InBookHitRow(
                        theme = theme,
                        hit = hit,
                        groupIndex = gi,
                        hitIndex = hi,
                        // Dismiss-on-success: dismiss ONLY when the jump reports Succeeded.
                        onClick = { if (onJump(hit) == JumpResult.Succeeded) onDismiss() },
                    )
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
            InBookRecentRow(theme = theme, text = text, index = index, onPick = onPickRecent)
        }
    }
}
