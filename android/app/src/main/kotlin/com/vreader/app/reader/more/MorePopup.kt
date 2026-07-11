// Purpose: feature #134 WI-3 — the reader More popover (`vreader-more.jsx` `MorePopover`): an anchored
// top-right popover (width 268, radius 16, a notch pointing at the "..." button) over a list of [MoreRow]
// rows the caller supplies. Renders ONLY the supplied rows — an id with no row is absent (no dead TTS/
// Auto-turn/Bilingual/Export rows; the plan's §more-row-ownership + #129 no-dead-control rule). Action
// rows fire onTap (chevron accessory), Toggle rows reflect `on` + call onToggle (switch accessory),
// Disabled rows are non-interactive with a sub-text. A transparent full-bleed backdrop dismisses on tap.
// Reuses the active [ReaderTheme]'s token map (ink/accent/isDark → the design's ink/sub/rule/surface
// tokens) so it matches the reader chrome. The host renders this inside the More-button anchor slot so
// the popup positions off the button's own layout coordinates (WI-5 wiring). Pure function of state.
package com.vreader.app.reader.more

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupProperties
import com.vreader.app.reader.settings.ReaderTheme

private val POPUP_WIDTH = 268.dp
private val POPUP_RADIUS = 16.dp
private val SWITCH_ON_TRACK = Color(0xFF3A6A5A) // vreader-more.jsx ToggleSwitch on-track.

/**
 * The reader More popover. [rows] are the caller-supplied rows in design order — the popup renders ONLY
 * these (no invented/dead rows). [onDismiss] fires on a backdrop tap. Anchored to the top-trailing edge
 * (under the "..." button in the top chrome) via a [Popup] with [Alignment.TopEnd]. Renders in [theme]'s
 * colors.
 */
@Composable
fun MorePopup(
    theme: ReaderTheme,
    rows: List<MoreRow>,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    // A single Popup that fills the window so the transparent backdrop can catch outside taps, and the
    // popover card is aligned to the top-trailing corner (the design's `top:92 right:14`). Compose flips
    // TopEnd to the leading edge automatically under RTL. `focusable` so the back button dismisses.
    Popup(
        alignment = Alignment.TopEnd,
        onDismissRequest = onDismiss,
        properties = PopupProperties(focusable = true),
    ) {
        Box(
            modifier
                .fillMaxSize()
                .testTag("more-popup"),
        ) {
            // Transparent full-bleed backdrop — a tap outside the card dismisses (the design's dim layer).
            Box(
                Modifier
                    .fillMaxSize()
                    .testTag("more-backdrop")
                    .clickable(onClick = onDismiss)
                    .semantics { contentDescription = "Dismiss menu" },
            )

            // The popover card, offset from the top-trailing corner to sit under the "..." button.
            Surface(
                shape = RoundedCornerShape(POPUP_RADIUS),
                color = surfaceColor(theme),
                shadowElevation = 12.dp,
                tonalElevation = 0.dp,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 8.dp, end = 14.dp)
                    .width(POPUP_WIDTH)
                    .testTag("more-popup-card"),
            ) {
                Column(Modifier.padding(vertical = 6.dp)) {
                    rows.forEach { row -> MoreRowItem(theme, row) }
                }
            }
        }
    }
}

/** The popover's fill color — the design's `#2a2724` (dark) / `#fcf8f0` (light). */
private fun surfaceColor(theme: ReaderTheme): Color =
    if (theme.isDark) Color(0xFF2A2724) else Color(0xFFFCF8F0)

/**
 * One More-menu row, dispatched on the [MoreRow] shape. Layout mirrors `vreader-more.jsx` `Row`: a 28dp
 * rounded icon tile + a label (+ optional sub-text) + a trailing accessory (a switch for [MoreRow.Toggle],
 * a chevron for [MoreRow.Action]/[MoreRow.Disabled]). Renders in [theme]'s tokens. Disabled rows are
 * dimmed + non-interactive.
 */
