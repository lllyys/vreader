// Purpose: feature #131 WI-9 — the reader More-menu row assembly, split out of ReaderChromeScaffold.kt to
// keep that file under the ~300-line bar (rule 50 §9). [readerMoreRows] builds the [MoreRow] list the WI-3
// [MorePopup] renders — #134's Details + Share rows, plus (when supplied) #131's Bilingual row modelled by
// [BilingualMoreRow]. The design (`vreader-more.jsx`) drives every treatment: a configured Bilingual row is
// a Toggle; an unconfigured one is the design's NON-interactive Disabled "Configure AI provider first" row.
// Pure (no Compose runtime beyond the Material icon refs).
// @coordinates-with: ReaderChromeScaffold.kt (the caller), EpubReaderChrome.kt (the EPUB caller),
//   reader/more/MoreRow.kt (the row model), dev-docs/designs/vreader-fidelity-v1/project/vreader-more.jsx
package com.vreader.app.reader.chrome

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Translate
import com.vreader.app.reader.more.MoreActionId
import com.vreader.app.reader.more.MoreRow

/**
 * feature #134 WI-5 — the reader More-menu rows the scaffold + the EPUB chrome feed to the WI-3
 * [MorePopup]. #134 owns the Details + Share rows (the design's `vreader-more.jsx` `Book details` /
 * `Share book` actions). feature #131 WI-9 owns the Bilingual row: it is supplied ONLY when [bilingual]
 * is non-null, mirroring the design's conditional (`vreader-more.jsx:91–102`) — a [BilingualMoreRow.Ready]
 * (AI configured) renders `MoreRow.Toggle(BILINGUAL, on=…, sub="English ↔ <lang>" | "Translate inline")`,
 * an [BilingualMoreRow.NeedsConfig] (no AI) renders the design's DISABLED `MoreRow.Disabled("Configure AI
 * provider first")` — non-interactive + informational, EXACTLY as the design renders it (`vreader-more.jsx`
 * makes the disabled row's onClick `undefined`). A null [bilingual] supplies no Bilingual row (the
 * #132/#134-only callers). TTS / Auto-turn / Export remain OTHER features' rows and are never invented here
 * (the §more-row-ownership contract + the #129 no-dead-control rule — the popup renders only the rows it is
 * given). In design order the Bilingual row precedes the Details/Share group. Pure function of its callbacks.
 */
internal fun readerMoreRows(
    onDetails: () -> Unit,
    onShare: () -> Unit,
    bilingual: BilingualMoreRow? = null,
    includeDetailsShare: Boolean = true,
): List<MoreRow> = buildList {
    when (bilingual) {
        null -> Unit
        is BilingualMoreRow.Ready -> add(
            MoreRow.Toggle(
                id = MoreActionId.BILINGUAL,
                label = "Bilingual mode",
                icon = Icons.Filled.Translate,
                sub = if (bilingual.on) "English ↔ ${bilingual.languageKey}" else "Translate inline",
                on = bilingual.on,
                onToggle = bilingual.onToggle,
            ),
        )
        // The design's UNCONFIGURED state: an informational, NON-interactive disabled row (the committed
        // `vreader-more.jsx` renders `onClick={disabled ? undefined : on}` — the disabled row is not
        // tappable). [MorePopup] renders [MoreRow.Disabled] non-clickable, so the onTap is a no-op stub
        // (rule 51 — reproduce the design's non-interactive disabled row, do NOT invent a tappable one).
        is BilingualMoreRow.NeedsConfig -> add(
            MoreRow.Disabled(
                id = MoreActionId.BILINGUAL,
                label = "Bilingual mode",
                icon = Icons.Filled.Translate,
                sub = "Configure AI provider first",
                onTap = {},
            ),
        )
    }
    // The Details + Share rows are #134's; supply them ONLY when the host has a Book-details data source
    // ([includeDetailsShare] = bookDetails != null). A bilingual-only host (or one whose details model has
    // not loaded yet) omits them so the More menu never shows a Book-details row that opens no sheet
    // (Gate-4 Medium-2 — the #129 no-dead-control rule).
    if (includeDetailsShare) {
        add(MoreRow.Action(id = MoreActionId.DETAILS, label = "Book details", icon = Icons.Filled.Info, onTap = onDetails))
        add(MoreRow.Action(id = MoreActionId.SHARE, label = "Share book", icon = Icons.Filled.Share, onTap = onShare))
    }
}

/**
 * feature #131 WI-9 — the host-neutral model for the More-menu Bilingual row (design `vreader-more.jsx`
 * conditional). [Ready] = an AI provider is configured → a [MoreRow.Toggle] reflecting [on] (sub =
 * "English ↔ <lang>" on / "Translate inline" off; toggling routes to the setup sheet — nav model
 * "first toggle on → BilingualSetupSheet"); [NeedsConfig] = no provider → the design's informational
 * DISABLED row (non-interactive). Null (the default in [readerMoreRows]) supplies no Bilingual row —
 * the #132/#134-only callers stay valid.
 */
sealed interface BilingualMoreRow {
    data class Ready(val on: Boolean, val languageKey: String, val onToggle: (Boolean) -> Unit) : BilingualMoreRow
    data object NeedsConfig : BilingualMoreRow
}

/**
 * feature #131 WI-9 — wrap a [BilingualMoreRow.Ready] toggle so it ALSO runs [dismiss] (closing the More
 * popup) before the host's toggle — the popup dismisses the same tap that acts, mirroring the Details/Share
 * rows (`showMore = false; …`). [NeedsConfig] is non-interactive so it is returned unchanged. Pure.
 */
internal fun BilingualMoreRow.dismissingWith(dismiss: () -> Unit): BilingualMoreRow = when (this) {
    is BilingualMoreRow.Ready -> copy(onToggle = { on -> dismiss(); onToggle(on) })
    BilingualMoreRow.NeedsConfig -> this
}
