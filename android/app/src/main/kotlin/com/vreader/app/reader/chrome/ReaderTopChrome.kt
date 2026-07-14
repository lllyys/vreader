// Purpose: feature #132 WI-2 (#110 Phase 3) — the designed reader TOP chrome
// (vreader-reader.jsx ReaderTopChrome): a leading "‹ Library" back control (chevron + accent-colored
// "Library" label), a centered italic-serif title (maxLines=1, ellipsized), and a trailing cluster
// (Search / bookmark slot / More). Per the #129 dead-control rule (the LibraryScreen precedent, no dead
// placeholders) each trailing slot renders ONLY when its callback/slot is non-null: Search arrives with
// #133, More with #134, and the bookmark slot is filled by #135 — all via these already-present nullable
// params, no signature change later. Renders in the active [ReaderTheme]'s colors (chrome = the theme
// background + a bottom rule — a local mapping of the design's chrome/rule tokens). The sibling of
// [ReaderBottomChrome]; same token map + conventions. Pure function of state + callbacks.
//
// feature #131 WI-9 — the bilingual pill: [pillSlot] fills the center cluster next to the title
// (vreader-reader.jsx:489 renders `<BilingualPill/>` inline after the title span when bilingual is on).
// A null slot renders nothing (bilingual off / not applicable — the #129 no-dead-control rule); the host
// supplies the WI-7a BilingualPill only while bilingual is enabled.
package com.vreader.app.reader.chrome

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBackIos
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.reader.settings.ReaderTheme
import com.vreader.app.ui.theme.VReaderFonts

/**
 * The reader top chrome. [title] is the book title (italic serif, single-line + ellipsized). [onBack]
 * fires the leading "‹ Library" control. The trailing cluster follows the design order Search → bookmark
 * → More, and each slot appears ONLY when populated: [onSearch] renders the Search icon iff non-null
 * (#133), [bookmarkSlot] is invoked iff non-null (#135's toggle), [onMore] renders the More icon iff
 * non-null (#134). A null slot renders NOTHING — never a dead/disabled control (the #129 rule).
 * Renders in [theme]'s colors.
 *
 * feature #131 WI-9 — [pillSlot] (the WI-7a BilingualPill) renders inline after the title in the center
 * cluster when non-null (bilingual on); a null slot renders nothing (bilingual off — no dead control).
 */
@Composable
fun ReaderTopChrome(
    theme: ReaderTheme,
    title: String,
    onBack: () -> Unit,
    onSearch: (() -> Unit)? = null,
    onMore: (() -> Unit)? = null,
    bookmarkSlot: (@Composable () -> Unit)? = null,
    pillSlot: (@Composable () -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val ink = theme.ink
    val accent = theme.accent
    val rule = theme.ink.copy(alpha = 0.10f)

    Column(
        modifier
            .fillMaxWidth()
            .background(theme.background)
            .testTag("reader-top-chrome"),
    ) {
        // A single Box so the title centers across the FULL bar width (independent of the trailing
        // cluster's size); the leading + trailing controls are OVERLAID at the ends. The title reserves
        // horizontal room for the widest end cluster so it never overlaps the controls.
        Box(
            Modifier.fillMaxWidth().height(52.dp).padding(horizontal = 6.dp),
            contentAlignment = Alignment.Center,
        ) {
            // Centered — italic-serif title, single-line, ellipsized (design: Source Serif 4 italic, nowrap).
            // The horizontal padding reserves room for the widest possible end cluster (the trailing
            // Search+bookmark+More = 3 * 48dp = 144dp) so the title never overlaps the controls. feature
            // #131 WI-9 — when [pillSlot] is non-null the WI-7a BilingualPill sits inline AFTER the title
            // (design vreader-reader.jsx:489); the title takes only the room it needs (weight, ellipsized)
            // so the pill stays adjacent instead of pushed off-center.
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 144.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center,
            ) {
                Text(
                    title,
                    modifier = Modifier.weight(1f, fill = false),
                    color = ink,
                    fontFamily = VReaderFonts.Serif,
                    fontStyle = FontStyle.Italic,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    textAlign = TextAlign.Center,
                )
                if (pillSlot != null) {
                    Box(Modifier.padding(start = 6.dp).testTag("chrome-bilingual-pill-slot")) { pillSlot() }
                }
            }

            // Leading — "‹ Library" back control (accent). ≥48dp touch target via the row height.
            Row(
                Modifier
                    .align(Alignment.CenterStart)
                    .clip(CircleShape)
                    .clickable(onClick = onBack)
                    .height(48.dp)
                    .padding(horizontal = 8.dp)
                    .testTag("chrome-back")
                    .semantics { contentDescription = "Back to library" },
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Icon(
                    Icons.AutoMirrored.Filled.ArrowBackIos,
                    contentDescription = null,
                    tint = accent,
                    modifier = Modifier.size(16.dp),
                )
                Text(
                    "Library",
                    color = accent,
                    fontFamily = VReaderFonts.Sans,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Medium,
                )
            }

            // Trailing cluster — Search / bookmark slot / More (design order). Each present ONLY when
            // populated: null slots render nothing (the #129 dead-control rule).
            Row(
                Modifier.align(Alignment.CenterEnd),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (onSearch != null) {
                    ChromeIconButton(
                        tag = "chrome-search",
                        description = "Search",
                        icon = Icons.Filled.Search,
                        tint = ink,
                        onClick = onSearch,
                    )
                }
                if (bookmarkSlot != null) {
                    // The slot itself is host-supplied; the wrapper guarantees a ≥48dp minimum touch
                    // target so the trailing-cluster a11y contract holds regardless of the slot's content.
                    Box(
                        Modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp).testTag("chrome-bookmark-slot"),
                        contentAlignment = Alignment.Center,
                    ) { bookmarkSlot() }
                }
                if (onMore != null) {
                    ChromeIconButton(
                        tag = "chrome-more",
                        description = "More",
                        icon = Icons.Filled.MoreVert,
                        tint = ink,
                        onClick = onMore,
                    )
                }
            }
        }

        // Bottom rule — the design's chrome divider.
        Box(Modifier.fillMaxWidth().height(0.5.dp).background(rule))
    }
}

/**
 * A 48dp-minimum tappable icon control: an 18dp icon centered in a 48dp circular touch target (the
 * a11y minimum), with the [description] on the tappable node so accessibility + tests target it.
 */
@Composable
private fun ChromeIconButton(
    tag: String,
    description: String,
    icon: ImageVector,
    tint: Color,
    onClick: () -> Unit,
) {
    Box(
        Modifier
            .size(48.dp)
            .clip(CircleShape)
            .clickable(onClick = onClick)
            .testTag(tag)
            .semantics { contentDescription = description },
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(18.dp))
    }
}
