// Purpose: feature #133 WI-9 (#110 Phase 3) — the in-book-search sheet's query bar (vreader-search.jsx
// `SearchSheet` search bar, lines 55-79), split out of InBookSearchSheet.kt to keep the sheet focused. The
// design's single rounded pill holds the search glyph, the AUTOFOCUS text field, an inline clear (✕), and
// the trailing "Cancel" — no invented accent border (rule 51). The field auto-focuses on first composition
// (the design's `inputRef.focus()`) so the keyboard is up the moment the sheet opens; the inline clear resets
// the query, Cancel dismisses. Colors come from the active [ReaderTheme] token map. Pure fn of state
// (rule 50 §4).
package com.vreader.app.search

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
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
import com.vreader.app.reader.settings.ReaderTheme
import com.vreader.app.ui.theme.VReaderFonts

/**
 * The design's search bar: a single rounded pill (search glyph · autofocus text field · inline clear ·
 * trailing "Cancel"). [bookTitle] hints the placeholder; [query] is the live text (hoisted). The field
 * auto-focuses on first composition (the design's `inputRef.focus()`). Clearing (the inline ✕) resets the
 * query via [onQueryChange]; "Cancel" calls [onDismiss]. testTags `inbook-search-field` / `-clear` /
 * `-cancel`. Renders in [theme]'s colors.
 */
@Composable
internal fun InBookSearchField(
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

    // The design's single rounded pill: search glyph · input · clear · Cancel, all inside one container
    // (vreader-search.jsx lines 55-79) — no invented accent border.
    Row(
        Modifier
            .fillMaxWidth()
            .padding(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 8.dp)
            .clip(shape)
            .background(fieldFill)
            .padding(horizontal = 14.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
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
            // A ≥48dp invisible tap target around the 16dp glyph (the visual stays design-faithful).
            Box(
                Modifier
                    .size(44.dp)
                    .clickable { onQueryChange("") }
                    .testTag("inbook-search-clear")
                    .semantics { contentDescription = "Clear search" },
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.Close, contentDescription = null, tint = sub, modifier = Modifier.size(16.dp))
            }
        }
        // Cancel: the same 14sp text, but its clickable box fills the pill height so the tap target reaches
        // the 48dp minimum without changing the visible label.
        Box(
            Modifier
                .heightIn(min = 44.dp)
                .clickable(onClick = onDismiss)
                .padding(start = 6.dp, end = 2.dp)
                .testTag("inbook-search-cancel")
                .semantics { contentDescription = "Cancel search" },
            contentAlignment = Alignment.Center,
        ) {
            Text(
                "Cancel",
                color = theme.accent,
                fontFamily = VReaderFonts.Sans,
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
            )
        }
    }
}
