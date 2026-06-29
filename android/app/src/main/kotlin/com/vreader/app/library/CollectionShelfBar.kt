// Purpose: the collections shelf-bar over the library grid — feature #127 WI-3 (#110 Phase 3).
// A Compose recreation of the committed design `vreader-library-android.jsx` CollectionBar: a
// horizontal scrolling chip row of "All" + each user collection; the active chip is ink-filled
// with the page-bg text + bold, inactive chips are a faint ink tint. Tapping a chip selects it
// (null = "All"); selection filters the grid (the LibraryViewModel membership filter). Pure function
// of (collections, selectedId) + an onSelect callback (rule 50 §4). Shown only when ≥1 collection
// exists; the manage/assign sheets (the create/rename entry points) are WI-4/WI-5.
package com.vreader.app.library

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.data.Collection
import com.vreader.app.ui.theme.VReaderColors
import com.vreader.app.ui.theme.VReaderFonts

/** A null id is the "All" chip (no collection filter). */
@Composable
fun CollectionShelfBar(
    collections: List<Collection>,
    selectedId: String?,
    onSelect: (String?) -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyRow(
        modifier = modifier.testTag("collection-shelf-bar"),
        contentPadding = PaddingValues(start = 18.dp, end = 18.dp),
        horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(8.dp),
    ) {
        item(key = "all") { CollectionChip(label = "All", selected = selectedId == null) { onSelect(null) } }
        items(collections, key = { it.id }) { c ->
            CollectionChip(label = c.name, selected = selectedId == c.id) { onSelect(c.id) }
        }
    }
}

@Composable
private fun CollectionChip(label: String, selected: Boolean, onClick: () -> Unit) {
    Text(
        text = label,
        color = if (selected) VReaderColors.Background else VReaderColors.Ink,
        fontFamily = VReaderFonts.Sans,
        fontSize = 13.5.sp,
        fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium,
        maxLines = 1,
        modifier = Modifier
            .testTag("collection-chip-$label")
            .clip(RoundedCornerShape(100))
            .background(if (selected) VReaderColors.Ink else VReaderColors.Ink.copy(alpha = 0.05f))
            .clickable(onClick = onClick)
            .semantics { this.selected = selected }
            .padding(horizontal = 15.dp, vertical = 8.dp),
    )
}
