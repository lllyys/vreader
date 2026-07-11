// Purpose: feature #133 WI-9 (#110 Phase 3) — the in-book-search sheet's non-list body states, split out of
// InBookSearchRows.kt to keep each file focused. [InBookIndexingHint] is the TXT/MD "still building" hint
// (the plan's Indexing state — NOT a false NoResults; the held query re-runs when the index settles), and
// [InBookNoResults] is the design's `NoResults` empty state (a circular tinted search badge + heading +
// guidance copy). Both take the active [ReaderTheme] token map (the same `sub` derivation the rows use).
// Pure functions of state (rule 50 §4).
package com.vreader.app.search

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.reader.settings.ReaderTheme
import com.vreader.app.ui.theme.VReaderFonts

/**
 * The TXT/MD Indexing hint (the design/plan's "still building" state — NOT a false NoResults). The held
 * query re-runs automatically when the index settles; this is the interim reassurance. testTag
 * `inbook-indexing`.
 */
@Composable
fun InBookIndexingHint(theme: ReaderTheme) {
    val ink = theme.ink
    val sub = ink.copy(alpha = 0.55f)
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 96.dp)
            .padding(horizontal = 24.dp, vertical = 24.dp)
            .testTag("inbook-indexing"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            "Indexing this book…",
            color = ink,
            fontFamily = VReaderFonts.Serif,
            fontSize = 15.sp,
            fontWeight = FontWeight.Medium,
        )
        Text(
            "Search will run automatically when it finishes.",
            modifier = Modifier.weight(1f),
            color = sub,
            fontFamily = VReaderFonts.Sans,
            fontSize = 12.sp,
        )
    }
}

/**
 * The `NoResults` empty state (the design's `NoResults`): a circular tinted search badge, the "No matches
 * for "query"" heading, and the approved guidance copy. testTag `inbook-no-results`.
 */
@Composable
fun InBookNoResults(theme: ReaderTheme, query: String) {
    val ink = theme.ink
    val sub = ink.copy(alpha = 0.55f)
    Column(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 200.dp)
            .padding(horizontal = 30.dp, vertical = 48.dp)
            .testTag("inbook-no-results"),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            Modifier
                .padding(bottom = 12.dp)
                .clip(CircleShape)
                .background(ink.copy(alpha = if (theme.isDark) 0.05f else 0.04f))
                .size(44.dp),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                Icons.Filled.Search,
                contentDescription = null,
                tint = sub,
                modifier = Modifier.size(20.dp),
            )
        }
        Text(
            "No matches for “$query”",
            color = ink,
            fontFamily = VReaderFonts.Serif,
            fontSize = 16.sp,
            fontWeight = FontWeight.Medium,
        )
        Text(
            "Try a different spelling or a partial word.",
            modifier = Modifier.padding(top = 8.dp),
            color = sub,
            fontFamily = VReaderFonts.Sans,
            fontSize = 13.sp,
            textAlign = TextAlign.Center,
        )
    }
}
