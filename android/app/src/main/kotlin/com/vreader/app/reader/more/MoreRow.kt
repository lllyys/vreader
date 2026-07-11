// Purpose: feature #134 WI-3 — the reader More-menu ROW model (`vreader-more.jsx` `MorePopover` rows),
// rendered by [MorePopup]. A `sealed interface` so each row carries a stable [MoreActionId] + its own
// callback + (for toggles) its own on/onToggle state. The row's OWNER supplies it: #134 owns only
// DETAILS + SHARE (Action rows); TTS/AUTO_TURN/BILINGUAL ids exist so their owning features (#121/#131/
// a future Auto-turn feature) can supply rows, but a row is NEVER invented here — an id with no supplied
// row is simply absent from the popup (the plan's §more-row-ownership contract; the #129 no-dead-control
// rule). Pure model: an ImageVector icon ref + strings + lambdas, no Compose UI in the type itself.
package com.vreader.app.reader.more

import androidx.compose.ui.graphics.vector.ImageVector

/**
 * A stable identifier for a More-menu row. Used for the row's testTag (`more-row-$id`) and to key row
 * ownership. #134 owns [DETAILS] + [SHARE]; the others exist so their owning features can supply rows —
 * #134 supplies none of them and omits any id it is not given a row for. There is deliberately NO
 * `EXPORT` id: Android has no annotation-export subsystem, so the Export row is never rendered (the
 * plan's scoped-out invariant), and absence-by-omission is enforced by there being no id to supply.
 */
enum class MoreActionId {
    DETAILS,
    SHARE,
    TTS,
    AUTO_TURN,
    BILINGUAL,
}

/** The lowercase stable slug for this id — the testTag / route suffix (e.g. `AUTO_TURN` → `auto_turn`). */
val MoreActionId.slug: String
    get() = name.lowercase()

/**
 * A single More-menu row. Exactly one of three shapes, mirroring the design's three row treatments:
 *  - [Action]   — a tap row with a trailing chevron (`vreader-more.jsx` `onAction`).
 *  - [Toggle]   — a stateful row with a trailing switch reflecting [Toggle.on] (`onToggle`).
 *  - [Disabled] — the design's disabled state (e.g. Bilingual "Configure AI provider first"):
 *                 non-interactive, dimmed, shows its [Disabled.sub].
 *
 * Every row carries a stable [id] (its testTag key) and its own callback. The OWNER of a row's behavior
 * is the feature that supplies it — never [MorePopup] itself.
 */
sealed interface MoreRow {
    val id: MoreActionId
    val label: String
    val icon: ImageVector

    /** A tap row: fires [onTap]; renders a trailing chevron accessory. */
    data class Action(
        override val id: MoreActionId,
        override val label: String,
        override val icon: ImageVector,
        val sub: String? = null,
        val onTap: () -> Unit,
    ) : MoreRow

    /** A toggle row: the trailing switch reflects [on]; tapping the row calls [onToggle] with `!on`. */
    data class Toggle(
        override val id: MoreActionId,
        override val label: String,
        override val icon: ImageVector,
        val sub: String? = null,
        val on: Boolean,
        val onToggle: (Boolean) -> Unit,
    ) : MoreRow

    /** A disabled row: non-interactive, dimmed, shows [sub] (the design's "Configure AI provider first"). */
    data class Disabled(
        override val id: MoreActionId,
        override val label: String,
        override val icon: ImageVector,
        val sub: String,
        val onTap: () -> Unit,
    ) : MoreRow
}
