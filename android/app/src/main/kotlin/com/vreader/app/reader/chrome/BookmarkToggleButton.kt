// Purpose: feature #135 WI-5 (#110 Phase 3) — the designed top-bar bookmark toggle
// (vreader-reader.jsx ReaderTopChrome's bookmark <button>). It fills [ReaderTopChrome]'s reserved
// `bookmarkSlot`: a FILLED bookmark icon in the theme accent when the current position IS bookmarked, an
// OUTLINE bookmark icon in the theme ink when it is not — the exact `BookmarkFilled`/`Bookmark` swap the
// JSX depicts. Tapping toggles create/remove ([onToggle]). Renders as an 18dp icon centered in a 48dp
// circular touch target (the a11y minimum + the trailing-cluster contract), with a content-description
// that FLIPS with state ("Remove bookmark" when filled / "Add bookmark" when outline) so accessibility
// announces what the next tap does. Pure function of state + callback (rule 50 §4); the same 48dp/18dp
// touch-target + [ReaderTheme] token map as [ReaderTopChrome]'s ChromeIconButton.
package com.vreader.app.reader.chrome

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.BookmarkBorder
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.vreader.app.reader.settings.ReaderTheme

/**
 * The top-bar bookmark toggle. [isBookmarked] drives the icon: `true` → the FILLED bookmark
 * ([Icons.Filled.Bookmark]) tinted the theme [accent][ReaderTheme.accent]; `false` → the OUTLINE bookmark
 * ([Icons.Filled.BookmarkBorder]) tinted the theme [ink][ReaderTheme.ink] — the design's
 * `BookmarkFilled`/`Bookmark` states. [onToggle] fires on tap (create when unbookmarked, remove when
 * bookmarked). The content-description flips with [isBookmarked] ("Remove bookmark" / "Add bookmark") so
 * screen readers announce the toggle's effect. Renders in [theme]'s colors.
 */
@Composable
fun BookmarkToggleButton(
    theme: ReaderTheme,
    isBookmarked: Boolean,
    onToggle: () -> Unit,
) {
    val icon = if (isBookmarked) Icons.Filled.Bookmark else Icons.Filled.BookmarkBorder
    val tint = if (isBookmarked) theme.accent else theme.ink
    val description = if (isBookmarked) "Remove bookmark" else "Add bookmark"
    Box(
        Modifier
            .size(48.dp)
            .clip(CircleShape)
            .clickable(onClick = onToggle)
            .testTag("chrome-bookmark-toggle")
            .semantics { contentDescription = description },
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(18.dp))
    }
}
