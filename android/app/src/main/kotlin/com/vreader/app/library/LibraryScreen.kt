// Purpose: Library screen — feature #106 WI-8. A Compose recreation of the committed
// design dev-docs/designs/vreader-fidelity-v1/project/vreader-library.jsx (the shared
// visual identity; ADR-0001). Nav bar (settings / search / grid-list toggle / import),
// serif "Library" title + count, filter chips, grid/list of books, empty state. Pure
// function of LibraryUiState + event callbacks (unidirectional data flow, rule 50 §4).
// Data-limited fields (cover art, author, genre tags, progress) degrade gracefully per
// the design's branches until that metadata is extracted (Phase 3).
package com.vreader.app.library

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ViewList
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.ui.theme.VReaderColors
import com.vreader.app.ui.theme.VReaderFonts

private enum class LibraryView { Grid, List }

@Composable
fun LibraryScreen(
    state: LibraryUiState,
    onOpenBook: (LibraryBook) -> Unit,
    onImport: () -> Unit,
) {
    // Boolean (not the enum) so rememberSaveable persists the mode across rotation /
    // process recreation without a custom Saver.
    var isGrid by rememberSaveable { mutableStateOf(true) }
    val view = if (isGrid) LibraryView.Grid else LibraryView.List

    Column(
        Modifier.fillMaxSize().background(VReaderColors.Background).systemBarsPadding(),
    ) {
        // Nav bar — the functional controls (view-toggle / import). The design's
        // settings + search pills are added when those features land (separate WIs);
        // shipping non-functional controls is a fidelity defect, so they're omitted now.
        Row(
            Modifier.fillMaxWidth().padding(start = 18.dp, end = 18.dp, top = 6.dp),
            horizontalArrangement = Arrangement.End,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                PillIcon(
                    if (view == LibraryView.Grid) Icons.AutoMirrored.Filled.ViewList else Icons.Filled.GridView,
                    "Toggle view",
                ) { isGrid = !isGrid }
                PillIcon(Icons.Filled.Add, "Import book", onImport)
            }
        }

        // Title + count.
        Text(
            "Library",
            Modifier.padding(start = 22.dp, end = 22.dp, top = 12.dp, bottom = 4.dp),
            color = VReaderColors.Ink,
            fontFamily = VReaderFonts.Serif,
            fontSize = 36.sp,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            "${state.books.size} books · ${state.readingCount} reading",
            Modifier.padding(start = 22.dp, bottom = 16.dp),
            color = VReaderColors.InkMuted,
            fontSize = 13.sp,
        )

        when {
            state.loading -> Unit
            state.books.isEmpty() -> EmptyState(onImport)
            view == LibraryView.Grid -> BookGrid(state.books, onOpenBook)
            else -> BookList(state.books, onOpenBook)
        }
    }
}

@Composable
private fun PillIcon(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    contentDescription: String,
    onClick: () -> Unit,
) {
    Box(
        Modifier.size(36.dp).clip(RoundedCornerShape(18.dp)).background(VReaderColors.PillFill)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription, tint = VReaderColors.IconBrown, modifier = Modifier.size(19.dp))
    }
}

@Composable
private fun BookGrid(books: List<LibraryBook>, onOpen: (LibraryBook) -> Unit) {
    LazyVerticalGrid(
        columns = GridCells.Fixed(3),
        contentPadding = PaddingValues(start = 22.dp, end = 22.dp, bottom = 60.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalArrangement = Arrangement.spacedBy(22.dp),
        modifier = Modifier.fillMaxSize(),
    ) {
        items(books, key = { it.id }) { book ->
            Column(Modifier.clickable { onOpen(book) }, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                FallbackCover(book, Modifier.fillMaxWidth().aspectRatio(104f / 156f), 4.dp)
                Text(
                    book.title,
                    color = VReaderColors.Ink,
                    fontFamily = VReaderFonts.Serif,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 12.5.sp,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
private fun BookList(books: List<LibraryBook>, onOpen: (LibraryBook) -> Unit) {
    LazyVerticalGrid(
        columns = GridCells.Fixed(1),
        contentPadding = PaddingValues(start = 18.dp, end = 18.dp, bottom = 60.dp),
        verticalArrangement = Arrangement.spacedBy(0.dp),
        modifier = Modifier.fillMaxSize(),
    ) {
        items(books, key = { it.id }) { book ->
            Row(
                Modifier.fillMaxWidth().clickable { onOpen(book) }
                    .background(VReaderColors.Surface).padding(14.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                FallbackCover(book, Modifier.size(width = 44.dp, height = 62.dp), 3.dp)
                Column(Modifier.weight(1f)) {
                    Text(
                        book.title,
                        color = VReaderColors.Ink,
                        fontFamily = VReaderFonts.Serif,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 15.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Spacer(Modifier.height(5.dp))
                    FormatChip(book.format)
                }
            }
        }
    }
}

@Composable
private fun FormatChip(format: String) {
    Text(
        format,
        Modifier.clip(RoundedCornerShape(4.dp)).background(VReaderColors.ChipFill)
            .padding(horizontal = 6.dp, vertical = 1.dp),
        color = VReaderColors.InkMuted,
        fontSize = 9.5.sp,
        fontWeight = FontWeight.SemiBold,
    )
}

private val coverTints = listOf(
    Color(0xFF5A4632), Color(0xFF4A5240), Color(0xFF5B3A3A), Color(0xFF3A4A5A), Color(0xFF504030),
)

/** The design's BookCover fallback for art-less books: a tinted block + the title initial. */
@Composable
private fun FallbackCover(book: LibraryBook, modifier: Modifier, radius: androidx.compose.ui.unit.Dp) {
    val tint = coverTints[(book.id.hashCode() and 0x7FFFFFFF) % coverTints.size]
    Box(
        modifier.clip(RoundedCornerShape(radius)).background(tint),
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

@Composable
private fun EmptyState(onImport: () -> Unit) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(
                "No books yet",
                color = VReaderColors.Ink,
                fontFamily = VReaderFonts.Serif,
                fontWeight = FontWeight.SemiBold,
                fontSize = 20.sp,
            )
            Text(
                "Tap + to import an EPUB",
                Modifier.clickable(onClick = onImport),
                color = VReaderColors.Accent,
                fontSize = 14.sp,
            )
        }
    }
}