@Composable
private fun MoreRowItem(theme: ReaderTheme, row: MoreRow) {
    val ink = theme.ink
    val sub = theme.ink.copy(alpha = 0.6f)
    val accent = theme.accent
    val slug = row.id.slug

    when (row) {
        is MoreRow.Action -> RowScaffold(
            testTag = "more-row-$slug",
            icon = row.icon, label = row.label, sub = row.sub,
            ink = ink, sub_ = sub, accent = accent, isDark = theme.isDark,
            enabled = true, onClick = row.onTap,
        ) { ChevronAccessory(sub) }

        is MoreRow.Disabled -> RowScaffold(
            testTag = "more-row-$slug",
            icon = row.icon, label = row.label, sub = row.sub,
            ink = ink, sub_ = accent, accent = accent, isDark = theme.isDark,
            enabled = false, dim = true, subBold = true, onClick = {},
        ) { ChevronAccessory(sub) }

        is MoreRow.Toggle -> RowScaffold(
            testTag = "more-row-$slug",
            icon = row.icon, label = row.label, sub = row.sub,
            ink = ink, sub_ = sub, accent = accent, isDark = theme.isDark,
            enabled = true, active = row.on, onClick = { row.onToggle(!row.on) },
        ) {
            Switch(
                checked = row.on,
                onCheckedChange = { row.onToggle(it) },
                modifier = Modifier.testTag("more-row-toggle-$slug"),
                colors = SwitchDefaults.colors(checkedTrackColor = SWITCH_ON_TRACK),
            )
        }
    }
}

/**
 * The shared row shell: an optional-click wrapper around the icon tile + text block + trailing
 * [accessory]. [enabled]=false makes the row non-interactive (no click action). [dim] applies the
 * design's disabled opacity; [active] tints the icon tile with the accent.
 */
@Composable
private fun RowScaffold(
    testTag: String,
    icon: ImageVector,
    label: String,
    sub: String?,
    ink: Color,
    sub_: Color,
    accent: Color,
    isDark: Boolean,
    enabled: Boolean,
    active: Boolean = false,
    dim: Boolean = false,
    subBold: Boolean = false,
    onClick: () -> Unit,
    accessory: @Composable () -> Unit,
) {
    val base = Modifier
        .fillMaxWidth()
        .testTag(testTag)
        .semantics { contentDescription = label }
    // A disabled row carries no click action (non-interactive, per the design + the test).
    val rowModifier = if (enabled) base.clickable(onClick = onClick) else base
    val contentAlpha = if (dim) 0.55f else 1f

    Row(
        rowModifier.padding(horizontal = 14.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Icon tile — 28dp rounded (radius 8); accent-tinted background when active.
        Box(
            Modifier
                .size(28.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(
                    if (active) accent.copy(alpha = if (isDark) 0.20f else 0.10f)
                    else ink.copy(alpha = if (isDark) 0.05f else 0.04f),
                ),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                icon, contentDescription = null,
                tint = (if (active) accent else ink).copy(alpha = contentAlpha),
                modifier = Modifier.size(15.dp),
            )
        }

        // Text block — label (+ optional sub-text). Takes the remaining width; the accessory follows.
        Column(Modifier.weight(1f)) {
            Text(
                label,
                color = ink.copy(alpha = contentAlpha),
                fontSize = 14.5.sp,
                fontWeight = FontWeight.Medium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (sub != null) {
                Text(
                    sub,
                    color = sub_,
                    fontSize = 11.sp,
                    fontWeight = if (subBold) FontWeight.SemiBold else FontWeight.Normal,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }

        accessory()
    }
}

@Composable
private fun ChevronAccessory(tint: Color) {
    Icon(
        Icons.AutoMirrored.Filled.KeyboardArrowRight,
        contentDescription = null,
        tint = tint,
        modifier = Modifier.size(16.dp),
    )
}

/** A design divider between row groups (0.5dp, the theme rule token, inset 14dp). Kept for host use. */
@Composable
fun MoreMenuDivider(theme: ReaderTheme) {
    Box(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 14.dp, vertical = 4.dp),
    ) {
        Spacer(
            Modifier
                .fillMaxWidth()
                .height(0.5.dp)
                .background(theme.ink.copy(alpha = 0.10f)),
        )
    }
}
